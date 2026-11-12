-- Audit coverage for financial and production allocation records.
-- Applied to Supabase migration version 20261112085121.

CREATE TRIGGER audit_trigger
AFTER INSERT OR UPDATE OR DELETE ON public.business_capital_entries
FOR EACH ROW EXECUTE FUNCTION public.log_changes();

CREATE TRIGGER audit_trigger
AFTER INSERT OR UPDATE OR DELETE ON public.business_finance_ledger
FOR EACH ROW EXECUTE FUNCTION public.log_changes();

CREATE TRIGGER audit_trigger
AFTER INSERT OR UPDATE OR DELETE ON public.product_cost_rates
FOR EACH ROW EXECUTE FUNCTION public.log_changes();

CREATE TRIGGER audit_trigger
AFTER INSERT OR UPDATE OR DELETE ON public.production_worker_allocations
FOR EACH ROW EXECUTE FUNCTION public.log_changes();

CREATE OR REPLACE FUNCTION private.log_business_month_closing_changes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.audit_log(table_name,record_id,action,new_data,changed_by)
    VALUES ('business_month_closings',NEW.month_start::text,'INSERT',to_jsonb(NEW),COALESCE(auth.uid(),NEW.closed_by));
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    INSERT INTO public.audit_log(table_name,record_id,action,old_data,new_data,changed_by)
    VALUES ('business_month_closings',NEW.month_start::text,'UPDATE',to_jsonb(OLD),to_jsonb(NEW),COALESCE(auth.uid(),NEW.closed_by,OLD.closed_by));
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    INSERT INTO public.audit_log(table_name,record_id,action,old_data,changed_by)
    VALUES ('business_month_closings',OLD.month_start::text,'DELETE',to_jsonb(OLD),COALESCE(auth.uid(),OLD.closed_by));
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$function$;

REVOKE EXECUTE ON FUNCTION private.log_business_month_closing_changes() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER business_month_closings_audit_trigger
AFTER INSERT OR UPDATE OR DELETE ON public.business_month_closings
FOR EACH ROW EXECUTE FUNCTION private.log_business_month_closing_changes();
