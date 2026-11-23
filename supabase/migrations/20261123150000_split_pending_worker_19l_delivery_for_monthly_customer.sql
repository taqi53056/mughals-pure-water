create or replace function private.split_pending_unassigned_19l_delivery_to_monthly_customer(
  p_delivery_id bigint,
  p_customer_id bigint,
  p_monthly_bottles integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_parent public.unassigned_19l_deliveries%rowtype;
  v_customer public.unregistered_monthly_customers%rowtype;
  v_split_request_id uuid;
  v_split_id bigint;
  v_split_details text;
  v_existing public.unassigned_19l_deliveries%rowtype;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'صرف مجاز ایڈمن یہ کارروائی کر سکتا ہے۔'
      using errcode = '42501';
  end if;

  if p_monthly_bottles is null or p_monthly_bottles <= 0 then
    raise exception 'ماہانہ کھاتے کے لیے بوتلوں کی تعداد ایک یا زیادہ ہونی چاہیے۔'
      using errcode = '22023';
  end if;

  select *
    into v_parent
    from public.unassigned_19l_deliveries
   where id = p_delivery_id
   for update;

  if not found then
    raise exception 'اصل سپلائی ریکارڈ موجود نہیں۔' using errcode = 'P0002';
  end if;

  v_split_request_id := md5(
    'mpw-unassigned-monthly-split:' || v_parent.request_id::text || ':' ||
    p_customer_id::text || ':' || p_monthly_bottles::text
  )::uuid;
  v_split_details := 'تقسیم شدہ سپلائی — اصل ریکارڈ #' || v_parent.id::text || ' — ماہانہ حصہ';

  -- Safe retry: never create a second child row for the same split.
  select *
    into v_existing
    from public.unassigned_19l_deliveries
   where request_id = v_split_request_id
   for update;

  if found then
    if v_existing.customer_classification = 'monthly'
       and v_existing.monthly_customer_id = p_customer_id
       and v_existing.bottles_delivered = p_monthly_bottles
       and v_existing.empty_bottles_returned = p_monthly_bottles
       and v_existing.damaged_caps = 0
       and v_existing.worker_id = v_parent.worker_id
       and v_existing.delivery_date = v_parent.delivery_date
       and v_parent.bottles_delivered > 0
       and v_parent.empty_bottles_returned = v_parent.bottles_delivered
       and v_parent.labor_amount = v_parent.bottles_delivered::numeric * 20
       and v_parent.details like '%تقسیم شدہ اصل سپلائی%'
       and v_parent.customer_classification = 'monthly_pending_review'
       and v_parent.monthly_customer_id is null then
      return jsonb_build_object(
        'status', 'already_split',
        'original_delivery_id', v_parent.id,
        'monthly_delivery_id', v_existing.id,
        'monthly_customer_id', p_customer_id,
        'monthly_bottles', v_existing.bottles_delivered,
        'remaining_bottles', v_parent.bottles_delivered,
        'remaining_damaged_caps', v_parent.damaged_caps,
        'worker_id', v_parent.worker_id,
        'total_labor_amount', v_parent.labor_amount + v_existing.labor_amount
      );
    end if;
    raise exception 'اس سپلائی کی تقسیم پہلے مختلف حالت میں ہو چکی ہے؛ پہلے ریکارڈ کی جانچ ضروری ہے۔'
      using errcode = '55000';
  end if;

  if v_parent.customer_classification <> 'monthly_pending_review'
     or v_parent.monthly_customer_id is not null then
    raise exception 'صرف زیرِ جائزہ غیر منسلک سپلائی تقسیم کی جا سکتی ہے۔'
      using errcode = '55000';
  end if;

  if v_parent.performed_by_owner or v_parent.worker_id is null then
    raise exception 'یہ تقسیم صرف مزدور کے ذریعے پہنچائی گئی سپلائی کے لیے دستیاب ہے۔'
      using errcode = '22023';
  end if;

  if p_monthly_bottles >= v_parent.bottles_delivered then
    raise exception 'ماہانہ حصہ اصل سپلائی سے کم ہونا چاہیے تاکہ باقی حصہ الگ رہے۔'
      using errcode = '22023';
  end if;

  if v_parent.empty_bottles_returned <> v_parent.bottles_delivered then
    raise exception 'اس وقت صرف برابر تعداد میں خالی بوتلیں واپس آنے والی سپلائی تقسیم کی جا سکتی ہے۔'
      using errcode = '22023';
  end if;

  if v_parent.labor_rate <> 20
     or v_parent.labor_amount is distinct from v_parent.bottles_delivered::numeric * 20 then
    raise exception 'اصل مزدوری کا حساب مقررہ شرح سے مطابقت نہیں رکھتا؛ تقسیم روک دی گئی۔'
      using errcode = '23514';
  end if;

  if exists (
    select 1
      from public.unassigned_19l_delivery_collections c
     where c.delivery_id = v_parent.id
  ) then
    raise exception 'اس سپلائی پر وصولی درج ہے؛ وصولی کی محفوظ تقسیم کے بغیر کارروائی نہیں ہو سکتی۔'
      using errcode = '55000';
  end if;

  select *
    into v_customer
    from public.unregistered_monthly_customers
   where id = p_customer_id
   for share;

  if not found or not v_customer.is_active then
    raise exception 'ماہانہ گاہک کا اکاؤنٹ موجود یا فعال نہیں۔'
      using errcode = '23503';
  end if;

  if v_parent.delivery_date < v_customer.start_date then
    raise exception 'سپلائی کی تاریخ ماہانہ اکاؤنٹ کے آغاز سے پہلے ہے۔'
      using errcode = '22023';
  end if;

  -- Keep the original row as the unassigned remainder. Its damaged caps
  -- remain on this remainder, as specified by the administrator.
  update public.unassigned_19l_deliveries
     set bottles_delivered = v_parent.bottles_delivered - p_monthly_bottles,
         empty_bottles_returned = v_parent.empty_bottles_returned - p_monthly_bottles,
         labor_amount = (v_parent.bottles_delivered - p_monthly_bottles) * v_parent.labor_rate,
         details = concat_ws(E'\\n', nullif(btrim(v_parent.details), ''),
           'تقسیم شدہ اصل سپلائی — ماہانہ حصہ #' || p_monthly_bottles::text)
   where id = v_parent.id;

  -- Create only the accounting split row. This is not a second physical delivery:
  -- aggregate bottles/empties remain unchanged and the existing worker-ledger
  -- synchronization recalculates wages across the two source rows.
  perform private.record_unassigned_19l_delivery(
    v_parent.delivery_date,
    v_parent.worker_id,
    p_monthly_bottles,
    p_monthly_bottles,
    v_split_details,
    v_split_request_id,
    0,
    false
  );

  select id
    into v_split_id
    from public.unassigned_19l_deliveries
   where request_id = v_split_request_id;

  update public.unassigned_19l_deliveries
     set customer_classification = 'monthly_pending_review'
   where id = v_split_id;

  perform public.link_pending_unassigned_19l_delivery_to_monthly_customer(
    v_split_id,
    p_customer_id
  );

  select *
    into v_parent
    from public.unassigned_19l_deliveries
   where id = p_delivery_id;

  select *
    into v_existing
    from public.unassigned_19l_deliveries
   where id = v_split_id;

  return jsonb_build_object(
    'status', 'split',
    'original_delivery_id', v_parent.id,
    'monthly_delivery_id', v_existing.id,
    'monthly_customer_id', p_customer_id,
    'monthly_bottles', v_existing.bottles_delivered,
    'remaining_bottles', v_parent.bottles_delivered,
    'remaining_damaged_caps', v_parent.damaged_caps,
    'worker_id', v_parent.worker_id,
    'total_labor_amount', v_parent.labor_amount + v_existing.labor_amount
  );
end;
$function$;

revoke all on function private.split_pending_unassigned_19l_delivery_to_monthly_customer(bigint,bigint,integer) from public, anon;
grant execute on function private.split_pending_unassigned_19l_delivery_to_monthly_customer(bigint,bigint,integer) to authenticated;

create or replace function public.split_pending_unassigned_19l_delivery_to_monthly_customer(
  p_delivery_id bigint,
  p_customer_id bigint,
  p_monthly_bottles integer
)
returns jsonb
language sql
security invoker
set search_path = ''
as $wrapper$
  select private.split_pending_unassigned_19l_delivery_to_monthly_customer(
    p_delivery_id, p_customer_id, p_monthly_bottles
  );
$wrapper$;

revoke all on function public.split_pending_unassigned_19l_delivery_to_monthly_customer(bigint,bigint,integer) from public, anon;
grant execute on function public.split_pending_unassigned_19l_delivery_to_monthly_customer(bigint,bigint,integer) to authenticated;