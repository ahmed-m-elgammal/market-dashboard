-- Migration 086: cancel_order notification subtransaction + mark_driver_settlement_paid payout_reference validation
--
-- P2 fixes from money-movement-gap-analysis.md:
--
-- §3.8 (LOW→MEDIUM): The cancel_order RPC inserts into `notifications`
-- (customer + driver) inside the same transaction as the `orders` UPDATE
-- and `driver_earnings` insert. If a notification insert fails (e.g., a
-- constraint violation or a trigger that raises), the entire transaction
-- rolls back — including the `merchant_payout` recomputation and the
-- `payout_recomputed_at` stamp. The customer's cancel request fails
-- entirely because of a notification insert error.
--
-- Fix: wrap the notification inserts in a subtransaction with
-- `EXCEPTION WHEN OTHERS THEN` so a notification failure is logged but
-- does not roll back the cancellation. The `driver_earnings` insert
-- (compensation) is money-moving and stays in the main transaction.
--
-- §3.2 (CRITICAL defense-in-depth): The mark_driver_settlement_paid RPC
-- (migration 083) takes p_payout_reference TEXT and writes it directly
-- into the row without validating non-emptiness. The admin API route
-- enforces z.string().min(1), but if any other caller ever invokes the
-- RPC directly (a future internal tool, a SQL session, a background job),
-- it would accept '' or NULL. The S4 mark_merchant_payout_paid RPC
-- (migration 085) already has this validation baked in — this migration
-- brings the S5 RPC to parity.
--
-- Both changes are RECREATIONS of existing RPCs (DROP + CREATE OR REPLACE
-- would not work for SECURITY DEFINER functions; CREATE OR REPLACE alone
-- preserves the existing ACL, which is what we want).

BEGIN;

-- =============================================================================
-- 1. cancel_order RPC — recreate with notification subtransaction
-- =============================================================================
-- Body is identical to migration 082's canonical version except:
--   * The two INSERT INTO notifications statements are wrapped in
--     BEGIN ... EXCEPTION WHEN OTHERS THEN ... END
--   * A RAISE NOTICE records the failure for ops debugging
--   * The driver_earnings INSERT stays in the main transaction (money-moving)
--   * The RETURN shape is unchanged (8 columns including payout_recomputed_at)
--     so all existing callers (cancel-order EF, admin cancel route,
--     reconcile-payments EF) continue to work without changes.

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
  SELECT * INTO v_order
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
  SELECT * INTO v_rule FROM public.cancellation_rules
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
  -- 5b. NOTIFICATIONS — wrapped in a subtransaction (§3.8 fix)
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

COMMENT ON FUNCTION public.cancel_order(UUID, UUID, TEXT, TEXT) IS 'Atomically cancels an order with row-level locking: validates rules, calculates fees/refunds, updates order + status history, notifies stakeholders (in a subtransaction so a notification failure does NOT roll back the cancellation — gap-analysis §3.8), compensates driver. Recomputes merchant_payout (proportional reduction on cancellation, zeroed on full refund) and stamps payout_recomputed_at. SECURITY DEFINER — service role only.';

-- ACL preserved by CREATE OR REPLACE — re-issue to be explicit (matches
-- the pattern in migration 082).
REVOKE EXECUTE ON FUNCTION public.cancel_order(UUID, UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cancel_order(UUID, UUID, TEXT, TEXT) TO service_role;

-- =============================================================================
-- 2. mark_driver_settlement_paid RPC — add payout_reference validation (§3.2)
-- =============================================================================
-- Recreate the RPC with the same body as migration 083 plus a non-empty
-- check on p_payout_reference at the top of the body. Brings the S5 RPC
-- to parity with S4's mark_merchant_payout_paid (migration 085).
--
-- The admin API route already validates via Zod, but defense-in-depth says
-- the money-moving RPC should be the authoritative validator. If a future
-- internal tool or SQL session invokes this RPC directly with an empty
-- reference, the RPC must reject it — not silently record a paid row with
-- no audit trail.

CREATE OR REPLACE FUNCTION public.mark_driver_settlement_paid(
  p_settlement_id UUID,
  p_paid_by UUID,
  p_payout_reference TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: mark_driver_settlement_paid can only be called by service role.';
  END IF;

  -- Defense-in-depth: payout_reference must be non-empty (gap-analysis §3.2).
  -- Mirrors the validation in mark_merchant_payout_paid (migration 085).
  IF p_payout_reference IS NULL OR trim(p_payout_reference) = '' THEN
    RAISE EXCEPTION 'payout_reference is required to mark a settlement paid'
      USING ERRCODE = 'not_null_violation';
  END IF;

  UPDATE public.driver_settlements
    SET
      status = 'paid',
      paid_at = NOW(),
      paid_by = p_paid_by,
      payout_reference = p_payout_reference,
      updated_at = NOW()
    WHERE id = p_settlement_id AND status IN ('pending', 'approved');
END;
$$;

COMMENT ON FUNCTION public.mark_driver_settlement_paid(UUID, UUID, TEXT) IS 'Manually marks a driver settlement as paid. Used when Paymob disbursement is not wired (default) or as a fallback. Idempotent: no-op if already paid. Validates payout_reference is non-empty (defense-in-depth, gap-analysis §3.2). SECURITY DEFINER — service role only.';

REVOKE ALL ON FUNCTION public.mark_driver_settlement_paid(UUID, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_driver_settlement_paid(UUID, UUID, TEXT) TO service_role;

COMMIT;
