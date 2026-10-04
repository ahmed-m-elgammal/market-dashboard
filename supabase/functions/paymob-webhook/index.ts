// Edge Function: paymob-webhook
// P3D-06 through P3D-09: Receives Paymob payment status updates
// No JWT auth — secured via HMAC signature verification
// Returns HTTP 200 immediately, processes async
//
// Security model:
//   - HMAC verification is ALWAYS enforced (fails closed)
//   - Payment amount is verified against order total
//   - Idempotent: paid transitions are an atomic test-and-set UPDATE guarded on
//     payment_status, so concurrent/duplicate success callbacks (Paymob
//     retries, double delivery) produce exactly ONE paid transition and ONE
//     push notification (G7)
//   - Payment-gated dispatch: on the paid transition, if the
//     payment_dispatch_gating flag is ON and the order has no driver yet, the
//     webhook fires the driver assignment (G5 — place-order skipped it while
//     the order was unpaid). reconcile-payments is the safety net.
//   - Paid-after-cancel: a success callback for an order that was already
//     cancelled queues a refund (refund_status='pending_refund') instead of
//     leaving captured money on a dead order (EC-9)
//   - Rate-limited by client IP (rightmost from x-forwarded-for)
//   - Request body size limited to 10KB
//   - Always returns 200 to prevent Paymob retries

import { corsResponse } from '../_shared/cors.ts';
import { getSupabaseAdmin, fetchWithTimeout } from '../_shared/supabase.ts';
import { checkRateLimit, RATE_LIMITS } from '../_shared/rate-limit.ts';
import { verifyPaymobHmac } from '../_shared/paymob.ts';
import { assignDriverIfPaymentGated } from '../_shared/dispatch.ts';
import { createLogger, generateRequestId } from '../_shared/logger.ts';

// Maximum webhook payload size (10KB — Paymob callbacks are well under this)
const MAX_BODY_SIZE = 10 * 1024;

/**
 * Extract the most trustworthy IP from x-forwarded-for.
 * The rightmost IP is set by the closest trusted proxy and is hardest to spoof.
 * Falls back to a connection identifier if no IP is available.
 */
function extractClientIp(req: Request): string {
  const xff = req.headers.get('x-forwarded-for');
  if (xff) {
    // "client, proxy1, proxy2" — rightmost is set by our infrastructure
    const ips = xff.split(',').map((s) => s.trim()).filter(Boolean);
    if (ips.length > 0) {
      return ips[ips.length - 1];
    }
  }
  // Fallback: use a generic identifier so rate limiting still works
  return 'unknown';
}

/**
 * Build a standard 200 response for Paymob.
 * We ALWAYS return 200 so Paymob doesn't retry — even for rejected webhooks.
 */
function webhookAck(payload?: Record<string, unknown>): Response {
  return new Response(JSON.stringify({ received: true, ...payload }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  const requestId = generateRequestId();
  const log = createLogger({ requestId, functionName: 'paymob-webhook' });

  if (req.method === 'OPTIONS') return corsResponse('ok', 204);

  try {
    // ── Rate limit by IP ──────────────────────────────────────────────
    const clientIp = extractClientIp(req);
    const rl = checkRateLimit(`webhook:${clientIp}`, RATE_LIMITS.PAYMOB_WEBHOOK);
    if (!rl.allowed) {
      log.warn('Rate limit exceeded', { clientIp, retryAfterMs: rl.retryAfterMs });
      return webhookAck();
    }

    // ── Request size validation ───────────────────────────────────────
    const contentLength = req.headers.get('content-length');
    if (contentLength && parseInt(contentLength, 10) > MAX_BODY_SIZE) {
      log.warn('Payload too large', { contentLength, max: MAX_BODY_SIZE });
      return webhookAck();
    }

    // ── Parse form-urlencoded body from Paymob ────────────────────────
    const text = await req.text();
    if (text.length > MAX_BODY_SIZE) {
      log.warn('Payload body exceeds size limit', { bodyLength: text.length, max: MAX_BODY_SIZE });
      return webhookAck();
    }

    const params = new URLSearchParams(text);

    // ── HMAC VERIFICATION (always enforced, fails closed) ─────────────
    const hmacResult = await verifyPaymobHmac(params);
    if (!hmacResult.valid) {
      log.error('HMAC verification failed — rejecting webhook', {
        error: hmacResult.error,
        clientIp,
        paymobTxnId: params.get('id'),
        paymobOrderId: params.get('order'),
      });
      // Return 200 to prevent Paymob retries, but do NOT process the payment
      return webhookAck();
    }

    log.info('HMAC verification passed');

    // ── EXTRACT PAYMENT DATA ──────────────────────────────────────────
    const success = params.get('success') === 'true';
    const pending = params.get('pending') === 'true';
    const paymobOrderId = params.get('order');
    const paymobTransactionId = params.get('id');
    const amountCents = params.get('amount_cents');
    // §5.1 fix: extract the void/refund flags Paymob sends when an admin
    // voids a payment or issues a refund via the Paymob dashboard (not via
    // our refundPaymobPayment API). Previously these were silently dropped,
    // leaving our DB out of sync with Paymob's view of the payment.
    const isVoided = params.get('is_voided') === 'true';
    const isRefunded = params.get('is_refunded') === 'true';

    log.info('Webhook payload parsed', {
      success,
      pending,
      paymobOrderId,
      paymobTransactionId,
      amountCents,
      isVoided,
      isRefunded,
    });

    // ── PROCESS THE PAYMENT UPDATE ────────────────────────────────────
    const processPromise = processPaymentUpdate(
      log,
      success,
      pending,
      isVoided,
      isRefunded,
      paymobOrderId,
      paymobTransactionId,
      amountCents,
    );

    try {
      // Try to use EdgeRuntime.waitUntil for true async processing
      (EdgeRuntime as { waitUntil?: (p: Promise<void>) => void }).waitUntil?.(processPromise);
    } catch {
      // EdgeRuntime.waitUntil not available — await inline instead
      // This is slightly slower (delays the 200 response) but guarantees processing
      await processPromise;
    }

    return webhookAck();
  } catch (err) {
    log.error('paymob-webhook unhandled error', {
      error: err instanceof Error ? err.message : String(err),
    });
    return webhookAck();
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Payment processing logic
// ─────────────────────────────────────────────────────────────────────────────

async function processPaymentUpdate(
  log: ReturnType<typeof createLogger>,
  success: boolean,
  pending: boolean,
  isVoided: boolean,
  isRefunded: boolean,
  paymobOrderId: string | null,
  paymobTransactionId: string | null,
  amountCents: string | null,
) {
  try {
    const supabase = getSupabaseAdmin();

    // Find our order by Paymob order ID (backed by the unique partial index
    // idx_orders_paymob_order_id, migration 094 — this lookup was a seq scan).
    const { data: order, error: orderError } = await supabase
      .from('orders')
      .select('id, customer_id, order_number, total, payment_status, status, merchant_id')
      .eq('paymob_order_id', paymobOrderId)
      .maybeSingle();

    if (orderError || !order) {
      log.error('Order not found for Paymob order ID', {
        paymobOrderId,
        error: orderError?.message,
      });
      return;
    }

    // ── §5.1 fix: HANDLE VOID / REFUND FLAGS BEFORE IDEMPOTENCY ───────
    // These flags are sent by Paymob when an admin voids a payment or
    // issues a refund via the Paymob dashboard (not via our
    // refundPaymobPayment API). They MUST be processed before the
    // `payment_status === 'paid'` idempotency check below — a paid order
    // can still receive a refund webhook, and a voided payment may arrive
    // after the success webhook (Paymob fires both).
    //
    // is_voided: payment was voided in the Paymob dashboard (reverses a
    //   capture before settlement). Reverse the paid status → 'failed'.
    //   The order is already cancelled-or-not in our DB; this just syncs
    //   the payment status so finance reports don't show ghost revenue.
    //
    // is_refunded: refund was issued via the Paymob dashboard (not via our
    //   cancel-order EF). Sync refund_status='refunded' + stamp refunded_at
    //   without re-calling Paymob's refund API. The refund_amount field is
    //   left untouched — Paymob's webhook doesn't include the refund amount,
    //   so we can't recompute it here. Finance reconciles via Paymob's
    //   transaction list.
    if (isVoided && order.payment_status === 'paid') {
      log.info('Payment voided in Paymob dashboard — reversing paid status', {
        orderId: order.id,
        orderNumber: order.order_number,
        paymobTransactionId,
      });
      await supabase
        .from('orders')
        .update({
          payment_status: 'failed',
          paymob_transaction_id: paymobTransactionId,
        })
        .eq('id', order.id);
      return;
    }

    if (isRefunded && order.payment_status === 'paid') {
      log.info('Refund issued in Paymob dashboard — syncing refund_status', {
        orderId: order.id,
        orderNumber: order.order_number,
        paymobTransactionId,
      });
      await supabase
        .from('orders')
        .update({
          refund_status: 'refunded',
          refunded_at: new Date().toISOString(),
          paymob_transaction_id: paymobTransactionId,
        })
        .eq('id', order.id);
      return;
    }

    // ── IDEMPOTENCY: skip already-processed orders ────────────────────
    // Fast-path for true duplicates (the heavy race window is closed by the
    // test-and-set UPDATEs below — two concurrent success callbacks both read
    // 'pending' here, but Postgres serializes the guarded UPDATEs and only
    // one of them matches a row).
    if (order.payment_status === 'paid') {
      log.info('Order already paid — skipping duplicate webhook', {
        orderId: order.id,
        orderNumber: order.order_number,
        paymobTransactionId,
      });
      return;
    }

    // ── AMOUNT VERIFICATION ───────────────────────────────────────────
    // Per security spec doc 21: verify amount_cents matches order total
    if (success && !pending && amountCents) {
      const expectedCents = Math.round(order.total * 100);
      const receivedCents = parseInt(amountCents, 10);

      if (!isNaN(receivedCents) && receivedCents !== expectedCents) {
        log.error('Amount mismatch — possible tampering or misconfiguration', {
          orderId: order.id,
          orderNumber: order.order_number,
          orderTotal: order.total,
          expectedCents,
          receivedCents,
          paymobTransactionId,
        });
        // Do NOT mark as paid — amount doesn't match
        // Optionally mark as failed or leave as-is
        await supabase
          .from('orders')
          .update({
            payment_status: 'failed',
            paymob_transaction_id: paymobTransactionId,
          })
          .eq('id', order.id);
        return;
      }

      log.info('Amount verification passed', {
        expectedCents,
        receivedCents: isNaN(receivedCents) ? 'N/A' : receivedCents,
      });
    }

    // ── PROCESS SUCCESS / FAILURE ─────────────────────────────────────
    if (success && !pending) {
      // ── EC-9: success for an already-cancelled order ──────────────────
      // The customer (or the stale-order cron) cancelled while payment was
      // in flight, and Paymob captured the money anyway. cancel_order (088)
      // leaves such orders with a PHANTOM refunded/partial_refund state
      // (computed from cancellation_rules even though nothing was ever
      // captured). Re-open the money trail: mark the capture as paid and
      // queue a real refund — reconcile-payments refunds it via Paymob.
      // Guarded on the pre-capture payment states so a duplicate callback
      // can never re-open a refund reconcile already completed.
      if (order.status === 'cancelled') {
        const { data: queued, error: queueErr } = await supabase
          .from('orders')
          .update({
            payment_status: 'paid',
            refund_status: 'pending_refund',
            refund_amount: order.total,
            paid_at: new Date().toISOString(),
            paymob_transaction_id: paymobTransactionId,
          })
          .eq('id', order.id)
          .eq('status', 'cancelled')
          .in('payment_status', ['pending', 'refunded', 'partial_refund'])
          .select('id');

        if (queueErr) {
          log.error('Failed to queue refund for cancelled-order capture', {
            orderId: order.id,
            error: queueErr.message,
          });
          return;
        }
        if (queued && queued.length > 0) {
          log.warn('Payment captured for cancelled order — refund queued for reconcile cron', {
            orderId: order.id,
            orderNumber: order.order_number,
            refundAmount: order.total,
            paymobTransactionId,
          });
          await sendNotification(log, order.customer_id, order.id, order.total, order.order_number, 'refund_pending');
        }
        return;
      }

      // Payment successful — atomic test-and-set (G7). 'failed' is included
      // so a failed attempt followed by a successful retry in the same Paymob
      // iframe still lands (behavior preserved from the unconditional update).
      const { data: updated, error: updateError } = await supabase
        .from('orders')
        .update({
          payment_status: 'paid',
          paymob_transaction_id: paymobTransactionId,
          paid_at: new Date().toISOString(), // G8
        })
        .eq('id', order.id)
        .in('payment_status', ['pending', 'failed'])
        .select('id');

      if (updateError) {
        log.error('Failed to update order to paid', {
          orderId: order.id,
          error: updateError.message,
        });
        return;
      }

      if (!updated || updated.length === 0) {
        // Lost the race (a concurrent webhook already transitioned the order).
        // Nothing to transition, nothing to notify — the dedup short-circuit.
        log.info('Paid transition lost the race — treating webhook as duplicate', {
          orderId: order.id,
          orderNumber: order.order_number,
          paymobTransactionId,
        });
        return;
      }

      log.info('Order marked as paid', {
        orderId: order.id,
        orderNumber: order.order_number,
        paymobTransactionId,
      });

      // G5 takeover: with dispatch gating ON and the order still driver-less,
      // assign now (helper no-ops when the flag is OFF or the order is
      // cancelled; driver-actions itself is idempotent).
      await assignDriverIfPaymentGated(log, supabase, {
        orderId: order.id,
        merchantId: order.merchant_id,
        orderStatus: order.status,
      });

      // Notify customer — ONLY on the winning transition (kills duplicate pushes)
      await sendNotification(log, order.customer_id, order.id, order.total, order.order_number, 'success');
    } else if (!success && !pending) {
      // Payment failed — same test-and-set discipline (G7): the failure
      // callback may also arrive twice, and only the first should push.
      const { data: updated, error: updateError } = await supabase
        .from('orders')
        .update({
          payment_status: 'failed',
          paymob_transaction_id: paymobTransactionId,
        })
        .eq('id', order.id)
        .eq('payment_status', 'pending')
        .select('id');

      if (updateError) {
        log.error('Failed to update order to failed', {
          orderId: order.id,
          error: updateError.message,
        });
        return;
      }

      if (!updated || updated.length === 0) {
        log.info('Failure transition lost the race — treating webhook as duplicate', {
          orderId: order.id,
          orderNumber: order.order_number,
          paymobTransactionId,
        });
        return;
      }

      log.info('Order marked as payment failed', {
        orderId: order.id,
        orderNumber: order.order_number,
        paymobTransactionId,
      });

      // Notify customer (only on the winning transition)
      await sendNotification(log, order.customer_id, order.id, order.total, order.order_number, 'failure');
    }
    // If pending, do nothing — wait for final callback
    else if (pending) {
      log.info('Payment still pending — awaiting final callback', {
        orderId: order.id,
        orderNumber: order.order_number,
      });
    }
  } catch (err) {
    log.error('Webhook processing error', {
      error: err instanceof Error ? err.message : String(err),
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notification helper
// ─────────────────────────────────────────────────────────────────────────────

async function sendNotification(
  log: ReturnType<typeof createLogger>,
  customerId: string,
  orderId: string,
  total: number,
  orderNumber: string,
  type: 'success' | 'failure' | 'refund_pending',
) {
  try {
    const functionUrl = `${Deno.env.get('SUPABASE_URL')}/functions/v1/send-notification`;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

    const payload = type === 'success'
      ? {
          user_id: customerId,
          title_en: 'Payment Successful',
          title_ar: 'تم الدفع بنجاح',
          body_en: `Payment of ${total} EGP received`,
          body_ar: `تم استلام دفع بقيمة ${total} ج.م`,
          type: 'order_status',
          reference_id: orderId,
        }
      : type === 'refund_pending'
        ? {
            // EC-9: the customer paid for an order that was already cancelled.
            // Money was captured; reconcile-payments will refund it via Paymob.
            user_id: customerId,
            title_en: 'Payment Received — Refund Scheduled',
            title_ar: 'تم استلام الدفع — سيتم رد المبلغ',
            body_en: `We received your ${total} EGP payment for cancelled order #${orderNumber}. A full refund will be processed shortly.`,
            body_ar: `استلمنا دفعتك بقيمة ${total} ج.م للطلب الملغي #${orderNumber}. سيتم رد المبلغ كاملاً قريباً.`,
            type: 'order_status',
            reference_id: orderId,
          }
        : {
            user_id: customerId,
            title_en: 'Payment Failed',
            title_ar: 'فشل الدفع',
            body_en: `Payment for order #${orderNumber} failed`,
            body_ar: `فشل الدفع للطلب #${orderNumber}`,
            type: 'order_status',
            reference_id: orderId,
          };

    const res = await fetchWithTimeout(functionUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${serviceKey}`,
      },
      body: JSON.stringify(payload),
    });

    if (!res.ok) {
      log.warn('Notification delivery failed', {
        type,
        status: res.status,
        orderId,
      });
    } else {
      log.debug('Notification sent', { type, orderId });
    }
  } catch (err) {
    log.warn('Notification delivery error', {
      type,
      error: err instanceof Error ? err.message : String(err),
    });
  }
}
