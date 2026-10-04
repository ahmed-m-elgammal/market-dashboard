// In-memory sliding window rate limiter for Edge Functions
// Uses Deno global state — persists across requests within the same isolate
//
// ⚠️ PERFORMANCE (P5): KNOWN LIMITATION — this rate limiter is per-isolate
// only. Supabase Edge Functions run in multiple isolates, so in-memory state
// is NOT shared across instances. This means:
//   - A user hitting different isolates may exceed the rate limit
//   - Rate limiting is "best effort" — it prevents abuse within a single
//     isolate but is NOT a hard guarantee
//   - For the place-order endpoint (5/min/customer), a determined attacker
//     with concurrent connections across isolates could exceed this. The
//     duplicate-order check (10s window in place-order/index.ts) provides
//     a secondary defense for the most abuse-prone endpoint.
//
// TODO (Phase 11): Replace with Redis-based rate limiting (e.g., Upstash)
// for distributed, consistent rate limiting across all isolates.
// Example: const rl = await redis.incr(key); await redis.expire(key, window);
//
// For now, this is acceptable because:
//   1. Most Edge Function requests from the same user tend to hit the same
//      isolate (Deno's routing is somewhat sticky)
//   2. The rate limits are generous enough that occasional overages are fine
//   3. True distributed rate limiting requires external infrastructure
//
// SECURITY NOTE: Do NOT rely on this rate limiter as the sole defense
// against abuse for any endpoint that creates state (place-order, admin
// actions). Pair it with idempotency keys, duplicate-detection, or
// server-side validation as appropriate.

// B1-G2: one-time startup warning so the per-isolate limitation is visible
// in Edge Function logs. Without this, a deployer reading the logs has no
// indication that rate limits are "best effort" only.
let _rateLimitWarningLogged = false;
function logRateLimitWarning() {
  if (_rateLimitWarningLogged) return;
  _rateLimitWarningLogged = true;
  console.warn(
    '[rate-limit] Using in-memory per-isolate rate limiter. ' +
      'Rate limits are BEST-EFFORT only — a user hitting different isolates may exceed the limit. ' +
      'For hard rate limiting, deploy Redis-based limiting (see file comment).'
  );
}

interface RateLimitEntry {
  timestamps: number[];
}

// Global rate limit store (persists within Edge Function isolate lifetime)
const rateLimitStore = new Map<string, RateLimitEntry>();

// Cleanup old entries every 60 seconds
let lastCleanup = Date.now();
const CLEANUP_INTERVAL = 60_000;

function cleanup() {
  const now = Date.now();
  if (now - lastCleanup < CLEANUP_INTERVAL) return;
  lastCleanup = now;
  const cutoff = now - 120_000; // Remove entries older than 2 minutes
  for (const [key, entry] of rateLimitStore.entries()) {
    entry.timestamps = entry.timestamps.filter((t) => t > cutoff);
    if (entry.timestamps.length === 0) {
      rateLimitStore.delete(key);
    }
  }
}

export interface RateLimitConfig {
  maxRequests: number;
  windowMs: number;
}

/**
 * Check rate limit for a given key.
 * Returns { allowed: true } or { allowed: false, retryAfterMs: number }
 *
 * NOTE: This is per-isolate only. See file-level comment for details.
 */
export function checkRateLimit(
  key: string,
  config: RateLimitConfig,
): { allowed: true } | { allowed: false; retryAfterMs: number } {
  logRateLimitWarning();
  cleanup();
  const now = Date.now();
  const windowStart = now - config.windowMs;

  let entry = rateLimitStore.get(key);
  if (!entry) {
    entry = { timestamps: [] };
    rateLimitStore.set(key, entry);
  }

  // Remove timestamps outside the window
  entry.timestamps = entry.timestamps.filter((t) => t > windowStart);

  if (entry.timestamps.length >= config.maxRequests) {
    const oldestInWindow = entry.timestamps[0];
    const retryAfterMs = oldestInWindow + config.windowMs - now;
    return { allowed: false, retryAfterMs: Math.max(retryAfterMs, 1000) };
  }

  entry.timestamps.push(now);
  return { allowed: true };
}

// Pre-defined rate limit configs
export const RATE_LIMITS = {
  PLACE_ORDER: { maxRequests: 5, windowMs: 60_000 },
  CANCEL_ORDER: { maxRequests: 10, windowMs: 60_000 },
  VALIDATE_PROMO: { maxRequests: 10, windowMs: 60_000 },
  MERCHANT_FEED: { maxRequests: 30, windowMs: 60_000 },
  SEARCH: { maxRequests: 30, windowMs: 60_000 },
  FEE_PREVIEW: { maxRequests: 15, windowMs: 60_000 },
  DRIVER_LOCATION: { maxRequests: 15, windowMs: 60_000 },
  DRIVER_RESPOND: { maxRequests: 10, windowMs: 60_000 },
  COMPLETE_DELIVERY: { maxRequests: 10, windowMs: 60_000 },
  ASSIGN_DRIVER: { maxRequests: 20, windowMs: 60_000 },
  SEND_NOTIFICATION: { maxRequests: 100, windowMs: 60_000 },
  ADMIN_CREATE_DRIVER: { maxRequests: 10, windowMs: 3_600_000 },
  ADMIN_REVIEW_DRIVER: { maxRequests: 20, windowMs: 3_600_000 },
  ADMIN_DEACTIVATE_DRIVER: { maxRequests: 10, windowMs: 3_600_000 },
  // admin-api dashboard reads. Generous per minute because the Overview page
  // fires four of them at once (kpis, series, trending, recent orders) and an
  // operator switching the 7/30/90 range selector adds another series call.
  ADMIN_DASHBOARD_READ: { maxRequests: 120, windowMs: 60_000 },
  // admin-api WRITES. Far tighter than reads because these change state that
  // customers see, and because the limiter is per-isolate and best-effort (see
  // the header) — it is a speed bump, not the guard. The real guard is the
  // state-machine checks in each handler (no-op transitions are rejected, and
  // publish refuses unless approved).
  ADMIN_MERCHANT_WRITE: { maxRequests: 30, windowMs: 60_000 },
  PAYMOB_WEBHOOK: { maxRequests: 100, windowMs: 60_000 },
} as const;
