-- Migration 125: guard the JWT claims cast in prevent_driver_role_escalation (BUG-16)
--
-- THE BUG
--   The trigger reads the caller's role out of the request.jwt.claims GUC:
--
--       IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '')
--          != 'service_role'
--          AND current_setting('app.allow_driver_role_change', true) IS DISTINCT FROM 'true' THEN
--
--   UNSET is handled: current_setting returns NULL and COALESCE takes over.
--   An EMPTY STRING is not. It casts to NULL in the COALESCE fine, but the
--   cast itself raises first:
--
--       ERROR: invalid input syntax for type json
--       DETAIL: The input string ended unexpectedly.
--
--   An empty claims GUC is an ordinary state, not an exotic one: any session
--   that sets and then clears it lands there. In that state the guard cannot be
--   evaluated and the trigger errors instead of allowing or refusing.
--
-- THE FIX
--   NULLIF the empty string away, so the cast only ever sees real JSON or NULL.
--   This is the same guard place_order_with_items already uses for this GUC,
--   and its own source comment calls the missing NULLIF a pre-existing bug
--   dating to migration 080. This brings the trigger in line.
--
-- SCOPE
--   Only this trigger is changed. 22 public functions cast the same GUC
--   unguarded -- including admin_create_driver, cancel_order,
--   update_driver_location and place_order_with_items itself. They all share
--   the failure mode but each needs its own review; rewriting 22 functions in
--   one migration would make a regression impossible to attribute. The list is
--   reproduced at the bottom so the rest can be triaged on purpose.
--
-- DATA IMPACT
--   None. The guard refuses exactly the same promotions as before; it just no
--   longer errors when the GUC is empty.
--
-- Rollback: revert the NULLIF. Safe, but reintroduces the empty-GUC failure.

CREATE OR REPLACE FUNCTION public.prevent_driver_role_escalation() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
  IF NEW.role = 'driver' THEN
    IF COALESCE(NULLIF(current_setting('request.jwt.claims', true), '')::json->>'role', '') != 'service_role'
       AND current_setting('app.allow_driver_role_change', true) IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Role escalation blocked: users cannot set role to driver. Use admin-create-driver Edge Function instead.'
        USING HINT = 'Driver accounts must be created by admin via the admin-create-driver API. '
                     'Trusted migrations may set app.allow_driver_role_change=true to bypass.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;
-- Verification: functions still casting request.jwt.claims without NULLIF.
-- SELECT p.proname
--   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--  WHERE n.nspname = 'public'
--    AND p.prosrc LIKE '%current_setting(''request.jwt.claims'', true)::json%'
--  ORDER BY 1;
