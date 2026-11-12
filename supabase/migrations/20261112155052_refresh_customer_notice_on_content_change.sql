-- Keep changed customer notifications visibly unread for the customer.
-- Trigger-only function: no direct client execution is required.

CREATE OR REPLACE FUNCTION public.guard_customer_notification_update()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
BEGIN
  IF NEW.title IS DISTINCT FROM OLD.title
     OR NEW.message IS DISTINCT FROM OLD.message THEN
    NEW.is_read := false;
    NEW.created_at := now();
  END IF;

  IF session_user = 'postgres' THEN
    RETURN NEW;
  END IF;

  IF NOT (SELECT public.is_admin()) THEN
    IF (to_jsonb(NEW) - 'is_read') IS DISTINCT FROM (to_jsonb(OLD) - 'is_read') THEN
      RAISE EXCEPTION 'Customers may only mark their own notification as read';
    END IF;

    IF OLD.is_read IS TRUE AND NEW.is_read IS FALSE THEN
      RAISE EXCEPTION 'A read notification cannot be marked unread by a customer';
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.guard_customer_notification_update() FROM PUBLIC, anon, authenticated;
