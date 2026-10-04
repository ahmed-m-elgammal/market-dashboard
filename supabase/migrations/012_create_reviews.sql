-- Migration 012: Create reviews table
-- P1D-02: Create reviews table

-- =============================================================================
-- REVIEWS TABLE
-- Customer ratings for both merchants and drivers after order delivery.
-- A single review row can rate both the merchant and the driver for the same order.
-- Triggers update the merchant and driver aggregate ratings.
-- =============================================================================
CREATE TABLE reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Order reference (one review per order)
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,

  -- Customer who wrote the review
  customer_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,

  -- Merchant being reviewed
  merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,

  -- Driver being reviewed (may be NULL if order not yet assigned to driver)
  driver_id UUID REFERENCES drivers(id) ON DELETE SET NULL,

  -- Merchant rating (1-5, required)
  merchant_rating SMALLINT NOT NULL CHECK (merchant_rating BETWEEN 1 AND 5),

  -- Driver rating (1-5, optional if no driver assigned)
  driver_rating SMALLINT CHECK (driver_rating BETWEEN 1 AND 5),

  -- Review comments (bilingual — user writes in their preferred language)
  merchant_comment TEXT,
  driver_comment TEXT,

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- One review per order (enforce at DB level)
CREATE UNIQUE INDEX idx_reviews_order
  ON reviews(order_id);

-- Index: reviews for a merchant (display on merchant page)
CREATE INDEX idx_reviews_merchant_created
  ON reviews(merchant_id, created_at DESC);

-- Index: reviews for a driver (display on driver profile)
CREATE INDEX idx_reviews_driver_created
  ON reviews(driver_id, created_at DESC) WHERE driver_id IS NOT NULL;

-- Index: reviews by a customer (display in order history)
CREATE INDEX idx_reviews_customer
  ON reviews(customer_id, created_at DESC);

-- =============================================================================
-- UPDATE_UPDATED_AT TRIGGER
-- =============================================================================
CREATE TRIGGER set_reviews_updated_at
  BEFORE UPDATE ON reviews
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- =============================================================================
-- COMMENTS
-- =============================================================================
COMMENT ON TABLE reviews IS 'Customer ratings for merchants and drivers. One review per order. Triggers update aggregate ratings on merchants and drivers tables.';
COMMENT ON COLUMN reviews.merchant_rating IS 'Required rating 1-5 for the merchant. 1=terrible, 5=excellent.';
COMMENT ON COLUMN reviews.driver_rating IS 'Optional rating 1-5 for the driver. NULL if no driver was assigned to the order.';
COMMENT ON COLUMN reviews.merchant_comment IS 'Free-text comment about the merchant. Written in user preferred language.';
