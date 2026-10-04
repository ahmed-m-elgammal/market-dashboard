-- Migration 049: Add orders.scheduled_time + profiles.is_active (Sprint 0 fixes D04 + D05)
--
-- D04: Add orders.scheduled_time column to persist scheduled-for-later orders.
--      Previously the client sent scheduled_time in the place-order payload,
--      but the Edge Function never read it, the place_order_with_items RPC
--      never persisted it, and the orders table had no column for it. Every
--      "scheduled" order was silently placed as ASAP.
--
--      This migration adds the column. The place_order_with_items RPC is
--      replaced in-place to read p_order->>'scheduled_time' and persist it.
--      The place-order Edge Function is updated separately (TypeScript) to
--      forward the field.
--
-- D05: Add profiles.is_active column so deleteAccount() can soft-delete.
--      Previously auth.service.ts:deleteAccount() called
--        update({ is_active: false })
--      but profiles had no is_active column — the update failed silently,
--      the user was signed out but the profile + auth.users row remained.
--      This migration adds the column (default TRUE) and updates the
--      profiles_update_own RLS policy (from migration 048) to allow only
--      the true→false transition (no self-reactivation).

-- =============================================================================
-- D04: orders.scheduled_time
-- =============================================================================

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS scheduled_time TIMESTAMPTZ
    CHECK (scheduled_time IS NULL OR scheduled_time > created_at);

COMMENT ON COLUMN public.orders.scheduled_time IS
  'Customer-requested delivery time (NULL = ASAP). Must be later than created_at.';

-- =============================================================================
-- D04: Replace place_order_with_items to persist scheduled_time
-- =============================================================================
-- The function signature (JSONB, JSONB) is unchanged — only the body adds one
-- column to the INSERT. We DROP and CREATE to keep the migration idempotent
-- (CREATE OR REPLACE would also work, but DROP+CREATE makes the diff explicit
-- and matches the pattern used by migration 045).

DROP FUNCTION IF EXISTS public.place_order_with_items(JSONB, JSONB);

CREATE OR REPLACE FUNCTION public.place_order_with_items(
  p_order JSONB,
  p_items JSONB
)
RETURNS TABLE(id UUID, order_number TEXT, created_at TIMESTAMPTZ)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_order_id UUID;
  v_order_number TEXT;
  v_created_at TIMESTAMPTZ;
  v_item JSONB;
  v_customer_id UUID;
  v_merchant_id UUID;
  v_idempotency_key TEXT;
  v_platform_fee NUMERIC;
  v_platform_fee_pct NUMERIC;
  v_merchant_commission_pct NUMERIC;
  v_max_items INTEGER;
  v_duplicate_threshold_seconds INTEGER;
  v_item_count INTEGER;
  v_promo_code_id UUID;
  v_promo_max_usage INTEGER;
  v_promo_max_usage_per_user INTEGER;
  v_user_usage_count INTEGER;
  v_new_usage INTEGER;
BEGIN
  -- =====================================================================
  -- SECURITY: Verify service role
  -- =====================================================================
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: place_order_with_items is service-role only.';
  END IF;

  -- =====================================================================
  -- INPUT VALIDATION
  -- =====================================================================
  v_customer_id := (p_order->>'customer_id')::UUID;
  v_merchant_id := (p_order->>'merchant_id')::UUID;
  v_idempotency_key := p_order->>'idempotency_key';

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_customer_id) THEN
    RAISE EXCEPTION 'Customer not found';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.merchants WHERE id = v_merchant_id AND is_active = TRUE) THEN
    RAISE EXCEPTION 'Merchant not found or inactive';
  END IF;

  v_item_count := jsonb_array_length(p_items);
  IF v_item_count = 0 THEN
    RAISE EXCEPTION 'Order must have at least one item';
  END IF;

  SELECT COALESCE(
    (SELECT value::INTEGER FROM public.platform_config WHERE key = 'max_items_per_order'),
    50
  ) INTO v_max_items;

  IF v_item_count > v_max_items THEN
    RAISE EXCEPTION 'Order exceeds maximum items limit of %', v_max_items;
  END IF;

  -- =====================================================================
  -- DUPLICATE ORDER CHECK
  -- =====================================================================
  SELECT COALESCE(
    (SELECT value::INTEGER FROM public.platform_config WHERE key = 'order_duplicate_threshold_seconds'),
    10
  ) INTO v_duplicate_threshold_seconds;

  IF v_idempotency_key IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM public.orders
      WHERE idempotency_key = v_idempotency_key
    ) THEN
      RAISE EXCEPTION 'Duplicate order (idempotency key)';
    END IF;
  ELSE
    IF EXISTS (
      SELECT 1 FROM public.orders
      WHERE customer_id = v_customer_id
        AND merchant_id = v_merchant_id
        AND created_at > NOW() - (v_duplicate_threshold_seconds || ' seconds')::INTERVAL
        AND status != 'cancelled'
    ) THEN
      RAISE EXCEPTION 'Duplicate order (recent similar order)';
    END IF;
  END IF;

  -- =====================================================================
  -- FETCH PLATFORM CONFIG FOR FEES
  -- =====================================================================
  SELECT COALESCE(
    (SELECT value::NUMERIC FROM public.platform_config WHERE key = 'platform_fee'),
    3.00
  ) INTO v_platform_fee;

  SELECT COALESCE(
    (SELECT value::NUMERIC FROM public.platform_config WHERE key = 'platform_fee_percentage'),
    0
  ) INTO v_platform_fee_pct;

  SELECT COALESCE(
    (SELECT value::NUMERIC FROM public.platform_config WHERE key = 'default_commission_pct'),
    15.00
  ) INTO v_merchant_commission_pct;

  -- =====================================================================
  -- INSERT ORDER  (D04: now persists scheduled_time)
  -- =====================================================================
  INSERT INTO public.orders (
    customer_id, merchant_id, status, delivery_address,
    subtotal, delivery_fee, platform_fee, discount_amount, total,
    payment_method, payment_status, promo_code_id, promo_code,
    distance_km, estimated_delivery_minutes, idempotency_key,
    merchant_commission_pct, paymob_order_id, notes,
    customer_phone, scheduled_time
  ) VALUES (
    v_customer_id,
    v_merchant_id,
    COALESCE(p_order->>'status', 'pending'),
    p_order->'delivery_address',
    COALESCE((p_order->>'subtotal')::NUMERIC, 0),
    COALESCE((p_order->>'delivery_fee')::NUMERIC, 0),
    CASE
      WHEN v_platform_fee_pct > 0 THEN
        ROUND(COALESCE((p_order->>'subtotal')::NUMERIC, 0) * v_platform_fee_pct / 100, 2)
      ELSE v_platform_fee
    END,
    COALESCE((p_order->>'discount_amount')::NUMERIC, 0),
    COALESCE((p_order->>'total')::NUMERIC, 0),
    p_order->>'payment_method',
    COALESCE(p_order->>'payment_status', 'pending'),
    CASE WHEN p_order->>'promo_code_id' IS NOT NULL THEN (p_order->>'promo_code_id')::UUID ELSE NULL END,
    p_order->>'promo_code',
    COALESCE((p_order->>'distance_km')::NUMERIC, 0),
    COALESCE((p_order->>'estimated_delivery_minutes')::INTEGER, 30),
    v_idempotency_key,
    COALESCE(
      (SELECT commission_pct FROM public.merchants WHERE id = v_merchant_id),
      v_merchant_commission_pct
    ),
    p_order->>'paymob_order_id',
    p_order->>'notes',
    p_order->>'customer_phone',
    CASE WHEN p_order->>'scheduled_time' IS NOT NULL
         THEN (p_order->>'scheduled_time')::TIMESTAMPTZ
         ELSE NULL END
  )
  RETURNING id, order_number, created_at
  INTO v_order_id, v_order_number, v_created_at;

  -- =====================================================================
  -- INSERT ORDER ITEMS (atomically)
  -- =====================================================================
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    INSERT INTO public.order_items (
      order_id, item_id, item_name_ar, item_name_en,
      item_price, quantity, total_price,
      selected_options, special_instructions
    ) VALUES (
      v_order_id,
      (v_item->>'item_id')::UUID,
      v_item->>'item_name_ar',
      v_item->>'item_name_en',
      COALESCE((v_item->>'item_price')::NUMERIC, 0),
      COALESCE((v_item->>'quantity')::INTEGER, 1),
      COALESCE((v_item->>'total_price')::NUMERIC, 0),
      COALESCE(v_item->'selected_options', '[]'::JSONB),
      v_item->>'special_instructions'
    );
  END LOOP;

  -- =====================================================================
  -- TRACK PROMO CODE USAGE — ATOMICALLY ENFORCED (preserved from migration 045)
  -- =====================================================================
  IF p_order->>'promo_code_id' IS NOT NULL THEN
    v_promo_code_id := (p_order->>'promo_code_id')::UUID;

    -- Lock the promo row and read its limits.
    SELECT max_usage, max_usage_per_user
      INTO v_promo_max_usage, v_promo_max_usage_per_user
      FROM public.promo_codes
      WHERE id = v_promo_code_id
      FOR UPDATE;

    -- Atomic conditional increment — fails if already at global limit.
    UPDATE public.promo_codes
      SET current_usage = current_usage + 1
      WHERE id = v_promo_code_id
        AND current_usage < v_promo_max_usage
      RETURNING current_usage INTO v_new_usage;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Promo code % has reached its global usage limit', v_promo_code_id
        USING ERRCODE = 'check_violation';
    END IF;

    -- Count this user's existing usage (after the increment above, this
    -- transaction hasn't yet inserted the new row).
    SELECT COUNT(*) INTO v_user_usage_count
      FROM public.promo_code_usage
      WHERE promo_code_id = v_promo_code_id AND user_id = v_customer_id;

    IF v_user_usage_count >= v_promo_max_usage_per_user THEN
      RAISE EXCEPTION 'Promo code % has reached its per-user usage limit for user %',
        v_promo_code_id, v_customer_id
        USING ERRCODE = 'check_violation';
    END IF;

    -- Record per-user usage.
    INSERT INTO public.promo_code_usage (promo_code_id, user_id, order_id, discount_amount)
    VALUES (
      v_promo_code_id,
      v_customer_id,
      v_order_id,
      COALESCE((p_order->>'discount_amount')::NUMERIC, 0)
    );
  END IF;

  -- =====================================================================
  -- RETURN THE CREATED ORDER DATA
  -- =====================================================================
  RETURN QUERY SELECT v_order_id AS id, v_order_number AS order_number, v_created_at AS created_at;
END;
$$;

COMMENT ON FUNCTION public.place_order_with_items(JSONB, JSONB) IS
  'Hardened atomic order creation. SECURITY DEFINER, service-role only. '
  'Migration 045 added atomic per-user and global promo usage enforcement (closes TOCTOU window from migration 036). '
  'Migration 049 added persistence of scheduled_time (D04).';

REVOKE EXECUTE ON FUNCTION public.place_order_with_items(JSONB, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.place_order_with_items(JSONB, JSONB) TO service_role;

-- =============================================================================
-- D05: profiles.is_active column
-- =============================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE;

COMMENT ON COLUMN public.profiles.is_active IS
  'Soft-delete flag. FALSE = user invoked deleteAccount (profile + auth.users row retained for audit). '
  'Set to FALSE by auth.service.ts:deleteAccount().';

-- =============================================================================
-- D05: Update profiles_update_own RLS policy to allow only true→false transition
-- =============================================================================
-- Migration 048 pinned wallet_balance and role. We now also pin is_active to
-- disallow self-reactivation: a user may set is_active=FALSE (deleteAccount),
-- but may NOT set is_active=TRUE on any row (including their own). Reactivation
-- is admin-only via service role.

DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;

CREATE POLICY "profiles_update_own"
  ON public.profiles
  FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (
    auth.uid() = id
    -- wallet_balance must be unchanged (blocks direct wallet top-up fraud)
    AND wallet_balance IS NOT DISTINCT FROM (
      SELECT wallet_balance FROM public.profiles WHERE id = auth.uid()
    )
    -- role must be unchanged (defense-in-depth; also enforced by trigger 024)
    AND role IS NOT DISTINCT FROM (
      SELECT role FROM public.profiles WHERE id = auth.uid()
    )
    -- is_active may only transition true→false (deleteAccount).
    -- Setting is_active=TRUE is forbidden for users (admin-only via service role).
    AND is_active IS NOT DISTINCT FROM FALSE
  );

COMMENT ON POLICY "profiles_update_own" ON public.profiles IS
  'S01/S14/D05 fix: Users can update own profile EXCEPT wallet_balance, role, and is_active reactivation. '
  'wallet_balance: must go through adjust_wallet_balance RPC. '
  'role: admin-only. '
  'is_active: user may set FALSE (deleteAccount), may NOT set TRUE (no self-reactivation).';
