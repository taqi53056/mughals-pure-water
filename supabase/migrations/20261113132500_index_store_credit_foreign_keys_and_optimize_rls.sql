
-- Cover new auth-user foreign keys and avoid per-row auth.uid() evaluation.
CREATE INDEX IF NOT EXISTS business_stores_created_by_idx
  ON public.business_stores(created_by);
CREATE INDEX IF NOT EXISTS store_credit_payments_entered_by_idx
  ON public.store_credit_payments(entered_by);

DROP POLICY IF EXISTS business_stores_admin_insert ON public.business_stores;
CREATE POLICY business_stores_admin_insert
  ON public.business_stores FOR INSERT TO authenticated
  WITH CHECK (public.is_admin() AND created_by=(SELECT auth.uid()));
