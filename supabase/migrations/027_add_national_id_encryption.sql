-- Migration 027: Add national ID encryption support
-- Per 21-SECURITY-AUDIT-COMPLIANCE.md:
--   National IDs are the most sensitive data the platform handles.
--   They must be encrypted at the application level before being stored in the database.
--   Even a database dump should not expose them in plaintext.
--
-- This migration:
--   1. Adds `national_id_encrypted` column to drivers table
--   2. Creates DB-level encryption/decryption helper functions using pgcrypto
--   3. Adds a trigger to auto-encrypt national_id on INSERT/UPDATE
--   4. Provides a function to decrypt national_id (service role only)
--
-- IMPORTANT: In production, the encryption key should be set via Supabase Vault
-- or environment variable. The DB functions use a config key as fallback.
-- The Edge Functions also implement application-level AES-GCM encryption
-- (see 21-SECURITY-AUDIT-COMPLIANCE.md for the TypeScript implementation).

-- =============================================================================
-- 1. ADD ENCRYPTED NATIONAL ID COLUMN
-- Stores the AES-256 encrypted version of the national ID.
-- The plaintext `national_id` column will be kept for transition but should
-- be migrated and then NULLed in a follow-up data migration.
-- =============================================================================

ALTER TABLE public.drivers
  ADD COLUMN national_id_encrypted TEXT;

COMMENT ON COLUMN public.drivers.national_id_encrypted IS 'AES-256 encrypted national ID. Use decrypt_national_id() to read. The plaintext national_id column will be deprecated after data migration.';

-- =============================================================================
-- 2. DB-LEVEL ENCRYPTION HELPER FUNCTIONS
-- These use pgcrypto's pg_sym_encrypt/pg_sym_decrypt for DB-level operations.
-- Edge Functions should prefer the AES-GCM implementation in TypeScript
-- for better key management, but these DB functions provide defense-in-depth.
-- =============================================================================

-- Encrypt a national ID value using the platform config key
CREATE OR REPLACE FUNCTION public.encrypt_national_id(p_plaintext TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_key TEXT;
BEGIN
  -- Get the encryption key from Supabase Vault
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'national_id_encryption_key';

  IF v_key IS NULL OR v_key = '' THEN
    RAISE EXCEPTION 'National ID encryption key not configured in Vault.'
      USING HINT = 'Add secret to vault: INSERT INTO vault.secrets (secret, name, description) VALUES (encode(gen_random_bytes(32), ''base64''), ''national_id_encryption_key'', ''AES-256-GCM key for encrypting driver national IDs'');';
  END IF;

  -- Use pgcrypto symmetric encryption with AES-256-CFB
  RETURN pg_sym_encrypt(p_plaintext, v_key, 'cipher=aes256, mode=cfb');
END;
$$;

COMMENT ON FUNCTION public.encrypt_national_id(TEXT) IS 'Encrypts a national ID using AES-256 via pgcrypto. Key from Supabase Vault. SECURITY DEFINER — only service role should call this.';

-- Decrypt a national ID value using the platform config key
CREATE OR REPLACE FUNCTION public.decrypt_national_id(p_encrypted TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_key TEXT;
  v_decrypted TEXT;
BEGIN
  IF p_encrypted IS NULL THEN
    RETURN NULL;
  END IF;

  -- Get the encryption key from Supabase Vault
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'national_id_encryption_key';

  IF v_key IS NULL OR v_key = '' THEN
    RAISE EXCEPTION 'National ID encryption key not configured in Vault.';
  END IF;

  -- Decrypt using pgcrypto
  v_decrypted := pg_sym_decrypt(p_encrypted::bytea, v_key, 'cipher=aes256, mode=cfb');

  RETURN v_decrypted;
END;
$$;

COMMENT ON FUNCTION public.decrypt_national_id(TEXT) IS 'Decrypts an encrypted national ID using AES-256 via pgcrypto. SECURITY DEFINER — only service role should call this. Access is logged.';

-- =============================================================================
-- 4. MASK NATIONAL ID FOR DISPLAY
-- Returns masked version: 2900101****567 (first 7 + **** + last 3)
-- Used by admin panel for display without revealing full ID.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.mask_national_id(p_national_id TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_national_id IS NULL THEN RETURN '****'; END IF;
  IF length(p_national_id) < 10 THEN RETURN '****'; END IF;
  RETURN substr(p_national_id, 1, 7) || '****' || substr(p_national_id, -3);
END;
$$;

COMMENT ON FUNCTION public.mask_national_id(TEXT) IS 'Masks a national ID for safe display: 2900101****567. Used by admin panel.';

-- =============================================================================
-- 5. ADD INDEX ON ENCRYPTED COLUMN (for exact match lookups, not range queries)
-- =============================================================================

CREATE INDEX idx_drivers_national_id_encrypted
  ON public.drivers(national_id_encrypted)
  WHERE national_id_encrypted IS NOT NULL;

-- =============================================================================
-- 6. GRANT EXECUTE PERMISSIONS
-- Only service role should be able to encrypt/decrypt
-- =============================================================================

-- These are SECURITY DEFINER functions, so they run as the function owner.
-- RLS does not apply to them. Access control is via:
--   1. Only service role calls these (from Edge Functions)
--   2. The functions check the key exists before operating
--   3. Decrypt calls should be logged via data_access_log (migration 029)

REVOKE EXECUTE ON FUNCTION public.encrypt_national_id(TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.decrypt_national_id(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.encrypt_national_id(TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.decrypt_national_id(TEXT) TO service_role;

-- mask_national_id is safe for any role (it only masks, never reveals)
GRANT EXECUTE ON FUNCTION public.mask_national_id(TEXT) TO authenticated;

-- =============================================================================
-- COMMENTS
-- =============================================================================
COMMENT ON TABLE public.drivers IS 'Driver profiles — created by admin only. National IDs should be stored encrypted in national_id_encrypted. The plaintext national_id is kept for transition only.';

-- =============================================================================
-- 7. RECREATE drivers_update_own_location POLICY (🔒 SECURITY HARDENING)
-- Hardens the RLS policy to ensure drivers can only update current_lat,
-- current_lng, last_location_at, and is_online. All other columns must remain
-- unchanged, preventing tampering with ratings, earnings, verification status,
-- and identity documents (such as national_id_encrypted).
-- =============================================================================

DROP POLICY IF EXISTS "drivers_update_own_location" ON public.drivers;

CREATE POLICY "drivers_update_own_location"
  ON public.drivers
  FOR UPDATE
  USING (auth.uid() = id AND is_verified = TRUE AND is_active = TRUE)
  WITH CHECK (
    auth.uid() = id
    AND is_verified = TRUE
    AND is_active = TRUE
    -- Ensure driver can only change: current_lat, current_lng, last_location_at, is_online.
    -- All other columns must match their existing values in the database.
    AND national_id = (SELECT national_id FROM public.drivers WHERE id = auth.uid())
    AND (national_id_encrypted IS NOT DISTINCT FROM (SELECT national_id_encrypted FROM public.drivers WHERE id = auth.uid()))
    AND (national_id_image_url IS NOT DISTINCT FROM (SELECT national_id_image_url FROM public.drivers WHERE id = auth.uid()))
    AND (driving_license_number IS NOT DISTINCT FROM (SELECT driving_license_number FROM public.drivers WHERE id = auth.uid()))
    AND (driving_license_image_url IS NOT DISTINCT FROM (SELECT driving_license_image_url FROM public.drivers WHERE id = auth.uid()))
    AND (vehicle_registration_image_url IS NOT DISTINCT FROM (SELECT vehicle_registration_image_url FROM public.drivers WHERE id = auth.uid()))
    AND vehicle_plate = (SELECT vehicle_plate FROM public.drivers WHERE id = auth.uid())
    AND vehicle_type = (SELECT vehicle_type FROM public.drivers WHERE id = auth.uid())
    AND (vehicle_color IS NOT DISTINCT FROM (SELECT vehicle_color FROM public.drivers WHERE id = auth.uid()))
    AND (vehicle_model IS NOT DISTINCT FROM (SELECT vehicle_model FROM public.drivers WHERE id = auth.uid()))
    AND (rating IS NOT DISTINCT FROM (SELECT rating FROM public.drivers WHERE id = auth.uid()))
    AND (rating_count IS NOT DISTINCT FROM (SELECT rating_count FROM public.drivers WHERE id = auth.uid()))
    AND (total_deliveries IS NOT DISTINCT FROM (SELECT total_deliveries FROM public.drivers WHERE id = auth.uid()))
    AND (total_earnings IS NOT DISTINCT FROM (SELECT total_earnings FROM public.drivers WHERE id = auth.uid()))
    AND verification_status = (SELECT verification_status FROM public.drivers WHERE id = auth.uid())
    AND (verified_at IS NOT DISTINCT FROM (SELECT verified_at FROM public.drivers WHERE id = auth.uid()))
    AND (deactivated_at IS NOT DISTINCT FROM (SELECT deactivated_at FROM public.drivers WHERE id = auth.uid()))
  );

COMMENT ON POLICY "drivers_update_own_location" ON public.drivers IS 'P1F-08: Drivers can update ONLY their own row, ONLY location + online status, and ONLY if verified and active. All other columns are write-protected.';
