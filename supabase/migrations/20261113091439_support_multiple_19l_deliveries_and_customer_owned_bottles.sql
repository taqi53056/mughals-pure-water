
-- Customer-owned containers remain billable but are excluded from company custody.
ALTER TABLE public.customer_19l_deliveries
  ADD COLUMN IF NOT EXISTS customer_owned_bottles integer NOT NULL DEFAULT 0;

ALTER TABLE public.customer_19l_deliveries
  ADD COLUMN IF NOT EXISTS company_bottles_delivered integer
  GENERATED ALWAYS AS (bottles_delivered - customer_owned_bottles) STORED;

DO $migration$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.customer_19l_deliveries'::regclass
      AND conname='customer_19l_deliveries_customer_owned_bottles_check'
  ) THEN
    ALTER TABLE public.customer_19l_deliveries
      ADD CONSTRAINT customer_19l_deliveries_customer_owned_bottles_check
      CHECK (customer_owned_bottles >= 0 AND customer_owned_bottles <= bottles_delivered);
  END IF;
END;
$migration$;
