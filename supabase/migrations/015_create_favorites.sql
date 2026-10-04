-- Migration 015: Create favorites table
-- P1D-06: Create favorites table
-- P1D-07: Add UNIQUE(user_id, merchant_id) on favorites

-- =============================================================================
-- FAVORITES TABLE (P1D-06)
-- Customer saved/favorited merchants for quick access.
-- Simple junction table with unique constraint on (user_id, merchant_id).
-- =============================================================================
CREATE TABLE favorites (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Customer who favorited
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,

  -- Merchant who was favorited
  merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,

  -- Timestamp
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- P1D-07: Unique constraint — each user can favorite a merchant only once
  CONSTRAINT unique_user_merchant_favorite UNIQUE (user_id, merchant_id)
);

-- Index: get a user's favorites (favorites tab in app)
CREATE INDEX idx_favorites_user_created
  ON favorites(user_id, created_at DESC);

-- Index: check if a merchant is favorited (for heart icon on merchant card)
CREATE INDEX idx_favorites_merchant
  ON favorites(merchant_id);

-- =============================================================================
-- COMMENTS
-- =============================================================================
COMMENT ON TABLE favorites IS 'Customer favorited merchants. Simple junction table for quick access to preferred merchants.';
COMMENT ON COLUMN favorites.user_id IS 'Customer who favorited the merchant.';
COMMENT ON COLUMN favorites.merchant_id IS 'Merchant who was favorited.';
