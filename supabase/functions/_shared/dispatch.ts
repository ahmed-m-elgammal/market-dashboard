// Shared dispatch helpers: payment-gated driver assignment takeover.
//
// Used by paymob-webhook and reconcile-payments so that, when the
// payment_dispatch_gating flag is ON (platform_config), a digital order gets
// its driver assigned at the moment payment is CONFIRMED instead of at
// placement (G5 in docs/plans/payment-service-implementation-plan.md).
//
// The assign call itself is fire-and-forget with EdgeRuntime.waitUntil +
// inline-await fallback — the exact pattern place-order/index.ts uses (S23).
// driver-actions {action:'assign'} is idempotent: it re-checks
// orders.driver_id and returns { assigned:false, reason:'already_assigned' }
// (driver-actions/index.ts), so webhook + reconcile racing on the same order
// is harmless.

import { getSupabaseAdmin, fetchWithTimeout } from './supabase.ts';
import { createLogger } from './logger.ts';

type SupabaseAdmin = ReturnType<typeof getSupabaseAdmin>;
type Logger = ReturnType<typeof createLogger>;

/** How long the fire-and-forget assign call waits before giving up. */
const ASSIGN_TIMEOUT_MS = 8_000;

/**
 * Read payment_dispatch_gating from platform_config (seeded 'false' by
 * migration 094). Missing row or unparseable value → gating OFF (legacy
 * behavior: assign at placement), so a broken config can never stall dispatch.
 */
export async function isDispatchGatingEnabled(supabase: SupabaseAdmin): Promise<boolean> {
  const { data, error } = await supabase
    .from('platform_config')
    .select('value')
    .eq('key', 'payment_dispatch_gating')
    .maybeSingle();

  if (error) {
    // Fail open to legacy behavior rather than blocking dispatch.
    return false;
  }
  return (data?.value ?? 'false') === 'true';
}

/**
 * Fire-and-forget driver assignment for an order that just became paid.
 * No-ops unless dispatch gating is ON and the order can still be assigned
 * (not cancelled). Returns true when an assign call was actually dispatched.
 */
export async function assignDriverIfPaymentGated(
  log: Logger,
  supabase: SupabaseAdmin,
  params: { orderId: string; merchantId: string; orderStatus: string | null },
): Promise<boolean> {
  const { orderId, merchantId, orderStatus } = params;

  // A cancelled order must never receive a driver, regardless of gating.
  if (orderStatus === 'cancelled') return false;

  if (!(await isDispatchGatingEnabled(supabase))) {
    log.debug('Dispatch gating OFF — assign-on-paid skipped', { orderId });
    return false;
  }

  // The webhook/reconcile selects don't include merchant coordinates —
  // fetch them only when we're actually about to assign (paid transitions
  // are the rare path, so this extra query is negligible).
  const { data: merchant, error: merchantError } = await supabase
    .from('merchants')
    .select('lat, lng')
    .eq('id', merchantId)
    .maybeSingle();

  if (merchantError || !merchant) {
    log.warn('Assign-on-paid: merchant lookup failed — reconcile will retry on next run', {
      orderId,
      merchantId,
      error: merchantError?.message,
    });
    return false;
  }

  const functionUrl = `${Deno.env.get('SUPABASE_URL')}/functions/v1/driver-actions`;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

  const assignPromise = fetchWithTimeout(
    functionUrl,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${serviceKey}`,
      },
      body: JSON.stringify({
        action: 'assign',
        order_id: orderId,
        merchant_lat: merchant.lat,
        merchant_lng: merchant.lng,
      }),
    },
    ASSIGN_TIMEOUT_MS,
  )
    .then((res) => {
      if (!res.ok) {
        log.warn('Assign-on-paid: driver-actions returned non-OK', { orderId, status: res.status });
      }
    })
    .catch((err) => {
      log.warn('Assign-on-paid: driver-actions call failed', {
        orderId,
        error: err instanceof Error ? err.message : String(err),
      });
    });

  try {
    (EdgeRuntime as { waitUntil?: (p: Promise<unknown>) => void }).waitUntil?.(assignPromise);
  } catch {
    // Older runtime without waitUntil — await inline so the work isn't lost.
    await assignPromise;
  }
  return true;
}
