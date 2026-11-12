create or replace function public.record_unassigned_19l_collection(
  p_delivery_id bigint,
  p_received_date date,
  p_amount numeric,
  p_payment_method text,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_delivery public.unassigned_19l_deliveries%rowtype;
  v_existing public.unassigned_19l_delivery_collections%rowtype;
  v_due numeric;
  v_collected numeric;
  v_income_id bigint;
  v_id bigint;
  v_today date := (now() at time zone 'Asia/Karachi')::date;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'صرف مجاز ایڈمن وصولی درج کر سکتا ہے۔' using errcode='42501';
  end if;

  if p_request_id is null or p_delivery_id is null or p_received_date is null
     or p_received_date > v_today or p_amount is null or p_amount <= 0
     or p_payment_method is null
     or p_payment_method not in ('cash','bank','easypaisa','jazzcash') then
    raise exception 'وصولی کی تاریخ، رقم، طریقہ اور شناخت درست درج کریں۔' using errcode='22023';
  end if;

  select * into v_existing
  from public.unassigned_19l_delivery_collections
  where request_id=p_request_id;

  if found then
    if v_existing.delivery_id<>p_delivery_id
       or v_existing.received_date<>p_received_date
       or v_existing.amount<>p_amount
       or v_existing.payment_method<>p_payment_method then
      raise exception 'یہ درخواست پہلے مختلف تفصیل کے ساتھ محفوظ ہے۔' using errcode='23505';
    end if;
    return jsonb_build_object('id',v_existing.id,'business_income_id',v_existing.business_income_id,'already_saved',true);
  end if;

  -- Match month-close lock ordering: acquire the month lock before locking the delivery row.
  perform pg_advisory_xact_lock(
    hashtextextended('mpw-month-close-'||date_trunc('month',p_received_date)::date::text,0)
  );

  select * into v_delivery
  from public.unassigned_19l_deliveries
  where id=p_delivery_id
  for update;

  if not found then
    raise exception 'متعلقہ سپلائی ریکارڈ نہیں ملا۔' using errcode='P0002';
  end if;

  if p_received_date < v_delivery.delivery_date then
    raise exception 'وصولی کی تاریخ سپلائی کی تاریخ سے پہلے نہیں ہو سکتی۔' using errcode='22023';
  end if;

  if exists(
    select 1 from public.business_month_closings c
    where c.month_start=date_trunc('month',p_received_date)::date and c.status='closed'
  ) then
    raise exception 'یہ مہینہ بند ہو چکا ہے؛ وصولی درج نہیں ہو سکتی۔' using errcode='55000';
  end if;

  v_due:=v_delivery.empty_bottles_returned::numeric*100+v_delivery.damaged_caps::numeric*10;
  select coalesce(sum(amount),0) into v_collected
  from public.unassigned_19l_delivery_collections where delivery_id=p_delivery_id;

  if v_collected+p_amount>v_due then
    raise exception 'وصولی بقایا رقم سے زیادہ نہیں ہو سکتی۔ بقایا: %',
      greatest(v_due-v_collected,0) using errcode='23514';
  end if;

  insert into public.business_income(income_date,category,amount,details,request_id)
  values(p_received_date,'غیر منسلک 19L سپلائی کی وصولی',p_amount,
    'غیر منسلک سپلائی ID: '||p_delivery_id||'؛ طریقہ: '||p_payment_method,p_request_id)
  returning id into v_income_id;

  insert into public.unassigned_19l_delivery_collections(
    delivery_id,received_date,amount,payment_method,business_income_id,request_id,entered_by
  )
  values(p_delivery_id,p_received_date,p_amount,p_payment_method,v_income_id,p_request_id,auth.uid())
  returning id into v_id;

  return jsonb_build_object('id',v_id,'business_income_id',v_income_id,'delivery_id',p_delivery_id,
    'amount',p_amount,'remaining_due',v_due-v_collected-p_amount,'already_saved',false);
end;
$function$;

revoke all on function public.record_unassigned_19l_collection(bigint,date,numeric,text,uuid) from public, anon;
grant execute on function public.record_unassigned_19l_collection(bigint,date,numeric,text,uuid) to authenticated;
