// Edge Function: auto-generate-driver-settlements
// S5 (money-movement-implementation-plan.md lines 1118-1371):
// Scheduled cron that aggregates each driver's pending driver_earnings from
// the previous settlement window into a settlement row, then marks those
// earnings 'paid' (so they don't get re-settled on the next run).
//
// Schedule: daily at 03:30 UTC (configured in supabase/config.toml).
// Auth: requires service role key (set by the Supabase cron scheduler).
//
// Per-driver error isolation:
//   The create_driver_settlement RPC raises on overlap (already-settled
//   period) or zero-eligible-earnings. The cron MUST continue to the next
//   driver rather than abort the batch — so each call is wrapped in try/catch
//   and the per-driver outcome is recorded in the response.
//
// Period window:
//   - daily  drivers: previous UTC day (00:00 → 24:00)
//   - weekly drivers: previous 7 UTC days (runs only on Sundays)
//   - monthly drivers: previous calendar month (runs only on the 1st)
//   Drivers with payout_frequency='weekly' or 'monthly' are skipped on non-
//   matching days to avoid creating 7× or 30× more settlements than intended.
//
// Performance (gap-analysis §4.1 + §4.2 fixes):
//   §4.1 — Pre-filter drivers to only those with at least one pending
//   driver_earnings row. The previous implementation fetched ALL drivers and
//   sequentially invoked create_driver_settlement on each, including the
//   long-tail of inactive drivers with zero pending earnings. Each no-op
//   RPC still acquired a FOR UPDATE lock and ran the eligibility query
//   (~30ms wasted per inactive driver). At 1000 drivers / 50 active, that
//   was ~30s of wasted EF runtime per night.
//
//   The pre-filter is a single PostgREST query that joins drivers to
//   driver_earnings with an !inner filter on payout_status='pending'. The
//   result is one row per (driver × pending earning), so we dedupe by
//   driver_id into a Map.
//
//   §4.2 — Process drivers in concurrent chunks of 10. The previous
//   implementation awaited each RPC sequentially. With 200 active drivers
//   at ~50-100ms per RPC, the EF was close to Supabase's wall-clock limit.
//   create_driver_settlement is safe under concurrency — the FOR UPDATE
//   lock is per-driver, so two concurrent settlements for different drivers
//   don't contend. Promise.allSettled ensures one driver's RPC failure
//   doesn't abort the chunk.

import { corsResponse, handleOptions } from '../_shared/cors.ts';
import { errorResponse, successResponse } from '../_shared/errors.ts';
import { getSupabaseAdmin } from '../_shared/supabase.ts';
import { createLogger, generateRequestId } from '../_shared/logger.ts';
// §3.3 fix: timing-safe string comparison for the service-key check.
import { timingSafeEqualString } from '../_shared/crypto.ts';

interface DriverRow {
  id: string;
  payout_frequency: 'daily' | 'weekly' | 'monthly';
  payout_method: 'cash' | 'bank_transfer' | 'wallet' | 'instapay';
}

interface SettlementCallResult {
  settlement_id: string;
  net_payable: number;
  delivery_count: number;
}

// §4.2: chunk size for concurrent RPC calls. 10 keeps the EF well under
// Supabase's wall-clock limit while staying below PostgREST's default
// connection pool size (so we don't exhaust pool connections on a single
// batch). Tune up to 20 if Paymob API latency is ever added to this EF.
const RPC_CHUNK_SIZE = 10;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions(req);

  const requestId = generateRequestId();
  const log = createLogger({ requestId, functionName: 'auto-generate-driver-settlements' });

  // Auth: require service role key.
  // §3.3 fix: use timing-safe comparison instead of `!==` to avoid leaking
  // bytes of the expected value through response time. Low practical risk
  // (service keys are long random JWTs) but the codebase already uses
  // timingSafeEqualHex for HMAC verification — applying the same bar to
  // service-key checks is consistent.
  const authHeader = req.headers.get('Authorization');
  const token = authHeader?.replace('Bearer ', '') ?? '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!token || !timingSafeEqualString(token, serviceKey)) {
    log.warn('Unauthorized auto-settle attempt');
    return corsResponse(errorResponse('FORBIDDEN'), 403, undefined, req);
  }

  try {
    log.info('Auto-settle run started');
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
    // be used per driver, but computing all three up front avoids per-driver
    // date math).
    const todayUtcMidnight = Date.UTC(utcYear, utcMonth, utcDate, 0, 0, 0);
    const yesterdayUtcMidnight = todayUtcMidnight - 86_400_000;
    const dailyStart = new Date(yesterdayUtcMidnight).toISOString();
    const dailyEnd = new Date(todayUtcMidnight).toISOString();

    const weeklyStart = new Date(todayUtcMidnight - 7 * 86_400_000).toISOString();
    const weeklyEnd = dailyEnd;

    const prevMonthYear = utcMonth === 0 ? utcYear - 1 : utcYear;
    const prevMonthIdx = utcMonth === 0 ? 11 : utcMonth - 1;
    const monthlyStart = new Date(Date.UTC(prevMonthYear, prevMonthIdx, 1, 0, 0, 0)).toISOString();
    const monthlyEnd = new Date(Date.UTC(utcYear, utcMonth, 1, 0, 0, 0)).toISOString();

    log.info('Settlement windows computed', {
      dailyStart, dailyEnd,
      weeklyStart, weeklyEnd,
      monthlyStart, monthlyEnd,
      isSunday, isFirstOfMonth,
    });

    // §4.1 fix: pre-filter to only drivers with at least one pending
    // driver_earnings row. The !inner join + payout_status='pending' filter
    // returns one row per (driver × pending earning) — we dedupe by driver
    // id into a Map below.
    //
    // This skips the long-tail of inactive drivers who would have all
    // raised 'No eligible earnings for settlement in this period' anyway,
    // saving the FOR UPDATE lock acquisition + eligibility SELECT per
    // skipped driver (~30ms × N inactive drivers per night).
    //
    // Edge case: a driver with payout_frequency='weekly' on a Tuesday who
    // has pending earnings is fetched by this query, but the per-driver
    // loop below skips them with outcome='skipped' (preserving the original
    // behavior — weekly drivers only settle on Sundays).
    const { data: driverEarningRows, error: driversErr } = await supabase
      .from('drivers')
      .select(`
        id, payout_frequency, payout_method,
        earnings:driver_earnings!inner(payout_status)
      `)
      .eq('earnings.payout_status', 'pending')
      .returns<DriverRow[]>();

    if (driversErr) {
      log.error('Failed to fetch drivers with pending earnings', { error: driversErr.message });
      return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
    }

    // Dedupe by driver id — PostgREST returns one row per (driver × pending
    // earning), so a driver with 5 pending earnings appears 5 times.
    const uniqueDrivers = new Map<string, DriverRow>();
    for (const row of (driverEarningRows ?? []) as Array<DriverRow & { earnings: unknown }>) {
      if (!uniqueDrivers.has(row.id)) {
        uniqueDrivers.set(row.id, {
          id: row.id,
          payout_frequency: row.payout_frequency,
          payout_method: row.payout_method,
        });
      }
    }
    const drivers = Array.from(uniqueDrivers.values());

    log.info('Drivers with pending earnings', {
      count: drivers.length,
      // Track raw row count for ops visibility — if this ever approaches the
      // EF response limit, switch to paginating the pre-filter.
      raw_rows: driverEarningRows?.length ?? 0,
    });

    const results: Array<{
      driver_id: string;
      payout_frequency: string;
      outcome: 'settled' | 'no_earnings' | 'already_settled' | 'skipped' | 'error';
      settlement_id?: string;
      net_payable?: number;
      delivery_count?: number;
      error?: string;
    }> = [];

    let settledCount = 0;
    let noEarningsCount = 0;
    let alreadySettledCount = 0;
    let skippedCount = 0;
    let errorCount = 0;

    // Helper: settle one driver. Returns the outcome record to push into
    // the results array. Extracted so we can call it via Promise.allSettled
    // for concurrency (§4.2).
    async function settleOneDriver(driver: DriverRow): Promise<{
      driver_id: string;
      payout_frequency: string;
      outcome: 'settled' | 'no_earnings' | 'already_settled' | 'skipped' | 'error';
      settlement_id?: string;
      net_payable?: number;
      delivery_count?: number;
      error?: string;
    }> {
      // Skip weekly drivers on non-Sundays; skip monthly drivers on non-1st.
      // daily drivers always run. Preserves the original skip semantics.
      let periodStart: string;
      let periodEnd: string;
      if (driver.payout_frequency === 'daily') {
        periodStart = dailyStart;
        periodEnd = dailyEnd;
      } else if (driver.payout_frequency === 'weekly') {
        if (!isSunday) {
          return {
            driver_id: driver.id,
            payout_frequency: driver.payout_frequency,
            outcome: 'skipped',
          };
        }
        periodStart = weeklyStart;
        periodEnd = weeklyEnd;
      } else {
        // monthly
        if (!isFirstOfMonth) {
          return {
            driver_id: driver.id,
            payout_frequency: driver.payout_frequency,
            outcome: 'skipped',
          };
        }
        periodStart = monthlyStart;
        periodEnd = monthlyEnd;
      }

      // Call create_driver_settlement RPC. Errors are caught here and
      // translated to outcome records — never re-thrown (Promise.allSettled
      // would treat a throw as a rejection, complicating the chunk loop).
      try {
        const { data: rpcData, error: rpcErr } = await supabase.rpc(
          'create_driver_settlement',
          {
            p_driver_id: driver.id,
            p_period_start: periodStart,
            p_period_end: periodEnd,
            p_payout_method: driver.payout_method,
          },
        );

        if (rpcErr) {
          const msg = (rpcErr.message || '').toLowerCase();
          if (msg.includes('no eligible earnings')) {
            return {
              driver_id: driver.id,
              payout_frequency: driver.payout_frequency,
              outcome: 'no_earnings',
            };
          }
          if (msg.includes('already exists')) {
            return {
              driver_id: driver.id,
              payout_frequency: driver.payout_frequency,
              outcome: 'already_settled',
            };
          }
          log.warn('create_driver_settlement failed for driver', {
            driver_id: driver.id,
            error: rpcErr.message,
          });
          return {
            driver_id: driver.id,
            payout_frequency: driver.payout_frequency,
            outcome: 'error',
            error: rpcErr.message,
          };
        }

        // RPC returns TABLE with one row.
        const row = Array.isArray(rpcData) ? (rpcData[0] as SettlementCallResult | undefined) : (rpcData as SettlementCallResult | undefined);
        return {
          driver_id: driver.id,
          payout_frequency: driver.payout_frequency,
          outcome: 'settled',
          settlement_id: row?.settlement_id,
          net_payable: row?.net_payable != null ? Number(row.net_payable) : undefined,
          delivery_count: row?.delivery_count,
        };
      } catch (err) {
        const errMsg = err instanceof Error ? err.message : String(err);
        log.warn('Unexpected error settling driver', {
          driver_id: driver.id,
          error: errMsg,
        });
        return {
          driver_id: driver.id,
          payout_frequency: driver.payout_frequency,
          outcome: 'error',
          error: errMsg,
        };
      }
    }

    // §4.2 fix: process drivers in concurrent chunks. Each chunk runs
    // RPC_CHUNK_SIZE create_driver_settlement RPCs in parallel via
    // Promise.allSettled. The RPC is safe under concurrency — the FOR UPDATE
    // lock is per-driver, so two concurrent settlements for different drivers
    // don't contend.
    //
    // Promise.allSettled (not Promise.all) ensures one driver's RPC rejection
    // doesn't abort the chunk. settleOneDriver already catches and translates
    // errors to outcome records, so allSettled's `fulfilled` branch is the
    // only one that fires — but we keep the `rejected` branch as a defensive
    // fallback in case settleOneDriver ever throws unexpectedly.
    for (let i = 0; i < drivers.length; i += RPC_CHUNK_SIZE) {
      const chunk = drivers.slice(i, i + RPC_CHUNK_SIZE);
      const outcomes = await Promise.allSettled(chunk.map((d) => settleOneDriver(d)));

      for (const outcome of outcomes) {
        let record: {
          driver_id: string;
          payout_frequency: string;
          outcome: 'settled' | 'no_earnings' | 'already_settled' | 'skipped' | 'error';
          settlement_id?: string;
          net_payable?: number;
          delivery_count?: number;
          error?: string;
        };

        if (outcome.status === 'fulfilled') {
          record = outcome.value;
        } else {
          // Defensive: settleOneDriver catches all errors, so this branch
          // should never fire. If it does, log + record a generic error so
          // the run continues.
          log.error('settleOneDriver rejected unexpectedly', {
            error: outcome.reason instanceof Error ? outcome.reason.message : String(outcome.reason),
          });
          record = {
            driver_id: 'unknown',
            payout_frequency: 'unknown',
            outcome: 'error',
            error: outcome.reason instanceof Error ? outcome.reason.message : String(outcome.reason),
          };
        }

        results.push(record);
        switch (record.outcome) {
          case 'settled': settledCount++; break;
          case 'no_earnings': noEarningsCount++; break;
          case 'already_settled': alreadySettledCount++; break;
          case 'skipped': skippedCount++; break;
          case 'error': errorCount++; break;
        }
      }
    }

    log.info('Auto-settle run complete', {
      total_drivers_with_pending_earnings: drivers.length,
      settled: settledCount,
      no_earnings: noEarningsCount,
      already_settled: alreadySettledCount,
      skipped: skippedCount,
      errors: errorCount,
    });

    return corsResponse(successResponse({
      // Field name preserved for backwards compat with existing ops dashboards.
      // SEMANTICS CHANGED (§4.1): now reflects drivers with pending earnings,
      // not all drivers in the fleet. The pre-filter means inactive drivers
      // are no longer counted here.
      total_drivers: drivers.length,
      settled: settledCount,
      no_earnings: noEarningsCount,
      already_settled: alreadySettledCount,
      skipped: skippedCount,
      errors: errorCount,
      // Per-driver outcomes — capped at 200 entries to avoid bloating the
      // response on large fleets. Full results available in logs.
      results: results.slice(0, 200),
    }), 200, undefined, req);
  } catch (err) {
    log.error('Unhandled error', { error: err instanceof Error ? err.message : String(err) });
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }
});
