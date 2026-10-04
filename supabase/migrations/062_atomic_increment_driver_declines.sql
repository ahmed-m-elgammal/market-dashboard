-- Migration 062: Atomic increment_driver_declines RPC (A4-G2)
--
-- The handleDriverRespond decline path in driver-actions/index.ts uses a
-- non-atomic read-then-write pattern to track consecutive declines:
--
--   SELECT consecutive_declines FROM drivers WHERE id = $1;
--   nextDeclines = current + 1;
--   UPDATE drivers SET consecutive_declines = nextDeclines WHERE id = $1;
--   IF nextDeclines >= 3 THEN
--     UPDATE drivers SET suspended_until = NOW() + 1h, is_online = false,
--       consecutive_declines = 0 WHERE id = $1;
--
-- Two concurrent declines by the same driver (e.g., double-tap on two
-- orders at once) both read the same value, both compute the same nextDeclines,
-- and both write it — the counter ends at N+1 instead of N+2. Worse, the
-- suspension decision is racy: if the two reads happen when current=2, both
-- compute nextDeclines=3 and both apply suspension with slightly different
-- suspended_until timestamps (different Date.now()).
--
-- Fix: create an atomic increment_driver_declines RPC that:
--   1. Atomically increments consecutive_declines (SQL-level, no read gap).
--   2. Returns the NEW value so the caller can decide whether to suspend.
--   3. Is SECURITY DEFINER, SET search_path = '', service-role only —
--      matches the pattern of increment_driver_stats (migration 044).
--
-- The suspension logic (3-strike → suspended_until + is_online=false +
-- reset counter) stays in the EF because it involves a timestamp
-- computation that's cleaner in TypeScript. But the counter increment
-- itself is now atomic, and the suspension UPDATE is conditional on the
-- returned new value being >= 3.

CREATE OR REPLACE FUNCTION public.increment_driver_declines(
  p_driver_id UUID
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_new_count INTEGER;
BEGIN
  -- SECURITY: Service-role only. Prevents any authenticated user from
  -- calling this RPC directly to inflate their own or others' decline count.
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: increment_driver_declines is service-role only.';
  END IF;

  -- Atomic conditional increment. Returns the new value, or NULL if the
  -- driver row doesn't exist (caller should handle, but in practice the EF
  -- already verified the driver via requireVerifiedDriver).
  UPDATE public.drivers
    SET consecutive_declines = COALESCE(consecutive_declines, 0) + 1
    WHERE id = p_driver_id
    RETURNING consecutive_declines INTO v_new_count;

  RETURN v_new_count;
END;
$$;

COMMENT ON FUNCTION public.increment_driver_declines(UUID) IS
  'A4-G2: Atomic consecutive_declines increment. SECURITY DEFINER, service-role only, hardened with SET search_path = "". Returns the new count so the caller can apply 3-strike suspension. See migration 062.';

REVOKE EXECUTE ON FUNCTION public.increment_driver_declines(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.increment_driver_declines(UUID) TO service_role;
