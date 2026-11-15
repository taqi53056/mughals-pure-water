begin;
do $repair$
declare
 v_def text;
 v_old text;
 v_new text;
begin
 select pg_get_functiondef(p.oid) into v_def
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='private' and p.proname='mpw_guard_operational_stock';
 v_new:=v_def;
 v_old:=$old$  if tg_table_name in ('customer_19l_deliveries','unassigned_19l_deliveries')
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
  end if;$old$;
 if position(v_old in v_new)=0 then
   if position('if tg_table_name=''counter_water_sales'' then' in v_new)>0 then
     raise notice 'Daily-total validation already present';
   else
     raise exception 'Operational guard validation block changed unexpectedly';
   end if;
 else
   v_new:=replace(v_new,v_old,$new$  if tg_table_name='counter_water_sales' then
    select
      coalesce((select sum(d.bottles_delivered*19)
        from public.customer_19l_deliveries d where d.delivery_date=v_date),0)
      +coalesce((select sum(d.bottles_delivered*19)
        from public.unassigned_19l_deliveries d where d.delivery_date=v_date),0)
    into v_daily_required;
    v_daily_total:=v_required;
    if v_daily_total<v_daily_required then
      raise exception 'روزانہ کل پانی (% لیٹر) اسی تاریخ کی 19L سپلائی (% لیٹر) سے کم ہے۔',v_daily_total,v_daily_required
        using errcode='23514';
    end if;
  elsif tg_table_name in ('customer_19l_deliveries','unassigned_19l_deliveries')
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
  end if;$new$);
   execute v_new;
 end if;
end
$repair$;
commit;