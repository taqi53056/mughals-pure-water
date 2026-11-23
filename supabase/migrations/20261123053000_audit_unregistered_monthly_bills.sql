drop trigger if exists unregistered_monthly_bills_audit_trigger on public.unregistered_monthly_bills;
create trigger unregistered_monthly_bills_audit_trigger
  after insert or update or delete on public.unregistered_monthly_bills
  for each row execute function public.log_changes();
