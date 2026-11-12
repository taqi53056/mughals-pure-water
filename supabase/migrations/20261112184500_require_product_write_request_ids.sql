-- Require a non-null idempotency key for every product sale and return.
-- Keep the exposed wrappers SECURITY INVOKER; the private implementations
-- perform the admin authorization and privileged writes.
create or replace function public.record_product_sale(
  p_sale_date date,p_product_type text,p_quantity integer,p_worker_id bigint,
  p_unit_price numeric,p_payment_method text,p_request_id uuid
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  if p_request_id is null then
    raise exception 'ہر سیل کے لیے منفرد درخواست شناخت لازمی ہے۔' using errcode='22023';
  end if;
  return private.record_product_sale(
    p_sale_date,p_product_type,p_quantity,p_worker_id,p_unit_price,p_payment_method,p_request_id
  );
end;
$function$;

create or replace function public.record_product_return(
  p_return_date date,p_product_type text,p_quantity integer,p_reason text,p_request_id uuid
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  if p_request_id is null then
    raise exception 'ہر واپسی کے لیے منفرد درخواست شناخت لازمی ہے۔' using errcode='22023';
  end if;
  return private.record_product_return(
    p_return_date,p_product_type,p_quantity,p_reason,p_request_id
  );
end;
$function$;

revoke all on function public.record_product_sale(date,text,integer,bigint,numeric,text,uuid) from public, anon;
revoke all on function public.record_product_return(date,text,integer,text,uuid) from public, anon;
grant execute on function public.record_product_sale(date,text,integer,bigint,numeric,text,uuid) to authenticated;
grant execute on function public.record_product_return(date,text,integer,text,uuid) to authenticated;
