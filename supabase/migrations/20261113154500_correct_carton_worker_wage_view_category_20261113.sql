CREATE OR REPLACE VIEW public.carton_worker_wage_balance AS
SELECT
 coalesce(sum(wl.amount) FILTER (WHERE wl.entry_type='earning'),0) AS total_earned,
 coalesce(sum(wl.amount) FILTER (WHERE wl.entry_type IN ('payment','advance','deduction')),0) AS total_paid,
 coalesce(sum(wl.amount) FILTER (WHERE wl.entry_type='earning'),0)
 - coalesce(sum(wl.amount) FILTER (WHERE wl.entry_type IN ('payment','advance','deduction')),0) AS balance_due
FROM public.worker_ledger wl WHERE wl.work_category='carton loading/unloading';
