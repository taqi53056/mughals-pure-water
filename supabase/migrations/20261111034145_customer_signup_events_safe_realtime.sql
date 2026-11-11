-- Publish only a minimal, admin-only event for customer signups.
-- The customers table intentionally has column-level grants only; do not grant table SELECT.
create table public.customer_signup_events (
  id bigint generated always as identity primary key,
  customer_id bigint not null unique
    references public.customers(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.customer_signup_events enable row level security;
alter table public.customer_signup_events force row level security;

revoke all on table public.customer_signup_events from public, anon, authenticated;
grant select on table public.customer_signup_events to authenticated;

create policy customer_signup_events_admin_select
on public.customer_signup_events
for select
to authenticated
using ((select public.is_admin()));

create or replace function private.mpw_emit_customer_signup_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.is_active is false and new.approved_at is null then
    insert into public.customer_signup_events(customer_id)
    values (new.id)
    on conflict (customer_id) do nothing;
  end if;
  return new;
end;
$function$;

revoke all on function private.mpw_emit_customer_signup_event()
from public, anon, authenticated;

drop trigger if exists mpw_emit_customer_signup_event on public.customers;
create trigger mpw_emit_customer_signup_event
after insert on public.customers
for each row
execute function private.mpw_emit_customer_signup_event();

-- Remove the sensitive customers table from Realtime publication.
alter publication supabase_realtime drop table public.customers;
alter publication supabase_realtime add table public.customer_signup_events;
