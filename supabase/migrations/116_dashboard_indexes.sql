-- Migration 116: Indexes for the two dashboard queues (BUG-15, BUG-16)
--
-- Two screens the dashboard cannot render acceptably without an index. Both are
-- queues, both are operated continuously, and both were introduced by
-- migrations that added a filter column without indexing it.
--
-- BUG-15 -- merchants.approval_status is unindexed.
--   Migration 103 created the approval queue and, by default, new merchants as
--   pending. No index on merchants mentions approval_status, so the queue
--   filter falls back to a sequential scan.
--
--   Honest limitation: at 60 merchants the planner prefers a sequential scan
--   regardless, so this cannot be demonstrated by plan shape at launch
--   volumes. It is proven structurally and by before/after buffer counts in
--   dashborad/test/test_08_scale.py::test_approval_queue_cost_drops_when_indexed.
--   The index is cheap (partial, one column) and the queue grows monotonically
--   between review passes, so it is worth having before it is measurable.
--
-- BUG-16 -- the moderation queue cannot use the existing is_visible index.
--   An is_visible index DOES exist, added after 012:
--     idx_reviews_merchant_visible (merchant_id, created_at DESC)
--       WHERE is_visible = true
--   It serves exactly one query shape, "visible reviews for merchant X",
--   because:
--     * `is_visible = false` is outside the partial index by construction
--     * even `is_visible = true` alone cannot use it, merchant_id leads
--
--   So Ops' actual queue -- WHERE is_visible = FALSE ORDER BY created_at --
--   sequentially scans. Migration 104 made this the NORMAL state by defaulting
--   new reviews to hidden, so the backlog is not an edge case.
--
--   NOT claimed: the badge count `SELECT count(*) WHERE is_visible = false`
--   also seq-scans, but that is CORRECT behaviour, not a bug. Measured at 0.75ms
--   for 3,000 hidden rows, and PostgreSQL still prefers the scan even when a
--   matching partial index exists, because counting N narrow rows in one pass
--   beats walking N index entries. Only the ORDER BY queue benefits. Adding the
--   index below does not change the count's plan, by design.
--
-- Rollback: DROP INDEX public.idx_merchants_approval_pending;
--           DROP INDEX public.idx_reviews_pending;

-- =============================================================================
-- 1. APPROVAL QUEUE (BUG-15)
-- =============================================================================
-- Partial on the value the queue filters for: approved merchants are ~90% of
-- the table and are never in this queue, so indexing them would be waste.
-- created_at DESC matches the queue's ordering.
CREATE INDEX IF NOT EXISTS idx_merchants_approval_pending
  ON public.merchants(created_at DESC)
  WHERE approval_status = 'pending';

COMMENT ON INDEX public.idx_merchants_approval_pending IS
  'BUG-15 (migration 116): partial index for the merchant approval queue. Partial because approved merchants are never queued. Supports the dashboard''s pending-merchants list and its COUNT badge.';

-- =============================================================================
-- 2. MODERATION QUEUE (BUG-16)
-- =============================================================================
-- Partial on is_visible = false for the same reason: visible reviews are the
-- majority and are excluded. created ASC because moderation is FIFO -- the
-- oldest complaint is the most urgent.
CREATE INDEX IF NOT EXISTS idx_reviews_pending
  ON public.reviews(created_at ASC)
  WHERE is_visible = false;

COMMENT ON INDEX public.idx_reviews_pending IS
  'BUG-16 (migration 116): FIFO index for the review moderation queue. The pre-existing idx_reviews_merchant_visible is partial on is_visible = true and merchant_id-led, so it cannot serve WHERE is_visible = false. Supports the Ops queue; deliberately does not change the plan for the plain count, which is already cheap.';

-- =============================================================================
-- 3. NOT INDEXED, DELIBERATELY
-- =============================================================================
-- reviews.is_visible on its own -- a bare count over the hidden rows is a
-- sequential scan today and that is the right plan. Measured, not assumed; see
-- the header.
--
-- merchants.category alone -- already covered by idx_merchants_category_active
-- (098) and idx_merchants_city_category_active (005).
--
-- orders.status -- already covered by idx_orders_active (008), partial on the
-- non-terminal statuses.
--
-- items.category_id -- already the second column of
-- idx_items_merchant_category (007), which serves the menu query.