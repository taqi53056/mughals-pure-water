-- Preserve the effective start date of every unregistered monthly account.
-- Existing accounts retain their original creation date; new accounts must pass an explicit start date.

alter table public.unregistered_monthly_customers
  add column if not exists start_date date;

update public.unregistered_monthly_customers
set start_date = (created_at at time zone 'Asia/Karachi')::date
where start_date is null;

alter table public.unregistered_monthly_customers
  alter column start_date set default (timezone('Asia/Karachi', now()))::date,
  alter column start_date set not null;

create index if not exists unregistered_monthly_customers_start_date_idx
  on public.unregistered_monthly_customers(start_date);

-- Five-argument creator: idempotency now includes the effective start date.
create or replace function private.create_unregistered_monthly_customer(
  p_name text,
  p_mobile text,
  p_address text,
  p_start_date date,
  p_request_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_existing public.unregistered_monthly_customers%rowtype;
  v_id bigint;
  v_today date := (timezone('Asia/Karachi', now()))::date;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'صرف مجاز منتظم ماہانہ کھاتہ بنا سکتا ہے۔' using errcode='42501';
  end if;

  if p_request_id is null
     or p_name is null
     or length(btrim(p_name)) not between 2 and 120
     or (p_mobile is not null and length(btrim(p_mobile)) > 30)
     or (p_address is not null and length(btrim(p_address)) > 300)
     or p_start_date is null
     or p_start_date > v_today then
    raise exception 'نام، موبائل، پتہ یا ماہانہ کھاتے کی آغاز کی تاریخ درست درج کریں۔' using errcode='22023';
  end if;

  select * into v_existing
  from public.unregistered_monthly_customers
  where request_id = p_request_id;

  if found then
    if v_existing.name <> btrim(p_name)
       or v_existing.mobile is distinct from nullif(btrim(p_mobile),'')
       or v_existing.address is distinct from nullif(btrim(p_address),'')
       or v_existing.start_date is distinct from p_start_date then
      raise exception 'یہ درخواست پہلے مختلف تفصیل کے ساتھ محفوظ ہو چکی ہے۔' using errcode='23505';
    end if;
    return jsonb_build_object('id',v_existing.id,'already_saved',true);
  end if;

  insert into public.unregistered_monthly_customers(
    name,mobile,address,start_date,request_id,entered_by
  )
  values(
    btrim(p_name),nullif(btrim(p_mobile),''),nullif(btrim(p_address),''),
    p_start_date,p_request_id,auth.uid()
  )
  returning id into v_id;

  return jsonb_build_object('id',v_id,'already_saved',false);
end
$function$;

create or replace function public.create_unregistered_monthly_customer(
  p_name text,
  p_mobile text,
  p_address text,
  p_start_date date,
  p_request_id uuid
) returns jsonb
language sql
set search_path=''
as $function$
  select private.create_unregistered_monthly_customer($1,$2,$3,$4,$5);
$function$;

revoke all on function private.create_unregistered_monthly_customer(text,text,text,date,uuid) from public,anon;
grant execute on function private.create_unregistered_monthly_customer(text,text,text,date,uuid) to authenticated;
revoke all on function public.create_unregistered_monthly_customer(text,text,text,date,uuid) from public,anon;
grant execute on function public.create_unregistered_monthly_customer(text,text,text,date,uuid) to authenticated;

-- Enforce the effective start date at the trusted monthly-delivery RPC boundary.
create or replace function private.record_monthly_unregistered_delivery(
  p_customer_id bigint,
  p_delivery_date date,
  p_worker_id bigint,
  p_bottles_delivered integer,
  p_empty_bottles_returned integer,
  p_damaged_caps integer,
  p_performed_by_owner boolean,
  p_request_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_customer public.unregistered_monthly_customers%rowtype;
  v_result jsonb;
  v_id bigint;
  v_existing public.unassigned_19l_deliveries%rowtype;
  v_already boolean;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'صرف مجاز منتظم ماہانہ سپلائی درج کر سکتا ہے۔' using errcode='42501';
  end if;
  if p_customer_id is null then
    raise exception 'ماہانہ کھاتہ منتخب کریں۔' using errcode='22023';
  end if;

  select * into v_customer
  from public.unregistered_monthly_customers
  where id=p_customer_id and is_active=true;

  if not found then
    raise exception 'ماہانہ کھاتہ موجود نہیں یا غیر فعال ہے۔' using errcode='P0002';
  end if;

  if p_delivery_date is null or p_delivery_date < v_customer.start_date then
    raise exception 'سپلائی کی تاریخ ماہانہ کھاتے کے آغاز ('||v_customer.start_date::text||') سے پہلے نہیں ہو سکتی۔' using errcode='22023';
  end if;

  v_result:=public.record_unassigned_19l_delivery(
    p_delivery_date,p_worker_id,p_bottles_delivered,
    coalesce(p_empty_bottles_returned,0),null,p_request_id,
    coalesce(p_damaged_caps,0),coalesce(p_performed_by_owner,false)
  );
  v_id:=(v_result->>'id')::bigint;
  v_already:=coalesce((v_result->>'already_saved')::boolean,false);

  select * into v_existing
  from public.unassigned_19l_deliveries
  where id=v_id for update;

  if not found then
    raise exception 'محفوظ سپلائی ریکارڈ نہیں ملا۔' using errcode='P0002';
  end if;

  if v_already then
    if v_existing.customer_classification<>'monthly'
       or v_existing.monthly_customer_id is distinct from p_customer_id then
      raise exception 'یہ درخواست پہلے کسی دوسری قسم یا کھاتے میں محفوظ ہو چکی ہے۔' using errcode='23505';
    end if;
  else
    update public.unassigned_19l_deliveries
      set customer_classification='monthly',monthly_customer_id=p_customer_id
      where id=v_id
        and customer_classification='one_time'
        and monthly_customer_id is null;

    if not found then
      raise exception 'ماہانہ کھاتے سے سپلائی منسلک نہیں ہو سکی۔' using errcode='23514';
    end if;
  end if;

  return v_result || jsonb_build_object(
    'customer_id',p_customer_id,
    'customer_name',v_customer.name,
    'customer_classification','monthly'
  );
end
$function$;

revoke all on function private.record_monthly_unregistered_delivery(bigint,date,bigint,integer,integer,integer,boolean,uuid) from public,anon;
grant execute on function private.record_monthly_unregistered_delivery(bigint,date,bigint,integer,integer,integer,boolean,uuid) to authenticated;

comment on column public.unregistered_monthly_customers.start_date is
  'Effective date from which monthly 19L deliveries and account statements apply.';
