-- Migration 056: admin_cancel_order RPC
--
-- Wraps the order-cancel write path (update orders row + insert
-- order_status_history row) in a single transactional RPC. Previously
-- GET /api/orders/[id]/cancel (apps/admin/src/app/api/orders/[id]/cancel/
-- route.ts) did these as two separate Supabase queries — if the second
-- (history insert) failed, the order was already marked 'cancelled' in the
-- DB but the timeline UI would be missing its entry. Review M1.
--
-- The RPC also encodes the business-rule guards (cannot cancel an already-
-- cancelled or delivered order) so the conditional update is atomic with
-- the status check — closing a small TOCTOU window in the previous route.
--
-- Parameters:
--   p_order_id   UUID  — the order to cancel.
--   p_admin_id   UUID  — the admin performing the cancellation (set on
--                        orders.cancelled_by and order_status_history.
--                        changed_by).
--   p_reason     TEXT  — one of the CANCELLATION_REASONS enum values
--                        (validated by the route's Zod schema before this
--                        RPC is called).
--   p_note       TEXT  — optional free-text note, prepended to the history
--                        note as "reason: note".
--
-- Returns: TEXT — one of:
--   'cancelled'           — success, order was transitioned to cancelled.
--   'already_cancelled'   — order.status was already 'cancelled'.
--   'already_delivered'   — order.status was 'delivered' (use refund instead).
--   'not_found'           — no order row with p_order_id exists.
--
-- Security:
--   - SECURITY DEFINER so the function can update orders + insert into
--     order_status_history. RLS still applies via the service-role key used
--     by the admin route.
--   - SET search_path = '' per the migration hardening convention (S16).
--   - PLPGSQL so we can use conditional logic + GET DIAGNOSTICS for row count.

CREATE OR REPLACE FUNCTION public.admin_cancel_order(
  p_order_id uuid,
  p_admin_id uuid,
  p_reason text,
  p_note text
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_current_status text;
  v_updated_count int;
BEGIN
  -- Lock the order row for the duration of the transaction so concurrent
  -- cancel requests serialize. This is the key concurrency fix: two
  -- simultaneous cancels can't both pass the status check.
  SELECT status INTO v_current_status
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN 'not_found';
  END IF;

  IF v_current_status = 'cancelled' THEN
    RETURN 'already_cancelled';
  END IF;

  IF v_current_status = 'delivered' THEN
    RETURN 'already_delivered';
  END IF;

  -- Conditional update: only transition if status hasn't changed under us
  -- (belt-and-suspenders alongside the FOR UPDATE lock).
  UPDATE public.orders
  SET
    status = 'cancelled',
    cancelled_by = p_admin_id,
    cancellation_reason = p_reason,
    cancelled_at = NOW()
  WHERE id = p_order_id
    AND status = v_current_status;

  GET DIAGNOSTICS v_updated_count = ROW_COUNT;

  IF v_updated_count = 0 THEN
    -- Status changed between the SELECT and UPDATE — treat as already
    -- cancelled by a concurrent request.
    RETURN 'already_cancelled';
  END IF;

  -- Insert the timeline entry. If this fails the whole transaction rolls
  -- back (including the order status update) — which is the whole point of
  -- wrapping them together (review M1).
  INSERT INTO public.order_status_history (
    order_id, status, changed_by, changed_by_role, note
  ) VALUES (
    p_order_id,
    'cancelled',
    p_admin_id,
    'admin',
    CASE WHEN p_note IS NOT NULL AND p_note <> '' THEN p_reason || ': ' || p_note
         ELSE p_reason END
  );

  RETURN 'cancelled';
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_cancel_order(uuid, uuid, text, text)
  TO service_role, authenticated, anon;
