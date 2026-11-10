DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.customer_19l_deliveries
    GROUP BY customer_id, delivery_date
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'Cannot enforce one 19L delivery per customer/date: duplicate rows already exist.';
  END IF;
END
$$;

CREATE UNIQUE INDEX IF NOT EXISTS customer_19l_deliveries_customer_date_uidx
  ON public.customer_19l_deliveries (customer_id, delivery_date);
