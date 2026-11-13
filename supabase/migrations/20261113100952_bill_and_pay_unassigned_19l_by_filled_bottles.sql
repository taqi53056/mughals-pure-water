
DO $migration$
DECLARE
  v_oid oid;
  v_def text;
  v_old text;
  v_new text;
BEGIN
  SELECT p.oid INTO v_oid
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='build_business_monthly_report'
    AND pg_get_function_identity_arguments(p.oid)='p_month_start date, p_month_end date';
  IF v_oid IS NULL THEN RAISE EXCEPTION 'Monthly report function not found'; END IF;
  v_def:=pg_get_functiondef(v_oid);

  v_old:='select coalesce(sum(bottles_delivered),0),coalesce(sum(empty_bottles_returned),0),coalesce(sum(labor_amount),0),coalesce(sum(damaged_caps),0)';
  v_new:='select coalesce(sum(bottles_delivered),0),coalesce(sum(bottles_delivered),0),coalesce(sum(labor_amount),0),coalesce(sum(damaged_caps),0)';
  IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'Monthly report unassigned bottle aggregation not found'; END IF;
  v_def:=replace(v_def,v_old,v_new);

  v_old:='select coalesce(sum(amount),0) into v_unassigned_receipts
  from public.business_income where income_date between p_month_start and p_month_end
    and category=''غیر منسلک 19L سپلائی کی وصولی'';';
  v_new:='select coalesce(sum(rc.amount),0) into v_unassigned_receipts
  from public.unassigned_19l_delivery_collections rc
  join public.unassigned_19l_deliveries d on d.id=rc.delivery_id
  where d.delivery_date between p_month_start and p_month_end;';
  IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'Monthly report linked collection aggregation not found'; END IF;
  v_def:=replace(v_def,v_old,v_new);
  EXECUTE v_def;

  SELECT p.oid INTO v_oid
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='record_unassigned_19l_collection'
    AND pg_get_function_identity_arguments(p.oid)=
      'p_delivery_id bigint, p_received_date date, p_amount numeric, p_payment_method text, p_request_id uuid';
  IF v_oid IS NULL THEN RAISE EXCEPTION 'Unassigned collection function not found'; END IF;
  v_def:=pg_get_functiondef(v_oid);
  v_old:='v_due:=v_delivery.empty_bottles_returned::numeric*100+v_delivery.damaged_caps::numeric*10;';
  v_new:='v_due:=v_delivery.bottles_delivered::numeric*100+v_delivery.damaged_caps::numeric*10;';
  IF position(v_old in v_def)=0 THEN
    IF position(v_new in v_def)=0 THEN RAISE EXCEPTION 'Unassigned collection due formula not found'; END IF;
  ELSE
    v_def:=replace(v_def,v_old,v_new);
    EXECUTE v_def;
  END IF;

  SELECT p.oid INTO v_oid
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='sync_unassigned_19l_worker_ledger'
    AND pg_get_function_identity_arguments(p.oid)='';
  IF v_oid IS NULL THEN RAISE EXCEPTION 'Unassigned worker ledger sync function not found'; END IF;
  v_def:=pg_get_functiondef(v_oid);
  v_old:='v_labor:=coalesce(new.empty_bottles_returned,0)::numeric*20;';
  v_new:='v_labor:=coalesce(new.bottles_delivered,0)::numeric*20;';
  IF position(v_old in v_def)>0 THEN
    v_def:=replace(v_def,v_old,v_new);
    v_old:='''غیر منسلک 19L سپلائی — ''||coalesce(new.empty_bottles_returned,0)||'' کامیاب بوتلیں''';
    v_new:='''غیر منسلک 19L سپلائی — ''||coalesce(new.bottles_delivered,0)||'' بھری بوتلیں''';
    IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'Unassigned worker ledger note formula not found'; END IF;
    v_def:=replace(v_def,v_old,v_new);
    EXECUTE v_def;
  ELSIF position('v_labor:=coalesce(new.bottles_delivered,0)::numeric*20;' in v_def)=0 THEN
    RAISE EXCEPTION 'Unassigned worker labor formula not found';
  END IF;
END;
$migration$;
