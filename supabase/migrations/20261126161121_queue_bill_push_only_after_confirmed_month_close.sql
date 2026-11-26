alter function private.close_business_month(date,boolean)
  rename to close_business_month_legacy;

create or replace function private.close_business_month(p_month_start date,p_expenses_confirmed boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  v_result:=private.close_business_month_legacy(p_month_start,p_expenses_confirmed);

  if v_result->>'status'='closed' then
    update public.customer_notifications
    set push_queue_eligible=true
    where notification_type='bill'
      and reference_key='bill:'||to_char(p_month_start,'YYYY-MM')
      and push_sent_at is null
      and push_queue_eligible=false;
  end if;

  return v_result;
end;
$$;

revoke all on function private.close_business_month(date,boolean) from public,anon,authenticated,service_role;
grant execute on function private.close_business_month(date,boolean) to authenticated,postgres;

create or replace function public.generate_month_end_customer_bills()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
begin
  return coalesce(public.generate_month_end_customer_bills_legacy(),0);
end;
$$;

revoke all on function public.generate_month_end_customer_bills() from public,anon,authenticated,service_role;

comment on function private.close_business_month(date,boolean) is
'Closes the month only after explicit admin expense confirmation, then queues that month''s registered-customer bill notifications for mobile push.';