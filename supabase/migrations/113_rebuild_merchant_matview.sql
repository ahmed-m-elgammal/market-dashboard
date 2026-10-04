-- Migration 113: Rebuild merchants_with_open_status so it tracks merchants (BUG-11)
--
-- THE BUG
--   Migration 031 created this materialized view with an EXPLICIT 19-column
--   list and never recreated it. Every column added to merchants afterwards is
--   therefore invisible to it:
--
--     042  delivery_radius_km, estimated_prep_time_minutes
--     085  payout_frequency, payout_method, bank_account_holder,
--          bank_account_number, bank_name, wallet_phone
--     103  approval_status, approval_note
--
--   Ten columns, all absent. The dashboard consequences:
--     * no approval_status, so the approval queue CANNOT be built from this
--       view at all
--     * no delivery_radius_km, so a merchant detail page routed through the
--       feed cannot show delivery reach
--
--   Verified by column-by-column diff:
--   dashborad/test/test_07_reporting.py::test_matview_is_missing_every_column_added_after_031
--
-- THE FIX
--   Recreate as SELECT m.*, <open status>. Using m.* means future columns are
--   picked up automatically -- the class of bug cannot recur. The open-status
--   expression stays explicit because it is derived, not a merchants column.
--
-- WHY THIS IS SAFE TO DO NOW
--   get_merchant_feed (031:98) reads this view and addresses its columns by
--   name. It is LANGUAGE plpgsql, so PostgreSQL does not parse its body at
--   creation time and holds no dependency -- the DROP cannot be blocked by it.
--   Every column that function selects (id, name_ar/en, category, logo_url,
--   cover_url, city, area, lat, lng, rating, rating_count, min_order_amount,
--   estimated_delivery_minutes, delivery_fee_override, is_currently_open)
--   exists in m.*, so the function keeps working unchanged.
--
--   Migration 109 already re-created this view with the approval gate; this
--   migration does it properly.
--
-- Rollback: re-create with 031's explicit column list minus the 109 gate. The
--           view is derived data, so nothing is lost -- only rebuild it.

-- =============================================================================
-- 1. DROP
-- =============================================================================
DROP MATERIALIZED VIEW IF EXISTS public.merchants_with_open_status;

-- =============================================================================
-- 2. REBUILD AS m.*
-- =============================================================================
CREATE MATERIALIZED VIEW public.merchants_with_open_status AS
SELECT
  m.*,
  -- Derived, so it cannot come from m.*. Batched as a single EXISTS rather
  -- than calling is_merchant_open() per row: 031 documented that per-row calls
  -- cost ~400ms for 200 merchants versus ~5ms for one EXISTS.
  EXISTS (
    SELECT 1
      FROM public.operating_hours oh
     WHERE oh.merchant_id = m.id
       AND oh.day_of_week = EXTRACT(ISODOW FROM NOW() AT TIME ZONE 'Africa/Cairo')
       AND oh.is_closed = FALSE
       AND (NOW() AT TIME ZONE 'Africa/Cairo')::TIME >= oh.open_time
       AND (NOW() AT TIME ZONE 'Africa/Cairo')::TIME <  oh.close_time
  ) AS is_currently_open
FROM public.merchants m
WHERE m.is_active = TRUE
  AND m.approval_status = 'approved';

-- =============================================================================
-- 3. INDEXES
-- =============================================================================
-- The UNIQUE index is mandatory, not cosmetic: REFRESH ... CONCURRENTLY fails
-- without one.
CREATE UNIQUE INDEX idx_merchants_open_status_id
  ON public.merchants_with_open_status(id);

CREATE INDEX idx_merchants_open_status_city_category
  ON public.merchants_with_open_status(city, category);

CREATE INDEX idx_merchants_open_status_open
  ON public.merchants_with_open_status(is_currently_open)
  WHERE is_currently_open = TRUE;

-- =============================================================================
-- 4. GRANTS -- a re-create does not carry them over
-- =============================================================================
GRANT SELECT ON public.merchants_with_open_status TO authenticated, anon;

-- =============================================================================
-- 5. DOCUMENTATION
-- =============================================================================
COMMENT ON MATERIALIZED VIEW public.merchants_with_open_status IS
  'BUG-11 (migration 113): rebuilt as SELECT m.* + derived is_currently_open, so it no longer silently omits columns added to merchants after 031 (it was missing 10, including approval_status and delivery_radius_km). Mirrors merchants.is_active AND approval_status = ''approved'' per migration 109. SNAPSHOT: nothing refreshes it automatically -- call public.refresh_merchant_open_status() out of band, which cannot run inside a migration transaction. For live data the dashboard should query merchants directly; this view exists for feed-grade open/closed display.';

COMMENT ON FUNCTION public.refresh_merchant_open_status() IS
  'Concurrently refreshes merchants_with_open_status. Safe to call while reads happen. CANNOT run inside a transaction block, so it cannot be called from a migration -- Supabase wraps each migration in one. (Migration 098 claimed otherwise; verified wrong on PostgreSQL 18.)';