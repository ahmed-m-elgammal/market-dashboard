-- Migration 057: Add get_unique_audit_actions RPC function for loose index scan
-- Emulates a loose index scan on public.audit_logs(action) using a recursive CTE.
-- This is extremely fast and avoids downloading/scanning the whole high-volume table.

CREATE OR REPLACE FUNCTION public.get_unique_audit_actions()
RETURNS TABLE (action TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN QUERY
  WITH RECURSIVE t AS (
     (SELECT al.action FROM public.audit_logs al ORDER BY al.action LIMIT 1)
     UNION ALL
     SELECT (SELECT al.action FROM public.audit_logs al WHERE al.action > t.action ORDER BY al.action LIMIT 1)
     FROM t
     WHERE t.action IS NOT NULL
  )
  SELECT t.action FROM t WHERE t.action IS NOT NULL;
END;
$$;

COMMENT ON FUNCTION public.get_unique_audit_actions() IS 'Retrieve unique audit log action types efficiently via loose index scan emulation.';
