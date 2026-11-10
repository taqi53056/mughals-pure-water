-- A finished-goods opening/manual stock row is unique per date and product.
-- Re-entering the same date/product updates the existing quantity instead of adding
-- a second row. Daily production and physical corrections use their own ledgers.
CREATE UNIQUE INDEX IF NOT EXISTS finished_goods_one_entry_per_product_date_uidx
ON public.finished_goods (entry_date, product_type);
