-- Migration 046: Atomic upsert_address_with_default RPC
--
-- Replaces the two-step "clear existing default + insert/update" pattern in
-- addAddress / updateAddress (apps/mobile/services/address.service.ts) with
-- a single atomic transaction. Eliminates the race condition where two
-- concurrent calls could leave the user with zero or two default addresses,
-- and the non-transactional failure mode where a clear succeeds but the
-- insert/update fails (leaving the user with no default).
--
-- The existing set_default_address RPC (migration 043) handles the "set an
-- existing address as default" case and is unchanged. This new RPC handles
-- the "insert or update an address, optionally making it the default" case.
--
-- Parameters:
--   p_address_id  UUID  — NULL for insert, the address UUID for update.
--   p_user_id     UUID  — The caller's user ID (auth.uid()).
--   p_data        JSONB — Address form fields. For insert, must include
--                         label, address, lat, lng, is_default. For update,
--                         only the fields to change (Partial<AddressFormData>).
--
-- Returns: the upserted address row (full addresses row, including id).
--
-- Security:
--   - SECURITY DEFINER so the function can read/update addresses rows
--     without the caller needing direct UPDATE permission on the partial
--     unique index. RLS still applies to the caller's own rows.
--   - Verifies p_user_id matches auth.uid() to prevent cross-user address
--     manipulation via injected p_user_id.
--   - For update: verifies the target address belongs to the caller before
--     touching it.

CREATE OR REPLACE FUNCTION public.upsert_address_with_default(
  p_address_id UUID,
  p_user_id UUID,
  p_data JSONB
)
RETURNS public.addresses
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_returned public.addresses;
  v_is_default BOOLEAN;
  v_existing_owner UUID;
BEGIN
  -- Security: verify p_user_id matches the JWT's auth.uid().
  -- Prevents a caller from passing another user's UUID as p_user_id.
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'sub', '')::UUID IS DISTINCT FROM p_user_id THEN
    RAISE EXCEPTION 'p_user_id does not match authenticated user';
  END IF;

  -- Extract is_default from the payload (default FALSE if absent).
  v_is_default := COALESCE((p_data->>'is_default')::BOOLEAN, FALSE);

  IF p_address_id IS NULL THEN
    -- ===== INSERT path (addAddress) =====
    -- 1. If is_default, clear the user's existing default in the same transaction.
    IF v_is_default THEN
      UPDATE public.addresses
      SET is_default = FALSE
      WHERE user_id = p_user_id AND is_default = TRUE;
    END IF;

    -- 2. Insert the new address.
    INSERT INTO public.addresses (
      user_id, label, title_ar, title_en, address,
      building_number, floor_number, apartment_number, landmark,
      lat, lng, city, area, google_place_id, is_default
    )
    VALUES (
      p_user_id,
      p_data->>'label',
      NULLIF(p_data->>'title_ar', '') ,
      NULLIF(p_data->>'title_en', ''),
      p_data->>'address',
      NULLIF(p_data->>'building_number', ''),
      NULLIF(p_data->>'floor_number', ''),
      NULLIF(p_data->>'apartment_number', ''),
      NULLIF(p_data->>'landmark', ''),
      (p_data->>'lat')::DOUBLE PRECISION,
      (p_data->>'lng')::DOUBLE PRECISION,
      NULLIF(p_data->>'city', ''),
      NULLIF(p_data->>'area', ''),
      NULLIF(p_data->>'google_place_id', ''),
      v_is_default
    )
    RETURNING * INTO v_returned;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Failed to insert address';
    END IF;

    RETURN v_returned;
  ELSE
    -- ===== UPDATE path (updateAddress) =====
    -- 1. Verify the address belongs to the caller (defense in depth — RLS
    --    already enforces this, but an explicit check produces a clearer
    --    error than a silent 0-row update).
    SELECT user_id INTO v_existing_owner
    FROM public.addresses
    WHERE id = p_address_id;

    IF v_existing_owner IS NULL THEN
      RAISE EXCEPTION 'Address not found';
    END IF;

    IF v_existing_owner IS DISTINCT FROM p_user_id THEN
      RAISE EXCEPTION 'Address does not belong to user';
    END IF;

    -- 2. If setting is_default=true, clear the user's other defaults in the
    --    same transaction. Only clear when the flag is being set to TRUE
    --    (not when being explicitly set to FALSE or absent).
    IF v_is_default THEN
      UPDATE public.addresses
      SET is_default = FALSE
      WHERE user_id = p_user_id AND is_default = TRUE AND id <> p_address_id;
    END IF;

    -- 3. Update the address with only the fields present in p_data.
    --    Using COALESCE to skip fields not in the payload (Partial<AddressFormData>).
    UPDATE public.addresses
    SET
      label             = COALESCE(NULLIF(p_data->>'label', ''), label),
      title_ar          = CASE WHEN p_data ? 'title_ar' THEN NULLIF(p_data->>'title_ar', '') ELSE title_ar END,
      title_en          = CASE WHEN p_data ? 'title_en' THEN NULLIF(p_data->>'title_en', '') ELSE title_en END,
      address           = COALESCE(NULLIF(p_data->>'address', ''), address),
      building_number   = CASE WHEN p_data ? 'building_number' THEN NULLIF(p_data->>'building_number', '') ELSE building_number END,
      floor_number      = CASE WHEN p_data ? 'floor_number' THEN NULLIF(p_data->>'floor_number', '') ELSE floor_number END,
      apartment_number  = CASE WHEN p_data ? 'apartment_number' THEN NULLIF(p_data->>'apartment_number', '') ELSE apartment_number END,
      landmark          = CASE WHEN p_data ? 'landmark' THEN NULLIF(p_data->>'landmark', '') ELSE landmark END,
      lat               = CASE WHEN p_data ? 'lat' THEN (p_data->>'lat')::DOUBLE PRECISION ELSE lat END,
      lng               = CASE WHEN p_data ? 'lng' THEN (p_data->>'lng')::DOUBLE PRECISION ELSE lng END,
      city              = CASE WHEN p_data ? 'city' THEN NULLIF(p_data->>'city', '') ELSE city END,
      area              = CASE WHEN p_data ? 'area' THEN NULLIF(p_data->>'area', '') ELSE area END,
      google_place_id   = CASE WHEN p_data ? 'google_place_id' THEN NULLIF(p_data->>'google_place_id', '') ELSE google_place_id END,
      is_default        = CASE WHEN p_data ? 'is_default' THEN v_is_default ELSE is_default END,
      updated_at        = NOW()
    WHERE id = p_address_id AND user_id = p_user_id
    RETURNING * INTO v_returned;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Failed to update address';
    END IF;

    RETURN v_returned;
  END IF;
END;
$$;

COMMENT ON FUNCTION public.upsert_address_with_default(UUID, UUID, JSONB) IS
  'Atomically inserts or updates an address, managing the is_default flag in a single transaction. '
  'Eliminates the race condition and non-transactional failure mode of the previous two-step clear-then-set pattern. '
  'For insert: pass p_address_id=NULL. For update: pass the address UUID. '
  'p_data is a JSONB object of AddressFormData (insert) or Partial<AddressFormData> (update).';

-- Grant execute to authenticated users (the function verifies p_user_id === auth.uid())
GRANT EXECUTE ON FUNCTION public.upsert_address_with_default(UUID, UUID, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_address_with_default(UUID, UUID, JSONB) TO service_role;
