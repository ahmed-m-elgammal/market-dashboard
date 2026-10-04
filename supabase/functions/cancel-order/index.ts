// Edge Function: cancel-order
// Sprint 0 security fix (S05): customer-facing order cancellation.
//
// Wraps the service-role-only `cancel_order` RPC (migration 033) so the mobile
// client can cancel its own orders without needing direct EXECUTE on the RPC.
// Mirrors the place-order Edge Function pattern: authenticate the customer,
// verify ownership of the order, then invoke the RPC with the service-role
// client.
//
// Rate limited (10/min/customer).

import { corsResponse, handleOptions } from '../_shared/cors.ts';
import { errorResponse, errorStatus, successResponse } from '../_shared/errors.ts';
import { checkRateLimit, RATE_LIMITS } from '../_shared/rate-limit.ts';
import { getSupabaseAdmin } from '../_shared/supabase.ts';
import { requireRole } from '../_shared/auth.ts';
import { validateUUID, validateString, validateRequestSize, formatValidationErrors } from '../_shared/validation.ts';
import { createLogger, generateRequestId, measure } from '../_shared/logger.ts';
import { refundPaymobPayment } from '../_shared/paymob.ts';

interface CancelOrderRequest {
  order_id: string;
  reason?: string;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions(req);

  const requestId = generateRequestId();
  const log = createLogger({ requestId, functionName: 'cancel-order' });

  try {
    log.info('Request received', { method: req.method });

    // === REQUEST SIZE VALIDATION ===
    const sizeValidation = validateRequestSize(req);
    if (!sizeValidation.valid) {
      log.warn('Request too large', { errors: sizeValidation.errors });
      return corsResponse(
        errorResponse('VALIDATION_ERROR', { message_en: formatValidationErrors(sizeValidation.errors) }),
        413,
        undefined,
        req,
      );
    }

    // Auth: require customer
    const authResult = await measure('auth', () =>
      requireRole(req.headers.get('Authorization'), 'customer'), log,
    );
    if (authResult.error) {
      log.warn('Auth failed', { code: authResult.error.error.code });
      return corsResponse(authResult.error, authResult.status || 403, undefined, req);
    }
    const customerId = authResult.data!.userId;
    log.info('Customer authenticated', { customerId });

    // Rate limit
    const rl = checkRateLimit(`cancel-order:${customerId}`, RATE_LIMITS.CANCEL_ORDER);
    if (!rl.allowed) {
      log.warn('Rate limited', { customerId, retryAfterMs: rl.retryAfterMs });
      return corsResponse(
        errorResponse('RATE_LIMITED'),
        429,
        { 'Retry-After': String(Math.ceil(rl.retryAfterMs / 1000)) },
        req,
      );
    }

    // Parse and validate request body
    const rawBody = await req.text();
    let body: CancelOrderRequest;
    try {
      body = JSON.parse(rawBody);
    } catch {
      log.warn('Invalid JSON body');
      return corsResponse(
        errorResponse('VALIDATION_ERROR', { message_en: 'Invalid JSON in request body' }),
        400,
        undefined,
        req,
      );
    }

    // === INPUT VALIDATION ===
    const errors: ReturnType<typeof validateUUID>['errors'] = [];

    const orderIdResult = validateUUID(body.order_id, 'order_id');
    if (!orderIdResult.valid) errors.push(...orderIdResult.errors);

    if (body.reason !== undefined && body.reason !== null) {
      const reasonResult = validateString(body.reason, 'reason', { required: false, max: 500 });
      if (!reasonResult.valid) errors.push(...reasonResult.errors);
    }

    if (errors.length > 0) {
      log.warn('Validation failed', { errors });
      return corsResponse(
        errorResponse('VALIDATION_ERROR', { message_en: formatValidationErrors(errors) }),
        400,
        undefined,
        req,
      );
    }

    const supabase = getSupabaseAdmin();

    // === OWNERSHIP CHECK ===
    // Verify the order belongs to the authenticated customer BEFORE invoking
    // the RPC. The RPC is service-role and trusts p_initiator_id blindly.
    // A2-G5: also fetch payment fields so we can issue a Paymob refund after
    // the RPC succeeds for paid digital orders.
    const { data: order, error: orderError } = await supabase
      .from('orders')
      .select('id, order_number, customer_id, driver_id, status, payment_method, payment_status, paymob_order_id, total')
      .eq('id', body.order_id)
      .eq('customer_id', customerId)
      .maybeSingle();

    if (orderError || !order) {
      log.warn('Order not found or not owned by caller', { orderId: body.order_id, customerId });
      return corsResponse(errorResponse('ORDER_NOT_FOUND'), errorStatus('ORDER_NOT_FOUND'), undefined, req);
    }

    // === INVOKE cancel_order RPC (service role) ===
    const { data: rpcResult, error: rpcError } = await supabase.rpc('cancel_order', {
      p_order_id: body.order_id,
      p_initiator_id: customerId,
      p_initiator_role: 'customer',
      p_reason: body.reason ?? null,
    });

    if (rpcError) {
      log.error('cancel_order RPC failed', {
        orderId: body.order_id,
        code: rpcError.code,
        message: rpcError.message,
      });
      // A2-G6: Map known Postgres exceptions to user-facing error codes.
      // Mirrors the error mapping in apps/admin/src/app/api/orders/[id]/cancel/route.ts.
      const msg = (rpcError.message || '').toLowerCase();
      if (msg.includes('already cancelled')) {
        return corsResponse(
          errorResponse('ORDER_INVALID_STATUS', { message_en: 'Order is already cancelled' }),
          errorStatus('ORDER_INVALID_STATUS'),
          undefined,
          req,
        );
      }
      if (msg.includes('delivered orders cannot be cancelled')) {
        return corsResponse(
          errorResponse('ORDER_INVALID_STATUS', { message_en: 'Cannot cancel a delivered order' }),
          errorStatus('ORDER_INVALID_STATUS'),
          undefined,
          req,
        );
      }
      if (msg.includes('cannot be cancelled') || msg.includes('not allowed')) {
        return corsResponse(
          errorResponse('ORDER_INVALID_STATUS', { message_en: 'This order can no longer be cancelled' }),
          errorStatus('ORDER_INVALID_STATUS'),
          undefined,
          req,
        );
      }
      if (msg.includes('reason is required')) {
        return corsResponse(
          errorResponse('VALIDATION_ERROR', { message_en: 'A cancellation reason is required for this order' }),
          400,
          undefined,
          req,
        );
      }
      if (msg.includes('order not found')) {
        return corsResponse(
          errorResponse('ORDER_NOT_FOUND'),
          errorStatus('ORDER_NOT_FOUND'),
          undefined,
          req,
        );
      }
      if (msg.includes('no cancellation rule found')) {
        return corsResponse(
          errorResponse('ORDER_INVALID_STATUS', { message_en: 'No cancellation rule configured for this order status' }),
          errorStatus('ORDER_INVALID_STATUS'),
          undefined,
          req,
        );
      }
      if (msg.includes('concurrently')) {
        // Order status changed between the RPC's SELECT FOR UPDATE and its
        // UPDATE — a concurrent cancel/transition won. Tell the customer to
        // refresh and retry.
        return corsResponse(
          errorResponse('ORDER_INVALID_STATUS', { message_en: 'Order status changed concurrently. Please refresh and try again.' }),
          409,
          undefined,
          req,
        );
      }
      return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
    }

    // RPC returns a TABLE with one row: (order_id, status, refund_amount,
    // cancellation_fee, driver_compensation, refund_percentage, merchant_payout,
    // payout_recomputed_at). The last two columns were added in migration 081
    // (merchant_payout) and 082 (payout_recomputed_at). Older EF deploys that
    // don't read them still work — the columns are simply ignored.
    const row = Array.isArray(rpcResult) ? rpcResult[0] : rpcResult;
    const adjustedMerchantPayout = row?.merchant_payout != null ? Number(row.merchant_payout) : null;
    const payoutRecomputedAt = row?.payout_recomputed_at ?? null;
    log.info('Order cancelled', {
      orderId: body.order_id,
      customerId,
      refundAmount: row?.refund_amount,
      cancellationFee: row?.cancellation_fee,
      adjustedMerchantPayout,
      payoutRecomputedAt,
    });

    // === A2-G5: PAYMOB REFUND for paid digital orders ===
    // If the order was paid via Paymob (payment_status='paid', payment_method
    // is digital, paymob_order_id is set) and the cancellation_rules computed
    // a refund_amount > 0, call Paymob's refund API to actually return the
    // money to the customer's card. The RPC already set refund_amount and
    // refund_status in the DB, but without this call the customer sees
    // "Refund: 125 EGP" in the app while their bank statement shows nothing.
    //
    // Failure handling: if the Paymob refund fails, we do NOT roll back the
    // cancellation (the order is already cancelled in the DB). Instead we
    // set refund_status='refund_failed' so the reconcile-payments cron or an
    // admin can retry. The customer-facing response still reports the
    // computed refund_amount — the money will be returned when the retry
    // succeeds.
    const refundAmount = Number(row?.refund_amount ?? 0);
    const DIGITAL_METHODS = ['card', 'vodafone_cash', 'instapay', 'orange_cash', 'wallet'];
    const isPaidDigital =
      order.payment_status === 'paid' &&
      DIGITAL_METHODS.includes(order.payment_method) &&
      !!order.paymob_order_id &&
      refundAmount > 0;

    if (isPaidDigital) {
      try {
        const refundTxId = await refundPaymobPayment(
          order.paymob_order_id,
          Math.round(refundAmount * 100),
        );
        log.info('Paymob refund succeeded', { orderId: body.order_id, refundTxId, refundAmount });

        // Persist the Paymob refund transaction ID and mark refund as complete.
        await supabase
          .from('orders')
          .update({
            refund_id: refundTxId,
            refunded_at: new Date().toISOString(),
            refund_status: 'refunded',
          })
          .eq('id', body.order_id);
      } catch (refundErr) {
        const errMsg = refundErr instanceof Error ? refundErr.message : String(refundErr);
        log.error('Paymob refund failed', { orderId: body.order_id, error: errMsg, refundAmount });

        // Mark refund as failed so it can be retried. The cancellation itself
        // is not rolled back — the order is cancelled, but the refund needs
        // manual or cron-driven retry.
        await supabase
          .from('orders')
          .update({ refund_status: 'refund_failed' })
          .eq('id', body.order_id);
      }
    }

    // Trigger push notifications for cancellation (push_only: true since RPC already inserted DB records)
    try {
      log.info('Triggering push notifications for cancellation', { orderId: body.order_id });
      
      // Notify customer
      await supabase.functions.invoke('send-notification', {
        body: {
          user_id: order.customer_id,
          title_en: 'Order Cancelled',
          title_ar: 'تم إلغاء طلبك',
          body_en: `Your order ${order.order_number} has been cancelled. Refund: ${refundAmount} EGP`,
          body_ar: `تم إلغاء طلبك رقم ${order.order_number}. المبلغ المسترد: ${refundAmount} ج.م`,
          type: 'order_cancelled',
          reference_id: body.order_id,
          data: { order_id: body.order_id, refund_amount: String(refundAmount) },
          push_only: true,
        },
      });

      // Notify driver if assigned
      if (order.driver_id) {
        const driverCompensation = Number(row?.driver_compensation ?? 0);
        await supabase.functions.invoke('send-notification', {
          body: {
            user_id: order.driver_id,
            title_en: 'Order Cancelled',
            title_ar: 'تم إلغاء الطلب',
            body_en: `Order ${order.order_number} has been cancelled. Compensation: ${driverCompensation} EGP`,
            body_ar: `تم إلغاء الطلب رقم ${order.order_number}. تعويض: ${driverCompensation} ج.م`,
            type: 'order_cancelled',
            reference_id: body.order_id,
            data: { order_id: body.order_id, compensation: String(driverCompensation) },
            push_only: true,
          },
        });
      }
    } catch (pushErr) {
      log.error('Failed to dispatch cancellation push notifications', {
        error: pushErr instanceof Error ? pushErr.message : String(pushErr),
      });
      // Do not fail the cancel-order response if push triggers fail
    }

    return corsResponse(successResponse({
      order_id: body.order_id,
      status: row?.status ?? 'cancelled',
      refund_amount: refundAmount,
      cancellation_fee: row?.cancellation_fee ?? 0,
      driver_compensation: row?.driver_compensation ?? 0,
      refund_percentage: row?.refund_percentage ?? 0,
      // S2: surface the recomputed merchant_payout + timestamp so the mobile
      // client + reconcile-payments cron can confirm the leak fix is applied.
      // merchant_payout is null when the RPC is from a pre-081 deploy.
      merchant_payout: adjustedMerchantPayout,
      payout_recomputed_at: payoutRecomputedAt,
    }), 200, undefined, req);
  } catch (err) {
    log.error('Unhandled error', { error: err instanceof Error ? err.message : String(err) });
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }
});
