CREATE OR REPLACE FUNCTION private.unregistered_monthly_customer_paid_before(p_customer_id bigint, p_cutoff date)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select
    coalesce((select sum(r.amount)
      from private.unregistered_monthly_customer_receipts r
      where r.customer_id=p_customer_id and r.received_date<p_cutoff),0)
    +
    coalesce((select sum(rc.amount)
      from public.unassigned_19l_delivery_collections rc
      join public.unassigned_19l_deliveries d on d.id=rc.delivery_id
      where d.monthly_customer_id=p_customer_id
        and d.customer_classification='monthly'
        and rc.received_date<p_cutoff
        and not exists (
          select 1
          from private.unregistered_monthly_customer_receipts parent
          cross join lateral jsonb_array_elements(coalesce(parent.allocations,'[]'::jsonb)) allocation
          where (allocation->>'collection_id')::bigint=rc.id
        )),0);
$function$


CREATE OR REPLACE FUNCTION private.record_unregistered_monthly_customer_collection(p_customer_id bigint, p_received_date date, p_amount numeric, p_payment_method text, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_customer public.unregistered_monthly_customers%rowtype;
  v_existing private.unregistered_monthly_customer_receipts%rowtype;
  v_today date := (now() at time zone 'Asia/Karachi')::date;
  v_charges numeric(14,2);
  v_paid_at_date numeric(14,2);
  v_available_due numeric(14,2);
  v_all_paid numeric(14,2);
  v_remaining_due numeric(14,2);
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'صرف مجاز ایڈمن ماہانہ گاہک کی وصولی درج کر سکتا ہے۔' using errcode='42501';
  end if;
  if p_customer_id is null or p_received_date is null or p_received_date>v_today
     or p_amount is null or p_amount<=0 or p_request_id is null
     or p_payment_method is null
     or p_payment_method not in ('cash','bank','easypaisa','jazzcash') then
    raise exception 'گاہک، تاریخ، کل رقم، طریقہ اور درخواست کی شناخت درست درج کریں۔' using errcode='22023';
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
    select coalesce(sum(d.bottles_delivered::numeric*100+d.damaged_caps::numeric*10),0)
      into v_charges
    from public.unassigned_19l_deliveries d
    where d.monthly_customer_id=p_customer_id and d.customer_classification='monthly';
    v_all_paid:=private.unregistered_monthly_customer_paid_before(p_customer_id,v_today+1);
    v_remaining_due:=greatest(v_charges-v_all_paid,0);
    return jsonb_build_object('id',v_existing.id,'receipt_amount',v_existing.amount,
      'remaining_due',v_remaining_due,'already_saved',true);
  end if;

  select * into v_customer
  from public.unregistered_monthly_customers
  where id=p_customer_id
  for update;
  if not found then
    raise exception 'منتخب ماہانہ گاہک کا کھاتہ موجود نہیں۔' using errcode='P0002';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('mpw-month-close-'||date_trunc('month',p_received_date)::date::text,0));
  if exists(select 1 from public.business_month_closings c
    where c.month_start=date_trunc('month',p_received_date)::date and c.status='closed') then
    raise exception 'یہ مہینہ بند ہو چکا ہے؛ وصولی درج نہیں ہو سکتی۔' using errcode='55000';
  end if;

  select coalesce(sum(d.bottles_delivered::numeric*100+d.damaged_caps::numeric*10),0)
    into v_charges
  from public.unassigned_19l_deliveries d
  where d.monthly_customer_id=p_customer_id
    and d.customer_classification='monthly'
    and d.delivery_date<=p_received_date;

  v_paid_at_date:=private.unregistered_monthly_customer_paid_before(p_customer_id,p_received_date+1);
  v_available_due:=greatest(v_charges-v_paid_at_date,0);
  if v_available_due<=0 then
    raise exception 'اس تاریخ تک اس گاہک کا کوئی بقایا موجود نہیں۔' using errcode='23514';
  end if;
  if p_amount>v_available_due then
    raise exception 'وصولی دستیاب مجموعی بقایا سے زیادہ نہیں ہو سکتی۔ دستیاب بقایا: %',v_available_due using errcode='23514';
  end if;

  insert into private.unregistered_monthly_customer_receipts(
    customer_id,received_date,amount,payment_method,request_id,allocations,entered_by
  ) values (
    p_customer_id,p_received_date,p_amount,p_payment_method,p_request_id,'[]'::jsonb,auth.uid()
  ) returning * into v_existing;

  select coalesce(sum(d.bottles_delivered::numeric*100+d.damaged_caps::numeric*10),0)
    into v_charges
  from public.unassigned_19l_deliveries d
  where d.monthly_customer_id=p_customer_id and d.customer_classification='monthly';
  v_all_paid:=private.unregistered_monthly_customer_paid_before(p_customer_id,v_today+1);
  v_remaining_due:=greatest(v_charges-v_all_paid,0);

  return jsonb_build_object('id',v_existing.id,'receipt_amount',v_existing.amount,
    'remaining_due',v_remaining_due,'already_saved',false);
end;
$function$




CREATE OR REPLACE FUNCTION private.list_unregistered_monthly_customer_receipts(p_customer_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'صرف مجاز ایڈمن ماہانہ گاہک کی وصولیاں دیکھ سکتا ہے۔' using errcode='42501';
  end if;
  if p_customer_id is null or p_customer_id<=0 then
    raise exception 'ماہانہ گاہک منتخب کرنا ضروری ہے۔' using errcode='22023';
  end if;
  if not exists(select 1 from public.unregistered_monthly_customers c where c.id=p_customer_id) then
    raise exception 'منتخب ماہانہ گاہک کا کھاتہ موجود نہیں۔' using errcode='P0002';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',receipt.id,
      'received_date',receipt.received_date,
      'amount',receipt.amount,
      'payment_method',receipt.payment_method,
      'receipt_label',receipt.receipt_label,
      'receipt_type',receipt.receipt_type
    ) order by receipt.received_date desc,receipt.sort_order desc,receipt.id desc)
    from (
      select r.id,r.received_date,r.amount,r.payment_method,
        'رسید نمبر: #'||r.id::text as receipt_label,
        'monthly'::text as receipt_type,1 as sort_order
      from private.unregistered_monthly_customer_receipts r
      where r.customer_id=p_customer_id
      union all
      select rc.id,rc.received_date,rc.amount,rc.payment_method,
        'سابقہ سپلائی وصولی #'||rc.id::text as receipt_label,
        'legacy_delivery'::text as receipt_type,0 as sort_order
      from public.unassigned_19l_delivery_collections rc
      join public.unassigned_19l_deliveries d on d.id=rc.delivery_id
      where d.monthly_customer_id=p_customer_id and d.customer_classification='monthly'
        and not exists (
          select 1
          from private.unregistered_monthly_customer_receipts parent
          cross join lateral jsonb_array_elements(coalesce(parent.allocations,'[]'::jsonb)) allocation
          where (allocation->>'collection_id')::bigint=rc.id
        )
    ) receipt
  ),'[]'::jsonb);
end;
$function$




CREATE OR REPLACE FUNCTION private.generate_unregistered_monthly_bills(p_month_start date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_month date:=date_trunc('month',p_month_start)::date;
  v_next date:=(date_trunc('month',p_month_start)+interval '1 month')::date;
  v_current_month date:=date_trunc('month',timezone('Asia/Karachi',now()))::date;
  c record;
  v_bottles integer;
  v_caps integer;
  v_bottle_amount numeric(14,2);
  v_cap_amount numeric(14,2);
  v_charges numeric(14,2);
  v_previous_due numeric(14,2);
  v_previous_advance numeric(14,2);
  v_payments numeric(14,2);
  v_advance_used numeric(14,2);
  v_due numeric(14,2);
  v_closing_advance numeric(14,2);
  v_historical_charges numeric(14,2);
  v_historical_payments numeric(14,2);
  v_count integer:=0;
begin
  if p_month_start is null or p_month_start<>v_month or v_month>v_current_month then
    raise exception 'درست مکمل ماہ منتخب کریں۔' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('mpw-month-close-'||v_month::text,0));

  if exists(select 1 from public.business_month_closings
    where month_start=v_month and status='closed') then
    return 0;
  end if;

  for c in
    select mc.id
    from public.unregistered_monthly_customers mc
    where mc.created_at < (v_next::timestamp at time zone 'Asia/Karachi')
      and (
        mc.is_active=true
        or exists(select 1 from public.unregistered_monthly_bills b
          where b.customer_id=mc.id and b.bill_month<v_month
            and (b.current_due>0 or b.closing_advance>0))
        or (not exists(select 1 from public.unregistered_monthly_bills prior
          where prior.customer_id=mc.id and prior.bill_month<v_month)
        and exists(select 1 from public.unassigned_19l_deliveries d
          where d.monthly_customer_id=mc.id and d.customer_classification='monthly'
            and d.delivery_date<v_month))
        or exists(select 1 from public.unassigned_19l_deliveries d
          where d.monthly_customer_id=mc.id and d.customer_classification='monthly'
            and d.delivery_date>=v_month and d.delivery_date<v_next)
        or exists(select 1 from public.unassigned_19l_delivery_collections rc
          join public.unassigned_19l_deliveries d on d.id=rc.delivery_id
          where d.monthly_customer_id=mc.id and d.customer_classification='monthly'
            and rc.received_date>=v_month and rc.received_date<v_next)
        or exists(select 1 from private.unregistered_monthly_customer_receipts r
          where r.customer_id=mc.id and r.received_date>=v_month and r.received_date<v_next)
      )
  loop
    v_previous_due:=0;
    v_previous_advance:=0;
    v_payments:=0;

    select b.current_due,b.closing_advance
      into v_previous_due,v_previous_advance
    from public.unregistered_monthly_bills b
    where b.customer_id=c.id and b.bill_month<v_month
    order by b.bill_month desc limit 1;

    if not found then
      select coalesce(sum(d.bottles_delivered::numeric*100+d.damaged_caps::numeric*10),0)
        into v_historical_charges
      from public.unassigned_19l_deliveries d
      where d.monthly_customer_id=c.id and d.customer_classification='monthly'
        and d.delivery_date<v_month;

      v_historical_payments:=private.unregistered_monthly_customer_paid_before(c.id,v_month);
      v_previous_due:=greatest(v_historical_charges-v_historical_payments,0);
      v_previous_advance:=greatest(v_historical_payments-v_historical_charges,0);
    end if;

    v_previous_due:=coalesce(v_previous_due,0);
    v_previous_advance:=coalesce(v_previous_advance,0);

    select coalesce(sum(d.bottles_delivered),0),coalesce(sum(d.damaged_caps),0)
      into v_bottles,v_caps
    from public.unassigned_19l_deliveries d
    where d.monthly_customer_id=c.id and d.customer_classification='monthly'
      and d.delivery_date>=v_month and d.delivery_date<v_next;

    v_payments:=private.unregistered_monthly_customer_paid_before(c.id,v_next)
      - private.unregistered_monthly_customer_paid_before(c.id,v_month);

    v_bottle_amount:=v_bottles*100;
    v_cap_amount:=v_caps*10;
    v_charges:=v_bottle_amount+v_cap_amount;
    v_advance_used:=least(v_previous_advance,v_previous_due+v_charges);
    v_due:=greatest(v_previous_due+v_charges-v_previous_advance-v_payments,0);
    v_closing_advance:=greatest(v_previous_advance+v_payments-v_previous_due-v_charges,0);

    insert into public.unregistered_monthly_bills(
      customer_id,bill_month,bottles_19l,bottle_amount,damaged_caps,cap_amount,
      previous_balance,payments,advance_used,current_due,closing_advance,generated_at
    ) values(
      c.id,v_month,v_bottles,v_bottle_amount,v_caps,v_cap_amount,
      v_previous_due,v_payments,v_advance_used,v_due,v_closing_advance,now()
    )
    on conflict(customer_id,bill_month) do update set
      bottles_19l=excluded.bottles_19l,
      bottle_amount=excluded.bottle_amount,
      damaged_caps=excluded.damaged_caps,
      cap_amount=excluded.cap_amount,
      previous_balance=excluded.previous_balance,
      payments=excluded.payments,
      advance_used=excluded.advance_used,
      current_due=excluded.current_due,
      closing_advance=excluded.closing_advance,
      generated_at=excluded.generated_at;

    v_count:=v_count+1;
  end loop;

  return v_count;
end
$function$


revoke all on function private.unregistered_monthly_customer_paid_before(bigint,date) from public,anon,authenticated;
revoke all on function private.record_unregistered_monthly_customer_collection(bigint,date,numeric,text,uuid) from public,anon;
grant usage on schema private to authenticated;
grant execute on function private.record_unregistered_monthly_customer_collection(bigint,date,numeric,text,uuid) to authenticated;
revoke all on function public.record_unregistered_monthly_customer_collection(bigint,date,numeric,text,uuid) from public,anon;
grant execute on function public.record_unregistered_monthly_customer_collection(bigint,date,numeric,text,uuid) to authenticated;
revoke all on function private.list_unregistered_monthly_customer_receipts(bigint) from public,anon;
grant execute on function private.list_unregistered_monthly_customer_receipts(bigint) to authenticated;
revoke all on function public.list_unregistered_monthly_customer_receipts(bigint) from public,anon;
grant execute on function public.list_unregistered_monthly_customer_receipts(bigint) to authenticated;