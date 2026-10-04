/**
 * Shared constants and types.
 *
 * Kept in one place so a schema change (migration) has exactly one place to be
 * reflected in the UI.
 */

export const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL as string;
export const SUPABASE_ANON_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY as string;
export const ADMIN_API_URL = import.meta.env.VITE_ADMIN_API_URL as string;

/** The four Overview ranges offered by the segmented control. */
export const RANGE_OPTIONS = [7, 30, 90] as const;
export type RangeDays = (typeof RANGE_OPTIONS)[number];
export const DEFAULT_RANGE: RangeDays = 30;

/** Trending is fixed at 7 days by product decision, not user-selectable. */
export const TRENDING_WINDOW_DAYS = 7;

/** Range selector -> i18n key. Kept beside RANGE_OPTIONS so the two can't drift. */
export const RANGE_LABEL_KEYS = {
  7: 'range7',
  30: 'range30',
  90: 'range90',
} as const satisfies Record<RangeDays, 'range7' | 'range30' | 'range90'>;

/**
 * Order statuses, in the order they occur in the lifecycle.
 * Must match the orders_status_check CHECK constraint (migration 008).
 */
export const ORDER_STATUSES = [
  'pending',
  'confirmed',
  'preparing',
  'ready',
  'picked_up',
  'on_the_way',
  'delivered',
  'cancelled',
] as const;
export type OrderStatus = (typeof ORDER_STATUSES)[number];

export const PAYMENT_STATUSES = [
  'pending',
  'pending_cash',
  'paid',
  'failed',
  'refunded',
  'pending_refund',
  'partial_refund',
  'refund_failed',
] as const;
export type PaymentStatus = (typeof PAYMENT_STATUSES)[number];

/**
 * Revenue and order counts BOTH exclude cancelled (migration 120), so the two
 * KPI cards agree. Cancelled is surfaced separately rather than folded in.
 */
export interface PlatformKpis {
  window_days: number;
  from: string;
  to: string;
  revenue: number;
  orders_count: number;
  cancelled_count: number;
  new_customers: number;
  active_customers: number;
  previous: {
    revenue: number;
    orders_count: number;
    new_customers: number;
  };
  change: {
    revenue: number | null;
    orders_count: number | null;
    new_customers: number | null;
  };
  requested_days: number;
}

/** Column order matches get_daily_series (migration 120). */
export interface DailySeriesRow {
  day: string;
  revenue: number;
  orders_count: number;
  new_customers: number;
  cancelled_count: number;
  orders_including_cancelled: number;
}

/** Column order matches get_trending_items (migration 120). */
export interface TrendingItem {
  item_id: string;
  name_en: string;
  name_ar: string;
  category_id: string | null;
  category_en: string | null;
  units_sold: number;
  revenue: number;
  discount_price: number | null;
  /**
   * Arabic category label. NOT returned by get_trending_items — it carries a
   * single `category` column — so this is absent on the live provider and the
   * UI falls back to `category_en`, which is what renders today. Present in the
   * demo so the Arabic Overview is not half-translated.
   */
  category_ar?: string | null;
}

/** Column order matches get_recent_orders (migration 120). */
export interface RecentOrder {
  id: string;
  order_number: string;
  status: OrderStatus;
  total: number;
  payment_method: string;
  payment_status: PaymentStatus;
  created_at: string;
  customer_id: string;
  customer_name: string | null;
  customer_phone: string | null;
  merchant_id: string;
  merchant_name: string | null;
  merchant_city: string | null;
  item_count: number;
  /**
   * Arabic variants. NOT returned by get_recent_orders — it hardcodes
   * m.name_en and reads the single profiles.full_name — so these are absent on
   * the live provider. Optional, and the UI falls back to the English column,
   * which is what renders today. See RecentOrdersTable.
   */
  customer_name_ar?: string;
  merchant_name_ar?: string;
}

/**
 * merchants.category is a foreign key to merchant_categories.code (migration
 * 098), seeded by migration 097 with exactly these eight. The list is copied
 * rather than imported from the database so the dashboard's add-merchant form
 * cannot offer a value the FK would reject.
 */
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
export type MerchantCategoryCode = (typeof MERCHANT_CATEGORY_CODES)[number];

/** merchant_categories lookup row (migration 097). */
export interface MerchantCategoryMeta {
  code: MerchantCategoryCode;
  name_en: string;
  name_ar: string;
  icon: string | null;
  sort_order: number;
}

/** merchants.approval_status CHECK constraint. */
export const APPROVAL_STATUSES = ['pending', 'approved', 'rejected'] as const;
export type ApprovalStatus = (typeof APPROVAL_STATUSES)[number];

/** merchants.payout_frequency CHECK constraint. */
export const PAYOUT_FREQUENCIES = ['daily', 'weekly', 'monthly'] as const;
export type PayoutFrequency = (typeof PAYOUT_FREQUENCIES)[number];

/** merchants.payout_method CHECK constraint. */
export const PAYOUT_METHODS = ['bank_transfer', 'wallet', 'cash', 'instapay'] as const;
export type PayoutMethod = (typeof PAYOUT_METHODS)[number];

/** Every merchants column, from the schema. */
export interface Merchant {
  id: string;
  name_ar: string;
  name_en: string;
  category: MerchantCategoryCode;
  logo_url: string | null;
  cover_url: string | null;
  description_ar: string | null;
  description_en: string | null;
  address: string;
  lat: number;
  lng: number;
  city: string;
  area: string | null;
  phone: string;
  is_active: boolean;
  rating: number;
  rating_count: number;
  min_order_amount: number;
  estimated_delivery_minutes: number;
  delivery_fee_override: number | null;
  commission_pct: number | null;
  delivery_radius_km: number;
  estimated_prep_time_minutes: number;
  payout_frequency: PayoutFrequency;
  payout_method: PayoutMethod;
  wallet_phone: string | null;
  approval_status: ApprovalStatus;
  approval_note: string | null;
  created_at: string;
  updated_at: string;
}

/**
 * The writeable slice of a merchant — what the add/edit form sends.
 *
 * Deliberately excludes id, rating, rating_count and created_at: those are not
 * operator input. rating is a customer-facing aggregate and letting a form set
 * it would let an admin invent a 5.0.
 */
export type MerchantInput = Pick<
  Merchant,
  | 'name_ar'
  | 'name_en'
  | 'category'
  | 'address'
  | 'city'
  | 'area'
  | 'phone'
  | 'description_ar'
  | 'description_en'
  | 'lat'
  | 'lng'
  | 'min_order_amount'
  | 'estimated_delivery_minutes'
  | 'estimated_prep_time_minutes'
  | 'delivery_fee_override'
  | 'commission_pct'
  | 'delivery_radius_km'
  | 'payout_frequency'
  | 'payout_method'
  | 'wallet_phone'
>;

/** categories. Soft-deleted rows carry a timestamp (migration 110). */
export interface Category {
  id: string;
  merchant_id: string;
  name_ar: string;
  name_en: string;
  sort_order: number;
  icon: string | null;
  is_available: boolean;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

/** items. discount_price obeys CHECK (0 <= discount_price <= price). */
export interface Item {
  id: string;
  merchant_id: string;
  category_id: string;
  name_ar: string;
  name_en: string;
  description_ar: string | null;
  description_en: string | null;
  price: number;
  image_url: string | null;
  is_available: boolean;
  sort_order: number;
  popularity_score: number;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
  discount_price: number | null;
}

export type CategoryInput = Pick<Category, 'name_ar' | 'name_en' | 'sort_order'>;

export type ItemInput = Pick<
  Item,
  | 'name_ar'
  | 'name_en'
  | 'description_ar'
  | 'description_en'
  | 'price'
  | 'image_url'
  | 'is_available'
  | 'sort_order'
  | 'discount_price'
>;

/** item_options — a choice group such as Size or Extras. */
export interface ItemOption {
  id: string;
  item_id: string;
  name_ar: string;
  name_en: string;
  is_required: boolean;
  max_selections: number | null;
  min_selections: number;
  sort_order: number;
}

/** item_option_choices — one selectable value, with a price modifier. */
export interface ItemOptionChoice {
  id: string;
  option_id: string;
  name_ar: string;
  name_en: string;
  price_modifier: number;
  is_default: boolean;
  is_available: boolean;
  sort_order: number;
  calories: number | null;
}

/** An option group with its choices nested, for the item editor. */
export interface ItemOptionWithChoices extends ItemOption {
  choices: ItemOptionChoice[];
}

/**
 * THE THREE ITEM STATES
 *
 * Not one boolean. Migration 121 states the distinction outright: "is_available
 * is a merchant-controlled toggle; deleted_at is an administrative removal.
 * Conflating them means 'deleting' an item does not remove it from search."
 *
 *   live       deleted_at IS NULL AND is_available = true   sellable
 *   unavailable deleted_at IS NULL AND is_available = false sold out
 *   deleted    deleted_at IS NOT NULL                      retired
 *
 * Hard DELETE is forbidden: migration 110 changed order_items.item_id to ON
 * DELETE SET NULL precisely because the old CASCADE erased order lines while
 * orders.total survived. The dashboard only ever sets deleted_at.
 */
export type ItemState = 'live' | 'unavailable' | 'deleted';

export function itemState(item: Pick<Item, 'deleted_at' | 'is_available'>): ItemState {
  if (item.deleted_at !== null) return 'deleted';
  return item.is_available ? 'live' : 'unavailable';
}

/** Shape returned by admin-api on success (matches _shared/errors.ts). */
export interface AdminApiSuccess<T> {
  success: true;
  data: T;
}

export interface AdminApiErrorBody {
  success: false;
  error: {
    code: string;
    message_en: string;
    message_ar: string;
    severity: 'info' | 'warning' | 'error';
  };
}

/** admin-api action names. Kept in sync with supabase/functions/admin-api. */
export type AdminAction =
  | 'overview.kpis'
  | 'overview.series'
  | 'overview.trending'
  | 'overview.recent_orders'
  | 'merchant.get'
  | 'merchant.create'
  | 'merchant.update'
  | 'merchant.approve'
  | 'merchant.unapprove'
  | 'merchant.reject'
  | 'merchant.publish'
  | 'merchant.unpublish';

/**
 * Refine resource name -> admin-api action.
 *
 * ONLY the Overview resources are listed. The merchants / categories / items
 * screens have no admin-api action yet, so under the live provider they fail
 * with UNMAPPED_RESOURCE by design — see dataProvider.actionFor. The demo
 * provider serves them from local data under the same resource names, so the
 * components are written once against one vocabulary.
 */
export const RESOURCE_ACTION: Record<string, AdminAction> = {
  'overview-kpis': 'overview.kpis',
  'overview-series': 'overview.series',
  'overview-trending': 'overview.trending',
  'overview-recent-orders': 'overview.recent_orders',

  // Merchant state machine. Keyed `merchants.<action>` because that is how the
  // provider reaches them — Refine has no custom methods, so an `action` field
  // in the payload selects one of these.
  'merchants.get': 'merchant.get',
  'merchants.create': 'merchant.create',
  'merchants.update': 'merchant.update',
  'merchants.approve': 'merchant.approve',
  'merchants.unapprove': 'merchant.unapprove',
  'merchants.reject': 'merchant.reject',
  'merchants.publish': 'merchant.publish',
  'merchants.unpublish': 'merchant.unpublish',
};

/**
 * Which data provider to mount.
 *
 * 'demo' (the default) reads src/demo/data.json plus a localStorage overlay and
 * makes NO network request of any kind — nothing reaches Supabase, so the UI can
 * be iterated on without spending a single call of the project's quota.
 * 'live' mounts the REST provider against the admin-api Edge Function.
 *
 * Resource NAMES are the same either way ('merchants', 'category-items', …), so
 * switching modes requires no component change — only the provider behind them.
 *
 * Read once at module load: switching modes requires a reload anyway, and
 * reading it per-call would let one screen disagree with another about which
 * backend it is talking to.
 */
export const DATA_MODE: 'demo' | 'live' =
  (import.meta.env.VITE_DATA_MODE as 'demo' | 'live' | undefined) ?? 'demo';