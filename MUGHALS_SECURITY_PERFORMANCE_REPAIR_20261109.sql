-- MUGHAL'S PURE WATER
-- Security and performance repair applied to live Supabase on 2026-11-09.
-- This is an idempotent record of the changes already applied.
-- Review against the target database before applying to any other project.

-- Pin trigger function search paths and the legacy 3-argument RPC.
ALTER FUNCTION public.set_delivery_wage() SET search_path = '';
ALTER FUNCTION public.set_production_labor() SET search_path = '';
ALTER FUNCTION public.record_product_sale(date, text, integer) SET search_path = '';

-- Add indexes for previously unindexed foreign-key columns.
CREATE INDEX IF NOT EXISTS idx_customer_19l_deliveries_worker_id ON public.customer_19l_deliveries(worker_id);
CREATE INDEX IF NOT EXISTS idx_customer_payments_entered_by ON public.customer_payments(entered_by);
CREATE INDEX IF NOT EXISTS idx_daily_cleaning_labor_worker_id ON public.daily_cleaning_labor(worker_id);
CREATE INDEX IF NOT EXISTS idx_delivery_daily_entered_by ON public.delivery_daily(entered_by);
CREATE INDEX IF NOT EXISTS idx_expenses_entered_by ON public.expenses(entered_by);
CREATE INDEX IF NOT EXISTS idx_finished_stock_adjustments_entered_by ON public.finished_stock_adjustments(entered_by);
CREATE INDEX IF NOT EXISTS idx_income_entered_by ON public.income(entered_by);
CREATE INDEX IF NOT EXISTS idx_labor_payments_entered_by ON public.labor_payments(entered_by);
CREATE INDEX IF NOT EXISTS idx_labor_payments_worker_id ON public.labor_payments(worker_id);
CREATE INDEX IF NOT EXISTS idx_product_sales_worker_id ON public.product_sales(worker_id);
CREATE INDEX IF NOT EXISTS idx_production_entered_by ON public.production(entered_by);
CREATE INDEX IF NOT EXISTS idx_production_worker_id ON public.production(worker_id);
CREATE INDEX IF NOT EXISTS idx_raw_material_entered_by ON public.raw_material(entered_by);
CREATE INDEX IF NOT EXISTS idx_sales_entered_by ON public.sales(entered_by);
CREATE INDEX IF NOT EXISTS idx_stock_ledger_entered_by ON public.stock_ledger(entered_by);
CREATE INDEX IF NOT EXISTS idx_worker_ledger_entered_by ON public.worker_ledger(entered_by);

-- Cache auth.uid() once per statement in customer-scoped RLS policies.
ALTER POLICY "Customers view own deliveries" ON public.customer_19l_deliveries
USING (EXISTS (SELECT 1 FROM public.customers c WHERE c.id = customer_19l_deliveries.customer_id AND c.auth_user_id = (SELECT auth.uid()) AND c.is_active = true));

ALTER POLICY "Customer can view own bills" ON public.customer_monthly_bills
USING (EXISTS (SELECT 1 FROM public.customers c WHERE c.id = customer_monthly_bills.customer_id AND c.auth_user_id = (SELECT auth.uid()) AND c.is_active = true));

ALTER POLICY "Customer can view own payments" ON public.customer_payments
USING (EXISTS (SELECT 1 FROM public.customers c WHERE c.id = customer_payments.customer_id AND c.auth_user_id = (SELECT auth.uid()) AND c.is_active = true));

ALTER POLICY "Customer can view own profile" ON public.customers
USING (auth_user_id = (SELECT auth.uid()) AND is_active = true);

ALTER POLICY customer_notifications_own_select ON public.customer_notifications
USING (EXISTS (SELECT 1 FROM public.customers c WHERE c.id = customer_notifications.customer_id AND c.auth_user_id = (SELECT auth.uid()) AND c.is_active = true));

ALTER POLICY customer_complaints_own_select ON public.customer_complaints
USING (EXISTS (SELECT 1 FROM public.customers c WHERE c.id = customer_complaints.customer_id AND c.auth_user_id = (SELECT auth.uid()) AND c.is_active = true));

ALTER POLICY customer_complaints_own_insert ON public.customer_complaints
WITH CHECK (status = 'new' AND admin_note IS NULL AND EXISTS (SELECT 1 FROM public.customers c WHERE c.id = customer_complaints.customer_id AND c.auth_user_id = (SELECT auth.uid()) AND c.is_active = true));

-- Remove the redundant duplicate UNIQUE constraint; the primary composite
-- UNIQUE constraint customer_monthly_bills_customer_id_bill_month_key remains.
ALTER TABLE public.customer_monthly_bills
DROP CONSTRAINT IF EXISTS customer_monthly_bills_unique_month;

-- Restrict customer table column access: obsolete PIN fields must never be
-- readable or writable by browser-authenticated users. The app selects only
-- the safe profile/account columns listed below.
REVOKE ALL PRIVILEGES ON TABLE public.customers FROM authenticated;
REVOKE ALL (id, customer_code, name, mobile, address, pin_hash, is_active, created_at, auth_user_id, pin_enabled, pin) ON TABLE public.customers FROM authenticated;
GRANT SELECT (id, customer_code, name, mobile, address, is_active, auth_user_id) ON TABLE public.customers TO authenticated;
GRANT UPDATE (name, mobile, address, is_active) ON TABLE public.customers TO authenticated;
