-- Permit trusted PostgreSQL-owned scheduled jobs to refresh system-managed
-- notification content. API customers remain restricted to is_read-only changes.
CREATE OR REPLACE FUNCTION public.guard_customer_notification_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO ''
AS $function$
BEGIN
  -- pg_cron executes these jobs with session_user = postgres. SECURITY DEFINER
  -- changes current_user, not session_user, so this identifies the trusted
  -- database-owned session without trusting a caller-controlled JWT claim.
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
