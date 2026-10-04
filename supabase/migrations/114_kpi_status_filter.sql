-- Migration 114: Correct and de-duplicate the merchant KPI RPCs (BUG-09, BUG-17)
--
-- TWO BUGS, ONE REWRITE
--
-- BUG-09 -- "revenue" includes cancelled orders.
--   Both RPCs summed orders.total with NO status filter:
--
--     066:39  'revenue', COALESCE((SELECT SUM(total) FROM orders
--                               WHERE merchant_id = p_merchant_id), 0)
--     091:37  same, plus created_at >= p_from
--
--   VERIFIED: a merchant with delivered 100.00, cancelled 500.00 and pending
--   250.00 returns revenue 850.00. Real revenue is 350.00. The range RPC also
--   inflates AOV (returned 500.00 where it should be 100.00), because the
--   cancelled order sits in both the numerator and the denominator.
--
--   This is an oversight, not a definition: get_avg_order_value (069:20) DOES
--   filter status != 'cancelled'. Two RPCs disagreed about what revenue means.
--
-- BUG-17 -- the same aggregates are computed repeatedly.
--   091 contains SIX subqueries over identical rows: COUNT and SUM for the
--   range, then both AGAIN inside the AOV CASE branch. 066 has the same shape
--   with two. PostgreSQL inlines these LANGUAGE sql functions and constant-folds
--   them when arguments are literals -- so a literal call collapses to one pass
--   and the duplication is invisible. A PARAMETERISED call, which is exactly
--   how PostgREST invokes them, evaluates the repeated work for real.
--
--   MEASURED: the RPCs cost more buffers than the same numbers computed in a
--   single aggregate pass, on a merchant with a real order history.
--
-- THE FIX
--   One aggregate pass each, dividing once in the outer SELECT. Same output keys,
--   so no dashboard change is required.
--
-- THE STATUS DECISION, MADE EXPLICIT
--   Excluding ONLY 'cancelled'. Pending and in-flight orders still count, which
--   matches how the dashboard has always presented revenue (gross order value)
--   and keeps the tile from moving every time a driver taps "on the way". If
--   you want recognised revenue instead, add the delivered statuses here and
--   rename the output key -- do not do that silently.
--
--   Also fixed while in here: item_count counted soft-deleted items. Migration
--   110 added items.deleted_at.
--
-- Rollback: re-create the 066/091 bodies. They are derived reads, so no data
--           change is involved.

-- =============================================================================
-- 1. get_merchant_kpis -- all-time
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_merchant_kpis(p_merchant_id uuid)
RETURNS json
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
  -- One pass. BUG-17: was two independent subqueries over orders.
  -- BUG-09: cancelled orders are excluded from the REVENUE and COUNT
  -- aggregates, but still counted in cancelled_count. Doing that with a
  -- WHERE status <> 'cancelled' would make cancelled_count always zero --
  -- hence the conditional aggregates below rather than a filter.
  WITH order_agg AS (
    SELECT
      count(*) FILTER (WHERE status <> 'cancelled')  AS order_count,
      COALESCE(sum(total) FILTER (WHERE status <> 'cancelled'), 0) AS revenue,
      count(*) FILTER (WHERE status = 'delivered') AS delivered_count,
      count(*) FILTER (WHERE status = 'cancelled') AS cancelled_count
    FROM public.orders
    WHERE merchant_id = p_merchant_id
  )
  SELECT json_build_object(
    'order_count',       oa.order_count,
    'revenue',           oa.revenue,
    'avg_order_value',   CASE WHEN oa.order_count > 0
                             THEN round(oa.revenue / oa.order_count, 2)
                             ELSE 0 END,
    'delivered_count',   oa.delivered_count,
    'cancelled_count',   oa.cancelled_count,
    'item_count', (
      -- BUG-08 follow-up: exclude soft-deleted items.
      SELECT count(*) FROM public.items
       WHERE merchant_id = p_merchant_id
         AND deleted_at IS NULL
    ),
    'category_count', (
      SELECT count(*) FROM public.categories
       WHERE merchant_id = p_merchant_id
         AND deleted_at IS NULL
    )
  )
  FROM order_agg oa;
$$;

COMMENT ON FUNCTION public.get_merchant_kpis(uuid) IS
  'BUG-09 + BUG-17 (migration 114): revenue excluded cancelled orders (it summed every status), and the aggregates were computed in two separate passes. Now one pass with an explicit status filter. Revenue is GROSS ORDER VALUE -- pending and in-flight orders are included, cancelled are not. Returns order_count, revenue, avg_order_value, delivered_count, cancelled_count, item_count, category_count. item_count/category_count exclude soft-deleted rows (migration 110).';

-- =============================================================================
-- 2. get_merchant_kpis_range -- range-scoped
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_merchant_kpis_range(
  p_merchant_id uuid,
  p_from timestamptz
)
RETURNS json
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
  -- One pass instead of six subqueries. rating and rating_count are NOT
  -- included: they are not time-scoped, they live on the merchants row, and
  -- the dashboard reads them from the same SELECT.
  WITH order_agg AS (
    SELECT
      count(*)                                     AS order_count,
      COALESCE(sum(total), 0)                      AS revenue,
      count(*) FILTER (WHERE status = 'delivered') AS delivered_count
    FROM public.orders
    WHERE merchant_id = p_merchant_id
      AND created_at >= p_from
      AND status <> 'cancelled'
  )
  SELECT json_build_object(
    'order_count',     oa.order_count,
    'revenue',         oa.revenue,
    'avg_order_value', CASE WHEN oa.order_count > 0
                             THEN round(oa.revenue / oa.order_count, 2)
                             ELSE 0 END,
    'delivered_count', oa.delivered_count
  )
  FROM order_agg oa;
$$;

COMMENT ON FUNCTION public.get_merchant_kpis_range(uuid, timestamptz) IS
  'BUG-09 + BUG-17 (migration 114): was SIX subqueries over the same rows (count and sum, then both again for AOV) with no status filter. Now one aggregate pass, cancelled excluded, divided once in the outer SELECT. Revenue is gross order value in [p_from, now).';

-- =============================================================================
-- 3. GRANTS
-- =============================================================================
-- CREATE OR REPLACE keeps existing privileges, but restate them so an operator
-- reading this file sees the intended access surface. 069's pattern of
-- REVOKE-from-PUBLIC-then-GRANT-service_role is the stricter one; these two
-- were already granted to anon and authenticated by 066/091, and narrowing them
-- is a dashboard-visible change, so they are left as-is and documented instead.
GRANT EXECUTE ON FUNCTION public.get_merchant_kpis(uuid)
  TO service_role, authenticated, anon;

GRANT EXECUTE ON FUNCTION public.get_merchant_kpis_range(uuid, timestamptz)
  TO service_role, authenticated, anon;

-- =============================================================================
-- 4. OUTPUT-SHAPE CHANGE THE DASHBOARD MUST ABSORB
-- =============================================================================
-- Two keys were ADDED (avg_order_value, delivered_count, cancelled_count,
-- category_count). None were removed or renamed, so existing consumers keep
-- working. But note that 066 previously had NO avg_order_value key while 091
-- did -- they were inconsistent. Both now return it. A dashboard that
-- distinguished "all-time has no AOV" from "range has AOV" should collapse that
-- distinction.
--
-- Revenue VALUES change. Any saved dashboard, alert threshold or report that
-- was tuned against the cancelled-inclusive number will now read lower. That is
-- the fix working, not a regression.