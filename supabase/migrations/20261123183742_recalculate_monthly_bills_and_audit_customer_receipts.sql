create or replace function private.recalculate_unregistered_monthly_bills_after_receipt()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_from_month date:=date_trunc('month',new.received_date)::date;
  v_last_month date;
  v_month date;
begin
  select max(b.bill_month)
    into v_last_month
  from public.unregistered_monthly_bills b
  where b.customer_id=new.customer_id
    and b.bill_month>=v_from_month;

  if v_last_month is not null then
    v_month:=v_from_month;
    while v_month<=v_last_month loop
      perform private.generate_unregistered_monthly_bills(v_month);
      v_month:=(v_month+interval '1 month')::date;
    end loop;
  end if;
  return new;
end;
$function$;

revoke all on function private.recalculate_unregistered_monthly_bills_after_receipt() from public,anon,authenticated;

drop trigger if exists unregistered_monthly_receipts_recalculate_bills on private.unregistered_monthly_customer_receipts;
create trigger unregistered_monthly_receipts_recalculate_bills
after insert on private.unregistered_monthly_customer_receipts
for each row execute function private.recalculate_unregistered_monthly_bills_after_receipt();

drop trigger if exists unregistered_monthly_receipts_audit_trigger on private.unregistered_monthly_customer_receipts;
create trigger unregistered_monthly_receipts_audit_trigger
after insert or update or delete on private.unregistered_monthly_customer_receipts
for each row execute function public.log_changes();
