create or replace function private.enforce_product_sale_minimum_price()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.product_type = '6L' and coalesce(new.unit_price, 0) < 55 then
    raise exception '6L کی فی بوتل قیمت کم از کم 55 روپے ہونی چاہیے۔'
      using errcode = '23514';
  end if;
  if new.product_type in ('500ml','1.5L') and coalesce(new.unit_price, 0) < 280 then
    raise exception '500ml اور 1.5L کی فی کارٹن قیمت کم از کم 280 روپے ہونی چاہیے۔'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_product_sale_minimum_price on public.product_sales;
create trigger enforce_product_sale_minimum_price
before insert or update of product_type, unit_price
on public.product_sales
for each row
execute function private.enforce_product_sale_minimum_price();

update public.product_settings
set default_rate = 55
where product_type = '6L' and default_rate < 55;