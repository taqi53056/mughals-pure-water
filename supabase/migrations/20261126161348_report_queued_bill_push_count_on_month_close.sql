create or replace function private.close_business_month(p_month_start date,p_expenses_confirmed boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
  v_queued integer:=0;
begin
  v_result:=private.close_business_month_legacy(p_month_start,p_expenses_confirmed);

  if v_result->>'status'='closed' then
    update public.customer_notifications
    set push_queue_eligible=true
    where notification_type='bill'
      and reference_key='bill:'||to_char(p_month_start,'YYYY-MM')
      and push_sent_at is null
      and push_queue_eligible=false;
    get diagnostics v_queued = row_count;
  end if;

  v_result:=jsonb_set(v_result,'{bill_push_queued}',to_jsonb(v_queued),true);
  return v_result;
end;
$$;

revoke all on function private.close_business_month(date,boolean) from public,anon,authenticated,service_role;
grant execute on function private.close_business_month(date,boolean) to authenticated,postgres;