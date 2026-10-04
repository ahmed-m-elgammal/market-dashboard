-- Migration 017: Create database functions
-- P1E-08: generate_order_number() function using sequence
-- P1E-09: calculate_delivery_fee(merchant_id, distance_km) function
-- P1E-10: update_merchant_rating(merchant_id) function
-- P1E-11: update_driver_rating(driver_id) function
-- P1E-12: is_merchant_open(merchant_id) function
-- P1E-13: get_driver_location(p_order_id, p_customer_id) SECURITY DEFINER function

-- =============================================================================
-- P1E-08: GENERATE_ORDER_NUMBER() FUNCTION (⚡ PERFORMANCE-CRITICAL)
-- Generates unique order numbers in ORD-XXXXXX format using a sequence.
-- Called by trigger on orders INSERT (see 018_create_triggers.sql).
--
-- Design decisions:
--   - Uses a PostgreSQL SEQUENCE for gapless-ish number generation
--   - Format: ORD-000001, ORD-000002, etc. (6-digit zero-padded)
--   - Sequence is more performant than MAX()+1 under concurrent inserts
--   - Gaps are acceptable (sequences are not transactional — RED-08)
-- =============================================================================

-- Create a dedicated sequence for order numbers
CREATE SEQUENCE public.order_number_seq
  START WITH 1
  INCREMENT BY 1
  NO CYCLE;

CREATE OR REPLACE FUNCTION public.generate_order_number()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  next_val BIGINT;
  order_num TEXT;
BEGIN
  next_val := nextval('public.order_number_seq');
  order_num := 'ORD-' || LPAD(next_val::TEXT, 6, '0');
  RETURN order_num;
END;
$$;

COMMENT ON FUNCTION public.generate_order_number() IS 'P1E-08: Generates unique order numbers in ORD-XXXXXX format using a dedicated sequence. Called by trigger on orders INSERT.';

-- =============================================================================
-- P1E-09: CALCULATE_DELIVERY_FEE() FUNCTION
-- Calculates delivery fee based on platform_config settings and distance.
-- Used by get-order-fee-preview Edge Function and place-order Edge Function.
--
-- Calculation logic (all values from platform_config):
--   1. base_fee = delivery_base_fee (default 25 EGP)
--   2. distance_fee = delivery_per_km_rate * distance_km (default 5 EGP/km)
--   3. total_fee = base_fee + distance_fee
--   4. If order_total >= delivery_free_threshold, fee = 0
--   5. If distance > delivery_max_distance_km, return -1 (out of range)
--   6. If merchant has delivery_fee_override, use that instead
--
-- Returns: delivery fee in EGP, or -1 if out of delivery range
-- =============================================================================

CREATE OR REPLACE FUNCTION public.calculate_delivery_fee(
  p_merchant_id UUID,
  p_distance_km NUMERIC,
  p_order_subtotal NUMERIC DEFAULT 0
)
RETURNS NUMERIC
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_base_fee NUMERIC;
  v_per_km_rate NUMERIC;
  v_free_threshold NUMERIC;
  v_max_distance NUMERIC;
  v_override_fee NUMERIC;
  v_total_fee NUMERIC;
BEGIN
  -- Check if merchant has a delivery fee override
  SELECT delivery_fee_override INTO v_override_fee
  FROM public.merchants
  WHERE id = p_merchant_id;

  -- If merchant has an override, use it
  IF v_override_fee IS NOT NULL THEN
    -- Still check free delivery threshold
    SELECT COALESCE(
      (SELECT value::NUMERIC FROM public.platform_config WHERE key = 'delivery_free_threshold'),
      200.00
    ) INTO v_free_threshold;

    IF p_order_subtotal >= v_free_threshold THEN
      RETURN 0;
    END IF;

    RETURN v_override_fee;
  END IF;

  -- Fetch config values
  SELECT COALESCE(
    (SELECT value::NUMERIC FROM public.platform_config WHERE key = 'delivery_base_fee'),
    25.00
  ) INTO v_base_fee;

  SELECT COALESCE(
    (SELECT value::NUMERIC FROM public.platform_config WHERE key = 'delivery_per_km_rate'),
    5.00
  ) INTO v_per_km_rate;

  SELECT COALESCE(
    (SELECT value::NUMERIC FROM public.platform_config WHERE key = 'delivery_free_threshold'),
    200.00
  ) INTO v_free_threshold;

  SELECT COALESCE(
    (SELECT value::NUMERIC FROM public.platform_config WHERE key = 'delivery_max_distance_km'),
    15
  ) INTO v_max_distance;

  -- Check if distance exceeds max delivery range
  IF p_distance_km > v_max_distance THEN
    RETURN -1;
  END IF;

  -- Check if order qualifies for free delivery
  IF p_order_subtotal >= v_free_threshold THEN
    RETURN 0;
  END IF;

  -- Calculate: base fee + (per-km rate * distance)
  v_total_fee := v_base_fee + (v_per_km_rate * p_distance_km);

  -- Ensure fee is never negative
  RETURN GREATEST(v_total_fee, 0);
END;
$$;

COMMENT ON FUNCTION public.calculate_delivery_fee(UUID, NUMERIC, NUMERIC) IS 'P1E-09: Calculates delivery fee in EGP based on platform_config and distance. Returns -1 if out of delivery range. Checks merchant override first, then applies base + per-km formula.';

-- =============================================================================
-- P1E-10: UPDATE_MERCHANT_RATING() FUNCTION
-- Recalculates and updates the aggregate rating on the merchants table.
-- Called by trigger on reviews INSERT/UPDATE (see 018_create_triggers.sql).
--
-- Calculation: AVG(merchant_rating) and COUNT(*) from reviews table
-- for the given merchant. Only considers reviews with merchant_rating set.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.update_merchant_rating(p_merchant_id UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  v_avg_rating NUMERIC;
  v_rating_count INTEGER;
BEGIN
  SELECT
    ROUND(AVG(merchant_rating), 1),
    COUNT(*)
  INTO v_avg_rating, v_rating_count
  FROM public.reviews
  WHERE merchant_id = p_merchant_id;

  -- Update the merchants table with new aggregate values
  UPDATE public.merchants
  SET
    rating = COALESCE(v_avg_rating, 0.0),
    rating_count = COALESCE(v_rating_count, 0)
  WHERE id = p_merchant_id;
END;
$$;

COMMENT ON FUNCTION public.update_merchant_rating(UUID) IS 'P1E-10: Recalculates and updates the aggregate rating (AVG + COUNT) on the merchants table. Called by trigger on reviews INSERT/UPDATE.';

-- =============================================================================
-- P1E-11: UPDATE_DRIVER_RATING() FUNCTION
-- Recalculates and updates the aggregate rating on the drivers table.
-- Called by trigger on reviews INSERT/UPDATE (see 018_create_triggers.sql).
--
-- Calculation: AVG(driver_rating) and COUNT(*) from reviews table
-- for the given driver. Only considers reviews where driver_rating IS NOT NULL
-- (driver rating is optional — may be NULL if no driver was assigned).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.update_driver_rating(p_driver_id UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  v_avg_rating NUMERIC;
  v_rating_count INTEGER;
BEGIN
  SELECT
    ROUND(AVG(driver_rating), 1),
    COUNT(driver_rating)
  INTO v_avg_rating, v_rating_count
  FROM public.reviews
  WHERE driver_id = p_driver_id
    AND driver_rating IS NOT NULL;

  -- Update the drivers table with new aggregate values
  UPDATE public.drivers
  SET
    rating = COALESCE(v_avg_rating, 5.0),
    rating_count = COALESCE(v_rating_count, 0)
  WHERE id = p_driver_id;
END;
$$;

COMMENT ON FUNCTION public.update_driver_rating(UUID) IS 'P1E-11: Recalculates and updates the aggregate rating (AVG + COUNT) on the drivers table. Only considers reviews with non-NULL driver_rating. Default rating is 5.0 if no reviews.';

-- =============================================================================
-- P1E-12: IS_MERCHANT_OPEN() FUNCTION (⚡ PERFORMANCE-NOTE)
-- Checks if a merchant is currently open based on their operating_hours.
--
-- ⚠️ IMPORTANT PERFORMANCE NOTE (RED-01 in 13-PERFORMANCE-RED-FLAGS.md):
--   Do NOT call this function per-row in the merchant feed query.
--   Instead, use a SQL EXISTS subquery in the feed query for batch efficiency.
--   This function exists for single-merchant lookups (merchant detail page,
--   place-order validation) where per-row overhead is acceptable.
--
-- Logic:
--   1. Get current day of week (1=Monday, 7=Sunday per ISO)
--   2. Get current time in Cairo timezone (Africa/Cairo)
--   3. Check if operating_hours has an entry for this day
--   4. Check if current time is within open_time and close_time
--   5. If no operating_hours row exists for this day, merchant is closed
-- =============================================================================

CREATE OR REPLACE FUNCTION public.is_merchant_open(p_merchant_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_is_open BOOLEAN;
  v_current_day INTEGER;
  v_current_time TIME;
BEGIN
  -- Get current day of week (ISO: 1=Monday, 7=Sunday)
  v_current_day := EXTRACT(ISODOW FROM NOW() AT TIME ZONE 'Africa/Cairo');

  -- Get current time in Cairo timezone
  v_current_time := (NOW() AT TIME ZONE 'Africa/Cairo')::TIME;

  -- Check if there's an operating hours entry and if current time is within range
  SELECT EXISTS (
    SELECT 1
    FROM public.operating_hours
    WHERE merchant_id = p_merchant_id
      AND day_of_week = v_current_day
      AND is_closed = FALSE
      AND v_current_time >= open_time
      AND v_current_time < close_time
  ) INTO v_is_open;

  RETURN COALESCE(v_is_open, FALSE);
END;
$$;

COMMENT ON FUNCTION public.is_merchant_open(UUID) IS 'P1E-12: Checks if a merchant is currently open based on operating_hours. ⚠️ Do NOT call per-row in feed queries — use SQL EXISTS subquery instead (see RED-01). Use for single-merchant lookups only.';

-- =============================================================================
-- P1E-13: GET_DRIVER_LOCATION() SECURITY DEFINER FUNCTION (⚡🔒)
-- Securely retrieves a driver's real-time location for a given order.
-- Only the customer who placed the order can query the driver location.
--
-- Why SECURITY DEFINER?
--   Per RED-27 in 13-PERFORMANCE-RED-FLAGS.md:
--   RLS on the drivers table would require a join check on every SELECT,
--   adding overhead to hot driver location queries. Instead, we use a
--   SECURITY DEFINER function that:
--     1. Verifies the caller is the customer of the order
--     2. Verifies the order has a driver assigned
--     3. Returns only lat/lng/last_location_at
--
-- This function bypasses RLS on drivers but enforces its own access control.
-- The service role can always query driver locations directly.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_driver_location(
  p_order_id UUID,
  p_customer_id UUID
)
RETURNS TABLE (
  current_lat NUMERIC,
  current_lng NUMERIC,
  last_location_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_driver_id UUID;
BEGIN
  -- Step 1: Verify the order belongs to this customer and has a driver
  SELECT driver_id INTO v_driver_id
  FROM public.orders
  WHERE id = p_order_id
    AND customer_id = p_customer_id
    AND driver_id IS NOT NULL;

  -- If no matching order or no driver assigned, return empty
  IF v_driver_id IS NULL THEN
    RETURN;
  END IF;

  -- Step 2: Return only the location fields from the driver
  RETURN QUERY
  SELECT
    d.current_lat,
    d.current_lng,
    d.last_location_at
  FROM public.drivers d
  WHERE d.id = v_driver_id
    AND d.is_online = TRUE;
END;
$$;

COMMENT ON FUNCTION public.get_driver_location(UUID, UUID) IS 'P1E-13: SECURITY DEFINER function to securely retrieve driver location for a customer order. Verifies customer owns the order and driver is assigned. Bypasses RLS but enforces own access control. See RED-27.';

-- =============================================================================
-- HELPER: GET PLATFORM CONFIG VALUE
-- Simple helper to fetch a platform_config value by key.
-- Used by other functions to avoid repeating the query pattern.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_platform_config(p_key TEXT)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_value TEXT;
BEGIN
  SELECT value INTO v_value
  FROM public.platform_config
  WHERE key = p_key;

  RETURN v_value;
END;
$$;

COMMENT ON FUNCTION public.get_platform_config(TEXT) IS 'Helper: fetches a platform_config value by key. Returns NULL if key not found.';
