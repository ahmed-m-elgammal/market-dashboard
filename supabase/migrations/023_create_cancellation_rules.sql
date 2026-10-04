-- Migration 023: Add cancellation rules and cancellation config
-- Referenced by 23-ORDER-CANCELLATION.md
-- Adds cancellation_rules table for configurable cancellation policy per status/initiator.
-- Also adds cancellation-related platform_config entries.

-- =============================================================================
-- CANCELLATION_RULES TABLE
-- Configurable cancellation policy per order status and initiator.
-- Determines who can cancel, refund percentage, cancellation fee, and driver compensation.
-- Editable from admin panel without code changes.
-- =============================================================================
CREATE TABLE cancellation_rules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Which order status this rule applies to
  order_status TEXT NOT NULL
    CHECK (order_status IN ('pending', 'confirmed', 'preparing', 'ready', 'picked_up', 'on_the_way', 'delivered')),

  -- Who is initiating the cancellation
  initiator TEXT NOT NULL CHECK (initiator IN ('customer', 'driver', 'admin', 'system')),

  -- Can this initiator cancel at this status?
  can_cancel BOOLEAN NOT NULL DEFAULT FALSE,

  -- Refund percentage (0-100)
  refund_percentage NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK (refund_percentage BETWEEN 0 AND 100),

  -- Cancellation fee charged to customer
  cancellation_fee_percentage NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK (cancellation_fee_percentage BETWEEN 0 AND 100),
  cancellation_fee_min NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (cancellation_fee_min >= 0),

  -- Driver compensation for wasted trip
  driver_compensation NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (driver_compensation >= 0),

  -- Whether a reason is required
  requires_reason BOOLEAN NOT NULL DEFAULT FALSE,

  -- Whether admin approval is required
  requires_admin_approval BOOLEAN NOT NULL DEFAULT FALSE,

  -- Timestamps
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_by UUID REFERENCES profiles(id)
);

-- Unique: one rule per (order_status, initiator) combination
CREATE UNIQUE INDEX idx_cancellation_rules_status_initiator
  ON cancellation_rules(order_status, initiator);

-- =============================================================================
-- SEED DEFAULT CANCELLATION RULES
-- Based on the cancellation matrix in 23-ORDER-CANCELLATION.md
-- =============================================================================
INSERT INTO cancellation_rules (order_status, initiator, can_cancel, refund_percentage, cancellation_fee_percentage, cancellation_fee_min, driver_compensation, requires_reason) VALUES
  -- Pending: customer and admin can cancel freely
  ('pending', 'customer', TRUE, 100, 0, 0, 0, FALSE),
  ('pending', 'admin', TRUE, 100, 0, 0, 0, FALSE),
  ('pending', 'system', TRUE, 100, 0, 0, 0, FALSE),

  -- Confirmed: customer can cancel (full refund), driver may be assigned
  ('confirmed', 'customer', TRUE, 100, 0, 0, 5, TRUE),
  ('confirmed', 'admin', TRUE, 100, 0, 0, 5, FALSE),
  ('confirmed', 'system', TRUE, 100, 0, 0, 5, FALSE),

  -- Preparing: customer partial refund, cancellation fee applies
  ('preparing', 'customer', TRUE, 50, 50, 10, 5, TRUE),
  ('preparing', 'admin', TRUE, 100, 0, 0, 5, FALSE),
  ('preparing', 'driver', TRUE, 100, 0, 0, 5, TRUE),

  -- Ready: customer partial refund, higher cancellation fee
  ('ready', 'customer', TRUE, 25, 75, 10, 5, TRUE),
  ('ready', 'admin', TRUE, 100, 0, 0, 5, FALSE),
  ('ready', 'driver', TRUE, 100, 0, 0, 10, TRUE),

  -- Picked up: customer cannot cancel, driver can with reason
  ('picked_up', 'customer', FALSE, 0, 100, 0, 0, FALSE),
  ('picked_up', 'admin', TRUE, 100, 0, 0, 10, TRUE),
  ('picked_up', 'driver', TRUE, 100, 0, 0, 10, TRUE),

  -- On the way: same as picked up
  ('on_the_way', 'customer', FALSE, 0, 100, 0, 0, FALSE),
  ('on_the_way', 'admin', TRUE, 100, 0, 0, 10, TRUE),
  ('on_the_way', 'driver', TRUE, 100, 0, 0, 10, TRUE),

  -- Delivered: no customer/driver cancellation, admin can issue refund
  ('delivered', 'customer', FALSE, 0, 100, 0, 0, FALSE),
  ('delivered', 'admin', TRUE, 100, 0, 0, 0, TRUE),
  ('delivered', 'driver', FALSE, 0, 100, 0, 0, FALSE);

-- =============================================================================
-- ADD CANCELLATION-RELATED PLATFORM CONFIG ENTRIES
-- =============================================================================
INSERT INTO platform_config (key, value, description, value_type) VALUES
  ('auto_cancel_pending_minutes', '15', 'Minutes before pending order (no merchant confirm) is auto-cancelled', 'number'),
  ('auto_cancel_no_driver_minutes', '30', 'Minutes before confirmed order (no driver assigned) is auto-cancelled', 'number'),
  ('auto_cancel_payment_timeout_minutes', '10', 'Minutes before pending payment order is auto-cancelled', 'number'),
  ('auto_cancel_ready_timeout_minutes', '60', 'Minutes before ready order (no pickup) is auto-cancelled', 'number'),
  ('cancellation_fee_preparing_pct', '50', 'Cancellation fee percentage when order is preparing', 'number'),
  ('cancellation_fee_ready_pct', '75', 'Cancellation fee percentage when order is ready', 'number'),
  ('cancellation_fee_min', '10', 'Minimum cancellation fee in EGP', 'number'),
  ('cancelled_order_compensation', '5', 'Driver compensation for cancelled order in EGP', 'number');

-- =============================================================================
-- COMMENTS
-- =============================================================================
COMMENT ON TABLE cancellation_rules IS 'Configurable cancellation policy per order status and initiator. Determines who can cancel, refund %, cancellation fee, and driver compensation. Editable from admin panel.';
COMMENT ON COLUMN cancellation_rules.refund_percentage IS 'Percentage of total refunded to customer. 100=full refund, 0=no refund.';
COMMENT ON COLUMN cancellation_rules.cancellation_fee_percentage IS 'Percentage of subtotal charged as cancellation fee to customer.';
COMMENT ON COLUMN cancellation_rules.cancellation_fee_min IS 'Minimum cancellation fee in EGP, even if percentage calculation is lower.';
COMMENT ON COLUMN cancellation_rules.driver_compensation IS 'Fixed EGP amount paid to driver for wasted trip when order is cancelled.';

-- Enable RLS
ALTER TABLE public.cancellation_rules ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "cancellation_rules_read"
  ON public.cancellation_rules
  FOR SELECT
  USING (auth.role() = 'authenticated');
