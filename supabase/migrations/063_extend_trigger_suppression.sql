-- Migration 063: Extend trigger suppression for confirmed and delivered transitions
--
-- A4-G5: The on_order_status_change trigger (migration 018, modified by 060)
-- currently fires for all transitions EXCEPT transitions TO 'cancelled'.
-- The cancel_order RPC (migration 059) and admin_cancel_order RPC (migration
-- 056) explicitly insert a rich history row for cancels.
--
-- The same duplication issue exists for:
--   1. Transitions TO 'confirmed' from 'pending' — the driver-actions EF
--      (handleAssignDriver and handleDriverRespond accept path) now explicitly
--      inserts a history row with changed_by=driver.id, changed_by_role='system'.
--      The admin status override route also inserts an explicit row.
--   2. Transitions TO 'delivered' — the driver-actions EF (handleCompleteDelivery)
--      should own this transition's history. Currently the trigger fires with
--      changed_by=NULL.
--
-- Fix: extend the trigger's WHEN clause to also skip transitions TO 'confirmed'
-- and TO 'delivered'. The EFs that perform these transitions are now
-- responsible for inserting their own explicit history rows.
--
-- Transitions that STILL fire the trigger (no explicit insert from the app):
--   - pending → confirmed (admin status override) — admin route inserts explicit row
--   - confirmed → preparing (admin status override) — admin route inserts explicit row
--   - preparing → ready (admin status override) — admin route inserts explicit row
--   - ready → picked_up (driver mark_picked_up) — EF doesn't insert explicit row
--   - picked_up → on_the_way (driver mark_on_the_way) — EF doesn't insert explicit row
--
-- For the last two (mark_picked_up, mark_on_the_way), the trigger still fires
-- and sets changed_by=NULL. This is a known gap — the EFs don't currently
-- insert explicit history rows. A future migration/EF update could add them.
-- For now, the trigger provides a fallback audit trail (with NULL actor) for
-- these transitions.

DROP TRIGGER IF EXISTS on_order_status_change ON public.orders;

-- Recreate with extended WHEN clause: skip transitions TO 'cancelled',
-- 'confirmed', and 'delivered'. These transitions are owned by the EFs/RPCs
-- that perform them (cancel_order RPC, driver-actions EF, admin status route).
CREATE TRIGGER on_order_status_change
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW
  WHEN (
    OLD.status IS DISTINCT FROM NEW.status
    AND NEW.status NOT IN ('cancelled', 'confirmed', 'delivered')
  )
  EXECUTE FUNCTION public.trigger_log_order_status_change();

COMMENT ON TRIGGER on_order_status_change ON public.orders IS
  'A2-G4/A4-G5 fix: logs status transitions into order_status_history, EXCEPT transitions to cancelled (cancel RPCs own those), confirmed (driver-actions EF and admin route own those), and delivered (driver-actions EF owns those). Fallback audit trail for preparing/ready/picked_up/on_the_way transitions where the EF does not insert an explicit row.';
