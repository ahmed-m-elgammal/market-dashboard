-- Migration 103: merchant approval flow (edit merchants in place)
--
-- Reuses the merchants table — no new tables. Two columns, both safe for
-- existing rows (approval_status defaults to 'approved', so the 1 live
-- merchant and all history are unaffected; is_active stays the kill-switch).
--
-- Flow: pending → approved | rejected. New places enter as pending from the
-- dashboard (form initial); Ops reviews with a note. Suspended-via-abuse
-- continues to use is_active = false (unchanged semantics).
-- Net data change: none (DDL only).

ALTER TABLE public.merchants
  ADD COLUMN IF NOT EXISTS approval_status TEXT NOT NULL DEFAULT 'approved'
    CHECK (approval_status IN ('pending', 'approved', 'rejected')),
  ADD COLUMN IF NOT EXISTS approval_note TEXT;

COMMENT ON COLUMN public.merchants.approval_status IS
  'Onboarding review: pending=new place awaiting Ops, approved=live, rejected=refused with reason in approval_note. is_active remains the runtime kill-switch.';
