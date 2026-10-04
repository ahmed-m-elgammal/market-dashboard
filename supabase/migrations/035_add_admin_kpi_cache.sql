-- Migration 035: Admin KPI cache table
-- Per RED-22 in 13-PERFORMANCE-RED-FLAGS.md:
--   Admin dashboard live KPIs query the full orders table.
--   At 1M+ orders, COUNT(*) queries take 100ms+.
--   A summary table returns in <1ms.
--
-- Pre-computed summary table refreshed periodically (every 30 seconds)
-- by a cron job or Edge Function.

-- =============================================================================
-- ADMIN KPI CACHE TABLE
-- Stores pre-computed dashboard KPIs for instant admin panel loading.
-- =============================================================================

CREATE TABLE admin_kpi_cache (
  key TEXT PRIMARY KEY,
  value JSONB NOT NULL,
  computed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- KPI COMPUTATION FUNCTION
-- Computes all dashboard KPIs in a single pass.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.compute_admin_kpis()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_dashboard JSONB;
  v_orders JSONB;
  v_drivers JSONB;
  v_revenue JSONB;
  v_customers JSONB;
BEGIN
  -- Dashboard overview KPIs
  SELECT jsonb_build_object(
    'active_orders', COUNT(*) FILTER (WHERE status NOT IN ('delivered', 'cancelled')),
    'pending_orders', COUNT(*) FILTER (WHERE status = 'pending'),
    'confirmed_orders', COUNT(*) FILTER (WHERE status = 'confirmed'),
    'preparing_orders', COUNT(*) FILTER (WHERE status = 'preparing'),
    'ready_orders', COUNT(*) FILTER (WHERE status = 'ready'),
    'in_delivery_orders', COUNT(*) FILTER (WHERE status IN ('picked_up', 'on_the_way')),
    'delivered_today', COUNT(*) FILTER (WHERE status = 'delivered' AND delivered_at >= CURRENT_DATE),
    'cancelled_today', COUNT(*) FILTER (WHERE status = 'cancelled' AND cancelled_at >= CURRENT_DATE),
    'total_orders_today', COUNT(*) FILTER (WHERE created_at >= CURRENT_DATE)
  ) INTO v_dashboard
  FROM public.orders;

  -- Order metrics
  SELECT jsonb_build_object(
    'total_orders', COUNT(*),
    'avg_order_value', ROUND(AVG(total), 2),
    'avg_delivery_time_minutes', ROUND(AVG(
      EXTRACT(EPOCH FROM (delivered_at - created_at)) / 60
    ) FILTER (WHERE status = 'delivered' AND delivered_at IS NOT NULL), 1),
    'cash_orders_pct', ROUND(
      100.0 * COUNT(*) FILTER (WHERE payment_method = 'cash') / NULLIF(COUNT(*), 0), 1
    ),
    'digital_orders_pct', ROUND(
      100.0 * COUNT(*) FILTER (WHERE payment_method != 'cash') / NULLIF(COUNT(*), 0), 1
    )
  ) INTO v_orders
  FROM public.orders
  WHERE created_at >= CURRENT_DATE;

  -- Driver metrics
  SELECT jsonb_build_object(
    'total_drivers', COUNT(*),
    'online_drivers', COUNT(*) FILTER (WHERE is_online = TRUE),
    'verified_drivers', COUNT(*) FILTER (WHERE is_verified = TRUE),
    'pending_verification', COUNT(*) FILTER (WHERE verification_status = 'pending'),
    'active_on_order', COUNT(*) FILTER (WHERE is_online = TRUE AND EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.driver_id = drivers.id
        AND o.status IN ('confirmed', 'preparing', 'ready', 'picked_up', 'on_the_way')
    ))
  ) INTO v_drivers
  FROM public.drivers;

  -- Revenue metrics
  SELECT jsonb_build_object(
    'revenue_today', COALESCE(SUM(platform_fee + delivery_fee) FILTER (WHERE status = 'delivered' AND delivered_at >= CURRENT_DATE), 0),
    'revenue_this_week', COALESCE(SUM(platform_fee + delivery_fee) FILTER (WHERE status = 'delivered' AND delivered_at >= DATE_TRUNC('week', CURRENT_DATE)), 0),
    'revenue_this_month', COALESCE(SUM(platform_fee + delivery_fee) FILTER (WHERE status = 'delivered' AND delivered_at >= DATE_TRUNC('month', CURRENT_DATE)), 0),
    'gross_order_value_today', COALESCE(SUM(total) FILTER (WHERE status = 'delivered' AND delivered_at >= CURRENT_DATE), 0),
    'pending_cash_total', COALESCE(SUM(total) FILTER (WHERE payment_status = 'pending_cash'), 0)
  ) INTO v_revenue
  FROM public.orders;

  -- Customer metrics
  SELECT jsonb_build_object(
    'total_customers', (SELECT COUNT(*) FROM public.profiles WHERE role = 'customer'),
    'new_customers_today', (SELECT COUNT(*) FROM public.profiles WHERE role = 'customer' AND created_at >= CURRENT_DATE),
    'active_customers_week', (SELECT COUNT(DISTINCT customer_id) FROM public.orders WHERE created_at >= CURRENT_DATE - INTERVAL '7 days')
  ) INTO v_customers;

  -- Upsert all KPIs
  INSERT INTO public.admin_kpi_cache (key, value, computed_at) VALUES
    ('dashboard', v_dashboard, NOW()),
    ('orders', v_orders, NOW()),
    ('drivers', v_drivers, NOW()),
    ('revenue', v_revenue, NOW()),
    ('customers', v_customers, NOW())
  ON CONFLICT (key) DO UPDATE SET
    value = EXCLUDED.value,
    computed_at = EXCLUDED.computed_at;
END;
$$;

COMMENT ON FUNCTION public.compute_admin_kpis() IS 'Pre-computes all admin dashboard KPIs and stores in admin_kpi_cache. Call every 30 seconds via cron. Returns instantly from cache.';

-- =============================================================================
-- KPI READ FUNCTIONS (for admin Edge Functions)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_admin_kpi(p_key TEXT)
RETURNS TABLE (key TEXT, value JSONB, computed_at TIMESTAMPTZ, age_seconds INTEGER)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  RETURN QUERY
  SELECT
    akc.key,
    akc.value,
    akc.computed_at,
    EXTRACT(EPOCH FROM NOW() - akc.computed_at)::INTEGER AS age_seconds
  FROM public.admin_kpi_cache akc
  WHERE akc.key = p_key;
END;
$$;

COMMENT ON FUNCTION public.get_admin_kpi(TEXT) IS 'Returns a cached admin KPI with its age in seconds. If age > 30 seconds, consider recomputing.';

-- =============================================================================
-- ENABLE RLS
-- =============================================================================

ALTER TABLE public.admin_kpi_cache ENABLE ROW LEVEL SECURITY;
-- No policies: service role only

-- =============================================================================
-- GRANT PERMISSIONS
-- =============================================================================

REVOKE EXECUTE ON FUNCTION public.compute_admin_kpis() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_admin_kpi(TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.compute_admin_kpis() TO service_role;
GRANT EXECUTE ON FUNCTION public.get_admin_kpi(TEXT) TO service_role;
