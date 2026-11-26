create or replace function private.enforce_product_sale_minimum_price()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.product_type='6L' then
    if new.unit is distinct from 'bottle' or new.unit_price is null or new.unit_price<=0 then
      raise exception '6L کی فی بوتل اصل قیمت ایڈمن درج کرے؛ قیمت صفر سے زیادہ ہونی چاہیے۔'
        using errcode='23514';
    end if;
  elsif new.product_type in ('500ml','1.5L') then
    if new.unit is distinct from 'carton' or new.unit_price is null or new.unit_price<280 then
      raise exception '500ml اور 1.5L کی فی کارٹن قیمت کم از کم 280 روپے ہونی چاہیے۔'
        using errcode='23514';
    end if;
  else
    raise exception 'پروڈکٹ کی قسم درست نہیں۔' using errcode='22023';
  end if;
  return new;
end;
$$;

create or replace function public.record_product_sale(
  p_sale_date date,p_product_type text,p_quantity integer,p_worker_id bigint
)
returns jsonb
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'ہر سیل کے لیے ایڈمن اصل فی یونٹ قیمت واضح طور پر درج کرے۔'
    using errcode='22023';
end;
$$;