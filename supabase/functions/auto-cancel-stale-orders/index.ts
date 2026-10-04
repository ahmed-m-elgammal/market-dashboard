// Edge Function: auto-cancel-stale-orders
// A3-G6: Scheduled cron that cancels orders stuck in non-terminal statuses
// beyond their configured timeout thresholds.
//
// Migration 023 seeded 4 config keys:
//   - auto_cancel_pending_minutes=15        (pending orders, no merchant confirm)
//   - auto_cancel_no_driver_minutes=30      (confirmed orders, no driver assigned)
//   - auto_cancel_payment_timeout_minutes=10 (pending digital payment — handled by
//                                             reconcile-payments EF, NOT this one)
//   - auto_cancel_ready_timeout_minutes=60  (ready orders, no pickup)
//
// Previously, these config keys were seeded but never enforced — stale orders
// sat in their status forever, clogging the active-orders dashboard.
//
// This EF handles 3 of the 4 thresholds (the payment timeout one is handled
// by the reconcile-payments EF which queries Paymob before cancelling).
// For each threshold:
//   1. Read the config value (fallback to default if missing)
//   2. Find orders in the target status older than the threshold
//   3. Call cancel_order RPC with initiator='system' for each
//
// Auth: requires service role key (set by the Supabase cron scheduler).

import { corsResponse, handleOptions } from '../_shared/cors.ts';
import { errorResponse, successResponse } from '../_shared/errors.ts';
import { getSupabaseAdmin } from '../_shared/supabase.ts';
import { createLogger, generateRequestId, measure } from '../_shared/logger.ts';

// Hard cap on orders processed per run to stay within the Edge Runtime budget.
const BATCH_SIZE = 50;

// Config key → (status to match, default timeout in minutes).
// auto_cancel_payment_timeout_minutes is intentionally excluded — the
// reconcile-payments EF owns that path because it needs to query Paymob
// before cancelling.
const STALE_ORDER_RULES = [
  {
    configKey: 'auto_cancel_pending_minutes',
    status: 'pending',
    defaultMinutes: 15,
    reason: 'Auto-cancelled: merchant did not confirm within timeout',
  },
  {
    configKey: 'auto_cancel_no_driver_minutes',
    status: 'confirmed',
    defaultMinutes: 30,
    reason: 'Auto-cancelled: no driver assigned within timeout',
  },
  {
    configKey: 'auto_cancel_ready_timeout_minutes',
    status: 'ready',
    defaultMinutes: 60,
    reason: 'Auto-cancelled: order not picked up within timeout',
  },
] as const;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions(req);

  const requestId = generateRequestId();
  const log = createLogger({ requestId, functionName: 'auto-cancel-stale-orders' });

  // Auth: require service role key.
  const authHeader = req.headers.get('Authorization');
  const token = authHeader?.replace('Bearer ', '') ?? '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!token || token !== serviceKey) {
    log.warn('Unauthorized auto-cancel attempt');
    return corsResponse(errorResponse('FORBIDDEN'), 403, undefined, req);
  }

  try {
    log.info('Auto-cancel run started');

    const supabase = getSupabaseAdmin();

    // Batch-fetch all config values for the rules in one query.
    const configKeys = STALE_ORDER_RULES.map((r) => r.configKey);
    const { data: configRows } = await supabase
      .from('platform_config')
      .select('key, value')
      .in('key', configKeys);

    const configMap = new Map(
      (configRows || []).map((r: { key: string; value: string }) => [r.key, r.value]),
    );

    let totalCancelled = 0;
    let totalFailed = 0;

    for (const rule of STALE_ORDER_RULES) {
      const minutes = Number(configMap.get(rule.configKey) || rule.defaultMinutes);
      const threshold = new Date(Date.now() - minutes * 60 * 1000).toISOString();

      // Find stale orders in this status. Only match orders with no driver
      // assigned for the 'confirmed' rule (auto_cancel_no_driver_minutes) —
      // if a driver is assigned, the order is in progress and shouldn't be
      // auto-cancelled by this rule.
      let query = supabase
        .from('orders')
        .select('id, order_number')
        .eq('status', rule.status)
        .lt('created_at', threshold)
        .order('created_at', { ascending: true })
        .limit(BATCH_SIZE);

      if (rule.status === 'confirmed') {
        // Only auto-cancel confirmed orders that have NO driver assigned.
        // Confirmed orders WITH a driver are in progress (driver heading to
        // merchant) and should not be cancelled by this rule.
        query = query.is('driver_id', null);
      }

      const { data: staleOrders, error: fetchErr } = await query;

      if (fetchErr) {
        log.error('Failed to fetch stale orders', {
          rule: rule.configKey,
          status: rule.status,
          error: fetchErr.message,
        });
        continue;
      }

      if (!staleOrders || staleOrders.length === 0) {
        log.debug('No stale orders for rule', {
          rule: rule.configKey,
          status: rule.status,
          minutes,
        });
        continue;
      }

      log.info('Found stale orders for rule', {
        rule: rule.configKey,
        status: rule.status,
        count: staleOrders.length,
        minutes,
      });

      for (const order of staleOrders) {
        try {
          const { error: rpcErr } = await measure('cancel-stale-order', () =>
            supabase.rpc('cancel_order', {
              p_order_id: order.id,
              p_initiator_id: null as unknown as string,
              p_initiator_role: 'system',
              p_reason: rule.reason,
            }),
          log);

          if (rpcErr) {
            // The RPC may raise 'Order is already cancelled' or 'Order status
            // changed concurrently' if another process cancelled/transitioned
            // the order between our SELECT and RPC call. These are not errors
            // — the order is no longer stale. Log and continue.
            const msg = (rpcErr.message || '').toLowerCase();
            if (
              msg.includes('already cancelled') ||
              msg.includes('concurrently') ||
              msg.includes('cannot be cancelled')
            ) {
              log.debug('Stale order already transitioned', {
                orderId: order.id,
                error: rpcErr.message,
              });
            } else {
              log.error('cancel_order RPC failed for stale order', {
                orderId: order.id,
                error: rpcErr.message,
              });
              totalFailed++;
            }
          } else {
            totalCancelled++;
            log.info('Stale order auto-cancelled', {
              orderId: order.id,
              orderNumber: order.order_number,
              rule: rule.configKey,
            });
          }
        } catch (err) {
          log.error('Unexpected error cancelling stale order', {
            orderId: order.id,
            error: err instanceof Error ? err.message : String(err),
          });
          totalFailed++;
        }
      }
    }

    log.info('Auto-cancel run complete', { totalCancelled, totalFailed });

    // B1-G5: Cleanup expired admin sessions. The cleanup_expired_admin_sessions()
    // RPC (migration 028) marks expired sessions as invalidated. Without this
    // call, expired sessions accumulate in the table indefinitely. This runs
    // on every cron invocation (every 5 min) — the RPC is idempotent and
    // cheap (single UPDATE with a WHERE clause).
    try {
      const { data: cleanedCount, error: cleanupErr } = await measure('cleanup-expired-sessions', () =>
        supabase.rpc('cleanup_expired_admin_sessions'),
      log);
      if (cleanupErr) {
        log.warn('cleanup_expired_admin_sessions RPC failed', { error: cleanupErr.message });
      } else {
        log.info('Expired admin sessions cleaned up', { count: cleanedCount ?? 0 });
      }
    } catch (err) {
      log.warn('cleanup_expired_admin_sessions failed', {
        error: err instanceof Error ? err.message : String(err),
      });
    }

    return corsResponse(successResponse({
      cancelled: totalCancelled,
      failed: totalFailed,
    }), 200, undefined, req);
  } catch (err) {
    log.error('Unhandled error', { error: err instanceof Error ? err.message : String(err) });
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }
});
