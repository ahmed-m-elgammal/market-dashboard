// Shared promo code validation logic.
//
// A1-G7: Previously duplicated in:
//   - supabase/functions/validate-promo/index.ts (user-facing validation EF)
//   - supabase/functions/place-order/index.ts (validatePromo helper)
//
// The two implementations had subtle differences (e.g., validate-promo checks
// min_order_amount, place-order doesn't because subtotal isn't known yet).
// This shared module extracts the common checks so both EFs use the same
// logic. The caller is responsible for:
//   - Computing discount_amount (needs subtotal, which may not be available
//     at validation time in the place-order EF)
//   - Mapping the result to their own response shape (validate-promo returns
//     user-friendly messages; place-order returns errorResponse codes)

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

// Promo row shape returned by the promo_codes table SELECT *.
// Matches the schema in migration 011_create_promo_codes.sql.
export interface PromoRow {
  id: string;
  code: string;
  description_ar: string | null;
  description_en: string | null;
  discount_type: 'percentage' | 'flat';
  discount_value: number;
  max_discount_amount: number;
  min_order_amount: number;
  max_usage: number;
  current_usage: number;
  max_usage_per_user: number;
  starts_at: string;
  expires_at: string;
  is_active: boolean;
  merchant_id: string | null;
  category: string | null;
  free_delivery: boolean;
  city: string | null;
  area: string | null;
  target_segment: 'all' | 'new_users' | 'first_order' | 'dormant_30d';
  funded_by: 'platform' | 'merchant' | 'shared';
  merchant_share_pct: number;
}

export type PromoValidationReason =
  | 'NOT_FOUND'
  | 'INACTIVE'
  | 'NOT_YET_ACTIVE'
  | 'EXPIRED'
  | 'MAX_USES_REACHED'
  | 'MAX_USES_PER_USER_REACHED'
  | 'BELOW_MIN_ORDER'
  | 'MERCHANT_MISMATCH'
  | 'CITY_MISMATCH'
  | 'SEGMENT_MISMATCH';

export interface PromoValidationSuccess {
  valid: true;
  promo_id: string;
  promo: PromoRow;
}

export interface PromoValidationFailure {
  valid: false;
  reason: PromoValidationReason;
  message_en: string;
  message_ar: string;
}

export type PromoValidationResult = PromoValidationSuccess | PromoValidationFailure;

// Bilingual messages for each rejection reason. Used by the validate-promo EF
// to return user-friendly messages. The place-order EF maps reasons to
// errorResponse codes instead.
const PROMO_REJECTION_MESSAGES: Record<PromoValidationReason, { en: string; ar: string }> = {
  NOT_FOUND: {
    en: 'Promo code not found',
    ar: 'كود الخصم غير موجود',
  },
  INACTIVE: {
    en: 'This promo code is no longer active',
    ar: 'كود الخصم لم يعد نشطاً',
  },
  NOT_YET_ACTIVE: {
    en: 'This promo code is not yet active',
    ar: 'كود الخصم لم يبدأ بعد',
  },
  EXPIRED: {
    en: 'This promo code has expired',
    ar: 'انتهت صلاحية كود الخصم',
  },
  MAX_USES_REACHED: {
    en: 'This promo code has reached its usage limit',
    ar: 'وصل كود الخصم للحد الأقصى للاستخدام',
  },
  MAX_USES_PER_USER_REACHED: {
    en: 'You have already used this promo code the maximum number of times',
    ar: 'لقد استخدمت كود الخصم هذا الحد الأقصى من المرات',
  },
  BELOW_MIN_ORDER: {
    en: 'Your order total is below the minimum for this promo',
    ar: 'إجمالي طلبك أقل من الحد الأدنى لهذا الكود',
  },
  MERCHANT_MISMATCH: {
    en: 'This promo is not valid for this merchant',
    ar: 'كود الخصم غير صالح لهذا التاجر',
  },
  CITY_MISMATCH: {
    en: 'This promo is not valid for your delivery area',
    ar: 'كود الخصم غير صالح لمنطقة التوصيل الخاصة بك',
  },
  SEGMENT_MISMATCH: {
    en: 'This promo is not available for your account type',
    ar: 'كود الخصم غير متاح لنوع حسابك',
  },
};

function reject(reason: PromoValidationReason, minOrderAmount?: number): PromoValidationFailure {
  const msgs = PROMO_REJECTION_MESSAGES[reason];
  // For BELOW_MIN_ORDER, include the actual threshold in the message.
  if (reason === 'BELOW_MIN_ORDER' && minOrderAmount != null) {
    return {
      valid: false,
      reason,
      message_en: `Your order total is below the minimum (${minOrderAmount} EGP)`,
      message_ar: `إجمالي طلبك أقل من الحد الأدنى (${minOrderAmount} ج.م)`,
    };
  }
  return { valid: false, reason, message_en: msgs.en, message_ar: msgs.ar };
}

/**
 * Validate a promo code against the common business rules.
 *
 * Checks performed (in order):
 *   1. Promo code exists in the database
 *   2. is_active = true
 *   3. Current time is within [starts_at, expires_at]
 *   4. current_usage < max_usage (global limit)
 *   5. Per-user usage < max_usage_per_user (queries promo_code_usage table)
 *   6. subtotal >= min_order_amount (ONLY if subtotal is provided)
 *   7. merchant_id matches (if promo is merchant-scoped)
 *   8. city/area matches (if promo is city/area-scoped — P2-4)
 *
 * @param supabase - Service-role Supabase client
 * @param code - The promo code string to validate
 * @param merchantId - The merchant ID from the order context
 * @param customerId - The customer UUID (for per-user usage check)
 * @param subtotal - Optional order subtotal. If provided, the min_order_amount
 *   check is performed. If omitted, the caller must check min_order_amount
 *   separately after computing the subtotal.
 * @param customerCity - Optional customer delivery address city (P2-4).
 *   If provided AND the promo has a city set, they must match (case-insensitive).
 * @param customerArea - Optional customer delivery address area (P2-4).
 *   If provided AND the promo has an area set, they must match (case-insensitive).
 * @returns Discriminated union: { valid: true, promo_id, promo } or
 *   { valid: false, reason, message_en, message_ar }
 */
export async function validatePromoCode(
  supabase: SupabaseClient,
  code: string,
  merchantId: string,
  customerId: string,
  subtotal?: number,
  customerCity?: string,
  customerArea?: string,
): Promise<PromoValidationResult> {
  // 1. Look up promo code
  const { data: promo, error } = await supabase
    .from('promo_codes')
    .select('*')
    .eq('code', code)
    .single();

  if (error || !promo) {
    return reject('NOT_FOUND');
  }

  // 2. Check is_active
  if (!promo.is_active) {
    return reject('INACTIVE');
  }

  // 3. Check date range
  const now = new Date().toISOString();
  if (now < promo.starts_at) {
    return reject('NOT_YET_ACTIVE');
  }
  if (now > promo.expires_at) {
    return reject('EXPIRED');
  }

  // 4. Check global usage limit
  if (promo.current_usage >= promo.max_usage) {
    return reject('MAX_USES_REACHED');
  }

  // 5. Check per-user usage limit.
  // SECURITY: Without this check, a single customer could apply a "1 per user"
  // promo on every order until the global max_usage is exhausted.
  const { count: userUsageCount, error: userUsageError } = await supabase
    .from('promo_code_usage')
    .select('id', { count: 'exact', head: true })
    .eq('promo_code_id', promo.id)
    .eq('user_id', customerId);

  if (userUsageError) {
    // Fail closed: if we can't verify the user hasn't exceeded the limit,
    // reject the promo. Same reason as the per-user limit reached so we
    // don't leak whether the promo exists.
    return reject('MAX_USES_PER_USER_REACHED');
  }

  if ((userUsageCount ?? 0) >= promo.max_usage_per_user) {
    return reject('MAX_USES_PER_USER_REACHED');
  }

  // 6. Check min_order_amount (only if subtotal is provided)
  if (subtotal != null && subtotal < promo.min_order_amount) {
    return reject('BELOW_MIN_ORDER', promo.min_order_amount);
  }

  // 7. Check merchant match
  if (promo.merchant_id && promo.merchant_id !== merchantId) {
    return reject('MERCHANT_MISMATCH');
  }

  // 8. Check city/area match (P2-4)
  // If the promo has a city set, the customer's city must match (case-insensitive).
  // If the promo has an area set, the customer's area must match too.
  // If customerCity/customerArea are not provided, skip the check (the caller
  // is responsible for passing them — e.g. validate-promo EF gets them from
  // the request body, place-order EF gets them from the delivery address).
  const promoCity = (promo as { city?: string | null }).city ?? null;
  const promoArea = (promo as { area?: string | null }).area ?? null;
  if (promoCity && customerCity != null) {
    if (promoCity.toLowerCase() !== customerCity.toLowerCase()) {
      return reject('CITY_MISMATCH');
    }
  }
  if (promoArea && customerArea != null) {
    if (promoArea.toLowerCase() !== customerArea.toLowerCase()) {
      return reject('CITY_MISMATCH');
    }
  }

  // 9. Check user segment (P2-5)
  // If target_segment is 'all', skip. Otherwise fetch the customer's
  // profile created_at + order history to determine eligibility.
  const targetSegment = (promo as { target_segment?: string }).target_segment ?? 'all';
  if (targetSegment !== 'all') {
    // Fetch profile.created_at
    const { data: customer, error: custErr } = await supabase
      .from('profiles')
      .select('created_at')
      .eq('id', customerId)
      .single();

    if (custErr || !customer) {
      // Fail closed — can't verify eligibility
      return reject('SEGMENT_MISMATCH');
    }

    // Fetch order count + last order date in one query
    const { data: orderStats, error: orderErr } = await supabase
      .from('orders')
      .select('created_at')
      .eq('customer_id', customerId)
      .neq('status', 'cancelled')
      .order('created_at', { ascending: false })
      .limit(1);

    if (orderErr) {
      return reject('SEGMENT_MISMATCH');
    }

    const orderCount = orderStats?.length ?? 0;
    const lastOrderAt = orderStats?.[0]?.created_at ?? null;
    const profileCreatedAt = (customer as { created_at: string }).created_at;

    switch (targetSegment) {
      case 'new_users': {
        // Account created within the last 7 days
        const sevenDaysAgo = Date.now() - 7 * 86400_000;
        if (new Date(profileCreatedAt).getTime() < sevenDaysAgo) {
          return reject('SEGMENT_MISMATCH');
        }
        break;
      }
      case 'first_order': {
        // No non-cancelled orders yet
        if (orderCount > 0) {
          return reject('SEGMENT_MISMATCH');
        }
        break;
      }
      case 'dormant_30d': {
        // At least one historical order, but none in the last 30 days
        if (orderCount === 0) {
          return reject('SEGMENT_MISMATCH');
        }
        const thirtyDaysAgo = Date.now() - 30 * 86400_000;
        if (lastOrderAt && new Date(lastOrderAt).getTime() > thirtyDaysAgo) {
          return reject('SEGMENT_MISMATCH');
        }
        break;
      }
    }
  }

  return { valid: true, promo_id: promo.id, promo: promo as PromoRow };
}

/**
 * Compute the discount amount for a validated promo.
 *
 * Both EFs use the same formula:
 *   - flat:       min(discount_value, subtotal, perPromoCap)
 *   - percentage: min(round(subtotal * discount_value / 100, 2), perPromoCap)
 *
 * The per-promo cap is `min(promo.max_discount_amount, maxDiscountCap)` —
 * the per-promo column is the primary cap, and the global
 * `platform_config.promo_max_discount_amount` (passed in as `maxDiscountCap`)
 * acts as a backstop ceiling that per-promo caps cannot exceed.
 *
 * P0-2 fix (MARKETING-IMPROVEMENT-PLAN.md Task 1.2):
 * The previous implementation ignored `promo.max_discount_amount` entirely
 * for percentage discounts (using only the global cap) and applied NO cap
 * at all for flat discounts. This caused a 50% promo with a 20 EGP
 * per-promo cap to grant 100 EGP off on a 1,000 EGP order — an 80 EGP
 * over-discount per redemption.
 *
 * The caller is responsible for fetching `maxDiscountCap` from
 * platform_config — this function takes it as a parameter to avoid a
 * redundant DB query when the caller already has it.
 */
export function computePromoDiscount(
  promo: PromoRow,
  subtotal: number,
  maxDiscountCap: number,
): number {
  // Per-promo cap is the primary limit; the global cap is a backstop ceiling.
  const perPromoCap = Math.min(promo.max_discount_amount, maxDiscountCap);

  if (promo.discount_type === 'flat') {
    // Flat discounts are capped by: the promo's value, the subtotal (can't
    // discount more than the order is worth), and the per-promo cap.
    return Math.min(promo.discount_value, subtotal, perPromoCap);
  }

  // Percentage discount, capped at perPromoCap.
  const calculated =
    Math.round(subtotal * (promo.discount_value / 100) * 100) / 100;
  return Math.min(calculated, perPromoCap);
}
