-- Migration 065: Auto default address on delete
-- If a default address is deleted and the user has other addresses, set one of them as default.

CREATE OR REPLACE FUNCTION public.handle_after_address_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_new_default_id UUID;
BEGIN
  -- If the deleted address was the default one
  IF OLD.is_default THEN
    -- Find the most recently updated address for the same user
    SELECT id INTO v_new_default_id
    FROM public.addresses
    WHERE user_id = OLD.user_id
    ORDER BY updated_at DESC, created_at DESC
    LIMIT 1;

    -- If another address exists, set it as default
    IF v_new_default_id IS NOT NULL THEN
      UPDATE public.addresses
      SET is_default = TRUE
      WHERE id = v_new_default_id;
    END IF;
  END IF;
  RETURN OLD;
END;
$$;

-- Drop trigger if exists
DROP TRIGGER IF EXISTS on_address_deleted ON public.addresses;

-- Create AFTER DELETE trigger
CREATE TRIGGER on_address_deleted
  AFTER DELETE ON public.addresses
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_after_address_delete();

COMMENT ON FUNCTION public.handle_after_address_delete() IS 'Promotes another address to default when the current default address is deleted.';
