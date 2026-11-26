alter table public.customer_notifications
  add column if not exists push_queue_eligible boolean not null default false,
  add column if not exists push_attempts integer not null default 0,
  add column if not exists push_last_attempt_at timestamptz,
  add column if not exists push_sent_at timestamptz,
  add column if not exists push_error text;

alter table public.customer_notifications
  drop constraint if exists customer_notifications_push_attempts_nonnegative;
alter table public.customer_notifications
  add constraint customer_notifications_push_attempts_nonnegative check (push_attempts>=0);

create index if not exists customer_notifications_pending_bill_push_idx
on public.customer_notifications(created_at,id)
where push_queue_eligible=true and push_sent_at is null and push_attempts<3;

do $$
begin
  if not exists(select 1 from vault.secrets where name='mpw_bill_push_cron_token') then
    perform vault.create_secret(
      replace(gen_random_uuid()::text||gen_random_uuid()::text,'-',''),
      'mpw_bill_push_cron_token',
      'Internal authentication token for scheduled MUGHALS PURE WATER bill push delivery'
    );
  end if;
end
$$;

create or replace function public.verify_mpw_bill_push_cron_token(p_token text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(auth.role()='service_role',false)
    and coalesce(p_token,'')<>''
    and exists(
      select 1 from vault.decrypted_secrets
      where name='mpw_bill_push_cron_token' and decrypted_secret=p_token
    );
$$;

revoke all on function public.verify_mpw_bill_push_cron_token(text) from public,anon,authenticated,service_role;
grant execute on function public.verify_mpw_bill_push_cron_token(text) to service_role;

create or replace function public.claim_pending_customer_bill_push(p_limit integer default 50)
returns table(notification_id bigint,customer_id bigint,title text,message text)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(auth.role(),'')<>'service_role' then
    raise exception 'Service role required' using errcode='42501';
  end if;

  return query
  with candidates as (
    select n.id
    from public.customer_notifications n
    where n.push_queue_eligible=true
      and n.push_sent_at is null
      and n.push_attempts<3
      and (n.push_last_attempt_at is null or n.push_last_attempt_at<now()-interval '5 minutes')
    order by n.created_at,n.id
    for update skip locked
    limit greatest(1,least(coalesce(p_limit,50),100))
  ),
  updated as (
    update public.customer_notifications n
    set push_attempts=n.push_attempts+1,
        push_last_attempt_at=now(),
        push_error=null
    from candidates c
    where n.id=c.id
    returning n.id,n.customer_id,n.title,n.message
  )
  select u.id,u.customer_id,u.title,u.message from updated u;
end;
$$;

revoke all on function public.claim_pending_customer_bill_push(integer) from public,anon,authenticated,service_role;
grant execute on function public.claim_pending_customer_bill_push(integer) to service_role;

create or replace function public.mark_customer_bill_push_result(
  p_notification_id bigint,p_sent boolean,p_error text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(auth.role(),'')<>'service_role' then
    raise exception 'Service role required' using errcode='42501';
  end if;

  if coalesce(p_sent,false) then
    update public.customer_notifications
    set push_sent_at=now(),push_queue_eligible=false,push_error=null
    where id=p_notification_id;
  else
    update public.customer_notifications
    set push_error=left(coalesce(p_error,'Push delivery failed'),500)
    where id=p_notification_id and push_sent_at is null;
  end if;
end;
$$;

revoke all on function public.mark_customer_bill_push_result(bigint,boolean,text) from public,anon,authenticated,service_role;
grant execute on function public.mark_customer_bill_push_result(bigint,boolean,text) to service_role;

create or replace function private.reset_pending_bill_push_attempts_on_subscription()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.is_active=true and
     (tg_op='INSERT' or old.is_active is distinct from new.is_active) then
    update public.customer_notifications
    set push_attempts=0,push_last_attempt_at=null,push_error=null
    where customer_id=new.customer_id
      and notification_type='bill'
      and push_queue_eligible=true
      and push_sent_at is null;
  end if;
  return new;
end;
$$;

drop trigger if exists reset_pending_bill_push_attempts_on_subscription on public.customer_push_subscriptions;
create trigger reset_pending_bill_push_attempts_on_subscription
after insert or update of is_active on public.customer_push_subscriptions
for each row execute function private.reset_pending_bill_push_attempts_on_subscription();

alter function public.generate_month_end_customer_bills()
  rename to generate_month_end_customer_bills_legacy;

create or replace function public.generate_month_end_customer_bills()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
  v_local_date date:=timezone('Asia/Karachi',now())::date;
  v_month date;
begin
  v_count:=public.generate_month_end_customer_bills_legacy();
  if v_count>0 then
    if v_local_date=(date_trunc('month',v_local_date::timestamp)+interval '1 month - 1 day')::date then
      v_month:=date_trunc('month',v_local_date::timestamp)::date;
    else
      v_month:=(date_trunc('month',v_local_date::timestamp)-interval '1 month')::date;
    end if;

    update public.customer_notifications
    set push_queue_eligible=true
    where notification_type='bill'
      and reference_key='bill:'||to_char(v_month,'YYYY-MM')
      and push_sent_at is null
      and push_queue_eligible=false;
  end if;
  return coalesce(v_count,0);
end;
$$;

revoke all on function public.generate_month_end_customer_bills() from public,anon,authenticated,service_role;

create or replace function private.invoke_mpw_bill_push()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text;
  v_request_id bigint;
begin
  select decrypted_secret into v_token
  from vault.decrypted_secrets
  where name='mpw_bill_push_cron_token'
  limit 1;

  if coalesce(v_token,'')='' then
    raise exception 'Scheduled bill-push token is missing';
  end if;

  v_request_id:=net.http_post(
    url:='https://tosxnmnqlufeuknrhxzr.supabase.co/functions/v1/send-pending-customer-bill-push',
    body:='{}'::jsonb,
    headers:=jsonb_build_object('Content-Type','application/json','x-internal-token',v_token),
    timeout_milliseconds:=10000
  );
  return v_request_id;
end;
$$;

revoke all on function private.invoke_mpw_bill_push() from public,anon,authenticated,service_role;

do $$
begin
  if not exists(select 1 from cron.job where jobname='mpw-customer-bill-push') then
    perform cron.schedule('mpw-customer-bill-push','*/5 * * * *','select private.invoke_mpw_bill_push();');
  end if;
end
$$;

comment on column public.customer_notifications.push_queue_eligible is
'True only for monthly bill notifications queued for server-side mobile push delivery.';
comment on function public.generate_month_end_customer_bills() is
'Generates month-end bills and queues their customer bill notifications for scheduled mobile push delivery.';