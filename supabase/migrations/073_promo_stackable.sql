-- Migration 073: Add stackable column to promo_codes
--
-- P2-6 (MARKETING-IMPROVEMENT-PLAN.md Task 3.3):
-- Adds an explicit stackable policy column to promo_codes. Currently the
-- orders table has a single promo_code_id column, so stacking is already
-- impossible at the schema level — this column documents intent and is
-- ready for a future multi-promo feature.
--
-- When (if) multi-promo support is added to place_order_with_items, the
-- RPC should reject a second promo if the first is non-stackable.

ALTER TABLE promo_codes
  ADD COLUMN IF NOT EXISTS stackable BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN promo_codes.stackable IS
  'P2-6: Whether this promo can be stacked with other promos on the same order. Currently informational — orders support only one promo (single promo_code_id column). Reserved for future multi-promo support.';
