-- Migration 074: Promo fraud detection — ip_address tracking + check_promo_fraud RPC
--
-- P2-7 (MARKETING-IMPROVEMENT-PLAN.md Task 3.4):
-- Detects when one IP address redeems the same promo code from 3+ distinct
-- user accounts within 24 hours — a strong signal of promo abuse (one person
-- creating multiple accounts to farm discounts).
--
-- This migration:
--   1. Adds ip_address INET to promo_code_usage (nullable — old rows + anon)
--   2. Adds an index for the fraud query (promo_code_id, ip_address, used_at)
--   3. Creates check_promo_fraud(p_promo_code_id, p_ip_address) RPC that
--      counts distinct user_id in the last 24h for the given promo + IP,
--      and inserts an alert_incident if >= 3
--   4. Seeds an alert_rule for promo_fraud so it shows up in the admin UI

-- =============================================================================
-- 1. Add ip_address to promo_code_usage
-- =============================================================================
ALTER TABLE public.promo_code_usage
  ADD COLUMN IF NOT EXISTS ip_address INET;

COMMENT ON COLUMN public.promo_code_usage.ip_address IS
  'P2-7: IP address the promo was redeemed from. Used by check_promo_fraud RPC to detect multi-account abuse. Nullable for old rows + anonymous redemptions.';

-- Index: the fraud query is
--   SELECT COUNT(DISTINCT user_id) FROM promo_code_usage
--   WHERE promo_code_id = ? AND ip_address = ? AND used_at > NOW() - INTERVAL '24 hours'
CREATE INDEX IF NOT EXISTS idx_promo_usage_fraud
  ON public.promo_code_usage(promo_code_id, ip_address, used_at DESC)
  WHERE ip_address IS NOT NULL;

-- =============================================================================
-- 2. check_promo_fraud RPC
-- =============================================================================
-- Called from place_order_with_items after a promo usage insert (fire-and-
-- forget — don't block the order). Returns the distinct user count so the
-- caller can log it. Inserts an alert_incident if >= 3 distinct users from
-- the same IP in 24h.
--
-- The alert_incident insertion is idempotent: it checks for an existing
-- active incident (status IN ('triggered', 'acknowledged')) for the same
-- promo + IP before inserting, matching the check_and_trigger_alerts pattern.
CREATE OR REPLACE FUNCTION public.check_promo_fraud(
  p_promo_code_id UUID,
  p_ip_address INET
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_distinct_users INTEGER;
  v_promo_code TEXT;
  v_msg TEXT;
  v_rule_id UUID;
BEGIN
  -- Count distinct users who redeemed this promo from this IP in the last 24h
  SELECT COUNT(DISTINCT user_id) INTO v_distinct_users
  FROM public.promo_code_usage
  WHERE promo_code_id = p_promo_code_id
    AND ip_address = p_ip_address
    AND used_at > NOW() - INTERVAL '24 hours';

  -- If >= 3, insert an alert incident (if one doesn't already exist)
  IF v_distinct_users >= 3 THEN
    SELECT code INTO v_promo_code FROM public.promo_codes WHERE id = p_promo_code_id;

    -- Find the seeded promo_fraud alert rule
    SELECT id INTO v_rule_id FROM public.alert_rules WHERE metric = 'promo_fraud' LIMIT 1;

    IF v_rule_id IS NOT NULL THEN
      -- Check for an existing active incident for this promo + IP
      IF NOT EXISTS (
        SELECT 1 FROM public.alert_incidents
        WHERE rule_id = v_rule_id
          AND status IN ('triggered', 'acknowledged')
          AND message LIKE '%' || v_promo_code || '%'
          AND message LIKE '%' || host(p_ip_address) || '%'
      ) THEN
        v_msg := 'Promo fraud detected: code "' || v_promo_code || '" redeemed by '
          || v_distinct_users || ' distinct users from IP ' || host(p_ip_address)
          || ' in the last 24 hours.';
        INSERT INTO public.alert_incidents (rule_id, metric, severity, message, trigger_value, status, triggered_at)
        VALUES (v_rule_id, 'promo_fraud', 'critical', v_msg, v_distinct_users, 'triggered', NOW());
      END IF;
    END IF;
  END IF;

  RETURN v_distinct_users;
END;
$$;

COMMENT ON FUNCTION public.check_promo_fraud(UUID, INET) IS
  'P2-7: Counts distinct users who redeemed a promo from a given IP in the last 24h. If >= 3, inserts a critical alert_incident. Idempotent — skips if an active incident already exists for this promo + IP.';

REVOKE EXECUTE ON FUNCTION public.check_promo_fraud(UUID, INET) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_promo_fraud(UUID, INET) TO service_role;

-- =============================================================================
-- 3. Seed the promo_fraud alert rule
-- =============================================================================
INSERT INTO public.alert_rules (name, description, metric, condition, threshold, duration_seconds, severity, is_active, notification_channels)
VALUES (
  'Promo Fraud — Multi-Account Abuse',
  'A single IP address redeems the same promo code from 3+ distinct user accounts within 24 hours',
  'promo_fraud', 'greater_than', 2, 0, 'critical',
  true, ARRAY['admin_panel']
)
ON CONFLICT DO NOTHING;
