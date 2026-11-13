-- Patch the existing sale RPC without rewriting its pricing, worker,
-- idempotency, and credit-related contracts. A backdated sale is checked
-- against every later stock event before it is inserted.
do $migration$
declare
  v_definition text;
  v_old_declaration text := '  v_available numeric;';
  v_new_declaration text := '  v_available numeric;'||chr(10)||'  v_event_date date;'||chr(10)||'  v_after numeric;';
  v_old_block text := $old$
  v_unit:=case when p_product_type='6L' then 'bottle' else 'carton' end;
  select b.available_quantity
    into v_available
  from private.get_finished_stock_balance(p_product_type,p_sale_date) b;

  if p_quantity>v_available then
    raise exception 'تیار مال کا اسٹاک کم ہے۔ دستیاب مقدار: %',greatest(0,v_available)
      using errcode='23514';
  end if;
$old$;
  v_new_block text := $new$
  v_unit:=case when p_product_type='6L' then 'bottle' else 'carton' end;

  for v_event_date in
    select distinct event_date
    from (
      select sl.movement_date event_date from public.stock_ledger sl where sl.product_type=p_product_type
      union all select ps.sale_date from public.product_sales ps where ps.product_type=p_product_type
      union all select a.adjustment_date from public.finished_stock_adjustments a where a.product_type=p_product_type
      union all select r.return_date from public.product_returns r where r.product_type=p_product_type
      union all select p_sale_date
    ) events
    where event_date is not null
    order by event_date
  loop
    select b.available_quantity into v_available
    from private.get_finished_stock_balance(p_product_type,v_event_date) b;

    v_after:=coalesce(v_available,0)
      - case when p_sale_date<=v_event_date then p_quantity else 0 end;

    if v_after<0 then
      raise exception 'اس سیل سے بعد کی تاریخ کا تیار مال منفی ہوگا۔ پروڈکٹ: %، تاریخ: %، دستیاب: %، سیل: %',
        p_product_type,v_event_date,greatest(coalesce(v_available,0),0),p_quantity
        using errcode='23514';
    end if;
  end loop;
$new$;
begin
  select pg_get_functiondef(
    'private.record_product_sale(date,text,integer,bigint,numeric,text,uuid)'::regprocedure
  ) into v_definition;

  if position(v_old_declaration in v_definition)=0
     or position(v_old_block in v_definition)=0 then
    raise exception 'Expected product-sale stock validation block was not found; migration aborted.';
  end if;

  v_definition:=replace(v_definition,v_old_declaration,v_new_declaration);
  v_definition:=replace(v_definition,v_old_block,v_new_block);
  execute v_definition;
end;
$migration$;
