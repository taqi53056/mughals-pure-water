-- Security/performance hardening for the customer-level monthly receipt RPC.
-- The exposed public RPC is SECURITY INVOKER; the guarded implementation stays in private.

create index if not exists unregistered_monthly_customer_receipts_customer_id_idx
  on private.unregistered_monthly_customer_receipts(customer_id);

drop policy if exists unregistered_monthly_customer_receipts_admin_only
  on private.unregistered_monthly_customer_receipts;
create policy unregistered_monthly_customer_receipts_admin_only
  on private.unregistered_monthly_customer_receipts
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create or replace function private.record_unregistered_monthly_customer_collection(
  p_customer_id bigint,
  p_received_date date,
  p_amount numeric,
  p_payment_method text,
  p_request_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_customer public.unregistered_monthly_customers%rowtype;
  v_delivery public.unassigned_19l_deliveries%rowtype;
  v_existing private.unregistered_monthly_customer_receipts%rowtype;
  v_due numeric(14,2);
  v_collected numeric(14,2);
  v_total_due numeric(14,2) := 0;
  v_remaining numeric(14,2);
  v_allocation numeric(14,2);
  v_child_request uuid;
  v_child_result jsonb;
  v_allocations jsonb := '[]'::jsonb;
  v_today date := (now() at time zone 'Asia/Karachi')::date;
  v_receipt_id bigint;
  v_remaining_due numeric(14,2);
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'صرف مجاز ایڈمن ماہانہ گاہک کی وصولی درج کر سکتا ہے۔' using errcode='42501';
  end if;
  if p_customer_id is null or p_received_date is null or p_received_date > v_today
     or p_amount is null or p_amount <= 0 or p_request_id is null
     or p_payment_method is null
     or p_payment_method not in ('cash','bank','easypaisa','jazzcash') then
    raise exception 'گاہک، تاریخ، رقم، طریقہ اور درخواست کی شناخت درست درج کریں۔' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('mpw-monthly-customer-collection-'||p_customer_id::text,0));
  select * into v_existing
  from private.unregistered_monthly_customer_receipts
  where request_id=p_request_id
  for update;
  if found then
    if v_existing.customer_id<>p_customer_id
       or v_existing.received_date<>p_received_date
       or v_existing.amount<>p_amount
       or v_existing.payment_method<>p_payment_method then
      raise exception 'یہ درخواست پہلے مختلف تفصیل کے ساتھ محفوظ ہو چکی ہے۔' using errcode='23505';
    end if;
    select coalesce(sum(greatest(d.bottles_delivered::numeric*100+d.damaged_caps::numeric*10-
      coalesce((select sum(x.amount) from public.unassigned_19l_delivery_collections x where x.delivery_id=d.id),0),0)),0)
    into v_remaining_due
    from public.unassigned_19l_deliveries d
    where d.customer_classification='monthly' and d.monthly_customer_id=p_customer_id;
    return jsonb_build_object('id',v_existing.id,'allocations',v_existing.allocations,
      'remaining_due',v_remaining_due,'already_saved',true);
  end if;

  select * into v_customer from public.unregistered_monthly_customers where id=p_customer_id for update;
  if not found then raise exception 'منتخب ماہانہ گاہک کا کھاتہ موجود نہیں۔' using errcode='P0002'; end if;

  perform pg_advisory_xact_lock(hashtextextended('mpw-month-close-'||date_trunc('month',p_received_date)::date::text,0));
  if exists(select 1 from public.business_month_closings c
    where c.month_start=date_trunc('month',p_received_date)::date and c.status='closed') then
    raise exception 'یہ مہینہ بند ہو چکا ہے؛ وصولی درج نہیں ہو سکتی۔' using errcode='55000';
  end if;

  for v_delivery in
    select d.* from public.unassigned_19l_deliveries d
    where d.customer_classification='monthly' and d.monthly_customer_id=p_customer_id
      and d.delivery_date<=p_received_date
    order by d.delivery_date,d.id for update
  loop
    v_due:=v_delivery.bottles_delivered::numeric*100+v_delivery.damaged_caps::numeric*10;
    select coalesce(sum(x.amount),0) into v_collected from public.unassigned_19l_delivery_collections x where x.delivery_id=v_delivery.id;
    v_total_due:=v_total_due+greatest(v_due-v_collected,0);
  end loop;

  if p_amount>v_total_due then
    raise exception 'وصولی تاریخ تک دستیاب بقایا سے زیادہ ہے۔ دستیاب بقایا: %',greatest(v_total_due,0) using errcode='23514';
  end if;
  if v_total_due<=0 then raise exception 'اس تاریخ تک اس گاہک کی کوئی واجب الادا سپلائی موجود نہیں۔' using errcode='23514'; end if;

  insert into private.unregistered_monthly_customer_receipts(customer_id,received_date,amount,payment_method,request_id,entered_by)
  values(p_customer_id,p_received_date,p_amount,p_payment_method,p_request_id,auth.uid())
  returning id into v_receipt_id;

  v_remaining:=p_amount;
  for v_delivery in
    select d.* from public.unassigned_19l_deliveries d
    where d.customer_classification='monthly' and d.monthly_customer_id=p_customer_id
      and d.delivery_date<=p_received_date
    order by d.delivery_date,d.id for update
  loop
    exit when v_remaining<=0;
    v_due:=v_delivery.bottles_delivered::numeric*100+v_delivery.damaged_caps::numeric*10;
    select coalesce(sum(x.amount),0) into v_collected from public.unassigned_19l_delivery_collections x where x.delivery_id=v_delivery.id;
    v_allocation:=least(v_remaining,greatest(v_due-v_collected,0));
    if v_allocation>0 then
      v_child_request:=md5(p_request_id::text||':'||v_delivery.id::text)::uuid;
      v_child_result:=private.record_unassigned_19l_collection(v_delivery.id,p_received_date,v_allocation,p_payment_method,v_child_request);
      v_allocations:=v_allocations||jsonb_build_array(jsonb_build_object(
        'delivery_id',v_delivery.id,'collection_id',(v_child_result->>'id')::bigint,'amount',v_allocation));
      v_remaining:=v_remaining-v_allocation;
    end if;
  end loop;

  update private.unregistered_monthly_customer_receipts set allocations=v_allocations where id=v_receipt_id;
  select coalesce(sum(greatest(d.bottles_delivered::numeric*100+d.damaged_caps::numeric*10-
    coalesce((select sum(x.amount) from public.unassigned_19l_delivery_collections x where x.delivery_id=d.id),0),0)),0)
  into v_remaining_due from public.unassigned_19l_deliveries d
  where d.customer_classification='monthly' and d.monthly_customer_id=p_customer_id;
  return jsonb_build_object('id',v_receipt_id,'allocations',v_allocations,'remaining_due',v_remaining_due,'already_saved',false);
end;
$function$;

revoke all on function private.record_unregistered_monthly_customer_collection(bigint,date,numeric,text,uuid) from public, anon;
grant execute on function private.record_unregistered_monthly_customer_collection(bigint,date,numeric,text,uuid) to authenticated;

create or replace function public.record_unregistered_monthly_customer_collection(
  p_customer_id bigint,p_received_date date,p_amount numeric,p_payment_method text,p_request_id uuid
) returns jsonb
language sql
security invoker
set search_path = ''
as $function$
  select private.record_unregistered_monthly_customer_collection($1,$2,$3,$4,$5);
$function$;
revoke all on function public.record_unregistered_monthly_customer_collection(bigint,date,numeric,text,uuid) from public, anon;
grant execute on function public.record_unregistered_monthly_customer_collection(bigint,date,numeric,text,uuid) to authenticated;
