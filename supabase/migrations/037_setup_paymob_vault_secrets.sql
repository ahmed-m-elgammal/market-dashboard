-- ============================================================
-- Paymob Secret Setup for Supabase Vault
-- P3D-01 + P3D-02: External account setup + Vault storage
--
-- This migration creates the Vault secrets for Paymob integration.
-- In production, the actual secret VALUES should be set via:
--   1. Supabase Dashboard → Vault → Add Secret
--   2. Or: `supabase secrets set PAYMOB_API_KEY=xxx` (CLI)
--   3. Or: The SQL below with actual values (NOT for version control)
--
-- SECURITY: Never commit actual secret values to version control.
-- The INSERT statements below use placeholder values that MUST be
-- replaced with real values from the Paymob merchant dashboard.
-- ============================================================

-- First, ensure the vault extension is available
CREATE EXTENSION IF NOT EXISTS supabase_vault;

-- ============================================================
-- Paymob API Key (used for authentication)
-- Replace 'YOUR_PAYMOB_API_KEY' with the actual key from Paymob Dashboard
-- ============================================================
-- NOTE: In Supabase, Vault secrets are typically managed via the Dashboard
-- or the `vault` schema. The following is a template for reference.
-- Actual secret creation should be done through the Supabase Dashboard:
--   Project Settings → Vault → New Secret

-- Template (DO NOT commit with real values):
-- INSERT INTO vault.secrets (secret, name, description)
-- VALUES (
--   'YOUR_PAYMOB_API_KEY',
--   'paymob_api_key',
--   'Paymob API key for payment authentication - get from accept.paymob.com dashboard'
-- );

-- Template for integration ID:
-- INSERT INTO vault.secrets (secret, name, description)
-- VALUES (
--   'YOUR_PAYMOB_INTEGRATION_ID',
--   'paymob_integration_id',
--   'Paymob integration ID for card/mobile wallet payments'
-- );

-- Template for iframe ID:
-- INSERT INTO vault.secrets (secret, name, description)
-- VALUES (
--   'YOUR_PAYMOB_IFRAME_ID',
--   'paymob_iframe_id',
--   'Paymob iframe ID for hosted payment page'
-- );

-- Template for HMAC secret:
-- INSERT INTO vault.secrets (secret, name, description)
-- VALUES (
--   'YOUR_PAYMOB_HMAC_SECRET',
--   'paymob_hmac_secret',
--   'Paymob HMAC secret for webhook signature verification'
-- );

-- ============================================================
-- National ID Encryption Key
-- Generate a new key using the Edge Function crypto.generateEncryptionKey()
-- or the SQL below:
-- ============================================================

-- Generate a random 32-byte key for AES-256-GCM encryption
-- Store this key securely — losing it means all encrypted national IDs become unrecoverable
-- DO NOT commit the actual key value to version control

-- Template:
-- INSERT INTO vault.secrets (secret, name, description)
-- VALUES (
--   encode(gen_random_bytes(32), 'base64'),
--   'national_id_encryption_key',
--   'AES-256-GCM key for encrypting driver national IDs - DO NOT LOSE'
-- );

-- ============================================================
-- Verification: Check that vault extension is active
-- ============================================================
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'supabase_vault') THEN
    RAISE NOTICE 'Supabase Vault extension is active. Configure secrets via Dashboard.';
  ELSE
    RAISE WARNING 'Supabase Vault extension is NOT active. Install it before storing secrets.';
  END IF;
END $$;
