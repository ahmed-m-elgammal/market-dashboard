-- Migration 089: Schedule Edge Functions via pg_cron
--
-- This migration schedules the 5 background Edge Functions that were previously
-- incorrectly configured with the invalid "schedule" key in config.toml.
--
-- Functions scheduled:
--   1. reconcile-payments (every 5 minutes)
--   2. auto-expiry-promos (every 5 minutes)
--   3. auto-issue-loyalty-promos (daily at 02:00 UTC)
--   4. auto-generate-driver-settlements (daily at 03:30 UTC)
--   5. auto-generate-merchant-payouts (daily at 03:00 UTC)

-- Ensure required extensions are enabled
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Helper function to trigger Edge Functions securely
CREATE OR REPLACE FUNCTION public.invoke_edge_function(
  p_function_name text,
  p_payload jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_project_url text;
  v_service_role_key text;
  v_url text;
  v_headers jsonb;
BEGIN
  -- 1. Resolve project URL from Vault
  SELECT decrypted_secret INTO v_project_url
  FROM vault.decrypted_secrets
  WHERE name = 'project_url';
  
  -- If not set, default to local Kong gateway inside the Docker network
  IF v_project_url IS NULL OR v_project_url = '' THEN
    v_project_url := 'http://kong:8000';
  END IF;

  v_url := v_project_url || '/functions/v1/' || p_function_name;

  -- 2. Resolve service role key from Vault
  SELECT decrypted_secret INTO v_service_role_key
  FROM vault.decrypted_secrets
  WHERE name = 'service_role_key';

  -- 3. Construct headers
  v_headers := jsonb_build_object(
    'Content-Type', 'application/json'
  );
  
  IF v_service_role_key IS NOT NULL AND v_service_role_key <> '' THEN
    v_headers := v_headers || jsonb_build_object('Authorization', 'Bearer ' || v_service_role_key);
  END IF;

  -- 4. Invoke the Edge Function via pg_net
  PERFORM net.http_post(
    url := v_url,
    headers := v_headers,
    body := p_payload
  );
END;
$$;

COMMENT ON FUNCTION public.invoke_edge_function(text, jsonb) IS
  'Trigger an Edge Function via pg_net, resolving project_url and service_role_key from Vault.';

-- Revoke execute from public to protect the invoker
REVOKE EXECUTE ON FUNCTION public.invoke_edge_function(text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.invoke_edge_function(text, jsonb) TO service_role;

-- =============================================================================
-- Schedule Cron Jobs (Idempotent)
-- =============================================================================
DO $$
BEGIN
  -- Unschedule existing jobs to prevent duplicates
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'reconcile-payments-cron') THEN
    PERFORM cron.unschedule('reconcile-payments-cron');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'auto-expiry-promos-cron') THEN
    PERFORM cron.unschedule('auto-expiry-promos-cron');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'auto-issue-loyalty-promos-cron') THEN
    PERFORM cron.unschedule('auto-issue-loyalty-promos-cron');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'auto-generate-driver-settlements-cron') THEN
    PERFORM cron.unschedule('auto-generate-driver-settlements-cron');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'auto-generate-merchant-payouts-cron') THEN
    PERFORM cron.unschedule('auto-generate-merchant-payouts-cron');
  END IF;
END $$;

-- Schedule jobs
SELECT cron.schedule(
  'reconcile-payments-cron',
  '*/5 * * * *',
  $$SELECT public.invoke_edge_function('reconcile-payments')$$
);

SELECT cron.schedule(
  'auto-expiry-promos-cron',
  '*/5 * * * *',
  $$SELECT public.invoke_edge_function('auto-expiry-promos')$$
);

SELECT cron.schedule(
  'auto-issue-loyalty-promos-cron',
  '0 2 * * *',
  $$SELECT public.invoke_edge_function('auto-issue-loyalty-promos')$$
);

SELECT cron.schedule(
  'auto-generate-driver-settlements-cron',
  '30 3 * * *',
  $$SELECT public.invoke_edge_function('auto-generate-driver-settlements')$$
);

SELECT cron.schedule(
  'auto-generate-merchant-payouts-cron',
  '0 3 * * *',
  $$SELECT public.invoke_edge_function('auto-generate-merchant-payouts')$$
);
