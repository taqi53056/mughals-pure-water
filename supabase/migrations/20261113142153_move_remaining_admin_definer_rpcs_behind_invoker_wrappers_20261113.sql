DO $$
DECLARE v_name text; v_oid oid; v_def text;
BEGIN
  FOREACH v_name IN ARRAY ARRAY['record_unassigned_19l_collection','record_unassigned_19l_delivery','save_raw_material_purchase_atomic'] LOOP
    SELECT p.oid INTO v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname=v_name;
    IF v_oid IS NULL THEN RAISE EXCEPTION 'Expected public function % was not found',v_name; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND p.proname=v_name) THEN
      v_def:=pg_get_functiondef(v_oid);
      v_def:=replace(v_def,'FUNCTION public.'||v_name||'(','FUNCTION private.'||v_name||'(');
      IF v_def=pg_get_functiondef(v_oid) THEN RAISE EXCEPTION 'Could not rewrite %',v_name; END IF;
      EXECUTE v_def;
    END IF;
  END LOOP;
END $$;

GRANT USAGE ON SCHEMA private TO authenticated;
REVOKE ALL ON FUNCTION private.record_unassigned_19l_collection(bigint,date,numeric,text,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.record_unassigned_19l_collection(bigint,date,numeric,text,uuid) TO authenticated;
REVOKE ALL ON FUNCTION private.record_unassigned_19l_delivery(date,bigint,integer,integer,text,uuid,integer,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.record_unassigned_19l_delivery(date,bigint,integer,integer,text,uuid,integer,boolean) TO authenticated;
REVOKE ALL ON FUNCTION private.save_raw_material_purchase_atomic(jsonb,uuid,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.save_raw_material_purchase_atomic(jsonb,uuid,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.record_production_with_workers(
 p_production_date date,p_product_type text,p_quantity integer,
 p_allocations jsonb DEFAULT '[]'::jsonb,p_request_id uuid DEFAULT NULL::uuid
) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path TO ''
AS $function$ SELECT private.record_production_with_workers($1,$2,$3,$4,$5); $function$;

CREATE OR REPLACE FUNCTION public.record_unassigned_19l_collection(
 p_delivery_id bigint,p_received_date date,p_amount numeric,p_payment_method text,p_request_id uuid
) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path TO ''
AS $function$ SELECT private.record_unassigned_19l_collection($1,$2,$3,$4,$5); $function$;

CREATE OR REPLACE FUNCTION public.record_unassigned_19l_delivery(
 p_delivery_date date,p_worker_id bigint,p_bottles_delivered integer,
 p_empty_bottles_returned integer DEFAULT 0,p_details text DEFAULT NULL::text,
 p_request_id uuid DEFAULT NULL::uuid,p_damaged_caps integer DEFAULT 0,
 p_performed_by_owner boolean DEFAULT false
) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path TO ''
AS $function$ SELECT private.record_unassigned_19l_delivery($1,$2,$3,$4,$5,$6,$7,$8); $function$;

CREATE OR REPLACE FUNCTION public.save_raw_material_purchase_atomic(
 p_purchase jsonb,p_request_id uuid DEFAULT NULL::uuid,p_cap_request_id uuid DEFAULT NULL::uuid
) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path TO ''
AS $function$ SELECT private.save_raw_material_purchase_atomic($1,$2,$3); $function$;

REVOKE ALL ON FUNCTION public.record_production_with_workers(date,text,integer,jsonb,uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.record_unassigned_19l_collection(bigint,date,numeric,text,uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.record_unassigned_19l_delivery(date,bigint,integer,integer,text,uuid,integer,boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.save_raw_material_purchase_atomic(jsonb,uuid,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_production_with_workers(date,text,integer,jsonb,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_unassigned_19l_collection(bigint,date,numeric,text,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_unassigned_19l_delivery(date,bigint,integer,integer,text,uuid,integer,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_raw_material_purchase_atomic(jsonb,uuid,uuid) TO authenticated;
