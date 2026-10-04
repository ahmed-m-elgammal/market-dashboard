-- Migration 093: Create get_merchant_review_summary RPC function
-- F-18 (audit §5 [P5] [MAJOR]): Aggregate ratings and star distributions server-side
-- in a single round-trip instead of pulling all review rows across the wire.

CREATE OR REPLACE FUNCTION public.get_merchant_review_summary(p_merchant_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_average_rating NUMERIC;
  v_total_count BIGINT;
  v_distribution JSON;
BEGIN
  -- Aggregate ratings
  SELECT 
    COALESCE(ROUND(AVG(merchant_rating)::NUMERIC, 1), 0.0),
    COUNT(*),
    JSON_BUILD_ARRAY(
      COUNT(*) FILTER (WHERE merchant_rating = 1),
      COUNT(*) FILTER (WHERE merchant_rating = 2),
      COUNT(*) FILTER (WHERE merchant_rating = 3),
      COUNT(*) FILTER (WHERE merchant_rating = 4),
      COUNT(*) FILTER (WHERE merchant_rating = 5)
    )
  INTO v_average_rating, v_total_count, v_distribution
  FROM public.reviews
  WHERE merchant_id = p_merchant_id;

  RETURN JSON_BUILD_OBJECT(
    'average_rating', v_average_rating,
    'total_count', v_total_count,
    'distribution', v_distribution
  );
END;
$$;

COMMENT ON FUNCTION public.get_merchant_review_summary(UUID) IS 'F-18: Computes aggregated rating average, count, and star distribution for a merchant in one server-side query.';
