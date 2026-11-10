alter table public.customers
  add column if not exists approved_at timestamptz;

update public.customers
set approved_at = coalesce(created_at, now())
where is_active is true
  and approved_at is null;

create or replace function private.mpw_set_customer_approval_timestamp()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if new.is_active is true then
    if tg_op = 'INSERT' then
      new.approved_at := coalesce(new.approved_at, now());
    else
      new.approved_at := coalesce(old.approved_at, new.approved_at, now());
    end if;
  elsif tg_op = 'INSERT' then
    new.approved_at := null;
  else
    new.approved_at := old.approved_at;
  end if;
  return new;
end;
$function$;

drop trigger if exists mpw_customer_approval_timestamp on public.customers;
create trigger mpw_customer_approval_timestamp
before insert or update of is_active, approved_at
on public.customers
for each row
execute function private.mpw_set_customer_approval_timestamp();

revoke all on function private.mpw_set_customer_approval_timestamp() from public, anon, authenticated;

comment on column public.customers.approved_at is
  'Timestamp when the customer account was first approved. Preserved when an approved account is later deactivated.';
