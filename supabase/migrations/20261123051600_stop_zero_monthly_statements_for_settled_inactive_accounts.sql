do $patch$
declare v_def text; v_new text;
begin
  select pg_get_functiondef('private.generate_unregistered_monthly_bills(date)'::regprocedure) into v_def;
  v_new:=replace(v_def,
    'or exists(select 1 from public.unregistered_monthly_bills b
          where b.customer_id=mc.id and b.bill_month<v_month)
        or exists(select 1 from public.unassigned_19l_deliveries d
          where d.monthly_customer_id=mc.id and d.customer_classification=''monthly''
            and d.delivery_date<v_next)
        or exists(select 1 from public.unassigned_19l_delivery_collections rc
          join public.unassigned_19l_deliveries d on d.id=rc.delivery_id
          where d.monthly_customer_id=mc.id and d.customer_classification=''monthly''
            and rc.received_date<v_next)',
    'or exists(select 1 from public.unregistered_monthly_bills b
          where b.customer_id=mc.id and b.bill_month<v_month
            and (b.current_due>0 or b.closing_advance>0))
        or (not exists(select 1 from public.unregistered_monthly_bills prior
          where prior.customer_id=mc.id and prior.bill_month<v_month)
        and exists(select 1 from public.unassigned_19l_deliveries d
          where d.monthly_customer_id=mc.id and d.customer_classification=''monthly''
            and d.delivery_date<v_month))
        or exists(select 1 from public.unassigned_19l_deliveries d
          where d.monthly_customer_id=mc.id and d.customer_classification=''monthly''
            and d.delivery_date>=v_month and d.delivery_date<v_next)
        or exists(select 1 from public.unassigned_19l_delivery_collections rc
          join public.unassigned_19l_deliveries d on d.id=rc.delivery_id
          where d.monthly_customer_id=mc.id and d.customer_classification=''monthly''
            and rc.received_date>=v_month and rc.received_date<v_next)');
  if v_new=v_def then
    if position('b.current_due>0 or b.closing_advance>0' in v_def)>0 then return; end if;
    raise exception 'Could not locate monthly statement eligibility clause.';
  end if;
  execute v_new;
end
$patch$;
