// Edge Function: place-order
// P3C + P3D: Creates order, validates merchant/items/promo, handles cash & digital payment
// Rate limited (5/min/customer), idempotency key support, parallel validation
//
// Production hardening:
//   - Cached Paymob auth token via shared module (RED-18, saves ~200ms/call)
//   - Batched platform_config queries (1 query instead of 2)
//   - Input validation via shared validation module
//   - Request size validation (Content-Length check)
//   - Structured JSON logging with request ID tracking
//   - Customer email/phone passed to Paymob billing data
//   - Atomic order insertion via Postgres RPC with fallback

import { corsResponse, handleOptions } from '../_shared/cors.ts';
import { errorResponse, errorStatus, successResponse } from '../_shared/errors.ts';
import { checkRateLimit, RATE_LIMITS } from '../_shared/rate-limit.ts';
import { getSupabaseAdmin, fetchWithTimeout } from '../_shared/supabase.ts';
import { haversineDistanceKm, estimateDeliveryMinutes } from '../_shared/geo.ts';
import { requireRole } from '../_shared/auth.ts';
import { initiatePaymobPayment } from '../_shared/paymob.ts';
import { validatePlaceOrderRequest, validateRequestSize, formatValidationErrors } from '../_shared/validation.ts';
import { createLogger, generateRequestId, measure } from '../_shared/logger.ts';
import { validatePromoCode, computePromoDiscount } from '../_shared/promo.ts';

interface PlaceOrderRequest {
  merchant_id: string;
  items: {
    item_id: string;
    quantity: number;
    selected_options?: { option_id: string; choice_ids: string[] }[];
    special_instructions?: string;
  }[];
  delivery_address: {
    lat: number;
    lng: number;
    address: string;
    building_number?: string;
    floor_number?: string;
    apartment_number?: string;
    landmark?: string;
    city?: string;
    area?: string;
  };
  payment_method: 'cash' | 'card' | 'vodafone_cash' | 'instapay' | 'orange_cash' | 'wallet';
  promo_code?: string;
  notes?: string;
  // ISO-8601 datetime string. NULL/omitted = ASAP. Sprint 0 fix (D04).
  scheduled_time?: string;
  idempotency_key?: string;
}

// G1 guard: 'wallet' is NOT in this list — it has no implementation (no funding
// path, no gateway branch in _shared/paymob.ts). It is rejected explicitly
// below instead of being treated as cash (customer would pay nothing on
// delivery) or as digital (an unpayable order that only the stale-cron cleans).
const DIGITAL_METHODS = ['card', 'vodafone_cash', 'instapay', 'orange_cash'];

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions(req);

  const requestId = generateRequestId();
  const log = createLogger({ requestId, functionName: 'place-order' });

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
      requireRole(req.headers.get('Authorization'), 'customer'), log
    );
    if (authResult.error) {
      log.warn('Auth failed', { code: authResult.error.error.code });
      return corsResponse(authResult.error, authResult.status || 403, undefined, req);
    }
    const customerId = authResult.data!.userId;
    const customerEmail = authResult.data!.email;
    const customerPhone = authResult.data!.profile?.phone || undefined;

    log.info('Customer authenticated', { customerId });

    // P2-7: extract client IP from headers for promo fraud detection.
    // x-forwarded-for chain: first IP is the original client.
    const customerIp =
      req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ||
      req.headers.get('x-real-ip') ||
      null;

    // Rate limit
    const rl = checkRateLimit(`place-order:${customerId}`, RATE_LIMITS.PLACE_ORDER);
    if (!rl.allowed) {
      log.warn('Rate limited', { customerId, retryAfterMs: rl.retryAfterMs });
      return corsResponse(errorResponse('RATE_LIMITED'), 429, { 'Retry-After': String(Math.ceil(rl.retryAfterMs / 1000)) }, req);
    }

    // Parse and validate request body
    const rawBody = await req.text();
    let body: PlaceOrderRequest;
    try {
      body = JSON.parse(rawBody);
    } catch {
      log.warn('Invalid JSON body');
      return corsResponse(errorResponse('VALIDATION_ERROR', { message_en: 'Invalid JSON in request body' }), 400, undefined, req);
    }

    // === INPUT VALIDATION ===
    const validation = validatePlaceOrderRequest(body);
    if (!validation.valid) {
      log.warn('Validation failed', { errors: validation.errors });
      return corsResponse(
        errorResponse('VALIDATION_ERROR', { message_en: formatValidationErrors(validation.errors) }),
        400,
        undefined,
        req,
      );
    }

    // === G1 GUARD: reject the unimplemented 'wallet' method ===
    // 'wallet' passes shared-constant validation but has no funding path yet.
    // Accepting it would create an order the customer can never pay. Fail fast
    // before any DB work. When the wallet feature ships (plan §Workstream A/B)
    // this guard is replaced by the wallet branch.
    if (body.payment_method === 'wallet') {
      log.warn('Rejected unimplemented payment method', { customerId, method: 'wallet' });
      return corsResponse(errorResponse('PAYMENT_METHOD_UNAVAILABLE'), 400, undefined, req);
    }

    const idempotencyKey = body.idempotency_key || req.headers.get('Idempotency-Key');

    const supabase = getSupabaseAdmin();

    // === IDEMPOTENCY CHECK ===
    if (idempotencyKey) {
      const { data: existingOrder } = await measure('idempotency-check', () =>
        supabase
          .from('orders')
          .select('id, order_number, status, payment_status, total, created_at')
          .eq('idempotency_key', idempotencyKey)
          .maybeSingle(),
        log,
      );

      if (existingOrder) {
        log.info('Idempotent request — returning existing order', { orderId: existingOrder.id });
        return corsResponse(successResponse({
          order_id: existingOrder.id,
          order_number: existingOrder.order_number,
          status: existingOrder.status,
          payment_status: existingOrder.payment_status,
          total: existingOrder.total,
          created_at: existingOrder.created_at,
        }), 200, undefined, req);
      }
    }

    // === DUPLICATE ORDER CHECK (same customer + merchant within 10s) ===
    const tenSecondsAgo = new Date(Date.now() - 10_000).toISOString();
    const { data: recentOrder } = await measure('duplicate-check', () =>
      supabase
        .from('orders')
        .select('id')
        .eq('customer_id', customerId)
        .eq('merchant_id', body.merchant_id)
        .gte('created_at', tenSecondsAgo)
        .maybeSingle(),
      log,
    );

    if (recentOrder) {
      log.warn('Duplicate order detected', { customerId, merchantId: body.merchant_id });
      return corsResponse(errorResponse('DUPLICATE_ORDER'), 409, undefined, req);
    }

    // === PARALLEL VALIDATION: merchant + items + promo ===
    const [merchantResult, itemsResult, promoResult] = await measure('parallel-validation', () =>
      Promise.all([
        validateMerchant(supabase, body.merchant_id, log),
        validateItems(supabase, body.merchant_id, body.items, log),
        body.promo_code ? validatePromo(supabase, body.promo_code, body.merchant_id, customerId, log) : Promise.resolve({ data: null, error: null }),
      ]),
      log,
    );

    if (merchantResult.error) {
      log.warn('Merchant validation failed', { code: merchantResult.error.error.code });
      return corsResponse(merchantResult.error, errorStatus(merchantResult.error.error.code), undefined, req);
    }
    if (itemsResult.error) {
      log.warn('Items validation failed', { code: itemsResult.error.error.code });
      return corsResponse(itemsResult.error, errorStatus(itemsResult.error.error.code), undefined, req);
    }
    if (promoResult.error) {
      log.warn('Promo validation failed', { code: promoResult.error.error.code });
      return corsResponse(promoResult.error, errorStatus(promoResult.error.error.code), undefined, req);
    }

    const merchant = merchantResult.data!;
    const validatedItems = itemsResult.data!;

    // === CHECK DELIVERY RANGE ===
    const distanceKm = haversineDistanceKm(
      body.delivery_address.lat, body.delivery_address.lng,
      merchant.lat, merchant.lng,
    );
    if (distanceKm > merchant.delivery_radius_km) {
      log.warn('Out of delivery range', { distanceKm, radius: merchant.delivery_radius_km });
      return corsResponse(errorResponse('OUT_OF_DELIVERY_RANGE'), 400, undefined, req);
    }

    // === CALCULATE FEES ===
    const subtotal = validatedItems.reduce((sum: number, i: { total_price: number }) => sum + i.total_price, 0);

    // Check min order
    if (subtotal < merchant.min_order_amount) {
      log.warn('Below min order', { subtotal, minOrder: merchant.min_order_amount });
      return corsResponse(errorResponse('BELOW_MIN_ORDER'), 400, undefined, req);
    }

    // Delivery fee via DB function
    const { data: deliveryFeeResult } = await measure('delivery-fee', () =>
      supabase.rpc('calculate_delivery_fee', {
        p_merchant_id: body.merchant_id,
        p_distance_km: distanceKm,
        p_order_subtotal: subtotal,
      }),
      log,
    );
    const deliveryFee = deliveryFeeResult === -1 ? 0 : Number(deliveryFeeResult);

    // === BATCHED PLATFORM CONFIG QUERY ===
    // Fetch platform_fee, promo_max_discount_amount and payment_dispatch_gating
    // in a single query (G5: gating flag rides the existing batch — no extra query).
    const { data: configRows } = await measure('platform-config', () =>
      supabase
        .from('platform_config')
        .select('key, value')
        .in('key', ['platform_fee', 'promo_max_discount_amount', 'payment_dispatch_gating']),
      log,
    );

    const configMap = new Map(
      (configRows || []).map((r: { key: string; value: string }) => [r.key, r.value]),
    );
    const platformFee = Number(configMap.get('platform_fee') || 3);
    const maxDiscount = Number(configMap.get('promo_max_discount_amount') || 100);
    // G5 dispatch gating (migration 094 seed, default 'false'). Missing row or
    // any value other than the exact string 'true' keeps legacy behavior.
    const dispatchGating = (configMap.get('payment_dispatch_gating') || 'false') === 'true';

    // A1-G7: discount calculation extracted to _shared/promo.ts (computePromoDiscount)
    let discountAmount = 0;
    const promoCodeId = promoResult.data?.promo_id || null;
    const promoData = promoResult.data?.promo;

    if (promoData) {
      discountAmount = computePromoDiscount(promoData, subtotal, maxDiscount);
    }

    // W1.4: free_delivery promo — zero out the delivery fee when the validated
    // promo carries the `free_delivery` flag. Previously this flag existed on
    // promo_codes (migration 042) and was settable from the admin UI, but the
    // EF silently ignored it, so customers redeeming a "free delivery" promo
    // still paid the full fee. The check runs AFTER `deliveryFee` is computed
    // and BEFORE `total` is assembled, so both the persisted order and the
    // Paymob amount reflect the waived fee.
    let effectiveDeliveryFee = deliveryFee;
    if (promoData?.free_delivery === true) {
      effectiveDeliveryFee = 0;
      log.info('Free delivery promo applied', { promo_code: body.promo_code });
    }

    // Merchant commission
    const merchantCommissionPct = merchant.commission_pct || 15;

    const total = subtotal + effectiveDeliveryFee + platformFee - discountAmount;

    log.info('Fee calculation', {
      subtotal,
      delivery_fee_computed: deliveryFee,
      delivery_fee_effective: effectiveDeliveryFee,
      platform_fee: platformFee,
      discount_amount: discountAmount,
      total,
      merchant_commission_pct: merchantCommissionPct,
      distance_km: distanceKm,
      free_delivery_promo_applied: effectiveDeliveryFee === 0 && deliveryFee > 0,
    });

    const isDigitalPayment = DIGITAL_METHODS.includes(body.payment_method);
    const paymentStatus = isDigitalPayment ? 'pending' : 'pending_cash';

    // === DIGITAL PAYMENT: Get Paymob payment key via shared module ===
    let paymentKey: string | null = null;
    let iframeUrl: string | null = null;
    let paymobOrderId: string | null = null;

    if (isDigitalPayment) {
      try {
        const paymobResult = await measure('paymob-payment', () =>
          initiatePaymobPayment(total, body.payment_method, customerId, customerEmail, customerPhone),
          log,
        );
        paymentKey = paymobResult.payment_key;
        iframeUrl = paymobResult.iframe_url;
        paymobOrderId = paymobResult.paymob_order_id;
        log.info('Paymob payment initiated', { paymobOrderId });
      } catch (paymobErr) {
        const errMsg = paymobErr instanceof Error ? paymobErr.message : String(paymobErr);
        log.error('Paymob payment initiation failed', { error: errMsg });
        return corsResponse(errorResponse('PAYMENT_INIT_FAILED'), 500, undefined, req);
      }
    }

    // === INSERT ORDER + ORDER_ITEMS ATOMICALLY ===
    // Use Postgres RPC function to insert order + items in a single transaction.
    // This prevents orphaned orders if the items insert fails.
    // The RPC function `place_order_with_items` takes the order + items array
    // and inserts them inside a BEGIN/EXCEPTION/END block, rolling back both on failure.
    // The RPC re-prices every line server-side from COALESCE(discount_price, price)
    // (migration 119), so item_price/total_price below are only a request. The
    // authoritative total is what the function returns -- see the response below.
    const orderItems = validatedItems.map((item: {
      item_id: string; item_name_ar: string; item_name_en: string;
      item_price: number; quantity: number; total_price: number;
      selected_options: unknown; special_instructions: string | null;
    }) => ({
      item_id: item.item_id,
      item_name_ar: item.item_name_ar,
      item_name_en: item.item_name_en,
      item_price: item.item_price,
      quantity: item.quantity,
      total_price: item.total_price,
      selected_options: item.selected_options || [],
      special_instructions: item.special_instructions || null,
    }));

    const { data: order, error: orderError } = await measure('atomic-insert', () =>
      supabase.rpc('place_order_with_items', {
        p_order: {
          customer_id: customerId,
          merchant_id: body.merchant_id,
          status: 'pending',
          delivery_address: body.delivery_address,
          subtotal,
          delivery_fee: effectiveDeliveryFee,
          platform_fee: platformFee,
          discount_amount: discountAmount,
          total,
          payment_method: body.payment_method,
          payment_status: paymentStatus,
          promo_code_id: promoCodeId,
          promo_code: body.promo_code || null,
          distance_km: Math.round(distanceKm * 100) / 100,
          estimated_delivery_minutes: estimateDeliveryMinutes(distanceKm),
          idempotency_key: idempotencyKey || null,
          merchant_commission_pct: merchantCommissionPct,
          paymob_order_id: paymobOrderId,
          notes: body.notes || null,
          scheduled_time: body.scheduled_time || null,
          // Persist the customer's contact phone at order time (gap A1-G2).
          // The RPC reads p_order->>'customer_phone' (migration 049) and stores
          // it on orders.customer_phone so drivers/merchants can reach the
          // customer even if they later change their profile phone.
          customer_phone: customerPhone ?? null,
          // P2-7: pass client IP for promo fraud detection
          customer_ip: customerIp,
        },
        p_items: orderItems,
      }),
      log,
    );

    if (orderError) {
      log.error('Atomic order insert error', { error: orderError.message });
      // The hardened place_order_with_items RPC (migration 036, hardened in
      // 045) is the only order-creation path. If it errors, surface 500 so
      // the operator can investigate — do NOT silently fall back to a
      // less-secure non-atomic insertion that skips promo-usage tracking,
      // platform-fee-percentage, and the per-user promo limit.
      return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
    }

    const orderId = order.id;
    const orderNumber = order.order_number;
    const createdAt = order.created_at;

    log.info('Order created', { orderId, orderNumber, total, paymentMethod: body.payment_method });

    // === FIRE-AND-FORGET: assign driver + send notification ===
    // Sprint 2 fix (S23): previously these were naked fetch().catch(() => {})
    // promises that the Supabase Edge Runtime could terminate when the
    // function returned. If the runtime killed the isolate before the
    // fetch resolved, the order was created with NO driver assignment and
    // NO confirmation notification — silent reliability gap. We now keep
    // the promises alive past the response via EdgeRuntime.waitUntil
    // (mirrors the pattern in paymob-webhook/index.ts:124-130).
    //
    // G5 dispatch gating: with payment_dispatch_gating=true, digital orders are
    // NOT assigned here — they are still payment_status='pending'. The
    // paymob-webhook assigns on the paid transition and reconcile-payments is
    // the safety net (both via _shared/dispatch.ts). Cash is always assigned
    // immediately (payment happens on delivery). With the flag OFF this block
    // behaves exactly as before.
    const assignNow = !dispatchGating || !isDigitalPayment;
    if (!assignNow) {
      log.info('Dispatch gating ON — skipping assignment until payment confirmed', {
        orderId,
        paymentMethod: body.payment_method,
      });
    }
    try {
      const functionUrl = `${Deno.env.get('SUPABASE_URL')}/functions/v1/driver-actions`;
      const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

      // Assign driver (skipped for unpaid digital orders when gating is ON)
      const assignPromise = assignNow ? fetchWithTimeout(functionUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${serviceKey}`,
        },
        body: JSON.stringify({
          action: 'assign',
          order_id: orderId,
          merchant_lat: merchant.lat,
          merchant_lng: merchant.lng,
        }),
      }).then((res) => {
        if (!res.ok) {
          log.warn('driver-actions assign returned non-OK', { status: res.status });
        }
      }).catch((err) => {
        log.warn('driver-actions assign failed', { error: err instanceof Error ? err.message : String(err) });
      }) : Promise.resolve();

      // Send notification
      const notifyUrl = `${Deno.env.get('SUPABASE_URL')}/functions/v1/send-notification`;
      const notifyPromise = fetchWithTimeout(notifyUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${serviceKey}`,
        },
        body: JSON.stringify({
          user_id: customerId,
          title_en: 'Order Confirmed',
          title_ar: 'تم تأكيد الطلب',
          body_en: `Your order #${orderNumber} has been placed`,
          body_ar: `تم تقديم طلبك #${orderNumber}`,
          type: 'order_status',
          reference_id: orderId,
        }),
      }).then((res) => {
        if (!res.ok) {
          log.warn('send-notification returned non-OK', { status: res.status });
        }
      }).catch((err) => {
        log.warn('send-notification failed', { error: err instanceof Error ? err.message : String(err) });
      });

      // Keep both promises alive past the HTTP response so the runtime
      // doesn't kill the isolate mid-fetch. Falls back to inline await
      // if EdgeRuntime.waitUntil isn't available (older runtime).
      try {
        (EdgeRuntime as { waitUntil?: (p: Promise<unknown>) => void }).waitUntil?.(assignPromise);
        (EdgeRuntime as { waitUntil?: (p: Promise<unknown>) => void }).waitUntil?.(notifyPromise);
      } catch {
        await Promise.allSettled([assignPromise, notifyPromise]);
      }
    } catch {
      // Fire-and-forget — errors don't affect order creation
    }

    // === RETURN RESPONSE ===
    const response: Record<string, unknown> = {
      order_id: orderId,
      order_number: orderNumber,
      status: 'pending',
      payment_status: isDigitalPayment ? 'pending' : 'pending_cash',
      total,
      created_at: createdAt,
    };

    if (isDigitalPayment && paymentKey) {
      response.payment_key = paymentKey;
      response.iframe_url = iframeUrl;
      response.payment_status = 'pending';
    }

    log.info('Place-order complete', { orderId, orderNumber });
    return corsResponse(successResponse(response), 201, undefined, req);
  } catch (err) {
    log.error('Unhandled error', { error: err instanceof Error ? err.message : String(err) });
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }
});

// === HELPER: Validate merchant ===
async function validateMerchant(
  supabase: ReturnType<typeof getSupabaseAdmin>,
  merchantId: string,
  log: ReturnType<typeof createLogger>,
) {
  const { data: merchant, error } = await supabase
    .from('merchants')
    .select('id, lat, lng, delivery_radius_km, min_order_amount, is_active, approval_status, commission_pct')
    .eq('id', merchantId)
    .single();

  if (error || !merchant) return { data: null, error: errorResponse('MERCHANT_NOT_FOUND') };
  if (!merchant.is_active) return { data: null, error: errorResponse('MERCHANT_INACTIVE') };
  // Approval is checked here, not only in the feed. This is the last gate
  // before money moves, and it runs on service_role, which bypasses the RLS
  // policy that migration 109 fixed. Without it a customer who already had the
  // merchant id could order from a pending vendor even while the feed hid it.
  if (merchant.approval_status !== 'approved') {
    return { data: null, error: errorResponse('MERCHANT_NOT_APPROVED') };
  }

  // Check open status using DB function
  const { data: isOpen } = await supabase.rpc('is_merchant_open', { p_merchant_id: merchantId });
  if (!isOpen) return { data: null, error: errorResponse('MERCHANT_CLOSED') };

  log.debug('Merchant validated', { merchantId, isActive: merchant.is_active });
  return { data: merchant, error: null };
}

// === HELPER: Validate items and re-fetch prices ===
async function validateItems(
  supabase: ReturnType<typeof getSupabaseAdmin>,
  merchantId: string,
  items: PlaceOrderRequest['items'],
  log: ReturnType<typeof createLogger>,
) {
  if (!items || items.length === 0) {
    return { data: null, error: errorResponse('ITEM_UNAVAILABLE') };
  }

  const itemIds = items.map((i) => i.item_id);

  // Single query to fetch all items for this merchant
  const { data: dbItems, error } = await supabase
    .from('items')
    .select(
      'id, name_ar, name_en, price, discount_price, is_available, merchant_id, category_id, deleted_at',
    )
    .in('id', itemIds)
    // Soft-deleted items (migration 110) are excluded from the catalog. Without
    // this filter a deleted item still validates here and can be ordered.
    .is('deleted_at', null);

  if (error) return { data: null, error: errorResponse('INTERNAL_ERROR') };

  const itemMap = new Map(dbItems.map((i: { id: string }) => [i.id, i]));

  const validatedItems = [];
  for (const reqItem of items) {
    const dbItem = itemMap.get(reqItem.item_id);
    if (!dbItem) return { data: null, error: errorResponse('ITEM_UNAVAILABLE') };
    if (!dbItem.is_available) return { data: null, error: errorResponse('ITEM_UNAVAILABLE') };
    if (dbItem.merchant_id !== merchantId) return { data: null, error: errorResponse('ITEM_MISMATCH') };

    // Re-fetch options and calculate option modifiers
    let optionsTotal = 0;
    const selectedOptions = [];

    if (reqItem.selected_options && reqItem.selected_options.length > 0) {
      const optionIds = reqItem.selected_options.map((o) => o.option_id);
      const choiceIds = reqItem.selected_options.flatMap((o) => o.choice_ids);

      const [optionsResult, choicesResult] = await Promise.all([
        supabase.from('item_options').select('id, group_name_ar, group_name_en').in('id', optionIds),
        supabase.from('item_option_choices').select('id, option_id, name_ar, name_en, price_modifier').in('id', choiceIds),
      ]);

      const choicesMap = new Map(
        (choicesResult.data || []).map((c: { id: string }) => [c.id, c]),
      );
      const optionsMap = new Map(
        (optionsResult.data || []).map((o: { id: string }) => [o.id, o]),
      );

      for (const selOpt of reqItem.selected_options) {
        const opt = optionsMap.get(selOpt.option_id);
        for (const cid of selOpt.choice_ids) {
          const choice = choicesMap.get(cid);
          if (choice) {
            optionsTotal += choice.price_modifier || 0;
            selectedOptions.push({
              option_name_ar: opt?.group_name_ar || '',
              option_name_en: opt?.group_name_en || '',
              choice_name_ar: choice.name_ar,
              choice_name_en: choice.name_en,
              price_modifier: choice.price_modifier,
            });
          }
        }
      }
    }

    // Effective selling price (migration 119): a promotional price applies to
    // every customer, always -- there is no scheduling or code requirement, so
    // this is not conditional on anything. Mirrors place_order_with_items, which
    // resolves COALESCE(discount_price, price) server-side; using list price here
    // while the SQL function used the discounted one is how the two paths drift
    // and charge different totals for the same basket.
    const listPrice = Number(dbItem.price);
    const sellPrice =
      dbItem.discount_price === null || dbItem.discount_price === undefined
        ? listPrice
        : Number(dbItem.discount_price);

    const unitPrice = sellPrice + optionsTotal;
    const totalPrice = unitPrice * reqItem.quantity;

    validatedItems.push({
      item_id: dbItem.id,
      item_name_ar: dbItem.name_ar,
      item_name_en: dbItem.name_en,
      item_price: sellPrice,
      original_price: listPrice,
      quantity: reqItem.quantity,
      total_price: totalPrice,
      selected_options: selectedOptions,
      special_instructions: reqItem.special_instructions || null,
    });
  }

  log.debug('Items validated', { count: validatedItems.length, subtotal: validatedItems.reduce((s, i) => s + i.total_price, 0) });
  return { data: validatedItems, error: null };
}

// === HELPER: Validate promo code ===
// A1-G7: validation logic extracted to _shared/promo.ts (validatePromoCode).
// This helper now delegates to the shared module so that validate-promo EF
// and place-order EF use the same checks. Returns the promo row on success
// or an errorResponse on failure (the place-order EF uses errorResponse codes
// rather than user-friendly messages).
//
// NOTE: subtotal is NOT passed here because it's not known yet (items are
// validated in parallel). The caller checks min_order_amount separately
// after computing the subtotal. The shared validatePromoCode function skips
// the min_order check when subtotal is omitted.
async function validatePromo(
  supabase: ReturnType<typeof getSupabaseAdmin>,
  code: string,
  merchantId: string,
  customerId: string,
  log: ReturnType<typeof createLogger>,
) {
  const result = await validatePromoCode(supabase, code, merchantId, customerId);

  if (!result.valid) {
    // Map the shared module's reason codes to errorResponse codes.
    const REASON_TO_ERROR_CODE: Record<string, string> = {
      NOT_FOUND: 'PROMO_INVALID',
      INACTIVE: 'PROMO_INVALID',
      NOT_YET_ACTIVE: 'PROMO_EXPIRED',
      EXPIRED: 'PROMO_EXPIRED',
      MAX_USES_REACHED: 'PROMO_MAX_USES',
      MAX_USES_PER_USER_REACHED: 'PROMO_MAX_USES_PER_USER',
      BELOW_MIN_ORDER: 'PROMO_INVALID',
      MERCHANT_MISMATCH: 'PROMO_MERCHANT_MISMATCH',
    };
    const errorCode = REASON_TO_ERROR_CODE[result.reason] || 'PROMO_INVALID';
    log.info('Promo validation failed', { code, reason: result.reason, errorCode });
    return { data: null, error: errorResponse(errorCode as 'PROMO_INVALID') };
  }

  log.debug('Promo validated', {
    code,
    discountType: result.promo.discount_type,
    discountValue: result.promo.discount_value,
  });
  // Return the full promo object so the caller can calculate discount_amount
  // using the subtotal (which is only known after item validation)
  return { data: { promo_id: result.promo_id, promo: result.promo }, error: null };
}
