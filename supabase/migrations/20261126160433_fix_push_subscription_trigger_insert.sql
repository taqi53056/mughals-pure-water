create or replace function private.reset_pending_bill_push_attempts_on_subscription()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.is_active=true then
    if tg_op='INSERT' then
      update public.customer_notifications
      set push_attempts=0,push_last_attempt_at=null,push_error=null
      where customer_id=new.customer_id
        and notification_type='bill'
        and push_queue_eligible=true
        and push_sent_at is null;
    elsif old.is_active is distinct from new.is_active then
      update public.customer_notifications
      set push_attempts=0,push_last_attempt_at=null,push_error=null
      where customer_id=new.customer_id
        and notification_type='bill'
        and push_queue_eligible=true
        and push_sent_at is null;
    end if;
  end if;
  return new;
end;
$$;