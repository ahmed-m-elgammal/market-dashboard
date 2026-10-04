-- Migration 088: cancel_order RPC — explicit column lists (§5.5) + forward-reference chain (§5.4)
--
-- P3 cleanup from money-movement-gap-analysis.md:
--
-- §5.5 (LOW→MEDIUM maintainability): The cancel_order RPC used
-- `SELECT * INTO v_order` and `SELECT * INTO v_rule` to capture all columns
-- into RECORD variables. This is fragile to schema changes — if a future
-- migration adds a column with a NOT NULL constraint and no default, the
-- RPC could break at runtime. Replacing `SELECT *` with explicit column
-- lists of only the fields the RPC actually uses makes the dependencies
-- explicit and resilient to schema drift.
--
-- §5.4 (MEDIUM maintainability): The cancel_order RPC is defined in 4
-- migrations (081 → 082 → 086 → 088). This header documents the full chain
-- so a new engineer reading any earlier migration knows where the canonical
-- version lives:
--   - 081: original 7-column return (merchant_payout recomputation)
--   - 082: added payout_recomputed_at as 8th return column
--   - 086: wrapped notification inserts in a subtransaction (§3.8) +
--          added mark_driver_settlement_paid payout_reference validation (§3.2)
--   - 088: replaced SELECT * with explicit column lists (§5.5) — THIS FILE
--
-- The body is identical to migration 086's cancel_order except:
--   1. `SELECT * INTO v_order` → explicit 10-column list
--   2. `SELECT * INTO v_rule` → explicit 6-column list
--   3. The §3.8 subtransaction fix is preserved
--   4. The 8-column RETURN shape is preserved
-- All existing callers (cancel-order EF, admin cancel route,
-- reconcile-payments EF) continue to work without changes.

DROP FUNCTION IF EXISTS public.cancel_order(UUID, UUID, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.cancel_order(
  p_order_id UUID,
  p_initiator_id UUID,
  p_initiator_role TEXT,
  p_reason TEXT DEFAULT NULL
)
RETURNS TABLE (
  order_id UUID,
  status TEXT,
  refund_amount NUMERIC,
  cancellation_fee NUMERIC,
  driver_compensation NUMERIC,
  refund_percentage NUMERIC,
  merchant_payout NUMERIC,
  payout_recomputed_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_order RECORD;
  v_rule RECORD;
  v_can_cancel BOOLEAN;
  v_refund_percentage NUMERIC;
  v_cancellation_fee_pct NUMERIC;
  v_cancellation_fee_min NUMERIC;
  v_driver_compensation NUMERIC;
  v_requires_reason BOOLEAN;
  v_refund_amount NUMERIC;
  v_cancellation_fee NUMERIC;
  v_new_payment_status TEXT;
  v_adjusted_merchant_payout NUMERIC(10,2);
  v_updated_count INT;
BEGIN
  -- Security check
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: cancel_order can only be called by service role (via Edge Function).';
  END IF;

  -- =====================================================================
  -- 1. FETCH ORDER AND VALIDATE (WITH FOR UPDATE LOCK)
  -- =====================================================================
  -- §5.5 fix: explicit column list instead of SELECT *. Only the fields
  -- the RPC actually uses are fetched — resilient to future schema changes
  -- (a new NOT NULL column on orders won't break this RPC). The FOR UPDATE
  -- lock is on the row, not the columns, so locking behavior is unchanged.
  SELECT
    id, customer_id, driver_id, status, subtotal, total,
    payment_method, payment_status, merchant_payout, order_number
  INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF v_order.status = 'cancelled' THEN
    RAISE EXCEPTION 'Order is already cancelled';
  END IF;

  IF v_order.status = 'delivered' THEN
    RAISE EXCEPTION 'Delivered orders cannot be cancelled through this function';
  END IF;

  -- =====================================================================
  -- 2. LOOK UP CANCELLATION RULES
  -- =====================================================================
  -- §5.5 fix: explicit column list instead of SELECT *.
  SELECT
    can_cancel, refund_percentage, cancellation_fee_percentage,
    cancellation_fee_min, driver_compensation, requires_reason
  INTO v_rule
  FROM public.cancellation_rules
  WHERE order_status = v_order.status AND initiator = p_initiator_role;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No cancellation rule found for status=% and initiator=%', v_order.status, p_initiator_role;
  END IF;

  v_can_cancel := v_rule.can_cancel;
  v_refund_percentage := v_rule.refund_percentage;
  v_cancellation_fee_pct := v_rule.cancellation_fee_percentage;
  v_cancellation_fee_min := v_rule.cancellation_fee_min;
  v_driver_compensation := v_rule.driver_compensation;
  v_requires_reason := v_rule.requires_reason;

  -- =====================================================================
  -- 3. VALIDATE CANCELLATION
  -- =====================================================================
  IF NOT v_can_cancel THEN
    RAISE EXCEPTION 'Cancellation not allowed for status=% by initiator=%', v_order.status, p_initiator_role;
  END IF;

  IF v_requires_reason AND (p_reason IS NULL OR trim(p_reason) = '') THEN
    RAISE EXCEPTION 'Cancellation reason is required for status=%', v_order.status;
  END IF;

  -- =====================================================================
  -- 4. CALCULATE FINANCIALS
  -- =====================================================================
  v_refund_amount := v_order.total * (v_refund_percentage / 100);

  v_cancellation_fee := GREATEST(
    v_order.subtotal * (v_cancellation_fee_pct / 100),
    v_cancellation_fee_min
  );

  v_cancellation_fee := LEAST(v_cancellation_fee, v_order.total);

  IF v_refund_percentage = 100 THEN
    v_new_payment_status := 'refunded';
  ELSIF v_refund_percentage > 0 THEN
    v_new_payment_status := 'partial_refund';
  ELSE
    v_new_payment_status := v_order.payment_status;
  END IF;

  -- S2: Compute adjusted merchant_payout based on refund percentage.
  v_adjusted_merchant_payout := CASE
    WHEN v_refund_percentage = 100 THEN 0
    WHEN v_refund_percentage = 0 THEN v_order.merchant_payout
    ELSE ROUND(
      v_order.merchant_payout * (1 - v_refund_percentage / 100),
      2
    )
  END;

  -- =====================================================================
  -- 5. ATOMIC UPDATE: Order + Status History
  -- =====================================================================
  -- Status history stays in the main transaction — it's audit data that
  -- must be consistent with the order status change.

  UPDATE public.orders
  SET status = 'cancelled',
      cancelled_by = p_initiator_id,
      cancellation_reason = p_reason,
      cancellation_fee = v_cancellation_fee,
      cancelled_at = NOW(),
      refund_amount = v_refund_amount,
      refund_status = v_new_payment_status,
      merchant_payout = v_adjusted_merchant_payout,
      payout_recomputed_at = NOW(),
      payment_status = CASE
        WHEN v_order.payment_method = 'cash' AND v_refund_percentage = 100 THEN 'pending_cash'
        ELSE v_new_payment_status
      END
  WHERE id = p_order_id
    AND status = v_order.status;

  GET DIAGNOSTICS v_updated_count = ROW_COUNT;

  IF v_updated_count = 0 THEN
    RAISE EXCEPTION 'Order status changed concurrently during cancellation processing';
  END IF;

  INSERT INTO public.order_status_history (order_id, status, changed_by, changed_by_role, note)
  VALUES (
    p_order_id,
    'cancelled',
    p_initiator_id,
    p_initiator_role,
    'Cancelled by ' || p_initiator_role || '. Reason: ' || COALESCE(p_reason, 'Not specified') ||
    '. Refund: ' || v_refund_amount || ' EGP (' || v_refund_percentage || '%). Fee: ' || v_cancellation_fee || ' EGP.'
  );

  -- =====================================================================
  -- 5b. NOTIFICATIONS — wrapped in a subtransaction (§3.8 fix, from mig 086)
  -- =====================================================================
  -- Notifications are NOT money-critical. A failed notification insert
  -- should NOT roll back the cancellation. The customer should still see
  -- "Order cancelled" in the app, even if the push notification delivery
  -- is delayed. The driver_earnings insert below is money-moving and
  -- stays in the main transaction (outside the subtransaction).
  BEGIN
    INSERT INTO public.notifications (user_id, type, title_ar, title_en, body_ar, body_en, data)
    VALUES (
      v_order.customer_id,
      'order_cancelled',
      'تم إلغاء طلبك', 'Order Cancelled',
      'تم إلغاء طلبك رقم ' || v_order.order_number || '. المبلغ المسترد: ' || v_refund_amount || ' ج.م',
      'Your order ' || v_order.order_number || ' has been cancelled. Refund: ' || v_refund_amount || ' EGP',
      jsonb_build_object('order_id', p_order_id, 'refund_amount', v_refund_amount)
    );

    IF v_order.driver_id IS NOT NULL THEN
      INSERT INTO public.notifications (user_id, type, title_ar, title_en, body_ar, body_en, data)
      VALUES (
        v_order.driver_id,
        'order_cancelled',
        'تم إلغاء الطلب', 'Order Cancelled',
        'تم إلغاء الطلب رقم ' || v_order.order_number || '. تعويض: ' || v_driver_compensation || ' ج.م',
        'Order ' || v_order.order_number || ' has been cancelled. Compensation: ' || v_driver_compensation || ' EGP',
        jsonb_build_object('order_id', p_order_id, 'compensation', v_driver_compensation)
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    -- Swallow the notification failure — the cancellation itself is already
    -- committed to the orders table (the UPDATE above succeeded). Log a
    -- NOTICE so ops can grep for "Notification insert failed" in the EF
    -- logs and investigate if a notification subsystem is broken.
    RAISE NOTICE 'Notification insert failed for order %: %', p_order_id, SQLERRM;
  END;

  -- =====================================================================
  -- 5c. DRIVER COMPENSATION — stays in main transaction (money-moving)
  -- =====================================================================
  -- This MUST roll back if it fails — a missing compensation earning is a
  -- money leak that finance would have to reconcile manually. Keeping it
  -- outside the notification subtransaction preserves that guarantee.

  IF v_order.driver_id IS NOT NULL AND v_driver_compensation > 0 THEN
    INSERT INTO public.driver_earnings (
      driver_id, order_id, delivery_fee_earned, platform_fee_deducted,
      net_earnings, earnings_pct_used, is_cancellation_compensation, compensation_reason
    ) VALUES (
      v_order.driver_id,
      p_order_id,
      v_driver_compensation,
      0,
      v_driver_compensation,
      100,
      TRUE,
      'Cancellation compensation for order ' || v_order.order_number
    );
  END IF;

  -- =====================================================================
  -- 6. RETURN RESULT (8 columns — unchanged from migration 082)
  -- =====================================================================
  RETURN QUERY SELECT
    p_order_id,
    'cancelled'::TEXT,
    v_refund_amount,
    v_cancellation_fee,
    v_driver_compensation,
    v_refund_percentage,
    v_adjusted_merchant_payout,
    NOW()::TIMESTAMPTZ;
END;
$$;

COMMENT ON FUNCTION public.cancel_order(UUID, UUID, TEXT, TEXT) IS 'Atomically cancels an order with row-level locking: validates rules, calculates fees/refunds, updates order + status history, notifies stakeholders (in a subtransaction so a notification failure does NOT roll back the cancellation — gap-analysis §3.8), compensates driver. Recomputes merchant_payout (proportional reduction on cancellation, zeroed on full refund) and stamps payout_recomputed_at. Uses explicit column lists instead of SELECT * (gap-analysis §5.5). SECURITY DEFINER — service role only.';

-- ACL preserved by CREATE OR REPLACE — re-issue to be explicit (matches
-- the pattern in migration 082 + 086).
REVOKE EXECUTE ON FUNCTION public.cancel_order(UUID, UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cancel_order(UUID, UUID, TEXT, TEXT) TO service_role;
