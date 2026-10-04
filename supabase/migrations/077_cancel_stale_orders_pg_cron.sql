-- Migration 077: Move auto-cancel-stale-orders from Edge Function to pg_cron
--
-- Previously the auto-cancel-stale-orders logic lived in a Deno Edge Function
-- at supabase/functions/auto-cancel-stale-orders/index.ts scheduled via
-- config.toml. That EF did pure DB work (read config → query orders → call
-- RPCs) with zero HTTP/API calls, so pg_cron is a better fit:
--   • No cold-start overhead every minute
--   • Postgres internal scheduler (more reliable)
--   • Fewer infrastructure pieces to maintain
--
-- The Edge Function source file is kept for reference; it will no longer be
-- scheduled in config.toml.

-- =============================================================================
-- 1. cancel_stale_orders() — pure-SQL replacement for the Edge Function
-- =============================================================================
CREATE OR REPLACE FUNCTION public.cancel_stale_orders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_config JSONB;
  v_order RECORD;
  v_minutes INT;
  v_cancelled INT := 0;
  v_failed INT := 0;
  v_session_cleaned INT;
BEGIN
  -- pg_cron doesn't set request.jwt.claims, but cancel_order RPC requires it for
  -- its service-role guard. Set it ourselves — safe because we're SECURITY DEFINER
  -- and this is an internal cron, not user-invokable.
  PERFORM set_config('request.jwt.claims', '{"role": "service_role"}', true);

  -- Batch-fetch all config thresholds in one query
  SELECT jsonb_object_agg(key, value) INTO v_config
  FROM public.platform_config
  WHERE key IN (
    'auto_cancel_pending_minutes',
    'auto_cancel_no_driver_minutes',
    'auto_cancel_ready_timeout_minutes'
  );

  -- Rule 1: pending orders past threshold
  v_minutes := COALESCE((v_config->>'auto_cancel_pending_minutes')::INT, 15);
  FOR v_order IN
    SELECT id FROM public.orders
    WHERE status = 'pending'
      AND created_at < NOW() - (v_minutes || ' minutes')::INTERVAL
    ORDER BY created_at ASC
    LIMIT 50
  LOOP
    BEGIN
      PERFORM public.cancel_order(v_order.id, NULL::UUID, 'system',
        'Auto-cancelled: merchant did not confirm within timeout');
      v_cancelled := v_cancelled + 1;
    EXCEPTION WHEN OTHERS THEN
      v_failed := v_failed + 1;
      RAISE WARNING 'cancel_stale_orders: failed to cancel order % (pending rule): %',
        v_order.id, SQLERRM;
    END;
  END LOOP;

  -- Rule 2: confirmed + no driver past threshold
  v_minutes := COALESCE((v_config->>'auto_cancel_no_driver_minutes')::INT, 30);
  FOR v_order IN
    SELECT id FROM public.orders
    WHERE status = 'confirmed' AND driver_id IS NULL
      AND created_at < NOW() - (v_minutes || ' minutes')::INTERVAL
    ORDER BY created_at ASC
    LIMIT 50
  LOOP
    BEGIN
      PERFORM public.cancel_order(v_order.id, NULL::UUID, 'system',
        'Auto-cancelled: no driver assigned within timeout');
      v_cancelled := v_cancelled + 1;
    EXCEPTION WHEN OTHERS THEN
      v_failed := v_failed + 1;
      RAISE WARNING 'cancel_stale_orders: failed to cancel order % (no-driver rule): %',
        v_order.id, SQLERRM;
    END;
  END LOOP;

  -- Rule 3: ready orders (no pickup) past threshold
  v_minutes := COALESCE((v_config->>'auto_cancel_ready_timeout_minutes')::INT, 60);
  FOR v_order IN
    SELECT id FROM public.orders
    WHERE status = 'ready'
      AND created_at < NOW() - (v_minutes || ' minutes')::INTERVAL
    ORDER BY created_at ASC
    LIMIT 50
  LOOP
    BEGIN
      PERFORM public.cancel_order(v_order.id, NULL::UUID, 'system',
        'Auto-cancelled: order not picked up within timeout');
      v_cancelled := v_cancelled + 1;
    EXCEPTION WHEN OTHERS THEN
      v_failed := v_failed + 1;
      RAISE WARNING 'cancel_stale_orders: failed to cancel order % (ready rule): %',
        v_order.id, SQLERRM;
    END;
  END LOOP;

  -- B1-G5: cleanup expired admin sessions
  SELECT public.cleanup_expired_admin_sessions() INTO v_session_cleaned;

  RAISE NOTICE 'cancel_stale_orders complete: cancelled=%, failed=%, sessions_cleaned=%',
    v_cancelled, v_failed, v_session_cleaned;
END;
$$;

COMMENT ON FUNCTION public.cancel_stale_orders() IS
  'W1.2: pg_cron replacement for auto-cancel-stale-orders EF. Cancels orders stuck in pending/confirmed/ready statuses past configurable timeouts. Also cleans up expired admin sessions.';

REVOKE EXECUTE ON FUNCTION public.cancel_stale_orders() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cancel_stale_orders() TO service_role;

-- =============================================================================
-- 2. Schedule via pg_cron (every minute)
-- =============================================================================
SELECT cron.schedule('cancel-stale-orders', '* * * * *', $$SELECT public.cancel_stale_orders()$$);
