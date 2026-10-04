// Edge Function: reconcile-payments
// A1-G5: Scheduled cron that reconciles stale `pending` digital-payment
// orders with Paymob's transaction status API.
//
// Problem: when a customer pays via Paymob (card, vodafone_cash, etc.), the
// order is created with payment_status='pending'. The paymob-webhook EF is
// supposed to update it to 'paid' or 'failed' on Paymob's callback. But:
//   - The webhook may be delayed or lost in transit.
//   - The webhook may arrive non-2xx (causing Paymob to retry, but the
//     retry may also fail).
//   - The customer may close the iframe before completing payment, leaving
//     the order in 'pending' forever.
//
// Without reconciliation, these orders sit in 'pending' indefinitely —
// clogging the active-orders dashboard and never releasing the customer's
// payment hold. The `auto_cancel_payment_timeout_minutes` config (default 10,
// seeded in migration 023) is read but never enforced.
//
// This EF runs on a Supabase cron schedule (every 5 minutes, configured in
// supabase/config.toml). For each stale pending digital-payment order:
//   1. Query Paymob's transaction status API.
//   2. If success=true, pending=false → mark order 'paid'.
//   3. If success=false, pending=false → mark order 'failed' and cancel it
//      via the cancel_order RPC (initiator='system').
//   4. If pending=true → leave alone, retry on next run.
//   5. If the order exceeds auto_cancel_payment_timeout_minutes since
//      creation AND Paymob still says pending → cancel it (the customer
//      abandoned the iframe).
//
// Auth: this EF is invoked by the Supabase cron scheduler with the service
// role key. No JWT auth — the schedule secret gate is sufficient.

import { corsResponse, handleOptions } from '../_shared/cors.ts';
import { errorResponse, successResponse } from '../_shared/errors.ts';
import { getSupabaseAdmin } from '../_shared/supabase.ts';
import { getPaymobTransactionStatus, refundPaymobPayment } from '../_shared/paymob.ts';
import { assignDriverIfPaymentGated } from '../_shared/dispatch.ts';
import { createLogger, generateRequestId, measure } from '../_shared/logger.ts';
// §3.3 fix: timing-safe string comparison for the service-key check.
import { timingSafeEqualString } from '../_shared/crypto.ts';

// Digital payment methods (cash is excluded — cash orders start as 'pending_cash'
// and don't need Paymob reconciliation).
const DIGITAL_METHODS = ['card', 'vodafone_cash', 'instapay', 'orange_cash', 'wallet'];

// Only reconcile orders older than this threshold (in minutes) to give the
// webhook time to arrive. Matches the auto_cancel_payment_timeout_minutes
// config default of 10 minutes; we read the actual config value at runtime.
const STALE_THRESHOLD_MINUTES_FALLBACK = 10;

// Hard cap on the number of orders processed per run to keep the EF within
// the Edge Runtime's CPU/wall-clock budget. If there are more stale orders,
// the next run picks them up.
// §4.6 fix: reduced from 50 to 20. Each order requires a sequential Paymob
// API call (~200–500ms). At BATCH_SIZE=50, the EF was close to Supabase's
// wall-clock limit (50 × 500ms = 25s). At 20, the worst case is ~10s — well
// under the limit. The cron runs every 5 minutes, so a backlog of 100+
// stale orders clears in ~25 minutes without any single run timing out.
// Increase back to 50 only after adding a batched Paymob transaction-status
// API to _shared/paymob.ts (gap-analysis §4.6 option 2).
const BATCH_SIZE = 20;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions(req);

  const requestId = generateRequestId();
  const log = createLogger({ requestId, functionName: 'reconcile-payments' });

  // Auth: require service role key (set by the Supabase cron scheduler).
  // This prevents arbitrary callers from triggering reconciliation runs
  // (which would hammer Paymob's API).
  // §3.3 fix: timing-safe comparison instead of `!==` to avoid leaking bytes
  // of the expected value through response time. Mirrors the pattern in
  // auto-generate-driver-settlements and the HMAC verification path.
  const authHeader = req.headers.get('Authorization');
  const token = authHeader?.replace('Bearer ', '') ?? '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!token || !timingSafeEqualString(token, serviceKey)) {
    log.warn('Unauthorized reconciliation attempt');
    return corsResponse(errorResponse('FORBIDDEN'), 403, undefined, req);
  }

  try {
    log.info('Reconciliation run started');

    const supabase = getSupabaseAdmin();

    // ── Read auto_cancel_payment_timeout_minutes from platform_config ──
    const { data: timeoutConfig } = await supabase
      .from('platform_config')
      .select('value')
      .eq('key', 'auto_cancel_payment_timeout_minutes')
      .single();
    const staleMinutes = timeoutConfig
      ? Number(timeoutConfig.value)
      : STALE_THRESHOLD_MINUTES_FALLBACK;
    const staleThreshold = new Date(Date.now() - staleMinutes * 60 * 1000).toISOString();

    // ── Fetch stale pending digital-payment orders ──
    // payment_status='pending' (digital) — NOT 'pending_cash' (cash on delivery).
    // merchant_id + status are needed by the assign-on-paid fallback (G5).
    const { data: staleOrders, error: fetchErr } = await supabase
      .from('orders')
      .select('id, order_number, paymob_order_id, payment_method, payment_status, status, merchant_id, total, created_at')
      .eq('payment_status', 'pending')
      .in('payment_method', DIGITAL_METHODS)
      .lt('created_at', staleThreshold)
      .order('created_at', { ascending: true })
      .limit(BATCH_SIZE);

    if (fetchErr) {
      log.error('Failed to fetch stale orders', { error: fetchErr.message });
      return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
    }

    if (!staleOrders || staleOrders.length === 0) {
      log.info('No stale pending digital orders found');
      return corsResponse(successResponse({ reconciled: 0, cancelled: 0, failed: 0 }), 200, undefined, req);
    }

    log.info('Found stale pending orders', { count: staleOrders.length });

    let reconciled = 0;
    let cancelled = 0;
    let failed = 0;

    for (const order of staleOrders) {
      // Skip orders without a Paymob order ID (shouldn't happen for digital
      // payments, but defensive — place-order EF sets paymob_order_id at
      // creation time).
      if (!order.paymob_order_id) {
        log.warn('Stale order missing paymob_order_id, cancelling', { orderId: order.id });
        await cancelOrderViaRpc(supabase, order.id, 'system', 'Payment initiation incomplete — no Paymob order ID');
        cancelled++;
        continue;
      }

      try {
        const status = await measure('paymob-tx-status', () =>
          getPaymobTransactionStatus(order.paymob_order_id!),
        log);

        if (status.pending) {
          // Paymob hasn't reached a terminal state. If the order is older
          // than 2× the stale threshold, cancel it (customer abandoned the
          // iframe). Otherwise leave it for the next run.
          const doubleThreshold = new Date(Date.now() - staleMinutes * 2 * 60 * 1000).toISOString();
          if (order.created_at < doubleThreshold) {
            log.info('Cancelling abandoned pending order', { orderId: order.id, orderNumber: order.order_number });
            await cancelOrderViaRpc(supabase, order.id, 'system', 'Payment timeout — customer did not complete payment');
            cancelled++;
          } else {
            log.debug('Order still pending at Paymob, will retry next run', { orderId: order.id });
          }
          continue;
        }

        if (status.success) {
          // Payment captured — mark as paid.
          const { error: updateErr } = await supabase
            .from('orders')
            .update({ payment_status: 'paid', paid_at: new Date().toISOString() }) // G8: capture timestamp
            .eq('id', order.id)
            .eq('payment_status', 'pending'); // optimistic concurrency
          if (updateErr) {
            log.error('Failed to mark order as paid', { orderId: order.id, error: updateErr.message });
            failed++;
          } else {
            reconciled++;
            log.info('Order marked as paid', { orderId: order.id, orderNumber: order.order_number });

            // G5 safety net: the webhook may never have arrived. With dispatch
            // gating ON, this is where a paid-but-driver-less order finally
            // gets its driver (helper no-ops when gating is OFF or the order
            // was cancelled in the meantime; driver-actions is idempotent, so
            // double-assign across webhook + reconcile is harmless).
            await assignDriverIfPaymentGated(log, supabase, {
              orderId: order.id,
              merchantId: order.merchant_id,
              orderStatus: order.status,
            });
          }
        } else {
          // Payment failed/voided — cancel the order.
          log.info('Cancelling failed-payment order', { orderId: order.id, orderNumber: order.order_number });
          await cancelOrderViaRpc(supabase, order.id, 'system', 'Payment failed at Paymob');
          cancelled++;
        }
      } catch (err) {
        log.error('Paymob status query failed for order', {
          orderId: order.id,
          error: err instanceof Error ? err.message : String(err),
        });
        failed++;
        // Continue to next order — one bad Paymob query shouldn't abort the run.
      }
    }

    log.info('Reconciliation run complete', { reconciled, cancelled, failed, total: staleOrders.length });

    // === A2-G5: Process pending Paymob refunds ===
    // Admin cancels (via /api/orders/[id]/cancel) and customer cancels where
    // the Paymob refund API call failed both leave orders with
    // refund_status='pending_refund' or 'refund_failed'. The customer
    // cancel-order EF attempts the refund inline, but the admin route (Node)
    // cannot call the Deno paymob module. This cron picks up those orders and
    // retries the Paymob refund.
    const { data: refundPendingOrders, error: refundFetchErr } = await supabase
      .from('orders')
      .select('id, order_number, paymob_order_id, payment_method, payment_status, refund_amount')
      .in('refund_status', ['pending_refund', 'refund_failed'])
      .not('paymob_order_id', 'is', null)
      .gt('refund_amount', 0)
      .order('created_at', { ascending: true })
      .limit(BATCH_SIZE);

    if (refundFetchErr) {
      log.error('Failed to fetch pending-refund orders', { error: refundFetchErr.message });
    } else if (refundPendingOrders && refundPendingOrders.length > 0) {
      log.info('Found pending-refund orders', { count: refundPendingOrders.length });
      for (const order of refundPendingOrders) {
        try {
          const refundAmount = Number(order.refund_amount ?? 0);
          const refundTxId = await refundPaymobPayment(
            order.paymob_order_id!,
            Math.round(refundAmount * 100),
          );
          log.info('Paymob refund succeeded', { orderId: order.id, refundTxId, refundAmount });

          await supabase
            .from('orders')
            .update({
              refund_id: refundTxId,
              refunded_at: new Date().toISOString(),
              refund_status: 'refunded',
            })
            .eq('id', order.id);
          reconciled++;
        } catch (refundErr) {
          const errMsg = refundErr instanceof Error ? refundErr.message : String(refundErr);
          log.error('Paymob refund retry failed', { orderId: order.id, error: errMsg });
          // Leave refund_status as-is (pending_refund or refund_failed) for next run.
          failed++;
        }
      }
    }

    return corsResponse(successResponse({
      reconciled,
      cancelled,
      failed,
      total: staleOrders.length,
    }), 200, undefined, req);
  } catch (err) {
    log.error('Unhandled error', { error: err instanceof Error ? err.message : String(err) });
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }
});

// Helper: invoke cancel_order RPC with initiator='system'.
// Mirrors the call shape from cancel-order/index.ts but with initiator_role='system'.
async function cancelOrderViaRpc(
  supabase: ReturnType<typeof getSupabaseAdmin>,
  orderId: string,
  initiatorRole: 'system',
  reason: string,
): Promise<void> {
  // The cancel_order RPC requires a p_initiator_id UUID. For system-initiated
  // cancels, we pass NULL — the RPC's cancellation_rules table has rows for
  // initiator='system' (migration 023), and the RPC doesn't enforce a
  // non-null initiator_id (it's used for cancelled_by and audit logs, both
  // of which accept NULL for system events).
  const { error } = await supabase.rpc('cancel_order', {
    p_order_id: orderId,
    p_initiator_id: null as unknown as string,
    p_initiator_role: initiatorRole,
    p_reason: reason,
  });
  if (error) {
    // Log but don't throw — the reconciliation run should continue with other orders.
    // The order will be retried on the next run.
    console.error(`[reconcile-payments] cancel_order RPC failed for ${orderId}:`, error.message);
  }
}
