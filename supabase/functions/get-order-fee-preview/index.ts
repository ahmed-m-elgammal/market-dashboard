// Edge Function: get-order-fee-preview
// P3A-04 + P3A-05: Calculate delivery fee + total breakdown before placing order
// Rate limited (15/min/customer)
//
// FIX: Percentage promo discount now properly capped at max_discount_amount
// (was incorrectly capped at discount_value which is the percentage, not an amount)
//
// Production hardening:
//   - Input validation via shared validation module
//   - Request size validation (Content-Length check)
//   - Structured JSON logging with request ID tracking
//   - Batched platform_config queries (1 query instead of 2 separate)

import { corsResponse, handleOptions } from '../_shared/cors.ts';
import { errorResponse, errorStatus, successResponse } from '../_shared/errors.ts';
import { checkRateLimit, RATE_LIMITS } from '../_shared/rate-limit.ts';
import { getSupabaseAdmin } from '../_shared/supabase.ts';
import { haversineDistanceKm, estimateDeliveryMinutes } from '../_shared/geo.ts';
import { authenticate } from '../_shared/auth.ts';
import { validateFeePreviewRequest, validateRequestSize, formatValidationErrors } from '../_shared/validation.ts';
import { createLogger, generateRequestId } from '../_shared/logger.ts';
import { validatePromoCode, computePromoDiscount } from '../_shared/promo.ts';

interface FeePreviewRequest {
  merchant_id: string;
  delivery_lat: number;
  delivery_lng: number;
  subtotal: number;
  promo_code?: string;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions(req);

  const requestId = generateRequestId();
  const log = createLogger({ requestId, functionName: 'get-order-fee-preview' });

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

    const authResult = await authenticate(req.headers.get('Authorization'));
    if (authResult.error) {
      log.warn('Auth failed', { code: authResult.error.error.code });
      return corsResponse(authResult.error, errorStatus(authResult.error.error.code), undefined, req);
    }

    log.info('User authenticated', { userId: authResult.data!.userId });

    // Rate limit
    const rl = checkRateLimit(`fee-preview:${authResult.data!.userId}`, RATE_LIMITS.FEE_PREVIEW);
    if (!rl.allowed) {
      log.warn('Rate limited', { userId: authResult.data!.userId, retryAfterMs: rl.retryAfterMs });
      return corsResponse(errorResponse('RATE_LIMITED'), 429, { 'Retry-After': String(Math.ceil(rl.retryAfterMs / 1000)) }, req);
    }

    // Parse and validate request body
    const rawBody = await req.text();
    let body: FeePreviewRequest;
    try {
      body = JSON.parse(rawBody);
    } catch {
      log.warn('Invalid JSON body');
      return corsResponse(errorResponse('VALIDATION_ERROR', { message_en: 'Invalid JSON in request body' }), 400, undefined, req);
    }

    // === INPUT VALIDATION ===
    const validation = validateFeePreviewRequest(body);
    if (!validation.valid) {
      log.warn('Validation failed', { errors: validation.errors });
      return corsResponse(
        errorResponse('VALIDATION_ERROR', { message_en: formatValidationErrors(validation.errors) }),
        400,
        undefined,
        req,
      );
    }

    const { merchant_id, delivery_lat, delivery_lng, subtotal, promo_code } = body;

    const supabase = getSupabaseAdmin();

    // Get merchant details
    const { data: merchant, error: merchantError } = await supabase
      .from('merchants')
      .select('id, lat, lng, delivery_radius_km, delivery_fee_override, min_order_amount, is_active, approval_status')
      .eq('id', merchant_id)
      .single();

    if (merchantError || !merchant) {
      log.warn('Merchant not found', { merchantId: merchant_id });
      return corsResponse(errorResponse('MERCHANT_NOT_FOUND'), 404, undefined, req);
    }

    if (!merchant.is_active) {
      log.warn('Merchant inactive', { merchantId: merchant_id });
      return corsResponse(errorResponse('MERCHANT_INACTIVE'), 400, undefined, req);
    }

    // Same gate as place-order, for the same reason: service_role bypasses the
    // RLS policy, and a fee quote for an unapproved vendor is a step toward an
    // order nobody should be able to take.
    if (merchant.approval_status !== 'approved') {
      log.warn('Merchant not approved', { merchantId: merchant_id });
      return corsResponse(errorResponse('MERCHANT_NOT_APPROVED'), 400, undefined, req);
    }

    // Calculate distance
    const distanceKm = haversineDistanceKm(delivery_lat, delivery_lng, merchant.lat, merchant.lng);

    // Check delivery range
    if (distanceKm > merchant.delivery_radius_km) {
      log.warn('Out of delivery range', { distanceKm, radius: merchant.delivery_radius_km });
      return corsResponse(errorResponse('OUT_OF_DELIVERY_RANGE'), 400, undefined, req);
    }

    // Calculate delivery fee using DB function
    const { data: feeResult, error: feeError } = await supabase.rpc('calculate_delivery_fee', {
      p_merchant_id: merchant_id,
      p_distance_km: distanceKm,
      p_order_subtotal: subtotal,
    });

    if (feeError) {
      log.error('calculate_delivery_fee error', { error: feeError.message });
      return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
    }

    if (feeResult === -1) {
      return corsResponse(errorResponse('OUT_OF_DELIVERY_RANGE'), 400, undefined, req);
    }

    const deliveryFee = Number(feeResult);

    // === BATCHED PLATFORM CONFIG QUERY ===
    // §4.4 fix: fetch ALL 4 config keys in a single query (previously
    // promo_max_discount_amount was fetched in a separate query inside the
    // promo branch — two round-trips when one would do).
    //   - platform_fee: flat fee added to every order
    //   - delivery_free_threshold: subtotal >= this → free delivery (platform-wide)
    //   - merchant_discount_floor: S1 knob — when funded_by='shared' and
    //     discount <= floor, platform absorbs 100% (see migration 080's CASE)
    //   - promo_max_discount_amount: cap on percentage-promo discounts
    const { data: configRows } = await supabase
      .from('platform_config')
      .select('key, value')
      .in('key', ['platform_fee', 'delivery_free_threshold', 'merchant_discount_floor', 'promo_max_discount_amount']);

    const configMap = new Map(
      (configRows || []).map((r: { key: string; value: string }) => [r.key, r.value]),
    );
    const platformFee = Number(configMap.get('platform_fee') || 3);
    const freeDeliveryThreshold = Number(configMap.get('delivery_free_threshold') || 200);
    const merchantDiscountFloor = Number(configMap.get('merchant_discount_floor') || 0);
    const maxDiscountCap = Number(configMap.get('promo_max_discount_amount') || 100);

    // Promo validation (if code provided).
    // A1-G7: uses the shared validatePromoCode from _shared/promo.ts so this
    // EF and validate-promo/place-order use the same checks.
    // A1-G4: surfaces the rejection reason so the UI can display why the
    // promo was rejected (below min order, expired, etc.) without requiring
    // the customer to tap "Apply" on the promo input.
    let discountAmount = 0;
    let promoRejectionReason: string | null = null;
    let promoRejectionMessageEn: string | null = null;
    let promoRejectionMessageAr: string | null = null;
    let validatedPromo: {
      free_delivery?: boolean;
      funded_by?: 'platform' | 'merchant' | 'shared';
      merchant_share_pct?: number;
    } | null = null;

    if (promo_code) {
      const result = await validatePromoCode(
        supabase,
        promo_code,
        merchant_id,
        authResult.data!.userId,
        subtotal,
      );

      if (result.valid) {
        // §4.4 fix: maxDiscountCap is already fetched in the batched
        // platform_config query above — no second round-trip needed.
        // A1-G7: discount calculation extracted to _shared/promo.ts
        discountAmount = computePromoDiscount(result.promo, subtotal, maxDiscountCap);
        validatedPromo = result.promo;
        log.info('Promo applied', {
          code: promo_code,
          discountType: result.promo.discount_type,
          discountAmount,
          fundedBy: result.promo.funded_by,
        });
      } else {
        // A1-G4: capture the rejection reason so the UI can display it.
        promoRejectionReason = result.reason;
        promoRejectionMessageEn = result.message_en;
        promoRejectionMessageAr = result.message_ar;
        log.info('Promo not valid', { code: promo_code, reason: result.reason });
      }
    }

    // S1: compute the promo funding breakdown so the customer (and admin) can
    // see who absorbs the discount before checkout. Mirrors the CASE statement
    // in migration 080's place_order_with_items RPC:
    //   - platform → merchant absorbs 0, platform absorbs discount_amount
    //   - merchant → merchant absorbs discount_amount, platform absorbs 0
    //   - shared   → merchant absorbs discount_amount × pct / 100 (but 0 when
    //                discount <= merchant_discount_floor), platform absorbs the rest
    // Returns null when no valid promo was applied, so the mobile UI can omit
    // the funding badge cleanly.
    let promoFundingBreakdown: {
      funded_by: 'platform' | 'merchant' | 'shared';
      merchant_share_pct: number;
      merchant_discount_share: number;
      platform_discount_share: number;
    } | null = null;
    if (validatedPromo && discountAmount > 0) {
      const fundedBy = validatedPromo.funded_by ?? 'platform';
      const merchantSharePct = validatedPromo.merchant_share_pct ?? 50;
      let merchantDiscountShare: number;
      if (fundedBy === 'platform') {
        merchantDiscountShare = 0;
      } else if (fundedBy === 'merchant') {
        merchantDiscountShare = discountAmount;
      } else {
        // shared — apply the floor (mirrors migration 080's CASE)
        if (discountAmount <= merchantDiscountFloor) {
          merchantDiscountShare = 0;
        } else {
          merchantDiscountShare = Math.round(discountAmount * merchantSharePct) / 100;
        }
      }
      const platformDiscountShare = Math.round((discountAmount - merchantDiscountShare) * 100) / 100;
      promoFundingBreakdown = {
        funded_by: fundedBy,
        merchant_share_pct: merchantSharePct,
        merchant_discount_share: merchantDiscountShare,
        platform_discount_share: platformDiscountShare,
      };
    }

    // W1.4: free_delivery promo — zero out the delivery fee when the validated
    // promo carries the `free_delivery` flag. The preview shown to the customer
    // before checkout MUST reflect the waived fee, otherwise the cart total
    // disagrees with the eventual order total (place-order EF applies the same
    // zeroing). Note: `free_delivery_eligible` below is a SEPARATE concept —
    // it tracks the platform-wide `delivery_free_threshold` spend-tier
    // promotion (subtotal >= 200 EGP → free delivery). The per-promo boolean
    // flag here overrides regardless of subtotal.
    let effectiveDeliveryFee = deliveryFee;
    const freeDeliveryPromoApplied = validatedPromo?.free_delivery === true;
    if (freeDeliveryPromoApplied) {
      effectiveDeliveryFee = 0;
      log.info('Free delivery promo applied', { promo_code });
    }

    const total = subtotal + effectiveDeliveryFee + platformFee - discountAmount;

    log.info('Fee preview calculated', {
      subtotal,
      delivery_fee_computed: deliveryFee,
      delivery_fee_effective: effectiveDeliveryFee,
      platform_fee: platformFee,
      discount_amount: discountAmount,
      total,
      distance_km: Math.round(distanceKm * 10) / 10,
      promoRejectionReason,
      free_delivery_promo_applied: freeDeliveryPromoApplied,
      promo_funding_breakdown: promoFundingBreakdown,
    });

    return corsResponse(successResponse({
      subtotal,
      delivery_fee: effectiveDeliveryFee,
      platform_fee: platformFee,
      discount_amount: discountAmount,
      total: Math.max(total, 0),
      free_delivery_eligible: subtotal >= freeDeliveryThreshold,
      amount_to_free_delivery: Math.max(freeDeliveryThreshold - subtotal, 0),
      distance_km: Math.round(distanceKm * 10) / 10,
      estimated_delivery_minutes: estimateDeliveryMinutes(distanceKm),
      // W1.4: surface the per-promo free_delivery override so the mobile
      // checkout can show "Free delivery" before the customer taps Place Order.
      free_delivery_promo_applied: freeDeliveryPromoApplied,
      // S1: surface the funding breakdown so the mobile UI can show
      // "Merchant absorbs X EGP, Platform absorbs Y EGP" and so the admin
      // dashboard fee-preview (if any) can verify the split. null when no
      // valid promo was applied.
      promo_funding_breakdown: promoFundingBreakdown,
      // A1-G4: surface promo rejection reason so the UI can display it.
      // null when promo is valid or no promo code was provided.
      promo_rejection_reason: promoRejectionReason,
      promo_rejection_message_en: promoRejectionMessageEn,
      promo_rejection_message_ar: promoRejectionMessageAr,
    }), 200, undefined, req);
  } catch (err) {
    log.error('Unhandled error', { error: err instanceof Error ? err.message : String(err) });
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }
});
