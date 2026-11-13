
-- A customer may receive more than one separate delivery on the same date.
DROP INDEX IF EXISTS public.customer_19l_deliveries_customer_date_uidx;
CREATE INDEX IF NOT EXISTS customer_19l_deliveries_customer_date_idx
  ON public.customer_19l_deliveries (customer_id, delivery_date DESC, id DESC);
