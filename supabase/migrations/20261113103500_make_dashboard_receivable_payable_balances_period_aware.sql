
-- Historical dashboard balances must reflect the selected period end, not today's later transactions.
DO $migration$
DECLARE
  v_oid oid;
  v_def text;
  v_old text;
  v_new text;
BEGIN
  SELECT p.oid INTO v_oid
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='private' AND p.proname='get_management_dashboard'
    AND pg_get_function_identity_arguments(p.oid)='p_month_start date, p_month_end date';
  IF v_oid IS NULL THEN RAISE EXCEPTION 'Private management dashboard function not found'; END IF;
  v_def:=pg_get_functiondef(v_oid);

  v_old:=E'    from public.customer_monthly_bills\n    order by customer_id,bill_month desc';
  v_new:=E'    from public.customer_monthly_bills\n    where bill_month<=date_trunc(''month'',p_month_end)::date\n    order by customer_id,bill_month desc';
  IF position(v_new in v_def)=0 THEN
    IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'Historical customer receivable query anchor not found'; END IF;
    v_def:=replace(v_def,v_old,v_new);
  END IF;

  v_old:='FROM public.unassigned_19l_deliveries d),0)';
  v_new:='FROM public.unassigned_19l_deliveries d WHERE d.delivery_date<=p_month_end),0)';
  IF position(v_new in v_def)=0 THEN
    IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'Unassigned delivery period filter anchor not found'; END IF;
    v_def:=replace(v_def,v_old,v_new);
  END IF;

  v_old:='- coalesce((SELECT sum(c.amount) FROM public.unassigned_19l_delivery_collections c),0),0)';
  v_new:='- coalesce((SELECT sum(c.amount) FROM public.unassigned_19l_delivery_collections c JOIN public.unassigned_19l_deliveries d ON d.id=c.delivery_id WHERE d.delivery_date<=p_month_end AND c.received_date<=p_month_end),0),0)';
  IF position(v_new in v_def)=0 THEN
    IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'Unassigned collection period filter anchor not found'; END IF;
    v_def:=replace(v_def,v_old,v_new);
  END IF;

  v_old:='  FROM public.worker_ledger;';
  v_new:='  FROM public.worker_ledger WHERE entry_date<=p_month_end;';
  IF position(v_new in v_def)=0 THEN
    IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'Worker payable period filter anchor not found'; END IF;
    v_def:=replace(v_def,v_old,v_new);
  END IF;

  EXECUTE v_def;
END;
$migration$;
