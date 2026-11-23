create or replace function private.list_unregistered_monthly_customer_receipts(p_customer_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'صرف مجاز ایڈمن ماہانہ گاہک کی وصولیاں دیکھ سکتا ہے۔' using errcode='42501';
  end if;
  if p_customer_id is null or p_customer_id <= 0 then
    raise exception 'ماہانہ گاہک منتخب کرنا ضروری ہے۔' using errcode='22023';
  end if;
  if not exists(select 1 from public.unregistered_monthly_customers c where c.id=p_customer_id) then
    raise exception 'منتخب ماہانہ گاہک کا کھاتہ موجود نہیں۔' using errcode='P0002';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',r.id,
      'received_date',r.received_date,
      'amount',r.amount,
      'payment_method',r.payment_method
    ) order by r.received_date desc,r.id desc)
    from private.unregistered_monthly_customer_receipts r
    where r.customer_id=p_customer_id
  ),'[]'::jsonb);
end;
$function$;

revoke all on function private.list_unregistered_monthly_customer_receipts(bigint) from public,anon;
grant usage on schema private to authenticated;
grant execute on function private.list_unregistered_monthly_customer_receipts(bigint) to authenticated;

create or replace function public.list_unregistered_monthly_customer_receipts(p_customer_id bigint)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
  select private.list_unregistered_monthly_customer_receipts($1);
$function$;

revoke all on function public.list_unregistered_monthly_customer_receipts(bigint) from public,anon;
grant execute on function public.list_unregistered_monthly_customer_receipts(bigint) to authenticated;
