create or replace function private.link_pending_unassigned_19l_delivery_to_monthly_customer(p_delivery_id bigint, p_customer_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_delivery public.unassigned_19l_deliveries%rowtype;
  v_customer public.unregistered_monthly_customers%rowtype;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'صرف مجاز ایڈمن یہ کارروائی کر سکتا ہے۔'
      using errcode = '42501';
  end if;

  select * into v_delivery
  from public.unassigned_19l_deliveries
  where id = p_delivery_id
  for update;

  if not found then
    raise exception 'سپلائی ریکارڈ موجود نہیں۔' using errcode = 'P0002';
  end if;

  if v_delivery.customer_classification = 'monthly'
     and v_delivery.monthly_customer_id = p_customer_id then
    return jsonb_build_object(
      'status', 'already_linked',
      'delivery_id', v_delivery.id,
      'monthly_customer_id', p_customer_id,
      'delivery_date', v_delivery.delivery_date,
      'bottles_delivered', v_delivery.bottles_delivered,
      'empty_bottles_returned', v_delivery.empty_bottles_returned,
      'performed_by_owner', v_delivery.performed_by_owner
    );
  end if;

  if v_delivery.customer_classification <> 'monthly_pending_review'
     or v_delivery.monthly_customer_id is not null then
    raise exception 'صرف زیرِ جائزہ غیر منسلک سپلائی کو ماہانہ کھاتے سے منسلک کیا جا سکتا ہے۔'
      using errcode = '55000';
  end if;

  select * into v_customer
  from public.unregistered_monthly_customers
  where id = p_customer_id
  for share;

  if not found or not v_customer.is_active then
    raise exception 'ماہانہ گاہک کا اکاؤنٹ موجود یا فعال نہیں۔'
      using errcode = '23503';
  end if;

  if v_delivery.delivery_date < v_customer.start_date then
    raise exception 'سپلائی کی تاریخ ماہانہ اکاؤنٹ کی آغاز کی تاریخ سے پہلے ہے۔'
      using errcode = '22023';
  end if;

  update public.unassigned_19l_deliveries
     set customer_classification = 'monthly',
         monthly_customer_id = p_customer_id
   where id = p_delivery_id;

  return jsonb_build_object(
    'status', 'linked',
    'delivery_id', v_delivery.id,
    'monthly_customer_id', p_customer_id,
    'delivery_date', v_delivery.delivery_date,
    'bottles_delivered', v_delivery.bottles_delivered,
    'empty_bottles_returned', v_delivery.empty_bottles_returned,
    'performed_by_owner', v_delivery.performed_by_owner
  );
end;
$function$;

revoke all on function private.link_pending_unassigned_19l_delivery_to_monthly_customer(bigint,bigint) from public, anon;
grant usage on schema private to authenticated;
grant execute on function private.link_pending_unassigned_19l_delivery_to_monthly_customer(bigint,bigint) to authenticated;

create or replace function public.link_pending_unassigned_19l_delivery_to_monthly_customer(p_delivery_id bigint, p_customer_id bigint)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
  select private.link_pending_unassigned_19l_delivery_to_monthly_customer($1,$2);
$function$;

revoke all on function public.link_pending_unassigned_19l_delivery_to_monthly_customer(bigint,bigint) from public, anon;
grant execute on function public.link_pending_unassigned_19l_delivery_to_monthly_customer(bigint,bigint) to authenticated;
