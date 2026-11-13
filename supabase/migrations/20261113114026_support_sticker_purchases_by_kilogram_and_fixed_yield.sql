
-- Sticker purchases are recorded by kg. Inventory and production use fixed piece yields:
-- 500ml sticker: 1,900 pieces/kg; shared 1.5L/6L sticker: 1,200 pieces/kg.
-- Existing legacy generic sticker rows remain readable; new production consumes separate pools.
DO $migration$
DECLARE v_def text; v_old text; v_new text;
BEGIN
  v_def:=pg_get_functiondef('public.save_raw_material_purchase_atomic(jsonb,uuid,uuid)'::regprocedure);
  v_old:=$old$    WHEN 'sticker' THEN 'piece'
    ELSE NULL
  END;$old$;
  v_new:=$new$    WHEN 'sticker' THEN 'piece'
    WHEN 'sticker_500ml' THEN 'kg'
    WHEN 'sticker_1_5l_6l' THEN 'kg'
    ELSE NULL
  END;$new$;
  IF position(v_new in v_def)=0 THEN
    IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'Raw purchase unit mapping anchor missing'; END IF;
    v_def:=replace(v_def,v_old,v_new);
  END IF;
  v_old:=$old$     OR v_quantity <> trunc(v_quantity)
     OR v_amount IS NULL$old$;
  v_new:=$new$     OR (v_type NOT IN ('sticker_500ml','sticker_1_5l_6l') AND v_quantity <> trunc(v_quantity))
     OR (v_type IN ('sticker_500ml','sticker_1_5l_6l') AND v_quantity > 100000)
     OR v_amount IS NULL$new$;
  IF position(v_new in v_def)=0 THEN
    IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'Raw purchase integer quantity validation anchor missing'; END IF;
    v_def:=replace(v_def,v_old,v_new);
  END IF;
  EXECUTE v_def;

  v_def:=pg_get_functiondef('private.mpw_guard_production_packaging_stock()'::regprocedure);
  v_old:=$old$      ('sticker'::text,
        CASE NEW.product_type
          WHEN '500ml' THEN NEW.quantity*24
          WHEN '1.5L' THEN NEW.quantity*12
          WHEN '6L' THEN NEW.quantity
          ELSE 0
        END)$old$;
  v_new:=$new$      ('sticker_500ml'::text,
        CASE WHEN NEW.product_type='500ml' THEN NEW.quantity*24 ELSE 0 END),
      ('sticker_1_5l_6l'::text,
        CASE NEW.product_type WHEN '1.5L' THEN NEW.quantity*12 WHEN '6L' THEN NEW.quantity ELSE 0 END)$new$;
  IF position(v_new in v_def)=0 THEN
    IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'Packaging sticker requirement anchor missing'; END IF;
    v_def:=replace(v_def,v_old,v_new);
  END IF;
  v_old:=$old$    SELECT coalesce(sum(r.quantity),0)
      INTO v_available
    FROM public.raw_material_purchases r
    WHERE r.material_type=v_requirement.material_type
      AND r.purchase_date<=NEW.production_date
      AND (v_cutover_date IS NULL OR NEW.production_date < v_cutover_date
        OR r.record_type='opening_stock' OR r.purchase_date>=v_cutover_date);$old$;
  v_new:=$new$    SELECT coalesce(sum(r.quantity * CASE r.material_type
        WHEN 'sticker_500ml' THEN 1900::numeric
        WHEN 'sticker_1_5l_6l' THEN 1200::numeric
        ELSE 1::numeric END),0)
      INTO v_available
    FROM public.raw_material_purchases r
    WHERE r.material_type=v_requirement.material_type
      AND r.purchase_date<=NEW.production_date
      AND (v_cutover_date IS NULL OR NEW.production_date < v_cutover_date
        OR r.record_type='opening_stock' OR r.purchase_date>=v_cutover_date);$new$;
  IF position(v_new in v_def)=0 THEN
    IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'Packaging sticker stock quantity anchor missing'; END IF;
    v_def:=replace(v_def,v_old,v_new);
  END IF;
  v_old:=$old$        WHEN 'sticker' THEN
          CASE p.product_type
            WHEN '500ml' THEN p.quantity*24
            WHEN '1.5L' THEN p.quantity*12
            WHEN '6L' THEN p.quantity
            ELSE 0
          END$old$;
  v_new:=$new$        WHEN 'sticker_500ml' THEN CASE WHEN p.product_type='500ml' THEN p.quantity*24 ELSE 0 END
        WHEN 'sticker_1_5l_6l' THEN CASE p.product_type WHEN '1.5L' THEN p.quantity*12 WHEN '6L' THEN p.quantity ELSE 0 END$new$;
  IF position(v_new in v_def)=0 THEN
    IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'Packaging sticker consumption anchor missing'; END IF;
    v_def:=replace(v_def,v_old,v_new);
  END IF;
  EXECUTE v_def;

  v_def:=pg_get_functiondef('private.mpw_guard_raw_material_opening_stock()'::regprocedure);
  v_old:=$old$        OR NEW.material_type IN ('tape_bundle','sticker')$old$;
  v_new:=$new$        OR NEW.material_type IN ('tape_bundle','sticker','sticker_500ml','sticker_1_5l_6l')$new$;
  IF position(v_new in v_def)=0 THEN
    IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'Opening stock event material anchor missing'; END IF;
    v_def:=replace(v_def,v_old,v_new);
  END IF;
  v_old:=$old$    SELECT coalesce(sum(r.quantity),0)
      + CASE WHEN NEW.purchase_date<=v_event_date
          AND (v_cutover_date IS NULL
            OR (v_event_date<v_cutover_date AND NEW.record_type<>'opening_stock')
            OR (v_event_date>=v_cutover_date
              AND (NEW.record_type='opening_stock' OR NEW.purchase_date>=v_cutover_date)))
        THEN NEW.quantity ELSE 0 END
    INTO v_available$old$;
  v_new:=$new$    SELECT coalesce(sum(r.quantity * CASE r.material_type
        WHEN 'sticker_500ml' THEN 1900::numeric
        WHEN 'sticker_1_5l_6l' THEN 1200::numeric
        ELSE 1::numeric END),0)
      + CASE WHEN NEW.purchase_date<=v_event_date
          AND (v_cutover_date IS NULL
            OR (v_event_date<v_cutover_date AND NEW.record_type<>'opening_stock')
            OR (v_event_date>=v_cutover_date
              AND (NEW.record_type='opening_stock' OR NEW.purchase_date>=v_cutover_date)))
        THEN NEW.quantity * CASE NEW.material_type
          WHEN 'sticker_500ml' THEN 1900::numeric
          WHEN 'sticker_1_5l_6l' THEN 1200::numeric
          ELSE 1::numeric END ELSE 0 END
    INTO v_available$new$;
  IF position(v_new in v_def)=0 THEN
    IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'Opening stock available quantity anchor missing'; END IF;
    v_def:=replace(v_def,v_old,v_new);
  END IF;
  v_old:=$old$        WHEN 'sticker' THEN coalesce(sum(p.quantity*CASE p.product_type
          WHEN '500ml' THEN 24 WHEN '1.5L' THEN 12 ELSE 1 END),0)$old$;
  v_new:=$new$        WHEN 'sticker' THEN coalesce(sum(p.quantity*CASE p.product_type
          WHEN '500ml' THEN 24 WHEN '1.5L' THEN 12 ELSE 1 END),0)
        WHEN 'sticker_500ml' THEN coalesce(sum(p.quantity*24) FILTER(WHERE p.product_type='500ml'),0)
        WHEN 'sticker_1_5l_6l' THEN coalesce(sum(p.quantity*CASE p.product_type WHEN '1.5L' THEN 12 ELSE 1 END)
          FILTER(WHERE p.product_type IN ('1.5L','6L')),0)$new$;
  IF position(v_new in v_def)=0 THEN
    IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'Opening stock sticker consumption anchor missing'; END IF;
    v_def:=replace(v_def,v_old,v_new);
  END IF;
  v_old:=$old$          OR NEW.material_type IN ('tape_bundle','sticker')$old$;
  v_new:=$new$          OR NEW.material_type IN ('tape_bundle','sticker','sticker_500ml','sticker_1_5l_6l')$new$;
  IF position(v_new in v_def)=0 THEN
    IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'Opening stock sticker filter anchor missing'; END IF;
    v_def:=replace(v_def,v_old,v_new);
  END IF;
  EXECUTE v_def;

  v_def:=pg_get_functiondef('private.record_production_with_workers(date,text,integer,jsonb,uuid)'::regprocedure);
  v_old:=$old$  -- One sticker per bottle, carton contents are 24 / 12 units.
  SELECT coalesce(sum(quantity),0) INTO v_available
  FROM public.raw_material_purchases
  WHERE material_type='sticker' AND purchase_date<=p_production_date;
  SELECT coalesce(sum(quantity*CASE product_type WHEN '500ml' THEN 24 WHEN '1.5L' THEN 12 ELSE 1 END),0)
    INTO v_consumed
  FROM public.production WHERE production_date<=p_production_date;
  v_required:=p_quantity*CASE p_product_type WHEN '500ml' THEN 24 WHEN '1.5L' THEN 12 ELSE 1 END;
  IF v_available-v_consumed<v_required THEN
    RAISE EXCEPTION 'اسٹیکرز ناکافی ہیں۔ دستیاب: %، درکار: %',greatest(v_available-v_consumed,0),v_required USING ERRCODE='23514';
  END IF;$old$;
  v_new:=$new$  -- Separate sticker rolls: 500ml yield 1,900/kg; shared 1.5L/6L yield 1,200/kg.
  IF p_product_type='500ml' THEN
    SELECT coalesce(sum(quantity*1900),0) INTO v_available
    FROM public.raw_material_purchases WHERE material_type='sticker_500ml' AND purchase_date<=p_production_date;
    SELECT coalesce(sum(quantity*24),0) INTO v_consumed
    FROM public.production WHERE product_type='500ml' AND production_date<=p_production_date;
    v_required:=p_quantity*24;
  ELSE
    SELECT coalesce(sum(quantity*1200),0) INTO v_available
    FROM public.raw_material_purchases WHERE material_type='sticker_1_5l_6l' AND purchase_date<=p_production_date;
    SELECT coalesce(sum(quantity*CASE product_type WHEN '1.5L' THEN 12 ELSE 1 END),0) INTO v_consumed
    FROM public.production WHERE product_type IN ('1.5L','6L') AND production_date<=p_production_date;
    v_required:=p_quantity*CASE p_product_type WHEN '1.5L' THEN 12 ELSE 1 END;
  END IF;
  IF v_available-v_consumed<v_required THEN
    RAISE EXCEPTION 'متعلقہ اسٹیکرز ناکافی ہیں۔ دستیاب: %، درکار: %',greatest(v_available-v_consumed,0),v_required USING ERRCODE='23514';
  END IF;$new$;
  IF position(v_new in v_def)=0 THEN
    IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'Private production sticker validation anchor missing'; END IF;
    v_def:=replace(v_def,v_old,v_new);
  END IF;
  EXECUTE v_def;

  v_def:=pg_get_functiondef('public.build_business_monthly_report(date,date)'::regprocedure);
  v_old:=$old$  v_carton500 numeric; v_carton15 numeric; v_tape numeric; v_cap19_cutover date; v_sticker numeric;$old$;
  v_new:=$new$  v_carton500 numeric; v_carton15 numeric; v_tape numeric; v_cap19_cutover date; v_sticker numeric;
  v_sticker500 numeric; v_sticker_shared numeric;$new$;
  IF position(v_new in v_def)=0 THEN
    IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'Monthly report sticker variable anchor missing'; END IF;
    v_def:=replace(v_def,v_old,v_new);
  END IF;
  v_old:=$old$  select sum(total_amount)/nullif(sum(quantity),0) into v_sticker
  from public.raw_material_purchases where material_type='sticker' and purchase_date<=p_month_end;$old$;
  v_new:=$new$  select sum(total_amount)/nullif(sum(quantity),0) into v_sticker
  from public.raw_material_purchases where material_type='sticker' and purchase_date<=p_month_end;
  select sum(total_amount)/nullif(sum(quantity*1900),0) into v_sticker500
  from public.raw_material_purchases where material_type='sticker_500ml' and purchase_date<=p_month_end;
  select sum(total_amount)/nullif(sum(quantity*1200),0) into v_sticker_shared
  from public.raw_material_purchases where material_type='sticker_1_5l_6l' and purchase_date<=p_month_end;
  v_sticker500:=coalesce(v_sticker500,v_sticker);
  v_sticker_shared:=coalesce(v_sticker_shared,v_sticker);$new$;
  IF position(v_new in v_def)=0 THEN
    IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'Monthly report sticker cost query anchor missing'; END IF;
    v_def:=replace(v_def,v_old,v_new);
  END IF;
  v_old:=$old$  if v_bottle500 is not null and v_cap500 is not null and v_carton500 is not null and v_tape is not null and v_sticker is not null then
    v_cost500:=v_bottle500*24+v_cap500*24+v_carton500+v_tape/200+24*v_sticker;
  end if;
  if v_bottle15 is not null and v_cap15 is not null and v_carton15 is not null and v_tape is not null and v_sticker is not null then
    v_cost15:=v_bottle15*12+v_cap15*12+v_carton15+v_tape/200+12*v_sticker;
  end if;
  if v_bottle6 is not null and v_cap6 is not null and v_sticker is not null then v_cost6:=v_bottle6+v_cap6+v_sticker; end if;$old$;
  v_new:=$new$  if v_bottle500 is not null and v_cap500 is not null and v_carton500 is not null and v_tape is not null and v_sticker500 is not null then
    v_cost500:=v_bottle500*24+v_cap500*24+v_carton500+v_tape/200+24*v_sticker500;
  end if;
  if v_bottle15 is not null and v_cap15 is not null and v_carton15 is not null and v_tape is not null and v_sticker_shared is not null then
    v_cost15:=v_bottle15*12+v_cap15*12+v_carton15+v_tape/200+12*v_sticker_shared;
  end if;
  if v_bottle6 is not null and v_cap6 is not null and v_sticker_shared is not null then v_cost6:=v_bottle6+v_cap6+v_sticker_shared; end if;$new$;
  IF position(v_new in v_def)=0 THEN
    IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'Monthly report sticker product cost anchor missing'; END IF;
    v_def:=replace(v_def,v_old,v_new);
  END IF;
  v_old:=$old$    'stickers',coalesce((select sum(quantity) from public.raw_material_purchases where material_type='sticker' and purchase_date<=p_month_end),0)
      -(coalesce((select sum(quantity) from public.production where product_type='500ml' and production_date<=p_month_end),0)*24
        +coalesce((select sum(quantity) from public.production where product_type='1.5L' and production_date<=p_month_end),0)*12
        +coalesce((select sum(quantity) from public.production where product_type='6L' and production_date<=p_month_end),0)),$old$;
  v_new:=$new$    'stickers',coalesce((select sum(quantity) from public.raw_material_purchases where material_type='sticker' and purchase_date<=p_month_end),0)
      -(coalesce((select sum(quantity) from public.production where product_type='500ml' and production_date<=p_month_end),0)*24
        +coalesce((select sum(quantity) from public.production where product_type='1.5L' and production_date<=p_month_end),0)*12
        +coalesce((select sum(quantity) from public.production where product_type='6L' and production_date<=p_month_end),0)),
    'stickers_500ml',coalesce((select sum(quantity*1900) from public.raw_material_purchases where material_type='sticker_500ml' and purchase_date<=p_month_end),0)
      -coalesce((select sum(quantity*24) from public.production where product_type='500ml' and production_date<=p_month_end),0),
    'stickers_1_5l_6l',coalesce((select sum(quantity*1200) from public.raw_material_purchases where material_type='sticker_1_5l_6l' and purchase_date<=p_month_end),0)
      -coalesce((select sum(quantity*CASE product_type WHEN '1.5L' THEN 12 ELSE 1 END) from public.production where product_type IN ('1.5L','6L') and production_date<=p_month_end),0),$new$;
  IF position(v_new in v_def)=0 THEN
    IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'Monthly report sticker stock anchor missing'; END IF;
    v_def:=replace(v_def,v_old,v_new);
  END IF;
  EXECUTE v_def;
END;
$migration$;
