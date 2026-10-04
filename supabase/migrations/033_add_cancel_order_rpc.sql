-- Migration 033: Atomic cancel_order RPC with fee calculation
-- Per 23-ORDER-CANCELLATION.md and cancellation_rules table (migration 023):
--   Cancellation involves multiple steps that must be atomic:
--   1. Check if cancellation is allowed per cancellation_rules
--   2. Calculate refund amount and cancellation fee
--   3. Update order status to 'cancelled'
--   4. Calculate driver compensation if applicable
--   5. Create notification for customer, driver, and merchant
--   6. Log the cancellation in order_status_history
--
-- This function wraps all of that in a single transaction.

-- =============================================================================
-- ATOMIC ORDER CANCELLATION FUNCTION
-- =============================================================================

CREATE OR REPLACE FUNCTION public.cancel_order(
  p_order_id UUID,
  p_initiator_id UUID,
  p_initiator_role TEXT,  -- 'customer', 'driver', 'admin', 'system'
  p_reason TEXT DEFAULT NULL
)
RETURNS TABLE (
  order_id UUID,
  status TEXT,
  refund_amount NUMERIC,
  cancellation_fee NUMERIC,
  driver_compensation NUMERIC,
  refund_percentage NUMERIC
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
BEGIN
  -- Security check
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: cancel_order can only be called by service role (via Edge Function).';
  END IF;

  -- =====================================================================
  -- 1. FETCH ORDER AND VALIDATE
  -- =====================================================================
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;

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
  SELECT * INTO v_rule FROM public.cancellation_rules
  WHERE order_status = v_order.status
    AND initiator = p_initiator_role;

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
  -- Refund amount
  v_refund_amount := v_order.total * (v_refund_percentage / 100);

  -- Cancellation fee
  v_cancellation_fee := GREATEST(
    v_order.subtotal * (v_cancellation_fee_pct / 100),
    v_cancellation_fee_min
  );

  -- Cap cancellation fee at order total
  v_cancellation_fee := LEAST(v_cancellation_fee, v_order.total);

  -- Determine new payment status
  IF v_refund_percentage = 100 THEN
    v_new_payment_status := 'refunded';
  ELSIF v_refund_percentage > 0 THEN
    v_new_payment_status := 'partial_refund';
  ELSE
    -- No refund — keep existing payment status
    v_new_payment_status := v_order.payment_status;
  END IF;

  -- =====================================================================
  -- 5. ATOMIC UPDATE: Order + Status History + Notification
  -- =====================================================================

  -- Update order
  UPDATE public.orders
  SET status = 'cancelled',
      cancelled_by = p_initiator_id,
      cancellation_reason = p_reason,
      cancellation_fee = v_cancellation_fee,
      cancelled_at = NOW(),
      refund_amount = v_refund_amount,
      refund_status = v_new_payment_status,
      payment_status = CASE
        WHEN v_order.payment_method = 'cash' AND v_refund_percentage = 100 THEN 'pending_cash'
        ELSE v_new_payment_status
      END
  WHERE id = p_order_id;

  -- Log in order_status_history (also handled by trigger, but explicit here for additional data)
  INSERT INTO public.order_status_history (order_id, status, changed_by, changed_by_role, note)
  VALUES (
    p_order_id,
    'cancelled',
    p_initiator_id,
    p_initiator_role,
    'Cancelled by ' || p_initiator_role || '. Reason: ' || COALESCE(p_reason, 'Not specified') ||
    '. Refund: ' || v_refund_amount || ' EGP (' || v_refund_percentage || '%). Fee: ' || v_cancellation_fee || ' EGP.'
  );

  -- Notify customer
  INSERT INTO public.notifications (user_id, type, title_ar, title_en, body_ar, body_en, data)
  VALUES (
    v_order.customer_id,
    'order_cancelled',
    'تم إلغاء طلبك', 'Order Cancelled',
    'تم إلغاء طلبك رقم ' || v_order.order_number || '. المبلغ المسترد: ' || v_refund_amount || ' ج.م',
    'Your order ' || v_order.order_number || ' has been cancelled. Refund: ' || v_refund_amount || ' EGP',
    jsonb_build_object('order_id', p_order_id, 'refund_amount', v_refund_amount)
  );

  -- Notify driver if assigned
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

    -- Create driver compensation earning if applicable
    IF v_driver_compensation > 0 THEN
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
  END IF;

  -- =====================================================================
  -- 6. RETURN RESULT
  -- =====================================================================
  RETURN QUERY SELECT
    p_order_id,
    'cancelled'::TEXT,
    v_refund_amount,
    v_cancellation_fee,
    v_driver_compensation,
    v_refund_percentage;
END;
$$;

COMMENT ON FUNCTION public.cancel_order(UUID, UUID, TEXT, TEXT) IS 'Atomically cancels an order: validates rules, calculates fees/refunds, updates order, notifies stakeholders, compensates driver. Based on cancellation_rules table. SECURITY DEFINER — service role only.';

-- =============================================================================
-- GRANT PERMISSIONS
-- =============================================================================

REVOKE EXECUTE ON FUNCTION public.cancel_order(UUID, UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cancel_order(UUID, UUID, TEXT, TEXT) TO service_role;
