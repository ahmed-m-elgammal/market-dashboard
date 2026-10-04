/**
 * Bilingual UI strings (English / Arabic).
 *
 * The database is bilingual throughout — every name, description and comment is
 * a *_ar / *_en pair — so the language toggle switches both the chrome and which
 * name column is rendered. Arabic also flips the document direction to RTL.
 */

export type Lang = 'en' | 'ar';

type Dict = Record<string, { en: string; ar: string }>;

export const STRINGS = {
  appName: { en: 'Marketak Admin', ar: 'مسوقك — الإدارة' },

  // Sidebar / nav
  navDashboard: { en: 'Dashboard', ar: 'لوحة التحكم' },
  navMerchants: { en: 'Merchants', ar: 'التجار' },

  // Login
  loginTitle: { en: 'Admin sign in', ar: 'تسجيل دخول الإدارة' },
  loginEmail: { en: 'Email', ar: 'البريد الإلكتروني' },
  loginPassword: { en: 'Password', ar: 'كلمة المرور' },
  loginSubmit: { en: 'Sign in', ar: 'تسجيل الدخول' },
  loginSigningIn: { en: 'Signing in…', ar: 'جارٍ تسجيل الدخول…' },
  loginFailed: { en: 'Sign in failed', ar: 'فشل تسجيل الدخول' },
  loginNotAdmin: {
    en: 'This account is not an admin.',
    ar: 'هذا الحساب ليس حساب إدارة.',
  },
  loginInvalidCredentials: {
    en: 'Incorrect email or password.',
    ar: 'البريد الإلكتروني أو كلمة المرور غير صحيحة.',
  },

  // Overview
  overviewTitle: { en: 'Overview', ar: 'نظرة عامة' },
  rangeLabel: { en: 'Range', ar: 'المدة' },
  range7: { en: '7 days', ar: '٧ أيام' },
  range30: { en: '30 days', ar: '٣٠ يومًا' },
  range90: { en: '90 days', ar: '٩٠ يومًا' },

  kpiRevenue: { en: 'Revenue', ar: 'الإيرادات' },
  kpiRevenueHint: {
    en: 'Excludes cancelled orders',
    ar: 'لا تشمل الطلبات الملغاة',
  },
  kpiOrders: { en: 'Orders', ar: 'الطلبات' },
  kpiOrdersHint: {
    en: 'Excludes cancelled orders',
    ar: 'لا تشمل الطلبات الملغاة',
  },
  kpiNewCustomers: { en: 'New customers', ar: 'عملاء جدد' },
  kpiActiveCustomers: { en: 'Ordering customers', ar: 'عملاء طلبوا' },

  chartRevenueTitle: { en: 'Daily revenue', ar: 'الإيرادات اليومية' },
  chartOrdersTitle: { en: 'Daily orders', ar: 'الطلبات اليومية' },
  chartCustomersTitle: { en: 'New customers', ar: 'العملاء الجدد' },

  recentOrdersTitle: { en: 'Recent orders', ar: 'أحدث الطلبات' },
  trendingTitle: { en: 'Trending products', ar: 'المنتجات الرائجة' },
  trendingHint: {
    en: 'Top 10 by revenue, last 7 days, delivered orders only',
    ar: 'أفضل ١٠ منتجات حسب الإيراد خلال آخر ٧ أيام، للطلبات المُسلَّمة فقط',
  },
  cancelledHidden: {
    en: '{n} cancelled orders excluded',
    ar: '{n} طلبات ملغاة غير محتسبة',
  },

  // Table columns
  colOrderNumber: { en: 'Order', ar: 'رقم الطلب' },
  colCustomer: { en: 'Customer', ar: 'العميل' },
  colMerchant: { en: 'Merchant', ar: 'التاجر' },
  colCity: { en: 'City', ar: 'المدينة' },
  colItems: { en: 'Items', ar: 'العناصر' },
  colTotal: { en: 'Total', ar: 'الإجمالي' },
  colStatus: { en: 'Status', ar: 'الحالة' },
  colPayment: { en: 'Payment', ar: 'الدفع' },
  colPlacedAt: { en: 'Placed', ar: 'وقت الطلب' },
  colProduct: { en: 'Product', ar: 'المنتج' },
  colCategory: { en: 'Category', ar: 'التصنيف' },
  colUnits: { en: 'Units', ar: 'العدد' },
  colOnPromotion: { en: 'On promotion', ar: 'في عرض' },

  // Merchants — a check-constraint VALUE, not a label.
//
// merchants.payout_frequency and payout_method are CHECK constraints, so their
// contents are the tokens 'weekly' and 'bank_transfer'. Those are identifiers,
// not display copy: an operator-facing screen must translate them, and the
// profile page shows them on every merchant.
//
// The tStatus() fallback already handles a value added by a later migration —
// it degrades to the raw token rather than rendering blank — which is why these
// follow the same status_* naming and are resolved through tStatus().
  status_daily: { en: 'Daily', ar: 'يومي' },
  status_weekly: { en: 'Weekly', ar: 'أسبوعي' },
  status_monthly: { en: 'Monthly', ar: 'شهري' },
  status_bank_transfer: { en: 'Bank transfer', ar: 'تحويل بنكي' },
  status_wallet: { en: 'Wallet', ar: 'محفظة' },
  status_cash: { en: 'Cash', ar: 'نقدًا' },
  status_instapay: { en: 'InstaPay', ar: 'إنستاباي' },

  // Generic
  save: { en: 'Save', ar: 'حفظ' },
  cancel: { en: 'Cancel', ar: 'إلغاء' },
  clear: { en: 'Clear', ar: 'مسح' },
  filter: { en: 'Filter', ar: 'تصفية' },
  retry: { en: 'Retry', ar: 'إعادة المحاولة' },
  loadFailed: { en: 'Could not load data', ar: 'تعذر تحميل البيانات' },
  signOut: { en: 'Sign out', ar: 'تسجيل الخروج' },
  noData: { en: 'No data', ar: 'لا توجد بيانات' },
  unknown: { en: 'Unknown', ar: 'غير معروف' },
  /**
   * For a nullable override column. Distinct from `unknown` on purpose: a null
   * delivery_fee_override is not missing data, it is a decision — "charge the
   * platform default". Rendering it as "Unknown" invites an operator to go
   * looking for a value that is deliberately absent.
   */
  platformDefault: { en: 'Platform default', ar: 'الافتراضي للمنصة' },
  notSet: { en: 'Not set', ar: 'غير محدد' },
  viewAll: { en: 'View all', ar: 'عرض الكل' },
  unexpectedError: { en: 'Unexpected error', ar: 'خطأ غير متوقع' },
  emailInvalid: { en: 'Enter a valid email address', ar: 'أدخل بريدًا إلكترونيًا صحيحًا' },
  /** Language names in their own language — a switcher reads wrong translated. */
  langEnglish: { en: 'English', ar: 'English' },
  langArabic: { en: 'العربية', ar: 'العربية' },
  brandName: { en: 'Marketak', ar: 'مسوقك' },
  brandSuffix: { en: 'Admin', ar: 'الإدارة' },
  /** Chart axis / tooltip captions. */
  axisDay: { en: 'Day', ar: 'اليوم' },
  axisValue: { en: 'Value', ar: 'القيمة' },

  // KPI trend indicators
  trendNew: { en: 'New', ar: 'جديد' },
  trendFlat: { en: 'No change', ar: 'بدون تغيير' },

  // Order status labels
  status_pending: { en: 'Pending', ar: 'قيد الانتظار' },
  status_confirmed: { en: 'Confirmed', ar: 'مؤكد' },
  status_preparing: { en: 'Preparing', ar: 'قيد التحضير' },
  status_ready: { en: 'Ready', ar: 'جاهز' },
  status_picked_up: { en: 'Picked up', ar: 'تم الاستلام' },
  status_on_the_way: { en: 'On the way', ar: 'في الطريق' },
  status_delivered: { en: 'Delivered', ar: 'تم التوصيل' },
  status_cancelled: { en: 'Cancelled', ar: 'ملغي' },

  // Payment status labels — must match payment_statuses CHECK constraint.
  payment_pending: { en: 'Pending', ar: 'قيد الانتظار' },
  payment_pending_cash: { en: 'Cash on delivery', ar: 'الدفع عند الاستلام' },
  payment_paid: { en: 'Paid', ar: 'مدفوع' },
  payment_failed: { en: 'Failed', ar: 'فشل' },
  payment_refunded: { en: 'Refunded', ar: 'مسترد' },
  payment_pending_refund: { en: 'Refund pending', ar: 'استرداد قيد المعالجة' },
  payment_partial_refund: { en: 'Partially refunded', ar: 'استرداد جزئي' },
  payment_refund_failed: { en: 'Refund failed', ar: 'فشل الاسترداد' },

  // Merchants
  merchantsTitle: { en: 'Merchants', ar: 'التجار' },
  addMerchant: { en: 'Add merchant', ar: 'إضافة تاجر' },
  editMerchant: { en: 'Edit merchant', ar: 'تعديل التاجر' },
  createMerchant: { en: 'Create merchant', ar: 'إنشاء التاجر' },
  merchantsCount: { en: '{n} merchants', ar: '{n} تاجر' },
  merchantSearchPlaceholder: {
    en: 'Search name, city or phone',
    ar: 'ابحث بالاسم أو المدينة أو الهاتف',
  },

  // Demo mode
  demoBanner: {
    en: 'Demo data — nothing here reaches the live database.',
    ar: 'بيانات تجريبية — لا يتم إرسال أي شيء إلى قاعدة البيانات الحية.',
  },
  demoSignInHint: {
    en: 'Demo sign-in: {email} with any password.',
    ar: 'الدخول التجريبي: {email} بأي كلمة مرور.',
  },
  resetDemoData: { en: 'Reset demo data', ar: 'إعادة تعيين البيانات التجريبية' },
  resetDemoDone: { en: 'Demo data reset.', ar: 'تمت إعادة تعيين البيانات التجريبية.' },
  resetDemoConfirm: {
    en: 'Discard every local edit and reload the generated dataset?',
    ar: 'هل تريد إلغاء كل التعديلات المحلية وإعادة تحميل البيانات المولدة؟',
  },
  demoEditsCount: { en: '{n} local edits', ar: '{n} تعديل محلي' },

  // Merchant status
  approval_pending: { en: 'Pending review', ar: 'قيد المراجعة' },
  approval_approved: { en: 'Approved', ar: 'معتمد' },
  approval_rejected: { en: 'Rejected', ar: 'مرفوض' },
  statusActive: { en: 'Active', ar: 'نشط' },
  statusInactive: { en: 'Inactive', ar: 'غير نشط' },

  // Merchant form
  fieldNameEn: { en: 'Name (English)', ar: 'الاسم (إنجليزي)' },
  fieldNameAr: { en: 'Name (Arabic)', ar: 'الاسم (عربي)' },
  fieldCategory: { en: 'Category', ar: 'التصنيف' },
  fieldDescriptionEn: { en: 'Description (English)', ar: 'الوصف (إنجليزي)' },
  fieldDescriptionAr: { en: 'Description (Arabic)', ar: 'الوصف (عربي)' },
  fieldAddress: { en: 'Address', ar: 'العنوان' },
  fieldCity: { en: 'City', ar: 'المدينة' },
  fieldArea: { en: 'Area', ar: 'المنطقة' },
  fieldPhone: { en: 'Phone', ar: 'الهاتف' },
  fieldMinOrder: { en: 'Minimum order', ar: 'الحد الأدنى للطلب' },
  fieldDeliveryMinutes: { en: 'Delivery time (min)', ar: 'مدة التوصيل (دقيقة)' },
  fieldPrepMinutes: { en: 'Prep time (min)', ar: 'مدة التحضير (دقيقة)' },
  fieldDeliveryFee: { en: 'Delivery fee override', ar: 'رسوم توصيل مخصصة' },
  fieldCommission: { en: 'Commission %', ar: 'نسبة العمولة %' },
  fieldDeliveryRadius: { en: 'Delivery radius (km)', ar: 'نطاق التوصيل (كم)' },
  fieldPayoutFrequency: { en: 'Payout frequency', ar: 'فترة التحويل' },
  fieldPayoutMethod: { en: 'Payout method', ar: 'طريقة التحويل' },
  fieldWalletPhone: { en: 'Wallet phone', ar: 'هاتف المحفظة' },
  fieldLat: { en: 'Latitude', ar: 'خط العرض' },
  fieldLng: { en: 'Longitude', ar: 'خط الطول' },
  /** Shown under the create form so approval behaviour is never a surprise. */
  /**
   * Approval and publication. Two separate decisions, so two separate groups —
   * "Approve" must never sit next to "Publish" as if they were the same act.
   */
  approvalSection: { en: 'Review', ar: 'المراجعة' },
  publicationSection: { en: 'Visibility to customers', ar: 'الظهور للعملاء' },
  actionApprove: { en: 'Approve', ar: 'اعتماد' },
  actionUnapprove: { en: 'Withdraw approval', ar: 'سحب الاعتماد' },
  actionReject: { en: 'Reject', ar: 'رفض' },
  actionPublish: { en: 'Publish', ar: 'نشر' },
  actionUnpublish: { en: 'Unpublish', ar: 'إلغاء النشر' },
  actionApproveTitle: { en: 'Approve this merchant', ar: 'اعتماد هذا التاجر' },
  actionApproveNote: {
    en: 'Optional note. Recorded against the approval.',
    ar: 'ملاحظة اختيارية. تُسجل مع قرار الاعتماد.',
  },
  actionRejectTitle: { en: 'Reject this merchant', ar: 'رفض هذا التاجر' },
  actionRejectReasonLabel: { en: 'Reason for rejection', ar: 'سبب الرفض' },
  actionRejectReasonRequired: {
    en: 'A reason is required so the merchant can be told why.',
    ar: 'سبب الرفض مطلوب ليُبلَّغ به التاجر.',
  },
  actionUnapproveConfirm: {
    en: 'Withdraw approval? The merchant will also be unpublished, because a withdrawn merchant must not stay visible to customers.',
    ar: 'هل سحب الاعتماد؟ سيُلغى نشر التاجر أيضاً، لأن التاجر المسحوب الاعتماد منه يجب ألا يظل ظاهراً للعملاء.',
  },
  actionUnpublishConfirm: {
    en: 'Unpublish this merchant? Customers will stop seeing it. Orders already placed are not affected.',
    ar: 'هل إلغاء نشر هذا التاجر؟ سيختفي عن العملاء. الطلبات السابقة لن تتأثر.',
  },
  approvalAwaitingReview: {
    en: 'This merchant is awaiting review.',
    ar: 'هذا التاجر في انتظار المراجعة.',
  },
  approvalGranted: { en: 'Approved', ar: 'معتمد' },
  approvalRejected: { en: 'Rejected', ar: 'مرفوض' },
  published_visible: {
    en: 'Visible to customers',
    ar: 'ظاهر للعملاء',
  },
  unpublished_hidden: {
    en: 'Hidden from customers',
    ar: 'مخفي عن العملاء',
  },
  publishNeedsApproval: {
    en: 'Approve this merchant before publishing it.',
    ar: 'يجب اعتماد هذا التاجر قبل نشره.',
  },
  stateAlreadyApproved: { en: 'This merchant is already approved', ar: 'هذا التاجر معتمد بالفعل' },
  stateAlreadyRejected: { en: 'This merchant is already rejected', ar: 'هذا التاجر مرفوض بالفعل' },
  stateNotApproved: { en: 'Approve this merchant first', ar: 'يجب اعتماد هذا التاجر أولاً' },
  stateAlreadyPublished: { en: 'This merchant is already published', ar: 'هذا التاجر منشور بالفعل' },
  stateNotPublished: { en: 'This merchant is not published', ar: 'هذا التاجر غير منشور' },
  stateNoteRequired: { en: 'A reason is required', ar: 'السبب مطلوب' },
  stateNotFound: { en: 'Merchant not found', ar: 'التاجر غير موجود' },

  newMerchantPendingNote: {
    en: 'A new merchant is created pending review and will not appear to customers until it is approved.',
    ar: 'يُنشأ التاجر الجديد قيد المراجعة ولن يظهر للعملاء حتى يُعتمد.',
  },

  /** Google Maps link importer. Optional — everything it fills can be typed. */
  fieldMapsLink: { en: 'Google Maps link', ar: 'رابط خرائط جوجل' },
  mapsLinkHint: {
    en: 'Optional. Paste a full Maps place link to fill the name and coordinates.',
    ar: 'اختياري. الصق رابط المكان الكامل من خرائط جوجل لملء الاسم والإحداثيات.',
  },
  mapsLinkFilled: {
    en: 'Filled in the name and coordinates. Check them before saving.',
    ar: 'تم ملء الاسم والإحداثيات. راجعها قبل الحفظ.',
  },
  /**
   * Second box: the address and phone text from the Maps info panel. Neither is
   * in the link, so this is what makes those two fields a paste instead of
   * typing.
   */
  fieldMapsPaste: { en: 'Address & phone from Maps', ar: 'العنوان والهاتف من الخرائط' },
  mapsPasteHint: {
    en: 'Optional. In Maps, open the place and copy the address and phone shown under the name, then paste them here.',
    ar: 'اختياري. افتح المكان في خرائط جوجل وانسخ العنوان ورقم الهاتف الظاهرين تحت الاسم، ثم الصقهما هنا.',
  },
  mapsPasteFilled: {
    en: 'Filled in what was recognised. Check it before saving.',
    ar: 'تم ملء ما تم التعرف عليه. راجعه قبل الحفظ.',
  },
  mapsPasteNothing: {
    en: 'No address or phone found in that text. Paste the lines Maps shows under the name.',
    ar: 'لم يتم العثور على عنوان أو هاتف في هذا النص. الصق السطور التي يعرضها الخرائط تحت الاسم.',
  },
  mapsLinkShortLink: {
    en: 'That is a short link, which the browser cannot open. In Maps choose Share, then Copy link, and paste the longer link.',
    ar: 'هذا رابط مختصر لا يستطيع المتصفح فتحه. من خرائط جوجل اختر مشاركة ثم نسخ الرابط، والصق الرابط الأطول.',
  },
  mapsLinkNoCoordinates: {
    en: 'No coordinates in that link. Open the place in Maps and copy the link from the address bar.',
    ar: 'لا توجد إحداثيات في هذا الرابط. افتح المكان في خرائط جوجل وانسخ الرابط من شريط العنوان.',
  },
  mapsLinkNotMaps: {
    en: 'That is not a Google Maps link.',
    ar: 'هذا ليس رابط خرائط جوجل.',
  },
  mapsLinkInvalid: {
    en: 'Could not read that link.',
    ar: 'تعذّرت قراءة هذا الرابط.',
  },

  merchantDetails: { en: 'Details', ar: 'التفاصيل' },
  merchantDelivery: { en: 'Delivery & fees', ar: 'التوصيل والرسوم' },
  merchantPayout: { en: 'Payout', ar: 'التحويلات' },
  merchantContact: { en: 'Contact', ar: 'التواصل' },
  merchantCreated: { en: 'Joined', ar: 'تاريخ الانضمام' },

  ratingLabel: { en: 'Rating', ar: 'التقييم' },
  ratingCount: { en: '{n} reviews', ar: '{n} تقييم' },

  // Categories
  categoriesTitle: { en: 'Menu categories', ar: 'تصنيفات القائمة' },
  /**
   * Header for the "categories / items" cell. Spelled out because the cell shows
   * two bare numbers and "Menu categories" does not say which is which.
   */
  categoriesAndItems: { en: 'Categories / items', ar: 'التصنيفات / العناصر' },
  addCategory: { en: 'Add category', ar: 'إضافة تصنيف' },
  editCategory: { en: 'Edit category', ar: 'تعديل التصنيف' },
  categorySearchPlaceholder: { en: 'Search category', ar: 'ابحث في التصنيفات' },
  categoryEmpty: {
    en: 'This merchant has no categories yet.',
    ar: 'لا توجد تصنيفات لهذا التاجر بعد.',
  },
  categoryItemsAction: { en: 'Items', ar: 'العناصر' },
  selectCategoryHint: {
    en: 'Pick a category to see its items.',
    ar: 'اختر تصنيفًا لعرض عناصره.',
  },
  colSortOrder: { en: 'Order', ar: 'الترتيب' },
  /**
   * items.sort_order, as distinct from an order (a purchase). "Order" alone is
   * ambiguous on a screen that also lists orders, so the label names what the
   * number actually controls.
   */
  colPosition: { en: 'Position in menu', ar: 'الترتيب في القائمة' },
  /** items.popularity_score — an internal ranking signal, not a review count. */
  popularityScore: { en: 'Popularity score', ar: 'مؤشر الرواج' },
  lastUpdated: { en: 'Last updated', ar: 'آخر تحديث' },
  neverDeleted: { en: 'Not deleted', ar: 'غير محذوف' },
  /** item_option_choices.calories — a bare number with no unit means nothing. */
  calories: { en: '{n} kcal', ar: '{n} سعرة' },
  colAvailability: { en: 'Availability', ar: 'التوفر' },
  colActions: { en: 'Actions', ar: 'إجراءات' },
  categoryCreated: { en: 'Category saved.', ar: 'تم حفظ التصنيف.' },
  /** Per-category summary on the merchant profile: "{n} items · {n} unavailable". */
  categoryItemsCount: { en: '{n} items', ar: '{n} صنف' },
  categoryUnavailableCount: { en: '{n} unavailable', ar: '{n} غير متوفر' },

  // Items
  itemsTitle: { en: 'Items', ar: 'العناصر' },
  addItem: { en: 'Add item', ar: 'إضافة صنف' },
  viewItem: { en: 'View item', ar: 'عرض الصنف' },
  editItem: { en: 'Edit item', ar: 'تعديل الصنف' },
  itemSearchPlaceholder: { en: 'Search name or ID', ar: 'ابحث بالاسم أو المعرف' },
  itemIdLabel: { en: 'ID', ar: 'المعرف' },
  copyId: { en: 'Copy ID', ar: 'نسخ المعرف' },
  copied: { en: 'Copied', ar: 'تم النسخ' },

  // THE THREE ITEM STATES — see itemState() in constants.ts
  itemStateLive: { en: 'Available', ar: 'متوفر' },
  itemStateUnavailable: { en: 'Unavailable', ar: 'غير متوفر' },
  itemStateDeleted: { en: 'Deleted', ar: 'محذوف' },

  /**
   * Why unavailable and deleted are different things, in the operator's own
   * terms. Shown as a tooltip on the state column because this is the single
   * most confusable pair in the admin: migration 121 spells out that
   * is_available is a merchant toggle and deleted_at is an admin removal.
   */
  itemStateLiveHint: {
    en: 'Visible in the menu and orderable.',
    ar: 'ظاهر في القائمة وقابل للطلب.',
  },
  itemStateUnavailableHint: {
    en: 'Hidden from the menu because the merchant marked it unavailable. Still in the catalog — toggle it back on at any time.',
    ar: 'مخفي من القائمة لأن التاجر جعله غير متوفر. ما زال في الكتالوج — يمكنك تفعيله في أي وقت.',
  },
  itemStateDeletedHint: {
    en: 'Removed from the menu. Kept, not erased, so order history and revenue stay intact.',
    ar: 'تمت إزالته من القائمة. محفوظ وليس محذوفًا، ليبقى سجل الطلبات والإيرادات سليمًا.',
  },

  showDeleted: { en: 'Show deleted', ar: 'عرض المحذوف' },
  stateFilterLabel: { en: 'Show', ar: 'عرض' },
  stateAll: { en: 'All', ar: 'الكل' },
  stateLive: { en: 'In menu', ar: 'في القائمة' },
  stateAvailable: { en: 'Available', ar: 'متوفر' },
  stateUnavailable: { en: 'Unavailable', ar: 'غير متوفر' },
  stateDeleted: { en: 'Deleted', ar: 'محذوف' },

  markUnavailable: { en: 'Mark unavailable', ar: 'تعليم كغير متوفر' },
  markAvailable: { en: 'Mark available', ar: 'تعليم كمتوفر' },
  deleteItem: { en: 'Delete item', ar: 'حذف الصنف' },
  restoreItem: { en: 'Restore item', ar: 'استعادة الصنف' },

  /**
   * Delete confirmation. States the consequence honestly: the row is retained
   * and order history survives. A confirmation that said "this cannot be
   * undone" when it can, or implied a hard delete when it is soft, would make an
   * operator hesitate over a reversible action and relax over an irreversible
   * one.
   */
  deleteItemConfirmTitle: { en: 'Delete this item?', ar: 'حذف هذا الصنف؟' },
  deleteItemConfirmBody: {
    en: 'It will disappear from the menu. The item is kept, not erased, so its order history and revenue stay intact. You can restore it later.',
    ar: 'سيختفي من القائمة. يُحتفظ بالصنف ولا يُتلف، ليبقى سجل الطلبات والإيرادات سليمًا. يمكنك استعادته لاحقًا.',
  },

  itemSaved: { en: 'Item saved.', ar: 'تم حفظ الصنف.' },
  itemDeleted: { en: 'Item deleted.', ar: 'تم حذف الصنف.' },
  itemRestored: { en: 'Item restored.', ar: 'تمت استعادة الصنف.' },
  itemMarkedAvailable: { en: 'Item is now available.', ar: 'الصنف متوفر الآن.' },
  itemMarkedUnavailable: {
    en: 'Item hidden from the menu.',
    ar: 'الصنف مخفي من القائمة.',
  },
  itemNotFound: { en: 'That item no longer exists.', ar: 'هذا الصنف لم يعد موجودًا.' },

  // Item form
  fieldPrice: { en: 'Price', ar: 'السعر' },
  fieldDiscountPrice: { en: 'Discount price', ar: 'سعر الخصم' },
  fieldImageUrl: { en: 'Image URL', ar: 'رابط الصورة' },
  onPromotion: { en: 'On promotion', ar: 'في عرض' },
  clearDiscount: { en: 'Remove discount', ar: 'إزالة الخصم' },
  discountHint: {
    en: 'Leave empty when the item is not on promotion. Must not exceed the price.',
    ar: 'اتركه فارغًا إذا لم يكن الصنف في عرض. يجب ألا يتجاوز السعر.',
  },
  /** Live read-out under the discount field: "20% off". */
  discountPercent: { en: '{n}% off', ar: 'خصم {n}٪' },
  optionsTitle: { en: 'Options', ar: 'الخيارات' },
  optionsHint: {
    en: 'Choice groups are configured per item. Each choice can add to or subtract from the price.',
    ar: 'مجموعات الخيارات تُعد لكل صنف. كل خيار يمكن أن يضيف أو يخصم من السعر.',
  },
  optionsEmpty: {
    en: 'This item has no option groups.',
    ar: 'لا توجد مجموعات خيارات لهذا الصنف.',
  },
  optionRequired: { en: 'Required', ar: 'مطلوب' },
  optionOptional: { en: 'Optional', ar: 'اختياري' },
  optionPriceModifier: { en: 'Price change', ar: 'تغيير السعر' },
  optionDefault: { en: 'Default', ar: 'افتراضي' },
  optionSoldOut: { en: 'Sold out', ar: 'غير متوفر' },
  optionsReadOnly: {
    en: 'Option groups are read-only in this build. Editing them is the next step.',
    ar: 'مجموعات الخيارات للقراءة فقط في هذه النسخة. تعديلها هو الخطوة التالية.',
  },

  // Validation
  errDiscountAbovePrice: {
    en: 'The discount price cannot be higher than the price.',
    ar: 'لا يمكن أن يكون سعر الخصم أعلى من السعر.',
  },
  errDiscountNegative: {
    en: 'The discount price cannot be negative.',
    ar: 'لا يمكن أن يكون سعر الخصم سالبًا.',
  },
  errRequired: { en: 'This field is required', ar: 'هذا الحقل مطلوب' },
  errPositiveNumber: { en: 'Enter a number of 0 or more', ar: 'أدخل رقمًا يساوي ٠ أو أكثر' },
  errInvalidNumber: { en: 'Enter a valid number', ar: 'أدخل رقمًا صالحًا' },
  errPhone: { en: 'Enter a valid phone number', ar: 'أدخل رقم هاتف صالحًا' },

  merchantCreatedToast: { en: 'Merchant created.', ar: 'تم إنشاء التاجر.' },
  merchantSaved: { en: 'Merchant saved.', ar: 'تم حفظ التاجر.' },
  merchantNotFound: { en: 'That merchant no longer exists.', ar: 'هذا التاجر لم يعد موجودًا.' },
  backToMerchants: { en: 'Back to merchants', ar: 'العودة إلى التجار' },
  backToCategories: { en: 'Back to categories', ar: 'العودة إلى التصنيفات' },
  backToItems: { en: 'Back to items', ar: 'العودة إلى العناصر' },

  // Errors
  errorNotFoundTitle: { en: 'Page not found', ar: 'الصفحة غير موجودة' },
  errorNotFoundBody: {
    en: 'That address does not exist in the admin dashboard.',
    ar: 'هذا العنوان غير موجود في لوحة التحكم.',
  },
  backToDashboard: { en: 'Back to dashboard', ar: 'العودة إلى لوحة التحكم' },
} satisfies Dict;

export type StringKey = keyof typeof STRINGS;

/** Translate a key. Falls back to English so a missing Arabic string is visible. */
export function t(key: StringKey, lang: Lang): string {
  return STRINGS[key][lang];
}

/**
 * Translate a dynamic status value, falling back to the raw database value.
 *
 * Each prefix is a CHECK constraint in the database, not a compile-time union at
 * this boundary, so the key cannot be proven to exist. A new status added by a
 * migration must degrade to the raw token ("pending_refund") rather than render
 * blank or throw — visible and debuggable beats a silent hole.
 */
export function tStatus(
  prefix: 'status' | 'payment' | 'approval',
  value: string,
  lang: Lang,
): string {
  const key = `${prefix}_${value}` as StringKey;
  return STRINGS[key]?.[lang] ?? value;
}

/** Pick the right name column for the active language. */
export function pickName(
  en: string | null | undefined,
  ar: string | null | undefined,
  lang: Lang,
): string {
  const primary = lang === 'ar' ? ar : en;
  const fallback = lang === 'ar' ? en : ar;
  return primary || fallback || '';
}

/** Interpolate {n}-style placeholders. */
export function fmt(template: string, values: Record<string, string | number>): string {
  return template.replace(/\{(\w+)\}/g, (_, k) => String(values[k] ?? ''));
}

/**
 * Render a thrown error's message in the active language.
 *
 * Both providers attach the other script to the error — AdminApiError carries
 * `messageAr`, DemoApiError the same — because the Edge Function's
 * ErrorResponse is bilingual (_shared/errors.ts) and there is no reason to throw
 * that away. Reading `.message` directly therefore rendered English inside an
 * Arabic UI.
 *
 * Falls back to `.message`, then to the caller's own generic string, and never
 * returns an empty string: a blank error box gives an operator nothing to act on
 * and nothing to report.
 */
export function errorText(
  error: unknown,
  lang: Lang,
  fallbackKey: StringKey = 'unexpectedError',
): string {
  const e = (error ?? {}) as { messageAr?: string; message?: string };
  if (lang === 'ar' && e.messageAr) return e.messageAr;
  return e.message || t(fallbackKey, lang);
}

export const CURRENCY = 'EGP';

/**
 * Bound currency formatter for the active language.
 *
 * Returns the FORMATTER, not a formatted string: Intl.NumberFormat instances
 * are stateful and expensive to construct, so one is built per language change
 * and reused across every card, table cell and axis on the page.
 */
export function currencyFormatter(lang: Lang): (value: number) => string {
  const nf = new Intl.NumberFormat(LOCALE[lang], {
    style: 'currency',
    currency: CURRENCY,
    maximumFractionDigits: 0,
  });
  return (value: number) => nf.format(value);
}

/** Grouped integer, script-appropriate digits for the active language. */
export function countFormatter(lang: Lang): (value: number) => string {
  const nf = new Intl.NumberFormat(LOCALE[lang], { maximumFractionDigits: 0 });
  return (value: number) => nf.format(value);
}

/**
 * A rating, always to one decimal place.
 *
 * A separate bound formatter rather than countFormatter because ratings need a
 * fixed fraction and a SEPARATOR: `toFixed(1)` hardcodes Latin digits and a
 * period, so an Arabic dashboard showed "3.7" beside "٢٤ تاجر" — two scripts for
 * numbers on the same screen. Intl supplies the locale's digits AND its decimal
 * separator (Arabic-Indic uses U+066B), which is the only way to get both right.
 */
export function ratingFormatter(lang: Lang): (value: number) => string {
  const nf = new Intl.NumberFormat(LOCALE[lang], {
    minimumFractionDigits: 1,
    maximumFractionDigits: 1,
  });
  return (value: number) => nf.format(value);
}

export const LOCALE: Record<Lang, string> = {
  en: 'en-EG',
  ar: 'ar-EG',
};

export const DIRECTION: Record<Lang, 'ltr' | 'rtl'> = {
  en: 'ltr',
  ar: 'rtl',
};