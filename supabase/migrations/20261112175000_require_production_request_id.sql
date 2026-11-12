-- The public production entry point must reject NULL request IDs.
-- The private implementation remains inaccessible to authenticated clients.
CREATE OR REPLACE FUNCTION public.record_production_with_workers(
  p_production_date date,
  p_product_type text,
  p_quantity integer,
  p_allocations jsonb DEFAULT '[]'::jsonb,
  p_request_id uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'صرف ایڈمن پروڈکشن درج کر سکتا ہے۔' USING ERRCODE='42501';
  END IF;
  IF p_request_id IS NULL THEN
    RAISE EXCEPTION 'پروڈکشن کی درخواست کی شناخت لازمی ہے۔' USING ERRCODE='22023';
  END IF;
  RETURN private.record_production_with_workers(
    p_production_date,p_product_type,p_quantity,p_allocations,p_request_id
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.record_production_with_workers(date,text,integer,jsonb,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_production_with_workers(date,text,integer,jsonb,uuid) TO authenticated;
