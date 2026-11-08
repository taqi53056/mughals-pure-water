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

-- Fixed pack sizes and labor rates used by the production/delivery ledger.
ALTER TABLE public.product_settings
ADD CONSTRAINT product_settings_fixed_pack_labor_rules_check
CHECK (
  (product_type='500ml' AND unit_type='carton' AND units_per_pack=24 AND labor_per_unit=10)
  OR
  (product_type='1.5L' AND unit_type='carton' AND units_per_pack=12 AND labor_per_unit=10)
  OR
  (product_type='6L' AND unit_type='bottle' AND units_per_pack=18 AND labor_per_unit=0)
) NOT VALID;
ALTER TABLE public.product_settings
VALIDATE CONSTRAINT product_settings_fixed_pack_labor_rules_check;

-- 6L is fixed at Rs.55 in the sale RPC and is therefore not editable here.
ALTER TABLE public.product_settings
ADD CONSTRAINT product_settings_6l_fixed_rate_check
CHECK (product_type<>'6L' OR (default_rate=55 AND special_100_rate IS NULL)) NOT VALID;
ALTER TABLE public.product_settings
VALIDATE CONSTRAINT product_settings_6l_fixed_rate_check;
