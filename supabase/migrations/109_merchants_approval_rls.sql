-- Migration 109: Hide unapproved merchants from public reads (BUG-13)
--
-- THE BUG
--   Migration 103 introduced merchants.approval_status with
--   pending = "new place awaiting Ops", and the dashboard creates new merchants
--   as pending. But merchants default to is_active = TRUE, and the only read
--   policy filters is_active alone:
--
--     CREATE POLICY "merchants_read_active" ON public.merchants
--       FOR SELECT USING (is_active = true);
--
--   So an unapproved vendor is returned to anon -- in the feed, in
--   get_merchant_feed, and in search_catalog -- before a human has approved
--   it. That defeats the entire approval flow 103 was built for.
--
-- VERIFIED
--   dashborad/test/test_06_rls.py::test_pending_approval_merchants_leak_to_anonymous
--   inserts a pending merchant and reads it back as role anon. Count 1 = bug.
--
-- THE FIX
--   Gate on both flags. approval_status is the onboarding gate; is_active
--   remains the runtime kill-switch for approved vendors. Both must pass.
--
-- COMPANION CHANGE
--   merchants_with_open_status (031) filters is_active = TRUE in its own WHERE
--   clause and is what get_merchant_feed reads, so the matview needs the same
--   gate or the feed still leaks pending vendors. Migration 113 rebuilds that
--   view; this migration patches it in place so the leak is closed immediately
--   rather than at 113.
--
-- Rollback: restore the is_active-only policy and refresh the matview.
--           Safe at any time -- tightening a read policy cannot orphan data.

-- =============================================================================
-- 1. RLS POLICY
-- =============================================================================
DROP POLICY IF EXISTS "merchants_read_active" ON public.merchants;

CREATE POLICY "merchants_read_active"
  ON public.merchants
  FOR SELECT
  USING (is_active = TRUE AND approval_status = 'approved');

COMMENT ON POLICY "merchants_read_active" ON public.merchants IS
  'BUG-13 (migration 109): was USING (is_active = true) only, so merchants with approval_status = ''pending'' were publicly readable. Now requires an active AND approved vendor. The admin dashboard is unaffected -- it reads through the service_role client, which bypasses RLS.';

-- =============================================================================
-- 2. MATERIALIZED VIEW (patched in place; 113 rebuilds it properly)
-- =============================================================================
-- Cannot SELECT m.* here: the view's column list is fixed by 031 and the
-- dashboard's feed query addresses those columns by name. So re-create it with
-- the identical shape plus the approval gate, keeping every column, index and
-- grant that 031 established.
DROP MATERIALIZED VIEW IF EXISTS public.merchants_with_open_status;

CREATE MATERIALIZED VIEW public.merchants_with_open_status AS
SELECT
  m.id,
  m.name_ar,
  m.name_en,
  m.category,
  m.logo_url,
  m.cover_url,
  m.description_ar,
  m.description_en,
  m.address,
  m.lat,
  m.lng,
  m.city,
  m.area,
  m.phone,
  m.is_active,
  m.rating,
  m.rating_count,
  m.min_order_amount,
  m.estimated_delivery_minutes,
  m.delivery_fee_override,
  m.commission_pct,
  m.created_at,
  EXISTS (
    SELECT 1 FROM public.operating_hours oh
    WHERE oh.merchant_id = m.id
      AND oh.day_of_week = EXTRACT(ISODOW FROM NOW() AT TIME ZONE 'Africa/Cairo')
      AND oh.is_closed = FALSE
      AND (NOW() AT TIME ZONE 'Africa/Cairo')::TIME >= oh.open_time
      AND (NOW() AT TIME ZONE 'Africa/Cairo')::TIME <  oh.close_time
  ) AS is_currently_open
FROM public.merchants m
WHERE m.is_active = TRUE
  AND m.approval_status = 'approved';

-- Unique index is required for REFRESH ... CONCURRENTLY.
CREATE UNIQUE INDEX idx_merchants_open_status_id
  ON public.merchants_with_open_status(id);

CREATE INDEX idx_merchants_open_status_city_category
  ON public.merchants_with_open_status(city, category);

CREATE INDEX idx_merchants_open_status_open
  ON public.merchants_with_open_status(is_currently_open)
  WHERE is_currently_open = TRUE;

COMMENT ON MATERIALIZED VIEW public.merchants_with_open_status IS
  'BUG-13 (migration 109): WHERE clause gained approval_status = ''approved'' so unapproved vendors cannot enter the public feed via get_merchant_feed. Column list is still the frozen 031 shape -- migration 113 rebuilds it as SELECT m.* so it tracks future column additions.';

-- Grants are not carried over by a re-create.
GRANT SELECT ON public.merchants_with_open_status TO authenticated, anon;

-- =============================================================================
-- 3. THE VIEW IS A SNAPSHOT -- POPULATE IT
-- =============================================================================
-- Unlike a normal view, this one has no WHERE that would zero it: the CREATE
-- above computed and stored rows for every currently-eligible merchant, so no
-- refresh is needed here. It will go stale on the next merchant change until
-- refresh_merchant_open_status() runs, which is pre-existing behaviour.
--
-- Note that CONCURRENTLY cannot be called from inside this migration (each
-- migration is one transaction), so the initial population above used a plain
-- CREATE, which is correct and non-blocking on an empty-to-small table.