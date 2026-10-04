-- Migration 029: Create data_access_log table
-- Per 21-SECURITY-AUDIT-COMPLIANCE.md:
--   "When an admin clicks Show on a masked field, the action is logged"
--   Required for Egyptian Data Protection Law (DPL) compliance.
--   Tracks all admin access to PII (Personally Identifiable Information).
--
-- Use cases:
--   - Admin views a customer's phone number → logged
--   - Admin reveals a driver's national ID → logged with reason
--   - Admin exports customer data → logged
--   - Admin modifies sensitive data → logged
--   - Detect anomalous access patterns (> 100 records/hour)

-- =============================================================================
-- DATA_ACCESS_LOG TABLE
-- Immutable audit trail for all admin PII access.
-- =============================================================================

CREATE TABLE data_access_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Who accessed the data
  admin_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,

  -- What action was performed
  action TEXT NOT NULL CHECK (action IN (
    'view',         -- Viewed PII in admin panel
    'reveal',       -- Clicked "Show" on masked field
    'export',       -- Exported data (CSV, JSON)
    'modify',       -- Modified sensitive data
    'delete',       -- Deleted data (customer account, etc.)
    'create',       -- Created a record with PII
    'login',        -- Admin login event
    'logout',       -- Admin logout event
    'search'        -- Admin searched PII data
  )),

  -- What resource was accessed
  resource_type TEXT NOT NULL CHECK (resource_type IN (
    'customer', 'driver', 'order', 'payment',
    'merchant', 'promo', 'config', 'session', 'other'
  )),
  resource_id UUID NOT NULL,

  -- Which specific field was accessed (nullable for non-field-specific actions)
  field_name TEXT,
  -- Examples: 'national_id', 'phone', 'address', 'wallet_balance', 'email'

  -- Admin-provided reason for accessing sensitive data (required for 'reveal' actions)
  reason TEXT,

  -- Request context
  ip_address INET,
  user_agent TEXT,
  request_id TEXT,

  -- Whether the access was flagged as anomalous
  is_flagged BOOLEAN NOT NULL DEFAULT FALSE,
  flag_reason TEXT,

  -- Timestamp (immutable — no updates allowed)
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- INDEXES
-- =============================================================================

-- Find all access by an admin (audit trail for a specific admin)
CREATE INDEX idx_data_access_log_admin
  ON public.data_access_log(admin_id, created_at DESC);

-- Find all access to a specific resource (e.g., who viewed driver X)
CREATE INDEX idx_data_access_log_resource
  ON public.data_access_log(resource_type, resource_id, created_at DESC);

-- Find access to specific fields (e.g., who viewed national IDs)
CREATE INDEX idx_data_access_log_field
  ON public.data_access_log(field_name, created_at DESC)
  WHERE field_name IN ('national_id', 'phone', 'address', 'wallet_balance', 'email');

-- Find flagged access (for security review)
CREATE INDEX idx_data_access_log_flagged
  ON public.data_access_log(created_at DESC)
  WHERE is_flagged = TRUE;

-- Find recent access by IP (for intrusion detection)
CREATE INDEX idx_data_access_log_ip
  ON public.data_access_log(ip_address, created_at DESC)
  WHERE ip_address IS NOT NULL;

-- =============================================================================
-- ENABLE RLS
-- =============================================================================

ALTER TABLE public.data_access_log ENABLE ROW LEVEL SECURITY;

-- =============================================================================
-- RLS POLICIES
-- No direct access for any role except service role.
-- Admin panel reads via Edge Functions using service role.
-- Data access log is immutable — no UPDATE or DELETE allowed.
-- =============================================================================

-- No SELECT/INSERT/UPDATE/DELETE policies for regular users
-- All access through service role (which bypasses RLS)

-- =============================================================================
-- HELPER: LOG DATA ACCESS
-- Called by Edge Functions to record PII access.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.log_data_access(
  p_admin_id UUID,
  p_action TEXT,
  p_resource_type TEXT,
  p_resource_id UUID,
  p_field_name TEXT DEFAULT NULL,
  p_reason TEXT DEFAULT NULL,
  p_ip_address INET DEFAULT NULL,
  p_user_agent TEXT DEFAULT NULL,
  p_request_id TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_log_id UUID;
  v_is_flagged BOOLEAN := FALSE;
  v_flag_reason TEXT;
  v_recent_count INTEGER;
BEGIN
  -- Anomaly detection: flag if admin accessed > 100 records in the last hour
  SELECT COUNT(*) INTO v_recent_count
  FROM public.data_access_log
  WHERE admin_id = p_admin_id
    AND action IN ('view', 'reveal', 'export')
    AND created_at > NOW() - INTERVAL '1 hour';

  IF v_recent_count > 100 THEN
    v_is_flagged := TRUE;
    v_flag_reason := 'High volume PII access: ' || v_recent_count || ' records in 1 hour';
  END IF;

  -- Log the access
  INSERT INTO public.data_access_log (
    admin_id, action, resource_type, resource_id,
    field_name, reason, ip_address, user_agent,
    request_id, is_flagged, flag_reason
  ) VALUES (
    p_admin_id, p_action, p_resource_type, p_resource_id,
    p_field_name, p_reason, p_ip_address, p_user_agent,
    p_request_id, v_is_flagged, v_flag_reason
  )
  RETURNING id INTO v_log_id;

  RETURN v_log_id;
END;
$$;

COMMENT ON FUNCTION public.log_data_access(UUID, TEXT, TEXT, UUID, TEXT, TEXT, INET, TEXT, TEXT) IS 'Records admin PII access with automatic anomaly detection. Flags admins accessing > 100 records/hour. Called by Edge Functions via service role.';

-- =============================================================================
-- HELPER: GET ADMIN ACCESS SUMMARY
-- Returns a summary of admin PII access for a time period.
-- Used by admin panel security dashboard.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_admin_access_summary(
  p_hours INTEGER DEFAULT 24
)
RETURNS TABLE (
  admin_id UUID,
  admin_name TEXT,
  total_accesses INTEGER,
  reveal_count INTEGER,
  export_count INTEGER,
  flagged_count INTEGER,
  last_access TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN QUERY
  SELECT
    dal.admin_id,
    p.full_name AS admin_name,
    COUNT(*)::INTEGER AS total_accesses,
    COUNT(*) FILTER (WHERE dal.action = 'reveal')::INTEGER AS reveal_count,
    COUNT(*) FILTER (WHERE dal.action = 'export')::INTEGER AS export_count,
    COUNT(*) FILTER (WHERE dal.is_flagged = TRUE)::INTEGER AS flagged_count,
    MAX(dal.created_at) AS last_access
  FROM public.data_access_log dal
  JOIN public.profiles p ON p.id = dal.admin_id
  WHERE dal.created_at > NOW() - (p_hours || ' hours')::INTERVAL
  GROUP BY dal.admin_id, p.full_name
  ORDER BY total_accesses DESC;
END;
$$;

COMMENT ON FUNCTION public.get_admin_access_summary(INTEGER) IS 'Returns PII access summary per admin for the last N hours. Used by security dashboard.';

-- =============================================================================
-- GRANT EXECUTE PERMISSIONS (service role only)
-- =============================================================================

REVOKE EXECUTE ON FUNCTION public.log_data_access(UUID, TEXT, TEXT, UUID, TEXT, TEXT, INET, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_admin_access_summary(INTEGER) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.log_data_access(UUID, TEXT, TEXT, UUID, TEXT, TEXT, INET, TEXT, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_admin_access_summary(INTEGER) TO service_role;

-- =============================================================================
-- COMMENTS
-- =============================================================================

COMMENT ON TABLE public.data_access_log IS 'Immutable audit trail for admin PII access. Required for Egyptian DPL compliance. No UPDATE/DELETE — records are permanent. Anomaly detection flags high-volume access.';
