-- Migration 079: Convert merchant_payout from GENERATED to regular column
--
-- S1 (money-movement-implementation-plan.md):
-- The orders.merchant_payout column was GENERATED ALWAYS AS:
--   subtotal - (subtotal * COALESCE(merchant_commission_pct, 0) / 100)
--
-- This formula ignores discounts entirely — the merchant always got paid on
-- the full subtotal regardless of who funded the promo. This migration:
--   1. Adds promo funding snapshot columns (promo_funded_by, promo_merchant_share_pct)
--      so we have forensic audit trail per-order.
--   2. Converts merchant_payout from GENERATED to a regular column so the
--      place_order_with_items RPC (migration 080) and cancel_order RPC
--      (migration 081) can compute/recompute it dynamically.
--
-- Strategy: Postgres does not allow ALTER on GENERATED columns. We:
--   a) Add a new regular column merchant_payout_v2
--   b) Backfill it from the existing GENERATED column
--   c) Drop the GENERATED column
--   d) Rename merchant_payout_v2 → merchant_payout
--
-- NOTE: The DROP COLUMN + RENAME briefly locks the orders table. At the
-- current scale (<10K rows), this takes <1 second. Run during low-traffic
-- window (02:00–04:00 EET) for safety.

BEGIN;

-- =============================================================================
-- STEP 1: Add promo funding snapshot columns
-- =============================================================================
-- These snapshot the promo's funding model at order time. If an admin later
-- changes a promo from 'shared' to 'platform', historical orders still show
-- the original funding model used for their payout calculation.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS promo_funded_by TEXT
    CHECK (promo_funded_by IS NULL OR promo_funded_by IN ('platform', 'merchant', 'shared')),
  ADD COLUMN IF NOT EXISTS promo_merchant_share_pct NUMERIC(5,2)
    CHECK (promo_merchant_share_pct IS NULL OR (promo_merchant_share_pct >= 0 AND promo_merchant_share_pct <= 100));

COMMENT ON COLUMN public.orders.promo_funded_by IS
  'Snapshot of promo_codes.funded_by at order time. NULL if no promo applied. For payout forensic audit.';
COMMENT ON COLUMN public.orders.promo_merchant_share_pct IS
  'Snapshot of promo_codes.merchant_share_pct at order time. NULL if no promo applied. For payout forensic audit.';

-- =============================================================================
-- STEP 2: Add the replacement column (not generated)
-- =============================================================================
-- Using a default of 0.00 — will be backfilled in Step 3.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS merchant_payout_v2 NUMERIC(10,2) DEFAULT 0.00;

-- =============================================================================
-- STEP 3: Backfill from the existing GENERATED column
-- =============================================================================
-- Copy current computed values so no data is lost.
UPDATE public.orders
  SET merchant_payout_v2 = merchant_payout;

-- =============================================================================
-- STEP 4: Drop the GENERATED column and rename
-- =============================================================================
ALTER TABLE public.orders DROP COLUMN merchant_payout;
ALTER TABLE public.orders RENAME COLUMN merchant_payout_v2 TO merchant_payout;

-- =============================================================================
-- STEP 5: Constraints on the new regular column
-- =============================================================================
ALTER TABLE public.orders ALTER COLUMN merchant_payout SET NOT NULL;
ALTER TABLE public.orders ALTER COLUMN merchant_payout SET DEFAULT 0.00;

-- Add a CHECK to prevent negative payouts
ALTER TABLE public.orders ADD CONSTRAINT chk_merchant_payout_non_negative
  CHECK (merchant_payout >= 0);

COMMENT ON COLUMN public.orders.merchant_payout IS
  'Net payout to merchant in EGP. Computed by place_order_with_items RPC using promo funded_by logic (subtotal - merchant discount share) * (1 - commission%). Recomputed by cancel_order RPC on cancellation. NO LONGER A GENERATED COLUMN since migration 079.';

COMMIT;
