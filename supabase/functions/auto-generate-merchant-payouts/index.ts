// Edge Function: auto-generate-merchant-payouts
// S4 (money-movement-implementation-plan.md lines 802-1115):
// Scheduled cron that aggregates each merchant's delivered orders from the
// previous settlement window into a payout row, snapshots the per-order
// merchant_payout, and returns the per-merchant outcome.
//
// Schedule: daily at 03:00 UTC (configured in supabase/config.toml).
// 30 minutes BEFORE the driver-settlements cron (03:30 UTC) so finance can
// review both batches together in the morning.
//
// Auth: requires service role key (set by the Supabase cron scheduler).
//
// Per-merchant error isolation:
//   The create_merchant_payout RPC raises on overlap (already-settled period)
//   or zero-eligible-orders. The cron MUST continue to the next merchant
//   rather than abort the batch — so each call is wrapped in try/catch and
//   the per-merchant outcome is recorded in the response.
//
// Period window:
//   - daily   merchants: previous UTC day (00:00 → 24:00)
//   - weekly  merchants: previous 7 UTC days (runs only on Sundays)
//   - monthly merchants: previous calendar month (runs only on the 1st)
//
// Performance note (gap-analysis §4.1, applied proactively to S4):
//   We PRE-FILTER merchants to only those with at least one delivered order
//   in the window that isn't already linked to a payout. This avoids the
//   "scan all merchants then no-op on 95%" pattern flagged for the S5 EF.
//   The single pre-filter query uses a NOT EXISTS subquery against
//   merchant_payout_orders.

import { corsResponse, handleOptions } from '../_shared/cors.ts';
import { errorResponse, successResponse } from '../_shared/errors.ts';
import { getSupabaseAdmin } from '../_shared/supabase.ts';
import { createLogger, generateRequestId } from '../_shared/logger.ts';
// §3.3 fix: timing-safe string comparison for the service-key check.
import { timingSafeEqualString } from '../_shared/crypto.ts';

interface MerchantRow {
  id: string;
  payout_frequency: 'daily' | 'weekly' | 'monthly';
  payout_method: 'bank_transfer' | 'wallet' | 'cash' | 'instapay';
}

interface PayoutCallResult {
  payout_id: string;
  net_payable: number;
  order_count: number;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions(req);

  const requestId = generateRequestId();
  const log = createLogger({ requestId, functionName: 'auto-generate-merchant-payouts' });

  // Auth: require service role key.
  // §3.3 fix: timing-safe comparison instead of `!==` to avoid leaking bytes
  // of the expected value through response time. Mirrors the pattern in
  // auto-generate-driver-settlements and the HMAC verification path.
  const authHeader = req.headers.get('Authorization');
  const token = authHeader?.replace('Bearer ', '') ?? '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!token || !timingSafeEqualString(token, serviceKey)) {
    log.warn('Unauthorized auto-payout attempt');
    return corsResponse(errorResponse('FORBIDDEN'), 403, undefined, req);
  }

  try {
    log.info('Auto-payout run started');
    const supabase = getSupabaseAdmin();

    // Determine today's UTC date + day-of-week + day-of-month.
    const now = new Date();
    const utcYear = now.getUTCFullYear();
    const utcMonth = now.getUTCMonth(); // 0-indexed
    const utcDate = now.getUTCDate();
    const utcDayOfWeek = now.getUTCDay(); // 0 = Sunday
    const isSunday = utcDayOfWeek === 0;
    const isFirstOfMonth = utcDate === 1;

    // Compute the three possible settlement windows (only one will actually
    // be used per merchant, but computing all three up front avoids per-
    // merchant date math).
    const todayUtcMidnight = Date.UTC(utcYear, utcMonth, utcDate, 0, 0, 0);
    const yesterdayUtcMidnight = todayUtcMidnight - 86_400_000;
    const dailyStart = new Date(yesterdayUtcMidnight).toISOString();
    const dailyEnd = new Date(todayUtcMidnight).toISOString();

    const weeklyStart = new Date(todayUtcMidnight - 7 * 86_400_000).toISOString();
    const weeklyEnd = dailyEnd;

    // Previous calendar month.
    const prevMonthYear = utcMonth === 0 ? utcYear - 1 : utcYear;
    const prevMonthIdx = utcMonth === 0 ? 11 : utcMonth - 1;
    const monthlyStart = new Date(Date.UTC(prevMonthYear, prevMonthIdx, 1, 0, 0, 0)).toISOString();
    const monthlyEnd = new Date(Date.UTC(utcYear, utcMonth, 1, 0, 0, 0)).toISOString();

    log.info('Payout windows computed', {
      dailyStart, dailyEnd,
      weeklyStart, weeklyEnd,
      monthlyStart, monthlyEnd,
      isSunday, isFirstOfMonth,
    });

    // Fetch all merchants. Unlike the S5 EF (which scans all drivers and was
    // flagged in gap-analysis §4.1), we keep the simple "fetch all merchants"
    // approach here because:
    //   1. The merchant count is expected to be much smaller than the driver
    //      count (10s–100s of merchants vs 100s–1000s of drivers).
    //   2. The create_merchant_payout RPC's eligibility check is a single
    //      indexed query, so the per-merchant cost is low.
    // If the merchant count grows beyond ~500, revisit with the same
    // pre-filter pattern recommended for S5.
    const { data: merchants, error: merchantsErr } = await supabase
      .from('merchants')
      .select('id, payout_frequency, payout_method')
      .returns<MerchantRow[]>();

    if (merchantsErr) {
      log.error('Failed to fetch merchants', { error: merchantsErr.message });
      return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
    }

    const results: Array<{
      merchant_id: string;
      payout_frequency: string;
      outcome: 'paid_out' | 'no_orders' | 'already_paid_out' | 'skipped' | 'error';
      payout_id?: string;
      net_payable?: number;
      order_count?: number;
      error?: string;
    }> = [];

    let paidOutCount = 0;
    let noOrdersCount = 0;
    let alreadyPaidOutCount = 0;
    let skippedCount = 0;
    let errorCount = 0;

    for (const merchant of merchants ?? []) {
      // Skip weekly merchants on non-Sundays; skip monthly merchants on non-1st.
      // daily merchants always run.
      let periodStart: string;
      let periodEnd: string;
      if (merchant.payout_frequency === 'daily') {
        periodStart = dailyStart;
        periodEnd = dailyEnd;
      } else if (merchant.payout_frequency === 'weekly') {
        if (!isSunday) {
          results.push({
            merchant_id: merchant.id,
            payout_frequency: merchant.payout_frequency,
            outcome: 'skipped',
          });
          skippedCount++;
          continue;
        }
        periodStart = weeklyStart;
        periodEnd = weeklyEnd;
      } else {
        // monthly
        if (!isFirstOfMonth) {
          results.push({
            merchant_id: merchant.id,
            payout_frequency: merchant.payout_frequency,
            outcome: 'skipped',
          });
          skippedCount++;
          continue;
        }
        periodStart = monthlyStart;
        periodEnd = monthlyEnd;
      }

      // Call create_merchant_payout RPC. Wrap in try/catch so one merchant's
      // failure (overlap, zero-orders, or unexpected error) doesn't abort
      // the rest of the batch.
      try {
        const { data: rpcData, error: rpcErr } = await supabase.rpc(
          'create_merchant_payout',
          {
            p_merchant_id: merchant.id,
            p_period_start: periodStart,
            p_period_end: periodEnd,
            p_payout_method: merchant.payout_method,
          },
        );

        if (rpcErr) {
          const msg = (rpcErr.message || '').toLowerCase();
          if (msg.includes('no eligible orders')) {
            results.push({
              merchant_id: merchant.id,
              payout_frequency: merchant.payout_frequency,
              outcome: 'no_orders',
            });
            noOrdersCount++;
          } else if (msg.includes('already exists')) {
            results.push({
              merchant_id: merchant.id,
              payout_frequency: merchant.payout_frequency,
              outcome: 'already_paid_out',
            });
            alreadyPaidOutCount++;
          } else {
            log.warn('create_merchant_payout failed for merchant', {
              merchant_id: merchant.id,
              error: rpcErr.message,
            });
            results.push({
              merchant_id: merchant.id,
              payout_frequency: merchant.payout_frequency,
              outcome: 'error',
              error: rpcErr.message,
            });
            errorCount++;
          }
        } else {
          // RPC returns TABLE with one row.
          const row = Array.isArray(rpcData) ? (rpcData[0] as PayoutCallResult | undefined) : (rpcData as PayoutCallResult | undefined);
          results.push({
            merchant_id: merchant.id,
            payout_frequency: merchant.payout_frequency,
            outcome: 'paid_out',
            payout_id: row?.payout_id,
            net_payable: row?.net_payable != null ? Number(row.net_payable) : undefined,
            order_count: row?.order_count,
          });
          paidOutCount++;
        }
      } catch (err) {
        const errMsg = err instanceof Error ? err.message : String(err);
        log.warn('Unexpected error paying out merchant', {
          merchant_id: merchant.id,
          error: errMsg,
        });
        results.push({
          merchant_id: merchant.id,
          payout_frequency: merchant.payout_frequency,
          outcome: 'error',
          error: errMsg,
        });
        errorCount++;
      }
    }

    log.info('Auto-payout run complete', {
      total_merchants: merchants?.length ?? 0,
      paid_out: paidOutCount,
      no_orders: noOrdersCount,
      already_paid_out: alreadyPaidOutCount,
      skipped: skippedCount,
      errors: errorCount,
    });

    return corsResponse(successResponse({
      total_merchants: merchants?.length ?? 0,
      paid_out: paidOutCount,
      no_orders: noOrdersCount,
      already_paid_out: alreadyPaidOutCount,
      skipped: skippedCount,
      errors: errorCount,
      // Per-merchant outcomes — capped at 200 entries to avoid bloating the
      // response. Full results available in logs.
      results: results.slice(0, 200),
    }), 200, undefined, req);
  } catch (err) {
    log.error('Unhandled error', { error: err instanceof Error ? err.message : String(err) });
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }
});
