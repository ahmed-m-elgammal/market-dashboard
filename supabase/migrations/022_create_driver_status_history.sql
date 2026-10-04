-- Migration 022: Create driver_status_history table
-- P1C-10: Create driver_status_history table
-- P1C-11: Add index on driver_status_history(driver_id, changed_at DESC)

-- =============================================================================
-- DRIVER_STATUS_HISTORY TABLE (P1C-10)
-- Audit trail for driver status changes (verification, activation, deactivation).
-- Every status change is logged with who made the change and why.
-- =============================================================================
CREATE TABLE driver_status_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Driver reference
  driver_id UUID NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,

  -- Status transition
  previous_status TEXT NOT NULL,
  new_status TEXT NOT NULL,

  -- Who made the change (admin UUID, or 'system' for auto-actions)
  changed_by UUID NOT NULL REFERENCES profiles(id),

  -- Optional reason for the change
  reason TEXT,

  -- Timestamp
  changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- P1C-11: INDEX FOR DRIVER STATUS HISTORY
-- Primary query: get a driver's status history in reverse chronological order.
-- Used by admin panel driver detail page "Status History" tab.
-- =============================================================================
CREATE INDEX idx_driver_status_history_driver
  ON driver_status_history(driver_id, changed_at DESC);

-- =============================================================================
-- COMMENTS
-- =============================================================================
COMMENT ON TABLE driver_status_history IS 'Audit trail for driver lifecycle status changes (verification, activation, deactivation). Every change is logged with who changed what and why.';
COMMENT ON COLUMN driver_status_history.previous_status IS 'Status before the change (e.g., pending, approved, deactivated).';
COMMENT ON COLUMN driver_status_history.new_status IS 'Status after the change (e.g., under_review, approved, deactivated).';
COMMENT ON COLUMN driver_status_history.changed_by IS 'Admin who made the change. References profiles.id.';

-- Enable RLS
ALTER TABLE public.driver_status_history ENABLE ROW LEVEL SECURITY;
