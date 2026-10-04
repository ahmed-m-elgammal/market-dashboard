-- Migration 068: Add soft-delete to promo_codes and promoted_slots
--
-- P1-4 fix (MARKETING-IMPROVEMENT-PLAN.md Task 2.4):
-- The DELETE routes previously hard-deleted rows, which:
--   1. Broke historical reporting (orders.promo_code_id FK is ON DELETE SET NULL,
--      so deleting a promo retroactively erased the link from every order that
--      used it)
--   2. Left no forensic recovery path
--   3. Lost the audit trail's referential target
--
-- This migration adds a deleted_at column. DELETE handlers now set deleted_at
-- = now() instead of removing the row. All admin SELECT queries add
-- WHERE deleted_at IS NULL (except ?include_deleted=true for the trash view).

ALTER TABLE promo_codes    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE promoted_slots ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- Partial index: speeds up the default "where deleted_at IS NULL" filter
-- that every admin list query now applies.
CREATE INDEX IF NOT EXISTS idx_promo_codes_deleted_at
  ON promo_codes(deleted_at) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_promoted_slots_deleted_at
  ON promoted_slots(deleted_at) WHERE deleted_at IS NULL;

COMMENT ON COLUMN promo_codes.deleted_at IS
  'P1-4: Soft-delete timestamp. NULL = active row. Set by DELETE /api/promo-codes/[id]. Admin list queries filter WHERE deleted_at IS NULL unless ?include_deleted=true.';
COMMENT ON COLUMN promoted_slots.deleted_at IS
  'P1-4: Soft-delete timestamp. NULL = active row. Set by DELETE /api/promoted-ads/[id]. Admin list queries filter WHERE deleted_at IS NULL unless ?include_deleted=true.';
