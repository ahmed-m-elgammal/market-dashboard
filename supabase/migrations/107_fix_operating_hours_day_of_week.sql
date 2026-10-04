-- Migration 107: Align operating_hours.day_of_week with ISO (BUG-01)
--
-- THE BUG
--   The column is documented and constrained as 0=Sunday..6=Saturday
--   (006:18, "Egyptian week"), but BOTH readers compare it against
--   EXTRACT(ISODOW ...), which is 1=Monday..7=Sunday:
--
--     017:248   is_merchant_open()   AND day_of_week = v_current_day
--     031:51    merchants_with_open_status  AND oh.day_of_week = EXTRACT(ISODOW ...)
--
--   Monday..Saturday coincide by accident. Sunday does not: it is stored as 0
--   but looked up as 7, and 7 is outside CHECK (day_of_week BETWEEN 0 AND 6),
--   so no such row can exist. Every merchant reads CLOSED on Sunday, and
--   get_merchant_feed sorts them into the closed bucket.
--
-- WHY MIGRATE THE DATA RATHER THAN CHANGE THE CALLERS
--   ISODOW is the right convention: it is what Postgres produces, it is what
--   both readers already use, and the alternative (EXTRACT(DOW)+1) would mean
--   editing a plpgsql body plus a materialized view to express the same thing.
--   Two readers, one writer -- change the writer.
--
--   Note the backfill is NOT a uniform +1. Stored 1..6 already equal ISODOW
--   1..6; only Sunday moves, 0 -> 7.
--
-- IMPACT OF THIS MIGRATION
--   Existing rows are rewritten in place. Every merchant that had a Sunday
--   schedule gains an open Sunday; merchants with no Sunday row stay closed.
--   There is no data loss -- a merchant either had a Sunday row (which becomes
--   visible) or did not (unchanged).
--
-- Rollback: UPDATE operating_hours SET day_of_week = 0 WHERE day_of_week = 7;
--           then restore the 0..6 CHECK and the 006 column comment.
--           Valid only while no merchant has a real Sunday schedule.

-- =============================================================================
-- 1. PRE-FLIGHT: report the distribution BEFORE changing anything
-- =============================================================================
DO $$
DECLARE
  v_sunday_rows INTEGER;
  v_total       INTEGER;
BEGIN
  SELECT count(*) INTO v_total FROM public.operating_hours;
  SELECT count(*) INTO v_sunday_rows
    FROM public.operating_hours WHERE day_of_week = 0;

  RAISE NOTICE 'operating_hours: % total rows, % on day_of_week=0 (Sunday)', v_total, v_sunday_rows;

  IF v_sunday_rows > 0 THEN
    RAISE NOTICE 'Sunday rows will move to day_of_week=7 and become visible to is_merchant_open()';
  END IF;
END
$$;

-- =============================================================================
-- 2. CONSTRAINT: widen to 1..7 (ISO) BEFORE backfilling
-- =============================================================================
-- ORDER MATTERS. This must precede step 3.
--
--   Migration 006 created CHECK (day_of_week BETWEEN 0 AND 6). A plain
--   UPDATE ... SET day_of_week = 7 evaluates that CHECK per row, so writing
--   Sunday as 7 raises SQLSTATE 23514 and the whole migration rolls back.
--
--   Production has 2 rows on day_of_week = 0, so this was not theoretical:
--   the first db push failed here and rolled back cleanly at version 106.
--
--   The local harness did not catch it because seed data is inserted AFTER the
--   migrations run, so local operating_hours only ever contained 1..7 and no
--   row could violate the old constraint. Local replay proves schema shape, not
--   that a backfill is safe against pre-existing data.
--
--   There is a brief window inside this transaction where the column has no
--   range check. That is acceptable: the transaction is atomic, so no other
--   session ever observes the table in that state.
ALTER TABLE public.operating_hours
  DROP CONSTRAINT IF EXISTS operating_hours_day_of_week_check;

-- =============================================================================
-- 3. BACKFILL: Sunday 0 -> 7
-- =============================================================================
UPDATE public.operating_hours
   SET day_of_week = 7
 WHERE day_of_week = 0;

-- Re-assert the ISO range now that every row is inside it.
ALTER TABLE public.operating_hours
  ADD CONSTRAINT operating_hours_day_of_week_check
  CHECK (day_of_week BETWEEN 1 AND 7);

-- =============================================================================
-- 4. COMMENTS
-- =============================================================================
COMMENT ON COLUMN public.operating_hours.day_of_week IS
  'ISO day of week: 1=Monday .. 7=Sunday. Migrated from the 006 convention (0=Sunday..6=Saturday) in migration 107, because both readers -- is_merchant_open() (017) and merchants_with_open_status (031) -- already compared this column against EXTRACT(ISODOW ...), making Sunday unreachable. Do not reintroduce a 0-based convention; use EXTRACT(ISODOW ...).';

COMMENT ON TABLE public.operating_hours IS
  'Per-day operating schedule for merchants, ISO day-of-week (1=Mon..7=Sun). Used by is_merchant_open() and the merchants_with_open_status materialized view. Migration 107 realigned the stored values with EXTRACT(ISODOW); before that, Sunday was permanently unreachable.';

-- =============================================================================
-- 5. REFRESH THE MATERIALIZED VIEW
-- =============================================================================
-- The view recomputes is_currently_open from operating_hours on every refresh,
-- so it must be refreshed for Sunday merchants to appear open. CONCURRENTLY
-- cannot run inside a transaction block, but Supabase wraps each migration in
-- one -- so the refresh is deliberately NOT called here. Migration 113 rebuilds
-- this view; until then, run refresh_merchant_open_status() out-of-band after
-- deploying this migration.