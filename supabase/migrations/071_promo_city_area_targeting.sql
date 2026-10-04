-- Migration 071: Add city/area targeting to promo_codes
--
-- P2-4 (MARKETING-IMPROVEMENT-PLAN.md Task 3.1):
-- Promos were previously scoped only by merchant_id or category. A
-- "Cairo-only new-user promo" or "Alexandria-only weekend special" was
-- not expressible. This migration adds city and area columns (nullable —
-- NULL = all cities/areas) that the validate-promo Edge Function checks
-- against the customer's delivery address.

ALTER TABLE promo_codes
  ADD COLUMN IF NOT EXISTS city TEXT,
  ADD COLUMN IF NOT EXISTS area TEXT;

-- Index: find promos targeting a specific city (admin panel filter)
CREATE INDEX IF NOT EXISTS idx_promo_codes_city
  ON promo_codes(city) WHERE city IS NOT NULL;

COMMENT ON COLUMN promo_codes.city IS
  'P2-4: If set, the promo is only valid for orders delivered to this city. NULL = all cities. Checked by validatePromoCode against the customer delivery address city.';
COMMENT ON COLUMN promo_codes.area IS
  'P2-4: If set, the promo is only valid for orders delivered to this area. NULL = all areas. More specific than city — e.g. city=Cairo, area=Maadi.';
