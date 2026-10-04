// Edge Function: search-catalog
// Search & Discovery MVP — docs/plans/search-discovery-implementation-plan.md §7.1.
//
// Single round-trip search over merchants AND items via the search_catalog RPC
// (migration 095), plus promoted slots (search_result/banner only), open
// status, delivery-radius filtering, relevance ranking, did-you-mean,
// suggestions, and fire-and-forget analytics logging.
//
// Structure mirrors get-merchant-feed (CORS → size check → auth → rate limit →
// parse → validate → config → work → respond) so the two endpoints behave
// identically at the edge. get-merchant-feed is intentionally untouched — old
// binaries keep using it (DOD-10).

import { corsResponse, handleOptions } from '../_shared/cors.ts';
import { errorResponse, errorStatus, successResponse } from '../_shared/errors.ts';
import { checkRateLimit, RATE_LIMITS } from '../_shared/rate-limit.ts';
import { getSupabaseAdmin } from '../_shared/supabase.ts';
import { haversineDistanceKm, estimateDeliveryMinutes } from '../_shared/geo.ts';
import { authenticate } from '../_shared/auth.ts';
import { validateSearchRequest, validateRequestSize, formatValidationErrors } from '../_shared/validation.ts';
import { createLogger, generateRequestId } from '../_shared/logger.ts';
import {
  SEARCH_CONFIG_KEYS,
  buildSearchRpcArgs,
  compareItemResults,
  compareMerchantResults,
  dedupeSuggestions,
  parseSearchConfig,
  surfaceDidYouMean,
} from '../_shared/search.ts';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions(req);

  const requestId = generateRequestId();
  const log = createLogger({ requestId, functionName: 'search-catalog' });

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

    // Auth: require customer (same as feed)
    const authResult = await authenticate(req.headers.get('Authorization'));
    if (authResult.error) {
      log.warn('Auth failed', { code: authResult.error.error.code });
      return corsResponse(authResult.error, errorStatus(authResult.error.error.code), undefined, req);
    }
    const userId = authResult.data!.userId;

    // Rate limit: SEARCH 30/min/customer
    const rlKey = `search:${userId}`;
    const rl = checkRateLimit(rlKey, RATE_LIMITS.SEARCH);
    if (!rl.allowed) {
      log.warn('Rate limited', { userId, retryAfterMs: rl.retryAfterMs });
      return corsResponse(errorResponse('RATE_LIMITED', undefined, 429), 429, { 'Retry-After': String(Math.ceil(rl.retryAfterMs / 1000)) }, req);
    }

    // Parse request body
    const rawBody = await req.text();
    let body: Record<string, unknown>;
    try {
      body = JSON.parse(rawBody);
    } catch {
      log.warn('Invalid JSON body');
      return corsResponse(errorResponse('VALIDATION_ERROR', { message_en: 'Invalid JSON in request body' }), 400, undefined, req);
    }

    // === INPUT VALIDATION ===
    const validation = validateSearchRequest(body);
    if (!validation.valid) {
      log.warn('Validation failed', { errors: validation.errors });
      return corsResponse(
        errorResponse('VALIDATION_ERROR', { message_en: formatValidationErrors(validation.errors) }),
        400,
        undefined,
        req,
      );
    }

    const supabase = getSupabaseAdmin();

    // === BATCHED PLATFORM CONFIG (F4 degradation ladder) ===
    const { data: configRows } = await supabase
      .from('platform_config')
      .select('key, value')
      .in('key', [...SEARCH_CONFIG_KEYS]);
    const config = parseSearchConfig(configRows);

    // === RPC + PROMOTED SLOTS (independent → concurrent) ===
    const rpcArgs = buildSearchRpcArgs(body, config);
    const nowIso = new Date().toISOString();
    const [rpcResult, slotsResult] = await Promise.all([
      supabase.rpc('search_catalog', rpcArgs),
      supabase
        .from('promoted_slots')
        .select('id, merchant_id, slot_type, image_url')
        .eq('is_active', true)
        .lte('starts_at', nowIso)
        .gte('expires_at', nowIso)
        .in('slot_type', ['search_result', 'banner']),
    ]);

    if (rpcResult.error) {
      log.error('search_catalog RPC failed', { error: rpcResult.error.message });
      return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
    }
    // Slots failing is non-fatal — search works un-promoted.
    if (slotsResult.error) {
      log.warn('Promoted slots query failed', { error: slotsResult.error.message });
    }

    const rpcData = (rpcResult.data ?? {}) as Record<string, unknown>;
    const rawMerchants = (Array.isArray(rpcData.merchants) ? rpcData.merchants : []) as Array<Record<string, unknown>>;
    const rawItems = (Array.isArray(rpcData.items) ? rpcData.items : []) as Array<Record<string, unknown>>;
    const banners = (Array.isArray(slotsResult.data) ? slotsResult.data : []) as Array<{ id: string; merchant_id: string }>;
    const promotedMerchantIds = new Set(banners.map((b) => b.merchant_id));

    const userLat = typeof rpcArgs.p_lat === 'number' ? rpcArgs.p_lat : null;
    const userLng = typeof rpcArgs.p_lng === 'number' ? rpcArgs.p_lng : null;

    // === OPEN STATUS (Cairo day/time — same computation as the feed) ===
    const merchantIds = Array.from(new Set([
      ...rawMerchants.map((m) => String(m.id)),
      ...rawItems.map((i) => String(i.merchant_id)),
    ]));
    const openStatusMap = new Map<string, boolean>();
    if (merchantIds.length > 0) {
      const now = new Date();
      const cairoOffset = 2; // UTC+2 (simplified — DST handled by DB function)
      const cairoNow = new Date(now.getTime() + cairoOffset * 60 * 60 * 1000);
      const currentDay = cairoNow.getDay() === 0 ? 7 : cairoNow.getDay(); // ISO: 1=Mon, 7=Sun
      const currentTime = cairoNow.toTimeString().slice(0, 8); // HH:MM:SS

      const { data: operatingHours } = await supabase
        .from('operating_hours')
        .select('merchant_id, day_of_week, open_time, close_time, is_closed')
        .in('merchant_id', merchantIds);
      if (operatingHours) {
        for (const oh of operatingHours as Array<{ merchant_id: string; day_of_week: number; open_time: string; close_time: string; is_closed: boolean }>) {
          if (oh.day_of_week === currentDay && !oh.is_closed) {
            openStatusMap.set(oh.merchant_id, currentTime >= oh.open_time && currentTime < oh.close_time);
          }
        }
      }
    }

    // === MERCHANT ENRICHMENT: distance, delivery-radius exclusion, promotion ===
    const merchants = rawMerchants
      .map((m) => {
        const lat = Number(m.lat);
        const lng = Number(m.lng);
        const radiusKm = Number(m.delivery_radius_km ?? 10);
        const distanceKm = userLat != null && userLng != null
          ? haversineDistanceKm(userLat, userLng, lat, lng)
          : null;
        // Authoritative radius exclusion (bbox in the RPC is only a pre-filter)
        if (distanceKm != null && distanceKm > radiusKm) return null;
        const isPromoted = promotedMerchantIds.has(String(m.id));
        return {
          ...m,
          is_currently_open: openStatusMap.get(String(m.id)) ?? false,
          distance_meters: distanceKm != null ? Math.round(distanceKm * 1000) : null,
          estimated_delivery_time_minutes: distanceKm != null ? estimateDeliveryMinutes(distanceKm) : null,
          is_promoted: isPromoted,
          promoted_position: isPromoted ? 0 : null,
        };
      })
      .filter((m): m is NonNullable<typeof m> => m !== null);

    // === ITEM ENRICHMENT: same radius rules via parent-merchant coords ===
    const items = rawItems
      .map((i) => {
        const lat = Number(i.merchant_lat);
        const lng = Number(i.merchant_lng);
        const radiusKm = Number(i.merchant_delivery_radius_km ?? 10);
        const distanceKm = userLat != null && userLng != null
          ? haversineDistanceKm(userLat, userLng, lat, lng)
          : null;
        if (distanceKm != null && distanceKm > radiusKm) return null;
        const isPromoted = promotedMerchantIds.has(String(i.merchant_id));
        return {
          id: i.id,
          merchant_id: i.merchant_id,
          name_ar: i.name_ar,
          name_en: i.name_en,
          price: i.price,
          image_url: i.image_url,
          popularity_score: i.popularity_score,
          match_tier: i.match_tier,
          merchant_name_ar: i.merchant_name_ar,
          merchant_name_en: i.merchant_name_en,
          is_parent_open: openStatusMap.get(String(i.merchant_id)) ?? false,
          distance_meters: distanceKm != null ? Math.round(distanceKm * 1000) : null,
          estimated_delivery_time_minutes: distanceKm != null ? estimateDeliveryMinutes(distanceKm) : null,
          is_promoted: isPromoted,
        };
      })
      .filter((i): i is NonNullable<typeof i> => i !== null);

    // === RANKING (deterministic; pure comparators in _shared/search.ts) ===
    merchants.sort((a, b) => compareMerchantResults(a as never, b as never));
    items.sort((a, b) => compareItemResults(a as never, b as never));

    // === did-you-mean + suggestions ===
    const didYouMean = surfaceDidYouMean(merchants.length, items.length, rpcData.fuzzy_top);
    const suggestions = dedupeSuggestions(rpcData.suggestions, typeof body.query === 'string' ? body.query : '');

    // === ANALYTICS (fire-and-forget; never blocks the response) ===
    if (config.logging) {
      supabase
        .from('search_queries')
        .insert({
          user_id: userId,
          query: typeof body.query === 'string' ? body.query.trim() : '',
          normalized_query: typeof rpcData.normalized_query === 'string' ? rpcData.normalized_query : '',
          city: rpcArgs.p_city,
          category: rpcArgs.p_category,
          merchant_results: merchants.length,
          item_results: items.length,
        })
        .then(({ error: insertError }: { error: { message: string } | null }) => {
          if (insertError) log.warn('Search analytics insert failed', { error: insertError.message });
        });
    }

    // Promoted impression tracking — same fire-and-forget idiom as the feed
    // (promoted_slot_events row + cumulative counter increment).
    if (banners.length > 0) {
      const events = banners.map((b) => ({
        slot_id: b.id,
        event_type: 'impression',
        customer_id: userId,
      }));
      supabase.from('promoted_slot_events').insert(events).then(({ error }: { error: { message: string } | null }) => {
        if (error) log.warn('Impression event insert failed', { error: error.message });
      });
      supabase.rpc('increment_promoted_slot_impressions', { p_slot_ids: banners.map((b) => b.id) }).then(({ error }: { error: { message: string } | null }) => {
        if (error) log.warn('Cumulative impression increment failed', { error: error.message });
      });
    }

    log.info('Search returned', {
      merchants: merchants.length,
      items: items.length,
      match_mode: rpcData.match_mode,
      suggestions: suggestions.length,
    });

    return corsResponse(successResponse({
      merchants,
      items,
      suggestions,
      did_you_mean: didYouMean,
      match_mode: rpcData.match_mode ?? 'none',
    }), 200, {
      // Personalized + rate-limited per user — never cached publicly (unlike
      // the feed's public 30s cache).
      'Cache-Control': 'private, no-store',
    }, req);
  } catch (err) {
    log.error('Unhandled error', { error: err instanceof Error ? err.message : String(err) });
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }
});
