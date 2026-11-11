ALTER TABLE public.customers
  ALTER COLUMN mobile SET NOT NULL;

ALTER TABLE public.customers
  ADD CONSTRAINT customers_mobile_format_check
  CHECK (mobile ~ '^03[0-9]{9}$');

ALTER TABLE public.customers
  ADD CONSTRAINT customers_mobile_key
  UNIQUE (mobile);
