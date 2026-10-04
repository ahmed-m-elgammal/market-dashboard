-- Migration 061: Drop trigger_increment_driver_deliveries (A3-G3)
--
-- The on_order_delivered_increment_driver_deliveries trigger (migration 018,
-- lines 177-198) fires AFTER UPDATE OF status WHEN NEW.status = 'delivered'
-- and increments drivers.total_deliveries by 1.
--
-- The handleCompleteDelivery action in the driver-actions Edge Function ALSO
-- increments drivers.total_deliveries (and total_earnings) atomically via
-- the increment_driver_stats RPC (migration 038, hardened in migration 044).
--
-- Result: every delivery increments total_deliveries by 2 (once by trigger,
-- once by RPC). Driver dashboards show 2× the actual delivery count.
-- total_earnings is only incremented by the RPC (the trigger doesn't touch
-- it), so the earnings number is correct — but the delivery count is wrong.
--
-- Fix: drop the trigger. The EF + RPC is the authoritative path because:
--   1. It updates BOTH total_deliveries and total_earnings atomically.
--   2. It is the path that has the driver_id in scope (the trigger would
--      fire even for admin status overrides to 'delivered', which may not
--      have a driver assigned — though the trigger checks NEW.driver_id
--      IS NOT NULL, it's cleaner to let the EF own this).
--   3. The RPC is SECURITY DEFINER with SET search_path = '' (hardened),
--      matching the codebase's security pattern.
--
-- We keep the trigger FUNCTION (trigger_increment_driver_deliveries) in
-- case a future migration wants to re-attach it, but DROP the TRIGGER
-- itself so it no longer fires.

DROP TRIGGER IF EXISTS on_order_delivered_increment_driver_deliveries ON public.orders;

COMMENT ON FUNCTION public.trigger_increment_driver_deliveries() IS
  'A3-G3: trigger detached from orders — handleCompleteDelivery in driver-actions EF now owns the total_deliveries increment via increment_driver_stats RPC. Function retained for reference; safe to drop in a future migration if no longer referenced.';
