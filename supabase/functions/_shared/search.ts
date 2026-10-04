// Pure logic for the search-catalog Edge Function (Search & Discovery MVP).
//
// Kept dependency-free and side-effect-free so it can be unit-tested directly
// (scripts/verify_search_catalog.ts under Deno) while the Edge Function wires
// it to Supabase/auth/rate-limiting. Mirrors the plan:
// docs/plans/search-discovery-implementation-plan.md §7.1.

// ── Types ──

export interface SearchConfig {
  items: boolean;
  fuzzy: boolean;
  fuzzyThreshold: number;
  suggestions: boolean;
  suggestionsMax: number;
  logging: boolean;
}

export interface SearchRequestBody {
  query?: unknown;
  city?: unknown;
  category?: unknown;
  lat?: unknown;
  lng?: unknown;
  limit?: unknown;
  mode?: unknown;
  merchant_id?: unknown;
  include_suggestions?: unknown;
}

export interface SearchRpcArgs {
  p_query: string;
  p_city: string | null;
  p_category: string | null;
  p_lat: number | null;
  p_lng: number | null;
  p_limit_merchants: number;
  p_limit_items: number;
  p_include_items: boolean;
  p_fuzzy_threshold: number;
  p_merchant_id: string | null;
  p_include_suggestions: boolean;
  p_suggestion_max: number;
}

export interface RankableMerchant {
  is_promoted?: boolean;
  match_tier?: string;
  is_currently_open?: boolean;
  distance_meters?: number | null;
  rating?: number | null;
  rating_count?: number | null;
}

export interface RankableItem {
  match_tier?: string;
  popularity_score?: number | null;
  is_parent_open?: boolean;
  distance_meters?: number | null;
}

// ── Config parsing (platform_config rows → typed config) ──

export const SEARCH_CONFIG_KEYS = [
  'search_items_enabled',
  'search_fuzzy_enabled',
  'search_fuzzy_threshold',
  'search_suggestions_enabled',
  'search_suggestions_max',
  'search_query_logging_enabled',
] as const;

const DEFAULT_SEARCH_CONFIG: SearchConfig = {
  items: true,
  fuzzy: true,
  fuzzyThreshold: 0.3,
  suggestions: true,
  suggestionsMax: 8,
  logging: true,
};

function clamp(n: number, min: number, max: number): number {
  return Math.min(Math.max(n, min), max);
}

/**
 * Parse the batched platform_config rows (values are TEXT, cast here — the
 * same convention place-order uses). Missing rows fall back to defaults so a
 * wiped config degrades to full features, never to a broken search.
 * F4 degradation ladder lives here: fuzzy_threshold ≤ 0 ⇒ fuzzy off.
 */
export function parseSearchConfig(
  rows: Array<{ key: unknown; value: unknown }> | null | undefined,
): SearchConfig {
  const map = new Map<string, string>();
  for (const row of rows ?? []) {
    if (typeof row?.key === 'string' && typeof row?.value === 'string') {
      map.set(row.key, row.value);
    }
  }

  const bool = (key: string, fallback: boolean): boolean => {
    const raw = map.get(key);
    if (raw === undefined) return fallback;
    return raw === 'true';
  };
  const num = (key: string, fallback: number, min: number, max: number): number => {
    const raw = map.get(key);
    if (raw === undefined) return fallback;
    const parsed = Number(raw);
    if (Number.isNaN(parsed)) return fallback;
    return clamp(parsed, min, max);
  };

  const threshold = num('search_fuzzy_threshold', DEFAULT_SEARCH_CONFIG.fuzzyThreshold, 0, 1);
  return {
    items: bool('search_items_enabled', DEFAULT_SEARCH_CONFIG.items),
    fuzzy: bool('search_fuzzy_enabled', DEFAULT_SEARCH_CONFIG.fuzzy) && threshold > 0,
    fuzzyThreshold: threshold,
    suggestions: bool('search_suggestions_enabled', DEFAULT_SEARCH_CONFIG.suggestions),
    suggestionsMax: num('search_suggestions_max', DEFAULT_SEARCH_CONFIG.suggestionsMax, 0, 20),
    logging: bool('search_query_logging_enabled', DEFAULT_SEARCH_CONFIG.logging),
  };
}

// ── Config + body → RPC arguments ──

export const MAX_MERCHANTS = 30;
export const MAX_ITEMS = 10;
export const MAX_QUERY_LENGTH = 80;

/**
 * Map the validated request body + parsed config to search_catalog RPC args.
 * Degradation ladder (plan F4):
 *   - search_items_enabled=false ⇒ p_include_items=false (merchants only)
 *   - search_fuzzy_enabled=false ⇒ p_fuzzy_threshold=0 (honest zero results)
 *   - search_suggestions_enabled=false ⇒ p_include_suggestions=false
 */
export function buildSearchRpcArgs(
  body: SearchRequestBody,
  config: SearchConfig,
): SearchRpcArgs {
  const query = typeof body.query === 'string' ? body.query.trim() : '';
  const mode = body.mode === 'merchants' || body.mode === 'items' ? body.mode : 'all';
  const limit =
    typeof body.limit === 'number' && Number.isFinite(body.limit)
      ? clamp(Math.floor(body.limit), 1, MAX_MERCHANTS)
      : 20;
  const lat = typeof body.lat === 'number' && Number.isFinite(body.lat) ? body.lat : null;
  const lng = typeof body.lng === 'number' && Number.isFinite(body.lng) ? body.lng : null;

  return {
    p_query: query,
    p_city: typeof body.city === 'string' && body.city.trim() !== '' ? body.city.trim() : null,
    p_category: typeof body.category === 'string' && body.category !== 'all' ? body.category : null,
    p_lat: lat,
    p_lng: lng,
    p_limit_merchants: limit,
    p_limit_items: MAX_ITEMS,
    p_include_items: mode !== 'merchants' && config.items,
    p_fuzzy_threshold: config.fuzzy ? config.fuzzyThreshold : 0,
    p_merchant_id: typeof body.merchant_id === 'string' && body.merchant_id !== '' ? body.merchant_id : null,
    p_include_suggestions: config.suggestions && body.include_suggestions !== false,
    p_suggestion_max: config.suggestionsMax,
  };
}

// ── Ranking comparators (deterministic, plan §7.1-6) ──

function tierRank(tier?: string): number {
  return tier === 'exact' ? 0 : 1;
}

function distanceRank(distance?: number | null): number {
  // null distance (no geo context) sorts after known distances
  return typeof distance === 'number' && Number.isFinite(distance) ? distance : Number.POSITIVE_INFINITY;
}

/**
 * Merchant ranking: promoted → match tier (exact > fuzzy) → open → distance
 * → rating desc → rating_count desc. Mirrors the feed's promoted→open→
 * distance spine with relevance inserted after promotion (plan DOD-5).
 */
export function compareMerchantResults(a: RankableMerchant, b: RankableMerchant): number {
  const pa = a.is_promoted ? 0 : 1;
  const pb = b.is_promoted ? 0 : 1;
  if (pa !== pb) return pa - pb;

  const ta = tierRank(a.match_tier);
  const tb = tierRank(b.match_tier);
  if (ta !== tb) return ta - tb;

  const oa = a.is_currently_open ? 0 : 1;
  const ob = b.is_currently_open ? 0 : 1;
  if (oa !== ob) return oa - ob;

  const da = distanceRank(a.distance_meters);
  const db = distanceRank(b.distance_meters);
  if (da !== db) return da - db;

  const ra = typeof a.rating === 'number' ? a.rating : 0;
  const rb = typeof b.rating === 'number' ? b.rating : 0;
  if (ra !== rb) return rb - ra;

  const ca = typeof a.rating_count === 'number' ? a.rating_count : 0;
  const cb = typeof b.rating_count === 'number' ? b.rating_count : 0;
  return cb - ca;
}

/**
 * Item ranking: match tier → popularity_score desc → parent open → distance.
 */
export function compareItemResults(a: RankableItem, b: RankableItem): number {
  const ta = tierRank(a.match_tier);
  const tb = tierRank(b.match_tier);
  if (ta !== tb) return ta - tb;

  const pa = typeof a.popularity_score === 'number' ? a.popularity_score : 0;
  const pb = typeof b.popularity_score === 'number' ? b.popularity_score : 0;
  if (pa !== pb) return pb - pa;

  const oa = a.is_parent_open ? 0 : 1;
  const ob = b.is_parent_open ? 0 : 1;
  if (oa !== ob) return oa - ob;

  const da = distanceRank(a.distance_meters);
  const db = distanceRank(b.distance_meters);
  return da - db;
}

// ── did-you-mean + suggestions ──

/**
 * "Did you mean" surfaces ONLY when both result lists are empty and the RPC
 * produced a fuzzy candidate (plan F2, EC-11). Any result at all ⇒ null.
 */
export function surfaceDidYouMean(
  merchantCount: number,
  itemCount: number,
  fuzzyTop: unknown,
): string | null {
  if (merchantCount > 0 || itemCount > 0) return null;
  return typeof fuzzyTop === 'string' && fuzzyTop.trim() !== '' ? fuzzyTop : null;
}

/**
 * Suggestion hygiene (belt-and-braces on top of the SQL dedupe):
 * trim, collapse internal whitespace, case-insensitive dedupe, and always
 * exclude the query being typed. Original casing of the first occurrence is
 * preserved for display.
 */
export function normalizeForDedup(s: string): string {
  return s.trim().toLowerCase().replace(/\s+/g, ' ');
}

export function dedupeSuggestions(suggestions: unknown, ownQuery: string): string[] {
  if (!Array.isArray(suggestions)) return [];
  const seen = new Set<string>();
  const own = normalizeForDedup(ownQuery);
  const out: string[] = [];
  for (const raw of suggestions) {
    if (typeof raw !== 'string') continue;
    const trimmed = raw.trim();
    if (trimmed === '') continue;
    const key = normalizeForDedup(trimmed);
    if (key === '' || key === own || seen.has(key)) continue;
    seen.add(key);
    out.push(trimmed);
  }
  return out;
}
