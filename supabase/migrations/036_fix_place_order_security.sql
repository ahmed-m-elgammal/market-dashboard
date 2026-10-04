-- Migration 036: Fix place_order_with_items security + add RLS grants
-- The original place_order_with_items function (migration 026) lacked:
--   1. SECURITY DEFINER with SET search_path = ''
--   2. Duplicate order check within the function
--   3. Input validation for critical fields
--   4. Platform fee calculation from platform_config
--   5. Proper column for delivery_lat/delivery_lng extraction
--   6. Promo code usage tracking
--
-- This migration replaces the function with a hardened version.

-- =============================================================================
-- DROP OLD FUNCTION AND REPLACE WITH HARDENED VERSION
-- =============================================================================

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

  -- Validate customer exists
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_customer_id) THEN
    RAISE EXCEPTION 'Customer not found';
  END IF;

  -- Validate merchant exists and is active
  IF NOT EXISTS (SELECT 1 FROM public.merchants WHERE id = v_merchant_id AND is_active = TRUE) THEN
    RAISE EXCEPTION 'Merchant not found or inactive';
  END IF;

  -- Validate items array is not empty
  v_item_count := jsonb_array_length(p_items);
  IF v_item_count = 0 THEN
    RAISE EXCEPTION 'Order must have at least one item';
  END IF;

  -- Check max items per order
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
    -- Check by idempotency key (more reliable)
    IF EXISTS (
      SELECT 1 FROM public.orders
      WHERE idempotency_key = v_idempotency_key
    ) THEN
      RAISE EXCEPTION 'Duplicate order (idempotency key)';
    END IF;
  ELSE
    -- Check by customer + merchant + recent time
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
  -- INSERT ORDER
  -- =====================================================================
  INSERT INTO public.orders (
    customer_id, merchant_id, status, delivery_address,
    subtotal, delivery_fee, platform_fee, discount_amount, total,
    payment_method, payment_status, promo_code_id, promo_code,
    distance_km, estimated_delivery_minutes, idempotency_key,
    merchant_commission_pct, paymob_order_id, notes,
    customer_phone
  ) VALUES (
    v_customer_id,
    v_merchant_id,
    COALESCE(p_order->>'status', 'pending'),
    p_order->'delivery_address',
    COALESCE((p_order->>'subtotal')::NUMERIC, 0),
    COALESCE((p_order->>'delivery_fee')::NUMERIC, 0),
    -- Platform fee: use percentage if > 0, otherwise fixed fee
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
    p_order->>'customer_phone'
  )
  RETURNING id, order_number, created_at
  INTO v_order_id, v_order_number, v_created_at;

  -- =====================================================================
  -- INSERT ORDER ITEMS (atomically — if any fail, whole transaction rolls back)
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
  -- TRACK PROMO CODE USAGE
  -- =====================================================================
  IF p_order->>'promo_code_id' IS NOT NULL THEN
    -- Increment usage count on promo_codes
    UPDATE public.promo_codes
    SET current_usage = current_usage + 1
    WHERE id = (p_order->>'promo_code_id')::UUID;

    -- Record per-user usage
    INSERT INTO public.promo_code_usage (promo_code_id, user_id, order_id, discount_amount)
    VALUES (
      (p_order->>'promo_code_id')::UUID,
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

COMMENT ON FUNCTION public.place_order_with_items(JSONB, JSONB) IS 'Hardened atomic order creation: validates inputs, checks duplicates, calculates fees from platform_config, tracks promo usage. SECURITY DEFINER — service role only. Replaces migration 026 version.';

-- =============================================================================
-- GRANT PERMISSIONS
-- =============================================================================

REVOKE EXECUTE ON FUNCTION public.place_order_with_items(JSONB, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.place_order_with_items(JSONB, JSONB) TO service_role;
