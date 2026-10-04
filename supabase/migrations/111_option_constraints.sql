-- Migration 111: Option group integrity + price reductions (BUG-04/05/06/07)
--
-- Four separate gaps in how "size" and modifiers are modelled. All in the
-- item_options / item_option_choices pair, all reachable from the dashboard's
-- item editor with no validation in between.
--
-- BUG-04  Cardinality is unconstrained.
--   min_selections = 5 with max_selections = 2 satisfies every existing CHECK
--   and is unsatisfiable. is_required = TRUE with min_selections = 0, and
--   is_required = FALSE with min_selections = 3, are both contradictory and
--   both accepted. No CHECK relates min_selections to max_selections.
--
-- BUG-05  Every choice in a group can be is_default.
--   item_option_choices has NO unique index at all, so a single-select group
--   (max_selections = 1, the Size pattern) can have three simultaneous
--   defaults and the UI cannot decide what to pre-select.
--
-- BUG-06  price_modifier CHECK (>= 0) makes price REDUCTIONS impossible.
--   A "-5.00 EGP" option is rejected by Postgres. Reductions are a confirmed
--   product requirement, and no amount of dashboard work works around a
--   schema-level block.
--
-- BUG-07  A sold-out choice can be the pre-selected default.
--   is_default = TRUE with is_available = FALSE is accepted, so the customer
--   UI would pre-select something they cannot order.
--
-- VERIFIED: dashborad/test/test_03_options.py (11 tests) reproduces all four.
--
-- DATA PRE-FLIGHT IS DELIBERATE
--   The constraints below can only be added if existing data already satisfies
--   them. Rather than trust that, section 0 measures every violation and RAISEs
--   with the count, so a violation surfaces as a named, actionable migration
--   failure instead of an opaque constraint-creation error three statements
--   later -- and so nothing is silently repaired.
--
-- Rollback: see the tail of each section.

-- =============================================================================
-- 0. PRE-FLIGHT: measure every violation, then refuse to continue if any exist
-- =============================================================================
DO $$
DECLARE
  v_min_gt_max   INTEGER;
  v_req_zero_min INTEGER;
  v_multi_default INTEGER;
  v_default_unavailable INTEGER;
BEGIN
  SELECT count(*) INTO v_min_gt_max
    FROM public.item_options
   WHERE max_selections IS NOT NULL AND min_selections > max_selections;

  SELECT count(*) INTO v_req_zero_min
    FROM public.item_options
   WHERE is_required AND min_selections < 1;

  SELECT count(*) INTO v_multi_default
    FROM (
      SELECT option_id FROM public.item_option_choices
       WHERE is_default
       GROUP BY option_id HAVING count(*) > 1
    ) d;

  SELECT count(*) INTO v_default_unavailable
    FROM public.item_option_choices
   WHERE is_default AND NOT is_available;

  IF v_min_gt_max > 0 THEN
    RAISE EXCEPTION
      'BUG-04: % item_options row(s) have min_selections > max_selections. Fix before applying migration 111.', v_min_gt_max;
  END IF;
  IF v_req_zero_min > 0 THEN
    RAISE EXCEPTION
      'BUG-04: % item_options row(s) are is_required with min_selections < 1. Fix before applying migration 111.', v_req_zero_min;
  END IF;
  IF v_multi_default > 0 THEN
    RAISE EXCEPTION
      'BUG-05: % option group(s) have more than one default choice. Keep the lowest sort_order and unset the rest before applying migration 111.', v_multi_default;
  END IF;
  IF v_default_unavailable > 0 THEN
    RAISE EXCEPTION
      'BUG-07: % choice(s) are is_default AND is_available = false. Unset the default or restock before applying migration 111.', v_default_unavailable;
  END IF;

  RAISE NOTICE
    'migration 111 pre-flight clean (min>max=0, required-zero-min=0, multi-default=0, default-unavailable=0)';
END
$$;

-- =============================================================================
-- 1. BUG-06 -- allow negative price modifiers
-- =============================================================================
-- The bound below is deliberately generous. The meaningful invariant is
-- "a modifier must not exceed the item's base price", which spans two tables
-- and so cannot be a column CHECK -- it is enforced in place_order_with_items
-- (migration 117) where the base price is in hand.
ALTER TABLE public.item_option_choices
  DROP CONSTRAINT IF EXISTS item_option_choices_price_modifier_check;

ALTER TABLE public.item_option_choices
  ADD CONSTRAINT item_option_choices_price_modifier_check
  CHECK (price_modifier >= -1000000);

COMMENT ON COLUMN public.item_option_choices.price_modifier IS
  'EGP delta added to items.price when this choice is selected. MAY BE NEGATIVE since migration 111 -- a "-5.00 EGP" smaller size is now storable. Previously CHECK (>= 0) blocked every reduction. Absolute floor is -1,000,000; the real guard (modifier must not exceed the item base price) lives in place_order_with_items.';

-- =============================================================================
-- 2. BUG-04 -- selection cardinality
-- =============================================================================
-- Note the existing max_selections CHECK (007:111) is left in place; only the
-- missing cross-column relation is added.
ALTER TABLE public.item_options
  DROP CONSTRAINT IF EXISTS item_options_selection_bounds_check;

ALTER TABLE public.item_options
  ADD CONSTRAINT item_options_selection_bounds_check
  CHECK (
    max_selections IS NULL
    OR (min_selections >= 0 AND min_selections <= max_selections)
  );

ALTER TABLE public.item_options
  DROP CONSTRAINT IF EXISTS item_options_required_min_check;

ALTER TABLE public.item_options
  ADD CONSTRAINT item_options_required_min_check
  CHECK (NOT is_required OR min_selections >= 1);

COMMENT ON COLUMN public.item_options.min_selections IS
  'Minimum choices the customer must pick. Must be <= max_selections (migration 111) and >= 1 when is_required (migration 111).';
COMMENT ON COLUMN public.item_options.max_selections IS
  'Maximum choices: NULL = unlimited, 1 = single-select (the Size pattern), >1 = multi-select with a cap. min_selections must not exceed it.';

-- =============================================================================
-- 3. BUG-05 -- at most one default per option group
-- =============================================================================
-- Partial, because is_default = FALSE is the common case and must not be
-- uniqueness-constrained.
CREATE UNIQUE INDEX IF NOT EXISTS idx_item_option_choices_one_default
  ON public.item_option_choices(option_id)
  WHERE is_default;

COMMENT ON INDEX public.idx_item_option_choices_one_default IS
  'BUG-05 (migration 111): at most one default choice per option group. Without this, a single-select group could have several defaults and the customer UI had no deterministic pre-selection.';

-- =============================================================================
-- 4. BUG-07 -- a default choice must be available
-- =============================================================================
-- Cannot be a CHECK: it spans two columns of the SAME row, so it could be --
-- but the useful version is "a group must not default to a sold-out choice",
-- which also spans rows. A trigger covers both without a second round trip.
CREATE OR REPLACE FUNCTION public.guard_default_choice_available()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.is_default AND NOT NEW.is_available THEN
    RAISE EXCEPTION
      'choice % cannot be both default and unavailable: a sold-out choice must not be pre-selected',
      NEW.id
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.guard_default_choice_available() IS
  'BUG-07 (migration 111): rejects is_default = TRUE combined with is_available = FALSE. The customer menu pre-selects the default, so defaulting to a sold-out choice shows an unorderable option as chosen.';

DROP TRIGGER IF EXISTS trg_guard_default_choice_available ON public.item_option_choices;

CREATE TRIGGER trg_guard_default_choice_available
  BEFORE INSERT OR UPDATE ON public.item_option_choices
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_default_choice_available();

-- =============================================================================
-- 5. ROLLBACK
-- =============================================================================
--   DROP INDEX public.idx_item_option_choices_one_default;
--   DROP TRIGGER trg_guard_default_choice_available ON public.item_option_choices;
--   DROP FUNCTION public.guard_default_choice_available();
--   ALTER TABLE public.item_option_choices
--     DROP CONSTRAINT item_option_choices_price_modifier_check,
--     ADD CONSTRAINT item_option_choices_price_modifier_check
--       CHECK (price_modifier >= 0);
--   ALTER TABLE public.item_options
--     DROP CONSTRAINT item_options_selection_bounds_check,
--     DROP CONSTRAINT item_options_required_min_check;