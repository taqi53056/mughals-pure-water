ALTER TABLE public.raw_material_purchases
  DROP CONSTRAINT raw_material_purchases_quantity_check;

ALTER TABLE public.raw_material_purchases
  ADD CONSTRAINT raw_material_purchases_quantity_check
  CHECK (
    quantity > 0
    OR (
      quantity = 0
      AND total_amount = 0
      AND (
        (record_type = 'purchase' AND details LIKE 'اصلاحی اندراج:%')
        OR
        (record_type = 'opening_stock' AND details LIKE 'اصلاحی اندراج:%')
      )
    )
  );
