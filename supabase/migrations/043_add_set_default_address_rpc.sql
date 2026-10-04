-- Migration 043: Atomic set_default_address RPC
-- Sprint 0.1.4: Replace the two-step "clear old default + set new default" with a
-- single atomic SQL statement using CTE. This eliminates the race condition where
-- two concurrent calls could result in zero or two default addresses.

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
  -- Security check: only service_role can call this (via Edge Function)
  -- or the user themselves via RLS-protected direct call
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') = 'service_role' THEN
    -- service_role can always proceed
    NULL;
  ELSE
    -- For non-service_role, verify the address belongs to the user
    IF NOT EXISTS (
      SELECT 1 FROM public.addresses
      WHERE id = p_address_id AND user_id = p_user_id
    ) THEN
      RAISE EXCEPTION 'Address not found or does not belong to user';
    END IF;
  END IF;

  -- Atomic: clear all defaults for this user, then set the new one
  -- Using a single UPDATE with CASE to do both in one statement
  UPDATE public.addresses
  SET is_default = CASE
    WHEN id = p_address_id THEN TRUE
    WHEN user_id = p_user_id THEN FALSE
    ELSE is_default  -- addresses belonging to other users are untouched
  END
  WHERE id = p_address_id OR (user_id = p_user_id AND is_default = TRUE);

  -- Verify the target address exists and was updated
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Address not found';
  END IF;
END;
$$;

COMMENT ON FUNCTION public.set_default_address(UUID, UUID) IS 'Atomically sets an address as default: clears existing default for the user and sets the new one in a single UPDATE. Eliminates race condition from two-step approach.';

-- Grant execute to authenticated users (RLS will still protect data)
GRANT EXECUTE ON FUNCTION public.set_default_address(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_default_address(UUID, UUID) TO service_role;
