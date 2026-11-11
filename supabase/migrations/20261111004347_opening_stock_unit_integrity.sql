ALTER TABLE public.raw_material_purchases
  ADD CONSTRAINT raw_material_purchases_quantity_integer_check
  CHECK (quantity = trunc(quantity));

ALTER TABLE public.finished_goods
  ADD CONSTRAINT finished_goods_quantity_integer_check
  CHECK (quantity = trunc(quantity));

ALTER TABLE public.finished_goods
  ADD CONSTRAINT finished_goods_unit_matches_product
  CHECK (
    (product_type = '6L' AND unit = 'bottle')
    OR (product_type IN ('500ml', '1.5L') AND unit = 'carton')
  );
