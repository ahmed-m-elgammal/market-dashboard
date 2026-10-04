// Paymob payment integration with auth token caching
// Per RED-18: Cache Paymob auth token with 55-minute expiry to avoid
// re-authenticating on every payment (saves ~200ms per call).
//
// Handles the 3-step Paymob payment flow:
//   1. Auth token (cached for 55 min)
//   2. Register order with Paymob
//   3. Generate payment key for iframe
//
// All secrets are read from environment variables.
// For production, these should be stored in Supabase Vault (P3D-02).
//
// PERFORMANCE (P4): KNOWN LIMITATION — `_paymobAuthToken` is module-level
// state, which in Deno Edge Functions means PER-ISOLATE. Supabase spins up
// multiple isolates; each will re-auth with Paymob on its first request
// after cold start. With N isolates and a 55-min TTL, that's N extra auth
// calls per 55 minutes — acceptable at current scale.
//
// To share the cache across isolates, move token storage to a shared
// backend (e.g. Supabase `vault.decrypted_secrets` with a TTL column, or
// Upstash Redis with a SETEX key). Do NOT move it to a global Map — that
// has the same per-isolate limitation as the current implementation.
//
// Token refresh is also racy under high concurrency: two concurrent calls
// to getPaymobAuthToken() after expiry will both fetch new tokens. The
// second one wins; the first token is wasted. Acceptable because Paymob
// tokens are stateless and ~200ms is below the user-perceived threshold.
// If this becomes a problem, wrap the fetch in a deduplication promise
// (in-flight request map) keyed by "paymob-auth".
import { fetchWithTimeout } from './supabase.ts';

export interface PaymobPaymentResult {
  payment_key: string;
  iframe_url: string;
  paymob_order_id: string;
}

// Cached auth token (persists within Edge Function isolate lifetime)
let _paymobAuthToken: string | null = null;
let _paymobTokenExpiry = 0;
const TOKEN_TTL_MS = 55 * 60 * 1000; // 55 minutes (Paymob tokens are valid ~1 hour)

/**
 * Get a cached Paymob auth token, or fetch a new one if expired.
 */
async function getPaymobAuthToken(): Promise<string> {
  // Return cached token if still valid
  if (_paymobAuthToken && Date.now() < _paymobTokenExpiry) {
    return _paymobAuthToken;
  }

  const apiKey = Deno.env.get('PAYMOB_API_KEY');
  if (!apiKey) {
    throw new Error('PAYMOB_API_KEY environment variable is not set. Configure it in Supabase Vault.');
  }

  const res = await fetchWithTimeout('https://accept.paymob.com/api/auth/tokens', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ api_key: apiKey }),
  });

  if (!res.ok) {
    const errorText = await res.text();
    throw new Error(`Paymob auth failed (${res.status}): ${errorText}`);
  }

  const data = await res.json();
  if (!data.token) {
    throw new Error('Paymob auth response missing token');
  }

  _paymobAuthToken = data.token;
  _paymobTokenExpiry = Date.now() + TOKEN_TTL_MS;

  return _paymobAuthToken;
}

/**
 * Initiate a Paymob payment: auth → register order → payment key → iframe URL
 *
 * @param amount - Total amount in EGP
 * @param paymentMethod - One of: card, vodafone_cash, instapay, orange_cash
 * @param customerId - Our customer UUID (used as merchant_order_id suffix)
 * @param customerEmail - Customer's email for billing data
 * @param customerPhone - Customer's phone for billing data
 * @returns Payment key, iframe URL, and Paymob order ID
 */
export async function initiatePaymobPayment(
  amount: number,
  paymentMethod: string,
  customerId: string,
  customerEmail?: string,
  customerPhone?: string,
): Promise<PaymobPaymentResult> {
  const integrationId = Deno.env.get('PAYMOB_INTEGRATION_ID');
  const iframeId = Deno.env.get('PAYMOB_IFRAME_ID');

  if (!integrationId) {
    throw new Error('PAYMOB_INTEGRATION_ID environment variable is not set. Configure it in Supabase Vault.');
  }

  // Step 1: Auth token (cached)
  const authToken = await getPaymobAuthToken();

  // Step 2: Register order with Paymob
  const orderRes = await fetchWithTimeout('https://accept.paymob.com/api/ecommerce/orders', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      auth_token: authToken,
      delivery_needed: true,
      amount_cents: Math.round(amount * 100),
      currency: 'EGP',
      merchant_order_id: `ord_${customerId.slice(0, 8)}_${Date.now()}`,
      items: [],
    }),
  });

  if (!orderRes.ok) {
    const errorText = await orderRes.text();
    throw new Error(`Paymob order registration failed (${orderRes.status}): ${errorText}`);
  }

  const orderData = await orderRes.json();
  const paymobOrderId = String(orderData.id);

  // Step 3: Generate payment key
  const billingData = {
    first_name: 'Customer',
    last_name: 'Customer',
    email: customerEmail || `${customerId.slice(0, 8)}@deliveryapp.com`,
    phone_number: customerPhone || '+201000000000',
    apartment: 'NA',
    floor: 'NA',
    building: 'NA',
    street: 'NA',
    city: 'Cairo',
    country: 'EG',
  };

  const paymentKeyRes = await fetchWithTimeout('https://accept.paymob.com/api/acceptance/payment_keys', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      auth_token: authToken,
      amount_cents: Math.round(amount * 100),
      expiration: 3600, // Payment key valid for 1 hour
      order_id: paymobOrderId,
      billing_data: billingData,
      currency: 'EGP',
      integration_id: Number(integrationId),
    }),
  });

  if (!paymentKeyRes.ok) {
    const errorText = await paymentKeyRes.text();
    throw new Error(`Paymob payment key failed (${paymentKeyRes.status}): ${errorText}`);
  }

  const paymentKeyData = await paymentKeyRes.json();
  if (!paymentKeyData.token) {
    throw new Error('Paymob payment key response missing token');
  }

  const iframeIdValue = iframeId || 'DEFAULT';
  const iframeUrl = `https://accept.paymob.com/api/acceptance/iframes/${iframeIdValue}?payment_token=${paymentKeyData.token}`;

  return {
    payment_key: paymentKeyData.token,
    iframe_url: iframeUrl,
    paymob_order_id: paymobOrderId,
  };
}

/**
 * Query Paymob for the current status of a payment transaction.
 *
 * A1-G5: used by the reconcile-payments cron EF to resolve stale `pending`
 * digital-payment orders whose webhook never arrived (or arrived non-2xx and
 * was retried by Paymob too late). Calls Paymob's /api/acceptance/transactions
 * /{id} endpoint with the cached auth token.
 *
 * @param paymobOrderId - The Paymob order ID (stored on orders.paymob_order_id
 *   at place-order time). Paymob's transaction query API accepts the Paymob
 *   *order* id, not our internal order id.
 * @returns Object with `success` (boolean) and `pending` (boolean) flags.
 *   - success=true, pending=false → payment captured, order should be marked 'paid'
 *   - success=false, pending=false → payment failed/voided, order should be
 *     marked 'failed' (and auto-cancelled by the cron)
 *   - pending=true → Paymob hasn't reached a terminal state; the cron should
 *     leave the order alone and retry on the next run
 */
export interface PaymobTransactionStatus {
  success: boolean;
  pending: boolean;
}

export async function getPaymobTransactionStatus(
  paymobOrderId: string,
): Promise<PaymobTransactionStatus> {
  const authToken = await getPaymobAuthToken();

  // Paymob's transaction query endpoint: list transactions for this order id.
  // Returns an array; we take the first (most recent) transaction.
  const res = await fetchWithTimeout(
    `https://accept.paymob.com/api/ecommerce/orders/${paymobOrderId}/transactions`,
    {
      method: 'GET',
      headers: { Authorization: `Bearer ${authToken}` },
    },
  );

  if (!res.ok) {
    const errorText = await res.text();
    throw new Error(`Paymob transaction query failed (${res.status}): ${errorText}`);
  }

  const data = await res.json();
  // Paymob returns { count, results: [...] } — results is the transactions array.
  const transactions = Array.isArray(data) ? data : (data.results ?? []);
  if (transactions.length === 0) {
    // No transactions yet — payment key was generated but customer never
    // completed the iframe flow. Treat as pending (the cron will eventually
    // cancel after the configured timeout).
    return { success: false, pending: true };
  }

  const tx = transactions[0];
  // Paymob transaction fields: `success` (bool), `pending` (bool).
  // A transaction is terminal when pending=false.
  const success = Boolean(tx.success);
  const pending = Boolean(tx.pending);
  return { success, pending };
}

/**
 * Initiate a Paymob refund for a captured payment.
 *
 * A2-G5: called by the cancel-order EF after the cancel_order RPC succeeds
 * for a digital-payment order with `payment_status = 'paid'`. The refund
 * amount comes from the RPC's refund_amount field (computed from
 * cancellation_rules).
 *
 * @param paymobOrderId - The Paymob order ID (orders.paymob_order_id).
 * @param amountCents - Refund amount in cents (Math.round(refundAmount * 100)).
 * @returns Paymob's refund transaction ID on success.
 * @throws if the refund API call fails or the Paymob config is missing.
 */
export async function refundPaymobPayment(
  paymobOrderId: string,
  amountCents: number,
): Promise<string> {
  const authToken = await getPaymobAuthToken();

  // Paymob refund API: POST /api/acceptance/void_refund_refund with
  // auth_token, order_id, amount_cents.
  const res = await fetchWithTimeout('https://accept.paymob.com/api/acceptance/void_refund_refund', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      auth_token: authToken,
      order_id: paymobOrderId,
      amount_cents: amountCents,
    }),
  });

  if (!res.ok) {
    const errorText = await res.text();
    throw new Error(`Paymob refund failed (${res.status}): ${errorText}`);
  }

  const data = await res.json();
  if (!data.id) {
    throw new Error('Paymob refund response missing transaction id');
  }

  return String(data.id);
}

/**
 * Verify HMAC signature from Paymob webhook.
 */
export async function verifyPaymobHmac(
  params: URLSearchParams,
): Promise<{ valid: boolean; error?: string }> {
  const hmacSecret = Deno.env.get('PAYMOB_HMAC_SECRET');

  if (!hmacSecret) {
    // SECURITY: Fail closed — if HMAC secret is not configured,
    // we MUST reject all webhooks. Without HMAC verification,
    // anyone can send fake payment confirmations.
    return {
      valid: false,
      error: 'PAYMOB_HMAC_SECRET is not configured. Webhook verification is impossible. Configure it in Supabase Vault.',
    };
  }

  const hmac = params.get('hmac');
  if (!hmac) {
    return { valid: false, error: 'Missing HMAC signature in webhook payload' };
  }

  // Paymob HMAC fields in the exact order specified by Paymob docs
  const hmacFields = [
    'amount_cents', 'created_at', 'currency', 'error_occured',
    'has_parent_transaction', 'id', 'integration_id', 'is_3d_secure',
    'is_auth', 'is_capture', 'is_refunded', 'is_standalone_payment',
    'is_voided', 'order.id', 'owner', 'pending',
    'source_data.pan', 'source_data.sub_type', 'source_data.type', 'success',
  ];

  const concatenated = hmacFields.map((field) => {
    // Paymob flat callback sends order ID under the key 'order'
    const key = field === 'order.id' ? 'order' : field;
    return params.get(key) || '';
  }).join('');

  // Compute HMAC-SHA256
  const encoder = new TextEncoder();
  const keyData = encoder.encode(hmacSecret);
  const msgData = encoder.encode(concatenated);
  const cryptoKey = await crypto.subtle.importKey(
    'raw', keyData, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  const signature = await crypto.subtle.sign('HMAC', cryptoKey, msgData);
  const computedHmac = Array.from(new Uint8Array(signature))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');

  // Sprint 2 fix (S26): constant-time string comparison to prevent timing
  // attacks that could leak bytes of the expected HMAC. The previous
  // `computedHmac !== hmac` short-circuited on the first differing byte,
  // theoretically allowing an attacker who can measure response time
  // precisely to recover the signature byte-by-byte. Low practical risk
  // (Paymob webhooks come from a fixed IP range, and the attacker needs
  // many precise measurements), but the codebase uses timingSafeEqual
  // elsewhere (send-notification, driver-actions) — applying it here too
  // is consistent.
  if (!timingSafeEqualHex(computedHmac, hmac)) {
    return { valid: false, error: 'HMAC verification failed — possible spoofed webhook' };
  }

  return { valid: true };
}

/**
 * Constant-time string comparison for hex-encoded HMAC digests.
 * Iterates over the full length regardless of where the first difference
 * is, so response time leaks no information about the expected value.
 */
function timingSafeEqualHex(a: string, b: string): boolean {
  if (a.length !== b.length) {
    // Still iterate over the longer string to avoid length-based timing.
    const maxLen = Math.max(a.length, b.length);
    let result = 1;
    for (let i = 0; i < maxLen; i++) {
      const charA = i < a.length ? a.charCodeAt(i) : 0;
      const charB = i < b.length ? b.charCodeAt(i) : 0;
      result |= charA ^ charB;
    }
    return result === 0;
  }
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}
