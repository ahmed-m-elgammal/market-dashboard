-- Migration 090: Promoted slot scheduling-conflict check
--
-- P1-3 fix (MARKETING-IMPROVEMENT-PLAN.md Task 1.5):
-- Two active promoted_slots with the same slot_type + city + category and
-- overlapping [starts_at, expires_at] windows will both be served by the
-- get-merchant-feed Edge Function — the customer sees two "top" merchants.
-- This migration adds a PL/pgSQL function the admin API calls before
-- insert/update to reject overlapping bookings.
--
-- Conflict rule:
--   same slot_type + same city + same category (NULL = NULL via COALESCE
--   sentinel) + overlapping time interval + is_active = TRUE.
--   Different categories can coexist (a restaurant feed_top and a pharmacy
--   feed_top in Cairo at the same time is fine — different audiences).
--
-- The function returns TRUE if NO overlap exists (safe to proceed),
-- FALSE if a conflict was found.

CREATE OR REPLACE FUNCTION public.fn_check_promoted_slot_overlap(
  p_slot_type TEXT,
  p_city TEXT,
  p_category TEXT,
  p_starts_at TIMESTAMPTZ,
  p_expires_at TIMESTAMPTZ,
  p_exclude_id UUID DEFAULT NULL
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  -- Count active slots that conflict with the proposed booking.
  -- Overlap test: existing.starts_at < proposed.expires_at
  --                AND existing.expires_at > proposed.starts_at
  -- (half-open intervals; touching endpoints do NOT conflict.)
  SELECT COUNT(*) INTO v_count
  FROM public.promoted_slots
  WHERE is_active = TRUE
    AND slot_type = p_slot_type
    AND city = p_city
    AND COALESCE(category, '__ALL__') = COALESCE(p_category, '__ALL__')
    AND starts_at < p_expires_at
    AND expires_at > p_starts_at
    AND (p_exclude_id IS NULL OR id != p_exclude_id);

  -- TRUE = no overlap (safe), FALSE = conflict found
  RETURN v_count = 0;
END;
$$;

COMMENT ON FUNCTION public.fn_check_promoted_slot_overlap(TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, UUID) IS
  'P1-3: Returns TRUE if no active promoted_slot overlaps the proposed (slot_type, city, category, [starts_at, expires_at]) window. p_exclude_id skips the row being updated (for PUT self-update). SECURITY DEFINER so the admin API (service role) can call it.';

REVOKE EXECUTE ON FUNCTION public.fn_check_promoted_slot_overlap(TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_check_promoted_slot_overlap(TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, UUID) TO service_role;
