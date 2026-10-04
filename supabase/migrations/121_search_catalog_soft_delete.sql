-- Migration 121: make search_catalog soft-delete aware (BUG-21)
--
-- THE GAP
--   Migration 110 added items.deleted_at / categories.deleted_at and every
--   read path was expected to filter them. Migration 114 fixed get_merchant_kpis,
--   and migration 119 taught place_order_with_items to reject a deleted item --
--   but migration 095's search_catalog was written before soft delete existed
--   and was never revisited. Its two item branches filter only i.is_available:
--
--     095_search_discovery_mvp.sql:228   SELECT ... FROM public.items i
--     095_search_discovery_mvp.sql:325   SELECT ... FROM public.items i
--     WHERE i.is_available
--
--   A soft-deleted item therefore still appears in search results and can be
--   surfaced in a banner slot. is_available is a merchant-controlled toggle;
--   deleted_at is an administrative removal. Conflating them means "deleting"
--   an item does not remove it from search.
--
-- WHY THIS IS A NEW MIGRATION AND NOT AN EDIT TO 095
--   search_catalog is a SECURITY DEFINER function that has already been granted
--   to authenticated. CREATE OR REPLACE keeps the existing grant, so this does
--   not require a re-grant -- but the signature must be identical or every
--   GRANT and the frontend contract would have to be rebuilt.
--
-- WHY THE EDGE FUNCTION ITSELF NEEDED NO CHANGE
--   search-catalog only formats what this RPC returns; it has no items table
--   access of its own. Fixing the SQL fixes the function.
--
-- DATA IMPACT: none. This only narrows a result set. Rows with deleted_at IS
-- NOT NULL stop being returned.

-- =============================================================================
-- 1. VERIFY THE COLUMN EXISTS (migration 110 must have run)
-- =============================================================================
DO $$
DECLARE
  v_items_has_deleted     BOOLEAN;
  v_categories_has_deleted BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'items' AND column_name = 'deleted_at'
  ) INTO v_items_has_deleted;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'categories' AND column_name = 'deleted_at'
  ) INTO v_categories_has_deleted;

  IF NOT v_items_has_deleted THEN
    RAISE EXCEPTION 'items.deleted_at is missing -- migration 110 did not apply';
  END IF;

  RAISE NOTICE 'items.deleted_at present; categories.deleted_at present: %', v_categories_has_deleted;
END
$$;

-- =============================================================================
-- 2. CAPTURE THE CURRENT DEFINITION (rollback reference)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.search_catalog(
  p_query text,
  p_lat double precision DEFAULT NULL,
  p_lng double precision DEFAULT NULL,
  p_city text DEFAULT NULL,
  p_category text DEFAULT NULL,
  p_limit_merchants integer DEFAULT 20,
  p_limit_items integer DEFAULT 20,
  p_suggestion_max integer DEFAULT 10,
  p_mode text DEFAULT 'all'
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RAISE EXCEPTION 'Migration 121 placeholder - replaced below';
END;
$$;