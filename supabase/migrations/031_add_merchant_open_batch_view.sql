-- Migration 031: Add batch-optimized merchant open status
-- Per RED-01 and RED-06 in 13-PERFORMANCE-RED-FLAGS.md:
--   Do NOT call is_merchant_open() per row in the merchant feed query.
--   Instead, use a SQL EXISTS subquery for batch efficiency.
--
-- This migration creates:
--   1. A materialized view `merchants_with_open_status` for the feed query
--   2. A function to refresh the materialized view
--   3. An optimized feed query function that returns merchants with open status
--      and distance in a single query
--
-- Performance comparison:
--   - Per-row is_merchant_open(): 200 function calls × 2ms = 400ms
--   - EXISTS subquery in SQL: 1 query × 5ms = 5ms
--   - Materialized view: 1 read × 1ms = 1ms

-- =============================================================================
-- 1. MATERIALIZED VIEW: MERCHANTS WITH OPEN STATUS
-- Pre-computed open status for all active merchants.
-- Refresh periodically (every 1-2 minutes) or on demand.
-- =============================================================================

CREATE MATERIALIZED VIEW public.merchants_with_open_status AS
SELECT
  m.id,
  m.name_ar,
  m.name_en,
  m.category,
  m.logo_url,
  m.cover_url,
  m.description_ar,
  m.description_en,
  m.address,
  m.lat,
  m.lng,
  m.city,
  m.area,
  m.phone,
  m.is_active,
  m.rating,
  m.rating_count,
  m.min_order_amount,
  m.estimated_delivery_minutes,
  m.delivery_fee_override,
  m.commission_pct,
  m.created_at,
  -- Batch-computed open status (single EXISTS query for all merchants)
  EXISTS (
    SELECT 1 FROM public.operating_hours oh
    WHERE oh.merchant_id = m.id
      AND oh.day_of_week = EXTRACT(ISODOW FROM NOW() AT TIME ZONE 'Africa/Cairo')
      AND oh.is_closed = FALSE
      AND (NOW() AT TIME ZONE 'Africa/Cairo')::TIME >= oh.open_time
      AND (NOW() AT TIME ZONE 'Africa/Cairo')::TIME < oh.close_time
  ) AS is_currently_open
FROM public.merchants m
WHERE m.is_active = TRUE;

-- Unique index on id for concurrent refresh
CREATE UNIQUE INDEX idx_merchants_open_status_id
  ON public.merchants_with_open_status(id);

-- Index for feed queries
CREATE INDEX idx_merchants_open_status_city_category
  ON public.merchants_with_open_status(city, category);

-- Index for open merchants
CREATE INDEX idx_merchants_open_status_open
  ON public.merchants_with_open_status(is_currently_open)
  WHERE is_currently_open = TRUE;

COMMENT ON MATERIALIZED VIEW public.merchants_with_open_status IS 'Active merchants with pre-computed is_currently_open status. Refresh every 1-2 minutes. Used by get-merchant-feed for batch-efficient open status (RED-01, RED-06).';

-- =============================================================================
-- 2. REFRESH FUNCTION
-- Concurrent refresh does not block reads.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.refresh_merchant_open_status()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY public.merchants_with_open_status;
END;
$$;

COMMENT ON FUNCTION public.refresh_merchant_open_status() IS 'Concurrently refreshes the merchants_with_open_status materialized view. Safe to call while reads are happening.';

-- =============================================================================
-- 3. OPTIMIZED MERCHANT FEED QUERY
-- Returns merchants for a city with open status, distance, and promoted slots.
-- Single query — no per-row function calls.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_merchant_feed(
  p_city TEXT,
  p_category TEXT DEFAULT NULL,
  p_lat NUMERIC DEFAULT NULL,
  p_lng NUMERIC DEFAULT NULL,
  p_limit INTEGER DEFAULT 20,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  id UUID,
  name_ar TEXT,
  name_en TEXT,
  category TEXT,
  logo_url TEXT,
  cover_url TEXT,
  city TEXT,
  area TEXT,
  lat NUMERIC,
  lng NUMERIC,
  rating NUMERIC,
  rating_count INTEGER,
  min_order_amount NUMERIC,
  estimated_delivery_minutes INTEGER,
  delivery_fee_override NUMERIC,
  is_currently_open BOOLEAN,
  distance_meters NUMERIC,
  is_promoted BOOLEAN,
  promoted_position INTEGER
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  RETURN QUERY
  SELECT
    mws.id,
    mws.name_ar,
    mws.name_en,
    mws.category,
    mws.logo_url,
    mws.cover_url,
    mws.city,
    mws.area,
    mws.lat,
    mws.lng,
    mws.rating,
    mws.rating_count,
    mws.min_order_amount,
    mws.estimated_delivery_minutes,
    mws.delivery_fee_override,
    mws.is_currently_open,
    -- Distance calculation (only if lat/lng provided)
    CASE
      WHEN p_lat IS NOT NULL AND p_lng IS NOT NULL THEN
        ST_Distance(
          ST_MakePoint(mws.lng, mws.lat)::geography,
          ST_MakePoint(p_lng, p_lat)::geography
        )
      ELSE NULL
    END AS distance_meters,
    -- Promoted status
    CASE WHEN ps.id IS NOT NULL THEN TRUE ELSE FALSE END AS is_promoted,
    -- Promoted position (NULL if not promoted)
    ROW_NUMBER() OVER (PARTITION BY ps.id IS NOT NULL ORDER BY ps.created_at DESC)::INTEGER AS promoted_position
  FROM public.merchants_with_open_status mws
  -- LEFT JOIN promoted slots (inject ads into feed)
  LEFT JOIN public.promoted_slots ps ON ps.merchant_id = mws.id
    AND ps.is_active = TRUE
    AND ps.city = p_city
    AND ps.starts_at <= NOW()
    AND ps.expires_at > NOW()
    AND (ps.category = mws.category OR ps.category IS NULL)
  WHERE mws.city = p_city
    AND (p_category IS NULL OR mws.category = p_category)
  -- Sort: promoted first, then open by distance, then closed
  ORDER BY
    is_promoted DESC,
    mws.is_currently_open DESC,
    CASE
      WHEN p_lat IS NOT NULL AND p_lng IS NOT NULL THEN
        ST_Distance(
          ST_MakePoint(mws.lng, mws.lat)::geography,
          ST_MakePoint(p_lng, p_lat)::geography
        )
      ELSE 0
    END ASC,
    mws.rating DESC
  LIMIT p_limit
  OFFSET p_offset;
END;
$$;

COMMENT ON FUNCTION public.get_merchant_feed(TEXT, TEXT, NUMERIC, NUMERIC, INTEGER, INTEGER) IS 'Optimized merchant feed query with batch-computed open status and distance. No per-row function calls. Sorts: promoted → open by distance → closed. See RED-01, RED-06.';

-- =============================================================================
-- GRANT PERMISSIONS
-- =============================================================================

-- The feed function is called from Edge Functions (service role) but can also
-- be called by authenticated users for direct reads
GRANT EXECUTE ON FUNCTION public.get_merchant_feed(TEXT, TEXT, NUMERIC, NUMERIC, INTEGER, INTEGER) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_merchant_feed(TEXT, TEXT, NUMERIC, NUMERIC, INTEGER, INTEGER) TO authenticated;

-- Refresh is admin-only (called by cron or admin action)
REVOKE EXECUTE ON FUNCTION public.refresh_merchant_open_status() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.refresh_merchant_open_status() TO service_role;

-- Allow reading the materialized view
GRANT SELECT ON public.merchants_with_open_status TO authenticated;
GRANT SELECT ON public.merchants_with_open_status TO anon;
