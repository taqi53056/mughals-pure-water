ALTER TABLE public.water_tanker_purchases
  ADD CONSTRAINT water_tanker_count_integer_check
  CHECK (tanker_count = trunc(tanker_count));
