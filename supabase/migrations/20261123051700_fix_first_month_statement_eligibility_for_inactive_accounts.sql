do $patch$
declare v_def text; v_new text;
begin
  select pg_get_functiondef('private.generate_unregistered_monthly_bills(date)'::regprocedure) into v_def;
  v_new:=replace(v_def,
    'or exists(select 1 from public.unregistered_monthly_bills b
          where b.customer_id=mc.id and b.bill_month<v_month
            and not exists(select 1 from public.unregistered_monthly_bills prior
              where prior.customer_id=mc.id and prior.bill_month<v_month))',
    'or (not exists(select 1 from public.unregistered_monthly_bills prior
          where prior.customer_id=mc.id and prior.bill_month<v_month)
        and exists(select 1 from public.unassigned_19l_deliveries d
          where d.monthly_customer_id=mc.id and d.customer_classification=''monthly''
            and d.delivery_date<v_month))');
  if v_new=v_def then
    if position('d.delivery_date<v_month' in v_def)>0 then return; end if;
    raise exception 'Could not locate first-month inactive account eligibility clause.';
  end if;
  execute v_new;
end
$patch$;
