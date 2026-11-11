ALTER TABLE public.raw_material_stock
  ADD CONSTRAINT raw_material_stock_cartons_integer_check
  CHECK (cartons = trunc(cartons));

ALTER TABLE public.finished_stock_adjustments
  ADD CONSTRAINT finished_stock_adjustments_quantity_integer_check
  CHECK (quantity = trunc(quantity) AND quantity > 0);

ALTER TABLE public.finished_stock_adjustments
  ADD CONSTRAINT finished_stock_adjustments_product_type_check
  CHECK (product_type IN ('500ml', '1.5L', '6L'));

ALTER TABLE public.finished_stock_adjustments
  ADD CONSTRAINT finished_stock_adjustments_adjustment_type_check
  CHECK (adjustment_type IN ('increase', 'decrease'));
