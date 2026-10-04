-- Migration 110: Soft delete for the menu catalog (BUG-08)
--
-- THE BUG
--   items and categories have no deleted_at column. Migration 068 added soft
--   delete to promo_codes and promoted_slots but never to the menu, and
--   order_items.item_id is ON DELETE CASCADE (007:105). So a hard DELETE of a
--   menu item silently erases every order line that referenced it:
--
--     1. merchant -> category -> item -> order -> order_items line
--     2. DELETE FROM items WHERE id = ...
--     3. the order_items row is GONE (cascade)
--     4. the orders row SURVIVES, still saying total = 45.00
--     5. SUM(order_items.total_price) for that order is now 0.00
--
--   The dashboard therefore cannot offer a Delete button on an item or
--   category without permanently losing revenue history, the "top items"
--   report, and the review-to-item trail. categories is worse: it cascades one
--   level higher, taking every item in it.
--
-- VERIFIED
--   dashborad/test/test_05_data_loss.py (5 tests) reproduces steps 1-5 and the
--   unreconcilable-order second-order effect.
--
-- THE FIX
--   1. deleted_at on items and categories, with partial indexes matching the
--      pattern 068 established.
--   2. order_items.item_id becomes NULLABLE with ON DELETE SET NULL, so even a
--      hard delete preserves the frozen name/price snapshot the row already
--      carries. The order line survives; only the link back to the (now gone)
--      catalog entry is lost, which is exactly the intent.
--   3. Read-side queries are NOT rewritten here. There are too many call sites
--      across the Edge Functions and the dashboard for one migration to catch
--      safely, so each is listed below as a required follow-up. This is the
--      risky part of the change and is called out rather than hidden.
--
-- ORDERING CONSTRAINT
--   Requires migration 108. Without idx_order_items_item, switching this FK to
--   SET NULL replaces a 2.6x-slow cascade with a differently-slow probe.
--
-- Rollback:
--   Set deleted_at = NULL on all rows, drop the columns, restore
--   order_items.item_id to NOT NULL + ON DELETE CASCADE. Only safe while no
--   hard delete has happened and no item_id has been nulled.

-- =============================================================================
-- 1. SOFT-DELETE COLUMNS
-- =============================================================================
ALTER TABLE public.items
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

ALTER TABLE public.categories
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- Partial index: every default read already filters `WHERE deleted_at IS NULL`,
-- so a full index would be wasted space on live rows.
CREATE INDEX IF NOT EXISTS idx_items_deleted_at
  ON public.items(deleted_at) WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_categories_deleted_at
  ON public.categories(deleted_at) WHERE deleted_at IS NULL;

COMMENT ON COLUMN public.items.deleted_at IS
  'BUG-08 (migration 110): soft-delete timestamp. NULL = live. The dashboard soft-deletes instead of DELETEing, because order_items.item_id used to cascade and erase order history.';
COMMENT ON COLUMN public.categories.deleted_at IS
  'BUG-08 (migration 110): soft-delete timestamp. NULL = live. Soft-deleting a category hides it and its items from menus; it does not remove rows.';

-- =============================================================================
-- 2. ORDER HISTORY MUST SURVIVE A HARD DELETE
-- =============================================================================
-- order_items already carries frozen copies (item_name_ar/en, item_price,
-- selected_options, total_price) precisely so history survives catalog edits.
-- The cascade was throwing that safety away. SET NULL keeps the snapshot and
-- drops only the pointer.
ALTER TABLE public.order_items
  DROP CONSTRAINT IF EXISTS order_items_item_id_fkey;

ALTER TABLE public.order_items
  ALTER COLUMN item_id DROP NOT NULL;

ALTER TABLE public.order_items
  ADD CONSTRAINT order_items_item_id_fkey
  FOREIGN KEY (item_id) REFERENCES public.items(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.order_items.item_id IS
  'Live pointer to the catalog item, or NULL if the item was hard-deleted. Nullable since migration 110: the row keeps its frozen name/price snapshot, so order history and revenue reporting survive catalog deletion. Do not make this NOT NULL again.';

-- =============================================================================
-- 3. CATALOG ROW COUNTS AND CASCADE SEMANTICS
-- =============================================================================
-- favorite_items is a user preference, not history: cascade is correct.
-- item_options / item_option_choices are configuration: cascade is correct.
-- Those are deliberately left as-is.
--
-- categories -> items stays ON DELETE CASCADE, but now terminates safely:
-- item deletion nulls order_items.item_id instead of deleting the line.

-- =============================================================================
-- 4. REQUIRED FOLLOW-UPS -- READ SITES THAT MUST FILTER deleted_at
-- =============================================================================
-- Deliberately NOT done here: these live in Edge Functions and the dashboard,
-- and a partial migration that updates some readers and not others would hide
-- soft-deleted rows in some screens and not others -- worse than not starting.
-- Each is a one-line change and all are mechanical:
--
--   supabase/functions/get-merchant-feed/index.ts      categories, items
--   supabase/functions/place-order/index.ts            items (validate live)
--   supabase/functions/search-catalog/index.ts         items
--   supabase/functions/get-order-fee-preview/index.ts  items (if it reads menu)
--   supabase/functions/validate-promo/index.ts         items (if it reads menu)
--   supabase/migrations/066 get_merchant_kpis()        item_count
--   supabase/migrations/091 get_merchant_kpis_range()  (no item read)
--   apps/admin: menu builder, item list, category list, merchant detail
--
-- Until those land, `deleted_at` is set but not yet honoured. That is safe:
-- soft-deleted rows stay visible, which is the pre-110 behaviour, not a
-- regression. The dangerous direction -- rows disappearing where a reader does
-- not expect it -- cannot happen until the readers change.

-- =============================================================================
-- 5. TRIGGERS THAT UPDATE deleted_at AUTOMATICALLY
-- =============================================================================
-- Only updated_at is maintained automatically today. A soft delete is an
-- explicit act by an admin, so it is written explicitly; no trigger, so the
-- migration cannot fight the application over who owns the value.