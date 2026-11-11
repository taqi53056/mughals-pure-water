ALTER TABLE public.production
  ADD CONSTRAINT production_quantity_integer_check
  CHECK (quantity = trunc(quantity));

ALTER TABLE public.production
  ADD CONSTRAINT production_product_type_check
  CHECK (product_type IN ('500ml', '1.5L', '6L'));

ALTER TABLE public.product_sales
  ADD CONSTRAINT product_sales_quantity_integer_check
  CHECK (quantity = trunc(quantity));

ALTER TABLE public.product_sales
  ADD CONSTRAINT product_sales_unit_matches_product
  CHECK (
    (product_type = '6L' AND unit = 'bottle')
    OR (product_type IN ('500ml', '1.5L') AND unit = 'carton')
  );

ALTER TABLE public.product_sales
  ADD CONSTRAINT product_sales_total_matches_quantity_price
  CHECK (total_amount = round(quantity * unit_price, 2));
