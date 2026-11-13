DO $$
DECLARE v_oid oid; v_def text; v_old text; v_new text;
BEGIN
 SELECT p.oid INTO v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='private' AND p.proname='mpw_guard_production_packaging_stock'
 AND pg_get_function_identity_arguments(p.oid)='';
 v_def:=pg_get_functiondef(v_oid);
 v_old:=$old$WHEN 'tape_bundle' THEN
          CASE WHEN p.product_type IN ('500ml','1.5L')
            THEN p.quantity/200::numeric ELSE 0 END$old$;
 v_new:=$new$WHEN 'tape_bundle' THEN 0::numeric$new$;
 IF v_oid IS NULL OR position(v_old in v_def)=0 THEN RAISE EXCEPTION 'Tape usage calculation in packaging guard not found'; END IF;
 EXECUTE replace(v_def,v_old,v_new);

 SELECT p.oid INTO v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='build_business_monthly_report'
 AND pg_get_function_identity_arguments(p.oid)='p_month_start date, p_month_end date';
 IF v_oid IS NULL THEN RAISE EXCEPTION 'Monthly report function not found'; END IF;
 v_def:=pg_get_functiondef(v_oid);
 v_old:=$old$'tape_bundles',coalesce((select sum(quantity) from public.raw_material_purchases where material_type='tape_bundle' and purchase_date<=p_month_end),0)
      -(coalesce((select sum(quantity) from public.production where product_type='500ml' and production_date<=p_month_end),0)::numeric
        +coalesce((select sum(quantity) from public.production where product_type='1.5L' and production_date<=p_month_end),0)::numeric)/200,$old$;
 v_new:=$new$'tape_bundles',null,
    'tape_bundles_recorded',coalesce((select sum(quantity) from public.raw_material_purchases where material_type='tape_bundle' and purchase_date<=p_month_end),0),$new$;
 IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'Tape stock balance calculation in monthly report not found'; END IF;
 EXECUTE replace(v_def,v_old,v_new);
END $$;
