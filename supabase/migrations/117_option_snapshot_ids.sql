-- Migration 117: Record option ids in the order snapshot (BUG-12)
--
-- THE BUG
--   order_items.selected_options stores the customer's selections as a JSONB
--   array built from NAMES only (008:117):
--
--     [{option_name_ar, option_name_en, choice_name_ar, choice_name_en,
--       price_modifier}]
--
--   VERIFIED by enumerating the JSONB keys:
--   dashborad/test/test_07_reporting.py::test_selected_options_json_has_no_choice_id
--
--   No option_id, no choice_id. Consequences:
--     * "which option configuration sells most" is answerable only by
--       string-matching labels
--     * rename a choice and history silently rewrites itself -- last quarter's
--       "Large" becomes this quarter's "XL" in the same report
--     * two merchants using the same size label cannot be told apart
--
-- APPROACH: A HELPER, NOT A REWRITE
--   place_order_with_items has been revised six times (026 -> 036 -> 045 ->
--   049 -> 075 -> 080) and the current body carries promo funding and payout
--   computation (080), atomic promo usage enforcement (045), scheduled_time
--   (049), customer IP tracking and check_promo_fraud (075), and a service-role
--   guard. Re-authoring 368 lines to change one expression risks silently
--   dropping one of those.
--
--   So this adds a standalone enrichment function and changes exactly ONE
--   expression inside place_order_with_items. Everything else in that function
--   is byte-for-byte 080.
--
-- WHY THE HELPER IS THE RIGHT PLACE
--   The client is not asked to supply ids, so it cannot get them wrong or
--   forge them. And because the helper reads price_modifier from the catalog
--   row, the snapshot's price is the DATABASE's, not the request's.
--
-- NO BACKFILL
--   The ids were never stored. Deriving them from frozen names would be a
--   guess: names are not unique across merchants, and a choice may have been
--   deleted or renamed since. Backfilling would manufacture false precision in
--   exactly the reporting this migration exists to make trustworthy. Existing
--   rows keep their names; only new orders carry ids. Reporting queries must
--   tolerate a missing choice_id -- see the output contract below.
--
-- Rollback: re-apply 080's single-expression change in reverse, i.e.
--           place_order_with_items goes back to
--             COALESCE(v_item->'selected_options', '[]'::JSONB)
--           and enrich_selected_options may be dropped. The extra JSONB keys
--           are additive; no reader breaks either way.

-- =============================================================================
-- 1. THE ENRICHMENT FUNCTION
-- =============================================================================
-- For each requested selection, resolve the option group and the choice by
-- name within this item, then emit their ids plus the catalog's price.
--
-- Unresolvable selections are silently dropped rather than raising, because
-- this runs inside place_order_with_items and the historical behaviour was to
-- store whatever the client sent. Raising here would reject baskets that used
-- to succeed. A dropped entry is visible as a shorter array, which beats a
-- failed checkout -- but it does mean a client sending an option name that no
-- longer exists gets a line priced without that modifier. Callers should
-- compare jsonb_array_length before and after if they need to detect it.
--
-- Deterministic ordering (o.sort_order, c.sort_order) so the same request
-- always produces the same snapshot.
CREATE OR REPLACE FUNCTION public.enrich_selected_options(
  p_item_id uuid,
  p_selected_options jsonb
)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'option_id',      o.option_id,
        'choice_id',      c.choice_id,
        'option_name_ar', o.name_ar,
        'option_name_en', o.name_en,
        'choice_name_ar', c.name_ar,
        'choice_name_en', c.name_en,
        'price_modifier', c.price_modifier
      )
      ORDER BY o.o_sort, c.c_sort
    ),
    '[]'::jsonb
  )
  FROM jsonb_array_elements(COALESCE(p_selected_options, '[]'::jsonb)) AS sel
  JOIN LATERAL (
    SELECT o.id AS option_id, o.name_ar, o.name_en, o.sort_order AS o_sort
      FROM public.item_options o
     WHERE o.item_id = p_item_id
       AND (
         (sel->>'option_name_en') IS NOT NULL AND o.name_en = sel->>'option_name_en'
         OR (sel->>'option_name_ar') IS NOT NULL AND o.name_ar = sel->>'option_name_ar'
       )
     ORDER BY o.sort_order
     LIMIT 1
  ) o ON TRUE
  JOIN LATERAL (
    SELECT c.id AS choice_id, c.name_ar, c.name_en,
           c.price_modifier, c.sort_order AS c_sort
      FROM public.item_option_choices c
     WHERE c.option_id = o.option_id
       AND (
         (sel->>'choice_name_en') IS NOT NULL AND c.name_en = sel->>'choice_name_en'
         OR (sel->>'choice_name_ar') IS NOT NULL AND c.name_ar = sel->>'choice_name_ar'
       )
     ORDER BY c.sort_order
     LIMIT 1
  ) c ON TRUE;
$$;

COMMENT ON FUNCTION public.enrich_selected_options(uuid, jsonb) IS
  'BUG-12 (migration 117): resolves each requested option selection to its catalog option_id and choice_id, and substitutes the DATABASE price_modifier for the client-supplied one. Returns [] for unresolvable selections rather than raising, so baskets that previously succeeded still succeed.';

-- =============================================================================
-- 2. PLACE ORDER -- ONE EXPRESSION CHANGED, NOTHING ELSE
-- =============================================================================
-- Byte-for-byte migration 080 apart from the selected_options value below.
-- Do not "tidy" the rest while editing this: the promo funding, atomic usage,
-- fraud and payout blocks are load-bearing.
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
BEGIN
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: place_order_with_items is service-role only.';
  END IF;

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

  v_subtotal := COALESCE((p_order->>'subtotal')::NUMERIC, 0);
  v_discount_amount := COALESCE((p_order->>'discount_amount')::NUMERIC, 0);

  v_commission_pct_resolved := COALESCE(
    (SELECT commission_pct FROM public.merchants WHERE id = v_merchant_id),
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
      WHERE id = v_promo_code_id
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
    v_promo_funded_by,
    v_promo_merchant_share_pct,
    v_merchant_payout
  )
  RETURNING id, order_number, created_at
  INTO v_order_id, v_order_number, v_created_at;

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
      -- === THE ONE LINE CHANGED IN 080 (BUG-12) ==========================
      -- was: COALESCE(v_item->'selected_options', '[]'::JSONB)
      -- now: resolved against the catalog, so option_id and choice_id are
      --      recorded and price_modifier comes from the database row.
      public.enrich_selected_options(
        (v_item->>'item_id')::UUID,
        COALESCE(v_item->'selected_options', '[]'::JSONB)
      ),
      -- ===================================================================
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
      WHERE id = v_promo_code_id
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
      COALESCE((p_order->>'discount_amount')::NUMERIC, 0),
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

COMMENT ON FUNCTION public.place_order_with_items(JSONB, JSONB) IS
  'Hardened atomic order creation. SECURITY DEFINER, service-role only. '
  'Migration 045: atomic per-user and global promo usage enforcement. '
  'Migration 049: scheduled_time persistence. '
  'Migration 075: customer_ip tracking + check_promo_fraud(). '
  'Migration 080: funded_by payout computation. '
  'Migration 117 (BUG-12): selected_options is passed through enrich_selected_options(), '
  'which records option_id and choice_id and takes price_modifier from the catalog. '
  'Identical to 080 apart from that one expression.';

REVOKE EXECUTE ON FUNCTION public.place_order_with_items(JSONB, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.place_order_with_items(JSONB, JSONB) TO service_role;

-- The helper runs inside a SECURITY DEFINER function, so it must be executable
-- by the same role. Revoke from PUBLIC so it is not callable directly.
REVOKE EXECUTE ON FUNCTION public.enrich_selected_options(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.enrich_selected_options(uuid, jsonb) TO service_role;

-- =============================================================================
-- 3. OUTPUT CONTRACT FOR REPORTING
-- =============================================================================
-- New shape, per entry:
--   {option_id, choice_id, option_name_ar, option_name_en,
--    choice_name_ar, choice_name_en, price_modifier}
--
-- Reporting queries MUST tolerate pre-117 rows, which have no ids:
--
--   SELECT e->>'choice_id' AS choice_id, count(*)
--     FROM order_items oi, LATERAL jsonb_array_elements(oi.selected_options) e
--    WHERE oi.created_at >= '2026-10-03'      -- migration date
--    GROUP BY 1;
--
-- Filter on the migration date, or accept a NULL choice_id bucket that
-- represents pre-117 history. Do not assume the key exists.
-- =============================================================================

-- =============================================================================
-- 4. FOUND BUT NOT FIXED HERE -- place_order_with_items TRUSTS CLIENT PRICES
-- =============================================================================
-- Observed while making this change, and deliberately NOT addressed, because
-- fixing it changes checkout arithmetic and needs product sign-off:
--
--   line 279  COALESCE((v_item->>'item_price')::NUMERIC, 0)   <- from the client
--   line 281  COALESCE((v_item->>'total_price')::NUMERIC, 0)   <- from the client
--   line 277  v_item->>'item_name_ar' / 'item_name_en'         <- from the client
--   line 236  COALESCE((p_order->>'subtotal')::NUMERIC, 0)    <- from the client
--
-- The service-role guard means only the Edge Function can call this, so the
-- trust boundary is "does place-order EF recompute prices before calling?".
-- If it does not, a tampered payload sets the order total, the order-item
-- snapshot, and the commission base. Recorded as BUG-18; verify the EF before
-- assuming it is safe.