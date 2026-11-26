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
    elsif old.is_active is distinct from new.is_active
       or old.endpoint is distinct from new.endpoint
       or old.p256dh is distinct from new.p256dh
       or old.auth is distinct from new.auth then
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

drop trigger if exists reset_pending_bill_push_attempts_on_subscription on public.customer_push_subscriptions;
create trigger reset_pending_bill_push_attempts_on_subscription
after insert or update of is_active,endpoint,p256dh,auth on public.customer_push_subscriptions
for each row execute function private.reset_pending_bill_push_attempts_on_subscription();