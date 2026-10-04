/**
 * The demo backend.
 *
 * Reads src/demo/data.json once, layers a localStorage overlay on top, and
 * answers the same queries the live admin-api would. It exists so the whole
 * dashboard — Overview included — can be built and iterated on with NO network
 * request of any kind, which is what keeps the real Supabase project untouched
 * while the UI is in flux.
 *
 * WHY AN OVERLAY RATHER THAN A MUTATED COPY
 *   The dataset is generated and regenerable: re-running the generator overwrites
 *   data.json wholesale. If edits were written back into the JSON they would be
 *   silently destroyed on the next regeneration, and a reviewer could never tell
 *   authored content from scratch data. So the JSON stays pristine and only the
 *   DELTA is persisted — as patches keyed by id, plus whole rows for things
 *   created in the browser.
 *
 *   The consequence to be aware of: an overlay row whose id no longer exists in
 *   the regenerated dataset is orphaned. Orphans are dropped on read rather than
 *   surfaced as phantom rows, and `resetOverlay` clears them.
 *
 * WHAT THIS IS NOT
 *   Not a mock of the API — it does not model the wire format, errors or latency.
 *   It models the DATABASE. Field names, CHECK constraints and soft-delete
 *   semantics are the real ones, so a screen that works here works against
 *   Postgres. Field-level validation that the database would enforce (the
 *   discount_price <= price rule, for instance) is asserted here too, so an
 *   invalid edit fails in the demo exactly as it would on insert.
 */
import type {
  Category,
  CategoryInput,
  Item,
  ItemInput,
  ItemOption,
  ItemOptionChoice,
  ItemOptionWithChoices,
  Merchant,
  MerchantCategoryMeta,
  MerchantInput,
  PlatformKpis,
  DailySeriesRow,
  TrendingItem,
  RecentOrder,
  RangeDays,
} from '../constants';

// ---------------------------------------------------------------------------
// Tuple types — the generated file stores orders as arrays to keep it small.
// These are positional mirrors of `order_shape` in the generator; the unpackers
// below are the ONLY place the positional knowledge lives.
// ---------------------------------------------------------------------------

type DemoOrderTuple = [
  id: string,
  orderNumber: string,
  merchantId: string,
  customerNameEn: string,
  customerNameAr: string,
  customerPhone: string,
  city: string,
  status: string,
  paymentStatus: string,
  paymentMethod: string,
  total: number,
  createdAt: string,
  lines: [itemId: string, quantity: number, unitPrice: number, lineTotal: number, selected: [string, number][] | null][],
];

type DemoSeriesTuple = [
  day: string,
  revenue: number,
  orders_count: number,
  new_customers: number,
  cancelled_count: number,
  orders_including_cancelled: number,
];

type DemoTrendingTuple = [
  item_id: string,
  name_en: string,
  name_ar: string,
  category_id: string | null,
  category_en: string | null,
  category_ar: string | null,
  units_sold: number,
  revenue: number,
  discount_price: number | null,
];

type DemoRecentOrderTuple = [
  id: string,
  order_number: string,
  status: string,
  total: number,
  payment_method: string,
  payment_status: string,
  created_at: string,
  customer_id: string,
  customer_name: string,
  customer_phone: string,
  merchant_id: string,
  merchant_name: string,
  merchant_city: string,
  item_count: number,
  customer_name_ar: string,
  merchant_name_ar: string,
];

interface DemoDataset {
  meta: {
    generator: string;
    seed: string;
    demo_today: string;
    history_days: number;
    counts: Record<string, number>;
  };
  merchant_categories: MerchantCategoryMeta[];
  merchants: Merchant[];
  categories: Category[];
  items: Item[];
  item_options: ItemOption[];
  item_option_choices: ItemOptionChoice[];
  orders: DemoOrderTuple[];
  overview: {
    kpis: Record<string, PlatformKpis>;
    series: Record<string, DemoSeriesTuple[]>;
    trending: DemoTrendingTuple[];
    recent_orders: DemoRecentOrderTuple[];
  };
}

/**
 * The dataset, loaded ON DEMAND.
 *
 * A static `import data from './data.json'` put 2.8 MB into the main chunk, and
 * the main chunk is what ships. That is the wrong shape for a fixture twice
 * over: it made the live-mode bundle carry demo data it can never use, and it
 * put 2.8 MB of JSON parsing in front of the first paint in demo mode.
 *
 * The dynamic import splits it into its own chunk, fetched in parallel with the
 * first query rather than before it. Every read below therefore goes through
 * ensureLoaded(), which the provider awaits — its methods are already async, so
 * this costs nothing structurally.
 */
let dataset: DemoDataset | null = null;
let loading: Promise<DemoDataset> | null = null;

async function ensureLoaded(): Promise<DemoDataset> {
  if (dataset) return dataset;
  // The in-flight promise is cached rather than the result alone: React Query
  // fires four Overview queries at once on first paint, and four concurrent
  // 2.8 MB fetches would each parse the file.
  if (!loading) {
    loading = import('./data.json').then((module) => {
      dataset = (module.default ?? module) as unknown as DemoDataset;
      return dataset;
    });
  }
  return loading;
}

/** True once the corpus is in memory. Used by the reset control's edit count. */
export function isLoaded(): boolean {
  return dataset !== null;
}

// ---------------------------------------------------------------------------
// Unpackers
// ---------------------------------------------------------------------------

function toSeriesRow(t: DemoSeriesTuple): DailySeriesRow {
  return {
    day: t[0],
    revenue: t[1],
    orders_count: t[2],
    new_customers: t[3],
    cancelled_count: t[4],
    orders_including_cancelled: t[5],
  };
}

function toTrendingItem(t: DemoTrendingTuple): TrendingItem {
  return {
    item_id: t[0],
    name_en: t[1],
    name_ar: t[2],
    category_id: t[3],
    category_en: t[4],
    // The live RPC returns one category label, so this is absent there and the
    // UI falls back to the English column — exactly what it renders today. The
    // demo carries both so the Arabic Overview is actually Arabic.
    category_ar: t[5],
    units_sold: t[6],
    revenue: t[7],
    discount_price: t[8],
  };
}

function toRecentOrder(t: DemoRecentOrderTuple): RecentOrder {
  return {
    id: t[0],
    order_number: t[1],
    status: t[2] as RecentOrder['status'],
    total: t[3],
    payment_method: t[4],
    payment_status: t[5] as RecentOrder['payment_status'],
    created_at: t[6],
    customer_id: t[7],
    customer_name: t[8],
    customer_phone: t[9],
    merchant_id: t[10],
    merchant_name: t[11],
    merchant_city: t[12],
    item_count: t[13],
    customer_name_ar: t[14],
    merchant_name_ar: t[15],
  };
}

// ---------------------------------------------------------------------------
// Overlay
// ---------------------------------------------------------------------------

const STORAGE_KEY = 'marketak-admin-demo-overlay';

/**
 * Edits made in the browser, layered over the generated dataset.
 *
 * `patches` is a partial row keyed by id — an edit only stores what changed, so
 * a field the generator later changes still comes through from the JSON rather
 * than being frozen at the moment of the edit.
 */
interface Overlay {
  merchantPatches: Record<string, Partial<Merchant>>;
  /** Rows created in the browser, which have no counterpart in the JSON. */
  newMerchants: Merchant[];
  itemPatches: Record<string, Partial<Item>>;
  newItems: Item[];
  categoryPatches: Record<string, Partial<Category>>;
  newCategories: Category[];
}

const EMPTY_OVERLAY: Overlay = {
  merchantPatches: {},
  newMerchants: [],
  itemPatches: {},
  newItems: [],
  categoryPatches: {},
  newCategories: [],
};

/**
 * Read the overlay, tolerating absence and corruption.
 *
 * A malformed blob must not brick the dashboard: it degrades to "no edits" and
 * says so in the console, because a user with a half-written localStorage entry
 * still needs to reach the screen to press Reset.
 */
function readOverlay(): Overlay {
  if (typeof window === 'undefined') return EMPTY_OVERLAY;
  const stored = window.localStorage.getItem(STORAGE_KEY);
  if (!stored) return EMPTY_OVERLAY;
  try {
    const parsed = JSON.parse(stored) as Partial<Overlay>;
    return {
      merchantPatches: parsed.merchantPatches ?? {},
      newMerchants: parsed.newMerchants ?? [],
      itemPatches: parsed.itemPatches ?? {},
      newItems: parsed.newItems ?? [],
      categoryPatches: parsed.categoryPatches ?? {},
      newCategories: parsed.newCategories ?? [],
    };
  } catch {
    // eslint-disable-next-line no-console
    console.warn('[demo] overlay was unreadable and has been ignored — press Reset demo data');
    return EMPTY_OVERLAY;
  }
}

function writeOverlay(overlay: Overlay) {
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(overlay));
  } catch {
    // Quota exceeded, or storage disabled (private browsing). The in-memory
    // edits still apply for this session; only persistence across a reload is
    // lost, which is recoverable and must not fail the write itself.
    // eslint-disable-next-line no-console
    console.warn('[demo] could not persist edits; they will not survive a reload');
  }
}

let overlay = readOverlay();

/** Number of local edits currently layered over the generated data. */
export function overlayEditCount(): number {
  return (
    Object.keys(overlay.merchantPatches).length +
    overlay.newMerchants.length +
    Object.keys(overlay.itemPatches).length +
    overlay.newItems.length +
    Object.keys(overlay.categoryPatches).length +
    overlay.newCategories.length
  );
}

/** Drop every local edit. The generated dataset is untouched either way. */
export function resetOverlay() {
  overlay = structuredClone(EMPTY_OVERLAY);
  writeOverlay(overlay);
}

/**
 * Ids that exist in the overlay but not in the regenerated dataset.
 *
 * Surfaced so a stale overlay is visible rather than silently resurrecting rows
 * that no longer exist upstream.
 */
export async function orphanedOverlayIds(): Promise<string[]> {
  const data = await ensureLoaded();
  const merchantIds = new Set(data.merchants.map((m) => m.id));
  const itemIds = new Set(data.items.map((i) => i.id));
  const categoryIds = new Set(data.categories.map((c) => c.id));

  const orphans: string[] = [];
  for (const id of Object.keys(overlay.merchantPatches)) {
    if (!merchantIds.has(id)) orphans.push(id);
  }
  for (const id of Object.keys(overlay.itemPatches)) {
    if (!itemIds.has(id)) orphans.push(id);
  }
  for (const id of Object.keys(overlay.categoryPatches)) {
    if (!categoryIds.has(id)) orphans.push(id);
  }
  // Rows created in the browser are expected to have no JSON counterpart — they
  // are not orphans, they are new. Only patched-but-missing ids are reported.
  return orphans;
}

// ---------------------------------------------------------------------------
// Reads
// ---------------------------------------------------------------------------

function merge<T extends { id: string }>(
  base: T[],
  patches: Record<string, Partial<T>>,
  created: T[],
): T[] {
  const merged = base.map((row) => (patches[row.id] ? { ...row, ...patches[row.id] } : row));
  return created.length > 0 ? [...merged, ...created] : merged;
}

export const demoMetaPlaceholder = null;

export async function allMerchants(): Promise<Merchant[]> {
  const data = await ensureLoaded();
  return merge(data.merchants, overlay.merchantPatches, overlay.newMerchants);
}

export async function allCategories(): Promise<Category[]> {
  const data = await ensureLoaded();
  return merge(data.categories, overlay.categoryPatches, overlay.newCategories);
}

export async function allItems(): Promise<Item[]> {
  const data = await ensureLoaded();
  return merge(data.items, overlay.itemPatches, overlay.newItems);
}

export async function getMerchant(id: string): Promise<Merchant | undefined> {
  return (await allMerchants()).find((m) => m.id === id);
}

export async function getCategory(id: string): Promise<Category | undefined> {
  return (await allCategories()).find((c) => c.id === id);
}

export async function getItem(id: string): Promise<Item | undefined> {
  return (await allItems()).find((i) => i.id === id);
}

export async function categoriesForMerchant(merchantId: string): Promise<Category[]> {
  return (await allCategories())
    .filter((c) => c.merchant_id === merchantId)
    .sort((a, b) => a.sort_order - b.sort_order);
}

export async function itemsForCategory(categoryId: string): Promise<Item[]> {
  return (await allItems())
    .filter((i) => i.category_id === categoryId)
    .sort((a, b) => a.sort_order - b.sort_order);
}

export async function optionsForItem(itemId: string): Promise<ItemOptionWithChoices[]> {
  const data = await ensureLoaded();
  return data.item_options
    .filter((o) => o.item_id === itemId)
    .sort((a, b) => a.sort_order - b.sort_order)
    .map((option) => ({
      ...option,
      choices: data.item_option_choices
        .filter((c) => c.option_id === option.id)
        .sort((a, b) => a.sort_order - b.sort_order),
    }));
}

/** Overview payloads, unpacked from the generated tuples. */
export async function kpisFor(days: RangeDays): Promise<PlatformKpis | undefined> {
  const data = await ensureLoaded();
  return data.overview.kpis[String(days)];
}

export async function seriesFor(days: RangeDays): Promise<DailySeriesRow[]> {
  const data = await ensureLoaded();
  return (data.overview.series[String(days)] ?? []).map(toSeriesRow);
}

export async function trendingItems(): Promise<TrendingItem[]> {
  const data = await ensureLoaded();
  return data.overview.trending.map(toTrendingItem);
}

export async function recentOrders(): Promise<RecentOrder[]> {
  const data = await ensureLoaded();
  return data.overview.recent_orders.map(toRecentOrder);
}
// Writes
// ---------------------------------------------------------------------------

/** Thrown for the same reasons Postgres would reject the statement. */
export class DemoValidationError extends Error {
  readonly messageAr: string;

  constructor(
    readonly code: string,
    messageEn: string,
    messageAr: string,
  ) {
    super(messageEn);
    this.name = 'DemoValidationError';
    this.messageAr = messageAr;
  }
}

function nowIso(): string {
  return new Date().toISOString();
}

/**
 * Ids for browser-created rows.
 *
 * crypto.randomUUID is used rather than a counter so two rows created in the
 * same millisecond cannot collide, and so a created row's id is visibly not part
 * of the generated id space.
 */
function newId(): string {
  if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) return crypto.randomUUID();
  // Fallback for a non-secure context. Still unique enough for a local overlay.
  return `demo-${Math.random().toString(36).slice(2)}-${overlay.newItems.length + overlay.newMerchants.length}`;
}

/**
 * Enforce the constraints the database enforces, so the demo rejects the same
 * edits Postgres would.
 *
 * This is the whole value of modelling the database rather than the API: an
 * invalid value cannot be typed into the demo and then discovered on deploy.
 */
function assertValidDiscount(price: number, discount: number | null | undefined) {
  if (discount === null || discount === undefined) return;
  if (!(discount >= 0)) {
    throw new DemoValidationError(
      'DISCOUNT_NEGATIVE',
      'Discount price cannot be negative.',
      'لا يمكن أن يكون سعر الخصم سالبًا.',
    );
  }
  if (!(discount <= price)) {
    throw new DemoValidationError(
      'DISCOUNT_ABOVE_PRICE',
      'Discount price cannot be higher than the price.',
      'لا يمكن أن يكون سعر الخصم أعلى من السعر.',
    );
  }
}

export async function createMerchant(input: MerchantInput): Promise<Merchant> {
  await ensureLoaded();
  const now = nowIso();
  const merchant: Merchant = {
    ...input,
    id: newId(),
    logo_url: null,
    cover_url: null,
    // A new merchant arrives unreviewed AND unpublished. Defaulting to
    // 'approved' would put a vendor on the platform that Ops never looked at,
    // which is the opposite of what approval_status is for.
    //
    // is_active must be false to match admin-api's handleMerchantCreate. It was
    // true here, which meant a merchant created in the demo was live to
    // customers while the same merchant created through the API was not — and
    // the customer feed filters on is_active alone, so demo showed unreviewed
    // vendors to customers. Demo exists to make behaviour visible, so it
    // must not disagree with the code it stands in for.
    approval_status: 'pending',
    approval_note: null,
    is_active: false,
    rating: 0,
    rating_count: 0,
    created_at: now,
    updated_at: now,
  };
  overlay.newMerchants = [...overlay.newMerchants, merchant];
  writeOverlay(overlay);
  return merchant;
}

export async function updateMerchant(
  id: string,
  patch: Partial<Merchant>,
): Promise<Merchant | undefined> {
  await ensureLoaded();
  const existing = await getMerchant(id);
  if (!existing) return undefined;

  const next = { ...patch, updated_at: nowIso() };
  const isNew = overlay.newMerchants.some((m) => m.id === id);
  if (isNew) {
    overlay.newMerchants = overlay.newMerchants.map((m) => (m.id === id ? { ...m, ...next } : m));
  } else {
    overlay.merchantPatches[id] = { ...overlay.merchantPatches[id], ...next };
  }
  writeOverlay(overlay);
  return getMerchant(id);
}

export async function createCategory(
  merchantId: string,
  input: CategoryInput,
): Promise<Category> {
  await ensureLoaded();
  const now = nowIso();
  const category: Category = {
    ...input,
    id: newId(),
    merchant_id: merchantId,
    icon: null,
    is_available: true,
    created_at: now,
    updated_at: now,
    deleted_at: null,
  };
  overlay.newCategories = [...overlay.newCategories, category];
  writeOverlay(overlay);
  return category;
}

export async function updateCategory(
  id: string,
  patch: Partial<Category>,
): Promise<Category | undefined> {
  await ensureLoaded();
  const existing = await getCategory(id);
  if (!existing) return undefined;

  const next = { ...patch, updated_at: nowIso() };
  const isNew = overlay.newCategories.some((c) => c.id === id);
  if (isNew) {
    overlay.newCategories = overlay.newCategories.map((c) => (c.id === id ? { ...c, ...next } : c));
  } else {
    overlay.categoryPatches[id] = { ...overlay.categoryPatches[id], ...next };
  }
  writeOverlay(overlay);
  return getCategory(id);
}

export async function createItem(
  categoryId: string,
  merchantId: string,
  input: ItemInput,
): Promise<Item> {
  await ensureLoaded();
  assertValidDiscount(input.price, input.discount_price);
  const now = nowIso();
  const item: Item = {
    ...input,
    id: newId(),
    merchant_id: merchantId,
    category_id: categoryId,
    popularity_score: 0,
    created_at: now,
    updated_at: now,
    deleted_at: null,
  };
  overlay.newItems = [...overlay.newItems, item];
  writeOverlay(overlay);
  return item;
}

export async function updateItem(
  id: string,
  patch: Partial<Item>,
): Promise<Item | undefined> {
  await ensureLoaded();
  const existing = await getItem(id);
  if (!existing) return undefined;

  // Validated against the POST-update price, not the current one: raising a
  // price must not be blocked by a discount that was already in range.
  assertValidDiscount(patch.price ?? existing.price, patch.discount_price);

  const next = { ...patch, updated_at: nowIso() };
  const isNew = overlay.newItems.some((i) => i.id === id);
  if (isNew) {
    overlay.newItems = overlay.newItems.map((i) => (i.id === id ? { ...i, ...next } : i));
  } else {
    overlay.itemPatches[id] = { ...overlay.itemPatches[id], ...next };
  }
  writeOverlay(overlay);
  return getItem(id);
}

/**
 * Soft delete. NEVER a hard delete.
 *
 * Migration 110 changed order_items.item_id to ON DELETE SET NULL because the
 * previous CASCADE erased every order line that referenced the item while
 * orders.total survived — leaving revenue that could no longer be reconciled.
 * A dashboard Delete button that issued DELETE would reintroduce exactly that.
 */
export async function softDeleteItem(id: string): Promise<Item | undefined> {
  return updateItem(id, { deleted_at: nowIso() });
}

export async function restoreItem(id: string): Promise<Item | undefined> {
  return updateItem(id, { deleted_at: null });
}

/** Toggle the merchant-controlled availability flag. Not a delete. */
export async function setItemAvailability(
  id: string,
  isAvailable: boolean,
): Promise<Item | undefined> {
  return updateItem(id, { is_available: isAvailable });
}

/**
 * Approval and publication are TWO separate decisions, and the demo enforces
 * the same rules admin-api does so a button that works here behaves identically
 * against the database.
 *
 * The separation is the point: approval is a judgement about the merchant, and
 * publication is a runtime switch. Collapsing them into one toggle is what let
 * unreviewed vendors reach customers, because the customer feed filters on
 * is_active and ignores approval_status entirely.
 */
export type MerchantStateError =
  | 'not_found'
  | 'already_approved'
  | 'already_rejected'
  | 'not_approved'
  | 'already_published'
  | 'not_published'
  | 'note_required';

/**
 * Apply a state transition, or explain why it is illegal.
 *
 * Returns the error code instead of throwing so the UI can show the specific
 * reason — admin-api returns the same codes, and a generic "something went
 * wrong" would hide a real state conflict from the operator.
 */
async function transitionMerchant(
  id: string,
  next: Partial<Pick<Merchant, 'approval_status' | 'approval_note' | 'is_active'>>,
  guard: (current: Merchant) => MerchantStateError | null,
): Promise<{ merchant?: Merchant; error?: MerchantStateError }> {
  await ensureLoaded();
  const current = await getMerchant(id);
  if (!current) return { error: 'not_found' };

  const problem = guard(current);
  if (problem) return { error: problem };

  const updated = await updateMerchant(id, next);
  return updated ? { merchant: updated } : { error: 'not_found' };
}

/** Approve a merchant. Review only — does not publish. */
export async function approveMerchant(
  id: string,
  note?: string,
): Promise<{ merchant?: Merchant; error?: MerchantStateError }> {
  return transitionMerchant(
    id,
    { approval_status: 'approved', approval_note: note ?? null },
    (m) => (m.approval_status === 'approved' ? 'already_approved' : null),
  );
}

/**
 * Withdraw approval.
 *
 * Forces is_active false as well. Leaving a withdrawn merchant published would
 * mean the kill-switch and the judgement disagree, and the customer feed trusts
 * is_active.
 */
export async function unapproveMerchant(
  id: string,
  note?: string,
): Promise<{ merchant?: Merchant; error?: MerchantStateError }> {
  return transitionMerchant(
    id,
    { approval_status: 'pending', approval_note: note ?? null, is_active: false },
    (m) => (m.approval_status === 'pending' ? 'not_approved' : null),
  );
}

/**
 * Reject a merchant. A reason is mandatory.
 *
 * Required because a rejection with no explanation cannot be acted on by the
 * merchant and is indistinguishable from a mistake in the audit log.
 */
export async function rejectMerchant(
  id: string,
  note: string,
): Promise<{ merchant?: Merchant; error?: MerchantStateError }> {
  const reason = note?.trim();
  if (!reason) return { error: 'note_required' };

  return transitionMerchant(
    id,
    { approval_status: 'rejected', approval_note: reason, is_active: false },
    (m) => (m.approval_status === 'rejected' ? 'already_rejected' : null),
  );
}

/**
 * Publish: make the merchant visible to customers.
 *
 * Requires prior approval. This is the guard that matters, and it is the whole
 * reason approval and publication are separate calls.
 */
export async function publishMerchant(
  id: string,
): Promise<{ merchant?: Merchant; error?: MerchantStateError }> {
  return transitionMerchant(
    id,
    { is_active: true },
    (m) => {
      if (m.approval_status !== 'approved') return 'not_approved';
      if (m.is_active) return 'already_published';
      return null;
    },
  );
}

/** Unpublish. Always allowed — it is a kill-switch, not a judgement. */
export async function unpublishMerchant(
  id: string,
): Promise<{ merchant?: Merchant; error?: MerchantStateError }> {
  return transitionMerchant(id, { is_active: false }, (m) =>
    m.is_active ? null : 'not_published',
  );
}