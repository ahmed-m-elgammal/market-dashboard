-- Migration: 026_place_order_with_items_rpc.sql
-- Creates a Postgres function that atomically inserts an order + its items
-- in a single DB transaction. This prevents orphaned orders if the items
-- insert fails (previously, the Edge Function did two separate inserts).

CREATE OR REPLACE FUNCTION place_order_with_items(
  p_order JSONB,
  p_items JSONB
)
RETURNS TABLE(id UUID, order_number TEXT, created_at TIMESTAMPTZ)
LANGUAGE plpgsql
AS $$
DECLARE
  v_order_id UUID;
  v_order_number TEXT;
  v_created_at TIMESTAMPTZ;
  v_item JSONB;
BEGIN
  -- Insert the order
  INSERT INTO orders (
    customer_id, merchant_id, status, delivery_address,
    subtotal, delivery_fee, platform_fee, discount_amount, total,
    payment_method, payment_status, promo_code_id, promo_code,
    distance_km, estimated_delivery_minutes, idempotency_key,
    merchant_commission_pct, paymob_order_id, notes
  ) VALUES (
    (p_order->>'customer_id')::UUID,
    (p_order->>'merchant_id')::UUID,
    COALESCE(p_order->>'status', 'pending'),
    p_order->'delivery_address',
    COALESCE((p_order->>'subtotal')::NUMERIC, 0),
    COALESCE((p_order->>'delivery_fee')::NUMERIC, 0),
    COALESCE((p_order->>'platform_fee')::NUMERIC, 0),
    COALESCE((p_order->>'discount_amount')::NUMERIC, 0),
    COALESCE((p_order->>'total')::NUMERIC, 0),
    p_order->>'payment_method',
    COALESCE(p_order->>'payment_status', 'pending'),
    CASE WHEN p_order->>'promo_code_id' IS NOT NULL THEN (p_order->>'promo_code_id')::UUID ELSE NULL END,
    p_order->>'promo_code',
    COALESCE((p_order->>'distance_km')::NUMERIC, 0),
    COALESCE((p_order->>'estimated_delivery_minutes')::INTEGER, 30),
    p_order->>'idempotency_key',
    COALESCE((p_order->>'merchant_commission_pct')::NUMERIC, 15),
    p_order->>'paymob_order_id',
    p_order->>'notes'
  )
  RETURNING id, order_number, created_at
  INTO v_order_id, v_order_number, v_created_at;

  -- Insert all order items (atomically — if any fail, the whole transaction rolls back)
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    INSERT INTO order_items (
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

  -- Return the created order data
  RETURN QUERY SELECT v_order_id AS id, v_order_number AS order_number, v_created_at AS created_at;
END;
$$;

-- Grant execute to service role (used by Edge Functions)
GRANT EXECUTE ON FUNCTION place_order_with_items(JSONB, JSONB) TO service_role;
