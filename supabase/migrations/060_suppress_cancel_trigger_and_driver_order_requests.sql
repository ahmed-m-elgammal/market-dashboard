-- Migration 060: Suppress duplicate order_status_history on cancel + create driver_order_requests
--
-- Two fixes from Session A gap analysis:
--
-- A2-G4: The on_order_status_change trigger (migration 018) fires AFTER UPDATE
--   OF status for ALL status transitions and inserts a generic row into
--   order_status_history with changed_by=NULL, note='Status changed from X
--   to Y'. The cancel_order RPC (migration 059) and admin_cancel_order RPC
--   (migration 056) ALSO explicitly insert a richer row (with changed_by,
--   changed_by_role, and a detailed note including refund/fee info). This
--   produces TWO history rows per cancel — the admin timeline UI renders
--   both, cluttering the audit trail.
--
--   Fix: modify the trigger's WHEN clause to skip transitions TO 'cancelled'.
--   The explicit inserts in the cancel RPCs own the cancelled-row history.
--   Non-cancel transitions (driver accept, assign, complete_delivery, admin
--   status overrides to non-cancelled statuses) still fire the trigger as
--   before — those paths don't have explicit history inserts (except the
--   admin status override route, which has a separate duplication issue not
--   in scope for this gap).
--
-- A4-G4: The workflow map (docs/workflow-map.md §1.5 line 256) references a
--   driver_order_requests table that didn't exist. No persistent audit trail
--   of which drivers were asked to take an order, who accepted/declined, or
--   response times. This migration creates the table; the driver-actions EF
--   is updated separately to populate it.

-- =============================================================================
-- A2-G4: Suppress trigger on cancel transitions
-- =============================================================================

DROP TRIGGER IF EXISTS on_order_status_change ON public.orders;

-- Recreate with an additional WHEN condition: skip transitions TO 'cancelled'.
-- The cancel_order RPC (migration 059) and admin_cancel_order RPC (migration
-- 056) explicitly insert a rich history row for cancels — the trigger's
-- generic row is redundant and clutters the admin timeline.
CREATE TRIGGER on_order_status_change
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status AND NEW.status <> 'cancelled')
  EXECUTE FUNCTION public.trigger_log_order_status_change();

COMMENT ON TRIGGER on_order_status_change ON public.orders IS
  'A2-G4 fix: logs status transitions into order_status_history, EXCEPT transitions to cancelled (cancel RPCs own those inserts with richer data).';

-- =============================================================================
-- A4-G4: Create driver_order_requests table
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.driver_order_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- The order this request is for
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,

  -- The driver being asked
  driver_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,

  -- Request lifecycle
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'accepted', 'declined', 'expired')),

  -- Timing
  sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  responded_at TIMESTAMPTZ,

  -- Optional reason for decline (free-text from driver)
  decline_reason TEXT,

  -- Record creation
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_driver_order_requests_order
  ON public.driver_order_requests(order_id);

CREATE INDEX IF NOT EXISTS idx_driver_order_requests_driver_status
  ON public.driver_order_requests(driver_id, status);

CREATE INDEX IF NOT EXISTS idx_driver_order_requests_status_sent_at
  ON public.driver_order_requests(status, sent_at)
  WHERE status = 'pending';

-- Enable RLS
ALTER TABLE public.driver_order_requests ENABLE ROW LEVEL SECURITY;

-- RLS: drivers can read their own requests; service role has full access.
-- No direct client INSERT/UPDATE — all writes go through the driver-actions
-- EF via the service-role client.
CREATE POLICY "driver_order_requests_read_own"
  ON public.driver_order_requests
  FOR SELECT
  USING (auth.uid() = driver_id);

COMMENT ON TABLE public.driver_order_requests IS
  'A4-G4: Persistent audit trail of driver assignment requests. Populated by the driver-actions Edge Function: handleAssignDriver inserts pending rows; handleDriverRespond updates to accepted/declined. No direct client writes — all via service role.';
