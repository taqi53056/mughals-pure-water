-- MUGHAL'S PURE WATER: CARTON PRICE FLOOR + FLEXIBLE PER-SALE PRICE
-- Run once in Supabase SQL Editor as postgres. Transactional; no business data is deleted.
BEGIN;
SET LOCAL lock_timeout='8s';
SET LOCAL statement_timeout='180s';

DO $preflight$
BEGIN
  IF to_regclass('public.product_sales') IS NULL OR to_regclass('public.sales') IS NULL THEN
    RAISE EXCEPTION 'Expected product_sales and sales tables are required; no changes applied.';
  END IF;
  IF to_regprocedure('public.record_product_sale(date,text,integer,bigint)') IS NULL THEN
    RAISE EXCEPTION 'Expected current record_product_sale(date,text,integer,bigint) function missing.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='product_sales' AND column_name='unit_price')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='product_sales' AND column_name='total_amount') THEN
    RAISE EXCEPTION 'Expected product_sales pricing columns missing.';
  END IF;
END;
$preflight$;

-- Backend-authoritative price enforcement for direct table writes too.
CREATE OR REPLACE FUNCTION public.enforce_product_sale_price_floor()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path TO '' AS $fn$
BEGIN
  IF NEW.product_type IN ('500ml','1.5L') THEN
    IF NEW.unit <> 'carton' OR NEW.unit_price IS NULL OR NEW.unit_price < 280 THEN
      RAISE EXCEPTION '500ml/1.5L carton price cannot be below Rs.280.' USING ERRCODE='23514';
    END IF;
  ELSIF NEW.product_type='6L' THEN
    IF NEW.unit <> 'bottle' OR NEW.unit_price IS NULL OR NEW.unit_price < 55 THEN
      RAISE EXCEPTION '6L bottle price cannot be below Rs.55.' USING ERRCODE='23514';
    END IF;
  ELSE
    RAISE EXCEPTION 'Invalid product type.' USING ERRCODE='22023';
  END IF;
  NEW.total_amount := NEW.quantity * NEW.unit_price;
  RETURN NEW;
END;
$fn$;
DROP TRIGGER IF EXISTS enforce_product_sale_price_floor ON public.product_sales;
CREATE TRIGGER enforce_product_sale_price_floor
BEFORE INSERT OR UPDATE OF product_type, unit, quantity, unit_price, total_amount
ON public.product_sales FOR EACH ROW
EXECUTE FUNCTION public.enforce_product_sale_price_floor();

DO $constraints$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.product_sales'::regclass AND conname='product_sales_price_floor_check') THEN
    ALTER TABLE public.product_sales ADD CONSTRAINT product_sales_price_floor_check
      CHECK ((product_type IN ('500ml','1.5L') AND unit='carton' AND unit_price>=280)
          OR (product_type='6L' AND unit='bottle' AND unit_price>=55)) NOT VALID;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.sales'::regclass AND conname='sales_price_floor_check') THEN
    ALTER TABLE public.sales ADD CONSTRAINT sales_price_floor_check
      CHECK ((product_type IN ('500ml','1.5L') AND sale_rate>=280)
          OR (product_type='6L' AND sale_rate>=55)) NOT VALID;
  END IF;
END;
$constraints$;

-- Replace the two legacy validators: 270/100-carton exception is removed.
CREATE OR REPLACE FUNCTION public.validate_sale()
RETURNS trigger LANGUAGE plpgsql SET search_path TO '' AS $fn$
BEGIN
  IF NEW.product_type IN ('500ml','1.5L') THEN
    IF NEW.sale_rate IS NULL OR NEW.sale_rate < 280 THEN
      RAISE EXCEPTION '500ml/1.5L carton rate cannot be below Rs.280.' USING ERRCODE='23514';
    END IF;
    NEW.price_type := 'normal';
  ELSIF NEW.product_type='6L' THEN
    IF NEW.sale_rate IS NULL OR NEW.sale_rate < 55 THEN
      RAISE EXCEPTION '6L bottle rate cannot be below Rs.55.' USING ERRCODE='23514';
    END IF;
    NEW.price_type := 'normal';
  END IF;
  RETURN NEW;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.validate_special_sale()
RETURNS trigger LANGUAGE plpgsql SET search_path TO '' AS $fn$
BEGIN
  IF NEW.product_type IN ('500ml','1.5L') AND (NEW.sale_rate IS NULL OR NEW.sale_rate < 280) THEN
    RAISE EXCEPTION '500ml/1.5L carton rate cannot be below Rs.280; special pricing is disabled.' USING ERRCODE='23514';
  ELSIF NEW.product_type='6L' AND (NEW.sale_rate IS NULL OR NEW.sale_rate < 55) THEN
    RAISE EXCEPTION '6L bottle rate cannot be below Rs.55.' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$fn$;

-- New RPC accepts the admin-entered unit price. 6L remains Rs.55.
CREATE OR REPLACE FUNCTION public.record_product_sale(p_sale_date date, p_product_type text, p_quantity integer, p_worker_id bigint, p_unit_price numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
  v_unit text; v_price numeric; v_available numeric; v_sale_id text; v_total numeric;
  v_is_owner boolean := false;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN RAISE EXCEPTION 'ØµØ±Ù Ø§ÛÚÙÙ Ø³ÛÙ Ø¯Ø±Ø¬ Ú©Ø± Ø³Ú©ØªØ§ ÛÛÛ' USING ERRCODE='42501'; END IF;
  IF p_sale_date IS NULL OR p_quantity IS NULL OR p_quantity<=0 THEN RAISE EXCEPTION 'ØªØ§Ø±ÛØ® Ø§ÙØ± ÙØ«Ø¨Øª ÙÚ©ÙÙ ÙÙØ¯Ø§Ø± Ø¶Ø±ÙØ±Û ÛÛÛ' USING ERRCODE='22023'; END IF;
  IF p_product_type NOT IN ('500ml','1.5L','6L') THEN RAISE EXCEPTION 'Ù¾Ø±ÙÚÚ©Ù¹ Ú©Û ÙØ³Ù Ø¯Ø±Ø³Øª ÙÛÛÚºÛ' USING ERRCODE='22023'; END IF;
  IF p_product_type='6L' AND p_worker_id IS NOT NULL THEN RAISE EXCEPTION '6L Ø³ÛÙ Ú©Û ÙÛÛ Ú©Ø§Ø±Ù¹Ù ÙØ²Ø¯ÙØ± ÙÙØªØ®Ø¨ ÙÛ Ú©Ø±ÛÚºÛ'; END IF;
  IF p_worker_id IS NOT NULL THEN
    SELECT w.is_owner INTO v_is_owner FROM public.workers w
    WHERE w.id=p_worker_id AND w.is_active=true
      AND (w.is_owner=true OR w.work_categories @> ARRAY['carton loading/unloading']::text[]);
    IF NOT FOUND THEN RAISE EXCEPTION 'ÙÙØªØ®Ø¨ ÙØ±Ú©Ø± ÙØ¹Ø§Ù ÙÛÛÚº ÛØ§ Ú©Ø§Ø±Ù¹Ù Ú©Û Ú©Ø§Ù Ú©Û ÙÛÛ ÙÙØ±Ø± ÙÛÛÚºÛ'; END IF;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('finished-stock:'||p_product_type,0));
  v_unit:=CASE WHEN p_product_type='6L' THEN 'bottle' ELSE 'carton' END;
  IF p_product_type='6L' THEN
    v_price:=55;
  ELSE
    IF p_unit_price IS NULL OR p_unit_price < 280 THEN
      RAISE EXCEPTION '500ml/1.5L carton price cannot be below Rs.280' USING ERRCODE='23514';
    END IF;
    v_price:=p_unit_price;
  END IF;
  v_total:=p_quantity*v_price;
  SELECT COALESCE((SELECT SUM(quantity) FROM public.finished_goods WHERE product_type=p_product_type AND unit=v_unit),0)
    + COALESCE((SELECT SUM(quantity) FROM public.stock_ledger WHERE product_type=p_product_type AND movement_type IN ('production','production_reversal')),0)
    - COALESCE((SELECT SUM(quantity) FROM public.product_sales WHERE product_type=p_product_type AND unit=v_unit),0)
    + COALESCE((SELECT SUM(CASE WHEN adjustment_type='increase' THEN quantity WHEN adjustment_type='decrease' THEN -quantity ELSE 0 END)
      FROM public.finished_stock_adjustments WHERE product_type=p_product_type),0) INTO v_available;
  IF p_quantity>v_available THEN RAISE EXCEPTION 'ØªÛØ§Ø± ÙØ§Ù Ú©Ø§ Ø§Ø³Ù¹Ø§Ú© Ú©Ù ÛÛÛ Ø¯Ø³ØªÛØ§Ø¨ ÙÙØ¯Ø§Ø±: %',GREATEST(0,v_available) USING ERRCODE='23514'; END IF;
  INSERT INTO public.product_sales(sale_date,product_type,quantity,unit,unit_price,total_amount,notes,worker_id)
  VALUES(p_sale_date,p_product_type,p_quantity,v_unit,v_price,v_total,NULL,p_worker_id) RETURNING id::text INTO v_sale_id;
  RETURN jsonb_build_object('sale_id',v_sale_id,'product_type',p_product_type,'quantity',p_quantity,'unit',v_unit,
    'unit_price',v_price,'total_amount',v_total,
    'labor_amount',CASE WHEN p_product_type='6L' OR p_worker_id IS NULL OR v_is_owner THEN 0 ELSE p_quantity*10 END,
    'owner_saved_labor',CASE WHEN p_product_type='6L' OR NOT v_is_owner THEN 0 ELSE p_quantity*10 END);
END; $function$

;

-- Backward-compatible old RPC signature: old clients get 280, never 270.
CREATE OR REPLACE FUNCTION public.record_product_sale(
  p_sale_date date, p_product_type text, p_quantity integer, p_worker_id bigint
) RETURNS jsonb LANGUAGE plpgsql SET search_path TO '' AS $fn$
BEGIN
  RETURN public.record_product_sale(
    p_sale_date, p_product_type, p_quantity, p_worker_id,
    CASE WHEN p_product_type='6L' THEN 55::numeric ELSE 280::numeric END
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.enforce_product_sale_price_floor() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_product_sale(date,text,integer,bigint,numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_product_sale(date,text,integer,bigint,numeric) TO authenticated;
REVOKE ALL ON FUNCTION public.record_product_sale(date,text,integer,bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_product_sale(date,text,integer,bigint) TO authenticated;

-- Verification result in SQL Editor.
SELECT 'CARTON_PRICE_RULES_COMMITTED' AS repair_status,
       to_regprocedure('public.record_product_sale(date,text,integer,bigint,numeric)') IS NOT NULL AS flexible_price_rpc_exists,
       EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.product_sales'::regclass AND tgname='enforce_product_sale_price_floor' AND NOT tgisinternal) AS product_sales_price_guard_enabled,
       EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.product_sales'::regclass AND conname='product_sales_price_floor_check') AS product_sales_floor_constraint_exists,
       EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.sales'::regclass AND conname='sales_price_floor_check') AS legacy_sales_floor_constraint_exists;
COMMIT;
