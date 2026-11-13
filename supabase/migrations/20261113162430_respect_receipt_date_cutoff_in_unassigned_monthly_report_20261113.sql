DO $$
DECLARE
 v_oid oid;
 v_def text;
 v_old text;
 v_new text;
BEGIN
 SELECT p.oid INTO v_oid
 FROM pg_proc p
 JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public'
   AND p.proname='build_business_monthly_report'
   AND pg_get_function_identity_arguments(p.oid)='p_month_start date, p_month_end date';
 IF v_oid IS NULL THEN
   RAISE EXCEPTION 'Monthly business report function not found';
 END IF;
 v_def:=pg_get_functiondef(v_oid);
 v_old:=$old$where d.delivery_date between p_month_start and p_month_end;$old$;
 v_new:=$new$where d.delivery_date between p_month_start and p_month_end
    and rc.received_date<=p_month_end;$new$;
 IF position(v_old in v_def)=0 THEN
   RAISE EXCEPTION 'Expected unassigned collection period filter not found; no change made';
 END IF;
 EXECUTE replace(v_def,v_old,v_new);
END $$;
