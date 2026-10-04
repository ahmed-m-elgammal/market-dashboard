// Edge Function: auto-issue-loyalty-promos
// Phase 4b (MARKETING-IMPROVEMENT-PLAN.md):
// Scheduled daily. Finds customers who spent >= loyalty_spend_threshold EGP
// in the last loyalty_lookback_days, and auto-issues a loyalty_discount_pct%
// off promo (max 1 per customer per loyalty_cooldown_days).
//
// The promo is:
//   - Per-user: max_usage=1, max_usage_per_user=1
//   - Global scope: merchant_id=null, category=null (works anywhere)
//   - Capped: max_discount_amount = loyalty_promo_max_discount
//   - Time-limited: expires loyalty_promo_validity_days after issue
//   - Code format: LOYAL-<8-char-user-prefix>
//
// Auth: requires service role key (set by the Supabase cron scheduler).
// Schedule: daily at 02:00 UTC (configured in supabase/config.toml).

import { corsResponse, handleOptions } from '../_shared/cors.ts';
import { errorResponse, successResponse } from '../_shared/errors.ts';
import { getSupabaseAdmin } from '../_shared/supabase.ts';
import { createLogger, generateRequestId } from '../_shared/logger.ts';

// Hard cap on customers processed per run to stay within Edge Runtime budget.
const BATCH_SIZE = 100;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions(req);

  const requestId = generateRequestId();
  const log = createLogger({ requestId, functionName: 'auto-issue-loyalty-promos' });

  // Auth: require service role key.
  const authHeader = req.headers.get('Authorization');
  const token = authHeader?.replace('Bearer ', '') ?? '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!token || token !== serviceKey) {
    log.warn('Unauthorized loyalty-issuance attempt');
    return corsResponse(errorResponse('FORBIDDEN'), 403, undefined, req);
  }

  try {
    log.info('Loyalty promo issuance run started');
    const supabase = getSupabaseAdmin();

    // ── Fetch config ──────────────────────────────────────────────────────
    const configKeys = [
      'loyalty_spend_threshold',
      'loyalty_discount_pct',
      'loyalty_lookback_days',
      'loyalty_cooldown_days',
      'loyalty_promo_max_discount',
      'loyalty_promo_validity_days',
    ];
    const { data: configRows } = await supabase
      .from('platform_config')
      .select('key, value')
      .in('key', configKeys);

    const config = new Map(
      (configRows || []).map((r: { key: string; value: string }) => [r.key, r.value]),
    );

    const spendThreshold = Number(config.get('loyalty_spend_threshold') || 500);
    const discountPct = Number(config.get('loyalty_discount_pct') || 10);
    const lookbackDays = Number(config.get('loyalty_lookback_days') || 7);
    const cooldownDays = Number(config.get('loyalty_cooldown_days') || 30);
    const maxDiscount = Number(config.get('loyalty_promo_max_discount') || 50);
    const validityDays = Number(config.get('loyalty_promo_validity_days') || 14);

    // ── Find eligible customers ───────────────────────────────────────────
    // Eligible = spent >= spendThreshold in the last lookbackDays on
    // non-cancelled orders, AND has NOT received a loyalty promo in the
    // last cooldownDays.
    const lookbackDate = new Date(Date.now() - lookbackDays * 86400_000).toISOString();
    const cooldownDate = new Date(Date.now() - cooldownDays * 86400_000).toISOString();

    // Step 1: find customers who met the spend threshold
    const { data: bigSpenders, error: spendErr } = await supabase
      .from('orders')
      .select('customer_id, total')
      .neq('status', 'cancelled')
      .gte('created_at', lookbackDate);

    if (spendErr) {
      log.error('Failed to fetch orders for spend calculation', { error: spendErr.message });
      return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
    }

    // Aggregate spend per customer
    const spendByCustomer = new Map<string, number>();
    for (const order of (bigSpenders || []) as { customer_id: string; total: number }[]) {
      spendByCustomer.set(
        order.customer_id,
        (spendByCustomer.get(order.customer_id) ?? 0) + Number(order.total),
      );
    }

    const eligibleCustomerIds = Array.from(spendByCustomer.entries())
      .filter(([, total]) => total >= spendThreshold)
      .map(([customerId]) => customerId)
      .slice(0, BATCH_SIZE);

    log.info('Customers meeting spend threshold', {
      count: eligibleCustomerIds.length,
      threshold: spendThreshold,
      lookbackDays,
    });

    if (eligibleCustomerIds.length === 0) {
      log.info('No eligible customers — run complete');
      return corsResponse(successResponse({ issued: 0, skipped: 0 }), 200, undefined, req);
    }

    // Step 2: exclude customers who received a loyalty promo in the cooldown
    const { data: recentLoyalty } = await supabase
      .from('loyalty_promo_log')
      .select('customer_id')
      .in('customer_id', eligibleCustomerIds)
      .gte('issued_at', cooldownDate);

    const recentlyIssued = new Set(
      (recentLoyalty || []).map((r: { customer_id: string }) => r.customer_id),
    );

    const toIssue = eligibleCustomerIds.filter((id) => !recentlyIssued.has(id));
    log.info('Customers eligible after cooldown filter', {
      count: toIssue.length,
      skipped: eligibleCustomerIds.length - toIssue.length,
    });

    // ── Issue promos ──────────────────────────────────────────────────────
    let issued = 0;
    let failed = 0;
    const now = new Date();
    const expiresAt = new Date(now.getTime() + validityDays * 86400_000).toISOString();

    for (const customerId of toIssue) {
      try {
        // Generate a unique promo code: LOYAL-<8-char-prefix-of-uuid>
        const codePrefix = customerId.replace(/-/g, '').slice(0, 8).toUpperCase();
        const promoCode = `LOYAL-${codePrefix}`;

        // Insert the promo (per-user: max_usage=1, max_usage_per_user=1)
        const { data: promo, error: promoErr } = await supabase
          .from('promo_codes')
          .insert({
            code: promoCode,
            discount_type: 'percentage',
            discount_value: discountPct,
            max_discount_amount: maxDiscount,
            starts_at: now.toISOString(),
            expires_at: expiresAt,
            max_usage: 1,
            max_usage_per_user: 1,
            min_order_amount: 0,
            merchant_id: null,
            category: null,
            free_delivery: false,
            target_segment: 'all',
            stackable: false,
            is_active: true,
          })
          .select()
          .single();

        if (promoErr || !promo) {
          log.error('Failed to insert loyalty promo', {
            customerId,
            error: promoErr?.message,
          });
          failed++;
          continue;
        }

        // Log the issuance
        const { error: logErr } = await supabase
          .from('loyalty_promo_log')
          .insert({
            customer_id: customerId,
            promo_code_id: (promo as { id: string }).id,
            spend_threshold_met: spendByCustomer.get(customerId) ?? spendThreshold,
          });

        if (logErr) {
          log.error('Failed to log loyalty issuance', {
            customerId,
            error: logErr.message,
          });
          // Don't fail — the promo was created, just the log failed.
          // The unique index on (customer_id, promo_code_id) prevents dupes.
        }

        issued++;
        log.info('Loyalty promo issued', {
          customerId,
          promoCode,
          discountPct,
          maxDiscount,
        });
      } catch (err) {
        log.error('Unexpected error issuing loyalty promo', {
          customerId,
          error: err instanceof Error ? err.message : String(err),
        });
        failed++;
      }
    }

    log.info('Loyalty promo issuance run complete', { issued, failed, skipped: recentlyIssued.size });

    return corsResponse(successResponse({
      issued,
      failed,
      skipped: recentlyIssued.size,
      config: { spendThreshold, discountPct, lookbackDays, cooldownDays, maxDiscount, validityDays },
    }), 200, undefined, req);
  } catch (err) {
    log.error('Unhandled error', { error: err instanceof Error ? err.message : String(err) });
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }
});
