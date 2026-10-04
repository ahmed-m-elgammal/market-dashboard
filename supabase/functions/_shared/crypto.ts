// National ID encryption/decryption using AES-256-GCM
// Per security spec (doc 21-SECURITY-AUDIT-COMPLIANCE.md):
//   - National IDs are encrypted before storage at the application level
//   - Ensures even a database dump would not expose them
//   - Decrypted only when needed for verification
//   - Key stored in environment variable NATIONAL_ID_ENCRYPTION_KEY (base64-encoded 32-byte key)
//
// Migration 027 (add_national_id_encryption) alters the drivers.national_id column
// to store encrypted values.

const ALGORITHM = 'AES-GCM';
const IV_LENGTH = 12; // 96-bit IV for AES-GCM
const KEY_LENGTH = 32; // 256-bit key

/**
 * Encrypt a national ID string using AES-256-GCM.
 * Returns a base64-encoded string containing IV + ciphertext + authTag.
 */
export async function encryptNationalId(nationalId: string): Promise<string> {
  const key = await getCryptoKey();
  const iv = crypto.getRandomValues(new Uint8Array(IV_LENGTH));
  const encoded = new TextEncoder().encode(nationalId);

  const ciphertext = await crypto.subtle.encrypt(
    { name: ALGORITHM, iv },
    key,
    encoded,
  );

  // Combine IV + ciphertext (authTag is appended automatically by AES-GCM)
  const combined = new Uint8Array(iv.length + new Uint8Array(ciphertext).length);
  combined.set(iv);
  combined.set(new Uint8Array(ciphertext), iv.length);

  return btoa(String.fromCharCode(...combined));
}

/**
 * Decrypt a previously encrypted national ID.
 * Expects a base64-encoded string containing IV + ciphertext + authTag.
 */
export async function decryptNationalId(encrypted: string): Promise<string> {
  const key = await getCryptoKey();
  const combined = Uint8Array.from(atob(encrypted), (c) => c.charCodeAt(0));
  const iv = combined.slice(0, IV_LENGTH);
  const ciphertext = combined.slice(IV_LENGTH);

  const decrypted = await crypto.subtle.decrypt(
    { name: ALGORITHM, iv },
    key,
    ciphertext,
  );

  return new TextDecoder().decode(decrypted);
}

/**
 * Check if a string appears to be encrypted (base64-encoded IV+ciphertext).
 * Encrypted values are base64 strings that decode to at least IV_LENGTH + 16 bytes.
 * Plain national IDs are exactly 14 digits.
 */
export function isEncrypted(value: string): boolean {
  if (/^\d{14}$/.test(value)) return false; // Plain 14-digit national ID
  try {
    const decoded = atob(value);
    return decoded.length >= IV_LENGTH + 16; // IV + at least one AES block
  } catch {
    return false;
  }
}

/**
 * Generate a new encryption key for NATIONAL_ID_ENCRYPTION_KEY env var.
 * Run once during initial setup and store the output in Supabase Vault.
 */
export function generateEncryptionKey(): string {
  const keyBytes = crypto.getRandomValues(new Uint8Array(KEY_LENGTH));
  return btoa(String.fromCharCode(...keyBytes));
}

// Internal: import the AES key from the environment variable
let _cachedKey: CryptoKey | null = null;

async function getCryptoKey(): Promise<CryptoKey> {
  if (_cachedKey) return _cachedKey;

  const rawKey = Deno.env.get('NATIONAL_ID_ENCRYPTION_KEY');
  if (!rawKey) {
    throw new Error(
      'NATIONAL_ID_ENCRYPTION_KEY environment variable is not set. ' +
      'Generate one with generateEncryptionKey() and store it in Supabase Vault.',
    );
  }

  const keyData = Uint8Array.from(atob(rawKey), (c) => c.charCodeAt(0));
  if (keyData.length !== KEY_LENGTH) {
    throw new Error(
      `NATIONAL_ID_ENCRYPTION_KEY must be ${KEY_LENGTH} bytes (base64-encoded). ` +
      `Got ${keyData.length} bytes.`,
    );
  }

  _cachedKey = await crypto.subtle.importKey(
    'raw',
    keyData,
    { name: ALGORITHM },
    false, // not extractable
    ['encrypt', 'decrypt'],
  );

  return _cachedKey;
}

// =============================================================================
// Timing-safe string comparison (gap-analysis §3.3)
// =============================================================================
// Used by scheduled Edge Functions (auto-generate-driver-settlements,
// auto-generate-merchant-payouts, reconcile-payments) to compare the
// Authorization header bearer token against the SUPABASE_SERVICE_ROLE_KEY
// without leaking bytes of the expected value through response time.
//
// Mirrors the timingSafeEqualHex helper in _shared/paymob.ts (used for HMAC
// verification) but operates on arbitrary UTF-8 strings rather than hex
// digests. The implementation iterates over the full length regardless of
// where the first difference is, so response time leaks no information
// about the expected value.
//
// Practical risk note: exploiting a timing attack on a long random JWT
// requires thousands of precise measurements from a network position close
// to the EF runtime. Low risk in practice. The fix is applied for
// consistency with the HMAC path and because the helper is one function.

/**
 * Constant-time string comparison.
 * Returns true iff `a` and `b` are byte-equal. Iterates over the full
 * length of the longer string even when lengths differ, so response time
 * leaks no information about the expected value.
 */
export function timingSafeEqualString(a: string, b: string): boolean {
  const maxLen = Math.max(a.length, b.length);
  // Use a single loop bound by maxLen so the runtime is independent of
  // which string is shorter. The result accumulator is OR-ed (|) so any
  // differing byte sets a non-zero bit; we check `=== 0` at the end.
  let result = a.length ^ b.length; // 0 if same length, non-zero otherwise
  for (let i = 0; i < maxLen; i++) {
    const ca = i < a.length ? a.charCodeAt(i) : 0;
    const cb = i < b.length ? b.charCodeAt(i) : 0;
    result |= ca ^ cb;
  }
  return result === 0;
}
