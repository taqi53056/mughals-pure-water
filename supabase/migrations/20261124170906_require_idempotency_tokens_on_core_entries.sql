begin;

do $preflight$
declare
  v_table text;
  v_has_null boolean;
  v_tables text[] := array[
    'business_expenses',
    'business_finance_ledger',
    'business_income',
    'customer_19l_deliveries',
    'customer_complaints',
    'customer_payments',
    'daily_cleaning_labor',
    'finished_goods',
    'finished_stock_adjustments',
    'product_returns',
    'product_sales',
    'production',
    'raw_material_stock',
    'water_tanker_purchases'
  ];
begin
  foreach v_table in array v_tables loop
    execute format('select exists(select 1 from public.%I where request_id is null)',v_table)
      into v_has_null;
    if v_has_null then
      raise exception 'Cannot require request_id: public.% has legacy NULL request IDs',v_table;
    end if;
  end loop;
end
$preflight$;

alter table public.business_expenses alter column request_id set not null;
alter table public.business_finance_ledger alter column request_id set not null;
alter table public.business_income alter column request_id set not null;
alter table public.customer_19l_deliveries alter column request_id set not null;
alter table public.customer_complaints alter column request_id set not null;
alter table public.customer_payments alter column request_id set not null;
alter table public.daily_cleaning_labor alter column request_id set not null;
alter table public.finished_goods alter column request_id set not null;
alter table public.finished_stock_adjustments alter column request_id set not null;
alter table public.product_returns alter column request_id set not null;
alter table public.product_sales alter column request_id set not null;
alter table public.production alter column request_id set not null;
alter table public.raw_material_stock alter column request_id set not null;
alter table public.water_tanker_purchases alter column request_id set not null;

do $repair_production_rpc$
declare
  v_def text;
  v_old text;
  v_new text;
begin
  select pg_get_functiondef('private.record_production_with_workers(date,text,integer,jsonb,uuid)'::regprocedure)
    into v_def;

  v_old := $anchor$  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'صرف ایڈمن پروڈکشن درج کر سکتا ہے۔' USING ERRCODE='42501';
  END IF;$anchor$;

  if position(v_old in v_def)=0 then
    raise exception 'Production RPC admin-guard anchor not found; no function changed';
  end if;

  v_new := replace(v_def,v_old,v_old || E'\n  IF p_request_id IS NULL THEN\n    RAISE EXCEPTION ''ہر پروڈکشن اندراج کے لیے منفرد درخواست شناخت لازمی ہے۔'' USING ERRCODE=''22023'';\n  END IF;');
  if v_new=v_def then
    raise exception 'Production RPC request-id guard was not inserted';
  end if;
  execute v_new;
end
$repair_production_rpc$;

commit;
