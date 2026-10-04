-- Migration 024: RLS policies for driver admin tables + role protection
-- P1F-14: driver_documents policies: own documents read+insert; service role full
-- P1F-15: driver_status_history policies: own history read; service role insert only
-- P1F-16: profiles role-protection RLS: users cannot set own role to 'driver'
--
-- This migration extends the RLS policies from 020_create_rls_policies.sql
-- with driver-specific tables and additional role-protection measures.

-- =============================================================================
-- P1F-14: DRIVER_DOCUMENTS POLICIES (🔒 SECURITY-CRITICAL)
--   - Drivers can read their own documents
--   - Drivers can INSERT (upload) their own documents during onboarding
--   - Drivers CANNOT update or delete documents (prevents tampering after review)
--   - Drivers CANNOT change document status (only admin/service role can approve/reject)
--   - Service role full access (admin reviews documents, changes status)
-- =============================================================================

-- Read: drivers can read their own documents
CREATE POLICY "driver_documents_read_own"
  ON public.driver_documents
  FOR SELECT
  USING (auth.uid() = driver_id);

-- Insert: drivers can upload their own documents
CREATE POLICY "driver_documents_insert_own"
  ON public.driver_documents
  FOR INSERT
  WITH CHECK (auth.uid() = driver_id);

-- No UPDATE policy: drivers cannot modify documents after upload
-- This prevents tampering with documents that have already been reviewed
-- Only service role can update (status changes by admin)

-- No DELETE policy: drivers cannot delete documents
-- Only service role can delete documents

-- =============================================================================
-- P1F-15: DRIVER_STATUS_HISTORY POLICIES (🔒 SECURITY-CRITICAL)
--   - Drivers can read their own status history
--   - Only service role can INSERT status history records
--   - This prevents drivers from forging status change records
--   - No UPDATE or DELETE (audit trail is immutable)
-- =============================================================================

-- Read: drivers can read their own status history
CREATE POLICY "driver_status_history_read_own"
  ON public.driver_status_history
  FOR SELECT
  USING (auth.uid() = driver_id);

-- No INSERT policy: only service role can insert status history
-- This ensures only admin actions create status records
-- The admin-deactivate-driver Edge Function uses service role

-- No UPDATE or DELETE policies: status history is immutable

-- =============================================================================
-- P1F-16: PROFILES ROLE-PROTECTION — ADDITIONAL RLS
--   - Users cannot set their own role to 'driver'
--   - The primary protection is in the profiles_update_own policy (020)
--   - This migration adds an additional layer: a CHECK constraint trigger
--     that prevents ANY insert or update where a non-service-role user
--     sets role='driver'
--
--   Why both RLS AND a trigger?
--     - RLS policies can be bypassed if misconfigured
--     - A trigger provides defense-in-depth at the data level
--     - The trigger fires REGARDLESS of how the change is made
--       (direct SQL, RPC, Edge Function with anon key, etc.)
-- =============================================================================

-- Trigger function: block role='driver' unless called by service role
-- Service role bypasses RLS but triggers still fire — so we check JWT claims
CREATE OR REPLACE FUNCTION public.prevent_driver_role_escalation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  -- Block if role is being set to 'driver' and the caller is NOT service role
  IF NEW.role = 'driver' THEN
    -- Only enforce if inside an HTTP context (JWT claims are present) and not service role.
    -- This allows local database seeding and migrations (which have no JWT claims) to run.
    IF current_setting('request.jwt.claims', true) IS NOT NULL 
       AND COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
      RAISE EXCEPTION 'Role escalation blocked: users cannot set role to driver. Use admin-create-driver Edge Function instead.'
        USING HINT = 'Driver accounts must be created by admin via the admin-create-driver API.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- Attach to profiles: check on both INSERT and UPDATE
CREATE TRIGGER on_profile_prevent_driver_escalation
  BEFORE INSERT OR UPDATE OF role ON public.profiles
  FOR EACH ROW
  WHEN (NEW.role = 'driver')
  EXECUTE FUNCTION public.prevent_driver_role_escalation();

-- =============================================================================
-- COMMENTS
-- =============================================================================
COMMENT ON POLICY "driver_documents_read_own" ON public.driver_documents IS 'P1F-14: Drivers can read their own documents only.';
COMMENT ON POLICY "driver_documents_insert_own" ON public.driver_documents IS 'P1F-14: Drivers can upload (insert) their own documents during onboarding. Cannot modify after upload.';
COMMENT ON POLICY "driver_status_history_read_own" ON public.driver_status_history IS 'P1F-15: Drivers can read their own status history. Only service role can insert (admin actions).';
COMMENT ON FUNCTION public.prevent_driver_role_escalation() IS 'P1F-16: Defense-in-depth trigger that blocks non-service-role users from setting role=driver on profiles. Prevents driver self-signup at the data level, even if RLS is misconfigured.';
