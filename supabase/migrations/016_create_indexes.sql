-- Migration 016: Create performance indexes
-- P1E-01: Merchants search: separate GIN trigram indexes on name_ar and name_en
-- P1E-02: Items search: separate GIN trigram indexes on name_ar and name_en
-- P1E-03: Orders by customer: (customer_id, created_at DESC)
-- P1E-04: Orders by merchant+status: (merchant_id, status, created_at DESC)
-- P1E-05: Active orders partial index (status, created_at DESC WHERE status NOT IN ('delivered','cancelled'))
-- P1E-06: Promo code unique index on code
-- P1E-07: Items by merchant+category: (merchant_id, category_id, is_available)

-- =============================================================================
-- P1E-01: MERCHANTS SEARCH — SEPARATE GIN TRIGRAM INDEXES
-- Per RED-24 in 13-PERFORMANCE-RED-FLAGS.md:
--   Do NOT use a single GIN index across both name_ar and name_en.
--   Separate indexes per language allow PostgreSQL to choose the right index
--   based on the query language, yielding faster and more accurate trigram matches.
--   The pg_trgm extension was enabled in 001_enable_extensions.sql.
-- =============================================================================

-- Arabic name trigram index (used when searching in Arabic)
CREATE INDEX idx_merchants_name_ar_trgm
  ON merchants USING gin (name_ar gin_trgm_ops);

-- English name trigram index (used when searching in English)
CREATE INDEX idx_merchants_name_en_trgm
  ON merchants USING gin (name_en gin_trgm_ops);

-- =============================================================================
-- P1E-02: ITEMS SEARCH — SEPARATE GIN TRIGRAM INDEXES
-- Same rationale as merchants: separate indexes per language for accurate
-- trigram matching and better query plan selection.
-- Used by search screen and merchant page item search.
-- =============================================================================

-- Arabic name trigram index (used when searching items in Arabic)
CREATE INDEX idx_items_name_ar_trgm
  ON items USING gin (name_ar gin_trgm_ops);

-- English name trigram index (used when searching items in English)
CREATE INDEX idx_items_name_en_trgm
  ON items USING gin (name_en gin_trgm_ops);

-- =============================================================================
-- P1E-03: ORDERS BY CUSTOMER
-- Primary query: "Get my orders" on the Orders tab.
-- Already created in 008_create_orders.sql as idx_orders_customer_created.
-- Verified: this index already exists. No duplicate needed.
-- =============================================================================

-- =============================================================================
-- P1E-04: ORDERS BY MERCHANT+STATUS
-- Primary query: Merchant order management (admin panel).
-- Already created in 008_create_orders.sql as idx_orders_merchant_status_created.
-- Verified: this index already exists. No duplicate needed.
-- =============================================================================

-- =============================================================================
-- P1E-05: ACTIVE ORDERS PARTIAL INDEX (⚡ PERFORMANCE-CRITICAL)
-- Per RED-05 in 13-PERFORMANCE-RED-FLAGS.md:
--   Without this partial index, queries for active orders (driver tracking,
--   admin dashboard, realtime subscriptions) scan ALL orders including
--   delivered/cancelled. With this index, only the small active set is scanned.
-- Already created in 008_create_orders.sql as idx_orders_active.
-- Verified: this index already exists. No duplicate needed.
-- =============================================================================

-- =============================================================================
-- P1E-06: PROMO CODE UNIQUE INDEX ON CODE
-- The UNIQUE constraint on promo_codes.code already creates a unique B-tree
-- index automatically. Additionally, in 011_create_promo_codes.sql we created
-- idx_promo_codes_active as a partial index on (code) WHERE is_active AND
-- expires_at > NOW(). No additional index needed.
-- Verified: UNIQUE constraint + partial index already exist.
-- =============================================================================

-- =============================================================================
-- P1E-07: ITEMS BY MERCHANT+CATEGORY+IS_AVAILABLE
-- Primary query: "Get available menu items for a merchant in a category"
-- Used by merchant page and get-merchant-menu API.
-- Already created in 007_create_menu_structure.sql as idx_items_merchant_category.
-- Verified: this index already exists. No duplicate needed.
-- =============================================================================

-- =============================================================================
-- ADDITIONAL PERFORMANCE INDEXES (from 13-PERFORMANCE-RED-FLAGS.md)
-- These were not explicitly listed in P1E but are recommended by the
-- performance spec and complement the existing indexes.
-- =============================================================================

-- Merchants: spatial indexes for location-based "near me" queries
-- Used by get-merchant-feed to calculate distance and sort by proximity
-- NOTE: GIST index with ::geography cast can fail on hosted Postgres.
-- Using btree on lat/lng; distance calculated in queries via ST_DWithin.
CREATE INDEX idx_merchants_location_lat ON merchants(lat) WHERE lat IS NOT NULL;
CREATE INDEX idx_merchants_location_lng ON merchants(lng) WHERE lng IS NOT NULL;

-- Items: GIN index on description for full-text search (future enhancement)
-- Lightweight trigram index on Arabic and English descriptions
CREATE INDEX idx_items_description_ar_trgm
  ON items USING gin (description_ar gin_trgm_ops)
  WHERE description_ar IS NOT NULL;

CREATE INDEX idx_items_description_en_trgm
  ON items USING gin (description_en gin_trgm_ops)
  WHERE description_en IS NOT NULL;

-- =============================================================================
-- COMMENTS
-- =============================================================================
COMMENT ON INDEX idx_merchants_name_ar_trgm IS 'P1E-01: GIN trigram index for Arabic merchant name search. Separate from English for optimal query plans. See RED-24.';
COMMENT ON INDEX idx_merchants_name_en_trgm IS 'P1E-01: GIN trigram index for English merchant name search. Separate from English for optimal query plans. See RED-24.';
COMMENT ON INDEX idx_items_name_ar_trgm IS 'P1E-02: GIN trigram index for Arabic item name search. Used by search screen.';
COMMENT ON INDEX idx_items_name_en_trgm IS 'P1E-02: GIN trigram index for English item name search. Used by search screen.';
COMMENT ON INDEX idx_merchants_location_lat IS 'Btree index for proximity-based merchant queries. Used with ST_DWithin in get-merchant-feed.';
