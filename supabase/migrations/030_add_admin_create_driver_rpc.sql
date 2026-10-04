-- Migration 030: Add admin_create_driver atomic RPC
-- Per RED-29 in 13-PERFORMANCE-RED-FLAGS.md:
--   admin-create-driver creates 3 things: auth.users entry, profiles.role update,
--   and drivers row insert. If auth user is created but driver row insert fails,
--   you have an orphaned auth user with role='customer' that's not a driver.
--
-- Fix: Single DB function for atomic driver creation AFTER auth user exists.
-- This function is called by the admin-create-driver Edge Function AFTER
-- creating the auth user. It atomically updates the profile role and creates
-- the driver row in a single transaction.
--
-- Security: SECURITY DEFINER with explicit service_role check.

-- =============================================================================
-- ATOMIC DRIVER CREATION FUNCTION
-- Called AFTER auth.users entry is created by the Edge Function.
-- Atomically: (1) updates profile role to 'driver', (2) creates driver row,
-- (3) logs status history, (4) records admin action in data_access_log.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.admin_create_driver(
  p_admin_id UUID,
  p_user_id UUID,
  p_national_id TEXT,
  p_vehicle_type TEXT,
  p_vehicle_plate TEXT,
  p_phone TEXT DEFAULT NULL,
  p_vehicle_color TEXT DEFAULT NULL,
  p_vehicle_model TEXT DEFAULT NULL
)
RETURNS TABLE (
  driver_id UUID,
  profile_role TEXT,
  verification_status TEXT,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_current_role TEXT;
  v_driver_id UUID;
  v_verification_status TEXT := 'pending';
  v_created_at TIMESTAMPTZ;
BEGIN
  -- =====================================================================
  -- SECURITY CHECK: Verify caller is service role
  -- =====================================================================
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: admin_create_driver can only be called by service role.'
      USING HINT = 'Use the admin-create-driver Edge Function.';
  END IF;

  -- =====================================================================
  -- VALIDATION: Verify the user exists in auth.users
  -- =====================================================================
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User not found in auth.users. Create the auth user first.'
      USING HINT = 'The admin-create-driver Edge Function should create the auth user before calling this function.';
  END IF;

  -- =====================================================================
  -- VALIDATION: Check user isn't already a driver
  -- =====================================================================
  SELECT role INTO v_current_role FROM public.profiles WHERE id = p_user_id;
  IF v_current_role = 'driver' THEN
    RAISE EXCEPTION 'User is already a driver.';
  END IF;
  IF v_current_role = 'admin' THEN
    RAISE EXCEPTION 'Cannot convert an admin to a driver.';
  END IF;

  -- =====================================================================
  -- VALIDATION: Check national_id uniqueness
  -- =====================================================================
  IF EXISTS (SELECT 1 FROM public.drivers WHERE national_id = p_national_id) THEN
    RAISE EXCEPTION 'A driver with this national ID already exists.';
  END IF;

  -- =====================================================================
  -- VALIDATION: Check vehicle_plate uniqueness
  -- =====================================================================
  IF EXISTS (SELECT 1 FROM public.drivers WHERE vehicle_plate = p_vehicle_plate) THEN
    RAISE EXCEPTION 'A driver with this vehicle plate already exists.';
  END IF;

  -- =====================================================================
  -- ATOMIC OPERATION: Update profile + create driver in one transaction
  -- =====================================================================

  -- Step 1: Update profile role to 'driver'
  -- The prevent_driver_role_escalation trigger (from migration 024) will
  -- NOT block this because we're running as SECURITY DEFINER with service_role
  UPDATE public.profiles
  SET role = 'driver',
      phone = COALESCE(p_phone, phone)
  WHERE id = p_user_id;

  -- Step 2: Create driver row
  INSERT INTO public.drivers (
    id, national_id, vehicle_type, vehicle_plate,
    vehicle_color, vehicle_model, verification_status,
    is_verified, is_active, is_online
  ) VALUES (
    p_user_id,
    p_national_id,
    p_vehicle_type,
    p_vehicle_plate,
    p_vehicle_color,
    p_vehicle_model,
    v_verification_status,
    FALSE,  -- is_verified: admin must verify later
    TRUE,   -- is_active
    FALSE   -- is_online
  )
  RETURNING id, verification_status, created_at
  INTO v_driver_id, v_verification_status, v_created_at;

  -- Step 3: Log the driver status creation in driver_status_history
  INSERT INTO public.driver_status_history (
    driver_id, previous_status, new_status, changed_by, reason
  ) VALUES (
    v_driver_id,
    'none',
    'pending',
    p_admin_id,
    'Driver account created by admin'
  );

  -- Step 4: Log admin action in data_access_log
  INSERT INTO public.data_access_log (
    admin_id, action, resource_type, resource_id,
    field_name, reason
  ) VALUES (
    p_admin_id,
    'create',
    'driver',
    v_driver_id,
    'driver_account',
    'Created driver account via admin panel'
  );

  -- =====================================================================
  -- RETURN RESULT
  -- =====================================================================
  RETURN QUERY SELECT
    v_driver_id AS driver_id,
    'driver' AS profile_role,
    v_verification_status,
    v_created_at;
END;
$$;

COMMENT ON FUNCTION public.admin_create_driver(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) IS 'Atomically creates a driver: updates profile role + creates driver row + logs status history + audit log. Must be called AFTER auth user creation. SECURITY DEFINER — service role only.';

-- =============================================================================
-- ATOMIC DRIVER VERIFICATION FUNCTION
-- Called by admin-review-driver Edge Function.
-- Atomically: (1) updates driver verification, (2) logs status history,
-- (3) creates notification, (4) records admin action.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.admin_review_driver(
  p_admin_id UUID,
  p_driver_id UUID,
  p_action TEXT,  -- 'approve' or 'reject'
  p_rejection_reason TEXT DEFAULT NULL
)
RETURNS TABLE (
  driver_id UUID,
  verification_status TEXT,
  is_verified BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_previous_status TEXT;
  v_new_status TEXT;
  v_is_verified BOOLEAN;
BEGIN
  -- Security check
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: admin_review_driver can only be called by service role.';
  END IF;

  -- Validate action
  IF p_action NOT IN ('approve', 'reject') THEN
    RAISE EXCEPTION 'Invalid action: must be approve or reject.';
  END IF;

  -- Get current status
  SELECT verification_status INTO v_previous_status
  FROM public.drivers WHERE id = p_driver_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Driver not found.';
  END IF;

  IF v_previous_status = 'approved' THEN
    RAISE EXCEPTION 'Driver is already approved.';
  END IF;

  -- Determine new status
  IF p_action = 'approve' THEN
    v_new_status := 'approved';
    v_is_verified := TRUE;
  ELSE
    v_new_status := 'rejected';
    v_is_verified := FALSE;
  END IF;

  -- Atomic update
  UPDATE public.drivers
  SET verification_status = v_new_status,
      is_verified = v_is_verified,
      rejection_reason = CASE WHEN p_action = 'reject' THEN p_rejection_reason ELSE NULL END,
      verified_at = CASE WHEN p_action = 'approve' THEN NOW() ELSE verified_at END
  WHERE id = p_driver_id;

  -- Log status change
  INSERT INTO public.driver_status_history (
    driver_id, previous_status, new_status, changed_by, reason
  ) VALUES (
    p_driver_id,
    v_previous_status,
    v_new_status,
    p_admin_id,
    CASE WHEN p_action = 'reject' THEN COALESCE(p_rejection_reason, 'Rejected by admin')
         ELSE 'Approved by admin' END
  );

  -- Create notification for the driver
  INSERT INTO public.notifications (
    user_id, type, title_ar, title_en, body_ar, body_en, data
  ) VALUES (
    p_driver_id,
    CASE WHEN p_action = 'approve' THEN 'driver_verified' ELSE 'driver_rejected' END,
    CASE WHEN p_action = 'approve' THEN 'تم التحقق من حسابك' ELSE 'تم رفض التحقق' END,
    CASE WHEN p_action = 'approve' THEN 'Account Verified' ELSE 'Verification Rejected' END,
    CASE WHEN p_action = 'approve' THEN 'تم التحقق من حسابك بنجاح! يمكنك الآن بدء العمل.'
         ELSE 'تم رفض التحقق من حسابك. السبب: ' || COALESCE(p_rejection_reason, 'غير محدد') END,
    CASE WHEN p_action = 'approve' THEN 'Your account has been verified! You can now start working.'
         ELSE 'Your account verification was rejected. Reason: ' || COALESCE(p_rejection_reason, 'Not specified') END,
    jsonb_build_object('driver_id', p_driver_id, 'action', p_action)
  );

  -- Log admin action
  INSERT INTO public.data_access_log (
    admin_id, action, resource_type, resource_id, field_name, reason
  ) VALUES (
    p_admin_id,
    'modify',
    'driver',
    p_driver_id,
    'verification_status',
    CASE WHEN p_action = 'approve' THEN 'Approved driver verification'
         ELSE 'Rejected driver verification: ' || COALESCE(p_rejection_reason, '') END
  );

  RETURN QUERY SELECT p_driver_id, v_new_status, v_is_verified;
END;
$$;

COMMENT ON FUNCTION public.admin_review_driver(UUID, UUID, TEXT, TEXT) IS 'Atomically reviews a driver: updates verification + logs + notifies + audits. SECURITY DEFINER — service role only.';

-- =============================================================================
-- ATOMIC DRIVER DEACTIVATION FUNCTION
-- =============================================================================

CREATE OR REPLACE FUNCTION public.admin_deactivate_driver(
  p_admin_id UUID,
  p_driver_id UUID,
  p_reason TEXT
)
RETURNS TABLE (
  driver_id UUID,
  is_active BOOLEAN,
  deactivated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_was_active BOOLEAN;
  v_driver_id UUID;
  v_deactivated_at TIMESTAMPTZ;
BEGIN
  -- Security check
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: admin_deactivate_driver can only be called by service role.';
  END IF;

  -- Validate reason is provided
  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'Deactivation reason is required.';
  END IF;

  -- Check current state
  SELECT is_active INTO v_was_active FROM public.drivers WHERE id = p_driver_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Driver not found.';
  END IF;
  IF NOT v_was_active THEN
    RAISE EXCEPTION 'Driver is already deactivated.';
  END IF;

  -- Atomic deactivation
  UPDATE public.drivers
  SET is_active = FALSE,
      is_online = FALSE,
      deactivated_at = NOW()
  WHERE id = p_driver_id
  RETURNING id, is_active, deactivated_at
  INTO v_driver_id, v_was_active, v_deactivated_at;

  -- Log status change
  INSERT INTO public.driver_status_history (
    driver_id, previous_status, new_status, changed_by, reason
  ) VALUES (
    p_driver_id, 'active', 'deactivated', p_admin_id, p_reason
  );

  -- Notify driver
  INSERT INTO public.notifications (
    user_id, type, title_ar, title_en, body_ar, body_en, data
  ) VALUES (
    p_driver_id, 'driver_deactivated',
    'تم إلغاء تفعيل حسابك', 'Account Deactivated',
    'تم إلغاء تفعيل حسابك. السبب: ' || p_reason,
    'Your account has been deactivated. Reason: ' || p_reason,
    jsonb_build_object('driver_id', p_driver_id, 'reason', p_reason)
  );

  -- Log admin action
  INSERT INTO public.data_access_log (
    admin_id, action, resource_type, resource_id, field_name, reason
  ) VALUES (
    p_admin_id, 'modify', 'driver', p_driver_id,
    'is_active', 'Deactivated driver: ' || p_reason
  );

  RETURN QUERY SELECT p_driver_id, FALSE, NOW()::TIMESTAMPTZ;
END;
$$;

COMMENT ON FUNCTION public.admin_deactivate_driver(UUID, UUID, TEXT) IS 'Atomically deactivates a driver: updates status + logs + notifies + audits. Requires reason. SECURITY DEFINER — service role only.';

-- =============================================================================
-- GRANT EXECUTE PERMISSIONS (service role only)
-- =============================================================================

REVOKE EXECUTE ON FUNCTION public.admin_create_driver(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_review_driver(UUID, UUID, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_deactivate_driver(UUID, UUID, TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.admin_create_driver(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_review_driver(UUID, UUID, TEXT, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_deactivate_driver(UUID, UUID, TEXT) TO service_role;
