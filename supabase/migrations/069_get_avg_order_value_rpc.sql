-- Migration 069: get_avg_order_value RPC
--
-- P2-8 (MARKETING-IMPROVEMENT-PLAN.md Task 2.7):
-- The create-promo dialog needs the average order value to compute a
-- worst-case liability preview (max_discount * max_usage). This RPC
-- returns AVG(total) for non-cancelled orders, scoped to the last 30 days
-- so the preview reflects recent ordering behavior rather than all-time.

CREATE OR REPLACE FUNCTION public.get_avg_order_value()
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_avg NUMERIC;
BEGIN
  SELECT COALESCE(AVG(total), 0) INTO v_avg
  FROM public.orders
  WHERE status != 'cancelled'
    AND created_at > NOW() - INTERVAL '30 days';

  RETURN v_avg;
END;
$$;

COMMENT ON FUNCTION public.get_avg_order_value() IS
  'P2-8: Returns AVG(total) for non-cancelled orders in the last 30 days. Used by the create-promo dialog estimated-cost preview.';

REVOKE EXECUTE ON FUNCTION public.get_avg_order_value() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_avg_order_value() TO service_role;
