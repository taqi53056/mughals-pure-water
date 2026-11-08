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

-- Generated labor_amount on production_worker_allocations is always computed
-- as cartons * 10 by PostgreSQL. Keep the trigger tolerant of NULL on legacy
-- rows, while leaving the generated column out of INSERT statements.
CREATE OR REPLACE FUNCTION public.sync_production_allocation_ledger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_production_date date;
  v_is_owner boolean := false;
  v_labor_amount numeric(12,2);
BEGIN
  IF TG_OP <> 'INSERT' THEN
    DELETE FROM public.worker_ledger
    WHERE source_table = 'production_worker_allocations'
      AND source_id = OLD.id;
  END IF;

  IF TG_OP <> 'DELETE' THEN
    SELECT p.production_date INTO v_production_date
    FROM public.production p
    WHERE p.id = NEW.production_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'پروڈکشن ریکارڈ موجود نہیں۔';
    END IF;

    SELECT w.is_owner INTO v_is_owner
    FROM public.workers w
    WHERE w.id = NEW.worker_id
      AND w.is_active = true
      AND (w.is_owner = true OR w.work_categories @> ARRAY['production']::text[]);
    IF NOT FOUND THEN
      RAISE EXCEPTION 'منتخب ورکر فعال نہیں یا پروڈکشن کے لیے مقرر نہیں۔';
    END IF;

    v_labor_amount := COALESCE(NEW.labor_amount, NEW.cartons * 10);

    IF NOT COALESCE(v_is_owner,false) THEN
      INSERT INTO public.worker_ledger(
        worker_id,entry_date,entry_type,work_category,amount,note,source_table,source_id,entered_by
      )
      VALUES (
        NEW.worker_id,
        v_production_date,
        'earning',
        'production',
        v_labor_amount,
        format('پروڈکشن: %s کارٹن × Rs.10',NEW.cartons),
        'production_worker_allocations',
        NEW.id,
        auth.uid()
      );
    END IF;
    RETURN NEW;
  END IF;

  RETURN OLD;
END;
$function$;

-- Remove browser EXECUTE rights from internal admin-only helpers that the
-- frontend does not call directly. Definer-owned callers remain able to use
-- them; the app-facing guarded RPCs retain their required grants.
REVOKE EXECUTE ON FUNCTION public.calculate_customer_bill(bigint,date) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.recalculate_customer_bill(bigint,date) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.record_customer_refund(bigint,numeric) FROM authenticated;
