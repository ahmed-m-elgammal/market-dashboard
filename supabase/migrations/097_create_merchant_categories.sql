-- Migration 097: Create merchant_categories lookup table (Phase 1 of the
-- vendor-categories widening — see docs/plans/VENDOR-CATEGORIES-IMPACT-AUDIT.md)
--
-- Replaces the two-value inline CHECK constraints on merchants.category
-- (005:18), promoted_slots.category (014:25) and promo_codes.category
-- (011:39) with a data-driven lookup table. This migration is PURELY
-- ADDITIVE: nothing reads this table yet; the FK swap happens in 098.
-- Rollback: DROP TABLE merchant_categories (nothing depends on it until 098).
--
-- Seeded codes (audit §4.1): restaurant, pharmacy (the two legacy values,
-- so 098's FK validates existing rows with zero data rewrite) plus market,
-- grocery, bakery, butcher, flowers, other. 'other' is the escape hatch: an
-- operator can always onboard, and no client ever renders an untranslatable
-- category label.
--
-- Security (mirrors the 096 stance, audit §4.1):
--   - ENABLE ROW LEVEL SECURITY (required by scripts/check-rls-coverage.js).
--   - One SELECT policy for anon/authenticated filtered to is_active rows —
--     inactive codes stay referentially valid for existing rows but are
--     invisible to clients (hide a vendor type without deleting it).
--   - Write paths are service_role only: no INSERT/UPDATE/DELETE policy
--     exists, so anon/authenticated are denied writes by RLS itself.
--
-- Rollback: DROP TABLE public.merchant_categories;
-- (only safe before 098 is applied — 098 adds the FKs that reference it).

-- =============================================================================
-- 1. Lookup table
-- =============================================================================
CREATE TABLE public.merchant_categories (
  code       TEXT PRIMARY KEY CHECK (code ~ '^[a-z][a-z0-9_]*$'),
  name_ar    TEXT NOT NULL,
  name_en    TEXT NOT NULL,
  icon       TEXT,                            -- emoji or icon key for the chip grid
  sort_order INTEGER NOT NULL DEFAULT 0,      -- chip row ordering
  is_active  BOOLEAN NOT NULL DEFAULT TRUE,   -- hide a vendor type without deleting
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- CI guard parity: scripts/check-rls-coverage.js enforces RLS on every table
-- (same-file pattern used by 028+ migrations).
ALTER TABLE public.merchant_categories ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_categories_read"
  ON public.merchant_categories
  FOR SELECT TO anon, authenticated
  USING (is_active = TRUE);  -- write paths: service_role only (no policy = denied)

-- =============================================================================
-- 2. Seed the 8 vendor categories
--    Legacy values first so 098's FK validates every existing row as-is.
-- =============================================================================
INSERT INTO public.merchant_categories (code, name_ar, name_en, icon, sort_order) VALUES
  ('restaurant', 'مطاعم',   'Restaurants', '🍔', 1),
  ('pharmacy',   'صيدليات', 'Pharmacies',  '💊', 2),
  ('market',     'أسواق',   'Markets',     '🛒', 3),
  ('grocery',    'بقالة',   'Grocery',     '🧺', 4),
  ('bakery',     'مخبوزات', 'Bakery',      '🥖', 5),
  ('butcher',    'جزارة',   'Butcher',     '🥩', 6),
  ('flowers',    'زهور',    'Flowers',     '💐', 7),
  ('other',      'أخرى',    'Other',       '🛍️', 8);

COMMENT ON TABLE public.merchant_categories IS
  'Vendor category lookup — single source of truth for merchants.category, promoted_slots.category and promo_codes.category (replaces the two-value inline CHECKs of 005/011/014). Read policy exposes is_active rows to clients; writes are service_role only.';
