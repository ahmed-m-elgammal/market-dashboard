-- Migration 094: Payment MVP hardening (G5/G6/G7/G8/G9 from docs/plans/payment-service-implementation-plan.md)
--
-- Five verified payment gaps, fixed with minimal surface:
--   G5  Digital orders are dispatched BEFORE payment confirmation
--       (place-order fire-and-forget assigns regardless of payment_status).
--       Fix: payment_dispatch_gating platform_config flag (default OFF) +
--       webhook/reconcile assign-on-paid takeover (Edge Function changes).
--   G6  cancel_stale_orders() (077) filters only on status + created_at —
--       once gating lands it would auto-cancel paid-but-unassigned orders
--       waiting for their webhook. Fix: payment-aware WHERE clauses below.
--   G7  Webhook success callbacks are not deduplicated: two concurrent
--       callbacks (Paymob retries / double delivery) both pass the
--       read-then-write check and both push a notification.
--       Fix: atomic test-and-set UPDATE guarded on payment_status (EF side).
--   G8  No paid_at timestamp — finance cannot distinguish capture time from
--       row-update time. Fix: orders.paid_at column here, stamped by
--       paymob-webhook + reconcile-payments + wallet-free paths.
--   G9  refund_failed / pending_refund orders retry silently forever.
--       Fix: 'payment_refunds_stuck' alert metric + seeded alert rule.
--
-- Also included (directly supporting the above):
--   - Unique index on orders.paymob_order_id (webhook hot-path lookup was a
--     sequential scan; uniqueness also backs the webhook order lookup).
--   - Partial index for the reconcile refund sweep + stuck-refund metric.
--   - 'payment_paid_unassigned' alert metric + rule: ops visibility for
--     paid orders that never got a driver (the reason rule 2 of
--     cancel_stale_orders now skips paid orders instead of cancelling them).

-- =============================================================================
-- 1. G8: paid_at capture timestamp
-- =============================================================================
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ;

COMMENT ON COLUMN public.orders.paid_at IS
  'When the digital payment was confirmed (webhook / reconcile / place-order for pre-paid methods). NULL = not yet captured. Never backfilled — historic rows stay NULL.';

-- =============================================================================
-- 2. Indexes supporting webhook lookup, reconcile sweeps and alert metrics
-- =============================================================================

-- Webhook hot path: looked up by paymob_order_id with NO index before this
-- (sequential scan on every callback). UNIQUE also guarantees a Paymob order
-- maps to at most one of our orders.
CREATE UNIQUE INDEX IF NOT EXISTS idx_orders_paymob_order_id
  ON public.orders(paymob_order_id)
  WHERE paymob_order_id IS NOT NULL;

-- Reconcile refund loop (.in refund_status + .gt refund_amount, ordered by
-- created_at) and the payment_refunds_stuck alert metric.
CREATE INDEX IF NOT EXISTS idx_orders_refund_sweep
  ON public.orders(refund_status, created_at)
  WHERE refund_status IN ('pending_refund', 'refund_failed');

-- =============================================================================
-- 3. G5: payment_dispatch_gating flag (ships OFF — rollout flips it)
-- =============================================================================
INSERT INTO public.platform_config (key, value, description, value_type, is_editable)
VALUES (
  'payment_dispatch_gating',
  'false',
  'When true, digital-payment orders are only assigned a driver AFTER payment confirmation (paymob-webhook / reconcile-payments assign on paid). Cash orders are always assigned immediately.',
  'boolean',
  TRUE
)
ON CONFLICT (key) DO NOTHING;

-- =============================================================================
-- 4. G9: alert metrics + rules
-- =============================================================================
-- check_and_trigger_alerts (058, still the canonical body — 074 only references
-- it in a comment) hardcodes its metric list, so new metrics require
-- recreating the function with the two new branches appended.

CREATE OR REPLACE FUNCTION public.check_and_trigger_alerts()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  r RECORD;
  v_val NUMERIC;
  v_triggered BOOLEAN;
  v_msg TEXT;
BEGIN
  FOR r IN SELECT * FROM public.alert_rules WHERE is_active = true LOOP
    -- Evaluate metric
    IF r.metric = 'online_drivers' THEN
      SELECT COUNT(*) INTO v_val FROM public.drivers WHERE is_online = true;
    ELSIF r.metric = 'order_cancellation_rate' THEN
      SELECT COALESCE(ROUND(100.0 * COUNT(*) FILTER (WHERE status = 'cancelled') / NULLIF(COUNT(*), 0), 2), 0)
      INTO v_val FROM public.orders WHERE created_at >= NOW() - INTERVAL '1 hour';
    ELSIF r.metric = 'payment_failures_5min' OR r.metric = 'payment_failures' THEN
      SELECT COUNT(*) INTO v_val FROM public.orders WHERE payment_status = 'failed' AND updated_at >= NOW() - INTERVAL '5 minutes';
    ELSIF r.metric = 'pending_verifications_24h' OR r.metric = 'pending_verifications' THEN
      SELECT COUNT(*) INTO v_val FROM public.drivers WHERE verification_status = 'pending' AND created_at <= NOW() - INTERVAL '24 hours';
    ELSIF r.metric = 'avg_delivery_time_minutes' THEN
      SELECT COALESCE(ROUND(AVG(EXTRACT(EPOCH FROM (delivered_at - created_at)) / 60)::numeric, 1), 0)
      INTO v_val FROM public.orders WHERE status = 'delivered' AND delivered_at >= NOW() - INTERVAL '1 hour';
    ELSIF r.metric = 'driver_rating_avg' OR r.metric = 'driver_low_rating' THEN
      SELECT COALESCE(MIN(rating), 5.0) INTO v_val FROM public.drivers WHERE total_deliveries >= 10;
    ELSIF r.metric = 'pending_orders' THEN
      SELECT COUNT(*) INTO v_val FROM public.orders WHERE status = 'pending';
    ELSIF r.metric = 'active_orders' THEN
      SELECT COUNT(*) INTO v_val FROM public.orders WHERE status NOT IN ('delivered', 'cancelled');
    ELSIF r.metric = 'revenue_today' THEN
      SELECT COALESCE(SUM(platform_fee + delivery_fee), 0) INTO v_val FROM public.orders WHERE status = 'delivered' AND delivered_at >= CURRENT_DATE;
    ELSIF r.metric = 'payment_refunds_stuck' THEN
      -- G9: refunds stuck > 1h. updated_at is bumped on ANY order update, so
      -- "no update in the last hour while still in a refund-pending state"
      -- means the reconcile cron is not making progress on it.
      SELECT COUNT(*) INTO v_val FROM public.orders
      WHERE refund_status IN ('pending_refund', 'refund_failed')
        AND refund_amount > 0
        AND updated_at <= NOW() - INTERVAL '1 hour';
    ELSIF r.metric = 'payment_paid_unassigned' THEN
      -- G5 companion: paid orders still without a driver after 15 minutes.
      -- With dispatch gating ON these mean the webhook AND the reconcile
      -- fallback both failed to assign; with gating OFF they mean the
      -- place-order assignment itself failed. Either way ops must look.
      SELECT COUNT(*) INTO v_val FROM public.orders
      WHERE payment_status = 'paid'
        AND driver_id IS NULL
        AND status NOT IN ('delivered', 'cancelled')
        AND updated_at <= NOW() - INTERVAL '15 minutes';
    ELSIF r.metric = 'storage_usage_pct' THEN
      v_val := 42.5; -- Simulated typical storage usage
    ELSIF r.metric = 'rate_limit_usage_pct' THEN
      v_val := 84.2; -- Simulated approaching limit (will trigger the default seed alert)
    ELSE
      v_val := 0;
    END IF;

    -- Evaluate condition
    v_triggered := false;
    IF r.condition = 'less_than' THEN
      IF v_val < r.threshold THEN v_triggered := true; END IF;
    ELSIF r.condition = 'greater_than' THEN
      IF v_val > r.threshold THEN v_triggered := true; END IF;
    ELSIF r.condition = 'equals' THEN
      IF v_val = r.threshold THEN v_triggered := true; END IF;
    END IF;

    -- Handle incident state
    IF v_triggered THEN
      -- If active incident does not exist, insert it
      IF NOT EXISTS (
        SELECT 1 FROM public.alert_incidents
        WHERE rule_id = r.id AND status IN ('triggered', 'acknowledged')
      ) THEN
        v_msg := 'Rule "' || r.name || '" breached threshold. Current metric value for ' || r.metric || ' is ' || v_val || ' (Condition: ' || r.condition || ' ' || r.threshold || ').';
        INSERT INTO public.alert_incidents (rule_id, metric, severity, message, trigger_value, status, triggered_at)
        VALUES (r.id, r.metric, r.severity, v_msg, v_val, 'triggered', NOW());
      END IF;
    ELSE
      -- If active incident exists, automatically resolve it
      UPDATE public.alert_incidents
      SET status = 'resolved',
          resolved_at = NOW(),
          resolution_notes = 'Automatically resolved: metric value (' || v_val || ') no longer breaches threshold.'
      WHERE rule_id = r.id AND status IN ('triggered', 'acknowledged');
    END IF;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.check_and_trigger_alerts() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_and_trigger_alerts() TO service_role;

-- Seed the two rules (guarded — alert_rules has no unique constraint on metric).
INSERT INTO public.alert_rules (name, description, metric, condition, threshold, duration_seconds, severity, is_active, notification_channels)
SELECT
  'Stuck Payment Refunds',
  'Orders sitting in pending_refund / refund_failed for more than 1 hour (reconcile cron not making progress)',
  'payment_refunds_stuck', 'greater_than', 0, 3600, 'critical',
  true, ARRAY['slack', 'email', 'admin_panel']
WHERE NOT EXISTS (SELECT 1 FROM public.alert_rules WHERE metric = 'payment_refunds_stuck');

INSERT INTO public.alert_rules (name, description, metric, condition, threshold, duration_seconds, severity, is_active, notification_channels)
SELECT
  'Paid Orders Without Driver',
  'Paid orders without an assigned driver for more than 15 minutes',
  'payment_paid_unassigned', 'greater_than', 0, 900, 'warning',
  true, ARRAY['admin_panel']
WHERE NOT EXISTS (SELECT 1 FROM public.alert_rules WHERE metric = 'payment_paid_unassigned');

-- =============================================================================
-- 5. G6: payment-aware cancel_stale_orders()
-- =============================================================================
-- Recreation of 077's function with payment-aware WHERE clauses. Rules 1 and 2
-- now skip orders where money is involved; rule 3 is DELIBERATELY unchanged —
-- a paid order stuck at 'ready' (prepared, never picked up) SHOULD be
-- auto-cancelled after its timeout, because cancel_order (088) recomputes the
-- refund from cancellation_rules and reconcile-payments executes it: the sweep
-- is the self-healing path there, not a money-loss path.
--
-- CREATE OR REPLACE keeps the 077 ACL (EXECUTE revoked from PUBLIC, granted to
-- service_role) because the signature and return type are unchanged; the
-- REVOKE/GRANT is re-asserted below as belt-and-braces. The pg_cron entry
-- ('cancel-stale-orders', every minute) is untouched by this recreation.

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
  -- G6: with payment dispatch gating ON, a paid digital order legitimately
  -- sits at status='pending' waiting for the webhook/reconcile assign. Never
  -- sweep it — payment_status <> 'paid' is the guard.
  v_minutes := COALESCE((v_config->>'auto_cancel_pending_minutes')::INT, 15);
  FOR v_order IN
    SELECT id FROM public.orders
    WHERE status = 'pending'
      AND payment_status IS DISTINCT FROM 'paid'
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
  -- G6: skip paid orders (customer already charged — surface them via the
  -- 'payment_paid_unassigned' alert instead of silently cancelling) and skip
  -- orders already queued for a refund (an admin refund is in flight; a
  -- cancel here would overwrite refund_amount/refund_status mid-flight).
  v_minutes := COALESCE((v_config->>'auto_cancel_no_driver_minutes')::INT, 30);
  FOR v_order IN
    SELECT id FROM public.orders
    WHERE status = 'confirmed' AND driver_id IS NULL
      AND payment_status IS DISTINCT FROM 'paid'
      AND (refund_status IS NULL OR refund_status NOT IN ('pending_refund', 'refund_failed'))
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

  -- Rule 3: ready orders (no pickup) past threshold — UNCHANGED by 094.
  -- A paid order reaching 'ready' then expiring SHOULD be swept: cancel_order
  -- recomputes the refund from cancellation_rules and reconcile-payments
  -- executes it, so this is the correct self-healing path.
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
  'W1.2 (patched by 094): pg_cron replacement for auto-cancel-stale-orders EF. Cancels orders stuck in pending/confirmed/ready past configurable timeouts. 094: pending + confirmed-no-driver rules skip paid / in-refund orders (money-linked orders surface via payment alerts instead). Also cleans up expired admin sessions.';

REVOKE EXECUTE ON FUNCTION public.cancel_stale_orders() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cancel_stale_orders() TO service_role;
