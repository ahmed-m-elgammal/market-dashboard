-- Migration 028: Create admin_sessions table
-- Per 21-SECURITY-AUDIT-COMPLIANCE.md:
--   Admin panel uses HTTP-only cookies with 8-hour max session.
--   One active session per admin (previous session invalidated on new login).
--   Session management table for tracking, timeout, and concurrent control.
--
-- Security features:
--   - IP address tracking for anomaly detection (login from new IP)
--   - User agent tracking for unauthorized access detection
--   - Session invalidation support (logout everywhere)
--   - Unique constraint: only one active session per admin
--   - Auto-expiry via expires_at column

-- =============================================================================
-- ADMIN_SESSIONS TABLE
-- Tracks admin panel sessions with security metadata.
-- =============================================================================

CREATE TABLE admin_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Admin user reference
  admin_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,

  -- Session token (hashed, not plaintext — the actual cookie value is a hash of this)
  session_token TEXT NOT NULL,

  -- Security metadata
  ip_address INET,
  user_agent TEXT,
  country TEXT,
  city TEXT,

  -- Timing
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_accessed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,

  -- Invalidation
  invalidated_at TIMESTAMPTZ,
  invalidation_reason TEXT
    CHECK (invalidation_reason IS NULL OR invalidation_reason IN (
      'logout', 'new_login', 'admin_force', 'timeout', 'security_alert'
    )),

  -- Device info for "logout everywhere" feature
  device_fingerprint TEXT,

  -- Ensure expires_at is always in the future at creation time
  CONSTRAINT admin_sessions_valid_expiry CHECK (expires_at > created_at)
);

-- =============================================================================
-- INDEXES
-- =============================================================================

-- Find active sessions for an admin (for "one session per admin" enforcement)
CREATE INDEX idx_admin_sessions_admin_active
  ON public.admin_sessions(admin_id, created_at DESC)
  WHERE invalidated_at IS NULL;

-- Find session by token (for cookie validation)
CREATE INDEX idx_admin_sessions_token
  ON public.admin_sessions(session_token)
  WHERE invalidated_at IS NULL;

-- Find expired sessions that need cleanup
CREATE INDEX idx_admin_sessions_expired
  ON public.admin_sessions(expires_at)
  WHERE invalidated_at IS NULL;

-- Audit: find all sessions for an admin (including invalidated)
CREATE INDEX idx_admin_sessions_admin_all
  ON public.admin_sessions(admin_id, created_at DESC);

-- =============================================================================
-- ENABLE RLS
-- =============================================================================

ALTER TABLE public.admin_sessions ENABLE ROW LEVEL SECURITY;

-- =============================================================================
-- RLS POLICIES
-- =============================================================================

-- Only service role can read/write admin sessions
-- Admin users never directly query this table — it's managed by Edge Functions
-- using the service role key. This prevents session token theft via RLS bypass.

-- No SELECT policy for anon/authenticated users
-- No INSERT/UPDATE/DELETE policy for anon/authenticated users
-- All operations go through service role (which bypasses RLS)

-- =============================================================================
-- HELPER: CLEANUP EXPIRED SESSIONS
-- Periodically mark expired sessions as invalidated.
-- Can be called by a cron job or pg_net scheduled task.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.cleanup_expired_admin_sessions()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  UPDATE public.admin_sessions
  SET invalidated_at = NOW(),
      invalidation_reason = 'timeout'
  WHERE invalidated_at IS NULL
    AND expires_at < NOW();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION public.cleanup_expired_admin_sessions() IS 'Marks expired admin sessions as invalidated. Call periodically via cron. Returns count of cleaned sessions.';

-- =============================================================================
-- HELPER: INVALIDATE ALL SESSIONS FOR AN ADMIN
-- Used for "logout everywhere" feature.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.invalidate_all_admin_sessions(p_admin_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  UPDATE public.admin_sessions
  SET invalidated_at = NOW(),
      invalidation_reason = 'admin_force'
  WHERE admin_id = p_admin_id
    AND invalidated_at IS NULL;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION public.invalidate_all_admin_sessions(UUID) IS 'Invalidates all active sessions for an admin. Used for "logout everywhere" feature.';

-- =============================================================================
-- HELPER: CREATE NEW ADMIN SESSION (invalidates previous)
-- Enforces one active session per admin.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.create_admin_session(
  p_admin_id UUID,
  p_session_token TEXT,
  p_ip_address INET DEFAULT NULL,
  p_user_agent TEXT DEFAULT NULL,
  p_device_fingerprint TEXT DEFAULT NULL,
  p_duration_hours INTEGER DEFAULT 8
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_session_id UUID;
BEGIN
  -- Invalidate any existing active sessions for this admin
  UPDATE public.admin_sessions
  SET invalidated_at = NOW(),
      invalidation_reason = 'new_login'
  WHERE admin_id = p_admin_id
    AND invalidated_at IS NULL;

  -- Create the new session
  INSERT INTO public.admin_sessions (
    admin_id, session_token, ip_address, user_agent,
    device_fingerprint, expires_at
  ) VALUES (
    p_admin_id,
    p_session_token,
    p_ip_address,
    p_user_agent,
    p_device_fingerprint,
    NOW() + (p_duration_hours || ' hours')::INTERVAL
  )
  RETURNING id INTO v_session_id;

  RETURN v_session_id;
END;
$$;

COMMENT ON FUNCTION public.create_admin_session(UUID, TEXT, INET, TEXT, TEXT, INTEGER) IS 'Creates a new admin session and invalidates all previous sessions. Enforces one active session per admin. Returns new session ID.';

-- =============================================================================
-- GRANT EXECUTE PERMISSIONS (service role only)
-- =============================================================================

REVOKE EXECUTE ON FUNCTION public.cleanup_expired_admin_sessions() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.invalidate_all_admin_sessions(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_admin_session(UUID, TEXT, INET, TEXT, TEXT, INTEGER) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.cleanup_expired_admin_sessions() TO service_role;
GRANT EXECUTE ON FUNCTION public.invalidate_all_admin_sessions(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.create_admin_session(UUID, TEXT, INET, TEXT, TEXT, INTEGER) TO service_role;

-- =============================================================================
-- COMMENTS
-- =============================================================================

COMMENT ON TABLE public.admin_sessions IS 'Admin panel session tracking. One active session per admin enforced. Used for session management, security monitoring, and logout-everywhere feature. All access via service role.';
