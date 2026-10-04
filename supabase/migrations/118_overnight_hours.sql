-- Migration 118: Support overnight operating hours (BUG-02)
--
-- THE BUG
--   The open window is evaluated as:
--
--     (now) >= open_time AND (now) < close_time
--
--   which cannot represent a window that crosses midnight. A merchant open
--   22:00 -> 02:00 matches nothing after midnight, because 01:00 < 02:00 is
--   true but 01:00 >= 22:00 is false.
--
--   VERIFIED:
--   dashborad/test/test_01_operating_hours.py::test_overnight_window_never_matches
--
--   This is not hypothetical: seed.sql:125 already writes
--   close_time = '01:00' for Thursday and Friday. Those rows have never worked.
--
--   The 24-hour case does NOT need this: 00:00 -> 24:00 works today, because
--   PostgreSQL TIME accepts 24:00:00 and `now < 24:00` is always true. Verified.
--
-- THE FIX
--   is_overnight flag, interpreted as: the window runs from open_time on
--   day_of_week to close_time on day_of_week + 1.
--
--   Deliberately a flag rather than split shift rows, because split rows would
--   break the UNIQUE (merchant_id, day_of_week) constraint that 006 established
--   and that the dashboard's 7-row-per-merchant form depends on.
--
--   A day is open if EITHER the same-day window contains now, OR the previous
--   day's overnight window is still running. Both are evaluated, because a
--   merchant can have an overnight Friday window that is still open at 01:00 on
--   Saturday.
--
-- ORDERING CONSTRAINT
--   Depends on migration 107 (day_of_week is ISO 1..7), so "the previous day"
--   is day_of_week - 1, wrapping 1 -> 7.
--
-- Rollback: the is_overnight rows become daytime rows again. Set
--           is_overnight = false first if any overnight window exists and you
--           are content to have those hours stop applying, then drop the column.

-- =============================================================================
-- 1. THE FLAG
-- =============================================================================
ALTER TABLE public.operating_hours
  ADD COLUMN IF NOT EXISTS is_overnight BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN public.operating_hours.is_overnight IS
  'BUG-02 (migration 118): TRUE means the window runs from open_time on this day_of_week to close_time on the NEXT day, so 22:00 -> 02:00 works. Without it the check `now >= open_time AND now < close_time` can never match after midnight. Defaults FALSE, so all existing rows keep their current meaning. A 24-hour merchant does NOT need this: 00:00 -> 24:00 already works.';

-- =============================================================================
-- 2. PRE-FLIGHT: report windows that were already trying to be overnight
-- =============================================================================
DO $$
DECLARE
  v_suspect INTEGER;
BEGIN
  -- close_time earlier than open_time is the only way this was previously
  -- expressible, and it never worked.
  SELECT count(*) INTO v_suspect
    FROM public.operating_hours
   WHERE NOT is_closed AND close_time <= open_time;

  IF v_suspect > 0 THEN
    RAISE NOTICE
      'migration 118: % row(s) have close_time <= open_time. These were dead windows before this migration. Setting is_overnight = true so they start working -- review the list first if the intent was not an overnight shift:', v_suspect;
  END IF;
END
$$;

-- Promote them. close_time <= open_time is unambiguous: no daytime window can
-- end before it starts, so the only possible intent was an overnight shift.
UPDATE public.operating_hours
   SET is_overnight = TRUE
 WHERE NOT is_closed
   AND close_time <= open_time
   AND is_overnight = FALSE;

-- =============================================================================
-- 3. REWRITE is_merchant_open
-- =============================================================================
-- Two branches, both required:
--   SAME DAY   -- today's window contains now
--   CARRY OVER -- yesterday's overnight window is still running
CREATE OR REPLACE FUNCTION public.is_merchant_open(p_merchant_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_isodow   INTEGER;
  v_now      TIME;
BEGIN
  v_isodow := EXTRACT(ISODOW FROM NOW() AT TIME ZONE 'Africa/Cairo')::INTEGER;
  v_now    := (NOW() AT TIME ZONE 'Africa/Cairo')::TIME;

  RETURN EXISTS (
    SELECT 1
      FROM public.operating_hours oh
     WHERE oh.merchant_id = p_merchant_id
       AND NOT oh.is_closed
       AND (
         -- Same-day window: today's row, not overnight, now is inside it.
         (
           NOT oh.is_overnight
           AND oh.day_of_week = v_isodow
           AND v_now >= oh.open_time
           AND v_now <  oh.close_time
         )
         OR
         -- Carry-over: YESTERDAY was an overnight window that has not closed yet.
         -- day_of_week - 1 with 1 -> 7 wrap (ISO Monday..Sunday).
         (
           oh.is_overnight
           AND oh.day_of_week = CASE WHEN v_isodow = 1 THEN 7 ELSE v_isodow - 1 END
           AND v_now <  oh.close_time
         )
       )
  );
END;
$$;

COMMENT ON FUNCTION public.is_merchant_open(UUID) IS
  'BUG-02 (migration 118): now also honours overnight windows. A merchant is open if the current time falls inside today''s daytime window, OR inside yesterday''s overnight window that has not closed yet. day_of_week is ISO (1=Mon..7=Sun, per migration 107). Single-merchant lookups only -- for feed queries use the merchants_with_open_status materialized view, whose EXISTS form is far cheaper than a per-row call.';

-- =============================================================================
-- 4. REBUILD THE MATERIALIZED VIEW TO MATCH
-- =============================================================================
-- The view embeds the same predicate as the function. If only the function
-- changes, an overnight merchant still shows closed in the feed.
DROP MATERIALIZED VIEW IF EXISTS public.merchants_with_open_status;

CREATE MATERIALIZED VIEW public.merchants_with_open_status AS
SELECT
  m.*,
  EXISTS (
    SELECT 1
      FROM public.operating_hours oh
     WHERE oh.merchant_id = m.id
       AND NOT oh.is_closed
       AND (
         (
           NOT oh.is_overnight
           AND oh.day_of_week = EXTRACT(ISODOW FROM NOW() AT TIME ZONE 'Africa/Cairo')
           AND (NOW() AT TIME ZONE 'Africa/Cairo')::TIME >= oh.open_time
           AND (NOW() AT TIME ZONE 'Africa/Cairo')::TIME <  oh.close_time
         )
         OR
         (
           oh.is_overnight
           AND oh.day_of_week = CASE
             WHEN EXTRACT(ISODOW FROM NOW() AT TIME ZONE 'Africa/Cairo')::INTEGER = 1 THEN 7
             ELSE EXTRACT(ISODOW FROM NOW() AT TIME ZONE 'Africa/Cairo')::INTEGER - 1
           END
           AND (NOW() AT TIME ZONE 'Africa/Cairo')::TIME < oh.close_time
         )
       )
  ) AS is_currently_open
FROM public.merchants m
WHERE m.is_active = TRUE
  AND m.approval_status = 'approved';

CREATE UNIQUE INDEX idx_merchants_open_status_id
  ON public.merchants_with_open_status(id);

CREATE INDEX idx_merchants_open_status_city_category
  ON public.merchants_with_open_status(city, category);

CREATE INDEX idx_merchants_open_status_open
  ON public.merchants_with_open_status(is_currently_open)
  WHERE is_currently_open = TRUE;

GRANT SELECT ON public.merchants_with_open_status TO authenticated, anon;

COMMENT ON MATERIALIZED VIEW public.merchants_with_open_status IS
  'Active AND approved merchants with pre-computed is_currently_open, honouring overnight windows (migration 118). Mirrors is_merchant_open() exactly -- keep the two predicates in step. SNAPSHOT: nothing refreshes it automatically; call public.refresh_merchant_open_status() out of band.';

-- =============================================================================
-- 5. THE DASHBOARD FORM STILL NEEDS A TOGGLE
-- =============================================================================
-- No UI can set is_overnight until the merchant edit form exposes it. That is
-- application work, listed here so the migration is not mistaken for the
-- complete feature:
--
--   apps/admin  merchant hours editor -- add an "closes next day" checkbox
--                next to open_time / close_time, and label the row with the
--                day the window OPENS.
--
-- A merchant open Fri 22:00 -> Sat 02:00 is stored on FRIDAY's row with
-- is_overnight = true. Labelling it "Saturday" would be the natural mistake,
-- because that is when it closes.
--
-- Until the form ships, overnight hours are settable only by direct SQL:
--   UPDATE operating_hours SET is_overnight = true
--    WHERE merchant_id = '<uuid>' AND day_of_week = 5;