
-- Include unassigned filled-bottle debt and recorded worker/loan balances in the executive dashboard.
DO $migration$
DECLARE
  v_oid oid;
  v_def text;
  v_old text;
  v_new text;
BEGIN
  SELECT p.oid INTO v_oid
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='private' AND p.proname='get_management_dashboard'
    AND pg_get_function_identity_arguments(p.oid)='p_month_start date, p_month_end date';
  IF v_oid IS NULL THEN RAISE EXCEPTION 'Private management dashboard function not found'; END IF;
  v_def:=pg_get_functiondef(v_oid);

  v_old:='  v_cash_out numeric(14,2):=0;';
  v_new:=v_old || E'\n  v_unassigned_due numeric(14,2):=0;\n  v_worker_payables numeric(14,2):=0;\n  v_loan_payables numeric(14,2):=0;\n  v_payables numeric(14,2):=0;';
  IF position(v_old in v_def)>0 THEN
    v_def:=replace(v_def,v_old,v_new);
  ELSIF position('v_unassigned_due numeric(14,2):=0;' in v_def)=0 THEN
    RAISE EXCEPTION 'Dashboard cashflow variable declaration anchor not found';
  END IF;

  v_old:=E'  select coalesce(sum(current_due),0),count(*) filter(where current_due>0)\n    into v_due,v_due_customers\n  from (\n    select distinct on(customer_id) customer_id,current_due\n    from public.customer_monthly_bills\n    order by customer_id,bill_month desc\n  ) latest;';
  v_new:=v_old || E'\n\n  SELECT greatest(\n    coalesce((SELECT sum(d.bottles_delivered::numeric*100 + d.damaged_caps::numeric*10)\n      FROM public.unassigned_19l_deliveries d),0)\n    - coalesce((SELECT sum(c.amount) FROM public.unassigned_19l_delivery_collections c),0),0)\n  INTO v_unassigned_due;\n  v_due:=v_due+v_unassigned_due\n    +greatest(coalesce((v_report->''capital_and_loans''->>''receivable_balance'')::numeric,0),0);';
  IF position('INTO v_unassigned_due' in v_def)=0 THEN
    IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'Dashboard receivables calculation anchor not found'; END IF;
    v_def:=replace(v_def,v_old,v_new);
  END IF;

  v_old:='    into v_cash_out;';
  v_new:=v_old || E'\n\n  SELECT greatest(coalesce(sum(CASE WHEN entry_type=''earning'' THEN amount ELSE -amount END),0),0)\n    INTO v_worker_payables\n  FROM public.worker_ledger;\n  v_loan_payables:=greatest(coalesce((v_report->''capital_and_loans''->>''loan_balance'')::numeric,0),0);\n  v_payables:=v_worker_payables+v_loan_payables;';
  IF position('INTO v_worker_payables' in v_def)=0 THEN
    IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'Dashboard cash outflow calculation anchor not found'; END IF;
    v_def:=replace(v_def,v_old,v_new);
  END IF;

  v_old:='    ''customers_with_due'',v_due_customers,''receivables'',v_due,';
  v_new:=v_old || E'\n    ''unassigned_receivables'',v_unassigned_due,\n    ''payables'',v_payables,''worker_payables'',v_worker_payables,''loan_payables'',v_loan_payables,';
  IF position('''payables'',v_payables' in v_def)=0 THEN
    IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'Dashboard return payload anchor not found'; END IF;
    v_def:=replace(v_def,v_old,v_new);
  END IF;

  EXECUTE v_def;
END;
$migration$;
