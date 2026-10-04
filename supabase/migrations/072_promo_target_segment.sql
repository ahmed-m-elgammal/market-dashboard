-- Migration 072: Add target_segment to promo_codes
--
-- P2-5 (MARKETING-IMPROVEMENT-PLAN.md Task 3.2):
-- Promos can now target specific user segments: all users, new users
-- (created within 7 days), first-order-only, or dormant (no orders in
-- last 30 days but at least one historical order). The validate-promo
-- Edge Function enforces the segment check.

ALTER TABLE promo_codes
  ADD COLUMN IF NOT EXISTS target_segment TEXT NOT NULL DEFAULT 'all'
    CHECK (target_segment IN ('all', 'new_users', 'first_order', 'dormant_30d'));

COMMENT ON COLUMN promo_codes.target_segment IS
  'P2-5: User segment this promo targets. all = everyone, new_users = accounts created within 7 days, first_order = customers with 0 non-cancelled orders, dormant_30d = customers with >=1 order but none in last 30 days. Enforced by validatePromoCode.';
