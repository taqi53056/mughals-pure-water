create or replace function private.mpw_guard_operational_stock()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  v_date date;
  v_available numeric := 0;
  v_consumed numeric := 0;
  v_required numeric := 0;
  v_cutover_date date;
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
      + coalesce((select sum(bottles_delivered*19) from public.unassigned_19l_deliveries
        where delivery_date<=v_date),0)
    into v_consumed;
    if v_available-v_consumed<v_required then
      raise exception 'دکان والی ٹنکی کا پانی ناکافی ہے۔ دستیاب لیٹر: %، درکار: %',
        greatest(v_available-v_consumed,0),v_required using errcode='23514';
    end if;

    perform pg_advisory_xact_lock(hashtextextended('raw-material-cap-19l',0));
    select min(purchase_date) into v_cutover_date
    from public.raw_material_purchases
    where material_type='cap_19l' and record_type='opening_stock';
    select coalesce(sum(quantity),0) into v_available
    from public.raw_material_purchases
    where material_type='cap_19l' and purchase_date<=v_date
      and (v_cutover_date is null or v_date<v_cutover_date
        or record_type='opening_stock' or purchase_date>=v_cutover_date);
    select coalesce(sum(bottles_delivered+damaged_caps),0) into v_consumed
    from public.customer_19l_deliveries
    where delivery_date<=v_date and id is distinct from new.id
      and (v_cutover_date is null or v_date<v_cutover_date
          or delivery_date>=v_cutover_date);
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
      + coalesce((select sum(bottles_delivered*19) from public.unassigned_19l_deliveries
        where delivery_date<=v_date),0)
    into v_consumed;
    if v_available-v_consumed<v_required then
      raise exception 'دکان والی ٹنکی کا پانی ناکافی ہے۔ دستیاب لیٹر: %، درکار: %',
        greatest(v_available-v_consumed,0),v_required using errcode='23514';
    end if;
    return new;

  elsif tg_table_name = 'production' then
    if new.production_date>(now() at time zone 'Asia/Karachi')::date then
      raise exception 'مستقبل کی تاریخ پر پروڈکشن درج نہیں ہو سکتی۔'
        using errcode='22023';
    end if;
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
        + coalesce((select sum(bottles_delivered*19) from public.unassigned_19l_deliveries
          where delivery_date<=v_date),0)
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
$function$;