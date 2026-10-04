-- Migration 083: Driver settlements (S5)
--
-- Implements the S5 track from money-movement-implementation-plan.md (lines
-- 1118–1371). Adds:
--   1. driver_settlements table — period-aggregated payout rows per driver
--   2. driver_settlement_earnings junction — links earnings rows to settlements
--   3. RLS policies (admin-only — drivers read via mobile service role)
--   4. Indexes for the list query + the eligibility scan
--   5. create_driver_settlement(p_driver_id, p_period_start, p_period_end,
--      p_payout_method) RPC — aggregates pending driver_earnings into a
--      settlement row, marks them paid, returns (settlement_id, net_payable,
--      delivery_count)
--   6. mark_driver_settlement_paid(p_settlement_id, p_paid_by, p_payout_reference)
--      RPC — flips status pending → paid (manual ops flow; Paymob disbursement
--      is intentionally NOT wired here — see money-movement-gap-analysis.md)
--   7. ALTER driver_earnings.payout_method CHECK to add 'instapay' (gap
--      analysis risk #1 — the existing CHECK excluded 'instapay' which would
--      have made the create_driver_settlement RPC fail when p_payout_method='instapay')
--   8. ALTER drivers ADD COLUMN payout_frequency + payout_method (per-driver
--      settlement config — the auto-generate-driver-settlements EF reads
--      these to decide which drivers to settle each night)
--
-- Paymob disbursement is intentionally skipped (user requested). The admin
-- "mark as paid" flow uses mark_driver_settlement_paid with a manual
-- payout_reference (bank transfer ref / cash handover receipt #).

BEGIN;

-- =====================================================================
-- 1. driver_settlements table
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.driver_settlements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id UUID NOT NULL REFERENCES public.drivers(id) ON DELETE RESTRICT,
  period_start TIMESTAMPTZ NOT NULL,
  period_end TIMESTAMPTZ NOT NULL,
  -- Snapshot at creation time (immutable)
  delivery_count INTEGER NOT NULL CHECK (delivery_count >= 0),
  gross_earnings NUMERIC(10,2) NOT NULL CHECK (gross_earnings >= 0),
  platform_fee_deducted NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (platform_fee_deducted >= 0),
  cancellation_compensation NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (cancellation_compensation >= 0),
  net_payable NUMERIC(10,2) NOT NULL CHECK (net_payable >= 0),
  -- Status machine: pending → approved → paid (or → failed/cancelled)
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'paid', 'failed', 'cancelled')),
  -- Payment metadata (filled when status → paid)
  paymob_transaction_id TEXT,
  paid_at TIMESTAMPTZ,
  paid_by UUID, -- admin user id (references profiles.id; not FK-enforced to allow soft deletes)
  payout_method TEXT CHECK (payout_method IS NULL OR payout_method IN ('cash', 'bank_transfer', 'wallet', 'instapay')),
  payout_reference TEXT, -- bank transfer ref, cash receipt #, etc.
  -- Audit
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- Each driver has at most one settlement per period (prevents double-payment)
  UNIQUE (driver_id, period_start, period_end)
);

COMMENT ON TABLE public.driver_settlements IS 'Period-aggregated driver payout rows. Each row settles a batch of driver_earnings (linked via driver_settlement_earnings). Status machine: pending → approved → paid. Paymob disbursement NOT wired — admin marks paid manually via mark_driver_settlement_paid RPC.';

COMMENT ON COLUMN public.driver_settlements.payout_method IS 'Payment channel for this settlement. cash = handover (no Paymob), bank_transfer/wallet/instapay = manual ops transfer with payout_reference.';

COMMENT ON COLUMN public.driver_settlements.payout_reference IS 'Free-text reference for the manual payout (bank transfer ref #, cash receipt #, wallet transaction ID). Required when status=paid.';

-- =====================================================================
-- 2. driver_settlement_earnings junction
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.driver_settlement_earnings (
  settlement_id UUID NOT NULL REFERENCES public.driver_settlements(id) ON DELETE CASCADE,
  earning_id UUID NOT NULL REFERENCES public.driver_earnings(id) ON DELETE RESTRICT,
  -- Snapshot of driver_earnings.net_earnings at settlement time
  net_earnings_at_settlement NUMERIC(10,2) NOT NULL,
  PRIMARY KEY (settlement_id, earning_id)
);

COMMENT ON TABLE public.driver_settlement_earnings IS 'Junction linking driver_earnings rows to the settlement that paid them. Prevents double-payment (a paid earning cannot be re-settled). The net_earnings_at_settlement snapshot preserves the amount even if the earning row is later edited.';

-- =====================================================================
-- 3. RLS — admin-only management; drivers read their own via mobile service
-- =====================================================================

ALTER TABLE public.driver_settlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.driver_settlement_earnings ENABLE ROW LEVEL SECURITY;

-- Admins (via admin_sessions lookup, mirroring the merchant_payouts pattern
-- from the plan) can do anything. Service role bypasses RLS for the cron EF.
CREATE POLICY "Admins can manage driver settlements"
  ON public.driver_settlements FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_sessions
      WHERE admin_id = auth.uid() AND expires_at > NOW()
    )
  );

CREATE POLICY "Admins can view settlement earnings"
  ON public.driver_settlement_earnings FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_sessions
      WHERE admin_id = auth.uid() AND expires_at > NOW()
    )
  );

-- Drivers can read their own settlements (mobile earnings screen). The
-- junction is readable if the parent settlement belongs to the driver.
CREATE POLICY "Drivers can read own settlements"
  ON public.driver_settlements FOR SELECT TO authenticated
  USING (driver_id = auth.uid());

CREATE POLICY "Drivers can read own settlement earnings"
  ON public.driver_settlement_earnings FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.driver_settlements ds
      WHERE ds.id = settlement_id AND ds.driver_id = auth.uid()
    )
  );

-- =====================================================================
-- 4. Indexes
-- =====================================================================

CREATE INDEX IF NOT EXISTS idx_driver_settlements_driver_status
  ON public.driver_settlements (driver_id, status);
CREATE INDEX IF NOT EXISTS idx_driver_settlements_period
  ON public.driver_settlements (period_start, period_end);
CREATE INDEX IF NOT EXISTS idx_driver_settlements_status_created
  ON public.driver_settlements (status, created_at);
CREATE INDEX IF NOT EXISTS idx_driver_settlement_earnings_earning
  ON public.driver_settlement_earnings (earning_id);

-- =====================================================================
-- 5. ALTER driver_earnings.payout_method CHECK to add 'instapay'
-- =====================================================================
-- Gap-analysis risk #1: the existing CHECK (migration 010) excluded
-- 'instapay', which would have made create_driver_settlement fail when
-- p_payout_method='instapay'. Drop + recreate the CHECK to add it.

ALTER TABLE public.driver_earnings DROP CONSTRAINT IF EXISTS driver_earnings_payout_method_check;
ALTER TABLE public.driver_earnings
  ADD CONSTRAINT driver_earnings_payout_method_check
  CHECK (payout_method IS NULL OR payout_method IN ('cash', 'bank_transfer', 'wallet', 'instapay'));

-- =====================================================================
-- 6. ALTER drivers ADD payout_frequency + payout_method columns
-- =====================================================================

ALTER TABLE public.drivers
  ADD COLUMN IF NOT EXISTS payout_frequency TEXT NOT NULL DEFAULT 'weekly'
    CHECK (payout_frequency IN ('daily', 'weekly', 'monthly')),
  ADD COLUMN IF NOT EXISTS payout_method TEXT NOT NULL DEFAULT 'cash'
    CHECK (payout_method IN ('cash', 'bank_transfer', 'wallet', 'instapay'));

COMMENT ON COLUMN public.drivers.payout_frequency IS 'How often the auto-generate-driver-settlements cron should aggregate this drivers pending earnings into a settlement row. daily = every night, weekly = every Sunday 03:30 UTC, monthly = first of month 03:30 UTC.';
COMMENT ON COLUMN public.drivers.payout_method IS 'Default payout channel for this driver. Used by create_driver_settlement when the admin does not pass an explicit p_payout_method. cash = manual handover; bank_transfer/wallet/instapay = manual ops transfer with payout_reference.';

-- =====================================================================
-- 7. create_driver_settlement RPC
-- =====================================================================
-- Aggregates a driver's pending driver_earnings (not already in a settlement)
-- for the given period into a new settlement row. Marks the earnings as
-- 'paid' so they don't get re-settled. Returns the new settlement_id +
-- net_payable + delivery_count.
--
-- Idempotency: raises if a pending/approved settlement already exists for
-- the same driver + overlapping period.
--
-- Raises 'No eligible earnings for settlement in this period' when the
-- driver has no pending earnings in the window — the auto-settle EF catches
-- this per-driver and continues to the next.

CREATE OR REPLACE FUNCTION public.create_driver_settlement(
  p_driver_id UUID,
  p_period_start TIMESTAMPTZ,
  p_period_end TIMESTAMPTZ,
  p_payout_method TEXT DEFAULT 'cash'
)
RETURNS TABLE (
  settlement_id UUID,
  net_payable NUMERIC,
  delivery_count INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_settlement_id UUID;
  v_delivery_count INTEGER;
  v_gross NUMERIC(10,2);
  v_platform_fee NUMERIC(10,2);
  v_cancel_comp NUMERIC(10,2);
  v_net NUMERIC(10,2);
BEGIN
  -- Security: service-role only (cron EF + admin API both use service role)
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: create_driver_settlement can only be called by service role.';
  END IF;

  -- Lock the driver row to prevent concurrent settlement creation
  PERFORM 1 FROM public.drivers WHERE id = p_driver_id FOR UPDATE;

  -- Check no overlapping pending/approved settlement exists
  IF EXISTS (
    SELECT 1 FROM public.driver_settlements
    WHERE driver_id = p_driver_id
      AND status IN ('pending', 'approved')
      AND period_start <= p_period_end
      AND period_end >= p_period_start
  ) THEN
    RAISE EXCEPTION 'A pending or approved settlement already exists for this period';
  END IF;

  -- Aggregate eligible earnings: pending + not already in a settlement +
  -- created in the period window.
  SELECT
    COUNT(de.id),
    COALESCE(SUM(de.delivery_fee_earned), 0),
    COALESCE(SUM(de.platform_fee_deducted), 0),
    COALESCE(SUM(CASE WHEN de.is_cancellation_compensation THEN de.net_earnings ELSE 0 END), 0)
  INTO v_delivery_count, v_gross, v_platform_fee, v_cancel_comp
  FROM public.driver_earnings de
  WHERE de.driver_id = p_driver_id
    AND de.created_at >= p_period_start
    AND de.created_at < p_period_end
    AND de.payout_status = 'pending'
    AND NOT EXISTS (
      SELECT 1 FROM public.driver_settlement_earnings dse WHERE dse.earning_id = de.id
    );

  IF v_delivery_count = 0 THEN
    RAISE EXCEPTION 'No eligible earnings for settlement in this period';
  END IF;

  v_net := v_gross - v_platform_fee + v_cancel_comp;
  IF v_net < 0 THEN
    v_net := 0;
  END IF;

  INSERT INTO public.driver_settlements (
    driver_id, period_start, period_end,
    delivery_count, gross_earnings, platform_fee_deducted,
    cancellation_compensation, net_payable, status, payout_method
  ) VALUES (
    p_driver_id, p_period_start, p_period_end,
    v_delivery_count, v_gross, v_platform_fee,
    v_cancel_comp, v_net, 'pending', p_payout_method
  )
  RETURNING id INTO v_settlement_id;

  -- Link earnings to the settlement (snapshot net_earnings for audit)
  INSERT INTO public.driver_settlement_earnings (settlement_id, earning_id, net_earnings_at_settlement)
    SELECT v_settlement_id, de.id, de.net_earnings
    FROM public.driver_earnings de
    WHERE de.driver_id = p_driver_id
      AND de.created_at >= p_period_start
      AND de.created_at < p_period_end
      AND de.payout_status = 'pending'
      AND NOT EXISTS (
        SELECT 1 FROM public.driver_settlement_earnings dse WHERE dse.earning_id = de.id
      );

  -- Flip the linked earnings to 'paid' so they don't get re-settled
  UPDATE public.driver_earnings
    SET payout_status = 'paid',
        paid_at = NOW(),
        payout_method = p_payout_method
    WHERE id IN (
      SELECT earning_id FROM public.driver_settlement_earnings WHERE settlement_id = v_settlement_id
    );

  RETURN QUERY SELECT v_settlement_id, v_net, v_delivery_count;
END;
$$;

COMMENT ON FUNCTION public.create_driver_settlement(UUID, TIMESTAMPTZ, TIMESTAMPTZ, TEXT) IS 'Aggregates a drivers pending driver_earnings for the period into a settlement row, marks them paid, returns (settlement_id, net_payable, delivery_count). Idempotency: raises on overlapping pending/approved settlement. SECURITY DEFINER — service role only.';

REVOKE ALL ON FUNCTION public.create_driver_settlement(UUID, TIMESTAMPTZ, TIMESTAMPTZ, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_driver_settlement(UUID, TIMESTAMPTZ, TIMESTAMPTZ, TEXT) TO service_role;

-- =====================================================================
-- 8. mark_driver_settlement_paid RPC
-- =====================================================================
-- Manual mark-as-paid flow (no Paymob disbursement). Admin passes a
-- payout_reference (bank transfer ref, cash receipt #, etc.). Idempotent:
-- no-op if the settlement is already paid.

CREATE OR REPLACE FUNCTION public.mark_driver_settlement_paid(
  p_settlement_id UUID,
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
    RAISE EXCEPTION 'Unauthorized: mark_driver_settlement_paid can only be called by service role.';
  END IF;

  UPDATE public.driver_settlements
    SET
      status = 'paid',
      paid_at = NOW(),
      paid_by = p_paid_by,
      payout_reference = p_payout_reference,
      updated_at = NOW()
    WHERE id = p_settlement_id AND status IN ('pending', 'approved');
END;
$$;

COMMENT ON FUNCTION public.mark_driver_settlement_paid(UUID, UUID, TEXT) IS 'Manually marks a driver settlement as paid. Used when Paymob disbursement is not wired (default) or as a fallback. Idempotent: no-op if already paid. SECURITY DEFINER — service role only.';

REVOKE ALL ON FUNCTION public.mark_driver_settlement_paid(UUID, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_driver_settlement_paid(UUID, UUID, TEXT) TO service_role;

-- =====================================================================
-- 9. updated_at trigger for driver_settlements
-- =====================================================================
-- Reuse the existing public.update_updated_at_column() function (defined in
-- migration 002 on profiles). The trigger name follows the convention
-- `set_<table>_updated_at` used across the schema.

DROP TRIGGER IF EXISTS set_driver_settlements_updated_at ON public.driver_settlements;
CREATE TRIGGER set_driver_settlements_updated_at
  BEFORE UPDATE ON public.driver_settlements
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

COMMIT;
