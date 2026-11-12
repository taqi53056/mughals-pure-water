alter table public.raw_material_purchases
  drop constraint raw_material_purchases_quantity_check;

alter table public.raw_material_purchases
  add constraint raw_material_purchases_quantity_check
  check (
    quantity > 0
    or (
      quantity = 0
      and total_amount = 0
      and record_type = 'purchase'
      and details like 'اصلاحی اندراج:%'
    )
  );
