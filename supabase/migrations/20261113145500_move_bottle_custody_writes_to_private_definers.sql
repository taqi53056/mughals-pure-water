
-- Keep PostgREST-facing functions SECURITY INVOKER; privileged writes stay in private helpers.
DO $migration$
DECLARE v_def text;
BEGIN
 v_def:=pg_get_functiondef('public.record_customer_19l_bottle_return(bigint,date,integer,uuid,text)'::regprocedure);
 v_def:=replace(v_def,
   'CREATE OR REPLACE FUNCTION public.record_customer_19l_bottle_return(',
   'CREATE OR REPLACE FUNCTION private.record_customer_19l_bottle_return(');
 IF v_def=pg_get_functiondef('public.record_customer_19l_bottle_return(bigint,date,integer,uuid,text)'::regprocedure) THEN
   RAISE EXCEPTION 'Could not move bottle-return RPC into private schema';
 END IF;
 EXECUTE v_def;
END;
$migration$;

REVOKE ALL ON FUNCTION public.record_customer_19l_bottle_return(bigint,date,integer,uuid,text) FROM PUBLIC,anon,authenticated;
DROP FUNCTION public.record_customer_19l_bottle_return(bigint,date,integer,uuid,text);
GRANT EXECUTE ON FUNCTION private.record_customer_19l_bottle_return(bigint,date,integer,uuid,text) TO authenticated;

CREATE FUNCTION public.record_customer_19l_bottle_return(
 p_customer_id bigint,p_return_date date,p_quantity integer,p_request_id uuid,p_details text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
BEGIN
 RETURN private.record_customer_19l_bottle_return(p_customer_id,p_return_date,p_quantity,p_request_id,p_details);
END;
$function$;
GRANT EXECUTE ON FUNCTION public.record_customer_19l_bottle_return(bigint,date,integer,uuid,text) TO authenticated;

DO $migration$
DECLARE v_def text;
BEGIN
 v_def:=pg_get_functiondef('public.record_customer_bottle_deposit(bigint,date,text,integer,text,uuid,text,boolean,bigint)'::regprocedure);
 v_def:=replace(v_def,
   'CREATE OR REPLACE FUNCTION public.record_customer_bottle_deposit(',
   'CREATE OR REPLACE FUNCTION private.record_customer_bottle_deposit_v2(');
 IF v_def=pg_get_functiondef('public.record_customer_bottle_deposit(bigint,date,text,integer,text,uuid,text,boolean,bigint)'::regprocedure) THEN
   RAISE EXCEPTION 'Could not move bottle-deposit RPC into private schema';
 END IF;
 EXECUTE v_def;
END;
$migration$;

REVOKE ALL ON FUNCTION public.record_customer_bottle_deposit(bigint,date,text,integer,text,uuid,text,boolean,bigint) FROM PUBLIC,anon,authenticated;
DROP FUNCTION public.record_customer_bottle_deposit(bigint,date,text,integer,text,uuid,text,boolean,bigint);
GRANT EXECUTE ON FUNCTION private.record_customer_bottle_deposit_v2(bigint,date,text,integer,text,uuid,text,boolean,bigint) TO authenticated;

CREATE FUNCTION public.record_customer_bottle_deposit(
 p_customer_id bigint,p_transaction_date date,p_transaction_type text,p_quantity integer,
 p_payment_method text,p_request_id uuid,p_details text,p_bottle_return_confirmed boolean,
 p_bottle_return_id bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
BEGIN
 RETURN private.record_customer_bottle_deposit_v2(
  p_customer_id,p_transaction_date,p_transaction_type,p_quantity,p_payment_method,
  p_request_id,p_details,p_bottle_return_confirmed,p_bottle_return_id
 );
END;
$function$;
GRANT EXECUTE ON FUNCTION public.record_customer_bottle_deposit(bigint,date,text,integer,text,uuid,text,boolean,bigint) TO authenticated;
