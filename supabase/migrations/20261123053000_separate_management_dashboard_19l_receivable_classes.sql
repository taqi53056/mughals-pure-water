do $patch$
declare
  v_def text;
  v_new text;
  v_start integer;
  v_end integer;
  v_block text;
begin
  select pg_get_functiondef('private.get_management_dashboard(date,date)'::regprocedure) into v_def;

  v_new:=replace(v_def,
    'v_unassigned_due numeric(14,2):=0;',
    'v_unassigned_due numeric(14,2):=0;
  v_monthly_account_due numeric(14,2):=0;
  v_pending_review_due numeric(14,2):=0;');
  if v_new=v_def and position('v_monthly_account_due' in v_def)=0 then
    raise exception 'Could not locate management receivable declarations.';
  end if;

  v_start:=position('  SELECT greatest(' in v_new);
  v_end:=position('  SELECT coalesce(sum(greatest(ps.total_amount-coalesce(paid.total_paid,0),0)),0)' in v_new);
  if v_start=0 or v_end=0 or v_end<=v_start then
    raise exception 'Could not locate management 19L receivable block.';
  end if;

  v_block:=
'  SELECT greatest(
    coalesce((SELECT sum(d.bottles_delivered::numeric*100+d.damaged_caps::numeric*10)
      FROM public.unassigned_19l_deliveries d
      WHERE d.customer_classification=''one_time'' AND d.delivery_date<=p_month_end),0)
    - coalesce((SELECT sum(c.amount) FROM public.unassigned_19l_delivery_collections c
      JOIN public.unassigned_19l_deliveries d ON d.id=c.delivery_id
      WHERE d.customer_classification=''one_time'' AND c.received_date<=p_month_end),0),0)
  INTO v_unassigned_due;

  SELECT greatest(
    coalesce((SELECT sum(d.bottles_delivered::numeric*100+d.damaged_caps::numeric*10)
      FROM public.unassigned_19l_deliveries d
      WHERE d.customer_classification=''monthly'' AND d.delivery_date<=p_month_end),0)
    - coalesce((SELECT sum(c.amount) FROM public.unassigned_19l_delivery_collections c
      JOIN public.unassigned_19l_deliveries d ON d.id=c.delivery_id
      WHERE d.customer_classification=''monthly'' AND c.received_date<=p_month_end),0),0)
  INTO v_monthly_account_due;

  SELECT greatest(
    coalesce((SELECT sum(d.bottles_delivered::numeric*100+d.damaged_caps::numeric*10)
      FROM public.unassigned_19l_deliveries d
      WHERE d.customer_classification=''monthly_pending_review'' AND d.delivery_date<=p_month_end),0)
    - coalesce((SELECT sum(c.amount) FROM public.unassigned_19l_delivery_collections c
      JOIN public.unassigned_19l_deliveries d ON d.id=c.delivery_id
      WHERE d.customer_classification=''monthly_pending_review'' AND c.received_date<=p_month_end),0),0)
  INTO v_pending_review_due;

';
  v_new:=left(v_new,v_start-1)||v_block||substring(v_new from v_end);

  v_new:=replace(v_new,
    'v_due:=v_due+v_unassigned_due+v_store_credit_due',
    'v_due:=v_due+v_unassigned_due+v_monthly_account_due+v_pending_review_due+v_store_credit_due');

  v_new:=replace(v_new,
    '''unassigned_receivables'',v_unassigned_due,',
    '''unassigned_receivables'',v_unassigned_due,
    ''monthly_unregistered_receivables'',v_monthly_account_due,
    ''historical_pending_19l_receivables'',v_pending_review_due,');

  if position('monthly_unregistered_receivables' in v_new)=0
     or position('historical_pending_19l_receivables' in v_new)=0 then
    raise exception 'Could not add receivable classes to dashboard output.';
  end if;

  execute v_new;
end
$patch$;
