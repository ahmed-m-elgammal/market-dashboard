-- Migration 070: Create promoted_slot_events table for time-series analytics
--
-- P1-6 (MARKETING-IMPROVEMENT-PLAN.md Task 2.6):
-- The promoted_slots table only stores cumulative impressions/clicks counters
-- (no time-series). The analytics tab shows a single snapshot — no daily/weekly
-- trend, no CTR-over-time chart. This migration adds an events table that
-- records each impression and click with a timestamp, enabling time-series
-- aggregation.
--
-- The cumulative counters on promoted_slots are kept as a fast counter for
-- the list-view badge; this events table is the source of truth for charts.
--
-- Note: the get-merchant-feed EF previously did NOT increment impressions
-- (despite migration 014's comment claiming it did). This migration + the
-- EF update in the same task finally wires up impression tracking.

CREATE TABLE promoted_slot_events (
  id BIGSERIAL PRIMARY KEY,
  slot_id UUID NOT NULL REFERENCES promoted_slots(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL CHECK (event_type IN ('impression', 'click')),
  customer_id UUID,  -- nullable for anonymous impressions
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index: fetch events for a slot, newest first (the timeseries query)
CREATE INDEX idx_slot_events_slot_time
  ON promoted_slot_events(slot_id, occurred_at DESC);

-- Index: fetch events by type over time (aggregate queries)
CREATE INDEX idx_slot_events_type_time
  ON promoted_slot_events(event_type, occurred_at DESC);

-- Index: cleanup old events (a future cron can DELETE WHERE occurred_at < NOW() - INTERVAL '90 days')
CREATE INDEX idx_slot_events_occurred_at
  ON promoted_slot_events(occurred_at);

COMMENT ON TABLE promoted_slot_events IS
  'P1-6: Per-event time-series for promoted slot impressions and clicks. The cumulative impressions/clicks columns on promoted_slots are kept as a fast counter; this table is the source of truth for charts.';

-- =============================================================================
-- RPCs: increment cumulative counters (called fire-and-forget from EFs)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.increment_promoted_slot_impressions(p_slot_ids UUID[])
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.promoted_slots
  SET impressions = impressions + 1
  WHERE id = ANY(p_slot_ids);
END;
$$;

CREATE OR REPLACE FUNCTION public.increment_promoted_slot_clicks(p_slot_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.promoted_slots
  SET clicks = clicks + 1
  WHERE id = p_slot_id;
END;
$$;

COMMENT ON FUNCTION public.increment_promoted_slot_impressions(UUID[]) IS
  'P1-6: Increment cumulative impressions counter for the given slot IDs. Called fire-and-forget from get-merchant-feed EF.';
COMMENT ON FUNCTION public.increment_promoted_slot_clicks(UUID) IS
  'P1-6: Increment cumulative clicks counter for a single slot. Called from the track-click endpoint.';

REVOKE EXECUTE ON FUNCTION public.increment_promoted_slot_impressions(UUID[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.increment_promoted_slot_impressions(UUID[]) TO service_role;

REVOKE EXECUTE ON FUNCTION public.increment_promoted_slot_clicks(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.increment_promoted_slot_clicks(UUID) TO service_role;
