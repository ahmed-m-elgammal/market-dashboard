-- Migration 092: Create favorite_items table
-- Customer saved/favorited individual menu items for quick re-ordering.
-- Simple junction table with unique constraint on (user_id, item_id).

-- =============================================================================
-- FAVORITE_ITEMS TABLE
-- =============================================================================
CREATE TABLE public.favorite_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Customer who favorited
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE DEFAULT auth.uid(),

  -- Item which was favorited
  item_id UUID NOT NULL REFERENCES public.items(id) ON DELETE CASCADE,

  -- Merchant who owns the item (denormalized to optimize queries without nested joins)
  merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,

  -- Timestamp
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Unique constraint — each user can favorite an item only once
  CONSTRAINT unique_user_item_favorite UNIQUE (user_id, item_id)
);

-- =============================================================================
-- INDEXES
-- =============================================================================
-- Index: get a user's favorite items (favorites tab in app, sorted by newest)
CREATE INDEX idx_favorite_items_user_created
  ON public.favorite_items(user_id, created_at DESC);

-- Index: check if an item is favorited (for heart icon on menu item card)
CREATE INDEX idx_favorite_items_item
  ON public.favorite_items(item_id);

-- Index: query optimization for merchant relations
CREATE INDEX idx_favorite_items_merchant
  ON public.favorite_items(merchant_id);

-- =============================================================================
-- ROW LEVEL SECURITY (RLS) & POLICIES
-- =============================================================================
ALTER TABLE public.favorite_items ENABLE ROW LEVEL SECURITY;

-- Read: own favorite items
CREATE POLICY "favorite_items_read_own"
  ON public.favorite_items
  FOR SELECT
  USING (auth.uid() = user_id);

-- Insert: own favorite items
CREATE POLICY "favorite_items_insert_own"
  ON public.favorite_items
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Delete: own favorite items
CREATE POLICY "favorite_items_delete_own"
  ON public.favorite_items
  FOR DELETE
  USING (auth.uid() = user_id);

-- =============================================================================
-- REALTIME REGISTRATION
-- =============================================================================
ALTER PUBLICATION supabase_realtime ADD TABLE public.favorite_items;

-- =============================================================================
-- COMMENTS
-- =============================================================================
COMMENT ON TABLE public.favorite_items IS 'Customer favorited menu items. Simple junction table with unique constraint on (user_id, item_id) for quick item reordering.';
COMMENT ON COLUMN public.favorite_items.user_id IS 'Customer who favorited the menu item.';
COMMENT ON COLUMN public.favorite_items.item_id IS 'Menu item that was favorited.';
COMMENT ON COLUMN public.favorite_items.merchant_id IS 'Merchant that sells the favorited item (stored for query optimization).';

COMMENT ON POLICY "favorite_items_read_own" ON public.favorite_items IS 'Users can read their own favorite items only.';
COMMENT ON POLICY "favorite_items_insert_own" ON public.favorite_items IS 'Users can add their own favorite items only.';
COMMENT ON POLICY "favorite_items_delete_own" ON public.favorite_items IS 'Users can remove their own favorite items only.';

COMMENT ON PUBLICATION supabase_realtime IS 'Supabase Realtime publication — includes all admin-dashboard-tracked tables for postgres_changes events. Migration 092 added favorite_items.';
