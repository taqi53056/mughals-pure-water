-- Validate revised finished-goods opening balances at every recorded
-- stock event date, not only today's ending balance.
create or replace function private.mpw_guard_finished_goods_opening_stock()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare
  v_unit text;
  v_event_date date;
  v_available numeric := 0;
begin
  if tg_op='DELETE' then
    raise exception 'ابتدائی تیار مال کا ریکارڈ حذف نہیں کیا جا سکتا؛ مقدار درست کریں۔'
      using errcode='55000';
  end if;

  if tg_op='UPDATE' then
    if new.product_type is distinct from old.product_type
       or new.unit is distinct from old.unit
       or new.entry_date is distinct from old.entry_date then
      raise exception 'ابتدائی تیار مال کی پروڈکٹ اور تاریخ تبدیل نہیں کی جا سکتی۔'
        using errcode='55000';
    end if;
  end if;

  v_unit:=case when new.product_type='6L' then 'bottle' else 'carton' end;

  if new.product_type not in ('500ml','1.5L','6L')
     or new.unit is distinct from v_unit
     or new.quantity<=0 then
    raise exception 'ابتدائی تیار مال کی پروڈکٹ، یونٹ اور مثبت مقدار درست درج کریں۔'
      using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('finished-stock:'||new.product_type,0));

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
      union all
      select r.return_date
      from public.product_returns r
      where r.product_type=new.product_type
      union all
      select (now() at time zone 'Asia/Karachi')::date
    ) events
    where event_date is not null
    order by event_date
  loop
    select b.available_quantity
      into v_available
    from private.get_finished_stock_balance(
      new.product_type,v_event_date,new.quantity,new.entry_date,null::bigint
    ) b;

    if coalesce(v_available,0)<0 then
      raise exception
        'ابتدائی تیار مال کی اس مقدار سے بعد کی تاریخ کا اسٹاک منفی ہوگا۔ پروڈکٹ: %، تاریخ: %، بیلنس: %',
        new.product_type,v_event_date,v_available
        using errcode='23514';
    end if;
  end loop;

  return new;
end;
$function$;
