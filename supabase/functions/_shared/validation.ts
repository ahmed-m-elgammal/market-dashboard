// Input validation for Edge Functions
// Per security spec (doc 21): "All inputs validated via Zod schema before processing"
// Per API contract (doc 16): Detailed validation rules for each endpoint
//
// This module provides runtime validation functions for all Edge Function inputs.
// Uses manual validation instead of Zod to avoid dependency issues in Deno Edge Functions
// (Zod's ESM build has compatibility issues with Deno's module resolution).
// The validation logic is equivalent to the Zod schemas defined in packages/shared/schemas.

import { luhnIsValid } from './luhn.ts';

export interface ValidationError {
  field: string;
  message: string;
}

export interface ValidationResult {
  valid: boolean;
  errors: ValidationError[];
}

function fail(field: string, message: string): ValidationResult {
  return { valid: false, errors: [{ field, message }] };
}

function ok(): ValidationResult {
  return { valid: true, errors: [] };
}

// ============================================================
// Common validators
// ============================================================

export function validateUUID(value: unknown, field: string): ValidationResult {
  if (typeof value !== 'string' || !value) return fail(field, `${field} is required`);
  const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (!uuidRegex.test(value)) return fail(field, `${field} must be a valid UUID`);
  return ok();
}

export function validatePositiveNumber(value: unknown, field: string, min = 0): ValidationResult {
  if (typeof value !== 'number' || isNaN(value)) return fail(field, `${field} must be a number`);
  if (value < min) return fail(field, `${field} must be >= ${min}`);
  return ok();
}

export function validateCoordinates(lat: unknown, lng: unknown): ValidationResult {
  const errors: ValidationError[] = [];
  if (typeof lat !== 'number' || isNaN(lat) || lat < -90 || lat > 90) {
    errors.push({ field: 'lat', message: 'Latitude must be a number between -90 and 90' });
  }
  if (typeof lng !== 'number' || isNaN(lng) || lng < -180 || lng > 180) {
    errors.push({ field: 'lng', message: 'Longitude must be a number between -180 and 180' });
  }
  return errors.length > 0 ? { valid: false, errors } : ok();
}

export function validateString(
  value: unknown,
  field: string,
  opts: { min?: number; max?: number; required?: boolean } = {},
): ValidationResult {
  const { min = 0, max = Infinity, required = true } = opts;
  if (typeof value !== 'string') {
    return required ? fail(field, `${field} must be a string`) : ok();
  }
  if (required && value.trim().length === 0) return fail(field, `${field} is required`);
  if (value.length < min) return fail(field, `${field} must be at least ${min} characters`);
  if (value.length > max) return fail(field, `${field} must be at most ${max} characters`);
  return ok();
}

export function validateEnum(value: unknown, field: string, allowed: string[]): ValidationResult {
  if (typeof value !== 'string' || !allowed.includes(value)) {
    return fail(field, `${field} must be one of: ${allowed.join(', ')}`);
  }
  return ok();
}

// Seeded merchant category codes — mirrors the merchant_categories lookup
// table (migration 097) and MERCHANT_CATEGORIES in packages/shared/src/constants.
// Keep in sync when a new code is seeded. (The feed/search validators used to
// hardcode ['restaurant','pharmacy','grocery'] while the DB CHECK only allowed
// two values — a 'grocery' request silently returned an empty feed.)
export const MERCHANT_CATEGORY_CODES = [
  'restaurant',
  'pharmacy',
  'market',
  'grocery',
  'bakery',
  'butcher',
  'flowers',
  'other',
] as const;

export function validateEgyptianPhone(value: unknown): ValidationResult {
  if (typeof value !== 'string') return fail('phone', 'Phone must be a string');
  // Egyptian phone: +20XXXXXXXXX (10 digits after +20)
  const phoneRegex = /^\+20[0-9]{10}$/;
  if (!phoneRegex.test(value)) return fail('phone', 'Phone must match +20XXXXXXXXX format');
  return ok();
}

/**
 * Coerce the Egyptian mobile formats an operator actually pastes into the one
 * canonical form the column is validated against.
 *
 * WHY THIS EXISTS
 *   validateEgyptianPhone accepts only `+20XXXXXXXXX`. An operator copying from
 *   a business card, a WhatsApp contact or a Maps listing produces `01001234567`,
 *   `+20 100 123 4567`, `0020 1001234567` or `1001234567` — all the same number,
 *   all rejected by a regex that is otherwise correct. Failing those is not
 *   validation, it is the "this form is hard" complaint in disguise.
 *
 *   Normalising here rather than in the browser means the rule is enforced in one
 *   place and cannot be bypassed by a direct call.
 *
 *   Returns null when the input is not recognisably an Egyptian mobile, so the
 *   caller can fall back to its own error rather than writing a mangled value.
 *   Landlines are deliberately not handled: the column's convention is mobile
 *   and silently coercing a landline would be worse than refusing it.
 */
export function normalizeEgyptianPhone(value: unknown): string | null {
  if (typeof value !== 'string') return null;

  // Strip everything that is not a digit or a leading plus, then drop formatting.
  const raw = value.trim();
  const digits = raw.replace(/[^\d]/g, '');

  let local = digits;
  if (digits.startsWith('0020')) local = digits.slice(4);
  else if (digits.startsWith('20') && digits.length === 12) local = digits.slice(2);

  // 010XXXXXXXX / 011XXXXXXXX -> the 10 digits after the national prefix.
  if (local.startsWith('0') && local.length === 11) local = local.slice(1);

  if (local.length !== 10 || !/^[0-9]{10}$/.test(local)) return null;

  // Mobile network prefixes are 010 / 011 / 012 / 015. Rejecting anything else
  // catches a mistyped digit rather than storing an unreachable number.
  if (!/^(010|011|012|015)/.test(local)) return null;

  return `+20${local}`;
}

export function validateEgyptianNationalId(value: unknown): ValidationResult {
  if (typeof value !== 'string') return fail('national_id', 'National ID must be a string');
  if (value.length !== 14) return fail('national_id', 'National ID must be 14 digits');
  if (!/^\d{14}$/.test(value)) return fail('national_id', 'National ID must contain only digits');
  // Luhn checksum — Egyptian national IDs end with a check digit computed
  // via Luhn over the first 13 digits. Rejects well-formed but fabricated
  // IDs (the previous implementation returned ok() for any 14-digit string).
  if (!luhnIsValid(value)) {
    return fail('national_id', 'National ID checksum is invalid');
  }
  return ok();
}

export function validateEgyptianPlate(value: unknown): ValidationResult {
  if (typeof value !== 'string') return fail('vehicle_plate', 'Vehicle plate must be a string');
  // Egyptian plate format: numbers + Arabic letters + numbers (e.g., "123 أ ب 45")
  // Simplified check: at least 2 characters
  if (value.trim().length < 2) return fail('vehicle_plate', 'Invalid vehicle plate format');
  return ok();
}

// ============================================================
// Request body validators per Edge Function
// ============================================================

const PAYMENT_METHODS = ['cash', 'card', 'vodafone_cash', 'instapay', 'orange_cash', 'wallet'] as const;
const DIGITAL_METHODS = ['card', 'vodafone_cash', 'instapay', 'orange_cash', 'wallet'] as const;

/**
 * Validate place-order request body.
 */
export function validatePlaceOrderRequest(body: unknown): ValidationResult {
  if (!body || typeof body !== 'object') return fail('body', 'Request body is required');
  const b = body as Record<string, unknown>;
  const errors: ValidationError[] = [];

  // merchant_id
  const merchantIdResult = validateUUID(b.merchant_id, 'merchant_id');
  if (!merchantIdResult.valid) errors.push(...merchantIdResult.errors);

  // items
  if (!Array.isArray(b.items) || b.items.length === 0) {
    errors.push({ field: 'items', message: 'Items must be a non-empty array' });
  } else if (b.items.length > 50) {
    errors.push({ field: 'items', message: 'Maximum 50 items per order' });
  } else {
    for (let i = 0; i < b.items.length; i++) {
      const item = b.items[i] as Record<string, unknown>;
      const itemPrefix = `items[${i}]`;

      const itemIdResult = validateUUID(item?.item_id, `${itemPrefix}.item_id`);
      if (!itemIdResult.valid) errors.push(...itemIdResult.errors);

      if (typeof item?.quantity !== 'number' || item.quantity < 1 || item.quantity > 99 || !Number.isInteger(item.quantity)) {
        errors.push({ field: `${itemPrefix}.quantity`, message: 'Quantity must be an integer between 1 and 99' });
      }
    }
  }

  // delivery_address
  if (!b.delivery_address || typeof b.delivery_address !== 'object') {
    errors.push({ field: 'delivery_address', message: 'delivery_address is required' });
  } else {
    const addr = b.delivery_address as Record<string, unknown>;
    const coordResult = validateCoordinates(addr.lat, addr.lng);
    if (!coordResult.valid) errors.push(...coordResult.errors);
    const addrTextResult = validateString(addr.address, 'delivery_address.address', { max: 500 });
    if (!addrTextResult.valid) errors.push(...addrTextResult.errors);
  }

  // payment_method
  const paymentResult = validateEnum(b.payment_method, 'payment_method', [...PAYMENT_METHODS]);
  if (!paymentResult.valid) errors.push(...paymentResult.errors);

  // promo_code (optional)
  if (b.promo_code !== undefined && b.promo_code !== null) {
    const promoResult = validateString(b.promo_code, 'promo_code', { min: 1, max: 50, required: false });
    if (!promoResult.valid) errors.push(...promoResult.errors);
  }

  // notes (optional)
  if (b.notes !== undefined && b.notes !== null) {
    const notesResult = validateString(b.notes, 'notes', { max: 500, required: false });
    if (!notesResult.valid) errors.push(...notesResult.errors);
  }

  // scheduled_time (optional, ISO-8601). Sprint 0 fix (D04).
  if (b.scheduled_time !== undefined && b.scheduled_time !== null) {
    if (typeof b.scheduled_time !== 'string') {
      errors.push({ field: 'scheduled_time', message: 'scheduled_time must be an ISO-8601 string' });
    } else {
      const ts = Date.parse(b.scheduled_time);
      if (Number.isNaN(ts)) {
        errors.push({ field: 'scheduled_time', message: 'scheduled_time must be a valid ISO-8601 datetime' });
      } else if (ts <= Date.now()) {
        errors.push({ field: 'scheduled_time', message: 'scheduled_time must be in the future' });
      }
    }
  }

  return errors.length > 0 ? { valid: false, errors } : ok();
}

/**
 * Validate get-merchant-feed request body.
 */
export function validateMerchantFeedRequest(body: unknown): ValidationResult {
  if (!body || typeof body !== 'object') return fail('body', 'Request body is required');
  const b = body as Record<string, unknown>;
  const errors: ValidationError[] = [];

  const cityResult = validateString(b.city, 'city', { min: 1, max: 50 });
  if (!cityResult.valid) errors.push(...cityResult.errors);

  if (b.category !== undefined && b.category !== 'all') {
    const catResult = validateEnum(b.category, 'category', ['all', ...MERCHANT_CATEGORY_CODES]);
    if (!catResult.valid) errors.push(...catResult.errors);
  }

  if (b.lat !== undefined || b.lng !== undefined) {
    const coordResult = validateCoordinates(b.lat, b.lng);
    if (!coordResult.valid) errors.push(...coordResult.errors);
  }

  if (b.limit !== undefined) {
    if (typeof b.limit !== 'number' || b.limit < 1 || b.limit > 50) {
      errors.push({ field: 'limit', message: 'Limit must be between 1 and 50' });
    }
  }

  return errors.length > 0 ? { valid: false, errors } : ok();
}

/**
 * Validate search-catalog request body (Search & Discovery MVP).
 * Query rules (plan §7.1-2): trim; 2..80 chars; at least one letter/digit in
 * ANY script (Unicode property escapes — rejects emoji-only and symbol-only
 * input); C0/C1 control characters rejected outright.
 */
export function validateSearchRequest(body: unknown): ValidationResult {
  if (!body || typeof body !== 'object') return fail('body', 'Request body is required');
  const b = body as Record<string, unknown>;
  const errors: ValidationError[] = [];

  // query — required
  if (typeof b.query !== 'string') {
    errors.push({ field: 'query', message: 'query must be a string' });
  } else {
    const q = b.query.trim();
    if (q.length < 2) {
      errors.push({ field: 'query', message: 'query must be at least 2 characters' });
    } else if (q.length > 80) {
      errors.push({ field: 'query', message: 'query must be at most 80 characters' });
    } else if (/[\u0000-\u001F\u007F]/.test(q)) {
      errors.push({ field: 'query', message: 'query contains control characters' });
    } else if (!/[\p{L}\p{N}]/u.test(q)) {
      errors.push({ field: 'query', message: 'query must contain at least one letter or digit' });
    }
  }

  // city — optional
  if (b.city !== undefined && b.city !== null) {
    const cityResult = validateString(b.city, 'city', { min: 1, max: 50 });
    if (!cityResult.valid) errors.push(...cityResult.errors);
  }

  // category — optional (mirrors the feed validator's allowed list)
  if (b.category !== undefined && b.category !== 'all') {
    const catResult = validateEnum(b.category, 'category', ['all', ...MERCHANT_CATEGORY_CODES]);
    if (!catResult.valid) errors.push(...catResult.errors);
  }

  // lat/lng — optional pair
  if (b.lat !== undefined || b.lng !== undefined) {
    const coordResult = validateCoordinates(b.lat, b.lng);
    if (!coordResult.valid) errors.push(...coordResult.errors);
  }

  // limit — optional
  if (b.limit !== undefined) {
    if (typeof b.limit !== 'number' || b.limit < 1 || b.limit > 30) {
      errors.push({ field: 'limit', message: 'Limit must be between 1 and 30' });
    }
  }

  // mode — optional
  if (b.mode !== undefined) {
    const modeResult = validateEnum(b.mode, 'mode', ['all', 'merchants', 'items']);
    if (!modeResult.valid) errors.push(...modeResult.errors);
  }

  // merchant_id — optional (reserved for in-merchant search)
  if (b.merchant_id !== undefined && b.merchant_id !== null) {
    const merchantResult = validateUUID(b.merchant_id, 'merchant_id');
    if (!merchantResult.valid) errors.push(...merchantResult.errors);
  }

  // include_suggestions — optional
  if (b.include_suggestions !== undefined && typeof b.include_suggestions !== 'boolean') {
    errors.push({ field: 'include_suggestions', message: 'include_suggestions must be a boolean' });
  }

  return errors.length > 0 ? { valid: false, errors } : ok();
}

/**
 * Validate get-order-fee-preview request body.
 */
export function validateFeePreviewRequest(body: unknown): ValidationResult {
  if (!body || typeof body !== 'object') return fail('body', 'Request body is required');
  const b = body as Record<string, unknown>;
  const errors: ValidationError[] = [];

  const merchantIdResult = validateUUID(b.merchant_id, 'merchant_id');
  if (!merchantIdResult.valid) errors.push(...merchantIdResult.errors);

  const coordResult = validateCoordinates(b.delivery_lat, b.delivery_lng);
  if (!coordResult.valid) errors.push(...coordResult.errors);

  const subtotalResult = validatePositiveNumber(b.subtotal, 'subtotal', 0);
  if (!subtotalResult.valid) errors.push(...subtotalResult.errors);

  return errors.length > 0 ? { valid: false, errors } : ok();
}

/**
 * Validate validate-promo request body.
 */
export function validatePromoRequest(body: unknown): ValidationResult {
  if (!body || typeof body !== 'object') return fail('body', 'Request body is required');
  const b = body as Record<string, unknown>;
  const errors: ValidationError[] = [];

  const codeResult = validateString(b.code, 'code', { min: 1, max: 50 });
  if (!codeResult.valid) errors.push(...codeResult.errors);

  const merchantIdResult = validateUUID(b.merchant_id, 'merchant_id');
  if (!merchantIdResult.valid) errors.push(...merchantIdResult.errors);

  const subtotalResult = validatePositiveNumber(b.subtotal, 'subtotal', 0);
  if (!subtotalResult.valid) errors.push(...subtotalResult.errors);

  return errors.length > 0 ? { valid: false, errors } : ok();
}

/**
 * Validate driver-actions request body.
 */
export function validateDriverActionsRequest(body: unknown): ValidationResult {
  if (!body || typeof body !== 'object') return fail('body', 'Request body is required');
  const b = body as Record<string, unknown>;
  const action = b.action as string;

  const actionResult = validateEnum(action, 'action', ['assign', 'respond', 'update_location', 'complete_delivery', 'mark_picked_up', 'mark_on_the_way']);
  if (!actionResult.valid) return actionResult;

  const errors: ValidationError[] = [];

  switch (action) {
    case 'assign': {
      const orderIdResult = validateUUID(b.order_id, 'order_id');
      if (!orderIdResult.valid) errors.push(...orderIdResult.errors);
      const coordResult = validateCoordinates(b.merchant_lat, b.merchant_lng);
      if (!coordResult.valid) errors.push(...coordResult.errors);
      if (b.max_radius_km !== undefined) {
        const radiusResult = validatePositiveNumber(b.max_radius_km, 'max_radius_km', 1);
        if (!radiusResult.valid) errors.push(...radiusResult.errors);
        if (typeof b.max_radius_km === 'number' && b.max_radius_km > 10) {
          errors.push({ field: 'max_radius_km', message: 'Maximum radius is 10km' });
        }
      }
      break;
    }
    case 'respond': {
      const orderIdResult = validateUUID(b.order_id, 'order_id');
      if (!orderIdResult.valid) errors.push(...orderIdResult.errors);
      const actionResult2 = validateEnum(b.driver_action, 'driver_action', ['accept', 'decline']);
      if (!actionResult2.valid) errors.push(...actionResult2.errors);
      break;
    }
    case 'update_location': {
      const coordResult = validateCoordinates(b.lat, b.lng);
      if (!coordResult.valid) errors.push(...coordResult.errors);
      if (b.accuracy !== undefined) {
        const accResult = validatePositiveNumber(b.accuracy, 'accuracy', 0);
        if (!accResult.valid) errors.push(...accResult.errors);
      }
      break;
    }
    case 'complete_delivery': {
      const orderIdResult = validateUUID(b.order_id, 'order_id');
      if (!orderIdResult.valid) errors.push(...orderIdResult.errors);
      break;
    }
    case 'mark_picked_up':
    case 'mark_on_the_way': {
      const orderIdResult = validateUUID(b.order_id, 'order_id');
      if (!orderIdResult.valid) errors.push(...orderIdResult.errors);
      break;
    }
  }

  return errors.length > 0 ? { valid: false, errors } : ok();
}

/**
 * Validate admin-driver request body.
 */
export function validateAdminDriverRequest(body: unknown): ValidationResult {
  if (!body || typeof body !== 'object') return fail('body', 'Request body is required');
  const b = body as Record<string, unknown>;
  const action = b.action as string;

  const actionResult = validateEnum(action, 'action', ['create', 'review', 'deactivate']);
  if (!actionResult.valid) return actionResult;

  const errors: ValidationError[] = [];

  switch (action) {
    case 'create': {
      const emailResult = validateString(b.email, 'email', { min: 1, max: 255 });
      if (!emailResult.valid) errors.push(...emailResult.errors);
      else if (typeof b.email === 'string' && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(b.email)) {
        errors.push({ field: 'email', message: 'Invalid email format' });
      }
      const phoneResult = validateEgyptianPhone(b.phone);
      if (!phoneResult.valid) errors.push(...phoneResult.errors);
      const nameResult = validateString(b.full_name, 'full_name', { min: 2, max: 100 });
      if (!nameResult.valid) errors.push(...nameResult.errors);
      const nationalIdResult = validateEgyptianNationalId(b.national_id);
      if (!nationalIdResult.valid) errors.push(...nationalIdResult.errors);
      const vehicleTypeResult = validateEnum(b.vehicle_type, 'vehicle_type', ['motorcycle', 'car', 'bicycle']);
      if (!vehicleTypeResult.valid) errors.push(...vehicleTypeResult.errors);
      const plateResult = validateEgyptianPlate(b.vehicle_plate);
      if (!plateResult.valid) errors.push(...plateResult.errors);
      break;
    }
    case 'review': {
      const driverIdResult = validateUUID(b.driver_id, 'driver_id');
      if (!driverIdResult.valid) errors.push(...driverIdResult.errors);
      const reviewActionResult = validateEnum(b.review_action, 'review_action', ['approve', 'reject']);
      if (!reviewActionResult.valid) errors.push(...reviewActionResult.errors);
      if (b.review_action === 'reject' && !b.rejection_reason) {
        errors.push({ field: 'rejection_reason', message: 'Rejection reason is required when rejecting' });
      }
      break;
    }
    case 'deactivate': {
      const driverIdResult = validateUUID(b.driver_id, 'driver_id');
      if (!driverIdResult.valid) errors.push(...driverIdResult.errors);
      const reasonResult = validateEnum(b.reason, 'reason', ['safety_violation', 'fraud', 'driver_request', 'vehicle_issues', 'other']);
      if (!reasonResult.valid) errors.push(...reasonResult.errors);
      if (b.details !== undefined && b.details !== null) {
        const detailsResult = validateString(b.details, 'details', { max: 500, required: false });
        if (!detailsResult.valid) errors.push(...detailsResult.errors);
      }
      break;
    }
  }

  return errors.length > 0 ? { valid: false, errors } : ok();
}

/**
 * Validate send-notification request body.
 */
export function validateSendNotificationRequest(body: unknown): ValidationResult {
  if (!body || typeof body !== 'object') return fail('body', 'Request body is required');
  const b = body as Record<string, unknown>;
  const errors: ValidationError[] = [];

  if (b.broadcast !== true) {
    const userIdResult = validateUUID(b.user_id, 'user_id');
    if (!userIdResult.valid) errors.push(...userIdResult.errors);
  }

  const titleEnResult = validateString(b.title_en, 'title_en', { min: 1, max: 200 });
  if (!titleEnResult.valid) errors.push(...titleEnResult.errors);

  const bodyEnResult = validateString(b.body_en, 'body_en', { min: 1, max: 500 });
  if (!bodyEnResult.valid) errors.push(...bodyEnResult.errors);

  // Must match the DB CHECK constraint on notifications.type
  // (migration 013_create_notifications.sql). Sprint 0 fix (D01/D02):
  // previous list included values that don't exist in the DB, causing every
  // notification insert to fail silently.
  const typeResult = validateEnum(b.type, 'type', [
    'order_status',
    'order_assigned',
    'order_delivered',
    'order_cancelled',
    'promo',
    'driver_verified',
    'driver_rejected',
    'driver_deactivated',
    'driver_request',
    'review_request',
    'wallet',
    'general',
  ]);
  if (!typeResult.valid) errors.push(...typeResult.errors);

  if (b.reference_id !== undefined && b.reference_id !== null) {
    const refResult = validateUUID(b.reference_id, 'reference_id');
    if (!refResult.valid) errors.push(...refResult.errors);
  }

  return errors.length > 0 ? { valid: false, errors } : ok();
}

/**
 * Validate an admin-api merchant create/update body.
 *
 * WHY THIS IS SHAPED AROUND "ONLY WHAT IS REQUIRED"
 *   The operator's complaint about merchant entry is effort, and almost all of
 *   it is optional. merchants gives every tuning column either a DEFAULT or a
 *   NULL (schema-final.sql:9231-9245), so the create path deliberately validates
 *   ONLY the columns with no default — the 8 identity fields. Anything omitted
 *   falls through to the database default, which produces exactly the row the
 *   column's own default was written to produce.
 *
 *   That is what lets the UI collapse the rest behind an "Advanced" panel
 *   without changing what gets stored.
 *
 * The two state columns (`approval_status`, `is_active`) are validated nowhere
 * here and set by the handler instead: a client that could choose them would be
 * able to publish an unreviewed merchant, which is the entire thing this
 * endpoint exists to prevent.
 */
export function validateAdminMerchantRequest(body: unknown): ValidationResult {
  const errors: ValidationError[] = [];
  const b = (body ?? {}) as Record<string, unknown>;

  // The 8 NOT NULL columns with no default (schema-final.sql:9220-9232).
  errors.push(...validateString(b.name_en, 'name_en', { min: 1, max: 200 }).errors);
  errors.push(...validateString(b.name_ar, 'name_ar', { min: 1, max: 200 }).errors);
  errors.push(...validateEnum(b.category, 'category', [...MERCHANT_CATEGORY_CODES]).errors);
  errors.push(...validateString(b.address, 'address', { min: 1, max: 300 }).errors);
  errors.push(...validateString(b.city, 'city', { min: 1, max: 100 }).errors);

  // Phone: normalised rather than pattern-matched, so every format an operator
  // can realistically paste is accepted and stored canonically.
  if (normalizeEgyptianPhone(b.phone) === null) {
    errors.push(...fail('phone', 'Phone must be an Egyptian mobile number').errors);
  }

  // lat/lng are NOT NULL in the database. They were NOT NULL in the first draft
  // of the dashboard form and the form did not require them, which produced an
  // opaque not_null_violation on submit; requiring them here means the failure
  // is a named field error instead.
  errors.push(...validateCoordinates(b.lat, b.lng).errors);

  // Nullable columns, validated only when present.
  errors.push(...validateString(b.area, 'area', { max: 100, required: false }).errors);
  errors.push(
    ...validateString(b.description_en, 'description_en', { max: 1000, required: false }).errors,
  );
  errors.push(
    ...validateString(b.description_ar, 'description_ar', { max: 1000, required: false }).errors,
  );
  errors.push(...validateString(b.logo_url, 'logo_url', { max: 500, required: false }).errors);
  errors.push(...validateString(b.cover_url, 'cover_url', { max: 500, required: false }).errors);

  // Optional numeric columns. The `min` values mirror the DB CHECK constraints
  // exactly (schema-final.sql:9250-9255) so the function rejects them with a
  // named error instead of letting Postgres raise a constraint violation that
  // the client can only see as INTERNAL_ERROR.
  const optionalNumbers: [string, number, number][] = [
    // commission_pct: CHECK (NULL OR 0..100)
    ['commission_pct', 0, 100],
    // min_order_amount: CHECK (>= 0)
    ['min_order_amount', 0, Infinity],
    // delivery_fee_override: CHECK (NULL OR >= 0)
    ['delivery_fee_override', 0, Infinity],
    // delivery_radius_km: CHECK (> 0)
    ['delivery_radius_km', Number.MIN_VALUE, Infinity],
    // estimated_delivery_minutes: CHECK (> 0)
    ['estimated_delivery_minutes', Number.MIN_VALUE, Infinity],
    // estimated_prep_time_minutes: CHECK (> 0)
    ['estimated_prep_time_minutes', Number.MIN_VALUE, Infinity],
  ];

  for (const [field, min, max] of optionalNumbers) {
    const value = b[field];
    if (value === undefined || value === null) continue;
    const n = Number(value);
    if (!Number.isFinite(n)) {
      errors.push(...fail(field, `${field} must be a number`).errors);
    } else if (n < min || n > max) {
      errors.push(...fail(field, `${field} must be between ${min} and ${max}`).errors);
    }
  }

  if (b.payout_frequency !== undefined && b.payout_frequency !== null) {
    errors.push(
      ...validateEnum(b.payout_frequency, 'payout_frequency', ['daily', 'weekly', 'monthly'])
        .errors,
    );
  }

  if (b.payout_method !== undefined && b.payout_method !== null) {
    errors.push(
      ...validateEnum(b.payout_method, 'payout_method', [
        'bank_transfer',
        'wallet',
        'cash',
        'instapay',
      ]).errors,
    );
  }

  return errors.length > 0 ? { valid: false, errors } : ok();
}

/**
 * Maximum request body size (1MB).
 * Prevents oversized payloads from consuming memory.
 */
export const MAX_REQUEST_SIZE = 1024 * 1024; // 1MB

/**
 * Validate request body size from Content-Length header.
 */
export function validateRequestSize(req: Request): ValidationResult {
  const contentLength = req.headers.get('Content-Length');
  if (contentLength && parseInt(contentLength, 10) > MAX_REQUEST_SIZE) {
    return fail('body', `Request body too large. Maximum size is ${MAX_REQUEST_SIZE / 1024 / 1024}MB`);
  }
  return ok();
}

/**
 * Format validation errors into a single error message.
 */
export function formatValidationErrors(errors: ValidationError[]): string {
  return errors.map((e) => `${e.field}: ${e.message}`).join('; ');
}
