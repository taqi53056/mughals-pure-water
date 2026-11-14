-- Keep the privileged implementation outside the exposed public API schema.
CREATE OR REPLACE FUNCTION private.mark_customer_notification_read(p_notification_id bigint)
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

REVOKE ALL ON FUNCTION private.mark_customer_notification_read(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.mark_customer_notification_read(bigint) TO authenticated;

-- The public RPC is SECURITY INVOKER and delegates to the private,
-- ownership-checking SECURITY DEFINER implementation.
CREATE OR REPLACE FUNCTION public.mark_customer_notification_read(p_notification_id bigint)
RETURNS void
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $function$
  SELECT private.mark_customer_notification_read(p_notification_id);
$function$;

REVOKE ALL ON FUNCTION public.mark_customer_notification_read(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_customer_notification_read(bigint) TO authenticated;
