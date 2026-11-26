create or replace view public.shop_water_tank_current_balance
with (security_invoker=true)
as
with latest as (
  select m.id,m.tank_code,m.measured_at,m.measured_litres,m.ledger_litres,
         m.variance_litres,m.measurement_method,m.note,m.entered_by,m.created_at
  from public.water_tank_measurements m
  where m.tank_code='shop_counter'
  order by m.measured_at desc,m.id desc
  limit 1
),
flows as (
  select
    coalesce((
      select sum(t.tanker_count*1000::numeric)
      from public.water_tanker_purchases t
      cross join latest l
      where t.water_use='shop_counter'
        and (t.purchase_date>(l.measured_at at time zone 'Asia/Karachi')::date
          or (t.purchase_date=(l.measured_at at time zone 'Asia/Karachi')::date and t.created_at>l.measured_at))
    ),0::numeric) as inflow_litres,
    coalesce((
      select sum(d.bottles_delivered*19)
      from public.customer_19l_deliveries d cross join latest l
      where d.delivery_date>(l.measured_at at time zone 'Asia/Karachi')::date
        or (d.delivery_date=(l.measured_at at time zone 'Asia/Karachi')::date and d.created_at>l.measured_at)
    ),0::bigint)::numeric
    +coalesce((
      select sum(d.bottles_delivered*19)
      from public.unassigned_19l_deliveries d cross join latest l
      where d.delivery_date>(l.measured_at at time zone 'Asia/Karachi')::date
        or (d.delivery_date=(l.measured_at at time zone 'Asia/Karachi')::date and d.created_at>l.measured_at)
    ),0::bigint)::numeric
    +coalesce((
      select sum(coalesce(c.counter_water_litres,greatest(
        coalesce(c.total_litres,0)
        -coalesce((select sum(d.bottles_delivered*19) from public.customer_19l_deliveries d where d.delivery_date=c.sale_date),0)
        -coalesce((select sum(d.bottles_delivered*19) from public.unassigned_19l_deliveries d where d.delivery_date=c.sale_date),0),0)))
      from public.counter_water_sales c cross join latest l
      where c.sale_date>(l.measured_at at time zone 'Asia/Karachi')::date
        or (c.sale_date=(l.measured_at at time zone 'Asia/Karachi')::date and c.created_at>l.measured_at)
    ),0::numeric)
    +coalesce((
      select sum(p.quantity*6::numeric)
      from public.production p cross join latest l
      where p.product_type='6L'
        and (p.production_date>(l.measured_at at time zone 'Asia/Karachi')::date
          or (p.production_date=(l.measured_at at time zone 'Asia/Karachi')::date and p.created_at>l.measured_at))
    ),0::numeric) as outflow_litres
)
select l.id as measurement_id,l.measured_at,l.measured_litres,l.ledger_litres,
       l.variance_litres,f.inflow_litres,f.outflow_litres,
       l.measured_litres+f.inflow_litres-f.outflow_litres as current_balance_litres,
       l.measurement_method,l.note
from latest l cross join flows f;