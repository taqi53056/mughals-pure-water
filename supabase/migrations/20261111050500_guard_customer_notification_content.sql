create or replace function private.mpw_guard_customer_notification_update()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  if public.is_admin() then
    return new;
  end if;

  if (new.id,new.customer_id,new.title,new.message,new.notification_type,new.reference_key,new.created_at)
     is distinct from
     (old.id,old.customer_id,old.title,old.message,old.notification_type,old.reference_key,old.created_at) then
    raise exception 'گاہک صرف اپنی اطلاع کو پڑھا ہوا نشان زد کرسکتا ہے۔'
      using errcode = '42501';
  end if;

  return new;
end;
$function$;

drop trigger if exists mpw_customer_notification_update_guard on public.customer_notifications;
create trigger mpw_customer_notification_update_guard
before update on public.customer_notifications
for each row execute function private.mpw_guard_customer_notification_update();

comment on function private.mpw_guard_customer_notification_update() is
'Prevents customer accounts from editing notification content or ownership; customers may only change is_read. Admins may update notification content.';
