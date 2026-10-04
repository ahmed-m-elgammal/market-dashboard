-- Migration 115: Drop the plaintext bank columns (product decision)
--
-- DECISION
--   Merchant payouts are HUMAN-IN-THE-LOOP ONLY. Cash is handed over directly,
--   or money is sent by Vodafone Cash directly, both performed manually by a
--   person. Nothing is automated. Therefore the columns that exist purely to
--   feed an automated bank transfer are removed rather than encrypted.
--
--   The alternative -- applying the migration 027 national_id encryption
--   pattern -- is deliberately NOT taken: encrypting a column that no automated
--   process reads is effort spent defending data nobody needs.
--
-- WHAT IS DROPPED, AND WHY EACH
--   bank_account_number    the plaintext secret; the whole reason this column
--                          was flagged. Dropped.
--   bank_account_holder    only meaningful alongside an account number.
--                          Dropped.
--   bank_name              only meaningful alongside an account number.
--                          Dropped.
--
-- WHAT IS KEPT, AND WHY
--   payout_frequency       still useful for the manual ledger -- it records
--                          whether a merchant expects weekly or monthly
--                          settlement, which is what the auto-generate EFs read.
--   payout_method          'cash' and 'wallet' are exactly the two manual
--                          channels in use. Keeping it means the ledger records
--                          HOW a human settled, which is the audit trail.
--   wallet_phone           the Vodafone Cash number is the reference a human
--                          matches against their own confirmation. Dropping it
--                          would destroy reconciliation. Keep.
--
--   If you would rather have no financial columns on merchants at all, say so
--   and this becomes DROP COLUMN payout_frequency, payout_method, wallet_phone
--   as well -- but then the manual ledger loses its method and reference, and
--   merchant_payouts (085) has nowhere to record them.
--
-- IMPACT
--   No code may read these columns. Verified before writing this migration:
--   the four names appear only in 085 (which created them), its COMMENTs, and
--   admin dashboard forms. merchant_payouts does not reference them -- its
--   create_merchant_payout() takes the method as an argument instead.
--
-- Rollback: recreate the matview, then:
--           ALTER TABLE public.merchants
--             ADD COLUMN bank_account_number TEXT,
--             ADD COLUMN bank_account_holder TEXT,
--             ADD COLUMN bank_name TEXT;
--           Values are NOT recoverable -- they were dropped, not archived. If
--           any were recorded, re-enter them.

-- =============================================================================
-- 1. PRE-FLIGHT: warn if anything was ever stored
-- =============================================================================
DO $$
DECLARE
  v_bank_rows INTEGER;
  v_wallet_rows INTEGER;
BEGIN
  SELECT count(*) INTO v_bank_rows
    FROM public.merchants
   WHERE bank_account_number IS NOT NULL
      OR bank_account_holder IS NOT NULL
      OR bank_name IS NOT NULL;

  SELECT count(*) INTO v_wallet_rows
    FROM public.merchants
   WHERE wallet_phone IS NOT NULL;

  IF v_bank_rows > 0 THEN
    RAISE WARNING
      'migration 115: % merchant(s) have bank details that will be DELETED, not archived. Capture them first if they are needed.', v_bank_rows;
  END IF;
  IF v_wallet_rows > 0 THEN
    RAISE NOTICE
      'migration 115: % merchant(s) have a wallet_phone, which is KEPT.', v_wallet_rows;
  END IF;
END
$$;

-- =============================================================================
-- 2. DROP THE DEPENDENT MATERIALIZED VIEW FIRST
-- =============================================================================
-- Migration 113 rebuilt this view as SELECT m.*, which means it now holds a
-- column reference to every merchants column -- including the three being
-- dropped here. Postgres refuses the DROP while that dependency exists.
--
-- So: drop the view, drop the columns, recreate the view. The recreation is
-- identical to 113's definition, which is the point of having made it m.* --
-- there is no hand-maintained column list to update.
DROP MATERIALIZED VIEW IF EXISTS public.merchants_with_open_status;

-- =============================================================================
-- 3. DROP THE COLUMNS
-- =============================================================================
ALTER TABLE public.merchants
  DROP COLUMN IF EXISTS bank_account_number,
  DROP COLUMN IF EXISTS bank_account_holder,
  DROP COLUMN IF EXISTS bank_name;

-- =============================================================================
-- 4. RECREATE THE MATERIALIZED VIEW
-- =============================================================================
CREATE MATERIALIZED VIEW public.merchants_with_open_status AS
SELECT
  m.*,
  EXISTS (
    SELECT 1
      FROM public.operating_hours oh
     WHERE oh.merchant_id = m.id
       AND oh.day_of_week = EXTRACT(ISODOW FROM NOW() AT TIME ZONE 'Africa/Cairo')
       AND oh.is_closed = FALSE
       AND (NOW() AT TIME ZONE 'Africa/Cairo')::TIME >= oh.open_time
       AND (NOW() AT TIME ZONE 'Africa/Cairo')::TIME <  oh.close_time
  ) AS is_currently_open
FROM public.merchants m
WHERE m.is_active = TRUE
  AND m.approval_status = 'approved';

CREATE UNIQUE INDEX idx_merchants_open_status_id
  ON public.merchants_with_open_status(id);

CREATE INDEX idx_merchants_open_status_city_category
  ON public.merchants_with_open_status(city, category);

CREATE INDEX idx_merchants_open_status_open
  ON public.merchants_with_open_status(is_currently_open)
  WHERE is_currently_open = TRUE;

GRANT SELECT ON public.merchants_with_open_status TO authenticated, anon;

-- =============================================================================
-- 5. DOCUMENT WHAT REMAINS AND WHY
-- =============================================================================
COMMENT ON COLUMN public.merchants.payout_method IS
  'Manual settlement channel. Payouts are human-in-the-loop: cash handed over directly, or money sent by Vodafone Cash directly. No automation. bank_transfer remains a valid value for merchants who are settled by an operator over manual bank transfer -- the operator does the transfer, the system only records it.';

COMMENT ON COLUMN public.merchants.wallet_phone IS
  'Vodafone Cash / wallet number used for manual settlement. KEPT in migration 115 while the bank columns were dropped: a human matching a payment needs the reference they sent to. Not sensitive in the way an account number + bank name pair is, and not machine-readable by any automated process.';

COMMENT ON TABLE public.merchants IS
  'Vendors (restaurants, pharmacies, groceries, markets, bakeries, butchers, flower shops, other). Core entity for the marketplace. Merchant settlement is MANUAL and human-in-the-loop -- cash by hand or Vodafone Cash by hand. Migration 115 removed the bank_account_* columns because nothing automated reads them. Net data change: three columns dropped, values not archived.';