-- Migration 006: Create operating_hours table
-- P1B-03: Create operating_hours table
-- P1B-04: Add UNIQUE(merchant_id, day_of_week) constraint

-- =============================================================================
-- OPERATING_HOURS TABLE
-- Stores per-day open/close times for each merchant.
-- Each merchant has 7 rows (one per day of the week).
-- Used by is_merchant_open() function to determine current open status.
-- =============================================================================
CREATE TABLE operating_hours (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Merchant reference
  merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,

  -- Day of week: 0=Sunday, 1=Monday, ..., 6=Saturday
  day_of_week SMALLINT NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),

  -- Operating times (24h format, e.g., '09:00', '23:30')
  open_time TIME NOT NULL,
  close_time TIME NOT NULL,

  -- Whether this day is a working day (for merchants closed on certain days)
  is_closed BOOLEAN NOT NULL DEFAULT FALSE,

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- P1B-04: UNIQUE CONSTRAINT
-- Each merchant can only have ONE operating hours entry per day.
-- =============================================================================
CREATE UNIQUE INDEX idx_operating_hours_merchant_day
  ON operating_hours(merchant_id, day_of_week);

-- Index for querying by merchant
CREATE INDEX idx_operating_hours_merchant
  ON operating_hours(merchant_id);

-- =============================================================================
-- UPDATE_UPDATED_AT TRIGGER
-- =============================================================================
CREATE TRIGGER set_operating_hours_updated_at
  BEFORE UPDATE ON operating_hours
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- =============================================================================
-- COMMENTS
-- =============================================================================
COMMENT ON TABLE operating_hours IS 'Per-day operating schedule for merchants. Used by is_merchant_open() to determine current open status.';
COMMENT ON COLUMN operating_hours.day_of_week IS '0=Sunday, 1=Monday, 2=Tuesday, 3=Wednesday, 4=Thursday, 5=Friday, 6=Saturday (Egyptian week).';
COMMENT ON COLUMN operating_hours.is_closed IS 'If true, the merchant is closed on this day regardless of open_time/close_time.';
