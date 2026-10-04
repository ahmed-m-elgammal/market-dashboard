-- Migration 112: Tie an item's category to its own merchant (BUG-03)
--
-- THE BUG
--   items carries BOTH merchant_id and category_id as independent single-column
--   foreign keys (007:50-51). Nothing relates them, so this is accepted:
--
--     -- category belongs to merchant A
--     INSERT INTO categories (merchant_id, ...) VALUES ('A', ...);
--     -- item claims merchant B but is filed under A's category
--     INSERT INTO items (merchant_id, category_id, ...)
--       VALUES ('B', '<A category>', ...);
--
--   VERIFIED: dashborad/test/test_02_catalog_integrity.py
--
--   The damage is asymmetric, which is why it matters:
--
--     * INVISIBLE. The menu query filters merchant_id AND category_id, so a
--       mis-filed item never appears in merchant B's menu. Nobody notices.
--     * STILL ORDERABLE. place_order_with_items resolves items by item_id
--       alone, so a customer who found the item elsewhere can order it, and the
--       order is attributed to merchant B while the menu it came from belongs
--       to A. Revenue lands on the wrong merchant.
--
-- THE FIX
--   A composite foreign key (category_id, merchant_id) -> categories(id,
--   merchant_id). That requires a UNIQUE on categories(id, merchant_id) to
--   reference, which is free: (id) is already the primary key, so every
--   (id, merchant_id) pair is already unique.
--
-- WHY NOT JUST DROP items.merchant_id
--   It would be fewer moving parts, but every read query, index, RPC and
--   dashboard filter in the codebase addresses merchant_id directly -- 7
--   indexes are built on it. Removing the column is a much larger change than
--   adding the constraint, and keeping it means the menu query keeps its
--   composite index. Constraint is the surgical fix.
--
-- DATA PRE-FLIGHT IS A HARD STOP
--   If any item is already mis-filed, this constraint cannot be created. The
--   DO block below reports them by name and raises, rather than silently
--   reassigning a merchant. Reassigning an item's merchant is a business
--   decision, not a migration's.
--
-- Rollback: ALTER TABLE public.items
--             DROP CONSTRAINT items_category_merchant_fk;
--           ALTER TABLE public.categories
--             DROP CONSTRAINT categories_id_merchant_key;

-- =============================================================================
-- 0. PRE-FLIGHT: report and refuse if drift already exists
-- =============================================================================
DO $$
DECLARE
  v_drift INTEGER;
BEGIN
  SELECT count(*) INTO v_drift
    FROM public.items i
    JOIN public.categories c ON c.id = i.category_id
   WHERE i.merchant_id IS DISTINCT FROM c.merchant_id;

  IF v_drift > 0 THEN
    RAISE EXCEPTION
      'BUG-03: % item(s) are filed under a category belonging to a different merchant. This constraint cannot be applied until they are reassigned. Run the diagnostic query in the header of this migration.', v_drift;
  END IF;

  RAISE NOTICE 'migration 112 pre-flight clean: 0 cross-merchant items';
END
$$;

-- Diagnostic for when the pre-flight fires:
--
--   SELECT i.id, i.name_en, i.merchant_id AS item_merchant,
--          c.merchant_id AS category_merchant
--     FROM public.items i
--     JOIN public.categories c ON c.id = i.category_id
--    WHERE i.merchant_id IS DISTINCT FROM c.merchant_id;

-- =============================================================================
-- 1. UNIQUE TARGET FOR THE COMPOSITE FK
-- =============================================================================
-- (id) is already the primary key, so this adds no storage beyond the index
-- and cannot fail on existing data.
ALTER TABLE public.categories
  DROP CONSTRAINT IF EXISTS categories_id_merchant_key;

ALTER TABLE public.categories
  ADD CONSTRAINT categories_id_merchant_key
  UNIQUE (id, merchant_id);

-- =============================================================================
-- 2. THE COMPOSITE FOREIGN KEY
-- =============================================================================
ALTER TABLE public.items
  DROP CONSTRAINT IF EXISTS items_category_merchant_fk;

ALTER TABLE public.items
  ADD CONSTRAINT items_category_merchant_fk
  FOREIGN KEY (category_id, merchant_id)
  REFERENCES public.categories(id, merchant_id)
  ON DELETE CASCADE;

-- =============================================================================
-- 3. KEEP THE ORIGINAL SINGLE-COLUMN FK
-- =============================================================================
-- items_category_id_fkey from 007 stays. On its own it was not enough, but
-- removing it would change nothing functionally (the composite FK implies the
-- reference) and would churn the schema for no gain.

-- =============================================================================
-- 4. DOCUMENTATION
-- =============================================================================
COMMENT ON CONSTRAINT items_category_merchant_fk ON public.items IS
  'BUG-03 (migration 112): enforces that an item''s category belongs to the same merchant as the item. Before this, items.merchant_id and items.category_id were independent FKs and an item could be filed under another merchant''s category -- invisible in that merchant''s menu (the menu query filters both) but still orderable, mis-attributing revenue.';
COMMENT ON CONSTRAINT categories_id_merchant_key ON public.categories IS
  'Referential target for items_category_merchant_fk. Free: (id) is already the primary key.';

-- =============================================================================
-- 5. THE APPLICATION STILL NEEDS TO COOPERATE
-- =============================================================================
-- This constraint fires at INSERT/UPDATE time, so a dashboard that sends a
-- mismatched merchant_id/category_id pair now gets a 23503 instead of a
-- silently wrong row. That is the point. The dashboard should still validate
-- client-side so the user sees a field-level message rather than a constraint
-- name.