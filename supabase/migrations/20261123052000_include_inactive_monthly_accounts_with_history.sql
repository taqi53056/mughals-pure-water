do $patch$
declare v_def text; v_new text;
begin
  select pg_get_functiondef('private.generate_unregistered_monthly_bills(date)'::regprocedure) into v_def;
  v_new:=replace(v_def,
    'or exists(select 1 from public.unassigned_19l_deliveries d
          where d.monthly_customer_id=mc.id and d.customer_classification=''monthly''
            and d.delivery_date>=v_month and d.delivery_date<v_next)
        or exists(select 1 from public.unassigned_19l_delivery_collections rc
          join public.unassigned_19l_deliveries d on d.id=rc.delivery_id
          where d.monthly_customer_id=mc.id and d.customer_classification=''monthly''
            and rc.received_date>=v_month and rc.received_date<v_next)',
    'or exists(select 1 from public.unassigned_19l_deliveries d
          where d.monthly_customer_id=mc.id and d.customer_classification=''monthly''
            and d.delivery_date<v_next)
        or exists(select 1 from public.unassigned_19l_delivery_collections rc
          join public.unassigned_19l_deliveries d on d.id=rc.delivery_id
          where d.monthly_customer_id=mc.id and d.customer_classification=''monthly''
            and rc.received_date<v_next)');
  if v_new=v_def then
    if position('d.delivery_date<v_next' in v_def)>0 then
      return;
    end if;
    raise exception 'Could not locate inactive monthly-account eligibility conditions.';
  end if;
  execute v_new;
end
$patch$;
