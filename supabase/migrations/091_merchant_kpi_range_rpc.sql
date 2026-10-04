-- Migration 091: get_merchant_kpis_range RPC
--
-- Range-scoped KPI aggregation for the merchant detail page (D1).
-- Companion to get_merchant_kpis (migration 066) which is all-time.
--
-- Output shape:
--   {
--     "order_count":     integer,   -- orders in [p_from, now)
--     "revenue":         numeric,   -- sum of orders.total in range
--     "avg_order_value": numeric    -- revenue / order_count (0 if no orders)
--   }
--
-- `item_count` and `rating` are NOT included here — they are not
-- time-scoped (item_count is the current menu size; rating is a live
-- trigger-maintained aggregate on the merchants row). The admin route
-- combines this RPC's output with those two values from the merchant row.
--
-- Security:
--   - SECURITY DEFINER, SET search_path = '' (matches migration 066)
--   - STABLE: reads only

CREATE OR REPLACE FUNCTION public.get_merchant_kpis_range(
  p_merchant_id uuid,
  p_from timestamptz
)
RETURNS json
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT json_build_object(
    'order_count', (
      SELECT COUNT(*) FROM public.orders
      WHERE merchant_id = p_merchant_id
        AND created_at >= p_from
    ),
    'revenue', COALESCE((
      SELECT SUM(total) FROM public.orders
      WHERE merchant_id = p_merchant_id
        AND created_at >= p_from
    ), 0),
    'avg_order_value', CASE
      WHEN (
        SELECT COUNT(*) FROM public.orders
        WHERE merchant_id = p_merchant_id
          AND created_at >= p_from
      ) > 0
      THEN ROUND((
        SELECT COALESCE(SUM(total), 0) FROM public.orders
        WHERE merchant_id = p_merchant_id
          AND created_at >= p_from
      )::numeric / (
        SELECT COUNT(*) FROM public.orders
        WHERE merchant_id = p_merchant_id
          AND created_at >= p_from
      ), 2)
      ELSE 0
    END
  );
$$;

GRANT EXECUTE ON FUNCTION public.get_merchant_kpis_range(uuid, timestamptz)
  TO service_role, authenticated, anon;
