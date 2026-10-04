-- Migration 039: Create audit_logs table
-- Per 21-SECURITY-AUDIT-COMPLIANCE.md and 20-MONITORING-OBSERVABILITY.md:
--   Permanent audit trail for all admin actions.
--   Immutable — no UPDATE or DELETE allowed.
--   Used for compliance, debugging, and security investigations.
--
-- Different from data_access_log which tracks PII access specifically.
-- This table tracks ALL admin actions (creates, updates, deletes, config changes, etc.)

-- =============================================================================
-- AUDIT_LOGS TABLE
-- Permanent, immutable audit trail for all admin panel actions.
-- =============================================================================

CREATE TABLE audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Who performed the action
  admin_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,

  -- What action was performed (e.g., 'driver.create', 'order.cancel', 'merchant.update')
  action TEXT NOT NULL,

  -- What resource was affected
  resource_type TEXT NOT NULL CHECK (resource_type IN (
    'driver', 'order', 'merchant', 'customer', 'promo',
    'ad', 'config', 'session', 'menu_item', 'category',
    'payment', 'notification', 'feature_flag', 'other'
  )),
  resource_id TEXT NOT NULL,  -- UUID of affected resource (TEXT to support non-UUID IDs)

  -- Snapshot of changes
  details JSONB,

  -- Request context
  ip_address INET,
  user_agent TEXT,

  -- Timestamp (immutable)
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- INDEXES
-- =============================================================================

-- Find all actions by an admin
CREATE INDEX idx_audit_logs_admin
  ON public.audit_logs(admin_id, created_at DESC);

-- Find all actions on a specific resource
CREATE INDEX idx_audit_logs_resource
  ON public.audit_logs(resource_type, resource_id);

-- Find all actions of a specific type
CREATE INDEX idx_audit_logs_action
  ON public.audit_logs(action, created_at DESC);

-- Find actions by date range (for compliance reports)
CREATE INDEX idx_audit_logs_created_at
  ON public.audit_logs(created_at DESC);

-- =============================================================================
-- ENABLE RLS
-- =============================================================================

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- No policies for regular users — service role only (bypasses RLS)
-- Admin panel reads audit logs via server-side service role client

-- =============================================================================
-- PREVENT MODIFICATION (Immutability)
-- =============================================================================

-- Prevent UPDATE on audit_logs
CREATE OR REPLACE FUNCTION public.prevent_audit_log_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'audit_logs rows cannot be updated — they are immutable';
  RETURN NULL;
END;
$$;

CREATE TRIGGER trg_prevent_audit_log_update
  BEFORE UPDATE ON public.audit_logs
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_audit_log_update();

-- Prevent DELETE on audit_logs
CREATE OR REPLACE FUNCTION public.prevent_audit_log_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'audit_logs rows cannot be deleted — they are permanent';
  RETURN NULL;
END;
$$;

CREATE TRIGGER trg_prevent_audit_log_delete
  BEFORE DELETE ON public.audit_logs
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_audit_log_delete();

-- =============================================================================
-- COMMENTS
-- =============================================================================

COMMENT ON TABLE public.audit_logs IS 'Permanent, immutable audit trail for all admin actions. No UPDATE or DELETE allowed. Used for compliance, debugging, and security investigations. Egyptian DPL compliance requires indefinite retention.';
COMMENT ON COLUMN public.audit_logs.action IS 'Action identifier: resource.verb format, e.g., driver.create, order.cancel, merchant.update, config.change';
COMMENT ON COLUMN public.audit_logs.details IS 'JSONB snapshot of the change: previous values, new values, reason, admin-provided justification';
