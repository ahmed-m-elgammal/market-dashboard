// Standardized error response builder for Edge Functions
// Follows the API contract: { success: false, error: { code, message_en, message_ar, severity } }

export interface ApiError {
  code: string;
  message_en: string;
  message_ar: string;
  severity: 'info' | 'warning' | 'error';
}

export interface ErrorResponse {
  success: false;
  error: ApiError;
}

export interface SuccessResponse<T> {
  success: true;
  data: T;
}

export type ApiResponse<T> = SuccessResponse<T> | ErrorResponse;

const ERROR_DEFINITIONS: Record<string, ApiError> = {
  // Auth
  UNAUTHORIZED: { code: 'UNAUTHORIZED', message_en: 'Authentication required', message_ar: 'يجب تسجيل الدخول', severity: 'error' },
  INVALID_TOKEN: { code: 'INVALID_TOKEN', message_en: 'Invalid or expired token', message_ar: 'الرمز غير صالح أو منتهي الصلاحية', severity: 'error' },
  FORBIDDEN: { code: 'FORBIDDEN', message_en: 'You do not have permission', message_ar: 'ليس لديك صلاحية', severity: 'error' },
  NOT_ADMIN: { code: 'NOT_ADMIN', message_en: 'Only admins can perform this action', message_ar: 'فقط المسؤول يمكنه تنفيذ هذا الإجراء', severity: 'error' },
  NOT_CUSTOMER: { code: 'NOT_CUSTOMER', message_en: 'Only customers can perform this action', message_ar: 'فقط العملاء يمكنهم تنفيذ هذا الإجراء', severity: 'error' },
  NOT_DRIVER: { code: 'NOT_DRIVER', message_en: 'Only drivers can perform this action', message_ar: 'فقط السائقون يمكنهم تنفيذ هذا الإجراء', severity: 'error' },
  DRIVER_NOT_VERIFIED: { code: 'DRIVER_NOT_VERIFIED', message_en: 'Your account is pending verification', message_ar: 'حسابك قيد التحقق', severity: 'warning' },
  DRIVER_NOT_ACTIVE: { code: 'DRIVER_NOT_ACTIVE', message_en: 'Your account is not active', message_ar: 'حسابك غير نشط', severity: 'warning' },

  // Merchant
  MERCHANT_NOT_FOUND: { code: 'MERCHANT_NOT_FOUND', message_en: 'Merchant not found', message_ar: 'التاجر غير موجود', severity: 'error' },
  MERCHANT_CLOSED: { code: 'MERCHANT_CLOSED', message_en: 'This merchant is currently closed', message_ar: 'هذا التاجر مغلق حالياً', severity: 'error' },
  MERCHANT_INACTIVE: { code: 'MERCHANT_INACTIVE', message_en: 'This merchant is no longer available', message_ar: 'هذا التاجر لم يعد متاحاً', severity: 'error' },

  // Merchant onboarding / approval state machine (admin-api writes).
  //
  // These exist because `approval_status` and `is_active` are two independent
  // columns and every illegal pair has to be refused explicitly. `getError`
  // falls back to INTERNAL_ERROR for an unknown code, so omitting one silently
  // loses both the bilingual copy and the status mapping below.
  MERCHANT_NOT_APPROVED: {
    code: 'MERCHANT_NOT_APPROVED',
    message_en: 'Approve this merchant before publishing it',
    message_ar: 'يجب اعتماد هذا التاجر قبل نشره',
    severity: 'warning',
  },
  MERCHANT_ALREADY_APPROVED: {
    code: 'MERCHANT_ALREADY_APPROVED',
    message_en: 'This merchant is already approved',
    message_ar: 'هذا التاجر معتمد بالفعل',
    severity: 'info',
  },
  MERCHANT_ALREADY_ACTIVE: {
    code: 'MERCHANT_ALREADY_ACTIVE',
    message_en: 'This merchant is already published',
    message_ar: 'هذا التاجر منشور بالفعل',
    severity: 'info',
  },
  MERCHANT_ALREADY_INACTIVE: {
    code: 'MERCHANT_ALREADY_INACTIVE',
    message_en: 'This merchant is not currently published',
    message_ar: 'هذا التاجر غير منشور حالياً',
    severity: 'info',
  },
  APPROVAL_NOTE_REQUIRED: {
    code: 'APPROVAL_NOTE_REQUIRED',
    message_en: 'A reason is required when rejecting a merchant',
    message_ar: 'سبب الرفض مطلوب عند رفض التاجر',
    severity: 'warning',
  },

  // Items
  ITEM_UNAVAILABLE: { code: 'ITEM_UNAVAILABLE', message_en: 'One or more items are unavailable', message_ar: 'عنصر أو أكثر غير متاح', severity: 'warning' },
  ITEM_MISMATCH: { code: 'ITEM_MISMATCH', message_en: 'Item does not belong to this merchant', message_ar: 'العنصر لا ينتمي لهذا التاجر', severity: 'error' },

  // Delivery
  OUT_OF_DELIVERY_RANGE: { code: 'OUT_OF_DELIVERY_RANGE', message_en: 'Your address is outside the delivery zone', message_ar: 'عنوانك خارج نطاق التوصيل', severity: 'error' },
  BELOW_MIN_ORDER: { code: 'BELOW_MIN_ORDER', message_en: 'Order total is below the minimum', message_ar: 'إجمالي الطلب أقل من الحد الأدنى', severity: 'warning' },

  // Orders
  DUPLICATE_ORDER: { code: 'DUPLICATE_ORDER', message_en: 'A similar order was just placed', message_ar: 'تم تقديم طلب مشابه للتو', severity: 'warning' },
  ORDER_NOT_FOUND: { code: 'ORDER_NOT_FOUND', message_en: 'Order not found', message_ar: 'الطلب غير موجود', severity: 'error' },
  ORDER_NOT_ASSIGNED_TO_YOU: { code: 'ORDER_NOT_ASSIGNED_TO_YOU', message_en: 'This order was not assigned to you', message_ar: 'لم يتم تعيين هذا الطلب لك', severity: 'error' },
  ORDER_ALREADY_TAKEN: { code: 'ORDER_ALREADY_TAKEN', message_en: 'Another driver already accepted this order', message_ar: 'سائق آخر قبل هذا الطلب بالفعل', severity: 'warning' },
  ORDER_INVALID_STATUS: { code: 'ORDER_INVALID_STATUS', message_en: 'Order is not in the expected status', message_ar: 'الطلب ليس في الحالة المتوقعة', severity: 'error' },

  // Promo
  PROMO_INVALID: { code: 'PROMO_INVALID', message_en: 'Invalid promo code', message_ar: 'كود الخصم غير صالح', severity: 'warning' },
  PROMO_EXPIRED: { code: 'PROMO_EXPIRED', message_en: 'This promo code has expired', message_ar: 'انتهت صلاحية كود الخصم', severity: 'warning' },
  PROMO_MAX_USES: { code: 'PROMO_MAX_USES', message_en: 'This promo code has reached its usage limit', message_ar: 'وصل كود الخصم للحد الأقصى للاستخدام', severity: 'warning' },
  PROMO_MAX_USES_PER_USER: { code: 'PROMO_MAX_USES_PER_USER', message_en: 'You have already used this promo code the maximum number of times', message_ar: 'لقد استخدمت كود الخصم هذا الحد الأقصى من المرات', severity: 'warning' },
  PROMO_MERCHANT_MISMATCH: { code: 'PROMO_MERCHANT_MISMATCH', message_en: 'This promo code is not valid for this merchant', message_ar: 'كود الخصم غير صالح لهذا التاجر', severity: 'warning' },
  PROMO_BELOW_MIN: { code: 'PROMO_BELOW_MIN', message_en: 'Your order total is below the minimum for this promo', message_ar: 'إجمالي طلبك أقل من الحد الأدنى لهذا الكود', severity: 'warning' },
  PROMO_INACTIVE: { code: 'PROMO_INACTIVE', message_en: 'This promo code is no longer active', message_ar: 'كود الخصم لم يعد نشطاً', severity: 'warning' },

  // Driver
  DRIVER_NOT_FOUND: { code: 'DRIVER_NOT_FOUND', message_en: 'Driver not found', message_ar: 'السائق غير موجود', severity: 'error' },
  NO_DRIVER_AVAILABLE: { code: 'NO_DRIVER_AVAILABLE', message_en: 'No drivers available right now', message_ar: 'لا يوجد سائقون متاحون الآن', severity: 'warning' },
  ALREADY_DEACTIVATED: { code: 'ALREADY_DEACTIVATED', message_en: 'This driver is already deactivated', message_ar: 'هذا السائق معطل بالفعل', severity: 'info' },

  // Admin
  EMAIL_EXISTS: { code: 'EMAIL_EXISTS', message_en: 'A user with this email already exists', message_ar: 'يوجد مستخدم بهذا البريد الإلكتروني بالفعل', severity: 'error' },
  NATIONAL_ID_EXISTS: { code: 'NATIONAL_ID_EXISTS', message_en: 'A driver with this national ID already exists', message_ar: 'يوجد سائق بهذا الرقم القومي بالفعل', severity: 'error' },
  PLATE_EXISTS: { code: 'PLATE_EXISTS', message_en: 'A driver with this vehicle plate already exists', message_ar: 'يوجد سائق بهذه اللوحة بالفعل', severity: 'error' },

  // Payment
  PAYMENT_INIT_FAILED: { code: 'PAYMENT_INIT_FAILED', message_en: 'Could not initiate payment', message_ar: 'تعذر بدء الدفع', severity: 'error' },
  PAYMENT_FAILED: { code: 'PAYMENT_FAILED', message_en: 'Payment failed', message_ar: 'فشل الدفع', severity: 'error' },
  HMAC_INVALID: { code: 'HMAC_INVALID', message_en: 'Invalid webhook signature', message_ar: 'توقيع ويب هوك غير صالح', severity: 'error' },
  PAYMENT_METHOD_UNAVAILABLE: { code: 'PAYMENT_METHOD_UNAVAILABLE', message_en: 'This payment method is not available yet', message_ar: 'طريقة الدفع هذه غير متاحة بعد', severity: 'warning' },

  // Rate limiting
  RATE_LIMITED: { code: 'RATE_LIMITED', message_en: 'Too many requests. Please try again later.', message_ar: 'طلبات كثيرة. يرجى المحاولة لاحقاً.', severity: 'warning' },

  // Generic
  VALIDATION_ERROR: { code: 'VALIDATION_ERROR', message_en: 'Invalid input data', message_ar: 'بيانات الإدخال غير صالحة', severity: 'warning' },
  INTERNAL_ERROR: { code: 'INTERNAL_ERROR', message_en: 'Something went wrong', message_ar: 'حدث خطأ ما', severity: 'error' },
};

export function getError(code: string, overrides?: Partial<ApiError>): ApiError {
  const base = ERROR_DEFINITIONS[code] || ERROR_DEFINITIONS.INTERNAL_ERROR;
  return { ...base, ...overrides };
}

export function errorResponse(code: string, overrides?: Partial<ApiError>, status = 400): ErrorResponse {
  return { success: false, error: getError(code, overrides) };
}

export function successResponse<T>(data: T): SuccessResponse<T> {
  return { success: true, data };
}

// Get HTTP status for error code
export function errorStatus(code: string): number {
  if (code === 'UNAUTHORIZED' || code === 'INVALID_TOKEN') return 401;
  if (code === 'FORBIDDEN' || code === 'NOT_ADMIN' || code === 'NOT_CUSTOMER' || code === 'NOT_DRIVER' || code === 'DRIVER_NOT_VERIFIED' || code === 'DRIVER_NOT_ACTIVE') return 403;
  if (code === 'MERCHANT_NOT_FOUND' || code === 'ORDER_NOT_FOUND' || code === 'DRIVER_NOT_FOUND') return 404;
  if (code === 'DUPLICATE_ORDER' || code === 'ORDER_ALREADY_TAKEN' || code === 'EMAIL_EXISTS' || code === 'NATIONAL_ID_EXISTS' || code === 'PLATE_EXISTS') return 409;
  // State-machine conflicts. 409 rather than 400 because the request was
  // well-formed — it conflicts with the row's current state, which is exactly
  // what 409 is for, and it tells the client a retry without changing anything
  // will not help.
  if (
    code === 'MERCHANT_ALREADY_APPROVED' ||
    code === 'MERCHANT_ALREADY_ACTIVE' ||
    code === 'MERCHANT_ALREADY_INACTIVE' ||
    code === 'MERCHANT_NOT_APPROVED'
  ) return 409;
  if (code === 'RATE_LIMITED') return 429;
  return 400;
}
