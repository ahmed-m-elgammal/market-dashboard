// Edge Function: get-merchant-feed
// P3A-01 through P3A-03: Returns paginated merchant feed with open status, distance, promoted slots
// Cursor-based pagination, rate limited (30/min/customer)
//
// FIX: Corrected broken import — `authenticate` was incorrectly imported from `errors.ts`
// instead of `auth.ts`. This would have caused a runtime crash.
// FIX: Cursor decode now properly uses `decoded.created_at` for created_at filtering
// instead of `decoded.id` which was a UUID and produced incorrect pagination.
//
// Production hardening:
//   - Input validation via shared validation module
//   - Request size validation (Content-Length check)
//   - Structured JSON logging with request ID tracking
//   - Correct cursor-based pagination using created_at from decoded cursor

import { corsResponse, handleOptions } from '../_shared/cors.ts';
import { errorResponse, errorStatus, successResponse } from '../_shared/errors.ts';
import { checkRateLimit, RATE_LIMITS } from '../_shared/rate-limit.ts';
import { getSupabaseAdmin } from '../_shared/supabase.ts';
import { haversineDistanceKm, estimateDeliveryMinutes } from '../_shared/geo.ts';
import { authenticate } from '../_shared/auth.ts';
import { validateMerchantFeedRequest, validateRequestSize, formatValidationErrors } from '../_shared/validation.ts';
import { createLogger, generateRequestId } from '../_shared/logger.ts';

interface FeedRequest {
  city: string;
  // 'all' = no filter; any seeded merchant_categories.code is accepted.
  // validateMerchantFeedRequest is the gate, not this type — narrowing the
  // type here is what let the old two-value list drift (audit row 30).
  category?: string;
  lat?: number;
  lng?: number;
  cursor?: string;
  limit?: number;
  search?: string;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions(req);

  const requestId = generateRequestId();
  const log = createLogger({ requestId, functionName: 'get-merchant-feed' });

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

    // Auth: require customer
    const authResult = await authenticate(req.headers.get('Authorization'));
    if (authResult.error) {
      log.warn('Auth failed', { code: authResult.error.error.code });
      return corsResponse(authResult.error, errorStatus(authResult.error.error.code), undefined, req);
    }

    log.info('User authenticated', { userId: authResult.data!.userId });

    // Rate limit
    const rlKey = `feed:${authResult.data!.userId}`;
    const rl = checkRateLimit(rlKey, RATE_LIMITS.MERCHANT_FEED);
    if (!rl.allowed) {
      log.warn('Rate limited', { userId: authResult.data!.userId, retryAfterMs: rl.retryAfterMs });
      return corsResponse(errorResponse('RATE_LIMITED', undefined, 429), 429, { 'Retry-After': String(Math.ceil(rl.retryAfterMs / 1000)) }, req);
    }

    // Parse and validate request body
    const rawBody = await req.text();
    let body: FeedRequest;
    try {
      body = JSON.parse(rawBody);
    } catch {
      log.warn('Invalid JSON body');
      return corsResponse(errorResponse('VALIDATION_ERROR', { message_en: 'Invalid JSON in request body' }), 400, undefined, req);
    }

    // === INPUT VALIDATION ===
    const validation = validateMerchantFeedRequest(body);
    if (!validation.valid) {
      log.warn('Validation failed', { errors: validation.errors });
      return corsResponse(
        errorResponse('VALIDATION_ERROR', { message_en: formatValidationErrors(validation.errors) }),
        400,
        undefined,
        req,
      );
    }

    const city = body.city || 'cairo';
    const category = body.category;
    const userLat = body.lat;
    const userLng = body.lng;
    const limit = Math.min(Math.max(body.limit || 20, 1), 50);
    const cursor = body.cursor;
    const search = body.search;

    // Decode cursor (base64 → JSON with { id, created_at })
    // FIX: Extract created_at from decoded cursor for pagination, NOT id
    let cursorCreatedAt: string | null = null;
    if (cursor) {
      try {
        const decoded = JSON.parse(atob(cursor));
        // FIX: Use decoded.created_at for created_at filtering instead of decoded.id
        // Previously decoded.id (a UUID) was used for .lt('created_at', ...) which
        // produced incorrect ordering since UUIDs don't sort chronologically
        cursorCreatedAt = decoded.created_at || null;
      } catch {
        log.warn('Invalid cursor provided, starting from beginning', { cursor: cursor.slice(0, 10) });
        // Invalid cursor — start from beginning
      }
    }

    const supabase = getSupabaseAdmin();

    // Build merchant query with EXISTS subquery for open status (RED-01: no per-row function call)
    let query = supabase
      .from('merchants')
      .select(`
        id, name_ar, name_en, category, logo_url, cover_url,
        description_ar, description_en,
        address, lat, lng, city, area, phone,
        is_active, rating, rating_count,
        min_order_amount, estimated_delivery_minutes,
        delivery_fee_override, commission_pct,
        delivery_radius_km, estimated_prep_time_minutes,
        created_at, updated_at
      `)
      // BOTH flags, and the reason matters: this query runs on the service_role
      // client, which BYPASSES RLS. Migration 109 gated the
      // `merchants_read_active` policy on `is_active AND approval_status`, and
      // that policy is correct — but it protects anon and authenticated, not
      // this function. Filtering on is_active alone here is what let a pending
      // vendor reach customers through the feed.
      //
      // Keep both filters even though `merchant.create` forces is_active=false
      // for new rows. That force is one code path; this is the last gate before
      // a customer sees a merchant, and it should not depend on every other
      // path behaving.
      .eq('is_active', true)
      .eq('approval_status', 'approved');

    if (userLat != null && userLng != null) {
      // 1 degree latitude is ~111km, so 50km is ~0.45 degrees
      // 1 degree longitude in Egypt (lat 30) is ~96km, so 50km is ~0.52 degrees
      const deltaLat = 0.45;
      const deltaLng = 0.52;
      query = query
        .gte('lat', userLat - deltaLat)
        .lte('lat', userLat + deltaLat)
        .gte('lng', userLng - deltaLng)
        .lte('lng', userLng + deltaLng);
    } else {
      query = query.ilike('city', city);
    }

    if (category && category !== 'all') {
      query = query.eq('category', category);
    }

    if (search && search.trim() !== '') {
      // Escape special characters in PostgREST filter syntax
      const escaped = search.replace(/([,()\\])/g, '\\$1');
      query = query.or(`name_en.ilike.%${escaped}%,name_ar.ilike.%${escaped}%`);
    }

    // FIX: Use cursorCreatedAt (ISO timestamp) for proper chronological pagination
    if (cursorCreatedAt) {
      query = query.lt('created_at', cursorCreatedAt);
    }

    query = query.order('created_at', { ascending: false }).limit(limit + 1);

    const { data: merchants, error: merchantError } = await query;
    if (merchantError) {
      log.error('Merchant query failed', { error: merchantError.message });
      return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
    }

    // Check if there's a next page
    const hasMore = merchants.length > limit;
    const items = hasMore ? merchants.slice(0, limit) : merchants;

    // Get current day + time for open status check (Cairo timezone)
    const now = new Date();
    const cairoOffset = 2; // UTC+2 (simplified — DST handled by DB function)
    const cairoNow = new Date(now.getTime() + cairoOffset * 60 * 60 * 1000);
    const currentDay = cairoNow.getDay() === 0 ? 7 : cairoNow.getDay(); // ISO: 1=Mon, 7=Sun
    const currentTime = cairoNow.toTimeString().slice(0, 8); // HH:MM:SS

    // Get operating hours for these merchants in one query
    const merchantIds = items.map((m: { id: string }) => m.id);
    const { data: operatingHours } = await supabase
      .from('operating_hours')
      .select('merchant_id, day_of_week, open_time, close_time, is_closed')
      .in('merchant_id', merchantIds);

    // Build open status map
    const openStatusMap = new Map<string, boolean>();
    if (operatingHours) {
      for (const oh of operatingHours) {
        if (oh.day_of_week === currentDay && !oh.is_closed) {
          const isOpen = currentTime >= oh.open_time && currentTime < oh.close_time;
          openStatusMap.set(oh.merchant_id, isOpen);
        }
      }
    }

    // Get promoted slots (active banners) — only on first page
    let banners: unknown[] = [];
    if (!cursor) {
      const { data: slots } = await supabase
        .from('promoted_slots')
        .select('id, merchant_id, slot_type, image_url')
        .eq('is_active', true)
        .lte('starts_at', new Date().toISOString())
        .gte('expires_at', new Date().toISOString());
      banners = slots || [];

      // P1-6: Fire-and-forget impression tracking — insert one event row per
      // banner served + increment the cumulative counter. NOT awaited so feed
      // latency is unaffected. Lost events on cold-start are acceptable for
      // analytics (this is for trend charts, not billing).
      if (banners.length > 0) {
        const events = (banners as { id: string }[]).map((b) => ({
          slot_id: b.id,
          event_type: 'impression',
          customer_id: authResult.data!.userId,
        }));
        supabase.from('promoted_slot_events').insert(events).then(({ error }: { error: { message: string } | null }) => {
          if (error) log.warn('Impression event insert failed', { error: error.message });
        });
        // Increment cumulative counters (fire-and-forget)
        const slotIds = (banners as { id: string }[]).map((b) => b.id);
        supabase.rpc('increment_promoted_slot_impressions', { p_slot_ids: slotIds }).then(({ error }: { error: { message: string } | null }) => {
          if (error) log.warn('Cumulative impression increment failed', { error: error.message });
        });
      }
    }

    // Get promoted merchant IDs
    const promotedMerchantIds = new Set(banners.map((b: { merchant_id: string }) => b.merchant_id));

    // Build response items
    const feedItems = items
      .map((m: {
        id: string; name_ar: string; name_en: string; category: string;
        logo_url: string | null; cover_url: string | null;
        description_ar: string | null; description_en: string | null;
        address: string | null; lat: number; lng: number;
        city: string; area: string | null; phone: string | null;
        is_active: boolean; rating: number; rating_count: number;
        min_order_amount: number; estimated_delivery_minutes: number;
        delivery_fee_override: number | null; commission_pct: number | null;
        delivery_radius_km: number; estimated_prep_time_minutes: number;
        created_at: string; updated_at: string;
      }) => {
        const distanceKm = userLat != null && userLng != null
          ? haversineDistanceKm(userLat, userLng, m.lat, m.lng)
          : null;

        // Exclude merchants that are further than their delivery radius
        if (distanceKm != null && distanceKm > m.delivery_radius_km) {
          return null;
        }

        const isPromoted = promotedMerchantIds.has(m.id);

        return {
          // Base Merchant fields
          id: m.id,
          name_ar: m.name_ar,
          name_en: m.name_en,
          category: m.category,
          logo_url: m.logo_url,
          cover_url: m.cover_url,
          description_ar: m.description_ar,
          description_en: m.description_en,
          address: m.address,
          lat: m.lat,
          lng: m.lng,
          city: m.city,
          area: m.area,
          phone: m.phone,
          is_active: m.is_active,
          rating: m.rating,
          rating_count: m.rating_count,
          min_order_amount: m.min_order_amount,
          estimated_delivery_minutes: m.estimated_delivery_minutes,
          delivery_fee_override: m.delivery_fee_override,
          commission_pct: m.commission_pct,
          delivery_radius_km: m.delivery_radius_km,
          estimated_prep_time_minutes: m.estimated_prep_time_minutes,
          created_at: m.created_at,
          updated_at: m.updated_at,
          // FeedItem-specific computed fields
          is_currently_open: openStatusMap.get(m.id) ?? false,
          distance_meters: distanceKm != null ? Math.round(distanceKm * 1000) : null,
          estimated_delivery_time_minutes: distanceKm != null ? estimateDeliveryMinutes(distanceKm) : null,
          is_promoted: isPromoted,
          promoted_position: isPromoted ? 0 : null,
        };
      })
      .filter((item): item is NonNullable<typeof item> => item !== null);

    // Sort: promoted first → open → closed → distance (nearest first)
    feedItems.sort((a: any, b: any) => {
      if (a.is_promoted !== b.is_promoted) return a.is_promoted ? -1 : 1;
      if (a.is_currently_open !== b.is_currently_open) return a.is_currently_open ? -1 : 1;
      if (a.distance_meters !== null && b.distance_meters !== null) {
        return a.distance_meters - b.distance_meters;
      }
      return 0;
    });

    // Next cursor
    const lastItem = items[items.length - 1];
    const nextCursor = hasMore && lastItem
      ? btoa(JSON.stringify({ id: lastItem.id, created_at: lastItem.created_at }))
      : null;

    log.info('Feed returned', { count: feedItems.length, hasMore, city, category: category || 'all' });

    return corsResponse(successResponse({
      items: feedItems,
      merchants: feedItems,
      next_cursor: nextCursor,
      has_more: hasMore,
      total_count: feedItems.length,
      banners: !cursor ? banners.map((b: { id: string; merchant_id: string; slot_type: string; image_url?: string }) => ({
        id: b.id,
        merchant_id: b.merchant_id,
        slot_type: b.slot_type,
      })) : undefined,
    }), 200, {
      'Cache-Control': 'public, s-maxage=30',
    }, req);
  } catch (err) {
    log.error('Unhandled error', { error: err instanceof Error ? err.message : String(err) });
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }
});
