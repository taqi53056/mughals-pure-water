-- Reject a finished-stock adjustment if it makes any later recorded
-- balance for the same product negative, not merely the adjustment date.
create or replace function private.mpw_guard_finished_stock_adjustment()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare
  v_event_date date;
  v_available numeric := 0;
  v_after numeric := 0;
  v_unit_cost numeric := 0;
  v_old_id bigint := null;
  v_delta numeric := 0;
begin
  if new.product_type not in ('500ml','1.5L','6L')
     or new.quantity is null or new.quantity<=0
     or new.adjustment_type not in ('increase','decrease')
     or nullif(btrim(new.reason),'') is null then
    raise exception 'اسٹاک درستگی کے لیے پروڈکٹ، مثبت مقدار، درست سمت اور وجہ لازمی ہے۔'
      using errcode='22023';
  end if;

  if tg_op='UPDATE' then
    v_old_id:=old.id;
  end if;

  perform pg_advisory_xact_lock(hashtextextended('finished-stock:'||new.product_type,0));

  v_delta:=case when new.adjustment_type='increase' then new.quantity else -new.quantity end;

  for v_event_date in
    select distinct event_date
    from (
      select sl.movement_date event_date
      from public.stock_ledger sl
      where sl.product_type=new.product_type
      union all
      select ps.sale_date
      from public.product_sales ps
      where ps.product_type=new.product_type
      union all
      select a.adjustment_date
      from public.finished_stock_adjustments a
      where a.product_type=new.product_type
        and (v_old_id is null or a.id is distinct from v_old_id)
      union all
      select r.return_date
      from public.product_returns r
      where r.product_type=new.product_type
      union all
      select new.adjustment_date
    ) events
    where event_date is not null
    order by event_date
  loop
    select b.available_quantity
      into v_available
    from private.get_finished_stock_balance(
      new.product_type,v_event_date,null::numeric,null::date,v_old_id
    ) b;

    v_after:=coalesce(v_available,0)
      + case when new.adjustment_date<=v_event_date then v_delta else 0 end;

    if v_after<0 then
      raise exception
        'اس اسٹاک درستگی سے بعد کی تاریخ کا تیار مال منفی ہوگا۔ پروڈکٹ: %، تاریخ: %، دستیاب: %، تبدیلی: %',
        new.product_type,v_event_date,greatest(coalesce(v_available,0),0),v_delta
        using errcode='23514';
    end if;
  end loop;

  if new.adjustment_type='decrease' then
    v_unit_cost:=private.get_product_direct_unit_cost(new.adjustment_date,new.product_type);
    new.loss_amount:=round(new.quantity*v_unit_cost,2);
  else
    new.loss_amount:=0;
  end if;

  return new;
end;
$function$;
