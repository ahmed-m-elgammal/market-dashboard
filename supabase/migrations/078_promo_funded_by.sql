-- Migration 078: Add promo discount funding model
--
-- S1 (money-movement-implementation-plan.md):
-- Adds `funded_by` and `merchant_share_pct` columns to promo_codes so the
-- admin dashboard can control who absorbs the discount cost per promo:
--   - 'platform'  → platform absorbs 100% (current default behavior)
--   - 'merchant'  → merchant absorbs 100% (deducted from merchant_payout)
--   - 'shared'    → split by merchant_share_pct (merchant %) / remainder (platform %)
--
-- Also adds `merchant_discount_floor` to platform_config — a configurable
-- EGP threshold below which the platform absorbs 100% of any shared discount.
-- Default is 0 (no floor). Editable from Admin → Settings without code changes.

BEGIN;

-- =============================================================================
-- 1. PROMO CODES — FUNDING MODEL COLUMNS
-- =============================================================================
ALTER TABLE public.promo_codes
  ADD COLUMN IF NOT EXISTS funded_by TEXT NOT NULL DEFAULT 'platform'
    CHECK (funded_by IN ('platform', 'merchant', 'shared')),
  ADD COLUMN IF NOT EXISTS merchant_share_pct NUMERIC(5,2) NOT NULL DEFAULT 50.00
    CHECK (merchant_share_pct >= 0 AND merchant_share_pct <= 100);

COMMENT ON COLUMN public.promo_codes.funded_by IS
  'Who absorbs the discount cost: platform (100% platform), merchant (100% merchant), shared (split by merchant_share_pct). Configurable per-promo from the admin dashboard.';
COMMENT ON COLUMN public.promo_codes.merchant_share_pct IS
  'When funded_by=shared, the percentage of the discount amount absorbed by the merchant (0-100). Remainder is absorbed by the platform. Default 50%. Only meaningful when funded_by=shared.';

-- =============================================================================
-- 2. PLATFORM CONFIG — MERCHANT DISCOUNT FLOOR
-- =============================================================================
-- Admins can set this in Settings → ORDER_LIFECYCLE_LIMITS.
-- When funded_by='shared' and discount_amount <= this floor, the platform
-- absorbs 100% (merchant_share becomes 0). This protects merchants from
-- being charged for tiny discounts. Default 0 = no floor.
INSERT INTO public.platform_config (key, value, description, value_type)
VALUES (
  'merchant_discount_floor',
  '0',
  'EGP floor below which platform absorbs 100% of shared promo discounts. Set to 0 to disable.',
  'number'
)
ON CONFLICT (key) DO NOTHING;

COMMIT;
