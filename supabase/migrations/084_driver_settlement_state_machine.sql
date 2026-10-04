-- Migration 084: Driver-settlement state-machine enforcement + paid-row immutability
--
-- P0 fix from money-movement-gap-analysis.md §3.1:
-- The PATCH /api/driver-settlements/[id] route previously allowed direct
-- status mutations with no transition check (e.g. `paid → cancelled`,
-- `approved → pending`, or mutating payout_method on a paid row). The
-- linked driver_earnings rows are already flipped to payout_status='paid'
-- by create_driver_settlement (migration 083) — they are NOT rolled back
-- by a settlement cancel. So a `paid → cancelled` PATCH left "paid earnings
-- with no settlement" — a quiet money leak / audit-trail break.
--
-- The API layer now rejects illegal transitions up-front (cleaner UX), but
-- defense-in-depth requires the DB to also enforce the rules. This migration:
--   1. Adds CHECK constraints tying `status` to `payout_method`/`payout_reference`
--      so a paid row MUST record how it was paid (gap-analysis §3.5).
--   2. Adds a trigger `enforce_driver_settlement_transitions` that raises on
--      any illegal status transition (paid → anything, cancelled → anything,
--      approved → pending, etc.) AND on any mutation of payout_method or
--      payout_reference once status='paid'.
--
-- Backward compatibility: existing paid rows that predate the CHECK
-- constraints would fail the new CHECKs if they had NULL payout_method.
-- The migration backfills them defensively (sets payout_method='cash' and
-- payout_reference='legacy-pre-084' on any paid row missing the values)
-- before adding the constraints, so the constraint addition cannot fail.
--
-- Affected callers:
--   - apps/admin/src/app/api/driver-settlements/[id]/route.ts (PATCH) — now
--     also rejects illegal transitions at the API layer for clean 409 UX.
--   - mark_driver_settlement_paid RPC (migration 083) — unaffected, already
--     only transitions pending/approved → paid.

BEGIN;

-- =============================================================================
-- 1. Backfill: ensure every existing paid row has payout_method + payout_reference
-- =============================================================================
-- Defensive: the auto-settle EF always sets payout_method at creation time
-- (migration 083 line 247–251), so paid rows should already have it. But the
-- admin PATCH route (before this fix) could set status='paid' directly with
-- no payout_method — guard against that historical bug by backfilling.
UPDATE public.driver_settlements
  SET payout_method = 'cash'
  WHERE status = 'paid' AND payout_method IS NULL;

UPDATE public.driver_settlements
  SET payout_reference = 'legacy-pre-084'
  WHERE status = 'paid' AND payout_reference IS NULL;

-- =============================================================================
-- 2. CHECK constraints — paid rows must record how they were paid
-- =============================================================================
-- Gap-analysis §3.5: previously a paid row could have NULL payout_method,
-- which silently broke finance reconciliation joins.
ALTER TABLE public.driver_settlements
  ADD CONSTRAINT chk_paid_settlement_has_payout_method
  CHECK (status <> 'paid' OR payout_method IS NOT NULL);

ALTER TABLE public.driver_settlements
  ADD CONSTRAINT chk_paid_settlement_has_payout_reference
  CHECK (status <> 'paid' OR payout_reference IS NOT NULL);

COMMENT ON CONSTRAINT chk_paid_settlement_has_payout_method ON public.driver_settlements IS
  'A settlement in the paid state MUST have a payout_method recorded. Prevents finance reconciliation gaps. Added by migration 084 (gap-analysis §3.5 + §3.1).';
COMMENT ON CONSTRAINT chk_paid_settlement_has_payout_reference ON public.driver_settlements IS
  'A settlement in the paid state MUST have a payout_reference recorded (bank transfer ref, cash receipt #, etc.). Added by migration 084.';

-- =============================================================================
-- 3. Trigger: enforce the state machine on UPDATE
-- =============================================================================
-- State machine (mirrors the API-layer ALLOWED_TRANSITIONS map):
--   pending  → approved | cancelled
--   approved → cancelled
--   cancelled→ (terminal — no transitions)
--   paid     → (terminal — no transitions; payout fields also immutable)
--   failed   → pending  (retry path — admin can re-queue a failed settlement)
--
-- The trigger fires BEFORE UPDATE and raises `check_violation` on any illegal
-- transition. It also blocks edits to payout_method / payout_reference /
-- paymob_transaction_id / paid_at / paid_by on paid rows (immutability rule).
--
-- NOTE: The mark_driver_settlement_paid RPC (migration 083) is unaffected —
-- it only fires UPDATEs with `WHERE status IN ('pending', 'approved')` and
-- sets status='paid'. That is a legal transition (pending → paid or
-- approved → paid), so the trigger allows it.

CREATE OR REPLACE FUNCTION public.enforce_driver_settlement_transitions()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_legal_targets TEXT[];
BEGIN
  -- Determine the legal target statuses for the OLD row's status.
  v_legal_targets := CASE OLD.status
    WHEN 'pending'  THEN ARRAY['approved', 'cancelled', 'paid']::TEXT[]
    WHEN 'approved' THEN ARRAY['cancelled', 'paid']::TEXT[]
    WHEN 'cancelled' THEN ARRAY[]::TEXT[]
    WHEN 'paid'     THEN ARRAY[]::TEXT[]
    WHEN 'failed'   THEN ARRAY['pending']::TEXT[]
    ELSE ARRAY[]::TEXT[]
  END;

  -- If status is changing, the new status must be in the legal set.
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NOT (NEW.status = ANY(v_legal_targets)) THEN
      RAISE EXCEPTION 'Illegal driver_settlements transition: % → %',
        OLD.status, NEW.status
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  -- Immutability: once paid, payout fields cannot be touched.
  -- This catches the PATCH {payout_reference: 'NEW'} attack on a paid row.
  IF OLD.status = 'paid' AND NEW.status = 'paid' THEN
    IF NEW.payout_method         IS DISTINCT FROM OLD.payout_method
    OR NEW.payout_reference      IS DISTINCT FROM OLD.payout_reference
    OR NEW.paymob_transaction_id IS DISTINCT FROM OLD.paymob_transaction_id
    OR NEW.paid_at               IS DISTINCT FROM OLD.paid_at
    OR NEW.paid_by               IS DISTINCT FROM OLD.paid_by THEN
      RAISE EXCEPTION 'Cannot edit payout fields on a paid driver_settlement (id=%)',
        OLD.id
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_driver_settlement_transitions
  ON public.driver_settlements;
CREATE TRIGGER trg_enforce_driver_settlement_transitions
  BEFORE UPDATE ON public.driver_settlements
  FOR EACH ROW EXECUTE FUNCTION public.enforce_driver_settlement_transitions();

COMMENT ON FUNCTION public.enforce_driver_settlement_transitions() IS
  'Enforces the driver_settlements state machine (pending → approved → paid; cancelled/failed terminal) and payout-field immutability on paid rows. Added by migration 084 (gap-analysis §3.1). The trigger is intentionally permissive about pending → paid (the mark_driver_settlement_paid RPC uses approved → paid but admin can also mark pending → paid directly).';

COMMIT;
