-- Migration 120: Dashboard overview RPCs
--
-- WHY
--   The admin dashboard's Overview needs four things that did not exist:
--     1. platform KPIs for a window (revenue, orders, new customers) plus the
--        previous window so the dashboard can show a delta
--     2. a DAILY time series for three of those, to drive the graphs
--     3. trending items by revenue
--     4. the most recent orders
--
--   Everything here is service_role ONLY. The dashboard's Edge Function proxy
--   holds service_role; the browser never does. Existing analytics RPCs
--   (get_merchant_kpis, get_avg_order_value) are granted to anon -- this
--   migration does NOT copy that pattern, because platform-wide revenue is not
--   something an unauthenticated caller should be able to read.
--
-- REVENUE AND ORDER COUNT SHARE ONE DEFINITION
--   Both exclude 'cancelled'. An earlier draft had orders_count include them,
--   on the reasoning that "how many orders came in" is operational. Rejected:
--   two adjacent KPI cards reading different totals from the same orders is
--   confusing, and an operator who spots it stops trusting both. Cancelled
--   orders are not lost -- cancelled_count is reported right beside them, and
--   get_daily_series carries them too under orders_including_cancelled.
--
--   So: revenue and orders_count exclude cancelled and agree with each other.
--   cancelled_count is the escape hatch for anyone who needs the raw count.
--
--   revenue is GROSS ORDER VALUE: pending and in-flight orders are included,
--   cancelled are not. Same definition as 114.
--
-- PERFORMANCE
--   Three supporting indexes, because each of these queries aggregates the whole
--   orders table over a window:
--
--     * orders(created_at)                     -- the daily series
--     * profiles(created_at) WHERE role='customer' -- new customers
--     * order_items(item_id, order_id) already exists (migration 108)
--
--   Without the first two, a 90-day range is a sequential scan of every order
--   ever placed, on a page that loads on every dashboard visit.
--
-- ROLLBACK
--   DROP FUNCTION get_platform_kpis(timestamptz);
--   DROP FUNCTION get_daily_series(timestamptz, timestamptz);
--   DROP FUNCTION get_trending_items(timestamptz, timestamptz, integer);
--   DROP FUNCTION get_recent_orders(integer);
--   DROP INDEX idx_orders_created_at;
--   DROP INDEX idx_profiles_role_created;

-- =============================================================================
-- 1. SUPPORTING INDEXES
-- =============================================================================
-- Existing order indexes all lead with a party column (customer_id,
-- merchant_id) or a partial predicate. None supports a plain time window over
-- the whole table, which is exactly what a platform-wide daily series is.
CREATE INDEX IF NOT EXISTS idx_orders_created_at
  ON public.orders(created_at);

COMMENT ON INDEX public.idx_orders_created_at IS
  'Migration 120: supports the platform-wide daily series (get_daily_series). Every pre-existing orders index leads with customer_id, merchant_id or a partial status predicate, so a date-range aggregate over all orders had no index.';

-- Partial: role='customer' is the overwhelming majority of profiles, but the
-- admin and driver rows are never "new customers", and keeping them out keeps
-- the index small.
CREATE INDEX IF NOT EXISTS idx_profiles_role_created
  ON public.profiles(created_at)
  WHERE role = 'customer';

COMMENT ON INDEX public.idx_profiles_role_created IS
  'Migration 120: counts new customers per day for get_daily_series. Partial on role=''customer'' so admin and driver signups are excluded and the index stays small.';

-- =============================================================================
-- 2. PLATFORM KPIs FOR A WINDOW, WITH THE PREVIOUS WINDOW FOR DELTAS
-- =============================================================================
-- Returns the window's numbers AND the immediately-preceding window of equal
-- length, so the dashboard can render a percentage change without a second
-- round trip. window_days is echoed back so the UI can label the comparison.
--
-- Helper first, because check_function_bodies is on and a SQL function
-- referencing a not-yet-created function fails at CREATE time.
CREATE OR REPLACE FUNCTION public._pct_change(p_now numeric, p_prev numeric)
RETURNS numeric
LANGUAGE sql IMMUTABLE
SET search_path = ''
AS $$
  SELECT CASE
    WHEN p_prev IS NULL OR p_prev = 0 THEN NULL
    ELSE round(((p_now - p_prev) / p_prev) * 100, 1)
  END
$$;

COMMENT ON FUNCTION public._pct_change(numeric, numeric) IS
  'Percentage change, or NULL when the baseline was zero. NULL is deliberate: a dashboard showing "0%" against an empty previous window would read as flat rather than new.';

CREATE OR REPLACE FUNCTION public.get_platform_kpis(p_from timestamptz)
RETURNS json
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
  WITH bounds AS (
    SELECT
      p_from                                             AS win_start,
      NOW()                                               AS win_end,
      GREATEST(EXTRACT(EPOCH FROM (NOW() - p_from)), 1)   AS win_seconds
  ),
  win AS (
    SELECT
      count(*) FILTER (WHERE status <> 'cancelled')                  AS orders_count,
      count(*) FILTER (WHERE status = 'cancelled')                  AS cancelled_count,
      COALESCE(sum(total) FILTER (WHERE status <> 'cancelled'), 0) AS revenue,
      count(DISTINCT customer_id) FILTER (WHERE status <> 'cancelled') AS customers
    FROM public.orders, bounds b
    WHERE created_at >= b.win_start AND created_at < b.win_end
  ),
  prev AS (
    SELECT
      count(*) FILTER (WHERE status <> 'cancelled')                  AS orders_count,
      COALESCE(sum(total) FILTER (WHERE status <> 'cancelled'), 0) AS revenue
    FROM public.orders, bounds b
    WHERE created_at >= b.win_start - make_interval(secs => b.win_seconds)
      AND created_at <  b.win_start
  ),
  cust AS (
    SELECT count(*) AS new_customers
    FROM public.profiles, bounds b
    WHERE role = 'customer'
      AND created_at >= b.win_start AND created_at < b.win_end
  ),
  prev_cust AS (
    SELECT count(*) AS new_customers
    FROM public.profiles, bounds b
    WHERE role = 'customer'
      AND created_at >= b.win_start - make_interval(secs => b.win_seconds)
      AND created_at <  b.win_start
  )
  SELECT json_build_object(
    'window_days',     round(extract(epoch FROM (NOW() - p_from)) / 86400.0)::int,
    'from',            b.win_start,
    'to',              b.win_end,
    'revenue',         w.revenue,
    'orders_count',    w.orders_count,
    'cancelled_count', w.cancelled_count,
    'new_customers',   c.new_customers,
    'active_customers', w.customers,
    'previous', json_build_object(
      'revenue',       p.revenue,
      'orders_count',  p.orders_count,
      'new_customers', pc.new_customers
    ),
    'change', json_build_object(
      'revenue',       public._pct_change(w.revenue, p.revenue),
      'orders_count',  public._pct_change(w.orders_count::numeric, p.orders_count::numeric),
      'new_customers', public._pct_change(c.new_customers::numeric, pc.new_customers::numeric)
    )
  )
  FROM win w, prev p, cust c, prev_cust pc, bounds b;
$$;

COMMENT ON FUNCTION public.get_platform_kpis(timestamptz) IS
  'Migration 120: platform Overview KPIs for [p_from, now), plus the immediately preceding window of equal length so the UI can show deltas without a second query. revenue AND orders_count both exclude cancelled orders so the two cards agree; cancelled_count sits beside them for anyone needing the raw number. change.* is NULL when the previous window was empty rather than 0, because 0% against no baseline reads as flat when the truth is new. service_role only.';

-- =============================================================================
-- 3. DAILY SERIES -- drives the three graphs
-- =============================================================================
-- generate_series fills the gaps. Without it a day with no orders is simply
-- absent from the result and the chart draws a line straight across the gap,
-- which reads as "steady" when it actually means "nothing happened".
--
-- Dates are computed in Africa/Cairo so a day boundary matches the merchant's
-- day, not UTC's.
CREATE OR REPLACE FUNCTION public.get_daily_series(
  p_from timestamptz,
  p_to   timestamptz DEFAULT NULL
)
RETURNS TABLE (
  day                        date,
  revenue                    numeric,
  orders_count               bigint,
  new_customers              bigint,
  cancelled_count            bigint,
  orders_including_cancelled bigint
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
  WITH days AS (
    SELECT d::date AS day
    FROM generate_series(
           (p_from AT TIME ZONE 'Africa/Cairo')::date,
           (COALESCE(p_to, NOW()) AT TIME ZONE 'Africa/Cairo')::date,
           interval '1 day'
         ) AS d
  ),
  order_days AS (
    SELECT
      (created_at AT TIME ZONE 'Africa/Cairo')::date AS day,
      COALESCE(sum(total) FILTER (WHERE status <> 'cancelled'), 0) AS revenue,
      -- matches get_platform_kpis: both exclude cancelled so the cards agree
      count(*) FILTER (WHERE status <> 'cancelled')  AS orders_count,
      count(*) FILTER (WHERE status = 'cancelled')  AS cancelled_count,
      count(*)                                      AS orders_including_cancelled
    FROM public.orders
    WHERE created_at >= p_from
      AND created_at <  COALESCE(p_to, NOW())
    GROUP BY 1
  ),
  customer_days AS (
    SELECT
      (created_at AT TIME ZONE 'Africa/Cairo')::date AS day,
      count(*) AS new_customers
    FROM public.profiles
    WHERE role = 'customer'
      AND created_at >= p_from
      AND created_at <  COALESCE(p_to, NOW())
    GROUP BY 1
  )
  SELECT
    d.day,
    COALESCE(o.revenue, 0),
    COALESCE(o.orders_count, 0),
    COALESCE(c.new_customers, 0),
    COALESCE(o.cancelled_count, 0),
    COALESCE(o.orders_including_cancelled, 0)
  FROM days d
  LEFT JOIN order_days    o ON o.day = d.day
  LEFT JOIN customer_days c ON c.day = d.day
  ORDER BY d.day;
$$;

COMMENT ON FUNCTION get_daily_series(timestamptz, timestamptz) IS
  'Migration 120: one row per calendar day in [p_from, p_to). revenue and orders_count both exclude cancelled, matching get_platform_kpis so the KPI cards and the graphs agree; cancelled_count and orders_including_cancelled are carried alongside for anyone needing the raw numbers. Days with no activity are returned as explicit zeros via generate_series, so a chart does not draw a straight line across a gap and read it as steady. Day boundaries are Africa/Cairo, matching the merchants'' own week. service_role only.';

-- =============================================================================
-- 4. TRENDING ITEMS BY REVENUE
-- =============================================================================
-- DELIVERED orders only. A trending list built on pending orders would promote
-- whatever was abandoned most recently, and one cancelled order should not
-- count as demand.
--
-- Joins items for the current name, but reads quantity and price from
-- order_items -- the frozen snapshot. Otherwise a price edit today would
-- retroactively change what an old order earned.
CREATE OR REPLACE FUNCTION public.get_trending_items(
  p_from   timestamptz,
  p_to     timestamptz DEFAULT NULL,
  p_limit  integer     DEFAULT 10
)
RETURNS TABLE (
  item_id      uuid,
  name_en      text,
  name_ar      text,
  category_id  uuid,
  category_en  text,
  units_sold   bigint,
  revenue      numeric,
  discount_price numeric
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
  SELECT
    i.id,
    i.name_en,
    i.name_ar,
    i.category_id,
    c.name_en,
    sum(oi.quantity)                  AS units_sold,
    sum(oi.total_price)               AS revenue,
    max(i.discount_price)             AS discount_price
  FROM public.order_items oi
  JOIN public.orders    o ON o.id = oi.order_id
  JOIN public.items     i ON i.id = oi.item_id
  LEFT JOIN public.categories c ON c.id = i.category_id
  WHERE o.status = 'delivered'
    AND o.created_at >= p_from
    AND o.created_at <  COALESCE(p_to, NOW())
    -- Soft-deleted items (migration 110) are excluded from merchandising, but
    -- their order lines still exist and still earned revenue. Filter on the
    -- order line's own snapshot instead of the catalog row's liveness.
    AND i.deleted_at IS NULL
  GROUP BY i.id, i.name_en, i.name_ar, i.category_id, c.name_en
  ORDER BY revenue DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 10), 1), 100);
$$;

COMMENT ON FUNCTION get_trending_items(timestamptz, timestamptz, integer) IS
  'Migration 120: top items by revenue from DELIVERED orders in [p_from, p_to). Units and revenue come from the order_items snapshot, not the live catalog, so a price edit today cannot retroactively change what an old order earned. p_limit is clamped to 1..100. service_role only.';

-- =============================================================================
-- 5. RECENT ORDERS
-- =============================================================================
-- Joins customer and merchant names. Both are live references, not snapshots --
-- orders does not freeze the merchant name (008). If a merchant is renamed, old
-- orders display the new name. Accepted: the merchant identity does not change,
-- only its label.
CREATE OR REPLACE FUNCTION public.get_recent_orders(p_limit integer DEFAULT 10)
RETURNS TABLE (
  id             uuid,
  order_number   text,
  status         text,
  total          numeric,
  payment_method text,
  payment_status text,
  created_at     timestamptz,
  customer_id    uuid,
  customer_name  text,
  customer_phone text,
  merchant_id    uuid,
  merchant_name  text,
  merchant_city  text,
  item_count     bigint
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
  SELECT
    o.id,
    o.order_number,
    o.status,
    o.total,
    o.payment_method,
    o.payment_status,
    o.created_at,
    o.customer_id,
    NULLIF(p.full_name, ''),
    p.phone,
    o.merchant_id,
    m.name_en,
    m.city,
    (SELECT count(*) FROM public.order_items oi WHERE oi.order_id = o.id)
  FROM public.orders o
  LEFT JOIN public.profiles  p ON p.id = o.customer_id
  LEFT JOIN public.merchants m ON m.id = o.merchant_id
  ORDER BY o.created_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 10), 1), 100);
$$;

COMMENT ON FUNCTION get_recent_orders(integer) IS
  'Migration 120: newest orders across all merchants with customer and merchant labels and a line count. All statuses included -- an operator wants to see what just came in. Customer name and phone are live from profiles, not snapshots. p_limit clamped to 1..100. service_role only.';

-- =============================================================================
-- 6. GRANTS -- service_role ONLY
-- =============================================================================
-- REVOKE FROM PUBLIC alone is NOT sufficient on Supabase. Supabase's default
-- privileges grant EXECUTE on every function in public to anon and
-- authenticated, so a freshly created function is callable by an
-- unauthenticated client before this migration's REVOKE runs, and stays
-- callable if the project's default privileges are re-applied or altered.
--
-- Hence the explicit per-role revokes. This is the same pattern migration 069
-- uses (REVOKE ... FROM PUBLIC, then GRANT to a single role) hardened for
-- Supabase's defaults.
--
-- These functions expose platform-wide revenue, customer names and customer
-- phone numbers. The dashboard reaches them through the Edge Function proxy,
-- which holds service_role.
REVOKE EXECUTE ON FUNCTION public.get_platform_kpis(timestamptz) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_daily_series(timestamptz, timestamptz) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_trending_items(timestamptz, timestamptz, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_recent_orders(integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._pct_change(numeric, numeric) FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION public.get_platform_kpis(timestamptz) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_daily_series(timestamptz, timestamptz) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_trending_items(timestamptz, timestamptz, integer) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_recent_orders(integer) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._pct_change(numeric, numeric) FROM anon, authenticated;

GRANT EXECUTE ON FUNCTION public.get_platform_kpis(timestamptz) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_daily_series(timestamptz, timestamptz) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_trending_items(timestamptz, timestamptz, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_recent_orders(integer) TO service_role;

-- =============================================================================
-- 7. NOTES FOR THE UI
-- =============================================================================
-- get_platform_kpis -> 4 KPI cards: revenue, orders_count, new_customers,
--   active_customers. change.* gives the percentage; NULL means the previous
--   window was empty, which the UI must render as "new" rather than "0%".
--
-- get_daily_series -> three graphs off one call, same day list, so the lines
--   are comparable. Order the rows by day.
--
-- get_trending_items -> revenue-ranked; units_sold is there for context.
--   discount_price non-NULL means the item is currently on promotion.
--
-- Revenue and orders_count disagree by design (cancelled excluded from the
-- former, included in the latter). Label the cards accordingly.
--
-- =============================================================================
-- 8. BUG-20, RECORDED NOT FIXED
-- =============================================================================
-- get_merchant_kpis and get_merchant_kpis_range are granted to anon (066, 091),
-- so an unauthenticated caller can read any merchant's revenue and order count
-- by guessing a UUID. Not fixed here: tightening an existing grant can break
-- the mobile app, which is outside the dashboard's scope and needs testing I
-- cannot do from this repo.
--
-- Verified as still-open by
-- dashborad/test/test_10_overview_rpcs.py::test_leaked_merchant_kpi_grant_is_recorded_but_not_fixed