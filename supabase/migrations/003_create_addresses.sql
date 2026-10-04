-- Migration 003: Create addresses table
-- P1A-07: Create addresses table (saved delivery addresses for users)
-- P1A-08: Add partial unique index (one default address per user)

-- =============================================================================
-- ADDRESSES TABLE
-- Stores saved delivery addresses for each user.
-- Each user can have multiple addresses, but only one default.
-- =============================================================================
CREATE TABLE addresses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Owner
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,

  -- Address details (bilingual)
  label TEXT NOT NULL DEFAULT 'home'
    CHECK (label IN ('home', 'work', 'other')),
  title_ar TEXT,
  title_en TEXT,

  -- Full address string
  address TEXT NOT NULL,
  building_number TEXT,
  floor_number TEXT,
  apartment_number TEXT,
  landmark TEXT,

  -- Location (lat/lng for driver navigation)
  lat NUMERIC(9,6) NOT NULL,
  lng NUMERIC(9,6) NOT NULL,

  -- Geocoded area (for merchant matching by zone)
  city TEXT,
  area TEXT,
  google_place_id TEXT,

  -- Default address flag
  is_default BOOLEAN NOT NULL DEFAULT FALSE,

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for fetching a user's addresses
CREATE INDEX idx_addresses_user_id ON addresses(user_id);

-- Index for finding addresses by city/area
CREATE INDEX idx_addresses_city_area ON addresses(city, area) WHERE city IS NOT NULL;

-- =============================================================================
-- P1A-08: PARTIAL UNIQUE INDEX
-- Ensures only ONE default address per user.
-- Uses partial index: only rows where is_default = TRUE are indexed.
-- =============================================================================
CREATE UNIQUE INDEX idx_addresses_one_default_per_user
  ON addresses(user_id) WHERE is_default = TRUE;

-- =============================================================================
-- UPDATE_UPDATED_AT TRIGGER
-- =============================================================================
CREATE TRIGGER set_addresses_updated_at
  BEFORE UPDATE ON addresses
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- =============================================================================
-- COMMENTS
-- =============================================================================
COMMENT ON TABLE addresses IS 'Saved delivery addresses for users. One default per user enforced by partial unique index.';
COMMENT ON COLUMN addresses.is_default IS 'Only one address per user can be default. Enforced by partial unique index.';
COMMENT ON COLUMN addresses.lat IS 'Latitude for driver navigation and distance calculation.';
COMMENT ON COLUMN addresses.lng IS 'Longitude for driver navigation and distance calculation.';
