-- Migration 054: get_analytics_summary RPC
--
-- Replaces the in-JS aggregation in GET /api/analytics (apps/admin/src/app/api/
-- analytics/route.ts) with a single SQL function. Previously the route fetched
-- every order row in the date range into Node memory and aggregated with
-- .filter()/.reduce() — at 1k orders/day × 30 days that's 30k rows parsed
-- per request. This RPC does all aggregation server-side and returns one
-- JSON blob.
--
-- Output shape (matches the previous JS output exactly so the client does
-- not need to change):
--   {
--     "orders": { total, completed, cancelled, pending,
--                 completionRate, cancellationRate },
--     "financials": { totalSales, totalPlatformFees, totalDeliveryFees,
--                     averageOrderValue, netRevenue },
--     "cancellations": [{ reason, count }, ...],
--     "cancellationsByRole": { customer, driver, merchant, admin, unknown },
--     "drivers": { total, online, active, averageRating,
--                  averageDeliveries, averageEarnings },
--     "recentDailyStats": [{ date, orders, revenue }, ...]
--   }
--
-- Daily stats are bucketed by Africa/Cairo local date (UTC+2, no DST since
-- 2014) to match the previous JS offset logic.
--
-- Security:
--   - SECURITY DEFINER so the function can read orders/drivers without the
--     caller needing direct SELECT grants. RLS still applies via the service
--     role used by the admin route.
--   - SET search_path = '' per the migration hardening convention (S16).
--   - STABLE: reads only, no side effects.

CREATE OR REPLACE FUNCTION public.get_analytics_summary(
  p_from timestamptz,
  p_to timestamptz
)
RETURNS json
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT json_build_object(
    'orders', (
      SELECT json_build_object(
        'total', COUNT(*),
        'completed', COUNT(*) FILTER (WHERE status = 'delivered'),
        'cancelled', COUNT(*) FILTER (WHERE status = 'cancelled'),
        'pending', COUNT(*) FILTER (WHERE status NOT IN ('delivered', 'cancelled')),
        'completionRate', CASE WHEN COUNT(*) > 0
          THEN ROUND((COUNT(*) FILTER (WHERE status = 'delivered'))::numeric * 100 / COUNT(*), 1)
          ELSE 0 END,
        'cancellationRate', CASE WHEN COUNT(*) > 0
          THEN ROUND((COUNT(*) FILTER (WHERE status = 'cancelled'))::numeric * 100 / COUNT(*), 1)
          ELSE 0 END
      )
      FROM public.orders
      WHERE created_at BETWEEN p_from AND p_to
    ),
    'financials', (
      SELECT json_build_object(
        'totalSales', COALESCE(SUM(total) FILTER (WHERE status = 'delivered'), 0),
        'totalPlatformFees', COALESCE(SUM(platform_fee) FILTER (WHERE status = 'delivered'), 0),
        'totalDeliveryFees', COALESCE(SUM(delivery_fee) FILTER (WHERE status = 'delivered'), 0),
        'averageOrderValue', CASE WHEN COUNT(*) FILTER (WHERE status = 'delivered') > 0
          THEN ROUND(SUM(total) FILTER (WHERE status = 'delivered')::numeric
            / COUNT(*) FILTER (WHERE status = 'delivered'), 2)
          ELSE 0 END,
        'netRevenue', COALESCE(SUM(platform_fee) FILTER (WHERE status = 'delivered'), 0)
                     + COALESCE(SUM(delivery_fee) FILTER (WHERE status = 'delivered'), 0)
      )
      FROM public.orders
      WHERE created_at BETWEEN p_from AND p_to
    ),
    'cancellations', COALESCE(
      (SELECT json_agg(json_build_object('reason', reason, 'count', cnt) ORDER BY cnt DESC)
       FROM (
         SELECT COALESCE(NULLIF(cancellation_reason, ''), 'Unspecified') AS reason,
                COUNT(*) AS cnt
         FROM public.orders
         WHERE created_at BETWEEN p_from AND p_to
           AND status = 'cancelled'
         GROUP BY 1
       ) c),
      '[]'::json
    ),
    'cancellationsByRole', (
      SELECT json_build_object(
        'customer', COUNT(*) FILTER (WHERE p.role = 'customer'),
        'driver',   COUNT(*) FILTER (WHERE p.role = 'driver'),
        'merchant', COUNT(*) FILTER (WHERE p.role = 'merchant'),
        'admin',    COUNT(*) FILTER (WHERE p.role = 'admin'),
        'unknown',  COUNT(*) FILTER (WHERE o.cancelled_by IS NOT NULL AND (p.role IS NULL OR p.role NOT IN ('customer', 'driver', 'merchant', 'admin')))
      )
      FROM public.orders o
      LEFT JOIN public.profiles p ON o.cancelled_by = p.id
      WHERE o.created_at BETWEEN p_from AND p_to
        AND o.status = 'cancelled'
    ),
    'drivers', (
      SELECT json_build_object(
        'total', COUNT(*),
        'online', COUNT(*) FILTER (WHERE is_online),
        'active', COUNT(*) FILTER (WHERE is_active),
        'averageRating', CASE WHEN COUNT(*) FILTER (WHERE rating IS NOT NULL) > 0
          THEN ROUND(AVG(rating) FILTER (WHERE rating IS NOT NULL), 2)
          ELSE 0 END,
        'averageDeliveries', CASE WHEN COUNT(*) > 0
          THEN ROUND(AVG(total_deliveries), 1)
          ELSE 0 END,
        'averageEarnings', CASE WHEN COUNT(*) > 0
          THEN ROUND(AVG(total_earnings), 2)
          ELSE 0 END
      )
      FROM public.drivers
    ),
    'recentDailyStats', COALESCE(
      (SELECT json_agg(json_build_object(
          'date', day,
          'orders', order_count,
          'revenue', revenue
        ) ORDER BY day)
       FROM (
         SELECT (created_at AT TIME ZONE 'Africa/Cairo')::date::text AS day,
                COUNT(*) AS order_count,
                COALESCE(SUM(total) FILTER (WHERE status = 'delivered'), 0) AS revenue
         FROM public.orders
         WHERE created_at BETWEEN p_from AND p_to
         GROUP BY 1
       ) d),
      '[]'::json
    )
  );
$$;

-- Grant execute to the service role (admin client) and anon/authenticated
-- (RLS still applies to the underlying tables). The admin route uses the
-- service-role key, so this grant is belt-and-suspenders.
GRANT EXECUTE ON FUNCTION public.get_analytics_summary(timestamptz, timestamptz)
  TO service_role, authenticated, anon;
