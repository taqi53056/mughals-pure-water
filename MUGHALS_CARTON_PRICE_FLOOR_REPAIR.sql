-- MUGHAL'S PURE WATER — READ-ONLY PRICE RULE VERIFICATION
-- Historical repair script superseded by:
--   20261126162500_remove_obsolete_six_litre_settings_price_floor.sql
--   20261126163000_remove_obsolete_six_litre_sale_price_floor.sql
--
-- DO NOT restore the historical Rs.55 6L floor. Current business rule:
--   500ml / 1.5L: at least Rs.280 per carton.
--   6L: admin enters the actual positive unit price on every sale; no fixed minimum.
-- This file intentionally performs SELECT statements only.

SELECT product_type,unit_type,units_per_pack,default_rate,special_100_rate,labor_per_unit,is_active
FROM public.product_settings
WHERE product_type IN ('500ml','1.5L','6L')
ORDER BY product_type;

SELECT conrelid::regclass AS table_name,conname,pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid IN ('public.product_sales'::regclass,'public.product_settings'::regclass,'public.sales'::regclass)
  AND pg_get_constraintdef(oid) ILIKE '%55%';

SELECT n.nspname,p.proname,pg_get_function_identity_arguments(p.oid) AS arguments,
       p.prosrc
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE p.pronamespace IN ('public'::regnamespace,'private'::regnamespace)
  AND p.proname IN (
    'enforce_product_sale_minimum_price',
    'enforce_product_settings_price_floor',
    'enforce_product_sale_price_floor',
    'record_product_sale',
    'validate_sale',
    'validate_special_sale'
  )
ORDER BY n.nspname,p.proname,arguments;

SELECT tgname,pg_get_triggerdef(oid) AS trigger_definition
FROM pg_trigger
WHERE tgrelid='public.product_sales'::regclass
  AND NOT tgisinternal
ORDER BY tgname;

SELECT tgname,pg_get_triggerdef(oid) AS legacy_trigger_definition
FROM pg_trigger
WHERE tgrelid='public.sales'::regclass
  AND NOT tgisinternal
ORDER BY tgname;
