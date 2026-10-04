-- Migration 099: Create active_merchant_categories view (chip-row data source)
-- (Phase 5 prerequisite — audit row 38 / §4.3 Option A; see
--  docs/plans/VENDOR-CATEGORIES-IMPACT-AUDIT.md)
--
-- One row per merchant category that currently has >= 1 ACTIVE merchant
-- anywhere. The mobile chip row reads this view via PostgREST, so the F-02
-- invariant "no chip without a backing merchant" holds BY CONSTRUCTION —
-- the past regression (chips advertising unbacked categories, leading users
-- into an unrecoverable empty state) becomes structurally impossible.
--
-- City-agnostic by design (any active merchant anywhere backs a chip);
-- per-city chips would need the audit's Option B edge function (§6.8 —
-- open business decision, revisit before relying on city scoping).
--
-- SECURITY — deliberate refinement of the audit sketch:
--   The sketch notes "a view executes with its owner's rights". This view
--   is created WITH (security_invoker = true) instead (PG15+/Supabase best
--   practice): the query executes with the CALLER's rights, so RLS applies
--   on both base tables. The result set is identical to the sketch's
--   owner-rights version because both base tables already expose exactly
--   these rows to clients:
--     - merchant_categories: policy "merchant_categories_read" (097)
--       exposes is_active = TRUE — the same predicate as this view's WHERE.
--     - merchants: policy "merchants_read_active" (020:97-100) exposes
--       is_active = TRUE — the same predicate as the join condition.
--   security_invoker avoids handing anon/authenticated an owner-power
--   window into the two base tables if their policies ever tighten.
--
-- Grants: explicit SELECT for anon/authenticated (documents intent;
-- Supabase default privileges would grant it anyway). Writes: none — the
-- view is read-only by definition and the base tables already deny
-- client writes via RLS.
--
-- Rollback: DROP VIEW active_merchant_categories (no FK depends on views;
-- the mobile fallback chip row renders from the bundled code list on
-- fetch error, so clients survive the drop).
--
-- NOTE on numbering: the audit sketch reserved "099" for the conditional
-- items type-aware columns (§4.4) — that migration remains gated on the
-- §6.2 business decisions and, if ever approved, becomes 100+.

CREATE VIEW public.active_merchant_categories
WITH (security_invoker = true) AS
SELECT
  mc.code,
  mc.name_ar,
  mc.name_en,
  mc.icon,
  mc.sort_order,
  count(m.id) AS active_merchants
FROM public.merchant_categories mc
JOIN public.merchants m
  ON m.category = mc.code
 AND m.is_active = TRUE
WHERE mc.is_active = TRUE
GROUP BY mc.code, mc.name_ar, mc.name_en, mc.icon, mc.sort_order;

GRANT SELECT ON public.active_merchant_categories TO anon, authenticated;

COMMENT ON VIEW public.active_merchant_categories IS
  'Chip-row data source (audit row 38, Option A): active merchant categories with >= 1 active merchant, bilingual names, icon and chip order. security_invoker view — RLS of merchant_categories (097) and merchants (020) applies to callers.';
