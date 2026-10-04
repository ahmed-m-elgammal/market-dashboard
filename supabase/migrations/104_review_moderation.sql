-- Migration 104: reviews hidden-by-default moderation (pre-launch policy)
--
-- POLICY: no review is publicly visible until Ops approves it. Rationale:
-- pre-launch, one bad review can cost merchants/drivers before the ops team
-- even sees why. Reuses the reviews table in place (like 103 did merchants).
--
-- Changes (all additive, zero backfill issue — live has 0 reviews):
--   1. reviews.is_visible BOOLEAN NOT NULL DEFAULT FALSE (+ moderated_by/at,
--      moderation_note). New inserts land hidden automatically.
--   2. update_merchant_rating / update_driver_rating count ONLY visible
--      reviews (else hidden reviews would move public stars).
--   3. get_merchant_review_summary counts ONLY visible reviews.
--   4. reviews_read policy restricted to is_visible rows for anon/authenticated.
--      Service role bypasses RLS (dashboard moderation unaffected). Users still
--      cannot UPDATE/DELETE (immutability preserved — moderation is
--      service-role-only via the dashboard).
--   5. Partial index for the now-standard visible-only merchant read.
-- Net data change: none (DDL only).

ALTER TABLE public.reviews
  ADD COLUMN IF NOT EXISTS is_visible BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS moderated_by UUID REFERENCES public.profiles(id),
  ADD COLUMN IF NOT EXISTS moderated_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS moderation_note TEXT;

COMMENT ON COLUMN public.reviews.is_visible IS
  'Moderation gate (104): FALSE=new review awaiting Ops, TRUE=approved and public. Aggregates, summary RPC, and public reads all filter on this.';

-- --- aggregates: visible-only -------------------------------------------
CREATE OR REPLACE FUNCTION public.update_merchant_rating(p_merchant_id UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  v_avg_rating NUMERIC;
  v_rating_count INTEGER;
BEGIN
  SELECT
    ROUND(AVG(merchant_rating), 1),
    COUNT(*)
  INTO v_avg_rating, v_rating_count
  FROM public.reviews
  WHERE merchant_id = p_merchant_id
    AND is_visible = TRUE;

  UPDATE public.merchants
  SET
    rating = COALESCE(v_avg_rating, 0.0),
    rating_count = COALESCE(v_rating_count, 0)
  WHERE id = p_merchant_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_driver_rating(p_driver_id UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  v_avg_rating NUMERIC;
  v_rating_count INTEGER;
BEGIN
  SELECT
    ROUND(AVG(driver_rating), 1),
    COUNT(driver_rating)
  INTO v_avg_rating, v_rating_count
  FROM public.reviews
  WHERE driver_id = p_driver_id
    AND driver_rating IS NOT NULL
    AND is_visible = TRUE;

  UPDATE public.drivers
  SET
    rating = COALESCE(v_avg_rating, 5.0),
    rating_count = COALESCE(v_rating_count, 0)
  WHERE id = p_driver_id;
END;
$$;

-- --- summary RPC: visible-only -------------------------------------------
CREATE OR REPLACE FUNCTION public.get_merchant_review_summary(p_merchant_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_average_rating NUMERIC;
  v_total_count BIGINT;
  v_distribution JSON;
BEGIN
  SELECT
    COALESCE(ROUND(AVG(merchant_rating)::NUMERIC, 1), 0.0),
    COUNT(*),
    JSON_BUILD_ARRAY(
      COUNT(*) FILTER (WHERE merchant_rating = 1),
      COUNT(*) FILTER (WHERE merchant_rating = 2),
      COUNT(*) FILTER (WHERE merchant_rating = 3),
      COUNT(*) FILTER (WHERE merchant_rating = 4),
      COUNT(*) FILTER (WHERE merchant_rating = 5)
    )
  INTO v_average_rating, v_total_count, v_distribution
  FROM public.reviews
  WHERE merchant_id = p_merchant_id
    AND is_visible = TRUE;

  RETURN JSON_BUILD_OBJECT(
    'average_rating', v_average_rating,
    'total_count', v_total_count,
    'distribution', v_distribution
  );
END;
$$;

-- --- public read: visible rows only ---------------------------------------
DROP POLICY IF EXISTS "reviews_read" ON public.reviews;
CREATE POLICY "reviews_read_visible"
  ON public.reviews
  FOR SELECT
  USING (is_visible = TRUE);

CREATE INDEX IF NOT EXISTS idx_reviews_merchant_visible
  ON public.reviews(merchant_id, created_at DESC)
  WHERE is_visible = TRUE;

-- --- verify (loud, atomic) --------------------------------------------------
DO $verify104$
DECLARE
  v_def TEXT;
BEGIN
  SELECT qual INTO v_def FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'reviews'
     AND policyname = 'reviews_read_visible';
  IF v_def IS NULL OR v_def NOT LIKE '%is_visible%' THEN
    RAISE EXCEPTION 'MIGRATION 104 VERIFY FAILED: reviews_read_visible missing or unfiltered';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'update_merchant_rating') THEN
    RAISE EXCEPTION 'MIGRATION 104 VERIFY FAILED: rating functions missing';
  END IF;
END;
$verify104$;
