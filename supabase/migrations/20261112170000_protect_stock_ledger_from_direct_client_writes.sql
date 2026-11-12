-- Prevent authenticated clients from directly mutating the derived finished-stock ledger.
-- Production triggers run as SECURITY DEFINER and remain the only application write path.
BEGIN;
DROP POLICY IF EXISTS "Admins full access stock ledger" ON public.stock_ledger;
CREATE POLICY "Admins read stock ledger" ON public.stock_ledger
  FOR SELECT TO authenticated USING (public.is_admin());
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.stock_ledger FROM anon, authenticated;
GRANT SELECT ON TABLE public.stock_ledger TO authenticated;
COMMIT;
