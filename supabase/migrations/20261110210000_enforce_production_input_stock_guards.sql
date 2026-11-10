-- Prevent production from exceeding raw-material and water opening/purchase balances.
-- Share the finished-stock advisory lock with product sales to prevent concurrent overselling.
CREATE OR REPLACE FUNCTION public.record_production_with_workers(
  p_production_date date,
  p_product_type text,
  p_quantity integer,
  p_allocations jsonb DEFAULT '[]'::jsonb,
  p_request_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
DECLARE
  v_production_id bigint;
  v_labor_amount numeric(12,2);
  v_worker_labor_total numeric(12,2):=0;
  v_owner_saved_labor numeric(12,2):=0;
  v_owner_cartons integer:=0;
  v_item jsonb;
  v_count integer:=0;
  v_sum bigint:=0;
  v_distinct_workers integer:=0;
  v_worker_id bigint;
  v_cartons integer;
  v_is_owner boolean;
  v_existing public.production%rowtype;
  v_available numeric:=0;
  v_consumed numeric:=0;
  v_required numeric:=0;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'صرف ایڈمن پروڈکشن درج کر سکتا ہے۔' USING ERRCODE='42501';
  END IF;
  IF p_production_date IS NULL OR p_quantity IS NULL OR p_quantity<=0 THEN
    RAISE EXCEPTION 'تاریخ اور مکمل مثبت مقدار درج کریں۔' USING ERRCODE='22023';
  END IF;
  IF p_product_type NOT IN ('500ml','1.5L','6L') THEN
    RAISE EXCEPTION 'پروڈکٹ کی قسم درست نہیں۔' USING ERRCODE='22023';
  END IF;
  IF jsonb_typeof(p_allocations) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'تقسیم فہرست کی صورت میں ہونی چاہیے۔' USING ERRCODE='22023';
  END IF;

  IF p_request_id IS NOT NULL THEN
    SELECT * INTO v_existing FROM public.production WHERE request_id=p_request_id;
    IF FOUND THEN
      SELECT
        coalesce(sum(a.cartons*10) FILTER(WHERE NOT coalesce(w.is_owner,false)),0),
        coalesce(sum(a.cartons*10) FILTER(WHERE coalesce(w.is_owner,false)),0),
        coalesce(sum(a.cartons) FILTER(WHERE coalesce(w.is_owner,false)),0),
        count(a.id)::integer
      INTO v_worker_labor_total,v_owner_saved_labor,v_owner_cartons,v_count
      FROM public.production_worker_allocations a
      LEFT JOIN public.workers w ON w.id=a.worker_id
      WHERE a.production_id=v_existing.id;
      RETURN jsonb_build_object(
        'production_id',v_existing.id,'product_type',v_existing.product_type,
        'quantity',v_existing.quantity,'labor_amount',coalesce(v_existing.labor_amount,0),
        'worker_labor_total',v_worker_labor_total,'owner_saved_labor',v_owner_saved_labor,
        'owner_cartons',v_owner_cartons,'worker_count',v_count,'already_recorded',true
      );
    END IF;
  END IF;

  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_allocations) e(value)
    WHERE jsonb_typeof(e.value)<>'object'
      OR NOT (e.value?'worker_id') OR NOT (e.value?'cartons')
      OR jsonb_typeof(e.value->'worker_id')<>'number'
      OR jsonb_typeof(e.value->'cartons')<>'number'
      OR (e.value->>'worker_id') !~ '^[1-9][0-9]*$'
      OR (e.value->>'cartons') !~ '^[1-9][0-9]*$'
  ) THEN
    RAISE EXCEPTION 'ہر شخص کے لیے درست worker_id اور مثبت کارٹن تعداد ضروری ہے۔' USING ERRCODE='22023';
  END IF;

  SELECT count(*)::integer,coalesce(sum((e.value->>'cartons')::integer),0),
         count(DISTINCT (e.value->>'worker_id')::bigint)::integer
  INTO v_count,v_sum,v_distinct_workers
  FROM jsonb_array_elements(p_allocations) e(value);
  IF v_count<>v_distinct_workers THEN
    RAISE EXCEPTION 'ایک شخص کو ایک ہی پروڈکشن میں ایک بار درج کریں۔' USING ERRCODE='22023';
  END IF;
  IF p_product_type='6L' AND v_count>0 THEN
    RAISE EXCEPTION '6L پروڈکشن پر مزدوری نہیں؛ تقسیم درج نہ کریں۔' USING ERRCODE='22023';
  END IF;
  IF p_product_type IN ('500ml','1.5L') AND (v_count=0 OR v_sum<>p_quantity) THEN
    RAISE EXCEPTION 'مالک اور مزدوروں کے کارٹنوں کا مجموعہ کل پروڈکشن کے برابر ہونا لازم ہے۔' USING ERRCODE='23514';
  END IF;

  -- The same lock used by record_product_sale prevents a sale and production
  -- from both consuming the same last finished-stock quantity concurrently.
  PERFORM pg_advisory_xact_lock(hashtextextended('finished-stock:'||p_product_type,0));
  -- All production types share raw materials and water pools.
  PERFORM pg_advisory_xact_lock(hashtextextended('production-inputs',0));

  IF p_request_id IS NOT NULL THEN
    SELECT * INTO v_existing FROM public.production WHERE request_id=p_request_id;
    IF FOUND THEN
      SELECT
        coalesce(sum(a.cartons*10) FILTER(WHERE NOT coalesce(w.is_owner,false)),0),
        coalesce(sum(a.cartons*10) FILTER(WHERE coalesce(w.is_owner,false)),0),
        coalesce(sum(a.cartons) FILTER(WHERE coalesce(w.is_owner,false)),0),
        count(a.id)::integer
      INTO v_worker_labor_total,v_owner_saved_labor,v_owner_cartons,v_count
      FROM public.production_worker_allocations a
      LEFT JOIN public.workers w ON w.id=a.worker_id
      WHERE a.production_id=v_existing.id;
      RETURN jsonb_build_object(
        'production_id',v_existing.id,'product_type',v_existing.product_type,
        'quantity',v_existing.quantity,'labor_amount',coalesce(v_existing.labor_amount,0),
        'worker_labor_total',v_worker_labor_total,'owner_saved_labor',v_owner_saved_labor,
        'owner_cartons',v_owner_cartons,'worker_count',v_count,'already_recorded',true
      );
    END IF;
  END IF;

  -- Enforce the material balance as of the production date.
  IF p_product_type='500ml' THEN
    v_required:=p_quantity*24;
    SELECT coalesce(sum(quantity),0) INTO v_available
    FROM public.raw_material_purchases
    WHERE material_type='bottle_500ml' AND purchase_date<=p_production_date;
    SELECT coalesce(sum(quantity),0)*24 INTO v_consumed
    FROM public.production WHERE product_type='500ml' AND production_date<=p_production_date;
    IF v_available-v_consumed<v_required THEN
      RAISE EXCEPTION '500ml کی خالی بوتلیں/ڈھکن ناکافی ہیں۔ دستیاب: %، درکار: %',greatest(v_available-v_consumed,0),v_required USING ERRCODE='23514';
    END IF;

    SELECT coalesce(sum(quantity),0) INTO v_available
    FROM public.raw_material_purchases
    WHERE material_type='carton_500ml' AND purchase_date<=p_production_date;
    SELECT coalesce(sum(quantity),0) INTO v_consumed
    FROM public.production WHERE product_type='500ml' AND production_date<=p_production_date;
    IF v_available-v_consumed<p_quantity THEN
      RAISE EXCEPTION '500ml کارٹن ناکافی ہیں۔ دستیاب: %، درکار: %',greatest(v_available-v_consumed,0),p_quantity USING ERRCODE='23514';
    END IF;

  ELSIF p_product_type='1.5L' THEN
    v_required:=p_quantity*12;
    SELECT coalesce(sum(quantity),0) INTO v_available
    FROM public.raw_material_purchases
    WHERE material_type='bottle_1_5l' AND purchase_date<=p_production_date;
    SELECT coalesce(sum(quantity),0)*12 INTO v_consumed
    FROM public.production WHERE product_type='1.5L' AND production_date<=p_production_date;
    IF v_available-v_consumed<v_required THEN
      RAISE EXCEPTION '1.5L کی خالی بوتلیں/ڈھکن ناکافی ہیں۔ دستیاب: %، درکار: %',greatest(v_available-v_consumed,0),v_required USING ERRCODE='23514';
    END IF;

    SELECT coalesce(sum(quantity),0) INTO v_available
    FROM public.raw_material_purchases
    WHERE material_type='carton_1_5l' AND purchase_date<=p_production_date;
    SELECT coalesce(sum(quantity),0) INTO v_consumed
    FROM public.production WHERE product_type='1.5L' AND production_date<=p_production_date;
    IF v_available-v_consumed<p_quantity THEN
      RAISE EXCEPTION '1.5L کارٹن ناکافی ہیں۔ دستیاب: %، درکار: %',greatest(v_available-v_consumed,0),p_quantity USING ERRCODE='23514';
    END IF;

  ELSE
    SELECT coalesce(sum(quantity),0) INTO v_available
    FROM public.raw_material_purchases
    WHERE material_type='bottle_6l' AND purchase_date<=p_production_date;
    SELECT coalesce(sum(quantity),0) INTO v_consumed
    FROM public.production WHERE product_type='6L' AND production_date<=p_production_date;
    IF v_available-v_consumed<p_quantity THEN
      RAISE EXCEPTION '6L کی خالی بوتلیں/ڈھکن ناکافی ہیں۔ دستیاب: %، درکار: %',greatest(v_available-v_consumed,0),p_quantity USING ERRCODE='23514';
    END IF;
  END IF;

  -- Tape: one bundle per 200 cartons across 500ml and 1.5L.
  SELECT coalesce(sum(quantity),0) INTO v_available
  FROM public.raw_material_purchases
  WHERE material_type='tape_bundle' AND purchase_date<=p_production_date;
  SELECT coalesce(sum(quantity),0)/200 INTO v_consumed
  FROM public.production
  WHERE product_type IN ('500ml','1.5L') AND production_date<=p_production_date;
  v_required:=CASE WHEN p_product_type IN ('500ml','1.5L') THEN p_quantity::numeric/200 ELSE 0 END;
  IF v_available-v_consumed<v_required THEN
    RAISE EXCEPTION 'پیکنگ ٹیپ ناکافی ہے۔ دستیاب بنڈل: %، درکار: %',greatest(v_available-v_consumed,0),v_required USING ERRCODE='23514';
  END IF;

  -- One sticker per bottle, carton contents are 24 / 12 units.
  SELECT coalesce(sum(quantity),0) INTO v_available
  FROM public.raw_material_purchases
  WHERE material_type='sticker' AND purchase_date<=p_production_date;
  SELECT coalesce(sum(quantity*CASE product_type WHEN '500ml' THEN 24 WHEN '1.5L' THEN 12 ELSE 1 END),0)
    INTO v_consumed
  FROM public.production WHERE production_date<=p_production_date;
  v_required:=p_quantity*CASE p_product_type WHEN '500ml' THEN 24 WHEN '1.5L' THEN 12 ELSE 1 END;
  IF v_available-v_consumed<v_required THEN
    RAISE EXCEPTION 'اسٹیکرز ناکافی ہیں۔ دستیاب: %، درکار: %',greatest(v_available-v_consumed,0),v_required USING ERRCODE='23514';
  END IF;

  -- Water pools are separate: product filling (500ml / 1.5L) and shop pool (19L / 6L).
  IF p_product_type IN ('500ml','1.5L') THEN
    SELECT
      coalesce((SELECT sum(tanker_count*1000) FROM public.water_tanker_purchases
        WHERE water_use='product_filling' AND purchase_date<=p_production_date),0)
      +coalesce((SELECT sum(litres) FROM public.water_opening_stock
        WHERE water_use='product_filling' AND as_of_date<=p_production_date),0)
    INTO v_available;
    SELECT coalesce(sum(quantity*CASE product_type WHEN '500ml' THEN 12 WHEN '1.5L' THEN 18 ELSE 0 END),0)
    INTO v_consumed FROM public.production
    WHERE product_type IN ('500ml','1.5L') AND production_date<=p_production_date;
    v_required:=p_quantity*CASE p_product_type WHEN '500ml' THEN 12 ELSE 18 END;
    IF v_available-v_consumed<v_required THEN
      RAISE EXCEPTION 'پروڈکشن والی ٹنکی کا پانی ناکافی ہے۔ دستیاب لیٹر: %، درکار: %',greatest(v_available-v_consumed,0),v_required USING ERRCODE='23514';
    END IF;
  ELSE
    SELECT
      coalesce((SELECT sum(tanker_count*1000) FROM public.water_tanker_purchases
        WHERE water_use='shop_counter' AND purchase_date<=p_production_date),0)
      +coalesce((SELECT sum(litres) FROM public.water_opening_stock
        WHERE water_use='shop_counter' AND as_of_date<=p_production_date),0)
    INTO v_available;
    SELECT
      coalesce((SELECT sum(successful_bottles*19) FROM public.customer_19l_deliveries
        WHERE delivery_date<=p_production_date),0)
      +coalesce((SELECT sum(total_litres) FROM public.counter_water_sales
        WHERE sale_date<=p_production_date),0)
      +coalesce((SELECT sum(quantity*6) FROM public.production
        WHERE product_type='6L' AND production_date<=p_production_date),0)
    INTO v_consumed;
    v_required:=p_quantity*6;
    IF v_available-v_consumed<v_required THEN
      RAISE EXCEPTION 'دکان والی ٹنکی کا پانی ناکافی ہے۔ دستیاب لیٹر: %، درکار: %',greatest(v_available-v_consumed,0),v_required USING ERRCODE='23514';
    END IF;
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_allocations) LOOP
    v_worker_id:=(v_item->>'worker_id')::bigint;
    v_cartons:=(v_item->>'cartons')::integer;
    SELECT w.is_owner INTO v_is_owner FROM public.workers w
    WHERE w.id=v_worker_id AND w.is_active=true
      AND (w.is_owner=true OR w.work_categories @> ARRAY['production']::text[]);
    IF NOT FOUND THEN RAISE EXCEPTION 'منتخب ورکر فعال نہیں یا پروڈکشن کے لیے مقرر نہیں۔'; END IF;
    IF coalesce(v_is_owner,false) THEN v_owner_cartons:=v_owner_cartons+v_cartons;
    ELSE v_worker_labor_total:=v_worker_labor_total+(v_cartons*10); END IF;
  END LOOP;

  v_owner_saved_labor:=v_owner_cartons*CASE WHEN p_product_type='6L' THEN 0 ELSE 10 END;
  INSERT INTO public.production(product_type,quantity,production_date,labor_rate,labor_amount,entered_by,worker_id,request_id)
  VALUES(p_product_type,p_quantity,p_production_date,
    CASE WHEN p_product_type='6L' THEN 0 ELSE 10 END,v_worker_labor_total,auth.uid(),NULL,p_request_id)
  ON CONFLICT(request_id) DO NOTHING
  RETURNING id,labor_amount INTO v_production_id,v_labor_amount;

  IF v_production_id IS NULL AND p_request_id IS NOT NULL THEN
    SELECT id,labor_amount INTO v_production_id,v_labor_amount
    FROM public.production WHERE request_id=p_request_id;
  END IF;
  IF v_production_id IS NULL THEN RAISE EXCEPTION 'پروڈکشن محفوظ ہونے کی تصدیق نہیں ہوئی۔'; END IF;

  IF NOT EXISTS(SELECT 1 FROM public.production_worker_allocations WHERE production_id=v_production_id) THEN
    FOR v_item IN SELECT value FROM jsonb_array_elements(p_allocations) LOOP
      INSERT INTO public.production_worker_allocations(production_id,worker_id,cartons)
      VALUES(v_production_id,(v_item->>'worker_id')::bigint,(v_item->>'cartons')::integer);
    END LOOP;
  END IF;

  RETURN jsonb_build_object('production_id',v_production_id,'product_type',p_product_type,
    'quantity',p_quantity,'labor_amount',coalesce(v_labor_amount,0),
    'worker_labor_total',v_worker_labor_total,'owner_saved_labor',v_owner_saved_labor,
    'owner_cartons',v_owner_cartons,'worker_count',v_count,'already_recorded',false);
END;
$function$;
