-- ============================================================
-- Atomic increment functions for driver stats and promo usage
-- Eliminates read-then-write race conditions in complete_delivery
--
-- These functions use atomic SQL increments instead of the
-- application-level read → compute → update pattern, which is
-- vulnerable to race conditions when multiple deliveries complete
-- concurrently for the same driver.
-- ============================================================

-- Atomic increment of driver delivery stats
-- Called from driver-actions Edge Function after successful delivery
CREATE OR REPLACE FUNCTION increment_driver_stats(
  p_driver_id UUID,
  p_earnings_amount NUMERIC
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE drivers
  SET
    total_deliveries = COALESCE(total_deliveries, 0) + 1,
    total_earnings = COALESCE(total_earnings, 0) + p_earnings_amount
  WHERE id = p_driver_id;
END;
$$;

-- Atomic increment of promo code usage count
-- Called from driver-actions Edge Function after successful delivery
CREATE OR REPLACE FUNCTION increment_promo_usage(
  p_promo_code_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE promo_codes
  SET current_usage = COALESCE(current_usage, 0) + 1
  WHERE id = p_promo_code_id;
END;
$$;

-- Grant execute to service role (Edge Functions use service role key)
GRANT EXECUTE ON FUNCTION increment_driver_stats(UUID, NUMERIC) TO service_role;
GRANT EXECUTE ON FUNCTION increment_promo_usage(UUID) TO service_role;
