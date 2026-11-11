-- A carton discount below the default rate is valid only at the configured
-- special rate and only for orders of at least 100 cartons.
CREATE OR REPLACE FUNCTION public.enforce_product_sale_price_floor()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
DECLARE
  v_default_rate numeric;
  v_special_rate numeric;
BEGIN
  IF NEW.product_type IN ('500ml','1.5L') THEN
    IF NEW.unit <> 'carton' OR NEW.unit_price IS NULL OR NEW.unit_price < 270 THEN
      RAISE EXCEPTION '500ml/1.5L carton price cannot be below Rs.270.'
        USING ERRCODE='23514';
    END IF;

    SELECT ps.default_rate, ps.special_100_rate
      INTO v_default_rate, v_special_rate
    FROM public.product_settings ps
    WHERE ps.product_type=NEW.product_type
      AND ps.is_active=true;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'اس پروڈکٹ کی فعال قیمتوں کی سیٹنگ موجود نہیں۔'
        USING ERRCODE='23514';
    END IF;

    IF NEW.unit_price < v_default_rate
       AND (NEW.quantity < 100
         OR v_special_rate IS NULL
         OR NEW.unit_price IS DISTINCT FROM v_special_rate) THEN
      RAISE EXCEPTION 'خصوصی قیمت صرف 100 یا زیادہ کارٹن پر اور مقررہ خصوصی قیمت کے مطابق لاگو ہوگی۔'
        USING ERRCODE='23514';
    END IF;

  ELSIF NEW.product_type='6L' THEN
    IF NEW.unit <> 'bottle' OR NEW.unit_price IS NULL OR NEW.unit_price < 55 THEN
      RAISE EXCEPTION '6L bottle price cannot be below Rs.55.'
        USING ERRCODE='23514';
    END IF;
  ELSE
    RAISE EXCEPTION 'Invalid product type.'
      USING ERRCODE='22023';
  END IF;

  NEW.total_amount := NEW.quantity * NEW.unit_price;
  RETURN NEW;
END;
$function$;