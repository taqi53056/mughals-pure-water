-- Align all shop-water stock guards with daily totals that already include 19L deliveries.
begin;

do $repair$
declare
  v_def text;
  v_old text;
  v_new text;
begin
  -- Operational stock trigger: daily total replaces individual 19L deductions
  -- on dates where a daily-total row exists.
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='private' and p.proname='mpw_guard_operational_stock';
  v_new:=v_def;

  v_old:=$x$v_pool text;$x$;
  if position(v_old in v_new)=0 then raise exception 'Operational guard declaration anchor missing'; end if;
  v_new:=replace(v_new,v_old,$x$v_pool text;
  v_daily_total numeric:=0;
  v_daily_required numeric:=0;$x$);

  v_old:=$x$  perform pg_advisory_xact_lock(hashtextextended(
    case when v_pool='shop_counter' then 'water-pool-shop' else 'water-pool-filling' end,0));

  for v_event_date in$x$;
  if position(v_old in v_new)=0 then raise exception 'Operational guard lock anchor missing'; end if;
  v_new:=replace(v_new,v_old,$x$  perform pg_advisory_xact_lock(hashtextextended(
    case when v_pool='shop_counter' then 'water-pool-shop' else 'water-pool-filling' end,0));

  if tg_table_name in ('customer_19l_deliveries','unassigned_19l_deliveries')
     and exists(select 1 from public.counter_water_sales c where c.sale_date=v_date) then
    select c.total_litres,
      coalesce((select sum(d.bottles_delivered*19)
        from public.customer_19l_deliveries d
        where d.delivery_date=v_date
          and (tg_table_name<>'customer_19l_deliveries' or v_old_id is null or d.id is distinct from v_old_id)),0)
      + coalesce((select sum(d.bottles_delivered*19)
        from public.unassigned_19l_deliveries d
        where d.delivery_date=v_date
          and (tg_table_name<>'unassigned_19l_deliveries' or v_old_id is null or d.id is distinct from v_old_id)),0)
      + v_required
    into v_daily_total,v_daily_required
    from public.counter_water_sales c
    where c.sale_date=v_date;
    if v_daily_total<v_daily_required then
      raise exception 'روزانہ کل پانی (% لیٹر) اسی تاریخ کی 19L سپلائی (% لیٹر) سے کم ہے۔ پہلے روزانہ پانی کا کل درست کریں۔',v_daily_total,v_daily_required
        using errcode='23514';
    end if;
  end if;

  for v_event_date in$x$);

  v_old:=$x$select
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
      into v_consumed;$x$;
  if position(v_old in v_new)=0 then raise exception 'Operational guard consumption query missing'; end if;
  v_new:=replace(v_new,v_old,$x$select
        coalesce((select sum(d.bottles_delivered*19)
          from public.customer_19l_deliveries d
          where d.delivery_date<=v_event_date
            and not (tg_table_name='counter_water_sales' and d.delivery_date=v_date)
            and not exists(select 1 from public.counter_water_sales c
              where c.sale_date=d.delivery_date
                and (tg_table_name<>'counter_water_sales' or v_old_id is null or c.id is distinct from v_old_id))
            and (tg_table_name<>'customer_19l_deliveries' or v_old_id is null or d.id is distinct from v_old_id)),0)
        + coalesce((select sum(d.bottles_delivered*19)
          from public.unassigned_19l_deliveries d
          where d.delivery_date<=v_event_date
            and not (tg_table_name='counter_water_sales' and d.delivery_date=v_date)
            and not exists(select 1 from public.counter_water_sales c
              where c.sale_date=d.delivery_date
                and (tg_table_name<>'counter_water_sales' or v_old_id is null or c.id is distinct from v_old_id))
            and (tg_table_name<>'unassigned_19l_deliveries' or v_old_id is null or d.id is distinct from v_old_id)),0)
        + coalesce((select sum(c.total_litres)
          from public.counter_water_sales c
          where c.sale_date<=v_event_date
            and (tg_table_name<>'counter_water_sales' or v_old_id is null or c.id is distinct from v_old_id)),0)
        + coalesce((select sum(p.quantity*6)
          from public.production p
          where p.product_type='6L' and p.production_date<=v_event_date
            and (tg_table_name<>'production' or v_old_id is null or p.id is distinct from v_old_id)),0)
      into v_consumed;$x$);

  v_old:=$x$    if v_date<=v_event_date then
      v_consumed:=v_consumed+v_required;
    end if;$x$;
  if position(v_old in v_new)=0 then raise exception 'Operational guard required-quantity anchor missing'; end if;
  v_new:=replace(v_new,v_old,$x$    if v_date<=v_event_date
       and not (tg_table_name in ('customer_19l_deliveries','unassigned_19l_deliveries')
         and exists(select 1 from public.counter_water_sales c where c.sale_date=v_date)) then
      v_consumed:=v_consumed+v_required;
    end if;$x$);
  execute v_new;

  -- Source-stock guards: count daily total once; count 19L deliveries separately
  -- only for dates that have no daily-total record.
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='private' and p.proname='mpw_guard_shop_water_full_balance';
  v_new:=v_def;
  v_old:=$x$FROM public.customer_19l_deliveries d WHERE d.delivery_date<=v_event_date),0)$x$;
  if position(v_old in v_new)=0 then raise exception 'Full-balance customer usage anchor missing'; end if;
  v_new:=replace(v_new,v_old,$x$FROM public.customer_19l_deliveries d WHERE d.delivery_date<=v_event_date
          AND NOT EXISTS(SELECT 1 FROM public.counter_water_sales c WHERE c.sale_date=d.delivery_date)),0)$x$);
  v_old:=$x$FROM public.unassigned_19l_deliveries d WHERE d.delivery_date<=v_event_date),0)$x$;
  if position(v_old in v_new)=0 then raise exception 'Full-balance unassigned usage anchor missing'; end if;
  v_new:=replace(v_new,v_old,$x$FROM public.unassigned_19l_deliveries d WHERE d.delivery_date<=v_event_date
          AND NOT EXISTS(SELECT 1 FROM public.counter_water_sales c WHERE c.sale_date=d.delivery_date)),0)$x$);
  execute v_new;

  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='private' and p.proname='mpw_guard_water_opening_stock';
  v_new:=v_def;
  v_old:=$x$       OR EXISTS (SELECT 1 FROM public.counter_water_sales
        WHERE sale_date<NEW.as_of_date)$x$;
  if position(v_old in v_new)=0 then raise exception 'Opening-stock prior-activity anchor missing'; end if;
  v_new:=replace(v_new,v_old,$x$       OR EXISTS (SELECT 1 FROM public.unassigned_19l_deliveries
        WHERE delivery_date<NEW.as_of_date)
       OR EXISTS (SELECT 1 FROM public.counter_water_sales
        WHERE sale_date<NEW.as_of_date)$x$);
  v_old:=$x$        SELECT d.delivery_date AS event_date FROM public.customer_19l_deliveries d
        UNION ALL SELECT c.sale_date FROM public.counter_water_sales c$x$;
  if position(v_old in v_new)=0 then raise exception 'Opening-stock event-date anchor missing'; end if;
  v_new:=replace(v_new,v_old,$x$        SELECT d.delivery_date AS event_date FROM public.customer_19l_deliveries d
        UNION ALL SELECT d.delivery_date FROM public.unassigned_19l_deliveries d
        UNION ALL SELECT c.sale_date FROM public.counter_water_sales c$x$);
  v_old:=$x$COALESCE((SELECT sum(d.bottles_delivered*19) FROM public.customer_19l_deliveries d
          WHERE d.delivery_date<=v_event_date),0)
        + COALESCE((SELECT sum(c.total_litres) FROM public.counter_water_sales c
          WHERE c.sale_date<=v_event_date),0)$x$;
  if position(v_old in v_new)=0 then raise exception 'Opening-stock consumption anchor missing'; end if;
  v_new:=replace(v_new,v_old,$x$COALESCE((SELECT sum(d.bottles_delivered*19) FROM public.customer_19l_deliveries d
          WHERE d.delivery_date<=v_event_date
            AND NOT EXISTS(SELECT 1 FROM public.counter_water_sales c WHERE c.sale_date=d.delivery_date)),0)
        + COALESCE((SELECT sum(d.bottles_delivered*19) FROM public.unassigned_19l_deliveries d
          WHERE d.delivery_date<=v_event_date
            AND NOT EXISTS(SELECT 1 FROM public.counter_water_sales c WHERE c.sale_date=d.delivery_date)),0)
        + COALESCE((SELECT sum(c.total_litres) FROM public.counter_water_sales c
          WHERE c.sale_date<=v_event_date),0)$x$);
  execute v_new;

  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='private' and p.proname='mpw_guard_water_tanker_purchase_update';
  v_new:=v_def;
  v_old:=$x$        select d.delivery_date as event_date from public.customer_19l_deliveries d
        union all select c.sale_date from public.counter_water_sales c$x$;
  if position(v_old in v_new)=0 then raise exception 'Tanker-update event-date anchor missing'; end if;
  v_new:=replace(v_new,v_old,$x$        select d.delivery_date as event_date from public.customer_19l_deliveries d
        union all select d.delivery_date from public.unassigned_19l_deliveries d
        union all select c.sale_date from public.counter_water_sales c$x$);
  v_old:=$x$coalesce((select sum(d.bottles_delivered*19) from public.customer_19l_deliveries d
          where d.delivery_date<=v_event_date),0)
        + coalesce((select sum(c.total_litres) from public.counter_water_sales c
          where c.sale_date<=v_event_date),0)$x$;
  if position(v_old in v_new)=0 then raise exception 'Tanker-update consumption anchor missing'; end if;
  v_new:=replace(v_new,v_old,$x$coalesce((select sum(d.bottles_delivered*19) from public.customer_19l_deliveries d
          where d.delivery_date<=v_event_date
            and not exists(select 1 from public.counter_water_sales c where c.sale_date=d.delivery_date)),0)
        + coalesce((select sum(d.bottles_delivered*19) from public.unassigned_19l_deliveries d
          where d.delivery_date<=v_event_date
            and not exists(select 1 from public.counter_water_sales c where c.sale_date=d.delivery_date)),0)
        + coalesce((select sum(c.total_litres) from public.counter_water_sales c
          where c.sale_date<=v_event_date),0)$x$);
  execute v_new;

  -- 6L production uses the same shop pool, while 19L delivery litres are already
  -- contained in the daily-total record on dates where that record exists.
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='private' and p.proname='record_production_with_workers';
  v_new:=v_def;
  v_old:=$x$      coalesce((SELECT sum(bottles_delivered*19) FROM public.customer_19l_deliveries
        WHERE delivery_date<=p_production_date),0)
      +coalesce((SELECT sum(total_litres) FROM public.counter_water_sales
        WHERE sale_date<=p_production_date),0)$x$;
  if position(v_old in v_new)=0 then raise exception 'Production shop-water anchor missing'; end if;
  v_new:=replace(v_new,v_old,$x$      coalesce((SELECT sum(d.bottles_delivered*19) FROM public.customer_19l_deliveries d
        WHERE d.delivery_date<=p_production_date
          AND NOT EXISTS(SELECT 1 FROM public.counter_water_sales c WHERE c.sale_date=d.delivery_date)),0)
      +coalesce((SELECT sum(d.bottles_delivered*19) FROM public.unassigned_19l_deliveries d
        WHERE d.delivery_date<=p_production_date
          AND NOT EXISTS(SELECT 1 FROM public.counter_water_sales c WHERE c.sale_date=d.delivery_date)),0)
      +coalesce((SELECT sum(total_litres) FROM public.counter_water_sales
        WHERE sale_date<=p_production_date),0)$x$);
  execute v_new;

  -- Unassigned-delivery RPC follows the same daily-total rule and validates that
  -- a pre-entered daily total is large enough to include this new delivery.
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='private' and p.proname='record_unassigned_19l_delivery';
  v_new:=v_def;
  v_old:=$x$v_worker public.workers%rowtype; v_labor_amount numeric:=0;$x$;
  if position(v_old in v_new)=0 then raise exception 'Unassigned RPC declarations anchor missing'; end if;
  v_new:=replace(v_new,v_old,$x$v_worker public.workers%rowtype; v_labor_amount numeric:=0;
 v_daily_total numeric:=0; v_daily_required numeric:=0; v_required numeric:=0;$x$);

  v_old:=$x$ select coalesce((select sum(bottles_delivered*19) from public.customer_19l_deliveries where delivery_date<=p_delivery_date),0)+coalesce((select sum(total_litres) from public.counter_water_sales where sale_date<=p_delivery_date),0)+coalesce((select sum(quantity*6) from public.production where product_type='6L' and production_date<=p_delivery_date),0)+coalesce((select sum(bottles_delivered*19) from public.unassigned_19l_deliveries where delivery_date<=p_delivery_date),0) into v_consumed;
 if v_available-v_consumed<p_bottles_delivered*19 then raise exception 'دکان والی ٹنکی کا پانی ناکافی ہے۔ دستیاب لیٹر: %، درکار: %',greatest(v_available-v_consumed,0),p_bottles_delivered*19 using errcode='23514'; end if;$x$;
  if position(v_old in v_new)=0 then raise exception 'Unassigned RPC consumption anchor missing'; end if;
  v_new:=replace(v_new,v_old,$x$ select
   coalesce((select sum(d.bottles_delivered*19) from public.customer_19l_deliveries d
     where d.delivery_date<=p_delivery_date
       and not exists(select 1 from public.counter_water_sales c where c.sale_date=d.delivery_date)),0)
   +coalesce((select sum(d.bottles_delivered*19) from public.unassigned_19l_deliveries d
     where d.delivery_date<=p_delivery_date
       and not exists(select 1 from public.counter_water_sales c where c.sale_date=d.delivery_date)),0)
   +coalesce((select sum(c.total_litres) from public.counter_water_sales c where c.sale_date<=p_delivery_date),0)
   +coalesce((select sum(p.quantity*6) from public.production p where p.product_type='6L' and p.production_date<=p_delivery_date),0)
  into v_consumed;
  if exists(select 1 from public.counter_water_sales c where c.sale_date=p_delivery_date) then
    select c.total_litres,
      coalesce((select sum(d.bottles_delivered*19) from public.customer_19l_deliveries d where d.delivery_date=p_delivery_date),0)
      +coalesce((select sum(d.bottles_delivered*19) from public.unassigned_19l_deliveries d where d.delivery_date=p_delivery_date),0)
      +p_bottles_delivered*19
    into v_daily_total,v_daily_required
    from public.counter_water_sales c where c.sale_date=p_delivery_date;
    if v_daily_total<v_daily_required then
      raise exception 'روزانہ کل پانی (% لیٹر) 19L سپلائی (% لیٹر) کو شامل کرنے کے لیے کافی نہیں۔',v_daily_total,v_daily_required
        using errcode='23514';
    end if;
  else
    v_required:=p_bottles_delivered*19;
  end if;
  if v_available-v_consumed<v_required then
    raise exception 'دکان والی ٹنکی کا پانی ناکافی ہے۔ دستیاب لیٹر: %، درکار: %',greatest(v_available-v_consumed,0),v_required
      using errcode='23514';
  end if;$x$);
  execute v_new;
end
$repair$;

commit;