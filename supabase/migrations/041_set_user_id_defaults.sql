-- Migration 041: Set user_id defaults for addresses, favorites and review trigger
-- Gap 12: Set default value for addresses.user_id and favorites.user_id to auth.uid()
-- Gap 13: Create trigger to auto-populate customer_id, merchant_id, driver_id from orders on reviews insert

-- =============================================================================
-- 1. ADDRESSES TABLE: Set user_id default to auth.uid()
-- =============================================================================
ALTER TABLE addresses ALTER COLUMN user_id SET DEFAULT auth.uid();

-- =============================================================================
-- 2. FAVORITES TABLE: Set user_id default to auth.uid()
-- =============================================================================
ALTER TABLE favorites ALTER COLUMN user_id SET DEFAULT auth.uid();

-- =============================================================================
-- 3. REVIEWS TABLE: Trigger to populate customer_id, merchant_id, driver_id from orders
-- =============================================================================

-- Trigger function: lookup order details and populate review foreign keys
CREATE OR REPLACE FUNCTION public.set_review_fields_from_order()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_order RECORD;
BEGIN
  -- Fetch the order details
  SELECT customer_id, merchant_id, driver_id
  INTO v_order
  FROM orders
  WHERE id = NEW.order_id;

  IF v_order.customer_id IS NOT NULL THEN
    NEW.customer_id := v_order.customer_id;
  END IF;

  IF v_order.merchant_id IS NOT NULL THEN
    NEW.merchant_id := v_order.merchant_id;
  END IF;

  IF v_order.driver_id IS NOT NULL THEN
    NEW.driver_id := v_order.driver_id;
  END IF;

  RETURN NEW;
END;
$$;

-- Drop existing trigger if exists (idempotent)
DROP TRIGGER IF EXISTS set_review_fields_from_order ON reviews;

-- Create BEFORE INSERT trigger
CREATE TRIGGER set_review_fields_from_order
  BEFORE INSERT ON reviews
  FOR EACH ROW
  EXECUTE FUNCTION public.set_review_fields_from_order();

-- =============================================================================
-- COMMENTS
-- =============================================================================
COMMENT ON TRIGGER set_review_fields_from_order ON reviews IS 'Automatically populates customer_id, merchant_id, driver_id from the referenced order on INSERT. Allows client to insert review with only order_id and ratings/comments.';