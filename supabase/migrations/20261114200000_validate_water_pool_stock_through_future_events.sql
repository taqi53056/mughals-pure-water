-- Validate both physical water pools chronologically for every operational write.
-- Include unassigned 19L deliveries in the shop-counter water pool.
create or replace function private.mpw_guard_operational_stock()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare
  v_date date;
  v_event_date date;
  v_available numeric := 0;
  v_consumed numeric := 0;
  v_required numeric := 0;
  v_old_id bigint := null;
  v_pool text;
begin
  if tg_table_name not in
    ('customer_19l_deliveries','unassigned_19l_deliveries',
     'counter_water_sales','production') then
    return new;
  end if;

  if tg_op='UPDATE' then
    v_old_id:=old.id;
  end if;

  if tg_table_name='customer_19l_deliveries' then
    v_date:=new.delivery_date;
    v_required:=coalesce(new.bottles_delivered,0)*19;
    v_pool:='shop_counter';
  elsif tg_table_name='unassigned_19l_deliveries' then
    v_date:=new.delivery_date;
    v_required:=coalesce(new.bottles_delivered,0)*19;
    v_pool:='shop_counter';
  elsif tg_table_name='counter_water_sales' then
    v_date:=new.sale_date;
    v_required:=coalesce(new.total_litres,0);
    v_pool:='shop_counter';
  else
    if new.production_date>(now() at time zone 'Asia/Karachi')::date then
      raise exception 'مستقبل کی تاریخ پر پروڈکشن درج نہیں ہو سکتی۔'
        using errcode='22023';
    end if;
    v_date:=new.production_date;
    if new.product_type='6L' then
      v_required:=coalesce(new.quantity,0)*6;
      v_pool:='shop_counter';
    elsif new.product_type in ('500ml','1.5L') then
      v_required:=coalesce(new.quantity,0)*
        case new.product_type when '500ml' then 12 else 18 end;
      v_pool:='product_filling';
    else
      return new;
    end if;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    case when v_pool='shop_counter' then 'water-pool-shop' else 'water-pool-filling' end,0));

  for v_event_date in
    select distinct event_date
    from (
      select d.delivery_date event_date
      from public.customer_19l_deliveries d
      where v_pool='shop_counter'
        and (tg_table_name<>'customer_19l_deliveries' or v_old_id is null or d.id is distinct from v_old_id)
      union all
      select d.delivery_date
      from public.unassigned_19l_deliveries d
      where v_pool='shop_counter'
        and (tg_table_name<>'unassigned_19l_deliveries' or v_old_id is null or d.id is distinct from v_old_id)
      union all
      select c.sale_date
      from public.counter_water_sales c
      where v_pool='shop_counter'
        and (tg_table_name<>'counter_water_sales' or v_old_id is null or c.id is distinct from v_old_id)
      union all
      select p.production_date
      from public.production p
      where ((v_pool='shop_counter' and p.product_type='6L')
          or (v_pool='product_filling' and p.product_type in ('500ml','1.5L')))
        and (tg_table_name<>'production' or v_old_id is null or p.id is distinct from v_old_id)
      union all
      select v_date
    ) events
    where event_date is not null
    order by event_date
  loop
    if v_pool='shop_counter' then
      select
        coalesce((select sum(t.tanker_count*1000)
          from public.water_tanker_purchases t
          where t.water_use='shop_counter' and t.purchase_date<=v_event_date),0)
        + coalesce((select sum(w.litres)
          from public.water_opening_stock w
          where w.water_use='shop_counter' and w.as_of_date<=v_event_date),0)
      into v_available;

      select
        coalesce((select sum(d.bottles_delivered*19)
          from public.customer_19l_deliveries d
          where d.delivery_date<=v_event_date
            and (tg_table_name<>'customer_19l_deliveries' or v_old_id is null or d.id is distinct from v_old_id)),0)
        + coalesce((select sum(d.bottles_delivered*19)
          from public.unassigned_19l_deliveries d
          where d.delivery_date<=v_event_date
            and (tg_table_name<>'unassigned_19l_deliveries' or v_old_id is null or d.id is distinct from v_old_id)),0)
        + coalesce((select sum(c.total_litres)
          from public.counter_water_sales c
          where c.sale_date<=v_event_date
            and (tg_table_name<>'counter_water_sales' or v_old_id is null or c.id is distinct from v_old_id)),0)
        + coalesce((select sum(p.quantity*6)
          from public.production p
          where p.product_type='6L' and p.production_date<=v_event_date
            and (tg_table_name<>'production' or v_old_id is null or p.id is distinct from v_old_id)),0)
      into v_consumed;
    else
      select
        coalesce((select sum(t.tanker_count*1000)
          from public.water_tanker_purchases t
          where t.water_use='product_filling' and t.purchase_date<=v_event_date),0)
        + coalesce((select sum(w.litres)
          from public.water_opening_stock w
          where w.water_use='product_filling' and w.as_of_date<=v_event_date),0)
      into v_available;

      select coalesce(sum(p.quantity*
        case p.product_type when '500ml' then 12 else 18 end),0)
      into v_consumed
      from public.production p
      where p.product_type in ('500ml','1.5L')
        and p.production_date<=v_event_date
        and (tg_table_name<>'production' or v_old_id is null or p.id is distinct from v_old_id);
    end if;

    if v_date<=v_event_date then
      v_consumed:=v_consumed+v_required;
    end if;

    if v_available<v_consumed then
      raise exception
        'متعلقہ پانی کی ٹنکی کا اسٹاک بعد کی تاریخ پر منفی ہوگا۔ پول: %، تاریخ: %، دستیاب لیٹر: %، استعمال: %',
        v_pool,v_event_date,greatest(v_available,0),v_consumed
        using errcode='23514';
    end if;
  end loop;

  return new;
end;
$function$;

drop trigger if exists mpw_shop_water_stock_guard on public.unassigned_19l_deliveries;
create trigger mpw_shop_water_stock_guard
before insert or update of delivery_date,bottles_delivered
on public.unassigned_19l_deliveries
for each row execute function private.mpw_guard_operational_stock();
