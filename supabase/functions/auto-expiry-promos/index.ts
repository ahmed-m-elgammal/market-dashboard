// Edge Function: auto-expiry-promos
// P3-7 (MARKETING-IMPROVEMENT-PLAN.md Task 2.5):
// Scheduled cron that flips is_active = false on promo_codes and
// promoted_slots whose expires_at < now(). Without this, expired promos
// stay is_active = true forever, polluting the "active" filter and the
// customer-facing feed (the validate-promo EF checks expires_at at query
// time, but the admin list view and the active-count badge rely on
// is_active).
//
// Schedule: every 5 minutes (configured in supabase/config.toml).
// Auth: requires service role key (set by the Supabase cron scheduler).
//
// Mirrors the auto-cancel-stale-orders EF pattern: service-role auth,
// batch update, structured logging.

import { corsResponse, handleOptions } from '../_shared/cors.ts';
import { errorResponse, successResponse } from '../_shared/errors.ts';
import { getSupabaseAdmin } from '../_shared/supabase.ts';
import { createLogger, generateRequestId } from '../_shared/logger.ts';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions(req);

  const requestId = generateRequestId();
  const log = createLogger({ requestId, functionName: 'auto-expiry-promos' });

  // Auth: require service role key.
  const authHeader = req.headers.get('Authorization');
  const token = authHeader?.replace('Bearer ', '') ?? '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!token || token !== serviceKey) {
    log.warn('Unauthorized auto-expiry attempt');
    return corsResponse(errorResponse('FORBIDDEN'), 403, undefined, req);
  }

  try {
    log.info('Auto-expiry run started');
    const supabase = getSupabaseAdmin();
    const now = new Date().toISOString();

    // Expire promo_codes: is_active = true AND expires_at < now AND not soft-deleted.
    const { data: expiredPromos, error: promoErr } = await supabase
      .from('promo_codes')
      .update({ is_active: false })
      .eq('is_active', true)
      .lt('expires_at', now)
      .is('deleted_at', null)
      .select('id, code');

    if (promoErr) {
      log.error('Failed to expire promo_codes', { error: promoErr.message });
    } else {
      log.info('Expired promo_codes', { count: expiredPromos?.length ?? 0 });
    }

    // Expire promoted_slots: same conditions.
    const { data: expiredAds, error: adErr } = await supabase
      .from('promoted_slots')
      .update({ is_active: false })
      .eq('is_active', true)
      .lt('expires_at', now)
      .is('deleted_at', null)
      .select('id, merchant_id');

    if (adErr) {
      log.error('Failed to expire promoted_slots', { error: adErr.message });
    } else {
      log.info('Expired promoted_slots', { count: expiredAds?.length ?? 0 });
    }

    const totalExpired = (expiredPromos?.length ?? 0) + (expiredAds?.length ?? 0);
    log.info('Auto-expiry run complete', { totalExpired });

    return corsResponse(successResponse({
      expired_promos: expiredPromos?.length ?? 0,
      expired_ads: expiredAds?.length ?? 0,
      total_expired: totalExpired,
    }), 200, undefined, req);
  } catch (err) {
    log.error('Unhandled error', { error: err instanceof Error ? err.message : String(err) });
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }
});
