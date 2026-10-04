-- Migration 014: Create promoted_slots table
-- P1D-05: Create promoted_slots table

-- =============================================================================
-- PROMOTED_SLOTS TABLE
-- Paid ad placements for merchants in the customer feed.
-- Promoted merchants appear at the top of the feed, clearly marked as "Sponsored".
-- =============================================================================
CREATE TABLE promoted_slots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Merchant being promoted
  merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,

  -- Slot type (where in the feed the ad appears)
  slot_type TEXT NOT NULL DEFAULT 'feed_top'
    CHECK (slot_type IN ('feed_top', 'feed_category', 'search_result', 'banner')),

  -- Schedule
  starts_at TIMESTAMPTZ NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,

  -- Targeting
  city TEXT NOT NULL DEFAULT 'Cairo',
  category TEXT CHECK (category IS NULL OR category IN ('restaurant', 'pharmacy')),

  -- Bilingual ad copy (optional — if NULL, uses merchant name)
  title_ar TEXT,
  title_en TEXT,
  subtitle_ar TEXT,
  subtitle_en TEXT,

  -- Ad creative image (stored in ad-creatives bucket)
  image_url TEXT,

  -- Status
  is_active BOOLEAN NOT NULL DEFAULT TRUE,

  -- Pricing (what the merchant paid)
  price_paid NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (price_paid >= 0),

  -- Performance tracking
  impressions INTEGER NOT NULL DEFAULT 0,
  clicks INTEGER NOT NULL DEFAULT 0,

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index: find active promoted slots for a city (feed injection)
CREATE INDEX idx_promoted_slots_active_city
  ON promoted_slots(city, slot_type, is_active)
  WHERE is_active = TRUE;

-- Index: find promoted slots by merchant (admin panel)
CREATE INDEX idx_promoted_slots_merchant
  ON promoted_slots(merchant_id, created_at DESC);

-- =============================================================================
-- UPDATE_UPDATED_AT TRIGGER
-- =============================================================================
CREATE TRIGGER set_promoted_slots_updated_at
  BEFORE UPDATE ON promoted_slots
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- =============================================================================
-- COMMENTS
-- =============================================================================
COMMENT ON TABLE promoted_slots IS 'Paid ad placements for merchants in the customer feed. Promoted merchants appear at top of feed, clearly marked as Sponsored.';
COMMENT ON COLUMN promoted_slots.slot_type IS 'feed_top=top of main feed, feed_category=top of category filter, search_result=promoted in search, banner=hero banner.';
COMMENT ON COLUMN promoted_slots.impressions IS 'Number of times this ad was shown to customers. Updated by get-merchant-feed Edge Function.';
COMMENT ON COLUMN promoted_slots.clicks IS 'Number of times customers tapped on this ad. Updated when customer opens merchant page from promoted slot.';
