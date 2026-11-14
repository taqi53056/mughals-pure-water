BEGIN;

-- Customers may read only their own notifications, but cannot alter notification
-- content or metadata. Admin workflows retain full update access.
DROP POLICY IF EXISTS customer_notifications_update ON public.customer_notifications;

CREATE POLICY customer_notifications_update
ON public.customer_notifications
FOR UPDATE
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- Customer read acknowledgements are handled by an ownership-checked function.
CREATE OR REPLACE FUNCTION public.mark_customer_notification_read(p_notification_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'لاگ اِن ضروری ہے۔' USING ERRCODE = '42501';
  END IF;

  UPDATE public.customer_notifications AS n
     SET is_read = true
   WHERE n.id = p_notification_id
     AND EXISTS (
       SELECT 1
       FROM public.customers AS c
       WHERE c.id = n.customer_id
         AND c.auth_user_id = (SELECT auth.uid())
         AND c.is_active = true
     );
END;
$function$;

REVOKE ALL ON FUNCTION public.mark_customer_notification_read(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_customer_notification_read(bigint) TO authenticated;

COMMIT;
