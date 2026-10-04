-- Migration 105: refire rating aggregates on review visibility flips
--
-- Follow-up to 104 (hidden-by-default): the 018 rating triggers only
-- recalculate when merchant_id/driver_id or the rating value changes, so
-- approving (is_visible false→true) or hiding (true→false) a review left
-- stale stars. Caught live 2026-09-30 by the hidden-by-default proof:
-- approving a 1★ review kept merchants.rating at 0.0.
-- Bodies identical to 018 plus the visibility branch. Net data change: none.

CREATE OR REPLACE FUNCTION public.trigger_update_merchant_rating()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM public.update_merchant_rating(NEW.merchant_id);
  ELSIF TG_OP = 'UPDATE' THEN
    IF OLD.merchant_id IS DISTINCT FROM NEW.merchant_id THEN
      PERFORM public.update_merchant_rating(OLD.merchant_id);
      PERFORM public.update_merchant_rating(NEW.merchant_id);
    ELSIF OLD.merchant_rating IS DISTINCT FROM NEW.merchant_rating THEN
      PERFORM public.update_merchant_rating(NEW.merchant_id);
    ELSIF OLD.is_visible IS DISTINCT FROM NEW.is_visible THEN
      PERFORM public.update_merchant_rating(NEW.merchant_id);
    END IF;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE OR REPLACE FUNCTION public.trigger_update_driver_rating()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.driver_id IS NOT NULL AND NEW.driver_rating IS NOT NULL THEN
      PERFORM public.update_driver_rating(NEW.driver_id);
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    IF OLD.driver_id IS DISTINCT FROM NEW.driver_id THEN
      IF OLD.driver_id IS NOT NULL THEN
        PERFORM public.update_driver_rating(OLD.driver_id);
      END IF;
      IF NEW.driver_id IS NOT NULL THEN
        PERFORM public.update_driver_rating(NEW.driver_id);
      END IF;
    ELSIF OLD.driver_rating IS DISTINCT FROM NEW.driver_rating THEN
      IF NEW.driver_id IS NOT NULL THEN
        PERFORM public.update_driver_rating(NEW.driver_id);
      END IF;
    ELSIF (OLD.is_visible IS DISTINCT FROM NEW.is_visible)
          AND NEW.driver_id IS NOT NULL THEN
      PERFORM public.update_driver_rating(NEW.driver_id);
    END IF;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;
