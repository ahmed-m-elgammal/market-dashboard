-- Migration 010: Create driver_earnings table
-- P1C-07: Create driver_earnings table

-- =============================================================================
-- DRIVER_EARNINGS TABLE
-- Per-order earnings for drivers. Created by complete-delivery Edge Function.
-- Tracks both the earning amount and payout status for reconciliation.
-- =============================================================================
CREATE TABLE driver_earnings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Driver and order references
  driver_id UUID NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,

  -- Earning breakdown (all in EGP)
  delivery_fee_earned NUMERIC(10,2) NOT NULL CHECK (delivery_fee_earned >= 0),
  platform_fee_deducted NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (platform_fee_deducted >= 0),
  net_earnings NUMERIC(10,2) NOT NULL CHECK (net_earnings >= 0),

  -- Earning calculation
  earnings_pct_used NUMERIC(5,2) NOT NULL,

  -- Cancellation compensation (if order was cancelled after pickup)
  is_cancellation_compensation BOOLEAN NOT NULL DEFAULT FALSE,
  compensation_reason TEXT,

  -- Payout status
  payout_status TEXT NOT NULL DEFAULT 'pending'
    CHECK (payout_status IN ('pending', 'paid', 'failed')),
  paid_at TIMESTAMPTZ,
  payout_method TEXT
    CHECK (payout_method IS NULL OR payout_method IN ('cash', 'bank_transfer', 'wallet')),

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Unique: one earnings record per order per driver
CREATE UNIQUE INDEX idx_driver_earnings_order_driver
  ON driver_earnings(order_id, driver_id);

-- Index: driver's earnings history (earnings screen)
CREATE INDEX idx_driver_earnings_driver_created
  ON driver_earnings(driver_id, created_at DESC);

-- Index: pending payouts (admin reconciliation)
CREATE INDEX idx_driver_earnings_payout_status
  ON driver_earnings(payout_status) WHERE payout_status = 'pending';

-- =============================================================================
-- COMMENTS
-- =============================================================================
COMMENT ON TABLE driver_earnings IS 'Per-order driver earnings. Created by complete-delivery Edge Function. Tracks earning amount and payout status for financial reconciliation.';
COMMENT ON COLUMN driver_earnings.earnings_pct_used IS 'Percentage of delivery fee the driver received, from platform_config.driver_earnings_pct at time of delivery.';
COMMENT ON COLUMN driver_earnings.net_earnings IS 'delivery_fee_earned - platform_fee_deducted. What the driver actually receives.';
COMMENT ON COLUMN driver_earnings.is_cancellation_compensation IS 'True if this earning is from a cancelled order (driver compensation for wasted trip).';
COMMENT ON COLUMN driver_earnings.payout_status IS 'pending=not yet paid out, paid=paid to driver, failed=payout attempt failed.';
