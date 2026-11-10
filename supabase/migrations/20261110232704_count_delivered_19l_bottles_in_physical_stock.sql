CREATE OR REPLACE FUNCTION private.mpw_guard_operational_stock()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_date date;
  v_available numeric := 0;
  v_consumed numeric := 0;
  v_required numeric := 0;
begin
  if tg_table_name = 'customer_19l_deliveries' then
    v_date := new.delivery_date;
    v_required := coalesce(new.bottles_delivered,0) * 19;

    perform pg_advisory_xact_lock(hashtextextended('water-pool-shop',0));
    select
      coalesce((select sum(tanker_count*1000) from public.water_tanker_purchases
        where water_use='shop_counter' and purchase_date<=v_date),0)
      + coalesce((select sum(litres) from public.water_opening_stock
        where water_use='shop_counter' and as_of_date<=v_date),0)
    into v_available;
    select
      coalesce((select sum(bottles_delivered*19) from public.customer_19l_deliveries
        where delivery_date<=v_date and id is distinct from new.id),0)
      + coalesce((select sum(total_litres) from public.counter_water_sales
        where sale_date<=v_date),0)
      + coalesce((select sum(quantity*6) from public.production
        where product_type='6L' and production_date<=v_date),0)
    into v_consumed;
    if v_available-v_consumed<v_required then
      raise exception 'دکان والی ٹنکی کا پانی ناکافی ہے۔ دستیاب لیٹر: %، درکار: %',
        greatest(v_available-v_consumed,0),v_required using errcode='23514';
    end if;

    perform pg_advisory_xact_lock(hashtextextended('raw-material-cap-19l',0));
    select coalesce(sum(quantity),0) into v_available
    from public.raw_material_purchases
    where material_type='cap_19l' and purchase_date<=v_date;
    select coalesce(sum(bottles_delivered+damaged_caps),0) into v_consumed
    from public.customer_19l_deliveries
    where delivery_date<=v_date and id is distinct from new.id;
    v_required := coalesce(new.bottles_delivered,0) + coalesce(new.damaged_caps,0);
    if v_available-v_consumed<v_required then
      raise exception '19L ڈھکن ناکافی ہیں۔ دستیاب: %، درکار: %',
        greatest(v_available-v_consumed,0),v_required using errcode='23514';
    end if;
    return new;

  elsif tg_table_name = 'counter_water_sales' then
    v_date := new.sale_date;
    v_required := new.total_litres;

    perform pg_advisory_xact_lock(hashtextextended('water-pool-shop',0));
    select
      coalesce((select sum(tanker_count*1000) from public.water_tanker_purchases
        where water_use='shop_counter' and purchase_date<=v_date),0)
      + coalesce((select sum(litres) from public.water_opening_stock
        where water_use='shop_counter' and as_of_date<=v_date),0)
    into v_available;
    select
      coalesce((select sum(bottles_delivered*19) from public.customer_19l_deliveries
        where delivery_date<=v_date),0)
      + coalesce((select sum(total_litres) from public.counter_water_sales
        where sale_date<=v_date and id is distinct from new.id),0)
      + coalesce((select sum(quantity*6) from public.production
        where product_type='6L' and production_date<=v_date),0)
    into v_consumed;
    if v_available-v_consumed<v_required then
      raise exception 'دکان والی ٹنکی کا پانی ناکافی ہے۔ دستیاب لیٹر: %، درکار: %',
        greatest(v_available-v_consumed,0),v_required using errcode='23514';
    end if;
    return new;

  elsif tg_table_name = 'production' then
    v_date := new.production_date;
    if new.product_type = '6L' then
      v_required := new.quantity*6;
      perform pg_advisory_xact_lock(hashtextextended('water-pool-shop',0));
      select
        coalesce((select sum(tanker_count*1000) from public.water_tanker_purchases
          where water_use='shop_counter' and purchase_date<=v_date),0)
        + coalesce((select sum(litres) from public.water_opening_stock
          where water_use='shop_counter' and as_of_date<=v_date),0)
      into v_available;
      select
        coalesce((select sum(bottles_delivered*19) from public.customer_19l_deliveries
          where delivery_date<=v_date),0)
        + coalesce((select sum(total_litres) from public.counter_water_sales
          where sale_date<=v_date),0)
        + coalesce((select sum(quantity*6) from public.production
          where product_type='6L' and production_date<=v_date
            and id is distinct from new.id),0)
      into v_consumed;
    else
      v_required := new.quantity*case new.product_type when '500ml' then 12 else 18 end;
      perform pg_advisory_xact_lock(hashtextextended('water-pool-filling',0));
      select
        coalesce((select sum(tanker_count*1000) from public.water_tanker_purchases
          where water_use='product_filling' and purchase_date<=v_date),0)
        + coalesce((select sum(litres) from public.water_opening_stock
          where water_use='product_filling' and as_of_date<=v_date),0)
      into v_available;
      select coalesce(sum(quantity*case product_type when '500ml' then 12 when '1.5L' then 18 else 0 end),0)
      into v_consumed
      from public.production
      where product_type in ('500ml','1.5L')
        and production_date<=v_date
        and id is distinct from new.id;
    end if;
    if v_available-v_consumed<v_required then
      raise exception 'پروڈکشن کے لیے متعلقہ ٹنکی کا پانی ناکافی ہے۔ دستیاب لیٹر: %، درکار: %',
        greatest(v_available-v_consumed,0),v_required using errcode='23514';
    end if;
    return new;
  end if;
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION private.mpw_guard_raw_material_opening_stock()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_old_id bigint;
  v_event_date date;
  v_available numeric := 0;
  v_consumed numeric := 0;
begin
  if tg_op='DELETE' then
    raise exception 'خام مال کی انٹری حذف نہیں کی جا سکتی؛ درستگی کے لیے ریکارڈ میں مقدار درست کریں۔'
      using errcode='55000';
  end if;

  if tg_op='UPDATE' then
    if new.record_type is distinct from old.record_type
       or new.material_type is distinct from old.material_type
       or new.purchase_date is distinct from old.purchase_date then
      raise exception 'خام مال کی انٹری میں ریکارڈ کی قسم، میٹریل اور تاریخ تبدیل نہیں کی جا سکتی۔'
        using errcode='55000';
    end if;
    v_old_id:=old.id;
  elsif new.record_type='purchase' then
    return new;
  end if;

  perform pg_advisory_xact_lock(hashtextextended('production-inputs',0));

  for v_event_date in
    select distinct event_date
    from (
      select p.production_date as event_date
      from public.production p
      where
        (new.material_type in ('bottle_500ml','cap_500ml','carton_500ml') and p.product_type='500ml')
        or (new.material_type in ('bottle_1_5l','cap_1_5l','carton_1_5l') and p.product_type='1.5L')
        or (new.material_type in ('bottle_6l','cap_6l') and p.product_type='6L')
        or new.material_type in ('tape_bundle','sticker')
      union all
      select d.delivery_date
      from public.customer_19l_deliveries d
      where new.material_type='cap_19l'
    ) events
    where event_date is not null
    order by event_date
  loop
    select coalesce(sum(r.quantity),0)
      + case when new.purchase_date<=v_event_date then new.quantity else 0 end
    into v_available
    from public.raw_material_purchases r
    where r.material_type=new.material_type
      and r.purchase_date<=v_event_date
      and (v_old_id is null or r.id is distinct from v_old_id);

    select case new.material_type
      when 'bottle_500ml' then coalesce(sum(p.quantity*24),0)
      when 'cap_500ml' then coalesce(sum(p.quantity*24),0)
      when 'bottle_1_5l' then coalesce(sum(p.quantity*12),0)
      when 'cap_1_5l' then coalesce(sum(p.quantity*12),0)
      when 'bottle_6l' then coalesce(sum(p.quantity),0)
      when 'cap_6l' then coalesce(sum(p.quantity),0)
      when 'carton_500ml' then coalesce(sum(p.quantity),0)
      when 'carton_1_5l' then coalesce(sum(p.quantity),0)
      when 'tape_bundle' then coalesce(sum(p.quantity),0)/200
      when 'sticker' then coalesce(sum(p.quantity*case p.product_type when '500ml' then 24 when '1.5L' then 12 else 1 end),0)
      else 0
    end
    into v_consumed
    from public.production p
    where p.production_date<=v_event_date
      and (
        (new.material_type in ('bottle_500ml','cap_500ml','carton_500ml') and p.product_type='500ml')
        or (new.material_type in ('bottle_1_5l','cap_1_5l','carton_1_5l') and p.product_type='1.5L')
        or (new.material_type in ('bottle_6l','cap_6l') and p.product_type='6L')
        or new.material_type in ('tape_bundle','sticker')
      );

    if new.material_type='cap_19l' then
      select coalesce(sum(d.bottles_delivered+d.damaged_caps),0)
        into v_consumed
      from public.customer_19l_deliveries d
      where d.delivery_date<=v_event_date;
    end if;

    if v_available<v_consumed then
      raise exception 'خام مال % کی درستگی سے سابقہ پیداوار/ڈلیوری میں اسٹاک منفی ہوگا۔ تاریخ: %، دستیاب: %، استعمال: %',
        new.material_type,v_event_date,greatest(v_available,0),v_consumed
        using errcode='23514';
    end if;
  end loop;

  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION private.mpw_guard_water_opening_stock()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_old_id bigint;
  v_event_date date;
  v_available numeric := 0;
  v_consumed numeric := 0;
  v_lock_key text;
begin
  if tg_op='DELETE' then
    raise exception 'ابتدائی پانی کا اسٹاک حذف نہیں کیا جا سکتا؛ درستگی کے لیے مقدار اپڈیٹ کریں۔'
      using errcode='55000';
  end if;

  if tg_op='UPDATE' then
    if new.water_use is distinct from old.water_use
       or new.as_of_date is distinct from old.as_of_date then
      raise exception 'پانی کے ابتدائی اسٹاک کا پول اور تاریخ تبدیل نہیں کیے جا سکتے۔'
        using errcode='55000';
    end if;
    v_old_id:=old.id;
  end if;

  if new.water_use not in ('shop_counter','product_filling') or new.litres<=0 then
    raise exception 'پانی کا پول اور مثبت لیٹر مقدار درست درج کریں۔'
      using errcode='22023';
  end if;

  v_lock_key:=case when new.water_use='shop_counter' then 'water-pool-shop' else 'water-pool-filling' end;
  perform pg_advisory_xact_lock(hashtextextended(v_lock_key,0));

  if new.water_use='shop_counter' then
    for v_event_date in
      select distinct event_date from (
        select d.delivery_date as event_date from public.customer_19l_deliveries d
        union all select c.sale_date from public.counter_water_sales c
        union all select p.production_date from public.production p where p.product_type='6L'
      ) e where event_date is not null order by event_date
    loop
      select
        coalesce((select sum(t.tanker_count*1000) from public.water_tanker_purchases t
          where t.water_use='shop_counter' and t.purchase_date<=v_event_date),0)
        + coalesce((select sum(w.litres) from public.water_opening_stock w
          where w.water_use='shop_counter' and w.as_of_date<=v_event_date
            and (v_old_id is null or w.id is distinct from v_old_id)),0)
        + case when new.as_of_date<=v_event_date then new.litres else 0 end
      into v_available;

      select
        coalesce((select sum(d.bottles_delivered*19) from public.customer_19l_deliveries d
          where d.delivery_date<=v_event_date),0)
        + coalesce((select sum(c.total_litres) from public.counter_water_sales c
          where c.sale_date<=v_event_date),0)
        + coalesce((select sum(p.quantity*6) from public.production p
          where p.product_type='6L' and p.production_date<=v_event_date),0)
      into v_consumed;

      if v_available<v_consumed then
        raise exception 'دکان والی ٹنکی کے ابتدائی پانی میں کمی سے سابقہ استعمال غیر متوازن ہوگا۔ تاریخ: %، دستیاب: %، استعمال: %',
          v_event_date,greatest(v_available,0),v_consumed using errcode='23514';
      end if;
    end loop;
  else
    for v_event_date in
      select distinct p.production_date
      from public.production p
      where p.product_type in ('500ml','1.5L')
      order by p.production_date
    loop
      select
        coalesce((select sum(t.tanker_count*1000) from public.water_tanker_purchases t
          where t.water_use='product_filling' and t.purchase_date<=v_event_date),0)
        + coalesce((select sum(w.litres) from public.water_opening_stock w
          where w.water_use='product_filling' and w.as_of_date<=v_event_date
            and (v_old_id is null or w.id is distinct from v_old_id)),0)
        + case when new.as_of_date<=v_event_date then new.litres else 0 end
      into v_available;

      select coalesce(sum(p.quantity*case p.product_type when '500ml' then 12 else 18 end),0)
      into v_consumed
      from public.production p
      where p.product_type in ('500ml','1.5L') and p.production_date<=v_event_date;

      if v_available<v_consumed then
        raise exception 'پروڈکشن والی ٹنکی کے ابتدائی پانی میں کمی سے سابقہ پروڈکشن غیر متوازن ہوگی۔ تاریخ: %، دستیاب: %، استعمال: %',
          v_event_date,greatest(v_available,0),v_consumed using errcode='23514';
      end if;
    end loop;
  end if;

  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION private.mpw_guard_water_tanker_purchase_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_event_date date;
  v_available numeric := 0;
  v_consumed numeric := 0;
  v_lock_key text;
begin
  if tg_op='DELETE' then
    raise exception 'ٹینکر خریداری حذف نہیں کی جا سکتی؛ درستگی کے لیے مقدار یا ریٹ اپڈیٹ کریں۔'
      using errcode='55000';
  end if;

  if new.purchase_date is distinct from old.purchase_date
     or new.water_use is distinct from old.water_use then
    raise exception 'ٹینکر خریداری کی تاریخ اور پانی کا پول تبدیل نہیں کیا جا سکتا۔'
      using errcode='55000';
  end if;

  v_lock_key:=case when new.water_use='shop_counter' then 'water-pool-shop' else 'water-pool-filling' end;
  perform pg_advisory_xact_lock(hashtextextended(v_lock_key,0));

  if new.water_use='shop_counter' then
    for v_event_date in
      select distinct event_date from (
        select d.delivery_date as event_date from public.customer_19l_deliveries d
        union all select c.sale_date from public.counter_water_sales c
        union all select p.production_date from public.production p where p.product_type='6L'
      ) e where event_date is not null order by event_date
    loop
      select
        coalesce((select sum(t.tanker_count*1000) from public.water_tanker_purchases t
          where t.water_use='shop_counter' and t.purchase_date<=v_event_date
            and t.id is distinct from old.id),0)
        + case when new.purchase_date<=v_event_date then new.tanker_count*1000 else 0 end
        + coalesce((select sum(w.litres) from public.water_opening_stock w
          where w.water_use='shop_counter' and w.as_of_date<=v_event_date),0)
      into v_available;

      select
        coalesce((select sum(d.bottles_delivered*19) from public.customer_19l_deliveries d
          where d.delivery_date<=v_event_date),0)
        + coalesce((select sum(c.total_litres) from public.counter_water_sales c
          where c.sale_date<=v_event_date),0)
        + coalesce((select sum(p.quantity*6) from public.production p
          where p.product_type='6L' and p.production_date<=v_event_date),0)
      into v_consumed;

      if v_available<v_consumed then
        raise exception 'ٹینکر کی مقدار کم کرنے سے دکان والی ٹنکی کا سابقہ استعمال غیر متوازن ہوگا۔ تاریخ: %، دستیاب: %، استعمال: %',
          v_event_date,greatest(v_available,0),v_consumed using errcode='23514';
      end if;
    end loop;
  else
    for v_event_date in
      select distinct p.production_date from public.production p
      where p.product_type in ('500ml','1.5L') order by p.production_date
    loop
      select
        coalesce((select sum(t.tanker_count*1000) from public.water_tanker_purchases t
          where t.water_use='product_filling' and t.purchase_date<=v_event_date
            and t.id is distinct from old.id),0)
        + case when new.purchase_date<=v_event_date then new.tanker_count*1000 else 0 end
        + coalesce((select sum(w.litres) from public.water_opening_stock w
          where w.water_use='product_filling' and w.as_of_date<=v_event_date),0)
      into v_available;

      select coalesce(sum(p.quantity*case p.product_type when '500ml' then 12 else 18 end),0)
      into v_consumed from public.production p
      where p.product_type in ('500ml','1.5L') and p.production_date<=v_event_date;

      if v_available<v_consumed then
        raise exception 'ٹینکر کی مقدار کم کرنے سے پروڈکشن ٹنکی کا سابقہ استعمال غیر متوازن ہوگا۔ تاریخ: %، دستیاب: %، استعمال: %',
          v_event_date,greatest(v_available,0),v_consumed using errcode='23514';
      end if;
    end loop;
  end if;

  return new;
end;
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
      coalesce((SELECT sum(bottles_delivered*19) FROM public.customer_19l_deliveries
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
$function$
;

CREATE OR REPLACE FUNCTION public.build_business_monthly_report(p_month_start date, p_month_end date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_water_litres numeric:=0; v_water_amount numeric:=0; v_water_per_litre numeric;
  v_fill_water_litres numeric:=0; v_fill_water_amount numeric:=0; v_fill_water_rate numeric;
  v_shop_water_litres numeric:=0; v_shop_water_amount numeric:=0; v_shop_water_rate numeric;
  v_fill_water_used numeric:=0; v_shop_water_used numeric:=0;
  v_bottles numeric:=0; v_caps numeric:=0; v_delivery_labor numeric:=0;
  v_counter_litres numeric:=0; v_counter_amount numeric:=0;
  v_bottle500 numeric; v_bottle15 numeric; v_bottle6 numeric; v_cap500 numeric; v_cap15 numeric; v_cap6 numeric;
  v_carton500 numeric; v_carton15 numeric; v_tape numeric; v_cap19 numeric; v_sticker numeric;
  v_cost500 numeric; v_cost15 numeric; v_cost6 numeric;
  v_rev500 numeric:=0; v_rev15 numeric:=0; v_rev6 numeric:=0;
  v_sold500 numeric:=0; v_sold15 numeric:=0; v_sold6 numeric:=0;
  v_return500 numeric:=0; v_return15 numeric:=0; v_return6 numeric:=0;
  v_labor500 numeric:=0; v_labor15 numeric:=0; v_labor6 numeric:=0;
  v_support_labor numeric:=0; v_exp19 numeric:=0; v_exp_products numeric:=0; v_exp_general numeric:=0;
  v_other_income numeric:=0; v_interest_income numeric:=0; v_interest_expense numeric:=0;
  v_depreciation numeric:=0; v_inventory_loss numeric:=0;
  v_owner1 numeric:=0; v_owner2 numeric:=0; v_owner3 numeric:=0; v_owner4 numeric:=0;
  v_capital numeric:=0; v_loan_received numeric:=0; v_loan_repaid numeric:=0;
  v_loan_given numeric:=0; v_loan_collected numeric:=0;
  v_raw_purchase_period numeric:=0; v_tanker_purchase_period numeric:=0;
  v_used_water numeric:=0; v_water_cost numeric:=0; v_cap_cost numeric:=0;
  v_revenue19 numeric:=0; v_profit19 numeric:=0; v_product_revenue numeric:=0;
  v_product_cogs numeric:=0; v_return_loss numeric:=0; v_production_labor numeric:=0;
  v_profit_products numeric:=0; v_net numeric:=0;
  v_missing text[]:=array[]::text[];
  v_has_activity boolean:=false; v_has_pnl_activity boolean:=false;
  v_stock jsonb;
begin
  if p_month_start is null or p_month_end is null or p_month_start>p_month_end then
    raise exception 'درست ماہانہ تاریخ درکار ہے۔' using errcode='22023';
  end if;

  select
    coalesce((select sum(tanker_count*1000) from public.water_tanker_purchases where purchase_date<=p_month_end and water_use='shop_counter'),0)
      +coalesce((select sum(litres) from public.water_opening_stock where as_of_date<=p_month_end and water_use='shop_counter'),0),
    coalesce((select sum(total_amount) from public.water_tanker_purchases where purchase_date<=p_month_end and water_use='shop_counter'),0)
      +coalesce((select sum(total_value) from public.water_opening_stock where as_of_date<=p_month_end and water_use='shop_counter'),0),
    coalesce((select sum(total_amount) from public.water_tanker_purchases where purchase_date between p_month_start and p_month_end),0)
  into v_water_litres,v_water_amount,v_tanker_purchase_period;
  v_water_per_litre:=v_water_amount/nullif(v_water_litres,0);
  SELECT coalesce((SELECT sum(tanker_count*1000) FROM public.water_tanker_purchases WHERE purchase_date<=p_month_end AND water_use='product_filling'),0)+coalesce((SELECT sum(litres) FROM public.water_opening_stock WHERE as_of_date<=p_month_end AND water_use='product_filling'),0), coalesce((SELECT sum(total_amount) FROM public.water_tanker_purchases WHERE purchase_date<=p_month_end AND water_use='product_filling'),0)+coalesce((SELECT sum(total_value) FROM public.water_opening_stock WHERE as_of_date<=p_month_end AND water_use='product_filling'),0) INTO v_fill_water_litres,v_fill_water_amount;
  v_fill_water_rate:=v_fill_water_amount/nullif(v_fill_water_litres,0);
  v_shop_water_litres:=v_water_litres;
  v_shop_water_amount:=v_water_amount;
  v_shop_water_rate:=v_water_per_litre;

  select coalesce(sum(successful_bottles),0),coalesce(sum(damaged_caps),0),coalesce(sum(delivery_labor),0)
  into v_bottles,v_caps,v_delivery_labor
  from public.customer_19l_deliveries
  where delivery_date between p_month_start and p_month_end;

  select coalesce(sum(total_litres),0),coalesce(sum(total_amount),0)
  into v_counter_litres,v_counter_amount
  from public.counter_water_sales where sale_date between p_month_start and p_month_end;

  select sum(total_amount)/nullif(sum(quantity),0) into v_bottle500
  from public.raw_material_purchases where material_type='bottle_500ml' and purchase_date<=p_month_end;
  select sum(total_amount)/nullif(sum(quantity),0) into v_bottle15
  from public.raw_material_purchases where material_type='bottle_1_5l' and purchase_date<=p_month_end;
  select sum(total_amount)/nullif(sum(quantity),0) into v_bottle6
  from public.raw_material_purchases where material_type='bottle_6l' and purchase_date<=p_month_end;
  select sum(total_amount)/nullif(sum(quantity),0) into v_cap500
  from public.raw_material_purchases where material_type='cap_500ml' and purchase_date<=p_month_end;
  select sum(total_amount)/nullif(sum(quantity),0) into v_cap15
  from public.raw_material_purchases where material_type='cap_1_5l' and purchase_date<=p_month_end;
  select sum(total_amount)/nullif(sum(quantity),0) into v_cap6
  from public.raw_material_purchases where material_type='cap_6l' and purchase_date<=p_month_end;
  select sum(total_amount)/nullif(sum(quantity),0) into v_carton500
  from public.raw_material_purchases where material_type='carton_500ml' and purchase_date<=p_month_end;
  select sum(total_amount)/nullif(sum(quantity),0) into v_carton15
  from public.raw_material_purchases where material_type='carton_1_5l' and purchase_date<=p_month_end;
  select sum(total_amount)/nullif(sum(quantity),0) into v_tape
  from public.raw_material_purchases where material_type='tape_bundle' and purchase_date<=p_month_end;
  select sum(total_amount)/nullif(sum(quantity),0) into v_cap19
  from public.raw_material_purchases where material_type='cap_19l' and purchase_date<=p_month_end;
  select sum(total_amount)/nullif(sum(quantity),0) into v_sticker
  from public.raw_material_purchases where material_type='sticker' and purchase_date<=p_month_end;
  v_sticker:=coalesce(v_sticker,1);

  if v_bottle500 is not null and v_cap500 is not null and v_carton500 is not null and v_tape is not null then
    v_cost500:=v_bottle500*24+v_cap500*24+v_carton500+v_tape/200+24*v_sticker;
  end if;
  if v_bottle15 is not null and v_cap15 is not null and v_carton15 is not null and v_tape is not null then
    v_cost15:=v_bottle15*12+v_cap15*12+v_carton15+v_tape/200+12*v_sticker;
  end if;
  if v_bottle6 is not null and v_cap6 is not null then v_cost6:=v_bottle6+v_cap6+v_sticker; end if;

  select
    coalesce(sum(total_amount) filter(where product_type='500ml'),0),
    coalesce(sum(total_amount) filter(where product_type='1.5L'),0),
    coalesce(sum(total_amount) filter(where product_type='6L'),0),
    coalesce(sum(quantity) filter(where product_type='500ml'),0),
    coalesce(sum(quantity) filter(where product_type='1.5L'),0),
    coalesce(sum(quantity) filter(where product_type='6L'),0)
  into v_rev500,v_rev15,v_rev6,v_sold500,v_sold15,v_sold6
  from public.product_sales where sale_date between p_month_start and p_month_end;

  select
    coalesce(sum(replacement_quantity) filter(where product_type='500ml'),0),
    coalesce(sum(replacement_quantity) filter(where product_type='1.5L'),0),
    coalesce(sum(replacement_quantity) filter(where product_type='6L'),0)
  into v_return500,v_return15,v_return6
  from public.product_returns where return_date between p_month_start and p_month_end;

  select
    coalesce((select sum(labor_amount)/nullif(sum(quantity),0) from public.production where product_type='500ml' and production_date<=p_month_end),(select labor_per_unit from public.product_settings where product_type='500ml'),0)*(v_sold500+v_return500/24),
    coalesce((select sum(labor_amount)/nullif(sum(quantity),0) from public.production where product_type='1.5L' and production_date<=p_month_end),(select labor_per_unit from public.product_settings where product_type='1.5L'),0)*(v_sold15+v_return15/12),
    coalesce((select sum(labor_amount)/nullif(sum(quantity),0) from public.production where product_type='6L' and production_date<=p_month_end),(select labor_per_unit from public.product_settings where product_type='6L'),0)*(v_sold6+v_return6)
  into v_labor500,v_labor15,v_labor6;

  select coalesce(sum(amount),0) into v_support_labor
  from public.worker_ledger
  where entry_date between p_month_start and p_month_end and entry_type='earning'
    and work_category in ('carton loading/unloading','cleaning','bottle washing','manual adjustment');

  select
    coalesce(sum(amount) filter(where business_segment='19L'),0),
    coalesce(sum(amount) filter(where business_segment='finished_goods'),0),
    coalesce(sum(amount) filter(where business_segment is null or business_segment='general'),0)
  into v_exp19,v_exp_products,v_exp_general
  from public.business_expenses where expense_date between p_month_start and p_month_end;

  select coalesce(sum(amount),0) into v_other_income
  from public.business_income where income_date between p_month_start and p_month_end;

  select
    coalesce(sum(amount) filter(where entry_type='interest_income'),0),
    coalesce(sum(amount) filter(where entry_type='interest_expense'),0),
    coalesce(sum(amount) filter(where entry_type='depreciation_expense'),0),
    coalesce(sum(amount) filter(where entry_type='inventory_loss'),0),
    coalesce(sum(amount) filter(where entry_type='owner_withdrawal' and counterparty IN ('محمد اسامہ مغل','M.Usama Mughal','M. Usama Mughal')),0),
    coalesce(sum(amount) filter(where entry_type='owner_withdrawal' and counterparty IN ('محمد مزمل مغل','M. Muzamil Mughal')),0),
    coalesce(sum(amount) filter(where entry_type='owner_withdrawal' and counterparty IN ('محمد تقی مغل','M.Taqi Mughal')),0),
    coalesce(sum(amount) filter(where entry_type='owner_withdrawal' and counterparty IN ('محمد رفیع مغل','M. Rafi Mughal')),0)
  into v_interest_income,v_interest_expense,v_depreciation,v_inventory_loss,
    v_owner1,v_owner2,v_owner3,v_owner4
  from public.business_finance_ledger where entry_date between p_month_start and p_month_end;

  select
    coalesce(sum(amount) filter(where entry_type='capital_in'),0),
    coalesce(sum(amount) filter(where entry_type='loan_received'),0),
    coalesce(sum(amount) filter(where entry_type='loan_repaid'),0),
    coalesce(sum(amount) filter(where entry_type='loan_given'),0),
    coalesce(sum(amount) filter(where entry_type='loan_collected'),0)
  into v_capital,v_loan_received,v_loan_repaid,v_loan_given,v_loan_collected
  from public.business_finance_ledger where entry_date<=p_month_end;

  select coalesce(sum(total_amount),0) into v_raw_purchase_period
  from public.raw_material_purchases where purchase_date between p_month_start and p_month_end and record_type='purchase';

  v_used_water:=v_bottles*19;
  v_fill_water_used:=coalesce((SELECT sum(quantity*CASE product_type WHEN '500ml' THEN 12 WHEN '1.5L' THEN 18 ELSE 0 END) FROM public.product_sales WHERE sale_date BETWEEN p_month_start AND p_month_end),0)+coalesce((SELECT sum(replacement_quantity*CASE product_type WHEN '500ml' THEN 0.5 WHEN '1.5L' THEN 1.5 ELSE 0 END) FROM public.product_returns WHERE return_date BETWEEN p_month_start AND p_month_end),0);
  v_shop_water_used:=v_counter_litres+coalesce((SELECT sum(quantity*6) FROM public.product_sales WHERE product_type='6L' AND sale_date BETWEEN p_month_start AND p_month_end),0)+coalesce((SELECT sum(replacement_quantity*6) FROM public.product_returns WHERE product_type='6L' AND return_date BETWEEN p_month_start AND p_month_end),0);
  v_water_cost:=v_used_water*coalesce(v_water_per_litre,0);
  v_cap_cost:=(v_bottles+v_caps)*coalesce(v_cap19,0);
  v_revenue19:=v_bottles*100+v_caps*10+v_counter_amount;
  v_profit19:=v_revenue19-v_water_cost-v_cap_cost-v_delivery_labor-v_exp19-v_counter_litres*coalesce(v_shop_water_rate,0);
  v_product_revenue:=v_rev500+v_rev15+v_rev6;
  v_product_cogs:=v_sold500*coalesce(v_cost500,0)+v_sold15*coalesce(v_cost15,0)+v_sold6*coalesce(v_cost6,0);
  v_return_loss:=v_return500*coalesce(v_cost500,0)/24+v_return15*coalesce(v_cost15,0)/12+v_return6*coalesce(v_cost6,0);
  v_production_labor:=v_labor500+v_labor15+v_labor6;
  v_profit_products:=v_product_revenue-v_product_cogs-v_return_loss-v_production_labor-v_support_labor-v_exp_products-v_fill_water_used*coalesce(v_fill_water_rate,0)-(v_shop_water_used-v_counter_litres)*coalesce(v_shop_water_rate,0);
  v_net:=v_profit19+v_profit_products+v_other_income+v_interest_income-v_exp_general-v_interest_expense-v_depreciation-v_inventory_loss;

  if v_used_water>0 and v_water_per_litre is null then v_missing:=array_append(v_missing,'ٹینکر خریداری'); end if;
  if v_bottles+v_caps>0 and v_cap19 is null then v_missing:=array_append(v_missing,'19L ڈھکن خریداری'); end if;
  if v_sold500+v_return500>0 and v_cost500 is null then v_missing:=array_append(v_missing,'500ml خام مال / پیکنگ'); end if;
  if v_sold15+v_return15>0 and v_cost15 is null then v_missing:=array_append(v_missing,'1.5L خام مال / پیکنگ'); end if;
  if v_sold6+v_return6>0 and v_cost6 is null then v_missing:=array_append(v_missing,'6L بوتل'); end if;
  if v_fill_water_used>0 and v_fill_water_rate is null then v_missing:=array_append(v_missing,'500ml / 1.5L فلنگ پانی کی خریداری یا ابتدائی اسٹاک'); end if;
  if v_shop_water_used>0 and v_shop_water_rate is null then v_missing:=array_append(v_missing,'6L / کاؤنٹر پانی کی خریداری یا ابتدائی اسٹاک'); end if;


  select exists(
    select 1 from public.customer_19l_deliveries where delivery_date between p_month_start and p_month_end
    union all select 1 from public.counter_water_sales where sale_date between p_month_start and p_month_end
    union all select 1 from public.product_sales where sale_date between p_month_start and p_month_end
    union all select 1 from public.product_returns where return_date between p_month_start and p_month_end
    union all select 1 from public.business_expenses where expense_date between p_month_start and p_month_end
    union all select 1 from public.business_income where income_date between p_month_start and p_month_end
    union all select 1 from public.production where production_date between p_month_start and p_month_end
    union all select 1 from public.raw_material_purchases where purchase_date between p_month_start and p_month_end
    union all select 1 from public.water_tanker_purchases where purchase_date between p_month_start and p_month_end
    union all select 1 from public.water_opening_stock where as_of_date between p_month_start and p_month_end
    union all select 1 from public.business_finance_ledger where entry_date between p_month_start and p_month_end
    union all select 1 from public.worker_ledger where entry_date between p_month_start and p_month_end
  ) into v_has_activity;
  select exists(
    select 1 from public.customer_19l_deliveries where delivery_date between p_month_start and p_month_end
    union all select 1 from public.counter_water_sales where sale_date between p_month_start and p_month_end
    union all select 1 from public.product_sales where sale_date between p_month_start and p_month_end
    union all select 1 from public.product_returns where return_date between p_month_start and p_month_end
    union all select 1 from public.business_expenses where expense_date between p_month_start and p_month_end
    union all select 1 from public.business_income where income_date between p_month_start and p_month_end
    union all select 1 from public.production where production_date between p_month_start and p_month_end
    union all select 1 from public.worker_ledger where entry_date between p_month_start and p_month_end and entry_type='earning'
    union all select 1 from public.business_finance_ledger where entry_date between p_month_start and p_month_end
      and entry_type in ('interest_income','interest_expense','depreciation_expense','inventory_loss')
  ) into v_has_pnl_activity;

  select jsonb_build_object(
    'water_litres',coalesce((select sum(tanker_count*1000) from public.water_tanker_purchases where purchase_date<=p_month_end),0)
      +coalesce((select sum(litres) from public.water_opening_stock where as_of_date<=p_month_end),0)
      -(coalesce((select sum(bottles_delivered) from public.customer_19l_deliveries where delivery_date<=p_month_end),0)*19
        +coalesce((select sum(total_litres) from public.counter_water_sales where sale_date<=p_month_end),0)
        +coalesce((select sum(quantity*CASE product_type WHEN '500ml' THEN 12 WHEN '1.5L' THEN 18 ELSE 0 END) from public.production where production_date<=p_month_end),0)
        +coalesce((select sum(quantity*6) from public.production where product_type='6L' and production_date<=p_month_end),0)),
    
    'water_shop_pool_litres',
      coalesce((select sum(tanker_count*1000) from public.water_tanker_purchases where purchase_date<=p_month_end and water_use='shop_counter'),0)
      +coalesce((select sum(litres) from public.water_opening_stock where as_of_date<=p_month_end and water_use='shop_counter'),0)
      -(coalesce((select sum(bottles_delivered)*19 from public.customer_19l_deliveries where delivery_date<=p_month_end),0)
        +coalesce((select sum(total_litres) from public.counter_water_sales where sale_date<=p_month_end),0)
        +coalesce((select sum(quantity*6) from public.production where product_type='6L' and production_date<=p_month_end),0)),
    'water_product_filling_litres',
      coalesce((select sum(tanker_count*1000) from public.water_tanker_purchases where purchase_date<=p_month_end and water_use='product_filling'),0)
      +coalesce((select sum(litres) from public.water_opening_stock where as_of_date<=p_month_end and water_use='product_filling'),0)
      -coalesce((select sum(quantity*case product_type when '500ml' then 12 when '1.5L' then 18 else 0 end) from public.production where production_date<=p_month_end),0),
    'water_shop_pool_remaining_litres',
      coalesce((select sum(tanker_count*1000) from public.water_tanker_purchases where purchase_date<=p_month_end and water_use='shop_counter'),0)
      +coalesce((select sum(litres) from public.water_opening_stock where as_of_date<=p_month_end and water_use='shop_counter'),0)
      -coalesce((select sum(bottles_delivered)*19 from public.customer_19l_deliveries where delivery_date<=p_month_end),0)
      -coalesce((select sum(total_litres) from public.counter_water_sales where sale_date<=p_month_end),0)
      -coalesce((select sum(quantity*6) from public.production where product_type='6L' and production_date<=p_month_end),0),
    'raw_19l_caps',
      coalesce((select sum(quantity) from public.raw_material_purchases where material_type='cap_19l' and purchase_date<=p_month_end),0)
      -coalesce((select sum(bottles_delivered+damaged_caps) from public.customer_19l_deliveries where delivery_date<=p_month_end),0),
'raw_500ml_bottles',coalesce((select sum(quantity) from public.raw_material_purchases where material_type='bottle_500ml' and purchase_date<=p_month_end),0)
      -coalesce((select sum(quantity) from public.production where product_type='500ml' and production_date<=p_month_end),0)*24,
    'raw_1_5l_bottles',coalesce((select sum(quantity) from public.raw_material_purchases where material_type='bottle_1_5l' and purchase_date<=p_month_end),0)
      -coalesce((select sum(quantity) from public.production where product_type='1.5L' and production_date<=p_month_end),0)*12,
    'raw_6l_bottles',coalesce((select sum(quantity) from public.raw_material_purchases where material_type='bottle_6l' and purchase_date<=p_month_end),0)
      -coalesce((select sum(quantity) from public.production where product_type='6L' and production_date<=p_month_end),0),
    'cartons_500ml',coalesce((select sum(quantity) from public.raw_material_purchases where material_type='carton_500ml' and purchase_date<=p_month_end),0)
      -coalesce((select sum(quantity) from public.production where product_type='500ml' and production_date<=p_month_end),0),
    'cartons_1_5l',coalesce((select sum(quantity) from public.raw_material_purchases where material_type='carton_1_5l' and purchase_date<=p_month_end),0)
      -coalesce((select sum(quantity) from public.production where product_type='1.5L' and production_date<=p_month_end),0),
    'tape_bundles',coalesce((select sum(quantity) from public.raw_material_purchases where material_type='tape_bundle' and purchase_date<=p_month_end),0)
      -(coalesce((select sum(quantity) from public.production where product_type='500ml' and production_date<=p_month_end),0)
        +coalesce((select sum(quantity) from public.production where product_type='1.5L' and production_date<=p_month_end),0))/200,
    'stickers',coalesce((select sum(quantity) from public.raw_material_purchases where material_type='sticker' and purchase_date<=p_month_end),0)
      -(coalesce((select sum(quantity) from public.production where product_type='500ml' and production_date<=p_month_end),0)*24
        +coalesce((select sum(quantity) from public.production where product_type='1.5L' and production_date<=p_month_end),0)*12
        +coalesce((select sum(quantity) from public.production where product_type='6L' and production_date<=p_month_end),0)),
    'finished_500ml_cartons',coalesce((select sum(quantity) from public.finished_goods where product_type='500ml' and unit='carton' and entry_date<=p_month_end),0)
      +coalesce((select sum(quantity) from public.production where product_type='500ml' and production_date<=p_month_end),0)
      -coalesce((select sum(quantity) from public.product_sales where product_type='500ml' and sale_date<=p_month_end),0)
      -coalesce((select sum(replacement_quantity) from public.product_returns where product_type='500ml' and return_date<=p_month_end),0)/24
      +coalesce((select sum(case when adjustment_type='increase' then quantity when adjustment_type='decrease' then -quantity else 0 end) from public.finished_stock_adjustments where product_type='500ml' and adjustment_date<=p_month_end),0),
    'finished_1_5l_cartons',coalesce((select sum(quantity) from public.finished_goods where product_type='1.5L' and unit='carton' and entry_date<=p_month_end),0)
      +coalesce((select sum(quantity) from public.production where product_type='1.5L' and production_date<=p_month_end),0)
      -coalesce((select sum(quantity) from public.product_sales where product_type='1.5L' and sale_date<=p_month_end),0)
      -coalesce((select sum(replacement_quantity) from public.product_returns where product_type='1.5L' and return_date<=p_month_end),0)/12
      +coalesce((select sum(case when adjustment_type='increase' then quantity when adjustment_type='decrease' then -quantity else 0 end) from public.finished_stock_adjustments where product_type='1.5L' and adjustment_date<=p_month_end),0),
    'finished_6l_bottles',coalesce((select sum(quantity) from public.finished_goods where product_type='6L' and unit='bottle' and entry_date<=p_month_end),0)
      +coalesce((select sum(quantity) from public.production where product_type='6L' and production_date<=p_month_end),0)
      -coalesce((select sum(quantity) from public.product_sales where product_type='6L' and sale_date<=p_month_end),0)
      -coalesce((select sum(replacement_quantity) from public.product_returns where product_type='6L' and return_date<=p_month_end),0)
      +coalesce((select sum(case when adjustment_type='increase' then quantity when adjustment_type='decrease' then -quantity else 0 end) from public.finished_stock_adjustments where product_type='6L' and adjustment_date<=p_month_end),0)
  ) into v_stock;

  return jsonb_build_object(
    'month_start',p_month_start,'month_end',p_month_end,'generated_at',now(),
    'has_activity',v_has_activity,'has_pnl_activity',v_has_pnl_activity,'complete',cardinality(v_missing)=0,'missing_costs',to_jsonb(v_missing),
    'segments',jsonb_build_object(
      '19L',jsonb_build_object('revenue',v_revenue19,'water_cost',v_water_cost,'water_rate_per_litre',v_water_per_litre,'cap_cost',v_cap_cost,
        'delivery_labor',v_delivery_labor,'segment_expenses',v_exp19,'profit_before_shared',v_profit19),
      'finished_goods',jsonb_build_object('revenue',v_product_revenue,'material_packaging_cost',v_product_cogs,'filling_water_litres',v_fill_water_used,'filling_water_cost',v_fill_water_used*coalesce(v_fill_water_rate,0),'shop_water_cost_for_6l',(v_shop_water_used-v_counter_litres)*coalesce(v_shop_water_rate,0),
        'replacement_loss',v_return_loss,'production_labor',v_production_labor,'support_labor',v_support_labor,
        'segment_expenses',v_exp_products,'profit_before_shared',v_profit_products),
      'shared',jsonb_build_object('general_expenses',v_exp_general,'interest_expense',v_interest_expense,
        'depreciation',v_depreciation,'inventory_loss',v_inventory_loss,'other_income',v_other_income+v_interest_income),
      'net_profit',v_net
    ),
    'products',jsonb_build_object(
      '500ml',jsonb_build_object('revenue',v_rev500,'quantity',v_sold500,'unit_cost',v_cost500,
        'material_cost',v_sold500*coalesce(v_cost500,0),'returns',v_return500,'return_loss',v_return500*coalesce(v_cost500,0)/24,'production_labor',v_labor500),
      '1.5L',jsonb_build_object('revenue',v_rev15,'quantity',v_sold15,'unit_cost',v_cost15,
        'material_cost',v_sold15*coalesce(v_cost15,0),'returns',v_return15,'return_loss',v_return15*coalesce(v_cost15,0)/12,'production_labor',v_labor15),
      '6L',jsonb_build_object('revenue',v_rev6,'quantity',v_sold6,'unit_cost',v_cost6,
        'material_cost',v_sold6*coalesce(v_cost6,0),'returns',v_return6,'return_loss',v_return6*coalesce(v_cost6,0),'production_labor',v_labor6)
    ),
    'owner_withdrawals',jsonb_build_object(
      'M.Usama Mughal',v_owner1,'M. Muzamil Mughal',v_owner2,'M.Taqi Mughal',v_owner3,'M. Rafi Mughal',v_owner4,
      'total',v_owner1+v_owner2+v_owner3+v_owner4),
    'capital_and_loans',jsonb_build_object('capital',v_capital,'loan_received',v_loan_received,
      'loan_repaid',v_loan_repaid,'loan_balance',v_loan_received-v_loan_repaid,
      'loan_given',v_loan_given,'loan_collected',v_loan_collected,'receivable_balance',v_loan_given-v_loan_collected),
    'purchases',jsonb_build_object('raw_material_period',v_raw_purchase_period,'water_tanker_period',v_tanker_purchase_period),
    'stock_estimate',v_stock,
    'notes','اسٹاک کا اندازہ کلیم کے بدلے مفت آنے والی بوتلوں کے بغیر ہے؛ ان کی مقدار درج نہ ہونے سے خام مال کا اسٹاک اندازاً ہوگا۔'
  );
end;
$function$
;

comment on function private.mpw_guard_operational_stock() is 'Validates physical water and 19L cap usage from all bottles delivered; successful_bottles remains the exchange/billing count.';
