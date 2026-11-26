create or replace function private.enforce_product_settings_price_floor()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.product_type='6L' then
    if coalesce(new.default_rate,0)<55 then
      raise exception '6L کی مقررہ کم از کم فی بوتل قیمت 55 روپے ہے۔' using errcode='23514';
    end if;
  elsif new.product_type in ('500ml','1.5L') then
    if coalesce(new.default_rate,0)<280 then
      raise exception '500ml اور 1.5L کی مقررہ کم از کم فی کارٹن قیمت 280 روپے ہے۔' using errcode='23514';
    end if;
    if new.special_100_rate is not null and
       (new.special_100_rate<280 or new.special_100_rate>new.default_rate) then
      raise exception 'خصوصی کارٹن قیمت 280 روپے سے کم یا طے شدہ قیمت سے زیادہ نہیں ہوسکتی۔' using errcode='23514';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_product_settings_price_floor on public.product_settings;
create trigger enforce_product_settings_price_floor
before insert or update of product_type,default_rate,special_100_rate
on public.product_settings
for each row
execute function private.enforce_product_settings_price_floor();

comment on function private.enforce_product_settings_price_floor() is
'Enforces the configured minimum product sale prices at the database boundary.';