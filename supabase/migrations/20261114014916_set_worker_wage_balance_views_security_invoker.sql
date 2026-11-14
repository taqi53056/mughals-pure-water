-- Keep worker wage views subject to the underlying worker_ledger RLS policies.
ALTER VIEW public.carton_worker_wage_balance SET (security_invoker = true);
ALTER VIEW public.delivery_worker_wage_balance SET (security_invoker = true);
