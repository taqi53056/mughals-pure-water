create or replace function private.mpw_shop_water_balance_as_of(p_as_of date)
returns numeric
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_measured_at timestamptz;
  v_measured_litres numeric;
  v_measure_date date;
  v_inflow numeric;
  v_outflow numeric;
begin
  if p_as_of is null then
    raise exception 'پانی کے بیلنس کے لیے تاریخ درکار ہے۔' using errcode='22023';
  end if;

  select m.measured_at,m.measured_litres
    into v_measured_at,v_measured_litres
  from public.water_tank_measurements m
  where m.tank_code='shop_counter'
    and (m.measured_at at time zone 'Asia/Karachi')::date <= p_as_of
  order by m.measured_at desc,m.id desc
  limit 1;

  if v_measured_at is null then
    return
      coalesce((select sum(t.tanker_count*1000)
        from public.water_tanker_purchases t
        where t.water_use='shop_counter' and t.purchase_date<=p_as_of),0)
      +coalesce((select sum(s.litres)
        from public.water_opening_stock s
        where s.water_use='shop_counter' and s.as_of_date<=p_as_of),0)
      -coalesce((select sum(d.bottles_delivered*19)
        from public.customer_19l_deliveries d where d.delivery_date<=p_as_of),0)
      -coalesce((select sum(d.bottles_delivered*19)
        from public.unassigned_19l_deliveries d where d.delivery_date<=p_as_of),0)
      -coalesce((select sum(private.mpw_counter_water_litres(c.sale_date,c.total_litres,c.counter_water_litres))
        from public.counter_water_sales c where c.sale_date<=p_as_of),0)
      -coalesce((select sum(p.quantity*6)
        from public.production p where p.product_type='6L' and p.production_date<=p_as_of),0);
  end if;

  v_measure_date := (v_measured_at at time zone 'Asia/Karachi')::date;

  select coalesce(sum(t.tanker_count*1000),0)
    into v_inflow
  from public.water_tanker_purchases t
  where t.water_use='shop_counter'
    and t.purchase_date<=p_as_of
    and (t.purchase_date>v_measure_date
      or (t.purchase_date=v_measure_date and t.created_at>v_measured_at));

  select
    coalesce((select sum(d.bottles_delivered*19)
      from public.customer_19l_deliveries d
      where d.delivery_date<=p_as_of
        and (d.delivery_date>v_measure_date
          or (d.delivery_date=v_measure_date and d.created_at>v_measured_at))),0)
    +coalesce((select sum(d.bottles_delivered*19)
      from public.unassigned_19l_deliveries d
      where d.delivery_date<=p_as_of
        and (d.delivery_date>v_measure_date
          or (d.delivery_date=v_measure_date and d.created_at>v_measured_at))),0)
    +coalesce((select sum(private.mpw_counter_water_litres(c.sale_date,c.total_litres,c.counter_water_litres))
      from public.counter_water_sales c
      where c.sale_date<=p_as_of
        and (c.sale_date>v_measure_date
          or (c.sale_date=v_measure_date and c.created_at>v_measured_at))),0)
    +coalesce((select sum(p.quantity*6)
      from public.production p
      where p.product_type='6L' and p.production_date<=p_as_of
        and (p.production_date>v_measure_date
          or (p.production_date=v_measure_date and p.created_at>v_measured_at))),0)
  into v_outflow;

  return v_measured_litres+coalesce(v_inflow,0)-coalesce(v_outflow,0);
end;
$$;

alter function public.build_business_monthly_report(date,date)
  rename to build_business_monthly_report_legacy;

create or replace function public.build_business_monthly_report(p_month_start date,p_month_end date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_report jsonb;
  v_shop_balance numeric;
  v_fill_balance numeric;
  v_total_water numeric;
begin
  v_report:=public.build_business_monthly_report_legacy(p_month_start,p_month_end);
  v_shop_balance:=private.mpw_shop_water_balance_as_of(p_month_end);
  v_fill_balance:=coalesce((v_report #>> '{stock_estimate,water_product_filling_litres}')::numeric,0);
  v_total_water:=v_shop_balance+v_fill_balance;

  v_report:=jsonb_set(v_report,'{stock_estimate,water_shop_pool_litres}',to_jsonb(v_shop_balance),true);
  v_report:=jsonb_set(v_report,'{stock_estimate,water_shop_pool_remaining_litres}',to_jsonb(v_shop_balance),true);
  v_report:=jsonb_set(v_report,'{stock_estimate,water_litres}',to_jsonb(v_total_water),true);
  v_report:=jsonb_set(v_report,'{stock_estimate,water_shop_pool_remaining_litres_is_estimate}',to_jsonb(true),true);
  v_report:=jsonb_set(v_report,'{water_litres}',to_jsonb(v_total_water),true);

  return v_report;
end;
$$;

revoke all on function public.build_business_monthly_report(date,date) from public,anon,authenticated,service_role;
revoke all on function private.mpw_shop_water_balance_as_of(date) from public,anon,authenticated,service_role;

comment on function public.build_business_monthly_report(date,date) is
'Builds the monthly business report and reconciles shop-water stock estimates to the latest physical measurement as of month end. P&L cost rates remain based on historical purchase/opening-stock values.';