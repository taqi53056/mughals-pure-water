do $patch$
declare
  v_def text;
  v_new text;
  v_start integer;
  v_end integer;
  v_block text;
begin
  select pg_get_functiondef('public.build_business_monthly_report(date,date)'::regprocedure) into v_def;

  v_new:=replace(v_def,
    'v_product_revenue numeric:=0; v_unassigned_receipts numeric:=0; v_unassigned_unclassified numeric:=0;',
    'v_product_revenue numeric:=0; v_unassigned_receipts numeric:=0; v_unassigned_unclassified numeric:=0; v_monthly_account_receipts numeric:=0; v_monthly_account_receivable numeric:=0;');
  if v_new=v_def then
    if position('v_monthly_account_receipts' in v_def)>0 then
      v_new:=v_def;
    else
      raise exception 'Could not locate monthly report declaration anchor.';
    end if;
  end if;

  v_start:=position('  select coalesce(sum(rc.amount),0) into v_unassigned_receipts' in v_new);
  v_end:=position('  select
    coalesce(sum(amount) filter(where entry_type=''interest_income'')' in v_new);
  if v_start=0 or v_end=0 or v_end<=v_start then
    raise exception 'Could not locate monthly report receivable calculation block.';
  end if;

  v_block:=
'  select coalesce(sum(rc.amount),0) into v_unassigned_receipts
  from public.unassigned_19l_delivery_collections rc
  join public.unassigned_19l_deliveries d on d.id=rc.delivery_id
  where d.customer_classification=''one_time''
    and rc.received_date between p_month_start and p_month_end;

  select greatest(
    (select coalesce(sum(d.bottles_delivered::numeric*100+d.damaged_caps::numeric*10),0)
     from public.unassigned_19l_deliveries d
     where d.customer_classification=''one_time'' and d.delivery_date<=p_month_end)
    -
    (select coalesce(sum(rc.amount),0)
     from public.unassigned_19l_delivery_collections rc
     join public.unassigned_19l_deliveries d on d.id=rc.delivery_id
     where d.customer_classification=''one_time'' and rc.received_date<=p_month_end),
    0
  ) into v_unassigned_unclassified;

  select coalesce(sum(rc.amount),0) into v_monthly_account_receipts
  from public.unassigned_19l_delivery_collections rc
  join public.unassigned_19l_deliveries d on d.id=rc.delivery_id
  where d.customer_classification=''monthly''
    and rc.received_date between p_month_start and p_month_end;

  select greatest(
    (select coalesce(sum(d.bottles_delivered::numeric*100+d.damaged_caps::numeric*10),0)
     from public.unassigned_19l_deliveries d
     where d.customer_classification=''monthly'' and d.delivery_date<=p_month_end)
    -
    (select coalesce(sum(rc.amount),0)
     from public.unassigned_19l_delivery_collections rc
     join public.unassigned_19l_deliveries d on d.id=rc.delivery_id
     where d.customer_classification=''monthly'' and rc.received_date<=p_month_end),
    0
  ) into v_monthly_account_receivable;

';
  v_new:=left(v_new,v_start-1)||v_block||substring(v_new from v_end);

  v_new:=replace(v_new,
    '''unassigned_delivery_cash_unclassified'',v_unassigned_unclassified,''damaged_cap_revenue''',
    '''unassigned_delivery_cash_unclassified'',v_unassigned_unclassified,''monthly_account_cash_collected'',v_monthly_account_receipts,''monthly_account_receivable'',v_monthly_account_receivable,''damaged_cap_revenue''');

  if position('monthly_account_cash_collected' in v_new)=0
     or position('monthly_account_receivable' in v_new)=0 then
    raise exception 'Could not add monthly account report output fields.';
  end if;

  execute v_new;
end
$patch$;
