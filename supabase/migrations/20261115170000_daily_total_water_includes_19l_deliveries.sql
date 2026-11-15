-- Daily total litres include all customer and unassigned 19L deliveries.
-- Counter revenue remains only the sale of litres left after 19L supply.
begin;

alter table public.counter_water_sales
  drop constraint if exists counter_water_sales_total_amount_check;
alter table public.counter_water_sales
  add constraint counter_water_sales_total_amount_check
  check (total_amount >= 0);

do $repair$
declare
  v_def text;
  v_old text;
  v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname='build_business_monthly_report'
    and p.prokind='f';

  if v_def is null then
    raise exception 'build_business_monthly_report was not found';
  end if;

  v_new := v_def;

  if position('greatest(v_counter_litres-v_used_water,0)*coalesce(v_shop_water_rate,0)' in v_def)=0 then
  v_old := $x$v_counter_litres*coalesce(v_shop_water_rate,0)$x$;
  if (length(v_new)-length(replace(v_new,v_old,'')))/length(v_old) <> 4 then
    raise exception 'Unexpected counter water cost expression count';
  end if;
  v_new := replace(v_new,v_old,$x$greatest(v_counter_litres-v_used_water,0)*coalesce(v_shop_water_rate,0)$x$);

  v_old := $x$coalesce((select sum(bottles_delivered) from public.customer_19l_deliveries where delivery_date<=p_month_end),0)*19$x$;
  if (length(v_new)-length(replace(v_new,v_old,'')))/length(v_old) <> 1 then
    raise exception 'Unexpected customer 19L stock expression count';
  end if;
  v_new := replace(v_new,v_old,'0');

  v_old := $x$coalesce((select sum(bottles_delivered)*19 from public.customer_19l_deliveries where delivery_date<=p_month_end),0)$x$;
  if (length(v_new)-length(replace(v_new,v_old,'')))/length(v_old) <> 2 then
    raise exception 'Unexpected customer water-pool expression count';
  end if;
  v_new := replace(v_new,v_old,'0');

  v_old := $x$coalesce((select sum(bottles_delivered)*19 from public.unassigned_19l_deliveries where delivery_date<=p_month_end),0)$x$;
  if (length(v_new)-length(replace(v_new,v_old,'')))/length(v_old) <> 3 then
    raise exception 'Unexpected unassigned water-pool expression count';
  end if;
  v_new := replace(v_new,v_old,'0');

  v_old := $x$'counter_water_litres',v_counter_litres$x$;
  if (length(v_new)-length(replace(v_new,v_old,'')))/length(v_old) <> 1 then
    raise exception 'Counter litres JSON key not found exactly once';
  end if;
  v_new := replace(v_new,v_old,$x$'counter_water_litres',greatest(v_counter_litres-v_used_water,0),
        'daily_total_water_litres',v_counter_litres,
        'nineteen_litre_delivery_water_litres',v_used_water$x$);

  v_old := $x$'counter_average_price_per_estimated_litre',v_counter_amount/nullif(v_counter_litres,0)$x$;
  if (length(v_new)-length(replace(v_new,v_old,'')))/length(v_old) <> 1 then
    raise exception 'Counter average-price expression not found exactly once';
  end if;
  v_new := replace(v_new,v_old,$x$'counter_average_price_per_estimated_litre',v_counter_amount/nullif(greatest(v_counter_litres-v_used_water,0),0)$x$);

  v_old := $x$'counter_contribution_per_estimated_litre',v_counter_amount/nullif(v_counter_litres,0)-v_shop_water_rate$x$;
  if (length(v_new)-length(replace(v_new,v_old,'')))/length(v_old) <> 1 then
    raise exception 'Counter contribution expression not found exactly once';
  end if;
  v_new := replace(v_new,v_old,$x$'counter_contribution_per_estimated_litre',v_counter_amount/nullif(greatest(v_counter_litres-v_used_water,0),0)-v_shop_water_rate$x$);

  v_old := $x$v_used_water:=(v_delivered+v_unassigned_delivered)*19;$x$;
  if (length(v_new)-length(replace(v_new,v_old,'')))/length(v_old) <> 1 then
    raise exception 'Monthly delivered-water statement not found exactly once';
  end if;
  v_new := replace(v_new,v_old,$x$v_used_water:=(v_delivered+v_unassigned_delivered)*19;
  if exists (
    select 1
    from (
      select delivery_date, sum(bottles_delivered)*19 as required_litres
      from (
        select delivery_date,bottles_delivered
        from public.customer_19l_deliveries
        where delivery_date between p_month_start and p_month_end
        union all
        select delivery_date,bottles_delivered
        from public.unassigned_19l_deliveries
        where delivery_date between p_month_start and p_month_end
      ) daily_deliveries
      group by delivery_date
    ) required
    left join public.counter_water_sales daily_total
      on daily_total.sale_date=required.delivery_date
    where daily_total.sale_date is null
       or daily_total.total_litres < required.required_litres
  ) then
    v_missing:=array_append(v_missing,'روزانہ کل پانی درج نہیں یا 19L سپلائی سے کم ہے');
  end if;$x$);

  v_old := $x$دکان کے کاؤنٹر پانی کے لیٹر صارف کا تخمینہ ہیں؛ اسی لیے اس پانی کی لاگت، دکان والی ٹنکی کا باقی لیٹر اور خالص منافع بھی تخمینی ہیں۔$x$;
  if position(v_old in v_new)=0 then
    raise exception 'Monthly report water note not found';
  end if;
  v_new := replace(v_new,v_old,$x$روزانہ کل پانی میں 19L سپلائی بھی شامل ہے؛ رپورٹ 19L کے لیٹر منہا کرکے باقی کاؤنٹر فروخت اور اس کی تخمینی لاگت دکھاتی ہے۔$x$);

  end if;

  execute v_new;
end
$repair$;

commit;