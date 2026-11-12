-- Remove device push registrations as soon as a customer is deactivated.
-- Prevents notifications for an inactive account from remaining linked to a shared device.

CREATE OR REPLACE FUNCTION private.mpw_remove_customer_push_on_deactivation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF OLD.is_active IS TRUE AND NEW.is_active IS FALSE THEN
    DELETE FROM public.customer_push_subscriptions
    WHERE customer_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE EXECUTE ON FUNCTION private.mpw_remove_customer_push_on_deactivation() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS mpw_remove_customer_push_on_deactivation ON public.customers;
CREATE TRIGGER mpw_remove_customer_push_on_deactivation
AFTER UPDATE OF is_active ON public.customers
FOR EACH ROW
WHEN (OLD.is_active IS TRUE AND NEW.is_active IS FALSE)
EXECUTE FUNCTION private.mpw_remove_customer_push_on_deactivation();
