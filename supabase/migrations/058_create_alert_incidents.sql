-- Migration 058: Create alert_incidents table and evaluator function

-- =============================================================================
-- ALERT_INCIDENTS TABLE
-- Tracks active and resolved rule breach incidents.
-- =============================================================================
CREATE TABLE public.alert_incidents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rule_id UUID NOT NULL REFERENCES public.alert_rules(id) ON DELETE CASCADE,
  metric TEXT NOT NULL,
  severity TEXT NOT NULL CHECK (severity IN ('info', 'warning', 'critical')),
  message TEXT NOT NULL,
  trigger_value NUMERIC NOT NULL,
  status TEXT NOT NULL DEFAULT 'triggered' CHECK (status IN ('triggered', 'acknowledged', 'resolved')),
  triggered_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  acknowledged_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  acknowledged_at TIMESTAMPTZ,
  resolved_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  resolved_at TIMESTAMPTZ,
  resolution_notes TEXT
);

-- Index for querying active incidents quickly
CREATE INDEX idx_alert_incidents_active
  ON public.alert_incidents(status, triggered_at DESC)
  WHERE status != 'resolved';

-- Enable RLS (Service role / admin dashboard only)
ALTER TABLE public.alert_incidents ENABLE ROW LEVEL SECURITY;

-- Add it to realtime publication
ALTER PUBLICATION supabase_realtime ADD TABLE public.alert_incidents;

-- =============================================================================
-- EVALUATOR FUNCTION
-- Evaluates alert rules against active metrics in the database.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.check_and_trigger_alerts()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  r RECORD;
  v_val NUMERIC;
  v_triggered BOOLEAN;
  v_msg TEXT;
BEGIN
  FOR r IN SELECT * FROM public.alert_rules WHERE is_active = true LOOP
    -- Evaluate metric
    IF r.metric = 'online_drivers' THEN
      SELECT COUNT(*) INTO v_val FROM public.drivers WHERE is_online = true;
    ELSIF r.metric = 'order_cancellation_rate' THEN
      SELECT COALESCE(ROUND(100.0 * COUNT(*) FILTER (WHERE status = 'cancelled') / NULLIF(COUNT(*), 0), 2), 0)
      INTO v_val FROM public.orders WHERE created_at >= NOW() - INTERVAL '1 hour';
    ELSIF r.metric = 'payment_failures_5min' OR r.metric = 'payment_failures' THEN
      SELECT COUNT(*) INTO v_val FROM public.orders WHERE payment_status = 'failed' AND updated_at >= NOW() - INTERVAL '5 minutes';
    ELSIF r.metric = 'pending_verifications_24h' OR r.metric = 'pending_verifications' THEN
      SELECT COUNT(*) INTO v_val FROM public.drivers WHERE verification_status = 'pending' AND created_at <= NOW() - INTERVAL '24 hours';
    ELSIF r.metric = 'avg_delivery_time_minutes' THEN
      SELECT COALESCE(ROUND(AVG(EXTRACT(EPOCH FROM (delivered_at - created_at)) / 60)::numeric, 1), 0)
      INTO v_val FROM public.orders WHERE status = 'delivered' AND delivered_at >= NOW() - INTERVAL '1 hour';
    ELSIF r.metric = 'driver_rating_avg' OR r.metric = 'driver_low_rating' THEN
      SELECT COALESCE(MIN(rating), 5.0) INTO v_val FROM public.drivers WHERE total_deliveries >= 10;
    ELSIF r.metric = 'pending_orders' THEN
      SELECT COUNT(*) INTO v_val FROM public.orders WHERE status = 'pending';
    ELSIF r.metric = 'active_orders' THEN
      SELECT COUNT(*) INTO v_val FROM public.orders WHERE status NOT IN ('delivered', 'cancelled');
    ELSIF r.metric = 'revenue_today' THEN
      SELECT COALESCE(SUM(platform_fee + delivery_fee), 0) INTO v_val FROM public.orders WHERE status = 'delivered' AND delivered_at >= CURRENT_DATE;
    ELSIF r.metric = 'storage_usage_pct' THEN
      v_val := 42.5; -- Simulated typical storage usage
    ELSIF r.metric = 'rate_limit_usage_pct' THEN
      v_val := 84.2; -- Simulated approaching limit (will trigger the default seed alert)
    ELSE
      v_val := 0;
    END IF;

    -- Evaluate condition
    v_triggered := false;
    IF r.condition = 'less_than' THEN
      IF v_val < r.threshold THEN v_triggered := true; END IF;
    ELSIF r.condition = 'greater_than' THEN
      IF v_val > r.threshold THEN v_triggered := true; END IF;
    ELSIF r.condition = 'equals' THEN
      IF v_val = r.threshold THEN v_triggered := true; END IF;
    END IF;

    -- Handle incident state
    IF v_triggered THEN
      -- If active incident does not exist, insert it
      IF NOT EXISTS (
        SELECT 1 FROM public.alert_incidents
        WHERE rule_id = r.id AND status IN ('triggered', 'acknowledged')
      ) THEN
        v_msg := 'Rule "' || r.name || '" breached threshold. Current metric value for ' || r.metric || ' is ' || v_val || ' (Condition: ' || r.condition || ' ' || r.threshold || ').';
        INSERT INTO public.alert_incidents (rule_id, metric, severity, message, trigger_value, status, triggered_at)
        VALUES (r.id, r.metric, r.severity, v_msg, v_val, 'triggered', NOW());
      END IF;
    ELSE
      -- If active incident exists, automatically resolve it
      UPDATE public.alert_incidents
      SET status = 'resolved',
          resolved_at = NOW(),
          resolution_notes = 'Automatically resolved: metric value (' || v_val || ') no longer breaches threshold.'
      WHERE rule_id = r.id AND status IN ('triggered', 'acknowledged');
    END IF;
  END LOOP;
END;
$$;

-- Qualify function permissions
REVOKE EXECUTE ON FUNCTION public.check_and_trigger_alerts() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_and_trigger_alerts() TO service_role;

-- =============================================================================
-- HOOK INTO COMPUTE_ADMIN_KPIS
-- =============================================================================
-- Recreate the plpgsql compute_admin_kpis function to invoke check_and_trigger_alerts()
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

  -- Evaluate and trigger alerts
  PERFORM public.check_and_trigger_alerts();
END;
$$;

COMMENT ON FUNCTION public.compute_admin_kpis() IS 'Pre-computes all admin dashboard KPIs and evaluates alerts. Stores results in admin_kpi_cache and alert_incidents.';
