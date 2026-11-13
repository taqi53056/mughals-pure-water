CREATE OR REPLACE VIEW public.delivery_worker_wage_balance AS
SELECT
 coalesce(sum(wl.amount) FILTER (WHERE wl.entry_type='earning'),0) AS total_earned,
 coalesce(sum(wl.amount) FILTER (WHERE wl.entry_type IN ('payment','advance','deduction')),0) AS total_paid,
 coalesce(sum(wl.amount) FILTER (WHERE wl.entry_type='earning'),0)
 - coalesce(sum(wl.amount) FILTER (WHERE wl.entry_type IN ('payment','advance','deduction')),0) AS balance_due
FROM public.worker_ledger wl WHERE wl.work_category='19L delivery';

CREATE OR REPLACE VIEW public.carton_worker_wage_balance AS
SELECT
 coalesce(sum(wl.amount) FILTER (WHERE wl.entry_type='earning'),0) AS total_earned,
 coalesce(sum(wl.amount) FILTER (WHERE wl.entry_type IN ('payment','advance','deduction')),0) AS total_paid,
 coalesce(sum(wl.amount) FILTER (WHERE wl.entry_type='earning'),0)
 - coalesce(sum(wl.amount) FILTER (WHERE wl.entry_type IN ('payment','advance','deduction')),0) AS balance_due
FROM public.worker_ledger wl WHERE wl.work_category='carton loading/unloading';

DO $$
DECLARE v_oid oid; v_def text; v_old text; v_new text;
BEGIN
 SELECT p.oid INTO v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='private' AND p.proname='get_management_dashboard'
 AND pg_get_function_identity_arguments(p.oid)='p_month_start date, p_month_end date';
 IF v_oid IS NULL THEN RAISE EXCEPTION 'Dashboard function not found'; END IF;
 v_def:=pg_get_functiondef(v_oid);
 v_old:=$old$SELECT greatest(coalesce(sum(CASE WHEN entry_type='earning' THEN amount ELSE -amount END),0),0)
    INTO v_worker_payables
  FROM public.worker_ledger WHERE entry_date<=p_month_end;$old$;
 v_new:=$new$SELECT greatest(coalesce(sum(CASE
      WHEN entry_type='earning' THEN amount
      WHEN entry_type IN ('payment','advance','deduction') THEN -amount
      ELSE 0 END),0),0)
    INTO v_worker_payables
  FROM public.worker_ledger WHERE entry_date<=p_month_end;$new$;
 IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'Expected worker payable expression not found; no change made'; END IF;
 v_def:=replace(v_def,v_old,v_new);
 EXECUTE v_def;
END $$;
