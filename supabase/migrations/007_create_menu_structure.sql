-- Migration 007: Create menu structure tables
-- P1B-05: Create categories table
-- P1B-06: Create items table
-- P1B-07: Create item_options table
-- P1B-08: Create item_option_choices table

-- =============================================================================
-- CATEGORIES TABLE (P1B-05)
-- Menu categories per merchant (e.g., "Burgers", "Sides", "Drinks").
-- Sorted by sort_order for display in the app.
-- =============================================================================
CREATE TABLE categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Merchant reference
  merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,

  -- Bilingual names
  name_ar TEXT NOT NULL,
  name_en TEXT NOT NULL,

  -- Display order (lower = appears first)
  sort_order INTEGER NOT NULL DEFAULT 0,

  -- Category icon/emoji (optional, for UI)
  icon TEXT,

  -- Availability
  is_available BOOLEAN NOT NULL DEFAULT TRUE,

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for fetching categories by merchant
CREATE INDEX idx_categories_merchant
  ON categories(merchant_id, sort_order);

-- =============================================================================
-- ITEMS TABLE (P1B-06)
-- Menu items within categories.
-- Prices in EGP. Bilingual names and descriptions.
-- Price snapshots are taken when order is placed (stored in order_items).
-- =============================================================================
CREATE TABLE items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Merchant and category references
  merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  category_id UUID NOT NULL REFERENCES categories(id) ON DELETE CASCADE,

  -- Bilingual names
  name_ar TEXT NOT NULL,
  name_en TEXT NOT NULL,

  -- Bilingual descriptions
  description_ar TEXT,
  description_en TEXT,

  -- Price in EGP
  price NUMERIC(10,2) NOT NULL CHECK (price >= 0),

  -- Image
  image_url TEXT,

  -- Availability
  is_available BOOLEAN NOT NULL DEFAULT TRUE,

  -- Display order within category
  sort_order INTEGER NOT NULL DEFAULT 0,

  -- Popularity (for sorting recommendations)
  popularity_score INTEGER NOT NULL DEFAULT 0,

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for fetching items by merchant + category (main menu query)
CREATE INDEX idx_items_merchant_category
  ON items(merchant_id, category_id, is_available);

-- Index for fetching items by merchant alone (search within merchant)
CREATE INDEX idx_items_merchant
  ON items(merchant_id) WHERE is_available = TRUE;

-- =============================================================================
-- ITEM_OPTIONS TABLE (P1B-07)
-- Option groups for items (e.g., "Size", "Extra Toppings", "Drink").
-- An item can have multiple option groups.
-- Some are required (must select at least one), some are optional.
-- =============================================================================
CREATE TABLE item_options (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Item reference
  item_id UUID NOT NULL REFERENCES items(id) ON DELETE CASCADE,

  -- Bilingual names
  name_ar TEXT NOT NULL,
  name_en TEXT NOT NULL,

  -- Is this option group required? (e.g., Size is required, Extra Toppings is optional)
  is_required BOOLEAN NOT NULL DEFAULT FALSE,

  -- Maximum number of selections within this group
  -- NULL = unlimited, 1 = single select, >1 = multi-select with limit
  max_selections INTEGER
    CHECK (max_selections IS NULL OR max_selections >= 1),

  -- Minimum number of selections (for required groups, typically 1)
  min_selections INTEGER NOT NULL DEFAULT 0
    CHECK (min_selections >= 0),

  -- Display order
  sort_order INTEGER NOT NULL DEFAULT 0,

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for fetching options by item
CREATE INDEX idx_item_options_item
  ON item_options(item_id, sort_order);

-- =============================================================================
-- ITEM_OPTION_CHOICES TABLE (P1B-08)
-- Individual choices within an option group.
-- Each choice has a price modifier (addition to the base item price).
-- =============================================================================
CREATE TABLE item_option_choices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Option group reference
  option_id UUID NOT NULL REFERENCES item_options(id) ON DELETE CASCADE,

  -- Bilingual names
  name_ar TEXT NOT NULL,
  name_en TEXT NOT NULL,

  -- Price modifier in EGP (added to the item's base price)
  -- e.g., "Large" size might add 15.00 EGP
  price_modifier NUMERIC(10,2) NOT NULL DEFAULT 0.00
    CHECK (price_modifier >= 0),

  -- Is this the default choice? (pre-selected in UI)
  is_default BOOLEAN NOT NULL DEFAULT FALSE,

  -- Availability
  is_available BOOLEAN NOT NULL DEFAULT TRUE,

  -- Display order
  sort_order INTEGER NOT NULL DEFAULT 0,

  -- Calories (optional, for health-focused users)
  calories INTEGER,

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for fetching choices by option group
CREATE INDEX idx_item_option_choices_option
  ON item_option_choices(option_id, sort_order);

-- =============================================================================
-- UPDATE_UPDATED_AT TRIGGERS
-- =============================================================================
CREATE TRIGGER set_categories_updated_at
  BEFORE UPDATE ON categories
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER set_items_updated_at
  BEFORE UPDATE ON items
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER set_item_options_updated_at
  BEFORE UPDATE ON item_options
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER set_item_option_choices_updated_at
  BEFORE UPDATE ON item_option_choices
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- =============================================================================
-- COMMENTS
-- =============================================================================
COMMENT ON TABLE categories IS 'Menu categories per merchant (e.g., Burgers, Sides, Drinks). Sorted by sort_order.';
COMMENT ON TABLE items IS 'Menu items within categories. Prices in EGP. Bilingual names and descriptions. Price snapshots taken at order time.';
COMMENT ON TABLE item_options IS 'Option groups for items (e.g., Size, Extra Toppings). Some required, some optional.';
COMMENT ON TABLE item_option_choices IS 'Individual choices within option groups. Each has a price modifier added to base item price.';

COMMENT ON COLUMN items.price IS 'Base price in EGP. Actual price at order time is snapshotted in order_items.';
COMMENT ON COLUMN item_options.is_required IS 'If true, customer must select at least min_selections choices from this group.';
COMMENT ON COLUMN item_options.max_selections IS 'Maximum choices selectable. NULL=unlimited, 1=single select.';
COMMENT ON COLUMN item_option_choices.price_modifier IS 'Amount in EGP added to the item base price when this choice is selected.';
COMMENT ON COLUMN item_option_choices.is_default IS 'If true, this choice is pre-selected in the UI.';
