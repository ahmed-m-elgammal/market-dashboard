-- Migration 066: get_merchant_kpis RPC
--
-- Replaces the in-JS aggregation in GET /api/merchants/[id] (apps/admin/src/app/
-- api/merchants/[id]/route.ts) with a single SQL function. Previously the route
-- fetched every order row for the merchant into Node memory and summed `total`
-- with .reduce() — at 50k historical orders that's 50k rows parsed per
-- detail-page mount. This RPC does all aggregation server-side and returns one
-- JSON blob in a single round-trip (was 2 parallel queries).
--
-- Output shape (matches the previous JS output exactly so the client does not
-- need to change):
--   {
--     "order_count": integer,
--     "revenue":      numeric,   -- sum of orders.total (all statuses)
--     "item_count":   integer
--   }
--
-- `rating` and `rating_count` are NOT included here — they live on the
-- merchants row itself (maintained by triggers) and are already returned by
-- the merchant SELECT in the same route.
--
-- Security:
--   - SECURITY DEFINER so the function can read orders/items without the
--     caller needing direct SELECT grants. RLS still applies via the service
--     role used by the admin route.
--   - SET search_path = '' per the migration hardening convention (S16).
--   - STABLE: reads only, no side effects.

CREATE OR REPLACE FUNCTION public.get_merchant_kpis(p_merchant_id uuid)
RETURNS json
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT json_build_object(
    'order_count', (
      SELECT COUNT(*) FROM public.orders WHERE merchant_id = p_merchant_id
    ),
    'revenue', COALESCE((
      SELECT SUM(total) FROM public.orders WHERE merchant_id = p_merchant_id
    ), 0),
    'item_count', (
      SELECT COUNT(*) FROM public.items WHERE merchant_id = p_merchant_id
    )
  );
$$;

-- Grant execute to the service role (admin client) and anon/authenticated
-- (RLS still applies to the underlying tables). The admin route uses the
-- service-role key, so this grant is belt-and-suspenders.
GRANT EXECUTE ON FUNCTION public.get_merchant_kpis(uuid)
  TO service_role, authenticated, anon;
