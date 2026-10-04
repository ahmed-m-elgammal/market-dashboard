-- Migration 123: fix AmbiguousColumn in place_order_with_items (BUG-14)
--
-- THE BUG
--   place_order_with_items is declared
--
--       RETURNS TABLE(id uuid, order_number text, created_at timestamp with time zone)
--
--   In plpgsql an OUT parameter (a RETURNS TABLE column) is a variable in the
--   function's scope. The duplicate-detection branch references created_at
--   unqualified, so it matches BOTH the OUT parameter and
--   public.orders.created_at and Postgres raises:
--
--       ERROR:  AmbiguousColumn
--       CONTEXT:  place_order_with_items line 100
--
--   That branch is the ELSE of IF v_idempotency_key IS NOT NULL, so it runs
--   exactly when the caller did NOT supply an idempotency key. Every caller
--   omitting the key got an error instead of a duplicate check, which was
--   never the stated contract.
--
--   Only created_at collides. customer_id, merchant_id and status are not OUT
--   parameters of this function, so they resolve to the table column correctly
--   and are deliberately left unqualified.
--
-- HOW THIS WAS FOUND
--   dashborad/test/test_13_order_lifecycle_e2e.py. Every other order test passes
--   an idempotency_key, so this branch had no coverage at all: the bug was
--   invisible rather than absent.
--
-- THE FIX
--   Qualify the one reference: public.orders.created_at.
--
-- DATA IMPACT
--   None. No stored row changes; this only makes an erroring code path
--   executable. The idempotency_key branch is untouched.
--
-- Rollback: revert the qualification. Restores a function that cannot be called
--           without an idempotency key.

CREATE OR REPLACE FUNCTION public.place_order_with_items(p_order jsonb, p_items jsonb) RETURNS TABLE(id uuid, order_number text, created_at timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
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
  v_customer_ip INET;
  v_fraud_count INTEGER;
  v_subtotal NUMERIC(10,2);
  v_discount_amount NUMERIC(10,2);
  v_commission_pct_resolved NUMERIC(5,2);
  v_promo_funded_by TEXT;
  v_promo_merchant_share_pct NUMERIC(5,2);
  v_merchant_discount_floor NUMERIC(10,2);
  v_merchant_discount_share NUMERIC(10,2);
  v_merchant_payout NUMERIC(10,2);
  -- REQ-02
  v_item_id          UUID;
  v_item_list_price  NUMERIC(10,2);   -- items.price, pre-discount
  v_item_sell_price  NUMERIC(10,2);   -- COALESCE(discount_price, price)
  v_item_available   BOOLEAN;
  v_item_deleted     TIMESTAMPTZ;     -- items.deleted_at (migration 110)
  v_modifiers        NUMERIC(10,2);   -- sum of price_modifier across selections
  v_line_total       NUMERIC(10,2);
  v_lines            JSONB := '[]'::jsonb;  -- prepared lines, server-priced
BEGIN
  -- BUG FIXED HERE (pre-existing since 080): the original guard was
  --     COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '')
  -- When the GUC is unset, current_setting returns NULL, COALESCE then picks
  -- the empty string, and ''::json raises
  --     invalid input syntax for type json ... input string ended unexpectedly
  -- instead of the intended 'Unauthorized'. A rejected caller got a confusing
  -- parse error instead of an auth error. NULLIF turns the unset case into
  -- NULL, so COALESCE falls through to '' and the guard does its job.
  IF COALESCE(
       NULLIF(current_setting('request.jwt.claims', true), '')::json->>'role',
       ''
     ) <> 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: place_order_with_items is service-role only.';
  END IF;

  v_customer_id := (p_order->>'customer_id')::UUID;
  v_merchant_id := (p_order->>'merchant_id')::UUID;
  v_idempotency_key := p_order->>'idempotency_key';

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = v_customer_id) THEN
    RAISE EXCEPTION 'Customer not found';
  END IF;

  -- REQ-02 / BUG-13: an unapproved vendor cannot take orders.
  IF NOT EXISTS (
    SELECT 1 FROM public.merchants
     WHERE merchants.id = v_merchant_id AND merchants.is_active = TRUE
       AND merchants.approval_status = 'approved'
  ) THEN
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
        AND public.orders.created_at > NOW() - (v_duplicate_threshold_seconds || ' seconds')::INTERVAL
        AND status != 'cancelled'
    ) THEN
      RAISE EXCEPTION 'Duplicate order (recent similar order)';
    END IF;
  END IF;

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

  SELECT COALESCE(
    (SELECT value::NUMERIC FROM public.platform_config WHERE key = 'merchant_discount_floor'),
    0
  ) INTO v_merchant_discount_floor;

  -- =====================================================================
  -- PRICING PASS (REQ-02: moved ahead of the order INSERT)
  -- =====================================================================
  -- Now a real pass rather than arithmetic on client-supplied numbers. Prices
  -- come from the catalog, discounts are applied here, and the line totals are
  -- stored in v_lines for the INSERT below.
  --
  -- Three consequences, all intentional:
  --   1. a tampered item_price in the payload is ignored
  --   2. discount_price is applied by the server, so it cannot be bypassed
  --   3. order_items.total_price is computed, not trusted
  --
  -- v_subtotal therefore becomes server-derived. The client's subtotal, total
  -- and discount_amount are still read for the fee/promo arithmetic below --
  -- see section 5 for why that half is left open.
  v_lines := '[]'::jsonb;
  v_subtotal := 0;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_item_id := (v_item->>'item_id')::UUID;

    SELECT price, COALESCE(discount_price, price), is_available, deleted_at
      INTO v_item_list_price, v_item_sell_price, v_item_available, v_item_deleted
      FROM public.items
     WHERE items.id = v_item_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Item not found';
    END IF;
    IF v_item_deleted IS NOT NULL THEN
      RAISE EXCEPTION 'Item unavailable';
    END IF;
    IF NOT v_item_available THEN
      RAISE EXCEPTION 'Item unavailable';
    END IF;

    -- Option modifiers, resolved from the catalog by enrich_selected_options
    -- (migration 117). Sourced from the database, not the request.
    v_modifiers := COALESCE((
      SELECT sum(COALESCE((e->>'price_modifier')::NUMERIC, 0))
        FROM jsonb_array_elements(
               public.enrich_selected_options(
                 v_item_id,
                 COALESCE(v_item->'selected_options', '[]'::jsonb)
               )
             ) e
    ), 0);

    -- A reduction must not exceed the base price (BUG-06 follow-up). Column
    -- CHECKs cannot span tables, so this is enforced here.
    IF v_modifiers < -v_item_sell_price THEN
      RAISE EXCEPTION 'Price modifier exceeds item price';
    END IF;

    v_line_total := (v_item_sell_price + v_modifiers) * COALESCE((v_item->>'quantity')::INTEGER, 1);
    IF v_line_total < 0 THEN
      RAISE EXCEPTION 'Invalid total';
    END IF;
    v_subtotal := v_subtotal + v_line_total;

    v_lines := v_lines || jsonb_build_array(
      jsonb_build_object(
        'item_id',            v_item_id,
        'item_name_ar',       (SELECT items.name_ar FROM public.items WHERE items.id = v_item_id),
        'item_name_en',       (SELECT items.name_en FROM public.items WHERE items.id = v_item_id),
        'item_price',         v_item_sell_price,
        'original_price',     v_item_list_price,
        'quantity',           COALESCE((v_item->>'quantity')::INTEGER, 1),
        'total_price',        v_line_total,
        'selected_options',   public.enrich_selected_options(
                               v_item_id,
                               COALESCE(v_item->'selected_options', '[]'::jsonb)
                             ),
        'special_instructions', v_item->>'special_instructions'
      )
    )::jsonb;
  END LOOP;

  -- =========================================================================
  -- v_subtotal is now server-derived. Re-state the client values that the fee
  -- and promo blocks below still consume.
  -- =========================================================================
  v_discount_amount := COALESCE((p_order->>'discount_amount')::NUMERIC, 0);

  v_commission_pct_resolved := COALESCE(
    (SELECT merchants.commission_pct FROM public.merchants
     WHERE merchants.id = v_merchant_id),
    v_merchant_commission_pct
  );

  v_promo_funded_by := NULL;
  v_promo_merchant_share_pct := NULL;
  v_merchant_discount_share := 0;

  IF p_order->>'promo_code_id' IS NOT NULL THEN
    v_promo_code_id := (p_order->>'promo_code_id')::UUID;

    SELECT funded_by, merchant_share_pct, max_usage, max_usage_per_user
      INTO v_promo_funded_by, v_promo_merchant_share_pct, v_promo_max_usage, v_promo_max_usage_per_user
      FROM public.promo_codes
      WHERE promo_codes.id = v_promo_code_id
      FOR UPDATE;

    IF v_discount_amount > 0 THEN
      v_merchant_discount_share := CASE
        WHEN v_promo_funded_by = 'platform' THEN 0
        WHEN v_promo_funded_by = 'merchant' THEN v_discount_amount
        WHEN v_promo_funded_by = 'shared' THEN
          CASE
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

  -- Commission base is the server-derived subtotal, not the client's.
  v_merchant_payout := ROUND(
    (v_subtotal - v_merchant_discount_share) *
    (1 - v_commission_pct_resolved / 100),
    2
  );

  IF v_merchant_payout < 0 THEN
    v_merchant_payout := 0;
  END IF;

  INSERT INTO public.orders (
    customer_id, merchant_id, status, delivery_address,
    subtotal, delivery_fee, platform_fee, discount_amount, total,
    payment_method, payment_status, promo_code_id, promo_code,
    distance_km, estimated_delivery_minutes, idempotency_key,
    merchant_commission_pct, paymob_order_id, notes,
    customer_phone, scheduled_time,
    promo_funded_by, promo_merchant_share_pct, merchant_payout
  ) VALUES (
    v_customer_id,
    v_merchant_id,
    COALESCE(p_order->>'status', 'pending'),
    p_order->'delivery_address',
    -- === server-derived (was: the client's subtotal) ===
    v_subtotal,
    COALESCE((p_order->>'delivery_fee')::NUMERIC, 0),
    CASE
      WHEN v_platform_fee_pct > 0 THEN ROUND(v_subtotal * v_platform_fee_pct / 100, 2)
      ELSE v_platform_fee
    END,
    v_discount_amount,
    -- total recomputed from the server subtotal so the header cannot disagree
    -- with its own lines.
    v_subtotal
      + COALESCE((p_order->>'delivery_fee')::NUMERIC, 0)
      + CASE
          WHEN v_platform_fee_pct > 0 THEN ROUND(v_subtotal * v_platform_fee_pct / 100, 2)
          ELSE v_platform_fee
        END
      - v_discount_amount,
    -- BUG FIXED HERE (pre-existing since 080): both were passed straight
    -- through with no default, so a payload omitting them hit the orders
    -- NOT NULL constraints instead of using the column defaults. Every other
    -- optional field here is COALESCEd.
    COALESCE(p_order->>'payment_method', 'cash'),
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
    v_promo_funded_by,
    v_promo_merchant_share_pct,
    v_merchant_payout
  )
  RETURNING orders.id, orders.order_number, orders.created_at
  INTO v_order_id, v_order_number, v_created_at;

  -- =====================================================================
  -- INSERT ORDER ITEMS from the prepared lines
  -- =====================================================================
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_lines)
  LOOP
    INSERT INTO public.order_items (
      order_id, item_id, item_name_ar, item_name_en,
      item_price, original_price, quantity, total_price,
      selected_options, special_instructions
    ) VALUES (
      v_order_id,
      (v_item->>'item_id')::UUID,
      v_item->>'item_name_ar',
      v_item->>'item_name_en',
      -- charged price (discounted when active)
      (v_item->>'item_price')::NUMERIC,
      -- pre-discount price, so history survives the promotion ending
      (v_item->>'original_price')::NUMERIC,
      (v_item->>'quantity')::INTEGER,
      (v_item->>'total_price')::NUMERIC,
      v_item->'selected_options',
      v_item->>'special_instructions'
    );
  END LOOP;

  IF p_order->>'promo_code_id' IS NOT NULL THEN
    IF p_order->>'customer_ip' IS NOT NULL THEN
      v_customer_ip := (p_order->>'customer_ip')::INET;
    ELSE
      v_customer_ip := NULL;
    END IF;

    UPDATE public.promo_codes
      SET current_usage = current_usage + 1
      WHERE promo_codes.id = v_promo_code_id
        AND current_usage < v_promo_max_usage
      RETURNING current_usage INTO v_new_usage;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Promo code % has reached its global usage limit', v_promo_code_id
        USING ERRCODE = 'check_violation';
    END IF;

    SELECT COUNT(*) INTO v_user_usage_count
      FROM public.promo_code_usage
      WHERE promo_code_id = v_promo_code_id AND user_id = v_customer_id;

    IF v_user_usage_count >= v_promo_max_usage_per_user THEN
      RAISE EXCEPTION 'Promo code % has reached its per-user usage limit for user %',
        v_promo_code_id, v_customer_id
        USING ERRCODE = 'check_violation';
    END IF;

    INSERT INTO public.promo_code_usage (promo_code_id, user_id, order_id, discount_amount, ip_address)
    VALUES (
      v_promo_code_id,
      v_customer_id,
      v_order_id,
      v_discount_amount,
      v_customer_ip
    );

    IF v_customer_ip IS NOT NULL THEN
      BEGIN
        SELECT public.check_promo_fraud(v_promo_code_id, v_customer_ip) INTO v_fraud_count;
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Promo fraud check failed for promo % IP %: %', v_promo_code_id, v_customer_ip, SQLERRM;
      END;
    END IF;
  END IF;

  RETURN QUERY SELECT v_order_id AS id, v_order_number AS order_number, v_created_at AS created_at;
END;
$$;
COMMENT ON FUNCTION public.place_order_with_items(jsonb, jsonb) IS
  'BUG-14 (migration 123): the no-idempotency-key duplicate check referenced created_at unqualified, which is ambiguous against the RETURNS TABLE output column of the same name, so the function raised AmbiguousColumn whenever a caller omitted the key. Now qualified as public.orders.created_at.';
