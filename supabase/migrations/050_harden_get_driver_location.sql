-- Migration 050: Harden get_driver_location (Sprint 1 fix S04)
--
-- Audit issue S04: get_driver_location is SECURITY DEFINER but takes
-- p_customer_id as a parameter and never compares it to auth.uid(). Combined
-- with the default Postgres EXECUTE grant to PUBLIC, any authenticated user
-- could pass another customer's UUID as p_customer_id and retrieve that
-- customer's driver location in real time.
--
-- Fix: add an in-body auth.uid() = p_customer_id check, REVOKE EXECUTE FROM
-- PUBLIC, and GRANT only to authenticated. Mirrors the hardening pattern from
-- migrations 030/033/044/045/046.

CREATE OR REPLACE FUNCTION public.get_driver_location(
  p_order_id UUID,
  p_customer_id UUID
)
RETURNS TABLE (
  current_lat NUMERIC,
  current_lng NUMERIC,
  last_location_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_driver_id UUID;
BEGIN
  -- =====================================================================
  -- SECURITY: caller must be the customer whose UUID is passed.
  -- Service role bypasses this check (uses RLS bypass instead).
  -- =====================================================================
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role'
     AND COALESCE(current_setting('request.jwt.claims', true)::json->>'sub', '')::UUID IS DISTINCT FROM p_customer_id THEN
    RAISE EXCEPTION 'Unauthorized: p_customer_id must match auth.uid()';
  END IF;

  -- Step 1: Verify the order belongs to this customer and has a driver
  SELECT driver_id INTO v_driver_id
  FROM public.orders
  WHERE id = p_order_id
    AND customer_id = p_customer_id
    AND driver_id IS NOT NULL;

  -- If no matching order or no driver assigned, return empty
  IF v_driver_id IS NULL THEN
    RETURN;
  END IF;

  -- Step 2: Return only the location fields from the driver
  RETURN QUERY
  SELECT
    d.current_lat,
    d.current_lng,
    d.last_location_at
  FROM public.drivers d
  WHERE d.id = v_driver_id
    AND d.is_online = TRUE;
END;
$$;

COMMENT ON FUNCTION public.get_driver_location(UUID, UUID) IS
  'P1E-13: SECURITY DEFINER function to securely retrieve driver location for a customer order. '
  'Verifies customer owns the order and driver is assigned. Bypasses RLS but enforces own access control. '
  'Migration 050 (S04): added auth.uid() = p_customer_id check and REVOKE FROM PUBLIC.';

-- =============================================================================
-- GRANT PERMISSIONS — service role + authenticated only (was implicit PUBLIC)
-- =============================================================================

REVOKE EXECUTE ON FUNCTION public.get_driver_location(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_driver_location(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_driver_location(UUID, UUID) TO service_role;
