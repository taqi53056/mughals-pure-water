DO $$
DECLARE v_oid oid; v_def text; v_old text; v_new text;
BEGIN
 SELECT p.oid INTO v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='private' AND p.proname='mpw_guard_raw_material_opening_stock'
 AND pg_get_function_identity_arguments(p.oid)='';
 IF v_oid IS NULL THEN RAISE EXCEPTION 'Raw material opening-stock guard not found'; END IF;
 v_def:=pg_get_functiondef(v_oid);
 v_old:=$old$WHEN 'tape_bundle' THEN coalesce(sum(p.quantity),0)::numeric/200$old$;
 v_new:=$new$WHEN 'tape_bundle' THEN 0::numeric$new$;
 IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'Expected tape consumption rule not found; no change made'; END IF;
 v_def:=replace(v_def,v_old,v_new);
 EXECUTE v_def;
END $$;
