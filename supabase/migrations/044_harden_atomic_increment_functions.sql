-- Migration 044: Harden increment_promo_usage and increment_driver_stats
--
-- Migration 038 introduced these as SECURITY DEFINER but missed three
-- protections that migration 036 (place_order_with_items) already applies:
--   1. SET search_path = ''  → prevents search-path hijacking
--   2. Explicit service-role check inside the function body → defense in
--      depth, fails closed if a future migration accidentally widens GRANT
--   3. REVOKE EXECUTE FROM PUBLIC → functions default to PUBLIC-executable
--      in Postgres; the existing GRANT to service_role was additive
--
-- Without these, any authenticated user could call:
--   supabase.rpc('increment_promo_usage', { p_promo_code_id: '...' })
-- repeatedly to exhaust every active promo's max_usage — disabling all
-- promos system-wide. Same vector on increment_driver_stats to corrupt
-- driver earnings counters.
--
-- This migration replaces both functions with hardened versions matching
-- the pattern established in migration 036.

-- =============================================================================
-- 1. increment_promo_usage
-- =============================================================================
DROP FUNCTION IF EXISTS public.increment_promo_usage(UUID);

CREATE OR REPLACE FUNCTION public.increment_promo_usage(
  p_promo_code_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  -- SECURITY: Service-role only. Prevents any authenticated user from
  -- calling this RPC directly to inflate promo usage counts.
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: increment_promo_usage is service-role only.';
  END IF;

  UPDATE public.promo_codes
  SET current_usage = COALESCE(current_usage, 0) + 1
  WHERE id = p_promo_code_id;
END;
$$;

COMMENT ON FUNCTION public.increment_promo_usage(UUID) IS
  'Atomic promo-code usage increment. SECURITY DEFINER, service-role only, hardened with SET search_path = "". See migration 044.';

REVOKE EXECUTE ON FUNCTION public.increment_promo_usage(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.increment_promo_usage(UUID) TO service_role;

-- =============================================================================
-- 2. increment_driver_stats
-- =============================================================================
DROP FUNCTION IF EXISTS public.increment_driver_stats(UUID, NUMERIC);

CREATE OR REPLACE FUNCTION public.increment_driver_stats(
  p_driver_id UUID,
  p_earnings_amount NUMERIC
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  -- SECURITY: Service-role only. Prevents any authenticated user from
  -- calling this RPC directly to corrupt driver delivery counts or earnings.
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: increment_driver_stats is service-role only.';
  END IF;

  UPDATE public.drivers
  SET
    total_deliveries = COALESCE(total_deliveries, 0) + 1,
    total_earnings = COALESCE(total_earnings, 0) + p_earnings_amount
  WHERE id = p_driver_id;
END;
$$;

COMMENT ON FUNCTION public.increment_driver_stats(UUID, NUMERIC) IS
  'Atomic driver stats increment. SECURITY DEFINER, service-role only, hardened with SET search_path = "". See migration 044.';

REVOKE EXECUTE ON FUNCTION public.increment_driver_stats(UUID, NUMERIC) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.increment_driver_stats(UUID, NUMERIC) TO service_role;
