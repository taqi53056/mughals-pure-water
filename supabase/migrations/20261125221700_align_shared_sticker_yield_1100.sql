CREATE OR REPLACE FUNCTION private.mpw_guard_raw_material_opening_stock()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
  v_old_id bigint;
  v_event_date date;
  v_cutover_date date;
  v_available numeric := 0;
  v_consumed numeric := 0;
BEGIN
  IF TG_OP='DELETE' THEN
    RAISE EXCEPTION 'خام مال کی انٹری حذف نہیں کی جا سکتی؛ درستگی کے لیے ریکارڈ میں مقدار درست کریں۔'
      USING ERRCODE='55000';
  END IF;

  IF TG_OP='UPDATE' THEN
    IF NEW.record_type IS DISTINCT FROM OLD.record_type
       OR NEW.material_type IS DISTINCT FROM OLD.material_type
       OR NEW.purchase_date IS DISTINCT FROM OLD.purchase_date THEN
      RAISE EXCEPTION 'خام مال کی انٹری میں ریکارڈ کی قسم، میٹریل اور تاریخ تبدیل نہیں کی جا سکتی۔'
        USING ERRCODE='55000';
    END IF;
    v_old_id:=OLD.id;
  ELSIF NEW.record_type='purchase' THEN
    RETURN NEW;
  END IF;

  IF NEW.material_type='cap_19l' THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('raw-material-cap-19l',0));
  ELSE
    PERFORM pg_advisory_xact_lock(hashtextextended('production-inputs',0));
  END IF;

  IF NEW.record_type='opening_stock' THEN
    v_cutover_date:=NEW.purchase_date;
  ELSE
    SELECT min(r.purchase_date) INTO v_cutover_date
    FROM public.raw_material_purchases r
    WHERE r.material_type=NEW.material_type
      AND r.record_type='opening_stock';
  END IF;

  FOR v_event_date IN
    SELECT DISTINCT event_date
    FROM (
      SELECT p.production_date AS event_date
      FROM public.production p
      WHERE
        (NEW.material_type IN ('bottle_500ml','cap_500ml','carton_500ml') AND p.product_type='500ml')
        OR (NEW.material_type IN ('bottle_1_5l','cap_1_5l','carton_1_5l') AND p.product_type='1.5L')
        OR (NEW.material_type IN ('bottle_6l','cap_6l') AND p.product_type='6L')
        OR NEW.material_type IN ('tape_bundle','sticker','sticker_500ml','sticker_1_5l_6l')
      UNION ALL
      SELECT d.delivery_date
      FROM public.customer_19l_deliveries d
      WHERE NEW.material_type='cap_19l'
      UNION ALL
      SELECT d.delivery_date
      FROM public.unassigned_19l_deliveries d
      WHERE NEW.material_type='cap_19l'
    ) events
    WHERE event_date IS NOT NULL
      AND (NEW.record_type<>'opening_stock' OR v_cutover_date IS NULL OR event_date>=v_cutover_date)
    ORDER BY event_date
  LOOP
    SELECT coalesce(sum(r.quantity * CASE r.material_type
        WHEN 'sticker_500ml' THEN 1900::numeric
        WHEN 'sticker_1_5l_6l' THEN 1100::numeric
        ELSE 1::numeric END),0)
      + CASE WHEN NEW.purchase_date<=v_event_date
          AND (v_cutover_date IS NULL
            OR (v_event_date<v_cutover_date AND NEW.record_type<>'opening_stock')
            OR (v_event_date>=v_cutover_date
              AND (NEW.record_type='opening_stock' OR NEW.purchase_date>=v_cutover_date)))
        THEN NEW.quantity * CASE NEW.material_type
          WHEN 'sticker_500ml' THEN 1900::numeric
          WHEN 'sticker_1_5l_6l' THEN 1100::numeric
          ELSE 1::numeric END ELSE 0 END
    INTO v_available
    FROM public.raw_material_purchases r
    WHERE r.material_type=NEW.material_type
      AND r.purchase_date<=v_event_date
      AND (v_cutover_date IS NULL
        OR (v_event_date<v_cutover_date AND r.record_type<>'opening_stock')
        OR (v_event_date>=v_cutover_date
          AND (r.record_type='opening_stock' OR r.purchase_date>=v_cutover_date)))
      AND (v_old_id IS NULL OR r.id IS DISTINCT FROM v_old_id);

    IF NEW.material_type='cap_19l' THEN
      SELECT
        coalesce((SELECT sum(d.damaged_caps)
          FROM public.customer_19l_deliveries d
          WHERE d.delivery_date<=v_event_date
            AND (v_cutover_date IS NULL OR v_event_date<v_cutover_date
              OR d.delivery_date>=v_cutover_date)),0)
        +coalesce((SELECT sum(d.damaged_caps)
          FROM public.unassigned_19l_deliveries d
          WHERE d.delivery_date<=v_event_date
            AND (v_cutover_date IS NULL OR v_event_date<v_cutover_date
              OR d.delivery_date>=v_cutover_date)),0)
      INTO v_consumed;
    ELSE
      SELECT CASE NEW.material_type
        WHEN 'bottle_500ml' THEN coalesce(sum(p.quantity*24),0)
        WHEN 'cap_500ml' THEN coalesce(sum(p.quantity*24),0)
        WHEN 'bottle_1_5l' THEN coalesce(sum(p.quantity*12),0)
        WHEN 'cap_1_5l' THEN coalesce(sum(p.quantity*12),0)
        WHEN 'bottle_6l' THEN coalesce(sum(p.quantity),0)
        WHEN 'cap_6l' THEN coalesce(sum(p.quantity),0)
        WHEN 'carton_500ml' THEN coalesce(sum(p.quantity),0)
        WHEN 'carton_1_5l' THEN coalesce(sum(p.quantity),0)
        WHEN 'tape_bundle' THEN coalesce(sum(p.quantity/70::numeric) FILTER(WHERE p.product_type IN ('500ml','1.5L')),0)
        WHEN 'sticker' THEN coalesce(sum(p.quantity*CASE p.product_type
          WHEN '500ml' THEN 24 WHEN '1.5L' THEN 12 ELSE 1 END),0)
        WHEN 'sticker_500ml' THEN coalesce(sum(p.quantity*24) FILTER(WHERE p.product_type='500ml'),0)
        WHEN 'sticker_1_5l_6l' THEN coalesce(sum(p.quantity*CASE p.product_type WHEN '1.5L' THEN 12 ELSE 1 END)
          FILTER(WHERE p.product_type IN ('1.5L','6L')),0)
        ELSE 0
      END
      INTO v_consumed
      FROM public.production p
      WHERE p.production_date<=v_event_date
        AND (v_cutover_date IS NULL OR v_event_date<v_cutover_date
          OR p.production_date>=v_cutover_date)
        AND (
          (NEW.material_type IN ('bottle_500ml','cap_500ml','carton_500ml') AND p.product_type='500ml')
          OR (NEW.material_type IN ('bottle_1_5l','cap_1_5l','carton_1_5l') AND p.product_type='1.5L')
          OR (NEW.material_type IN ('bottle_6l','cap_6l') AND p.product_type='6L')
          OR NEW.material_type IN ('tape_bundle','sticker','sticker_500ml','sticker_1_5l_6l')
        );
    END IF;

    IF v_available<v_consumed THEN
      RAISE EXCEPTION 'خام مال % کی درستگی سے سابقہ پیداوار/ڈلیوری میں اسٹاک منفی ہوگا۔ تاریخ: %، دستیاب: %، استعمال: %',
        NEW.material_type,v_event_date,greatest(v_available,0),v_consumed
        USING ERRCODE='23514';
    END IF;
  END LOOP;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION private.record_production_with_workers(p_production_date date, p_product_type text, p_quantity integer, p_allocations jsonb, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
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
  IF p_request_id IS NULL THEN
    RAISE EXCEPTION 'ہر پروڈکشن اندراج کے لیے منفرد درخواست شناخت لازمی ہے۔' USING ERRCODE='22023';
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
      IF v_existing.production_date IS DISTINCT FROM p_production_date
         OR v_existing.product_type IS DISTINCT FROM p_product_type
         OR v_existing.quantity IS DISTINCT FROM p_quantity
         OR EXISTS (
           SELECT a.worker_id, a.cartons
           FROM public.production_worker_allocations a
           WHERE a.production_id = v_existing.id
           EXCEPT
           SELECT (e.value->>'worker_id')::bigint, (e.value->>'cartons')::integer
           FROM jsonb_array_elements(p_allocations) e(value)
         )
         OR EXISTS (
           SELECT (e.value->>'worker_id')::bigint, (e.value->>'cartons')::integer
           FROM jsonb_array_elements(p_allocations) e(value)
           EXCEPT
           SELECT a.worker_id, a.cartons
           FROM public.production_worker_allocations a
           WHERE a.production_id = v_existing.id
         ) THEN
        RAISE EXCEPTION 'یہ درخواست پہلے مختلف پروڈکشن یا مزدوروں کی تقسیم کے لیے استعمال ہو چکی ہے۔'
          USING ERRCODE='23505';
      END IF;
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
      IF v_existing.production_date IS DISTINCT FROM p_production_date
         OR v_existing.product_type IS DISTINCT FROM p_product_type
         OR v_existing.quantity IS DISTINCT FROM p_quantity
         OR EXISTS (
           SELECT a.worker_id, a.cartons
           FROM public.production_worker_allocations a
           WHERE a.production_id = v_existing.id
           EXCEPT
           SELECT (e.value->>'worker_id')::bigint, (e.value->>'cartons')::integer
           FROM jsonb_array_elements(p_allocations) e(value)
         )
         OR EXISTS (
           SELECT (e.value->>'worker_id')::bigint, (e.value->>'cartons')::integer
           FROM jsonb_array_elements(p_allocations) e(value)
           EXCEPT
           SELECT a.worker_id, a.cartons
           FROM public.production_worker_allocations a
           WHERE a.production_id = v_existing.id
         ) THEN
        RAISE EXCEPTION 'یہ درخواست پہلے مختلف پروڈکشن یا مزدوروں کی تقسیم کے لیے استعمال ہو چکی ہے۔'
          USING ERRCODE='23505';
      END IF;
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

  -- Tape is consumed and validated at one bundle per 70 cartons by the production packaging stock guard.

  -- Separate sticker rolls: 500ml yield 1,900/kg; shared 1.5L/6L yield 1,200/kg.
  IF p_product_type='500ml' THEN
    SELECT coalesce(sum(quantity*1900),0) INTO v_available
    FROM public.raw_material_purchases WHERE material_type='sticker_500ml' AND purchase_date<=p_production_date;
    SELECT coalesce(sum(quantity*24),0) INTO v_consumed
    FROM public.production WHERE product_type='500ml' AND production_date<=p_production_date;
    v_required:=p_quantity*24;
  ELSE
    SELECT coalesce(sum(quantity*1100),0) INTO v_available
    FROM public.raw_material_purchases WHERE material_type='sticker_1_5l_6l' AND purchase_date<=p_production_date;
    SELECT coalesce(sum(quantity*CASE product_type WHEN '1.5L' THEN 12 ELSE 1 END),0) INTO v_consumed
    FROM public.production WHERE product_type IN ('1.5L','6L') AND production_date<=p_production_date;
    v_required:=p_quantity*CASE p_product_type WHEN '1.5L' THEN 12 ELSE 1 END;
  END IF;
  IF v_available-v_consumed<v_required THEN
    RAISE EXCEPTION 'متعلقہ اسٹیکرز ناکافی ہیں۔ دستیاب: %، درکار: %',greatest(v_available-v_consumed,0),v_required USING ERRCODE='23514';
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
      COALESCE((SELECT SUM(d.bottles_delivered*19) FROM public.customer_19l_deliveries d WHERE d.delivery_date<=p_production_date),0)
      +COALESCE((SELECT SUM(d.bottles_delivered*19) FROM public.unassigned_19l_deliveries d WHERE d.delivery_date<=p_production_date),0)
      +COALESCE((SELECT SUM(private.mpw_counter_water_litres(c.sale_date,c.total_litres,c.counter_water_litres)) FROM public.counter_water_sales c WHERE c.sale_date<=p_production_date),0)
      +COALESCE((SELECT SUM(p.quantity*6) FROM public.production p WHERE p.product_type='6L' AND p.production_date<=p_production_date),0)
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
$function$
;