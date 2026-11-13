DO $$
DECLARE
 v_oid oid;
 v_def text;
 v_old text;
 v_new text;
BEGIN
 SELECT p.oid INTO v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='private' AND p.proname='mpw_guard_production_packaging_stock'
 AND pg_get_function_identity_arguments(p.oid)='';
 IF v_oid IS NULL THEN RAISE EXCEPTION 'Production packaging stock guard not found'; END IF;
 v_def:=pg_get_functiondef(v_oid);
 v_old:=$old$('tape_bundle'::text,
        CASE WHEN NEW.product_type IN ('500ml','1.5L')
          THEN NEW.quantity/200::numeric ELSE 0 END),$old$;
 v_new:=$new$('tape_bundle'::text,0::numeric),$new$;
 IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'Expected tape requirement in packaging guard not found'; END IF;
 EXECUTE replace(v_def,v_old,v_new);

 SELECT p.oid INTO v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='private' AND p.proname='record_production_with_workers'
 AND pg_get_function_identity_arguments(p.oid)='p_production_date date, p_product_type text, p_quantity integer, p_allocations jsonb, p_request_id uuid';
 IF v_oid IS NULL THEN RAISE EXCEPTION 'Production RPC implementation not found'; END IF;
 v_def:=pg_get_functiondef(v_oid);
 v_old:=$old$-- Tape: one bundle per 200 cartons across 500ml and 1.5L.
  SELECT coalesce(sum(quantity),0) INTO v_available
  FROM public.raw_material_purchases
  WHERE material_type='tape_bundle' AND purchase_date<=p_production_date;
  SELECT coalesce(sum(quantity),0)::numeric/200 INTO v_consumed
  FROM public.production
  WHERE product_type IN ('500ml','1.5L') AND production_date<=p_production_date;
  v_required:=CASE WHEN p_product_type IN ('500ml','1.5L') THEN p_quantity::numeric/200 ELSE 0 END;
  IF v_available-v_consumed<v_required THEN
    RAISE EXCEPTION 'پیکنگ ٹیپ ناکافی ہے۔ دستیاب بنڈل: %، درکار: %',greatest(v_available-v_consumed,0),v_required USING ERRCODE='23514';
  END IF;

  $old$;
 v_new:=$new$-- ٹیپ کا استعمال الگ جسمانی گنتی/درست ریکارڈ کے بغیر خودکار طور پر منہا نہیں کیا جاتا.

  $new$;
 IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'Expected tape check in production RPC not found'; END IF;
 EXECUTE replace(v_def,v_old,v_new);

 SELECT p.oid INTO v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='build_business_monthly_report'
 AND pg_get_function_identity_arguments(p.oid)='p_month_start date, p_month_end date';
 IF v_oid IS NULL THEN RAISE EXCEPTION 'Monthly business report function not found'; END IF;
 v_def:=pg_get_functiondef(v_oid);
 v_old:=$old$if v_bottle500 is not null and v_cap500 is not null and v_carton500 is not null and v_tape is not null and v_sticker500 is not null then$old$;
 v_new:=$new$if v_bottle500 is not null and v_cap500 is not null and v_carton500 is not null and v_sticker500 is not null then$new$;
 IF position(v_old in v_def)=0 THEN RAISE EXCEPTION '500ml tape cost dependency not found'; END IF;
 v_def:=replace(v_def,v_old,v_new);
 v_old:=$old$v_cost500:=v_bottle500*24+v_cap500*24+v_carton500+v_tape/200+24*v_sticker500;$old$;
 v_new:=$new$v_cost500:=v_bottle500*24+v_cap500*24+v_carton500+24*v_sticker500;$new$;
 IF position(v_old in v_def)=0 THEN RAISE EXCEPTION '500ml tape cost formula not found'; END IF;
 v_def:=replace(v_def,v_old,v_new);
 v_old:=$old$if v_bottle15 is not null and v_cap15 is not null and v_carton15 is not null and v_tape is not null and v_sticker_shared is not null then$old$;
 v_new:=$new$if v_bottle15 is not null and v_cap15 is not null and v_carton15 is not null and v_sticker_shared is not null then$new$;
 IF position(v_old in v_def)=0 THEN RAISE EXCEPTION '1.5L tape cost dependency not found'; END IF;
 v_def:=replace(v_def,v_old,v_new);
 v_old:=$old$v_cost15:=v_bottle15*12+v_cap15*12+v_carton15+v_tape/200+12*v_sticker_shared;$old$;
 v_new:=$new$v_cost15:=v_bottle15*12+v_cap15*12+v_carton15+12*v_sticker_shared;$new$;
 IF position(v_old in v_def)=0 THEN RAISE EXCEPTION '1.5L tape cost formula not found'; END IF;
 v_def:=replace(v_def,v_old,v_new);
 EXECUTE v_def;
END $$;
