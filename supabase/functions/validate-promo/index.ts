// Edge Function: validate-promo
// P3B-01 + P3B-02: Validate promo code and return discount amount
// Rate limited (10/min/customer)
//
// Production hardening:
//   - Input validation via shared validation module
//   - Request size validation (Content-Length check)
//   - Structured JSON logging with request ID tracking
//   - Batched platform_config query (promo_max_discount_amount)

import { corsResponse, handleOptions } from '../_shared/cors.ts';
import { errorResponse, errorStatus, successResponse } from '../_shared/errors.ts';
import { checkRateLimit, RATE_LIMITS } from '../_shared/rate-limit.ts';
import { getSupabaseAdmin } from '../_shared/supabase.ts';
import { authenticate } from '../_shared/auth.ts';
import { validatePromoRequest, validateRequestSize, formatValidationErrors } from '../_shared/validation.ts';
import { createLogger, generateRequestId } from '../_shared/logger.ts';
import { validatePromoCode, computePromoDiscount } from '../_shared/promo.ts';

interface ValidatePromoRequest {
  code: string;
  merchant_id: string;
  subtotal: number;
  // P2-4: optional customer delivery address city/area for geo-targeted promos.
  customer_city?: string;
  customer_area?: string;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions(req);

  const requestId = generateRequestId();
  const log = createLogger({ requestId, functionName: 'validate-promo' });

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
    const rl = checkRateLimit(`promo:${authResult.data!.userId}`, RATE_LIMITS.VALIDATE_PROMO);
    if (!rl.allowed) {
      log.warn('Rate limited', { userId: authResult.data!.userId, retryAfterMs: rl.retryAfterMs });
      return corsResponse(errorResponse('RATE_LIMITED'), 429, { 'Retry-After': String(Math.ceil(rl.retryAfterMs / 1000)) }, req);
    }

    // Parse and validate request body
    const rawBody = await req.text();
    let body: ValidatePromoRequest;
    try {
      body = JSON.parse(rawBody);
    } catch {
      log.warn('Invalid JSON body');
      return corsResponse(errorResponse('VALIDATION_ERROR', { message_en: 'Invalid JSON in request body' }), 400, undefined, req);
    }

    // === INPUT VALIDATION ===
    const validation = validatePromoRequest(body);
    if (!validation.valid) {
      log.warn('Validation failed', { errors: validation.errors });
      return corsResponse(
        errorResponse('VALIDATION_ERROR', { message_en: formatValidationErrors(validation.errors) }),
        400,
        undefined,
        req,
      );
    }

    const { code, merchant_id, subtotal, customer_city, customer_area } = body;

    const supabase = getSupabaseAdmin();

    // A1-G7: validation logic extracted to _shared/promo.ts (validatePromoCode).
    // This EF and place-order/index.ts now share the same checks.
    // P2-4: pass customer_city/customer_area for geo-targeted promo validation.
    const result = await validatePromoCode(
      supabase,
      code,
      merchant_id,
      authResult.data!.userId,
      subtotal,
      customer_city,
      customer_area,
    );

    if (!result.valid) {
      log.info('Promo validation failed', { code, reason: result.reason });
      return corsResponse(successResponse({
        valid: false,
        reason: result.reason,
        message_en: result.message_en,
        message_ar: result.message_ar,
      }), 200, undefined, req);
    }

    const promo = result.promo;

    // Calculate discount
    // === BATCHED PLATFORM CONFIG QUERY ===
    // Fetch promo_max_discount_amount in a single batch query
    const { data: configRows } = await supabase
      .from('platform_config')
      .select('key, value')
      .in('key', ['promo_max_discount_amount']);

    const configMap = new Map(
      (configRows || []).map((r: { key: string; value: string }) => [r.key, r.value]),
    );
    const maxDiscountCap = Number(configMap.get('promo_max_discount_amount') || 100);

    // A1-G7: discount calculation extracted to _shared/promo.ts (computePromoDiscount)
    const discountAmount = computePromoDiscount(promo, subtotal, maxDiscountCap);

    log.info('Promo validated successfully', {
      code,
      discountType: promo.discount_type,
      discountValue: promo.discount_value,
      discountAmount,
    });

    return corsResponse(successResponse({
      valid: true,
      discount_type: promo.discount_type,
      discount_value: promo.discount_value,
      discount_amount: discountAmount,
      min_order_amount: promo.min_order_amount,
      description_en: promo.description_en,
      description_ar: promo.description_ar,
      free_delivery: promo.free_delivery,
    }), 200, undefined, req);
  } catch (err) {
    log.error('Unhandled error', { error: err instanceof Error ? err.message : String(err) });
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }
});
