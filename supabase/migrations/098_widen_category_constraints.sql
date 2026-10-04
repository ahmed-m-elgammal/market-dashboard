-- Migration 098: Widen category constraints to FK into merchant_categories
-- (Phase 2 of the vendor-categories widening — see
--  docs/plans/VENDOR-CATEGORIES-IMPACT-AUDIT.md, §4.2)
--
-- Swaps the three two-value inline CHECK constraints for foreign keys into
-- merchant_categories (created + seeded by 097 — this migration must ALWAYS
-- run after 097, never the reverse: the FKs validate existing rows against
-- the seeded codes at creation time).
--
-- Tables touched (all three category CHECKs in the schema, verified by grep):
--   merchants      005:18  category TEXT NOT NULL CHECK (category IN ('restaurant','pharmacy'))
--   promoted_slots 014:25  category TEXT CHECK (...)          (nullable — stays nullable)
--   promo_codes    011:39  category TEXT CHECK (...)          (nullable — stays nullable)
--
-- Constraint names: Postgres assigns the deterministic default
-- '{table}_{column}_check' to inline CHECKs, and no later migration drops or
-- re-adds any of these (verified). The app is not in production, so the
-- database is built by replaying these files in filename order — the default
-- names are guaranteed, and existing rows can only ever be 'restaurant' |
-- 'pharmacy' (seed.sql:75-112), both seeded by 097. The FK therefore
-- validates instantly with ZERO data rewrite — no backfill needed.
--
-- NOT NULL on merchants.category (005:18) is retained as-is; no new NOT NULL
-- is introduced anywhere (promoted_slots/promo_codes stay nullable).
--
-- DEVIATION from audit sketch §4.2 (deliberate): the sketch ends with
--   SELECT public.refresh_merchant_open_status();
-- That function issues REFRESH MATERIALIZED VIEW CONCURRENTLY (031:87),
-- which cannot execute inside a transaction block — and Supabase applies
-- each migration inside one transaction, so the call would abort this
-- migration with "REFRESH MATERIALIZED VIEW CONCURRENTLY cannot be executed
-- from a function". It is also unnecessary here: constraint widening changes
-- no rows, so the materialized view's contents are unaffected (its refresh
-- cadence is a pre-existing runtime concern, unchanged by this migration).
--
-- Rollback (audit §3): drop the three FKs and re-add the three original
-- CHECKs — only valid while every category value is still 'restaurant' |
-- 'pharmacy' (check the Phase 0 distribution query first).

-- =============================================================================
-- 1. merchants (005:18)
-- =============================================================================
ALTER TABLE public.merchants DROP CONSTRAINT merchants_category_check;
ALTER TABLE public.merchants
  ADD CONSTRAINT merchants_category_fk
  FOREIGN KEY (category) REFERENCES public.merchant_categories(code);

CREATE INDEX IF NOT EXISTS idx_merchants_category_active
  ON public.merchants(category) WHERE is_active = TRUE;

-- =============================================================================
-- 2. promoted_slots (014:25) — nullable column stays nullable
-- =============================================================================
ALTER TABLE public.promoted_slots DROP CONSTRAINT promoted_slots_category_check;
ALTER TABLE public.promoted_slots
  ADD CONSTRAINT promoted_slots_category_fk
  FOREIGN KEY (category) REFERENCES public.merchant_categories(code);

CREATE INDEX IF NOT EXISTS idx_promoted_slots_category_active
  ON public.promoted_slots(category) WHERE is_active = TRUE;

-- =============================================================================
-- 3. promo_codes (011:39) — nullable column stays nullable
-- =============================================================================
ALTER TABLE public.promo_codes DROP CONSTRAINT promo_codes_category_check;
ALTER TABLE public.promo_codes
  ADD CONSTRAINT promo_codes_category_fk
  FOREIGN KEY (category) REFERENCES public.merchant_categories(code);
