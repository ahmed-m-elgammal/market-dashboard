-- Migration 047: Add decline tracking and temporary lockout to drivers

ALTER TABLE public.drivers
  ADD COLUMN IF NOT EXISTS consecutive_declines INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS suspended_until TIMESTAMPTZ DEFAULT NULL;

-- Trigger to prevent going online if driver is suspended
CREATE OR REPLACE FUNCTION public.check_driver_suspension()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.is_online = TRUE AND (OLD.is_online = FALSE OR OLD.is_online = TRUE) THEN
    IF NEW.suspended_until IS NOT NULL AND NEW.suspended_until > NOW() THEN
      RAISE EXCEPTION 'Driver is temporarily suspended until %', NEW.suspended_until;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_check_driver_suspension ON public.drivers;
CREATE TRIGGER trg_check_driver_suspension
  BEFORE UPDATE OF is_online ON public.drivers
  FOR EACH ROW
  EXECUTE FUNCTION public.check_driver_suspension();
