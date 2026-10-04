-- Migration 096: Enable RLS on promoted_slot_events + loyalty_promo_log
-- (🔒 SECURITY-CRITICAL — closes CI RLS-coverage gaps, 019 pattern)
--
-- The RLS coverage check (scripts/check-rls-coverage.js, Sprint 3 Task 20)
-- enforces that every CREATE TABLE is followed by ENABLE ROW LEVEL SECURITY.
-- Two tables slipped through the 019 sweep because they were created later
-- (070, 076) without their own ENABLE statement:
--
--   1. promoted_slot_events (070) — per-impression/click event log for
--      promoted slots. Today any authenticated user could INSERT fake
--      impression rows (ad-fraud vector) and SELECT customer_id-bearing
--      analytics rows with the anon key. Never intended to be client-facing.
--
--   2. loyalty_promo_log (076) — tracks loyalty promos auto-issued per
--      customer (cooldown backstop). Exposes per-customer spend thresholds;
--      not client-facing.
--
-- Stance for both (mirrors 095 search_queries — internal service tables):
--   - ENABLE ROW LEVEL SECURITY with ZERO policies → deny-all for
--     anon/authenticated (no policy = no rows).
--   - REVOKE ALL from anon, authenticated (belt-and-braces alongside RLS;
--     removes direct table privileges RLS alone would still gate).
--   - Explicit GRANT SELECT, INSERT to service_role (documenting intent;
--     Supabase default-privileges already grant service_role ALL).
--
-- Consumers verified service-role-only (RLS bypassed for them, so zero
-- behaviour change):
--   promoted_slot_events:
--     - get-merchant-feed EF:223  .insert(events)          (service_role)
--     - search-catalog EF:245     .insert(events)          (service_role)
--     - admin promoted-ads track-click route: .insert()    (requireAdmin →
--       guard.adminClient = service role)
--     - admin promoted-ads analytics + timeseries routes: .select() (service role)
--   loyalty_promo_log:
--     - auto-issue-loyalty-promos EF: SELECT (cooldown check) + INSERT
--       (service_role cron)
--
-- Rollback: GRANT back + DISABLE ROW LEVEL SECURITY (not recommended — the
-- current state is the vulnerability).

-- =============================================================================
-- 1. promoted_slot_events (from 070)
-- =============================================================================
ALTER TABLE public.promoted_slot_events ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.promoted_slot_events FROM anon, authenticated;
GRANT SELECT, INSERT ON public.promoted_slot_events TO service_role;

COMMENT ON TABLE public.promoted_slot_events IS
  'P1-6: Per-event time-series for promoted slot impressions and clicks. RLS on with zero policies — service-role only (EF impression writers + admin analytics routes).';

-- =============================================================================
-- 2. loyalty_promo_log (from 076)
-- =============================================================================
ALTER TABLE public.loyalty_promo_log ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.loyalty_promo_log FROM anon, authenticated;
GRANT SELECT, INSERT ON public.loyalty_promo_log TO service_role;

COMMENT ON TABLE public.loyalty_promo_log IS
  'Phase 4b: Tracks loyalty promos auto-issued to customers (cooldown enforcement). RLS on with zero policies — service-role only (auto-issue-loyalty-promos cron EF).';
