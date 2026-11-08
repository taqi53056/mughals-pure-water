-- MUGHAL'S PURE WATER
-- Final RLS policy consolidation and RPC privilege hardening.
-- Applied and verified on the live Supabase project on 2026-11-09.
-- Apply after MUGHALS_SECURITY_PERFORMANCE_REPAIR_20261109.sql.
-- This migration is idempotent: existing policy names are dropped before recreation.

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO ''
AS $function$
  SELECT auth.uid() IN (
    '471fce90-625e-4e8c-863a-659d68afaab3'::uuid,
    'c64d7186-1990-4487-8d0f-e9307f588fd1'::uuid,
    'd713d3c6-9c9e-408f-baa4-4a5b2a157944'::uuid
  );
$function$;

-- Use invoker rights for app-facing RPCs. RLS policies enforce admin/customer scope.
ALTER FUNCTION public.get_finished_stock_summary() SECURITY INVOKER;
ALTER FUNCTION public.get_owner_work_summary() SECURITY INVOKER;
ALTER FUNCTION public.recalculate_customer_bills_from(bigint,date) SECURITY INVOKER;
ALTER FUNCTION public.record_production_with_workers(date,text,integer,jsonb) SECURITY INVOKER;
ALTER FUNCTION public.calculate_customer_bill(bigint,date) SECURITY INVOKER;
ALTER FUNCTION public.mark_customer_notification_read(bigint) SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.calculate_customer_bill(bigint,date) TO authenticated;
GRANT INSERT ON TABLE public.production_worker_allocations TO authenticated;

-- Deliveries: admin CRUD, customer own-row SELECT only.
DROP POLICY IF EXISTS "Admins full access deliveries" ON public.customer_19l_deliveries;
DROP POLICY IF EXISTS "Customers view own deliveries" ON public.customer_19l_deliveries;
DROP POLICY IF EXISTS customer_19l_deliveries_select ON public.customer_19l_deliveries;
DROP POLICY IF EXISTS customer_19l_deliveries_insert ON public.customer_19l_deliveries;
DROP POLICY IF EXISTS customer_19l_deliveries_update ON public.customer_19l_deliveries;
DROP POLICY IF EXISTS customer_19l_deliveries_delete ON public.customer_19l_deliveries;
CREATE POLICY customer_19l_deliveries_select ON public.customer_19l_deliveries
FOR SELECT TO authenticated
USING (
  (SELECT public.is_admin()) OR EXISTS (
    SELECT 1 FROM public.customers c
    WHERE c.id = customer_19l_deliveries.customer_id
      AND c.auth_user_id = (SELECT auth.uid()) AND c.is_active = true
  )
);
CREATE POLICY customer_19l_deliveries_insert ON public.customer_19l_deliveries
FOR INSERT TO authenticated WITH CHECK ((SELECT public.is_admin()));
CREATE POLICY customer_19l_deliveries_update ON public.customer_19l_deliveries
FOR UPDATE TO authenticated USING ((SELECT public.is_admin())) WITH CHECK ((SELECT public.is_admin()));
CREATE POLICY customer_19l_deliveries_delete ON public.customer_19l_deliveries
FOR DELETE TO authenticated USING ((SELECT public.is_admin()));

-- Monthly bills: admin CRUD, customer own-row SELECT only.
DROP POLICY IF EXISTS "Admins full access monthly bills" ON public.customer_monthly_bills;
DROP POLICY IF EXISTS "Customer can view own bills" ON public.customer_monthly_bills;
DROP POLICY IF EXISTS customer_monthly_bills_select ON public.customer_monthly_bills;
DROP POLICY IF EXISTS customer_monthly_bills_insert ON public.customer_monthly_bills;
DROP POLICY IF EXISTS customer_monthly_bills_update ON public.customer_monthly_bills;
DROP POLICY IF EXISTS customer_monthly_bills_delete ON public.customer_monthly_bills;
CREATE POLICY customer_monthly_bills_select ON public.customer_monthly_bills
FOR SELECT TO authenticated
USING (
  (SELECT public.is_admin()) OR EXISTS (
    SELECT 1 FROM public.customers c
    WHERE c.id = customer_monthly_bills.customer_id
      AND c.auth_user_id = (SELECT auth.uid()) AND c.is_active = true
  )
);
CREATE POLICY customer_monthly_bills_insert ON public.customer_monthly_bills
FOR INSERT TO authenticated WITH CHECK ((SELECT public.is_admin()));
CREATE POLICY customer_monthly_bills_update ON public.customer_monthly_bills
FOR UPDATE TO authenticated USING ((SELECT public.is_admin())) WITH CHECK ((SELECT public.is_admin()));
CREATE POLICY customer_monthly_bills_delete ON public.customer_monthly_bills
FOR DELETE TO authenticated USING ((SELECT public.is_admin()));

-- Payments: admin CRUD, customer own-row SELECT only.
DROP POLICY IF EXISTS "Admins full access customer payments" ON public.customer_payments;
DROP POLICY IF EXISTS "Customer can view own payments" ON public.customer_payments;
DROP POLICY IF EXISTS customer_payments_select ON public.customer_payments;
DROP POLICY IF EXISTS customer_payments_insert ON public.customer_payments;
DROP POLICY IF EXISTS customer_payments_update ON public.customer_payments;
DROP POLICY IF EXISTS customer_payments_delete ON public.customer_payments;
CREATE POLICY customer_payments_select ON public.customer_payments
FOR SELECT TO authenticated
USING (
  (SELECT public.is_admin()) OR EXISTS (
    SELECT 1 FROM public.customers c
    WHERE c.id = customer_payments.customer_id
      AND c.auth_user_id = (SELECT auth.uid()) AND c.is_active = true
  )
);
CREATE POLICY customer_payments_insert ON public.customer_payments
FOR INSERT TO authenticated WITH CHECK ((SELECT public.is_admin()));
CREATE POLICY customer_payments_update ON public.customer_payments
FOR UPDATE TO authenticated USING ((SELECT public.is_admin())) WITH CHECK ((SELECT public.is_admin()));
CREATE POLICY customer_payments_delete ON public.customer_payments
FOR DELETE TO authenticated USING ((SELECT public.is_admin()));

-- Customers: admin CRUD subject to column grants; customer own profile SELECT.
DROP POLICY IF EXISTS "Admins full access customers" ON public.customers;
DROP POLICY IF EXISTS "Customer can view own profile" ON public.customers;
DROP POLICY IF EXISTS customers_select ON public.customers;
DROP POLICY IF EXISTS customers_insert ON public.customers;
DROP POLICY IF EXISTS customers_update ON public.customers;
DROP POLICY IF EXISTS customers_delete ON public.customers;
CREATE POLICY customers_select ON public.customers
FOR SELECT TO authenticated
USING (
  (SELECT public.is_admin()) OR
  (auth_user_id = (SELECT auth.uid()) AND is_active = true)
);
CREATE POLICY customers_insert ON public.customers
FOR INSERT TO authenticated WITH CHECK ((SELECT public.is_admin()));
CREATE POLICY customers_update ON public.customers
FOR UPDATE TO authenticated USING ((SELECT public.is_admin())) WITH CHECK ((SELECT public.is_admin()));
CREATE POLICY customers_delete ON public.customers
FOR DELETE TO authenticated USING ((SELECT public.is_admin()));

-- Notifications: customer SELECT is own-row only; only admins may mutate notices.
DROP POLICY IF EXISTS customer_notifications_admin_all ON public.customer_notifications;
DROP POLICY IF EXISTS customer_notifications_own_select ON public.customer_notifications;
DROP POLICY IF EXISTS customer_notifications_own_update ON public.customer_notifications;
DROP POLICY IF EXISTS customer_notifications_select ON public.customer_notifications;
DROP POLICY IF EXISTS customer_notifications_insert ON public.customer_notifications;
DROP POLICY IF EXISTS customer_notifications_update ON public.customer_notifications;
DROP POLICY IF EXISTS customer_notifications_delete ON public.customer_notifications;
CREATE POLICY customer_notifications_select ON public.customer_notifications
FOR SELECT TO authenticated
USING (
  (SELECT public.is_admin()) OR EXISTS (
    SELECT 1 FROM public.customers c
    WHERE c.id = customer_notifications.customer_id
      AND c.auth_user_id = (SELECT auth.uid()) AND c.is_active = true
  )
);
CREATE POLICY customer_notifications_insert ON public.customer_notifications
FOR INSERT TO authenticated WITH CHECK ((SELECT public.is_admin()));
CREATE POLICY customer_notifications_update ON public.customer_notifications
FOR UPDATE TO authenticated USING ((SELECT public.is_admin())) WITH CHECK ((SELECT public.is_admin()));
CREATE POLICY customer_notifications_delete ON public.customer_notifications
FOR DELETE TO authenticated USING ((SELECT public.is_admin()));

-- mark_customer_notification_read remains SECURITY DEFINER because customers
-- must not receive direct UPDATE privileges on notification content. Its body
-- updates only the notification whose customer is linked to auth.uid().

-- Complaints: customer may submit a new complaint and view only their own;
-- administrators can view, reply/update, and manage all complaints.
DROP POLICY IF EXISTS customer_complaints_admin_all ON public.customer_complaints;
DROP POLICY IF EXISTS customer_complaints_own_insert ON public.customer_complaints;
DROP POLICY IF EXISTS customer_complaints_own_select ON public.customer_complaints;
DROP POLICY IF EXISTS customer_complaints_select ON public.customer_complaints;
DROP POLICY IF EXISTS customer_complaints_insert ON public.customer_complaints;
DROP POLICY IF EXISTS customer_complaints_update ON public.customer_complaints;
DROP POLICY IF EXISTS customer_complaints_delete ON public.customer_complaints;
CREATE POLICY customer_complaints_select ON public.customer_complaints
FOR SELECT TO authenticated
USING (
  (SELECT public.is_admin()) OR EXISTS (
    SELECT 1 FROM public.customers c
    WHERE c.id = customer_complaints.customer_id
      AND c.auth_user_id = (SELECT auth.uid()) AND c.is_active = true
  )
);
CREATE POLICY customer_complaints_insert ON public.customer_complaints
FOR INSERT TO authenticated
WITH CHECK (
  (SELECT public.is_admin()) OR (
    status = 'new' AND admin_note IS NULL AND EXISTS (
      SELECT 1 FROM public.customers c
      WHERE c.id = customer_complaints.customer_id
        AND c.auth_user_id = (SELECT auth.uid()) AND c.is_active = true
    )
  )
);
CREATE POLICY customer_complaints_update ON public.customer_complaints
FOR UPDATE TO authenticated USING ((SELECT public.is_admin())) WITH CHECK ((SELECT public.is_admin()));
CREATE POLICY customer_complaints_delete ON public.customer_complaints
FOR DELETE TO authenticated USING ((SELECT public.is_admin()));

-- Profiles: combine admin and own-active-profile SELECT into one policy.
DROP POLICY IF EXISTS admins_manage_profiles ON public.profiles;
DROP POLICY IF EXISTS users_view_own_active_profile ON public.profiles;
DROP POLICY IF EXISTS profiles_select ON public.profiles;
DROP POLICY IF EXISTS profiles_insert ON public.profiles;
DROP POLICY IF EXISTS profiles_update ON public.profiles;
DROP POLICY IF EXISTS profiles_delete ON public.profiles;
CREATE POLICY profiles_select ON public.profiles
FOR SELECT TO authenticated
USING (
  (SELECT public.is_admin()) OR
  (id = (SELECT auth.uid()) AND (
    role = 'admin' OR EXISTS (
      SELECT 1 FROM public.customers c
      WHERE c.auth_user_id = (SELECT auth.uid()) AND c.is_active = true
    )
  ))
);
CREATE POLICY profiles_insert ON public.profiles
FOR INSERT TO authenticated WITH CHECK ((SELECT public.is_admin()));
CREATE POLICY profiles_update ON public.profiles
FOR UPDATE TO authenticated USING ((SELECT public.is_admin())) WITH CHECK ((SELECT public.is_admin()));
CREATE POLICY profiles_delete ON public.profiles
FOR DELETE TO authenticated USING ((SELECT public.is_admin()));
