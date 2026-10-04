-- Migration 005: Create merchants table
-- P1B-01: Create merchants table (restaurants, pharmacies)
-- P1B-02: Add city+category+is_active composite index

-- =============================================================================
-- MERCHANTS TABLE
-- Stores vendor (restaurant, pharmacy) information.
-- Each merchant has bilingual names, location, commission settings, and status.
-- =============================================================================
CREATE TABLE merchants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Bilingual names
  name_ar TEXT NOT NULL,
  name_en TEXT NOT NULL,

  -- Category: restaurant or pharmacy
  category TEXT NOT NULL CHECK (category IN ('restaurant', 'pharmacy')),

  -- Images
  logo_url TEXT,
  cover_url TEXT,

  -- Bilingual descriptions
  description_ar TEXT,
  description_en TEXT,

  -- Address
  address TEXT NOT NULL,
  lat NUMERIC(9,6) NOT NULL,
  lng NUMERIC(9,6) NOT NULL,

  -- Location area
  city TEXT NOT NULL,
  area TEXT,

  -- Contact
  phone TEXT NOT NULL,

  -- Status
  is_active BOOLEAN NOT NULL DEFAULT TRUE,

  -- Ratings (updated by trigger)
  rating NUMERIC(2,1) NOT NULL DEFAULT 0.0
    CHECK (rating >= 0 AND rating <= 5),
  rating_count INTEGER NOT NULL DEFAULT 0,

  -- Order settings
  min_order_amount NUMERIC(10,2) NOT NULL DEFAULT 0.00
    CHECK (min_order_amount >= 0),
  estimated_delivery_minutes INTEGER NOT NULL DEFAULT 30
    CHECK (estimated_delivery_minutes > 0),

  -- Delivery fee override (if NULL, use platform_config calculation)
  delivery_fee_override NUMERIC(10,2)
    CHECK (delivery_fee_override IS NULL OR delivery_fee_override >= 0),

  -- Commission (if NULL, use platform_config default)
  commission_pct NUMERIC(5,2)
    CHECK (commission_pct IS NULL OR (commission_pct >= 0 AND commission_pct <= 100)),

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- P1B-02: COMPOSITE INDEX
-- Primary query pattern: filter merchants by city + category + is_active
-- Used by get-merchant-feed edge function for the main feed query.
-- =============================================================================
CREATE INDEX idx_merchants_city_category_active
  ON merchants(city, category, is_active);

-- Index for location-based queries (city + area)
CREATE INDEX idx_merchants_city_area
  ON merchants(city, area) WHERE is_active = TRUE;

-- Index for fetching active merchants (feed query optimization)
CREATE INDEX idx_merchants_active
  ON merchants(is_active) WHERE is_active = TRUE;

-- =============================================================================
-- UPDATE_UPDATED_AT TRIGGER
-- =============================================================================
CREATE TRIGGER set_merchants_updated_at
  BEFORE UPDATE ON merchants
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- =============================================================================
-- COMMENTS
-- =============================================================================
COMMENT ON TABLE merchants IS 'Vendors (restaurants, pharmacies). Core entity for the marketplace.';
COMMENT ON COLUMN merchants.name_ar IS 'Arabic name — displayed when user language is Arabic.';
COMMENT ON COLUMN merchants.name_en IS 'English name — displayed when user language is English.';
COMMENT ON COLUMN merchants.category IS 'restaurant=food delivery, pharmacy=medicine/health delivery.';
COMMENT ON COLUMN merchants.is_active IS 'Inactive merchants are hidden from the feed. Set by admin.';
COMMENT ON COLUMN merchants.rating IS 'Average rating (0.0-5.0). Updated by trigger on reviews INSERT/UPDATE.';
COMMENT ON COLUMN merchants.delivery_fee_override IS 'If set, overrides platform delivery fee calculation for this merchant.';
COMMENT ON COLUMN merchants.commission_pct IS 'Merchant commission percentage. If NULL, uses platform_config.default_commission_pct.';
