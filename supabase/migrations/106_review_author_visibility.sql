-- Migration 106: authors can see their own pending reviews
--
-- Follow-up to 104. The visible-only policy also hid a customer's OWN
-- pending review from themselves, which breaks two mobile paths with zero
-- mobile changes possible on old binaries:
--   canReview(order) reads own row to block duplicates -> would miss it ->
--     duplicate submit -> UNIQUE violation confusion.
--   submitReview().select().single() reads back the just-inserted hidden
--     row -> 0 rows -> false error despite success.
-- Fix: authors see own rows (still invisible to everyone else; aggregates
-- and summary stay visible-only). Old store builds keep working (DOD-10).
-- Net data change: none (policy only).

DROP POLICY IF EXISTS "reviews_read_visible" ON public.reviews;
CREATE POLICY "reviews_read_visible"
  ON public.reviews
  FOR SELECT
  USING (is_visible = TRUE OR customer_id = auth.uid());

DO $verify106$
DECLARE
  v_qual TEXT;
BEGIN
  SELECT qual INTO v_qual FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'reviews'
     AND policyname = 'reviews_read_visible';
  IF v_qual IS NULL OR v_qual NOT LIKE '%auth.uid()%' THEN
    RAISE EXCEPTION 'MIGRATION 106 VERIFY FAILED: author-visibility missing';
  END IF;
END;
$verify106$;
