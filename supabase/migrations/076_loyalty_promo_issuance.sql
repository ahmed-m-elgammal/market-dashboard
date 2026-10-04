-- Migration 076: Loyalty promo auto-issuance
--
-- Phase 4b (MARKETING-IMPROVEMENT-PLAN.md):
-- Loyalty-style automatic promo issuance. A scheduled Edge Function runs
-- daily, finds customers who spent >= 500 EGP in the last 7 days, and
-- auto-issues a 10% off promo (max 1 per customer per month). This
-- migration creates the tracking table + config seeds. The EF is in
-- supabase/functions/auto-issue-loyalty-promos/index.ts.
--
-- Config keys (seeded in platform_config):
--   - loyalty_spend_threshold = 500 (EGP spent in lookback window)
--   - loyalty_discount_pct = 10 (percentage off)
--   - loyalty_lookback_days = 7 (days to sum spend over)
--   - loyalty_cooldown_days = 30 (min days between loyalty promos per customer)
--   - loyalty_promo_max_discount = 50 (cap per redemption in EGP)
--   - loyalty_promo_validity_days = 14 (promo expires N days after issue)

-- =============================================================================
-- 1. loyalty_promo_log table — tracks issued loyalty promos (prevents dupes)
-- =============================================================================
CREATE TABLE loyalty_promo_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  promo_code_id UUID NOT NULL REFERENCES public.promo_codes(id) ON DELETE CASCADE,
  spend_threshold_met NUMERIC(10,2) NOT NULL,
  issued_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- One loyalty promo per customer per cooldown period (enforced by the EF
-- checking this table, but the unique index is a backstop).
CREATE UNIQUE INDEX idx_loyalty_promo_log_customer_promo
  ON loyalty_promo_log(customer_id, promo_code_id);

-- Index: find the last loyalty promo issued to a customer (cooldown check)
CREATE INDEX idx_loyalty_promo_log_customer_issued
  ON loyalty_promo_log(customer_id, issued_at DESC);

COMMENT ON TABLE loyalty_promo_log IS
  'Phase 4b: Tracks loyalty promos auto-issued to customers. The auto-issue-loyalty-promos EF checks this table to enforce the cooldown (one loyalty promo per customer per 30 days).';

-- =============================================================================
-- 2. Config seeds
-- =============================================================================
INSERT INTO public.platform_config (key, value, description, value_type) VALUES
  ('loyalty_spend_threshold', '500', 'Min EGP spent in the lookback window to qualify for a loyalty promo', 'number'),
  ('loyalty_discount_pct', '10', 'Discount percentage for loyalty promos', 'number'),
  ('loyalty_lookback_days', '7', 'Days to sum customer spend over when checking the threshold', 'number'),
  ('loyalty_cooldown_days', '30', 'Min days between loyalty promos for the same customer', 'number'),
  ('loyalty_promo_max_discount', '50', 'Max discount in EGP per loyalty promo redemption', 'number'),
  ('loyalty_promo_validity_days', '14', 'Days until a loyalty promo expires after issue', 'number')
ON CONFLICT (key) DO NOTHING;
