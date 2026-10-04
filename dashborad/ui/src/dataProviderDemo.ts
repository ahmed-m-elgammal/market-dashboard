/**
 * Refine dataProvider backed by the local demo dataset.
 *
 * Same interface as dataProvider.ts (the live REST one), so components are
 * written once against one vocabulary. Swapping VITE_DATA_MODE swaps this
 * module for the REST provider; no component changes.
 *
 * WHY THE OVERVIEW GOES THROUGH HERE TOO
 *   It would be simpler to leave the Overview on the live provider and only mock
 *   the merchants tree. But then "demo mode" would still make four network calls
 *   to Supabase on every load, which defeats the point: the point is that the
 *   whole dashboard can be opened, screenshotted and clicked through with the
 *   network switched off. So all four Overview resources are served locally too,
 *   from aggregates the generator derived from a real synthetic order stream.
 *
 * LATENCY
 *   A tiny artificial delay, so loading states are actually visible. Without it
 *   every query resolves in the same tick, Spinner never shows, and a broken
 *   loading indicator cannot be noticed until it ships.
 */
import type {
  BaseRecord,
  DataProvider,
  DeleteManyParams,
  DeleteManyResponse,
} from '@refinedev/core';
import {
  DEFAULT_RANGE,
  RANGE_OPTIONS,
  TRENDING_WINDOW_DAYS,
  type Category,
  type DailySeriesRow,
  type Item,
  type Merchant,
  type MerchantInput,
  type PlatformKpis,
  type RangeDays,
  type RecentOrder,
  type TrendingItem,
} from './constants';
import * as store from './demo/store';

/** Enough for a spinner to register, short enough not to annoy. */
const LATENCY_MS = 180;

function delay(): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, LATENCY_MS));
}

/** Errors surface with the same shape the live provider throws. */
class DemoApiError extends Error {
  readonly code: string;
  readonly status: number;

  constructor(code: string, messageEn: string, messageAr: string, status: number) {
    super(messageEn);
    this.name = 'DemoApiError';
    this.code = code;
    this.status = status;
    // Attached rather than subclassed per-language: the UI picks a script, the
    // transport does not care which one it is.
    Object.assign(this, { messageAr });
  }
}

/**
 * Clamp a caller-supplied range to one the dataset actually holds.
 *
 * The generated file only contains 7/30/90 because those are the three the
 * segmented control offers. An unknown value falls back to the default rather
 * than erroring, matching admin-api's resolveWindowDays: a dashboard should
 * render on load.
 */
function resolveDays(raw: unknown): RangeDays {
  const n = Number(raw ?? DEFAULT_RANGE);
  return (RANGE_OPTIONS as readonly number[]).includes(n) ? (n as RangeDays) : DEFAULT_RANGE;
}

function clampLimit(raw: unknown, fallback: number, max: number): number {
  const n = Number(raw);
  if (!Number.isFinite(n) || n < 1) return fallback;
  return Math.min(Math.floor(n), max);
}

/** Case-insensitive contains across both name scripts. */
function matches(haystack: string | null, needle: string): boolean {
  return (haystack ?? '').toLowerCase().includes(needle);
}

/**
 * Bilingual messages for an illegal merchant transition.
 *
 * The codes are the same strings admin-api returns, so the UI can key off the
 * code alone and behave identically in demo and live mode. 409 is used for a
 * conflict with the row's current state rather than 400: the request was
 * well-formed, it just conflicts with where the merchant already is, which is
 * what 409 exists for and what tells the client a plain retry will not help.
 */
const MERCHANT_STATE_ERRORS: Record<
  store.MerchantStateError,
  { status: number; en: string; ar: string }
> = {
  not_found: { status: 404, en: 'Merchant not found', ar: 'التاجر غير موجود' },
  already_approved: {
    status: 409,
    en: 'This merchant is already approved',
    ar: 'هذا التاجر معتمد بالفعل',
  },
  already_rejected: {
    status: 409,
    en: 'This merchant is already rejected',
    ar: 'هذا التاجر مرفوض بالفعل',
  },
  not_approved: {
    status: 409,
    en: 'Approve this merchant first',
    ar: 'يجب اعتماد هذا التاجر أولاً',
  },
  already_published: {
    status: 409,
    en: 'This merchant is already published',
    ar: 'هذا التاجر منشور بالفعل',
  },
  not_published: {
    status: 409,
    en: 'This merchant is not currently published',
    ar: 'هذا التاجر غير منشور حالياً',
  },
  note_required: {
    status: 422,
    en: 'A reason is required',
    ar: 'السبب مطلوب',
  },
};

function stateError(code: store.MerchantStateError): DemoApiError {
  const e = MERCHANT_STATE_ERRORS[code];
  return new DemoApiError(code.toUpperCase(), e.en, e.ar, e.status);
}

/** Wrap a thrown DemoValidationError so Refine surfaces it as a failed call. */
async function guard<T>(fn: () => T | Promise<T>): Promise<T> {
  await delay();
  try {
    return await fn();
  } catch (error) {
    if (error instanceof store.DemoValidationError) {
      throw new DemoApiError(error.code, error.message, error.messageAr, 422);
    }
    throw error;
  }
}

// ---------------------------------------------------------------------------
// Derived read shapes
// ---------------------------------------------------------------------------

/** A merchant row with the counts the list and profile screens display. */
interface MerchantRow extends Merchant {
  category_count: number;
  item_count: number;
  /** Items currently not orderable, for the profile's health summary. */
  unavailable_item_count: number;
  deleted_item_count: number;
}

async function merchantRows(): Promise<MerchantRow[]> {
  const categories = await store.allCategories();
  const items = await store.allItems();
  const visibleCategories = categories.filter((c) => c.deleted_at === null);

  return (await store.allMerchants()).map((merchant: Merchant) => {
    const ownCategories = visibleCategories.filter((c: Category) => c.merchant_id === merchant.id);
    const ownItems = items.filter((i: Item) => i.merchant_id === merchant.id);

    return {
      ...merchant,
      category_count: ownCategories.length,
      item_count: ownItems.filter((i: Item) => i.deleted_at === null).length,
      unavailable_item_count: ownItems.filter(
        (i: Item) => i.deleted_at === null && !i.is_available,
      ).length,
      deleted_item_count: ownItems.filter((i: Item) => i.deleted_at !== null).length,
    };
  });
}

/** A category row with the item count the categories screen shows. */
interface CategoryRow extends Category {
  item_count: number;
  unavailable_item_count: number;
}

/** An item row with its category's names, for the items table. */
interface ItemRow extends Item {
  category_name_en: string;
  category_name_ar: string;
  category_deleted_at: string | null;
  merchant_name_en: string;
  merchant_name_ar: string;
}

async function itemRows(categoryId?: string): Promise<ItemRow[]> {
  const categories = new Map(
    (await store.allCategories()).map((c: Category) => [c.id, c]),
  );
  const merchants = new Map(
    (await store.allMerchants()).map((m: Merchant) => [m.id, m]),
  );

  return (await store.allItems())
    .filter((item: Item) => (categoryId === undefined ? true : item.category_id === categoryId))
    .map((item: Item) => {
      const category = categories.get(item.category_id);
      const merchant = merchants.get(item.merchant_id);
      return {
        ...item,
        // Resolved from the CURRENT category row rather than snapshotted, so a
        // renamed category shows its new name on items that reference it.
        category_name_en: category?.name_en ?? '',
        category_name_ar: category?.name_ar ?? '',
        category_deleted_at: category?.deleted_at ?? null,
        merchant_name_en: merchant?.name_en ?? '',
        merchant_name_ar: merchant?.name_ar ?? '',
      };
    });
}

/** Generic filter/sort/page over an in-memory list. */
function query<T>(
  rows: T[],
  options: {
    page?: number;
    pageSize?: number;
    search?: string;
    /** Applied after search, before sorting — so counts stay honest. */
    where?: (row: T) => boolean;
    sortBy?: string;
    sortDir?: 'asc' | 'desc';
  },
): { rows: T[]; total: number } {
  let result = rows;

  if (options.where) result = result.filter(options.where);

  if (options.search) {
    const needle = options.search.toLowerCase();
    result = result.filter((row) => searchPredicate(row, needle));
  }

  if (options.sortBy) {
    const key = options.sortBy as keyof T;
    const dir = options.sortDir === 'asc' ? 1 : -1;
    result = [...result].sort((a, b) => {
      const av = a[key];
      const bv = b[key];
      if (av === bv) return 0;
      if (av === null || av === undefined) return 1; // nulls last either way
      if (bv === null || bv === undefined) return -1;
      if (typeof av === 'number' && typeof bv === 'number') return (av - bv) * dir;
      return String(av).localeCompare(String(bv)) * dir;
    });
  }

  const total = result.length;
  const pageSize = options.pageSize && options.pageSize > 0 ? options.pageSize : total;
  const current = Math.max(0, (options.page ?? 1) - 1);
  return { rows: result.slice(current * pageSize, current * pageSize + pageSize), total };
}

/**
 * Read the active sort from Refine's `sorters`, falling back to `meta`.
 *
 * Refine types a sorter field as BaseKey (string | number), but a column name is
 * always a string in this dataset, so the narrowing happens once here instead of
 * at each of the three call sites.
 */
function sortFrom(
  sorters: { field: string | number; order?: 'asc' | 'desc' }[] | undefined,
  meta: Record<string, unknown>,
): { sortBy?: string; sortDir?: 'asc' | 'desc' } {
  const field = sorters?.[0]?.field ?? meta.sortBy;
  const order = sorters?.[0]?.order ?? meta.sortDir;
  return {
    sortBy: field === undefined || field === null ? undefined : String(field),
    sortDir: order === 'asc' || order === 'desc' ? order : undefined,
  };
}

/**
 * Which text fields a free-text search looks at.
 *
 * Spelled out per entity rather than reflected over the object: a generic
 * "search every string field" would also match a phone number, a UUID or a
 * timestamp fragment, so typing "20" would return every row.
 */
function searchPredicate(row: unknown, needle: string): boolean {
  if (typeof row !== 'object' || row === null) return false;
  const r = row as Record<string, unknown>;

  const MERCHANT_FIELDS = ['name_en', 'name_ar', 'city', 'area', 'address', 'phone', 'category'];
  const CATEGORY_FIELDS = ['name_en', 'name_ar'];
  const ITEM_FIELDS = ['name_en', 'name_ar', 'description_en', 'description_ar', 'id'];

  const fields = MERCHANT_FIELDS.some((f) => f in r)
    ? MERCHANT_FIELDS
    : CATEGORY_FIELDS.some((f) => f in r)
      ? CATEGORY_FIELDS
      : ITEM_FIELDS;

  return fields.some((f) => matches(r[f] as string | null, needle));
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

export const demoDataProvider: DataProvider = {
  getApiUrl: () => 'demo://local',

  async getList({ resource, pagination, meta, sorters }) {
    const m = (meta ?? {}) as Record<string, unknown>;
    const page = pagination?.current ?? 1;
    const pageSize = pagination?.pageSize ?? 20;

    switch (resource) {
      // -- Overview -------------------------------------------------------
      case 'overview-kpis': {
        const row = await store.kpisFor(resolveDays(m.days));
        if (!row) throw new DemoApiError('NO_DATA', 'No dataset generated', 'لا توجد بيانات', 404);
        return { data: [row as PlatformKpis] as never, total: 1 };
      }

      case 'overview-series': {
        const rows = await store.seriesFor(resolveDays(m.days));
        return { data: rows as DailySeriesRow[] as never, total: rows.length };
      }

      case 'overview-trending': {
        // Trending is a fixed 7-day window by product decision, matching the
        // Overview's subtitle. A caller cannot widen it.
        void TRENDING_WINDOW_DAYS;
        const rows = (await store.trendingItems()).slice(0, clampLimit(m.limit, 10, 100));
        return { data: rows as TrendingItem[] as never, total: rows.length };
      }

      case 'overview-recent-orders': {
        const rows = (await store.recentOrders()).slice(0, clampLimit(m.limit, 10, 100));
        return { data: rows as RecentOrder[] as never, total: rows.length };
      }

      // -- Merchants ------------------------------------------------------
      case 'merchants': {
        // merchantRows() is async because the corpus is lazy-loaded, so the rows
        // are materialised BEFORE guard() wraps the (synchronous) filter/sort/page
        // step. guard exists to convert a thrown DemoValidationError into a
        // rejected Refine call; nothing in a read path throws one, and passing
        // an async thunk through it would put an await inside a non-async
        // arrow.
        const all = await merchantRows();
        const { rows, total } = await guard(() =>
          query(all, {
            page,
            pageSize,
            search: m.search as string | undefined,
            where: m.approval_status
              ? (row) => row.approval_status === m.approval_status
              : m.city
                ? (row) => row.city === m.city
                : undefined,
            sortBy: sortFrom(sorters, m).sortBy,
            sortDir: sortFrom(sorters, m).sortDir,
          }),
        );
        return { data: rows as never, total };
      }

      case 'merchant-categories': {
        const merchantId = String(m.merchantId ?? '');
        if (!(await store.getMerchant(merchantId))) {
          throw new DemoApiError('NOT_FOUND', 'Merchant not found', 'التاجر غير موجود', 404);
        }
        const items = await store.allItems();
        const categories = (
          await store.categoriesForMerchant(merchantId)
        ).map((category: Category) => {
            const own = items.filter((i) => i.category_id === category.id);
            return {
              ...category,
              item_count: own.filter((i: Item) => i.deleted_at === null).length,
              unavailable_item_count: own.filter(
                (i: Item) => i.deleted_at === null && !i.is_available,
              ).length,
            } satisfies CategoryRow;
          });

        const { rows, total } = query(categories, {
          page,
          pageSize,
          search: m.search as string | undefined,
          // Live categories only unless the caller asks otherwise. Migration 110
          // makes deleted_at the hide switch, so a default that ignores it would
          // surface retired categories as though nothing happened to them.
          where: m.includeDeleted ? undefined : (row) => row.deleted_at === null,
          sortBy: sortFrom(sorters, m).sortBy,
          sortDir: sortFrom(sorters, m).sortDir,
        });
        return { data: rows as never, total };
      }

      case 'category-items': {
        const categoryId = String(m.categoryId ?? '');
        const category = await store.getCategory(categoryId);
        if (!category) {
          throw new DemoApiError('NOT_FOUND', 'Category not found', 'التصنيف غير موجود', 404);
        }

        // isAvailableFilter is a THREE-way choice, not a boolean:
        //   'all'          every row
        //   'available'    live and orderable
        //   'unavailable'  live but sold out
        //   'deleted'      retired
        //   'live'         live whether orderable or not (the default)
        // A single `showDeleted` flag cannot express "show me the sold-out ones
        // but not the deleted ones", which is the question an operator actually
        // asks when investigating a menu problem.
        const stateFilter = (m.state as string | undefined) ?? 'live';
        const whereByState: Record<string, (row: ItemRow) => boolean> = {
          all: () => true,
          live: (row) => row.deleted_at === null,
          available: (row) => row.deleted_at === null && row.is_available,
          unavailable: (row) => row.deleted_at === null && !row.is_available,
          deleted: (row) => row.deleted_at !== null,
        };
        const stateWhere = whereByState[stateFilter];

        const { rows, total } = query(await itemRows(categoryId), {
          page,
          pageSize,
          search: m.search as string | undefined,
          where: stateWhere,
          sortBy: sortFrom(sorters, m).sortBy,
          sortDir: sortFrom(sorters, m).sortDir,
        });
        return { data: rows as never, total };
      }

      default:
        throw new DemoApiError(
          'UNMAPPED_RESOURCE',
          `No demo dataset is mapped for "${resource}"`,
          `لا توجد بيانات تجريبية للمورد "${resource}"`,
          501,
        );
    }
  },

  async getOne({ resource, id }) {
    switch (resource) {
      case 'merchants': {
        const row = (await merchantRows()).find((x: MerchantRow) => x.id === id);
        if (!row) throw new DemoApiError('NOT_FOUND', 'Merchant not found', 'التاجر غير موجود', 404);
        return { data: row as never };
      }

      case 'items': {
        const item = (await itemRows()).find((x: ItemRow) => x.id === id);
        if (!item) throw new DemoApiError('NOT_FOUND', 'Item not found', 'الصنف غير موجود', 404);
        // The option groups are nested in rather than fetched separately: the
        // item screen cannot render without them, so a second round trip would
        // only add a flash of empty state between two things that always load
        // together.
        return {
          data: { ...item, options: await store.optionsForItem(String(id)) } as never,
        };
      }

      case 'category-items': {
        const row = (await itemRows()).find((x: ItemRow) => x.id === id);
        if (!row) throw new DemoApiError('NOT_FOUND', 'Item not found', 'الصنف غير موجود', 404);
        return { data: row as never };
      }

      default:
        throw new DemoApiError(
          'UNMAPPED_RESOURCE',
          `No demo dataset is mapped for "${resource}"`,
          `لا توجد بيانات تجريبية للمورد "${resource}"`,
          501,
        );
    }
  },

  // -- Writes ------------------------------------------------------------

  async create({ resource, variables }) {
    const v = variables as Record<string, unknown>;

    switch (resource) {
      case 'merchants': {
        const merchant = await guard(() =>
          store.createMerchant(v as unknown as MerchantInput),
        );
        return { data: merchant as never };
      }

      case 'category-items': {
        const categoryId = String(v.category_id ?? '');
        const category = await store.getCategory(categoryId);
        if (!category) {
          throw new DemoApiError('NOT_FOUND', 'Category not found', 'التصنيف غير موجود', 404);
        }
        const { category_id, ...rest } = v;
        const item = await guard(() =>
          store.createItem(categoryId, category.merchant_id, rest as never),
        );
        return { data: item as never };
      }

      default:
        throw new DemoApiError(
          'NOT_IMPLEMENTED',
          `"${resource}" cannot be created in the demo yet`,
          `لا يمكن إنشاء "${resource}" في الوضع التجريبي بعد`,
          501,
        );
    }
  },

  async update({ resource, id, variables }) {
    const v = variables as Record<string, unknown>;
    const action = v.action;

    if (resource === 'merchants' && action) {
      const merchantId = String(id);
      const note = v.note as string | undefined;

      const result = await guard(async () => {
        switch (action) {
          case 'approve':
            return store.approveMerchant(merchantId, note);
          case 'unapprove':
            return store.unapproveMerchant(merchantId, note);
          case 'reject':
            return store.rejectMerchant(merchantId, note ?? '');
          case 'publish':
            return store.publishMerchant(merchantId);
          case 'unpublish':
            return store.unpublishMerchant(merchantId);
          default:
            throw new DemoApiError(
              'NOT_IMPLEMENTED',
              `Unknown merchant action "${String(action)}"`,
              `إجراء تاجر غير معروف "${String(action)}"`,
              501,
            );
        }
      });

      if (result.error) throw stateError(result.error);
      return { data: result.merchant as never };
    }

    switch (resource) {
      case 'merchants': {
        const patch = { ...v };
        // Never let a client set the state-machine columns through a plain
        // update. Approval and publication go through the guarded transitions
        // below; a raw write here would bypass the publish-requires-approval
        // check that the whole feature depends on.
        delete patch.action;
        delete patch.note;
        delete patch.approval_status;
        delete patch.is_active;
        delete patch.approval_note;

        const row = await guard(() => store.updateMerchant(String(id), patch as never));
        if (!row) throw new DemoApiError('NOT_FOUND', 'Merchant not found', 'التاجر غير موجود', 404);
        return { data: row as never };
      }

      case 'items':
      case 'category-items': {
        const row = await guard(() => store.updateItem(String(id), v as never));
        if (!row) throw new DemoApiError('NOT_FOUND', 'Item not found', 'الصنف غير موجود', 404);
        return { data: row as never };
      }

      default:
        throw new DemoApiError(
          'NOT_IMPLEMENTED',
          `"${resource}" cannot be updated in the demo yet`,
          `لا يمكن تحديث "${resource}" في الوضع التجريبي بعد`,
          501,
        );
    }
  },

  /**
   * "Delete" is a SOFT delete.
   *
   * The resource name is kept because that is what the UI calls, but the action
   * is a `deleted_at` timestamp — never a DELETE. See store.softDeleteItem for
   * why a hard delete would destroy revenue history.
   */
  async deleteOne({ resource, id }) {
    switch (resource) {
      case 'items':
      case 'category-items': {
        const row = await guard(() => store.softDeleteItem(String(id)));
        if (!row) throw new DemoApiError('NOT_FOUND', 'Item not found', 'الصنف غير موجود', 404);
        return { data: row as never };
      }

      default:
        throw new DemoApiError(
          'NOT_IMPLEMENTED',
          `"${resource}" cannot be deleted in the demo yet`,
          `لا يمكن حذف "${resource}" في الوضع التجريبي بعد`,
          501,
        );
    }
  },

  async deleteMany<TData extends BaseRecord, TVariables>({
    resource,
    ids,
  }: DeleteManyParams<TVariables>): Promise<DeleteManyResponse<TData>> {
    // Sequential rather than concurrent: every call writes the same localStorage
    // blob, and parallel writes would race and drop edits.
    for (const id of ids ?? []) {
      await this.deleteOne({ resource, id });
    }
    return { data: ((ids ?? []) as unknown) as TData[] };
  },
};