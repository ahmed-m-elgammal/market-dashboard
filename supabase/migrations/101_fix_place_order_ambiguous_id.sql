-- Migration 101: Fix place_order_with_items ambiguous "id" (42702)
--
-- BUG (caught live 2026-09-30 by the Phase-2 demo seed): the function declares
-- RETURNS TABLE(id UUID, order_number TEXT, created_at TIMESTAMPTZ), so plpgsql
-- creates OUT variables named id/order_number/created_at that collide with
-- unqualified column references (e.g. WHERE id = v_merchant_id) → every call
-- fails with: column reference "id" is ambiguous (42702). Live had 0 orders,
-- so this never surfaced.
--
-- FIX: #variable_conflict use_column — ambiguous refs resolve to the column
-- (the intent everywhere; OUT params are only ever written via the final
-- RETURN QUERY aliases). Output keys id/order_number/created_at UNCHANGED,
-- so the place-order EF contract is untouched. Body is otherwise byte-
-- identical to 080. Net data change: none.

CREATE OR REPLACE FUNCTION public.place_order_with_items(
  p_order JSONB,
  p_items JSONB
)
RETURNS TABLE(id UUID, order_number TEXT, created_at TIMESTAMPTZ)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
#variable_conflict use_column
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
  v_customer_ip INET;
  v_fraud_count INTEGER;
  -- S1: New variables for funded_by payout computation
  v_subtotal NUMERIC(10,2);
  v_discount_amount NUMERIC(10,2);
  v_commission_pct_resolved NUMERIC(5,2);
  v_promo_funded_by TEXT;
  v_promo_merchant_share_pct NUMERIC(5,2);
  v_merchant_discount_floor NUMERIC(10,2);
  v_merchant_discount_share NUMERIC(10,2);
  v_merchant_payout NUMERIC(10,2);
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

  -- S1: Fetch configurable merchant discount floor from platform_config.
  -- When funded_by='shared' and discount_amount <= this floor, the platform
  -- absorbs 100% (merchant_share becomes 0). Default 0 = disabled.
  SELECT COALESCE(
    (SELECT value::NUMERIC FROM public.platform_config WHERE key = 'merchant_discount_floor'),
    0
  ) INTO v_merchant_discount_floor;

  -- =====================================================================
  -- S1: COMPUTE MERCHANT PAYOUT (funded_by logic)
  -- =====================================================================
  v_subtotal := COALESCE((p_order->>'subtotal')::NUMERIC, 0);
  v_discount_amount := COALESCE((p_order->>'discount_amount')::NUMERIC, 0);

  -- Resolve commission: merchant-specific if set, else platform default
  v_commission_pct_resolved := COALESCE(
    (SELECT commission_pct FROM public.merchants WHERE id = v_merchant_id),
    v_merchant_commission_pct
  );

  -- Default: no promo funding info
  v_promo_funded_by := NULL;
  v_promo_merchant_share_pct := NULL;
  v_merchant_discount_share := 0;

  -- If a promo is applied, lock the row and read funding model + limits
  -- in a single query. The lock is held until transaction commit, which
  -- also covers the atomic usage enforcement below (no second SELECT needed).
  IF p_order->>'promo_code_id' IS NOT NULL THEN
    v_promo_code_id := (p_order->>'promo_code_id')::UUID;

    SELECT funded_by, merchant_share_pct, max_usage, max_usage_per_user
      INTO v_promo_funded_by, v_promo_merchant_share_pct, v_promo_max_usage, v_promo_max_usage_per_user
      FROM public.promo_codes
      WHERE id = v_promo_code_id
      FOR UPDATE;

    -- Compute merchant's share of the discount based on funding model
    IF v_discount_amount > 0 THEN
      v_merchant_discount_share := CASE
        -- Platform absorbs 100%
        WHEN v_promo_funded_by = 'platform' THEN 0
        -- Merchant absorbs 100%
        WHEN v_promo_funded_by = 'merchant' THEN v_discount_amount
        -- Shared: split by merchant_share_pct, but apply floor
        WHEN v_promo_funded_by = 'shared' THEN
          CASE
            -- Floor check: if discount <= floor, platform absorbs all
            WHEN v_discount_amount <= v_merchant_discount_floor THEN 0
            ELSE ROUND(
              v_discount_amount * COALESCE(v_promo_merchant_share_pct, 50) / 100,
              2
            )
          END
        ELSE 0
      END;
    END IF;
  END IF;

  -- merchant_payout = (subtotal - merchant's discount share) × (1 - commission%)
  -- This replaces the old GENERATED formula which was simply:
  --   subtotal - (subtotal * commission_pct / 100)
  -- The old formula completely ignored discounts.
  v_merchant_payout := ROUND(
    (v_subtotal - v_merchant_discount_share) *
    (1 - v_commission_pct_resolved / 100),
    2
  );

  -- Safety: never allow negative payout
  IF v_merchant_payout < 0 THEN
    v_merchant_payout := 0;
  END IF;

  -- =====================================================================
  -- INSERT ORDER
  -- =====================================================================
  INSERT INTO public.orders (
    customer_id, merchant_id, status, delivery_address,
    subtotal, delivery_fee, platform_fee, discount_amount, total,
    payment_method, payment_status, promo_code_id, promo_code,
    distance_km, estimated_delivery_minutes, idempotency_key,
    merchant_commission_pct, paymob_order_id, notes,
    customer_phone, scheduled_time,
    -- S1: New columns
    promo_funded_by, promo_merchant_share_pct, merchant_payout
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
    v_commission_pct_resolved,
    p_order->>'paymob_order_id',
    p_order->>'notes',
    p_order->>'customer_phone',
    CASE WHEN p_order->>'scheduled_time' IS NOT NULL THEN (p_order->>'scheduled_time')::TIMESTAMPTZ ELSE NULL END,
    -- S1: Snapshot promo funding model + computed payout
    v_promo_funded_by,
    v_promo_merchant_share_pct,
    v_merchant_payout
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
  -- TRACK PROMO CODE USAGE — ATOMICALLY ENFORCED
  -- =====================================================================
  -- Both the global max_usage and per-user max_usage_per_user limits are
  -- enforced at the SQL level here, not just in the Edge Function. The
  -- Edge Function's TS check is advisory (early rejection for UX); this
  -- block is authoritative (eliminates the TOCTOU window).
  -- NOTE: The promo row was already locked by the FOR UPDATE in the payout
  -- block above, so no additional SELECT ... FOR UPDATE is needed here.
  IF p_order->>'promo_code_id' IS NOT NULL THEN
    -- Parse customer_ip for fraud detection (optional, from migration 075)
    IF p_order->>'customer_ip' IS NOT NULL THEN
      v_customer_ip := (p_order->>'customer_ip')::INET;
    ELSE
      v_customer_ip := NULL;
    END IF;

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

    -- Record per-user usage (with ip_address for fraud detection, from 075).
    INSERT INTO public.promo_code_usage (promo_code_id, user_id, order_id, discount_amount, ip_address)
    VALUES (
      v_promo_code_id,
      v_customer_id,
      v_order_id,
      COALESCE((p_order->>'discount_amount')::NUMERIC, 0),
      v_customer_ip
    );

    -- Fire-and-forget fraud check. The result is not checked —
    -- fraud detection is async and inserts an alert_incident if needed.
    -- Wrapped in a BEGIN/EXCEPTION so a fraud-check failure never breaks
    -- the order placement.
    IF v_customer_ip IS NOT NULL THEN
      BEGIN
        SELECT public.check_promo_fraud(v_promo_code_id, v_customer_ip) INTO v_fraud_count;
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Promo fraud check failed for promo % IP %: %', v_promo_code_id, v_customer_ip, SQLERRM;
      END;
    END IF;
  END IF;

  -- =====================================================================
  -- RETURN THE CREATED ORDER DATA
  -- =====================================================================
  RETURN QUERY SELECT v_order_id AS id, v_order_number AS order_number, v_created_at AS created_at;
END;
$$;

COMMENT ON FUNCTION public.place_order_with_items(JSONB, JSONB) IS
  'Hardened atomic order creation. SECURITY DEFINER, service-role only. '
  'Migration 045: atomic per-user and global promo usage enforcement. '
  'Migration 049: scheduled_time persistence. '
  'Migration 075: customer_ip tracking + check_promo_fraud(). '
  'Migration 080: funded_by payout computation — merchant_payout now accounts '
  'for promo discount funding model (platform/merchant/shared) with configurable '
  'merchant_discount_floor from platform_config.';

REVOKE EXECUTE ON FUNCTION public.place_order_with_items(JSONB, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.place_order_with_items(JSONB, JSONB) TO service_role;
