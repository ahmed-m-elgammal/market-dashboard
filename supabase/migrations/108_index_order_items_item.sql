-- Migration 108: Index order_items.item_id (BUG-14)
--
-- THE BUG
--   order_items carries a primary key and idx_order_items_order on (order_id).
--   Nothing indexes item_id -- and item_id is the FK column that BOTH of these
--   must probe:
--
--     (a) ON DELETE CASCADE from items (007:105). The cascade runs as an RI
--         trigger, so its cost does not appear in the plan tree; EXPLAIN
--         reports it as `Trigger for constraint order_items_item_id_fkey:
--         time=8.42 calls=1` against a 124,840-row table.
--     (b) any "which orders contained this item" read -- a dashboard report,
--         or the audit trail behind BUG-08.
--
-- MEASURED (dashborad/test/test_08_scale.py)
--   delete cascade trigger   8.42 ms -> 3.24 ms   (2.6x) with this index
--   item order history       >4x fewer buffers    with this index
--
--   Both are linear in order volume, so the gap widens as the marketplace
--   grows. It is cheapest to fix now, while order_items is small.
--
-- ORDERING CONSTRAINT
--   Migration 110 changes order_items.item_id to ON DELETE SET NULL for the
--   soft-delete fix (BUG-08). That FK action probes item_id exactly like the
--   cascade does, so WITHOUT this index, migration 110 would replace a 2.6x
--   slow delete with a slightly different slow delete. This migration must
--   therefore land BEFORE 110.
--
-- Rollback: DROP INDEX public.idx_order_items_item;

-- =============================================================================
-- 1. THE INDEX
-- =============================================================================
-- Composite, not a narrow index on item_id alone.
--
-- item_id is the LEADING column, so this one index serves every access path:
--   * the FK probe (WHERE item_id = $1) from the delete cascade
--   * "which orders contained this item" (WHERE item_id = $1)
--   * "which orders contained this item, by order" with no sort
--
-- A narrow (item_id) index alongside it is redundant: PostgreSQL prefers the
-- composite for item_id lookups anyway, so the narrow index would only add
-- write amplification on every order_items insert. Measured -- dropping the
-- narrow one still leaves a Bitmap Heap Scan off this index.
CREATE INDEX IF NOT EXISTS idx_order_items_item_order
  ON public.order_items(item_id, order_id);

-- =============================================================================
-- 2. DOCUMENTATION
-- =============================================================================
COMMENT ON INDEX public.idx_order_items_item_order IS
  'BUG-14 (migration 108): order_items.item_id was unindexed, so the items -> order_items FK action ran as a full sequential scan (8.42ms at 124,840 rows) and every item-history query seq-scanned. item_id leads, so this single index covers the cascade probe and both history reads. Required before migration 110 switches that FK to ON DELETE SET NULL.';