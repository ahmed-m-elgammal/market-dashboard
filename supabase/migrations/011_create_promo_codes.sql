-- Migration 011: Create promo_codes table
-- P1D-01: Create promo_codes table

-- =============================================================================
-- PROMO_CODES TABLE
-- Discount codes for customers. Validated server-side only (via validate-promo Edge Function).
-- No direct read access from client — prevents code scraping.
-- =============================================================================
CREATE TABLE promo_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Promo code (uppercase, user-entered)
  code TEXT NOT NULL UNIQUE,

  -- Discount type and value
  discount_type TEXT NOT NULL CHECK (discount_type IN ('percentage', 'flat')),
  discount_value NUMERIC(10,2) NOT NULL CHECK (discount_value > 0),
  max_discount_amount NUMERIC(10,2) NOT NULL DEFAULT 100.00 CHECK (max_discount_amount > 0),

  -- Validity period
  starts_at TIMESTAMPTZ NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,

  -- Usage limits
  max_usage INTEGER NOT NULL DEFAULT 100 CHECK (max_usage > 0),
  current_usage INTEGER NOT NULL DEFAULT 0 CHECK (current_usage >= 0),
  max_usage_per_user INTEGER NOT NULL DEFAULT 1 CHECK (max_usage_per_user > 0),

  -- Conditions
  min_order_amount NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (min_order_amount >= 0),

  -- Scope: which merchants can this promo be used with?
  -- NULL = all merchants, otherwise specific merchant
  merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE,

  -- Scope: which category?
  -- NULL = all categories, otherwise specific category
  category TEXT CHECK (category IS NULL OR category IN ('restaurant', 'pharmacy')),

  -- Bilingual description (for admin UI and potentially customer display)
  description_ar TEXT,
  description_en TEXT,

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index: lookup promo code by code (for validation)
-- The UNIQUE constraint on `code` already creates an index,
-- but we add a partial one for active promos for faster validation
-- NOTE: expires_at check removed from index predicate because NOW() is not
-- immutable. Expiry is validated at query time in the Edge Function.
CREATE INDEX idx_promo_codes_active
  ON promo_codes(code) WHERE is_active = TRUE;

-- Index: find promos by merchant (admin panel)
CREATE INDEX idx_promo_codes_merchant
  ON promo_codes(merchant_id) WHERE merchant_id IS NOT NULL;

-- =============================================================================
-- UPDATE_UPDATED_AT TRIGGER
-- =============================================================================
CREATE TRIGGER set_promo_codes_updated_at
  BEFORE UPDATE ON promo_codes
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- =============================================================================
-- COMMENTS
-- =============================================================================
COMMENT ON TABLE promo_codes IS 'Discount codes. Validated server-side only via validate-promo Edge Function. No direct client read access to prevent code scraping.';
COMMENT ON COLUMN promo_codes.discount_type IS 'percentage=X% off subtotal, flat=fixed EGP amount off subtotal.';
COMMENT ON COLUMN promo_codes.max_discount_amount IS 'Maximum discount cap in EGP. Even if percentage discount exceeds this, the discount is capped.';
COMMENT ON COLUMN promo_codes.max_usage_per_user IS 'How many times a single user can apply this promo.';
COMMENT ON COLUMN promo_codes.merchant_id IS 'If set, promo only valid for this merchant. If NULL, valid for all merchants.';

-- =============================================================================
-- DEFERRED FK: orders.promo_code_id → promo_codes.id
-- This FK was deferred from 008_create_orders.sql because promo_codes
-- didn't exist yet at that point in the migration order.
-- =============================================================================
ALTER TABLE orders
  ADD CONSTRAINT fk_orders_promo_code
  FOREIGN KEY (promo_code_id) REFERENCES promo_codes(id) ON DELETE SET NULL;
