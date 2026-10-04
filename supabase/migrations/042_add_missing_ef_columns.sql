-- Migration 042: Add missing columns referenced by Edge Functions
-- Sprint 0.1.1: Five columns are used in Edge Functions but absent from their
-- respective table definitions. This migration adds them with sensible defaults
-- that preserve existing data and match the EF expectations.

-- =============================================================================
-- 1. promo_codes.free_delivery
-- Used by: validate-promo/index.ts (returned in API response)
-- Default: FALSE (most promo codes are discounts, not free delivery)
-- =============================================================================
ALTER TABLE promo_codes ADD COLUMN IF NOT EXISTS free_delivery BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN promo_codes.free_delivery IS 'If TRUE, this promo code grants free delivery regardless of delivery fee calculation.';

-- =============================================================================
-- 2. notifications.reference_id
-- Used by: send-notification, driver-actions, paymob-webhook, place-order,
--          admin-driver (9+ call sites) — links notification to an entity
-- Default: NULL (not all notifications reference an entity)
-- =============================================================================
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS reference_id UUID;

COMMENT ON COLUMN notifications.reference_id IS 'UUID of the related entity (order, driver, user). Used for deep-link navigation on notification tap.';

-- =============================================================================
-- 3. merchants.delivery_radius_km
-- Used by: get-order-fee-preview, place-order, get-merchant-feed
-- Default: 10 km (reasonable default for Cairo/Giza urban delivery)
-- Constraint: Must be positive
-- =============================================================================
ALTER TABLE merchants ADD COLUMN IF NOT EXISTS delivery_radius_km NUMERIC(5,2) NOT NULL DEFAULT 10.00
  CHECK (delivery_radius_km > 0);

COMMENT ON COLUMN merchants.delivery_radius_km IS 'Maximum delivery radius in km. Orders beyond this distance are rejected. Default 10 km.';

-- =============================================================================
-- 4. merchants.estimated_prep_time_minutes
-- Used by: get-merchant-feed (returned in feed response for ETA calculation)
-- Note: merchants already has estimated_delivery_minutes (total delivery time).
--       This column is specifically for kitchen preparation time, used by
--       get-merchant-feed to provide more accurate ETA breakdowns.
-- Default: 30 minutes (conservative default for food prep)
-- Constraint: Must be positive
-- =============================================================================
ALTER TABLE merchants ADD COLUMN IF NOT EXISTS estimated_prep_time_minutes INTEGER NOT NULL DEFAULT 30
  CHECK (estimated_prep_time_minutes > 0);

COMMENT ON COLUMN merchants.estimated_prep_time_minutes IS 'Estimated kitchen preparation time in minutes. Used for ETA calculations. Distinct from estimated_delivery_minutes which includes transit time.';

-- =============================================================================
-- 5. orders.notes
-- Used by: place-order/index.ts, validation.ts, and the place_order_with_items RPC
-- Default: NULL (most orders have no special notes)
-- Note: orders already has admin_notes (internal-only). This column is for
--       customer-facing delivery instructions (e.g., "ring doorbell twice").
-- =============================================================================
ALTER TABLE orders ADD COLUMN IF NOT EXISTS notes TEXT;

COMMENT ON COLUMN orders.notes IS 'Customer-provided delivery instructions or notes for this order. Visible to driver and merchant. Distinct from admin_notes which is internal-only.';

-- =============================================================================
-- INDEXES for new columns
-- =============================================================================
-- reference_id on notifications: enables efficient lookup of all notifications
-- for a specific entity (e.g., all notifications for order X)
CREATE INDEX IF NOT EXISTS idx_notifications_reference_id
  ON notifications(reference_id) WHERE reference_id IS NOT NULL;
