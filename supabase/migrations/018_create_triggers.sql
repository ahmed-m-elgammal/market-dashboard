-- Migration 018: Create triggers
-- P1E-14: Auto-generate order_number trigger on orders INSERT
-- P1E-15: Auto-create profile trigger on auth.users INSERT (already exists in 002, documented here)
-- P1E-16: Update merchant rating trigger on reviews INSERT/UPDATE
-- P1E-17: Update driver rating trigger on reviews INSERT/UPDATE
-- P1E-18: Insert order_status_history on orders status change

-- =============================================================================
-- P1E-14: AUTO-GENERATE ORDER_NUMBER TRIGGER
-- When a new order is inserted, automatically generate the order_number
-- using the generate_order_number() function from 017_create_functions.sql.
--
-- This trigger fires BEFORE INSERT so the order_number is available
-- in the inserted row (and can be returned to the client).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.set_order_number()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- Only generate if not already set (allows manual override)
  IF NEW.order_number IS NULL THEN
    NEW.order_number := public.generate_order_number();
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_order_insert_set_number
  BEFORE INSERT ON orders
  FOR EACH ROW
  EXECUTE FUNCTION public.set_order_number();

COMMENT ON FUNCTION public.set_order_number() IS 'P1E-14: Auto-generates order_number on orders INSERT using generate_order_number(). Only sets if NULL (allows manual override).';

-- =============================================================================
-- P1E-15: AUTO-CREATE PROFILE TRIGGER ON AUTH.USERS INSERT
-- Already created in 002_create_profiles.sql (on_auth_user_created trigger).
-- This task is marked as dependent on P1A-05 which was completed earlier.
-- No additional work needed — documented here for build plan completeness.
-- =============================================================================

-- (Already exists: trigger on_auth_user_created calls handle_new_user())

-- =============================================================================
-- P1E-16: UPDATE MERCHANT RATING TRIGGER
-- When a review is inserted or updated, recalculate the merchant's
-- aggregate rating using update_merchant_rating() from 017_create_functions.sql.
--
-- This trigger fires AFTER INSERT OR UPDATE to ensure the review data
-- is committed before recalculating the aggregate.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.trigger_update_merchant_rating()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- On INSERT: update the merchant from the new review
  IF TG_OP = 'INSERT' THEN
    PERFORM public.update_merchant_rating(NEW.merchant_id);
  -- On UPDATE: update if merchant_id or merchant_rating changed
  ELSIF TG_OP = 'UPDATE' THEN
    -- If merchant_id changed, update both old and new merchants
    IF OLD.merchant_id IS DISTINCT FROM NEW.merchant_id THEN
      PERFORM public.update_merchant_rating(OLD.merchant_id);
      PERFORM public.update_merchant_rating(NEW.merchant_id);
    -- If only rating changed, update the same merchant
    ELSIF OLD.merchant_rating IS DISTINCT FROM NEW.merchant_rating THEN
      PERFORM public.update_merchant_rating(NEW.merchant_id);
    END IF;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER on_review_change_update_merchant_rating
  AFTER INSERT OR UPDATE ON reviews
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_update_merchant_rating();

COMMENT ON FUNCTION public.trigger_update_merchant_rating() IS 'P1E-16: Trigger function to recalculate merchant aggregate rating on reviews INSERT/UPDATE. Calls update_merchant_rating().';

-- =============================================================================
-- P1E-17: UPDATE DRIVER RATING TRIGGER
-- When a review is inserted or updated with a driver_rating, recalculate
-- the driver's aggregate rating using update_driver_rating().
--
-- Only fires when driver_id IS NOT NULL (driver rating is optional).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.trigger_update_driver_rating()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- On INSERT: update the driver if driver_rating is provided
  IF TG_OP = 'INSERT' THEN
    IF NEW.driver_id IS NOT NULL AND NEW.driver_rating IS NOT NULL THEN
      PERFORM public.update_driver_rating(NEW.driver_id);
    END IF;
  -- On UPDATE: update if driver_id or driver_rating changed
  ELSIF TG_OP = 'UPDATE' THEN
    -- If driver_id changed, update old driver (if had rating) and new driver
    IF OLD.driver_id IS DISTINCT FROM NEW.driver_id THEN
      IF OLD.driver_id IS NOT NULL THEN
        PERFORM public.update_driver_rating(OLD.driver_id);
      END IF;
      IF NEW.driver_id IS NOT NULL THEN
        PERFORM public.update_driver_rating(NEW.driver_id);
      END IF;
    -- If only driver_rating changed, update the same driver
    ELSIF OLD.driver_rating IS DISTINCT FROM NEW.driver_rating THEN
      IF NEW.driver_id IS NOT NULL THEN
        PERFORM public.update_driver_rating(NEW.driver_id);
      END IF;
    END IF;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER on_review_change_update_driver_rating
  AFTER INSERT OR UPDATE ON reviews
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_update_driver_rating();

COMMENT ON FUNCTION public.trigger_update_driver_rating() IS 'P1E-17: Trigger function to recalculate driver aggregate rating on reviews INSERT/UPDATE. Only fires when driver_id and driver_rating are non-NULL.';

-- =============================================================================
-- P1E-18: INSERT ORDER_STATUS_HISTORY ON STATUS CHANGE
-- When an order's status changes, automatically insert a row into
-- order_status_history to maintain the audit trail.
--
-- This trigger fires AFTER UPDATE so the order status change is committed
-- before logging it. It only fires when the status column actually changes.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.trigger_log_order_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- Only fire when status actually changes
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    INSERT INTO public.order_status_history (order_id, status, changed_by, changed_by_role, note)
    VALUES (
      NEW.id,
      NEW.status,
      NULL,  -- changed_by is set by the Edge Function; NULL here as fallback
      NULL,  -- changed_by_role is set by the Edge Function; NULL here as fallback
      'Status changed from ' || OLD.status || ' to ' || NEW.status
    );
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER on_order_status_change
  AFTER UPDATE OF status ON orders
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION public.trigger_log_order_status_change();

COMMENT ON FUNCTION public.trigger_log_order_status_change() IS 'P1E-18: Trigger function to insert order_status_history row on orders status change. Logs the transition with old and new status.';

-- =============================================================================
-- ADDITIONAL TRIGGER: INCREMENT DRIVER DELIVERIES COUNT
-- When an order status changes to 'delivered', increment the driver's
-- total_deliveries counter on the drivers table.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.trigger_increment_driver_deliveries()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status = 'delivered' AND OLD.status IS DISTINCT FROM NEW.status THEN
    IF NEW.driver_id IS NOT NULL THEN
      UPDATE public.drivers
      SET total_deliveries = total_deliveries + 1
      WHERE id = NEW.driver_id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER on_order_delivered_increment_driver_deliveries
  AFTER UPDATE OF status ON orders
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status AND NEW.status = 'delivered')
  EXECUTE FUNCTION public.trigger_increment_driver_deliveries();

COMMENT ON FUNCTION public.trigger_increment_driver_deliveries() IS 'Auto-increments driver total_deliveries when order status changes to delivered.';
