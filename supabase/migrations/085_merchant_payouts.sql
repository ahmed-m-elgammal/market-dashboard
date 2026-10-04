-- Migration 085: Merchant payouts (S4)
--
-- Implements the S4 track from money-movement-implementation-plan.md (lines
-- 802–1115). Mirrors the S5 driver_settlements pattern (migration 083) so the
-- admin UI and ops workflow can reuse the same shape:
--   1. merchant_payouts table — period-aggregated payout rows per merchant
--   2. merchant_payout_orders junction — links delivered orders to payouts
--      (prevents double-payment — a paid order cannot be re-settled)
--   3. RLS policies (admin-only management; service role bypasses for cron)
--   4. Indexes for the list query + the eligibility scan
--   5. create_merchant_payout(p_merchant_id, p_period_start, p_period_end,
--      p_payout_method) RPC — aggregates eligible delivered orders into a
--      payout row, snapshots merchant_payout_at_settlement per order, returns
--      (payout_id, net_payable, order_count)
--   6. mark_merchant_payout_paid(p_payout_id, p_paid_by, p_payout_reference)
--      RPC — flips status pending → paid (manual ops flow; Paymob disbursement
--      is intentionally NOT wired here — same scope cut as S5)
--   7. ALTER merchants ADD payout_frequency + payout_method + bank/wallet
--      contact columns (per-merchant settlement config)
--   8. State-machine trigger + CHECK constraints (bakes in the §3.1 fix from
--      the gap analysis from day one — no follow-up migration needed)
--
-- Paymob disbursement is intentionally skipped (mirrors S5's scope cut). The
-- admin "mark as paid" flow uses mark_merchant_payout_paid with a manual
-- payout_reference (bank transfer ref / cash handover receipt #).
--
-- Per-order aggregation rule:
--   An order is eligible for a merchant payout when:
--     - status = 'delivered' (terminal success state)
--     - delivered_at IS NOT NULL AND delivered_at in [p_period_start, p_period_end)
--     - merchant_id = p_merchant_id
--     - NOT already linked to any row in merchant_payout_orders
--   The settlement row snapshots:
--     - gross_subtotal = SUM(orders.subtotal)
--     - commission_deducted = SUM(orders.subtotal * orders.merchant_commission_pct / 100)
--     - promo_discount_merchant_share = SUM(orders.discount_amount × merchant's
--       share per funded_by snapshot on the order, captured by migration 079's
--       promo_funded_by + promo_merchant_share_pct columns)
--     - cancellation_adjustment = SUM(orders.merchant_payout for cancelled
--       orders in the same period — already recomputed by cancel_order RPC in
--       migration 082). For simplicity this v1 implementation only aggregates
--       delivered orders; cancellations are already reflected per-order in
--       merchant_payout (S2 fix). The field is reserved for future use.
--     - net_payable = gross_subtotal - commission_deducted - promo_discount_merchant_share
--                     + cancellation_adjustment
--   = the sum of orders.merchant_payout for the same delivered orders, which
--     is the source of truth post-S1+S2.

BEGIN;

-- =============================================================================
-- 1. merchant_payouts table
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.merchant_payouts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE RESTRICT,
  period_start TIMESTAMPTZ NOT NULL,
  period_end TIMESTAMPTZ NOT NULL,
  -- Snapshot at creation time (immutable)
  order_count INTEGER NOT NULL CHECK (order_count >= 0),
  gross_subtotal NUMERIC(10,2) NOT NULL CHECK (gross_subtotal >= 0),
  commission_deducted NUMERIC(10,2) NOT NULL CHECK (commission_deducted >= 0),
  promo_discount_merchant_share NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (promo_discount_merchant_share >= 0),
  cancellation_adjustment NUMERIC(10,2) NOT NULL DEFAULT 0,  -- can be negative
  net_payable NUMERIC(10,2) NOT NULL CHECK (net_payable >= 0),
  -- Status machine: pending → approved → paid (or → failed/cancelled)
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'paid', 'failed', 'cancelled')),
  -- Payment metadata (filled when status → paid)
  paymob_transaction_id TEXT,  -- reserved for future Paymob disbursement wiring
  paid_at TIMESTAMPTZ,
  paid_by UUID,  -- admin user id (references profiles.id; not FK-enforced to allow soft deletes)
  payout_method TEXT CHECK (
    payout_method IS NULL OR payout_method IN ('bank_transfer', 'wallet', 'cash', 'instapay')
  ),
  payout_reference TEXT,  -- bank transfer ref, cash receipt #, wallet tx id, etc.
  -- Audit
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- Each merchant has at most one payout per period (prevents double-payment)
  UNIQUE (merchant_id, period_start, period_end)
);

COMMENT ON TABLE public.merchant_payouts IS 'Period-aggregated merchant payout rows. Each row settles a batch of delivered orders (linked via merchant_payout_orders). Status machine: pending → approved → paid. Paymob disbursement NOT wired — admin marks paid manually via mark_merchant_payout_paid RPC. Mirrors driver_settlements (migration 083).';

COMMENT ON COLUMN public.merchant_payouts.payout_method IS 'Payment channel for this payout. cash = handover (no Paymob), bank_transfer/wallet/instapay = manual ops transfer with payout_reference.';

COMMENT ON COLUMN public.merchant_payouts.payout_reference IS 'Free-text reference for the manual payout (bank transfer ref #, cash receipt #, wallet transaction ID). Required when status=paid (enforced by CHECK constraint + trigger).';

COMMENT ON COLUMN public.merchant_payouts.promo_discount_merchant_share IS 'Total discount absorbed by the merchant across all orders in this payout (per orders.promo_funded_by snapshot — S1). When 0, all promos were platform-funded.';

COMMENT ON COLUMN public.merchant_payouts.cancellation_adjustment IS 'Net adjustment for cancelled orders in the period. v1 implementation: always 0 (cancellations are already reflected per-order in merchant_payout via the S2 fix in migration 081/082). Reserved for future use if finance wants to surface cancellations separately.';

-- =============================================================================
-- 2. merchant_payout_orders junction
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.merchant_payout_orders (
  payout_id UUID NOT NULL REFERENCES public.merchant_payouts(id) ON DELETE CASCADE,
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE RESTRICT,
  -- Snapshot of orders.merchant_payout at settlement time
  merchant_payout_at_settlement NUMERIC(10,2) NOT NULL,
  PRIMARY KEY (payout_id, order_id)
);

COMMENT ON TABLE public.merchant_payout_orders IS 'Junction linking orders rows to the merchant_payouts row that paid them. Prevents double-payment (a paid order cannot be re-settled). The merchant_payout_at_settlement snapshot preserves the amount even if the order row is later edited.';

-- =============================================================================
-- 3. RLS — admin-only management; service role bypasses for cron
-- =============================================================================

ALTER TABLE public.merchant_payouts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_payout_orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage merchant payouts"
  ON public.merchant_payouts FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_sessions
      WHERE admin_id = auth.uid() AND expires_at > NOW()
    )
  );

CREATE POLICY "Admins can view payout orders"
  ON public.merchant_payout_orders FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_sessions
      WHERE admin_id = auth.uid() AND expires_at > NOW()
    )
  );

-- =============================================================================
-- 4. Indexes
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_merchant_payouts_merchant_status
  ON public.merchant_payouts (merchant_id, status);
CREATE INDEX IF NOT EXISTS idx_merchant_payouts_period
  ON public.merchant_payouts (period_start, period_end);
CREATE INDEX IF NOT EXISTS idx_merchant_payouts_status_created
  ON public.merchant_payouts (status, created_at);
CREATE INDEX IF NOT EXISTS idx_merchant_payout_orders_order
  ON public.merchant_payout_orders (order_id);

-- =============================================================================
-- 5. ALTER merchants — add payout config columns
-- =============================================================================
-- Mirrors the drivers.payout_frequency + payout_method additions from
-- migration 083. Bank account fields are included per the S4 plan; the
-- bank_account_number column is plaintext for v1 — encryption will be
-- wired in a follow-up using the migration 027 pattern (national_id
-- encryption). Comment is explicit so the gap is visible.

ALTER TABLE public.merchants
  ADD COLUMN IF NOT EXISTS payout_frequency TEXT NOT NULL DEFAULT 'weekly'
    CHECK (payout_frequency IN ('daily', 'weekly', 'monthly')),
  ADD COLUMN IF NOT EXISTS payout_method TEXT NOT NULL DEFAULT 'bank_transfer'
    CHECK (payout_method IN ('bank_transfer', 'wallet', 'cash', 'instapay')),
  ADD COLUMN IF NOT EXISTS bank_account_holder TEXT,
  ADD COLUMN IF NOT EXISTS bank_account_number TEXT,
  ADD COLUMN IF NOT EXISTS bank_name TEXT,
  ADD COLUMN IF NOT EXISTS wallet_phone TEXT;

COMMENT ON COLUMN public.merchants.payout_frequency IS 'How often the auto-generate-merchant-payouts cron should aggregate this merchants delivered orders into a payout row. daily = every night, weekly = every Sunday 03:00 UTC, monthly = first of month 03:00 UTC.';

COMMENT ON COLUMN public.merchants.payout_method IS 'Default payout channel for this merchant. Used by create_merchant_payout when the admin does not pass an explicit p_payout_method. cash = manual handover; bank_transfer/wallet/instapay = manual ops transfer with payout_reference.';

COMMENT ON COLUMN public.merchants.bank_account_number IS 'Bank account number for payouts. PLAINTEXT in v1 — TODO: encrypt at rest using the migration 027 national_id encryption pattern. Do not expose to non-admin roles (RLS already gates reads to admins).';

-- =============================================================================
-- 6. create_merchant_payout RPC
-- =============================================================================
-- Aggregates a merchant's delivered orders (not already in a payout) for the
-- given period into a new payout row. Snapshots merchant_payout_at_settlement
-- per order. Returns (payout_id, net_payable, order_count).
--
-- Idempotency: raises if a pending/approved payout already exists for the
-- same merchant + overlapping period.
--
-- Raises 'No eligible orders for payout in this period' when the merchant has
-- no delivered orders in the window — the auto-settle EF catches this per-
-- merchant and continues to the next.
--
-- Formula:
--   net_payable = SUM(orders.merchant_payout)
--   gross_subtotal = SUM(orders.subtotal)
--   commission_deducted = SUM(orders.subtotal * COALESCE(orders.merchant_commission_pct, 0) / 100)
--   promo_discount_merchant_share = SUM(
--     CASE orders.promo_funded_by
--       WHEN 'merchant' THEN orders.discount_amount
--       WHEN 'shared' THEN ROUND(orders.discount_amount * COALESCE(orders.promo_merchant_share_pct, 50) / 100, 2)
--       ELSE 0
--     END
--   )
--
-- Note: net_payable is the sum of per-order merchant_payout values (which
-- already account for funded_by + cancellation recompute via S1+S2). The
-- other columns are decomposed for the admin UI breakdown panel.

CREATE OR REPLACE FUNCTION public.create_merchant_payout(
  p_merchant_id UUID,
  p_period_start TIMESTAMPTZ,
  p_period_end TIMESTAMPTZ,
  p_payout_method TEXT DEFAULT 'bank_transfer'
)
RETURNS TABLE (
  payout_id UUID,
  net_payable NUMERIC,
  order_count INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_payout_id UUID;
  v_order_count INTEGER;
  v_gross NUMERIC(10,2);
  v_commission NUMERIC(10,2);
  v_discount_share NUMERIC(10,2);
  v_cancel_adj NUMERIC(10,2);
  v_net NUMERIC(10,2);
BEGIN
  -- Security: service-role only (cron EF + admin API both use service role)
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: create_merchant_payout can only be called by service role.';
  END IF;

  -- Lock the merchant row to prevent concurrent payout creation
  PERFORM 1 FROM public.merchants WHERE id = p_merchant_id FOR UPDATE;

  -- Check no overlapping pending/approved payout exists
  IF EXISTS (
    SELECT 1 FROM public.merchant_payouts
    WHERE merchant_id = p_merchant_id
      AND status IN ('pending', 'approved')
      AND period_start <= p_period_end
      AND period_end >= p_period_start
  ) THEN
    RAISE EXCEPTION 'A pending or approved payout already exists for this period';
  END IF;

  -- Aggregate eligible orders: delivered + in period + not already in a payout
  SELECT
    COUNT(o.id),
    COALESCE(SUM(o.subtotal), 0),
    COALESCE(SUM(o.subtotal * COALESCE(o.merchant_commission_pct, 0) / 100), 0),
    COALESCE(SUM(
      CASE
        WHEN o.promo_funded_by = 'merchant' THEN o.discount_amount
        WHEN o.promo_funded_by = 'shared' THEN
          ROUND(o.discount_amount * COALESCE(o.promo_merchant_share_pct, 50) / 100, 2)
        ELSE 0
      END
    ), 0),
    0  -- v_cancel_adj: cancellations are already reflected per-order in merchant_payout (S2)
  INTO v_order_count, v_gross, v_commission, v_discount_share, v_cancel_adj
  FROM public.orders o
  WHERE o.merchant_id = p_merchant_id
    AND o.status = 'delivered'
    AND o.delivered_at IS NOT NULL
    AND o.delivered_at >= p_period_start
    AND o.delivered_at < p_period_end
    AND NOT EXISTS (
      SELECT 1 FROM public.merchant_payout_orders mpo WHERE mpo.order_id = o.id
    );

  IF v_order_count = 0 THEN
    RAISE EXCEPTION 'No eligible orders for payout in this period';
  END IF;

  -- net_payable = sum of per-order merchant_payout (already correct post-S1+S2)
  SELECT COALESCE(SUM(o.merchant_payout), 0)
    INTO v_net
  FROM public.orders o
  WHERE o.merchant_id = p_merchant_id
    AND o.status = 'delivered'
    AND o.delivered_at IS NOT NULL
    AND o.delivered_at >= p_period_start
    AND o.delivered_at < p_period_end
    AND NOT EXISTS (
      SELECT 1 FROM public.merchant_payout_orders mpo WHERE mpo.order_id = o.id
    );

  IF v_net < 0 THEN
    v_net := 0;
  END IF;

  INSERT INTO public.merchant_payouts (
    merchant_id, period_start, period_end,
    order_count, gross_subtotal, commission_deducted,
    promo_discount_merchant_share, cancellation_adjustment,
    net_payable, status, payout_method
  ) VALUES (
    p_merchant_id, p_period_start, p_period_end,
    v_order_count, v_gross, v_commission,
    v_discount_share, v_cancel_adj,
    v_net, 'pending', p_payout_method
  )
  RETURNING id INTO v_payout_id;

  -- Link orders to the payout (snapshot merchant_payout at settlement)
  INSERT INTO public.merchant_payout_orders (payout_id, order_id, merchant_payout_at_settlement)
    SELECT v_payout_id, o.id, o.merchant_payout
    FROM public.orders o
    WHERE o.merchant_id = p_merchant_id
      AND o.status = 'delivered'
      AND o.delivered_at IS NOT NULL
      AND o.delivered_at >= p_period_start
      AND o.delivered_at < p_period_end
      AND NOT EXISTS (
        SELECT 1 FROM public.merchant_payout_orders mpo WHERE mpo.order_id = o.id
      );

  RETURN QUERY SELECT v_payout_id, v_net, v_order_count;
END;
$$;

COMMENT ON FUNCTION public.create_merchant_payout(UUID, TIMESTAMPTZ, TIMESTAMPTZ, TEXT) IS 'Aggregates a merchants delivered orders for the period into a payout row, snapshots merchant_payout per order, returns (payout_id, net_payable, order_count). Idempotency: raises on overlapping pending/approved payout. SECURITY DEFINER — service role only. Mirrors create_driver_settlement (migration 083).';

REVOKE ALL ON FUNCTION public.create_merchant_payout(UUID, TIMESTAMPTZ, TIMESTAMPTZ, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_merchant_payout(UUID, TIMESTAMPTZ, TIMESTAMPTZ, TEXT) TO service_role;

-- =============================================================================
-- 7. mark_merchant_payout_paid RPC
-- =============================================================================
-- Manual mark-as-paid flow (no Paymob disbursement, mirrors S5). Admin passes
-- a payout_reference (bank transfer ref, cash receipt #, etc.). Idempotent:
-- no-op if the payout is already paid.
--
-- Defense-in-depth (gap-analysis §3.2): validates payout_reference is non-
-- empty BEFORE updating the row. The admin API route also validates via Zod,
-- but the RPC is the authoritative validator since it can be called from
-- other contexts (SQL session, future internal tools).

CREATE OR REPLACE FUNCTION public.mark_merchant_payout_paid(
  p_payout_id UUID,
  p_paid_by UUID,
  p_payout_reference TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: mark_merchant_payout_paid can only be called by service role.';
  END IF;

  -- Defense-in-depth: payout_reference must be non-empty (gap-analysis §3.2).
  IF p_payout_reference IS NULL OR trim(p_payout_reference) = '' THEN
    RAISE EXCEPTION 'payout_reference is required to mark a payout paid'
      USING ERRCODE = 'not_null_violation';
  END IF;

  UPDATE public.merchant_payouts
    SET
      status = 'paid',
      paid_at = NOW(),
      paid_by = p_paid_by,
      payout_reference = p_payout_reference,
      updated_at = NOW()
    WHERE id = p_payout_id AND status IN ('pending', 'approved');
END;
$$;

COMMENT ON FUNCTION public.mark_merchant_payout_paid(UUID, UUID, TEXT) IS 'Manually marks a merchant payout as paid. Used when Paymob disbursement is not wired (default) or as a fallback. Idempotent: no-op if already paid. Validates payout_reference is non-empty (defense-in-depth, gap-analysis §3.2). SECURITY DEFINER — service role only.';

REVOKE ALL ON FUNCTION public.mark_merchant_payout_paid(UUID, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_merchant_payout_paid(UUID, UUID, TEXT) TO service_role;

-- =============================================================================
-- 8. updated_at trigger for merchant_payouts
-- =============================================================================
-- Reuse the existing public.update_updated_at_column() function (defined in
-- migration 002 on profiles). The trigger name follows the convention
-- `set_<table>_updated_at` used across the schema.

DROP TRIGGER IF EXISTS set_merchant_payouts_updated_at ON public.merchant_payouts;
CREATE TRIGGER set_merchant_payouts_updated_at
  BEFORE UPDATE ON public.merchant_payouts
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- =============================================================================
-- 9. State-machine enforcement (gap-analysis §3.1 fix baked in from day one)
-- =============================================================================
-- Same pattern as migration 084 (driver_settlements) — CHECK constraints tie
-- status='paid' to payout_method + payout_reference, and a BEFORE UPDATE
-- trigger enforces legal status transitions + payout-field immutability on
-- paid rows. Unlike driver_settlements (which needed a separate migration
-- 084 fix), merchant_payouts gets this from the start.

ALTER TABLE public.merchant_payouts
  ADD CONSTRAINT chk_paid_payout_has_payout_method
  CHECK (status <> 'paid' OR payout_method IS NOT NULL);

ALTER TABLE public.merchant_payouts
  ADD CONSTRAINT chk_paid_payout_has_payout_reference
  CHECK (status <> 'paid' OR payout_reference IS NOT NULL);

COMMENT ON CONSTRAINT chk_paid_payout_has_payout_method ON public.merchant_payouts IS
  'A payout in the paid state MUST have a payout_method recorded. Prevents finance reconciliation gaps (gap-analysis §3.5, baked in from day one).';
COMMENT ON CONSTRAINT chk_paid_payout_has_payout_reference ON public.merchant_payouts IS
  'A payout in the paid state MUST have a payout_reference recorded (bank transfer ref, cash receipt #, etc.).';

CREATE OR REPLACE FUNCTION public.enforce_merchant_payout_transitions()
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
      RAISE EXCEPTION 'Illegal merchant_payouts transition: % → %',
        OLD.status, NEW.status
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  -- Immutability: once paid, payout fields cannot be touched.
  IF OLD.status = 'paid' AND NEW.status = 'paid' THEN
    IF NEW.payout_method         IS DISTINCT FROM OLD.payout_method
    OR NEW.payout_reference      IS DISTINCT FROM OLD.payout_reference
    OR NEW.paymob_transaction_id IS DISTINCT FROM OLD.paymob_transaction_id
    OR NEW.paid_at               IS DISTINCT FROM OLD.paid_at
    OR NEW.paid_by               IS DISTINCT FROM OLD.paid_by THEN
      RAISE EXCEPTION 'Cannot edit payout fields on a paid merchant_payout (id=%)',
        OLD.id
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_merchant_payout_transitions
  ON public.merchant_payouts;
CREATE TRIGGER trg_enforce_merchant_payout_transitions
  BEFORE UPDATE ON public.merchant_payouts
  FOR EACH ROW EXECUTE FUNCTION public.enforce_merchant_payout_transitions();

COMMENT ON FUNCTION public.enforce_merchant_payout_transitions() IS
  'Enforces the merchant_payouts state machine (pending → approved → paid; cancelled/failed terminal) and payout-field immutability on paid rows. Baked in from day one (mirrors migration 084 for driver_settlements).';

COMMIT;
