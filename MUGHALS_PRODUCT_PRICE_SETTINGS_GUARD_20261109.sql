-- MUGHAL'S PURE WATER
-- Database guard for bulk carton pricing.
-- Applied and verified on live Supabase on 2026-11-09.
-- A 100+ carton special rate may be lower than the standard rate,
-- but it may never exceed the standard rate or fall below Rs.280.

ALTER TABLE public.product_settings
ADD CONSTRAINT product_settings_special_not_above_default_check
CHECK (special_100_rate IS NULL OR special_100_rate <= default_rate) NOT VALID;

ALTER TABLE public.product_settings
VALIDATE CONSTRAINT product_settings_special_not_above_default_check;

-- Verification: should return true.
SELECT EXISTS (
  SELECT 1 FROM pg_constraint
  WHERE conrelid = 'public.product_settings'::regclass
    AND conname = 'product_settings_special_not_above_default_check'
    AND convalidated
) AS bulk_special_price_guard_validated;
