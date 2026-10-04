-- Migration 052: Sprint 2 defense-in-depth (S09/S10/S15/S16/S17/S18/S27)
--
-- This migration bundles 7 hardening fixes from the security audit:
--   S09: set_default_address — add auth.uid() = p_user_id check
--   S10: get_stale_online_drivers + auto_offline_stale_drivers — add in-body
--        service-role check (defense-in-depth if REVOKE FROM PUBLIC is ever
--        accidentally widened)
--   S15: prevent_driver_role_escalation trigger — also block when
--        request.jwt.claims is unset (was an escape hatch for DB-level ops)
--   S16: set_review_fields_from_order trigger — add SET search_path = '' and
--        schema-qualify the orders table reference
--   S17: admin_deactivate_driver RPC — declare missing v_driver_id and
--        v_deactivated_at variables (currently raises at runtime)
--   S18: cancellation_rules_read policy — DROP (no mobile/admin caller reads
--        this table directly; only the cancel_order RPC reads it server-side)
--   S27: get_admin_kpi — convert from STABLE to SECURITY DEFINER + in-body
--        service-role check (consistency with other admin RPCs)

-- =============================================================================
-- S09: set_default_address — add auth.uid() = p_user_id check
-- =============================================================================
-- Previously the function only verified that the address belongs to p_user_id,
-- but never that p_user_id = auth.uid(). An attacker could pass another user's
-- UUID as p_user_id and the function would set that user's default address.
-- Mirrors the auth check pattern from migration 046's upsert_address_with_default.

CREATE OR REPLACE FUNCTION public.set_default_address(
  p_address_id UUID,
  p_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  -- Security check: service role bypasses; otherwise p_user_id must match auth.uid()
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role'
     AND COALESCE(current_setting('request.jwt.claims', true)::json->>'sub', '')::UUID IS DISTINCT FROM p_user_id THEN
    RAISE EXCEPTION 'p_user_id does not match authenticated user';
  END IF;

  -- Verify the address belongs to the user
  IF NOT EXISTS (
    SELECT 1 FROM public.addresses
    WHERE id = p_address_id AND user_id = p_user_id
  ) THEN
    RAISE EXCEPTION 'Address not found or does not belong to user';
  END IF;

  -- Atomic: clear all defaults for this user, then set the new one
  UPDATE public.addresses
  SET is_default = CASE
    WHEN id = p_address_id THEN TRUE
    WHEN user_id = p_user_id THEN FALSE
    ELSE is_default
  END
  WHERE id = p_address_id OR (user_id = p_user_id AND is_default = TRUE);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Address not found';
  END IF;
END;
$$;

COMMENT ON FUNCTION public.set_default_address(UUID, UUID) IS 'Atomically sets an address as default. Sprint 2 fix (S09): added auth.uid() = p_user_id check.';

-- =============================================================================
-- S10: get_stale_online_drivers + auto_offline_stale_drivers — in-body service-role check
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_stale_online_drivers(
  p_stale_threshold_seconds INTEGER DEFAULT 120
)
RETURNS TABLE (
  driver_id UUID,
  driver_name TEXT,
  last_location_at TIMESTAMPTZ,
  seconds_since_update INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  -- Sprint 2 fix (S10): defense-in-depth — fail closed if a future migration
  -- accidentally widens GRANT to authenticated.
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: get_stale_online_drivers is service-role only.';
  END IF;

  RETURN QUERY
  SELECT
    d.id AS driver_id,
    p.full_name AS driver_name,
    d.last_location_at,
    EXTRACT(EPOCH FROM NOW() - d.last_location_at)::INTEGER AS seconds_since_update
  FROM public.drivers d
  JOIN public.profiles p ON p.id = d.id
  WHERE d.is_online = TRUE
    AND d.is_verified = TRUE
    AND d.is_active = TRUE
    AND (
      d.last_location_at IS NULL
      OR d.last_location_at < NOW() - (p_stale_threshold_seconds || ' seconds')::INTERVAL
    )
  ORDER BY d.last_location_at ASC NULLS FIRST;
END;
$$;

COMMENT ON FUNCTION public.get_stale_online_drivers(INTEGER) IS 'Sprint 2 fix (S10): added in-body service-role check. Finds drivers with stale location data.';

CREATE OR REPLACE FUNCTION public.auto_offline_stale_drivers()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_count INTEGER;
  v_threshold_seconds INTEGER;
BEGIN
  -- Sprint 2 fix (S10): defense-in-depth — fail closed if GRANT is widened.
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: auto_offline_stale_drivers is service-role only.';
  END IF;

  SELECT COALESCE(
    (SELECT value::INTEGER FROM public.platform_config WHERE key = 'driver_max_location_update_interval_seconds'),
    120
  ) INTO v_threshold_seconds;

  UPDATE public.drivers
  SET is_online = FALSE
  WHERE is_online = TRUE
    AND is_verified = TRUE
    AND is_active = TRUE
    AND (
      last_location_at IS NULL
      OR last_location_at < NOW() - (v_threshold_seconds * 5 || ' seconds')::INTERVAL
    );

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION public.auto_offline_stale_drivers() IS 'Sprint 2 fix (S10): added in-body service-role check. Sets is_online=FALSE for stale drivers.';

-- =============================================================================
-- S15: prevent_driver_role_escalation — also block when jwt.claims is unset
-- =============================================================================
-- Previous version only fired when request.jwt.claims was set, leaving an
-- escape hatch for DB-level operations (cron, psql, migrations). Tightened
-- to also block when claims are unset, unless a trusted migration flag
-- (app.allow_driver_role_change) is set.

CREATE OR REPLACE FUNCTION public.prevent_driver_role_escalation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.role = 'driver' THEN
    IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role'
       AND current_setting('app.allow_driver_role_change', true) IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Role escalation blocked: users cannot set role to driver. Use admin-create-driver Edge Function instead.'
        USING HINT = 'Driver accounts must be created by admin via the admin-create-driver API. '
                     'Trusted migrations may set app.allow_driver_role_change=true to bypass.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.prevent_driver_role_escalation() IS 'Sprint 2 fix (S15): now also blocks when request.jwt.claims is unset (was an escape hatch for DB-level ops). Trusted migrations can set app.allow_driver_role_change=true to bypass.';

-- =============================================================================
-- S16: set_review_fields_from_order — add SET search_path = '' + schema-qualify
-- =============================================================================

CREATE OR REPLACE FUNCTION public.set_review_fields_from_order()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_order RECORD;
BEGIN
  SELECT customer_id, merchant_id, driver_id
  INTO v_order
  FROM public.orders
  WHERE id = NEW.order_id;

  IF v_order.customer_id IS NOT NULL THEN
    NEW.customer_id := v_order.customer_id;
  END IF;

  IF v_order.merchant_id IS NOT NULL THEN
    NEW.merchant_id := v_order.merchant_id;
  END IF;

  IF v_order.driver_id IS NOT NULL THEN
    NEW.driver_id := v_order.driver_id;
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.set_review_fields_from_order() IS 'Sprint 2 fix (S16): added SET search_path = "" and schema-qualified orders table reference.';

-- =============================================================================
-- S17: admin_deactivate_driver — declare missing variables
-- =============================================================================

CREATE OR REPLACE FUNCTION public.admin_deactivate_driver(
  p_admin_id UUID,
  p_driver_id UUID,
  p_reason TEXT
)
RETURNS TABLE (
  driver_id UUID,
  is_active BOOLEAN,
  deactivated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  -- Sprint 2 fix (S17): added missing declarations for the RETURNING INTO
  -- targets below. Previous version raised "v_driver_id is not a known
  -- variable" at function-creation time.
  v_was_active BOOLEAN;
  v_driver_id UUID;
  v_deactivated_at TIMESTAMPTZ;
BEGIN
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: admin_deactivate_driver can only be called by service role.';
  END IF;

  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'Deactivation reason is required.';
  END IF;

  SELECT is_active INTO v_was_active FROM public.drivers WHERE id = p_driver_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Driver not found.';
  END IF;
  IF NOT v_was_active THEN
    RAISE EXCEPTION 'Driver is already deactivated.';
  END IF;

  UPDATE public.drivers
  SET is_active = FALSE,
      is_online = FALSE,
      deactivated_at = NOW()
  WHERE id = p_driver_id
  RETURNING id, is_active, deactivated_at
  INTO v_driver_id, v_was_active, v_deactivated_at;

  INSERT INTO public.driver_status_history (
    driver_id, previous_status, new_status, changed_by, reason
  ) VALUES (
    p_driver_id, 'active', 'deactivated', p_admin_id, p_reason
  );

  INSERT INTO public.notifications (
    user_id, type, title_ar, title_en, body_ar, body_en, data
  ) VALUES (
    p_driver_id, 'driver_deactivated',
    'تم إلغاء تفعيل حسابك', 'Account Deactivated',
    'تم إلغاء تفعيل حسابك. السبب: ' || p_reason,
    'Your account has been deactivated. Reason: ' || p_reason,
    jsonb_build_object('driver_id', p_driver_id, 'reason', p_reason)
  );

  INSERT INTO public.data_access_log (
    admin_id, action, resource_type, resource_id, field_name, reason
  ) VALUES (
    p_admin_id, 'modify', 'driver', p_driver_id,
    'is_active', 'Deactivated driver: ' || p_reason
  );

  RETURN QUERY SELECT p_driver_id, FALSE, NOW()::TIMESTAMPTZ;
END;
$$;

COMMENT ON FUNCTION public.admin_deactivate_driver(UUID, UUID, TEXT) IS 'Sprint 2 fix (S17): declared missing v_driver_id and v_deactivated_at variables. Atomic driver deactivation.';

-- =============================================================================
-- S18: cancellation_rules_read — DROP policy
-- =============================================================================
-- No mobile or admin code reads cancellation_rules directly — only the
-- cancel_order RPC reads it server-side (as service role). The SELECT
-- policy exposed all 21 rules (cancellation fees, driver compensation
-- amounts, auto-cancel timing) to any authenticated user, useful for
-- adversarial order placement.

DROP POLICY IF EXISTS "cancellation_rules_read" ON public.cancellation_rules;

COMMENT ON TABLE public.cancellation_rules IS 'Sprint 2 fix (S18): SELECT policy dropped. Only the cancel_order RPC (service role) reads this table; mobile/admin code never queries it directly.';

-- =============================================================================
-- S27: get_admin_kpi — convert to SECURITY DEFINER + in-body service-role check
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_admin_kpi(p_key TEXT)
RETURNS TABLE (key TEXT, value JSONB, computed_at TIMESTAMPTZ, age_seconds INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  -- Sprint 2 fix (S27): converted from STABLE to SECURITY DEFINER with an
  -- in-body service-role check, matching the codebase's hardening standard
  -- (migration 044). RLS on admin_kpi_cache already blocks non-service-role
  -- SELECTs, but this is the documented defense-in-depth pattern.
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: get_admin_kpi is service-role only.';
  END IF;

  RETURN QUERY
  SELECT
    akc.key,
    akc.value,
    akc.computed_at,
    EXTRACT(EPOCH FROM NOW() - akc.computed_at)::INTEGER AS age_seconds
  FROM public.admin_kpi_cache akc
  WHERE akc.key = p_key;
END;
$$;

COMMENT ON FUNCTION public.get_admin_kpi(TEXT) IS 'Sprint 2 fix (S27): converted to SECURITY DEFINER with in-body service-role check. Returns cached admin KPI with age in seconds.';

REVOKE EXECUTE ON FUNCTION public.get_admin_kpi(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_admin_kpi(TEXT) TO service_role;
