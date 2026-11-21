-- MUGHAL'S PURE WATER
-- Daily counter gross receipts: include all counter product receipts.
-- Automatically isolate the 19L counter component by subtracting:
--   1) same-day unassigned 19L collections, and
--   2) same-day cash product_sales already recorded in the product-sales module.
-- Unpaid unassigned deliveries are NOT deducted until their collection is recorded.
-- Applied to the hosted database on 2026-11-21 and verified with rollback-only tests.

ALTER TABLE public.counter_water_sales
  ADD COLUMN IF NOT EXISTS product_sales_receipts_included numeric(14,2) NOT NULL DEFAULT 0;

CREATE OR REPLACE FUNCTION private.mpw_derive_counter_water_values()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_unassigned_receipts numeric(14,2) := 0;
  v_product_cash_receipts numeric(14,2) := 0;
BEGIN
  IF NEW.reported_total_amount IS NOT NULL THEN
    IF NEW.reported_total_amount < 0 THEN
      RAISE EXCEPTION 'روزانہ مجموعی کاؤنٹر وصولی منفی نہیں ہو سکتی۔'
        USING ERRCODE='22023';
    END IF;

    SELECT COALESCE(SUM(c.amount),0)
      INTO v_unassigned_receipts
    FROM public.unassigned_19l_delivery_collections c
    WHERE c.received_date = NEW.sale_date;

    SELECT COALESCE(SUM(ps.total_amount),0)
      INTO v_product_cash_receipts
    FROM public.product_sales ps
    WHERE ps.sale_date = NEW.sale_date
      AND ps.payment_method = 'cash';

    IF NEW.reported_total_amount < v_unassigned_receipts + v_product_cash_receipts THEN
      RAISE EXCEPTION
        'مجموعی کاؤنٹر وصولی (%)، آج کی غیر منسلک وصولی (%) اور الگ درج نقد مصنوعات کی فروخت (%) کے مجموعے سے کم ہے۔',
        NEW.reported_total_amount, v_unassigned_receipts, v_product_cash_receipts
        USING ERRCODE='23514';
    END IF;

    NEW.unassigned_receipts_included := v_unassigned_receipts;
    NEW.product_sales_receipts_included := v_product_cash_receipts;
    NEW.total_amount := NEW.reported_total_amount
      - v_unassigned_receipts - v_product_cash_receipts;
    NEW.counter_bottles_estimated := NEW.total_amount / 50;
    NEW.counter_water_litres := NEW.counter_bottles_estimated * 19;
    NEW.total_litres := 0;
    NEW.payment_method := 'mixed';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION private.mpw_refresh_counter_water_after_product_sale()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF TG_OP = 'DELETE' OR (TG_OP = 'UPDATE' AND OLD.sale_date IS DISTINCT FROM NEW.sale_date) THEN
    UPDATE public.counter_water_sales
       SET reported_total_amount = reported_total_amount
     WHERE sale_date = OLD.sale_date
       AND reported_total_amount IS NOT NULL;
  END IF;

  IF TG_OP <> 'DELETE' THEN
    UPDATE public.counter_water_sales
       SET reported_total_amount = reported_total_amount
     WHERE sale_date = NEW.sale_date
       AND reported_total_amount IS NOT NULL;
  END IF;

  RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS mpw_refresh_counter_water_after_product_sale
  ON public.product_sales;
CREATE TRIGGER mpw_refresh_counter_water_after_product_sale
AFTER INSERT OR UPDATE OR DELETE ON public.product_sales
FOR EACH ROW
EXECUTE FUNCTION private.mpw_refresh_counter_water_after_product_sale();

REVOKE ALL ON FUNCTION private.mpw_refresh_counter_water_after_product_sale() FROM PUBLIC, anon, authenticated;

-- Keep monthly report stock estimates aligned with the counter_water_litres
-- value used by the live water-tank module (legacy total_litres rows remain supported).
DO $repair$
DECLARE
  v_def text;
  v_old text := 'coalesce((select sum(total_litres) from public.counter_water_sales where sale_date<=p_month_end),0)';
  v_new text := 'coalesce((select sum(private.mpw_counter_water_litres(s.sale_date,s.total_litres,s.counter_water_litres)) from public.counter_water_sales s where s.sale_date<=p_month_end),0)';
  v_count integer;
  v_old_note text := 'نئے روزانہ اندراج میں صرف مجموعی 19L وصولی درج ہوتی ہے؛ اسی دن موصول غیر منسلک سپلائی کی رقم منہا کرکے کاؤنٹر رقم نکالی جاتی ہے۔';
  v_new_note text := 'نئے روزانہ اندراج میں تمام مصنوعات سمیت مجموعی کاؤنٹر وصولی درج ہوتی ہے؛ اسی دن موصول غیر منسلک سپلائی اور الگ درج نقد مصنوعات کی رقم منہا کرکے باقی رقم کو 50 روپے فی 19L بوتل کے حساب سے کاؤنٹر 19L پانی کا تخمینہ بنایا جاتا ہے۔';
BEGIN
  SELECT pg_get_functiondef('public.build_business_monthly_report(date,date)'::regprocedure)
    INTO v_def;
  v_count := (length(v_def)-length(replace(v_def,v_old,''))) / length(v_old);
  IF v_count <> 3 THEN
    RAISE EXCEPTION 'Expected 3 counter-water stock expressions, found %.',v_count;
  END IF;
  v_def := replace(v_def,v_old,v_new);
  IF position(v_old_note in v_def)=0 THEN
    RAISE EXCEPTION 'Expected legacy report note not found.';
  END IF;
  v_def := replace(v_def,v_old_note,v_new_note);
  EXECUTE v_def;
END
$repair$;
