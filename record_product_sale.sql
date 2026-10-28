-- MUGHAL'S PURE WATER: Atomic small-pack sale + carton labor entry
-- Run once in Supabase SQL Editor while signed in as project owner.
-- This function checks admin access and stock on the server, then writes
-- product_sales and (for carton products) business_expenses in one transaction.

CREATE OR REPLACE FUNCTION public.record_product_sale(
  p_sale_date date,
  p_product_type text,
  p_quantity integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_unit text;
  v_price numeric;
  v_available numeric;
  v_sale_id text;
  v_total numeric;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'صرف ایڈمن سیل درج کر سکتا ہے۔' USING ERRCODE = '42501';
  END IF;

  IF p_sale_date IS NULL THEN
    RAISE EXCEPTION 'سیل کی تاریخ درج کریں۔' USING ERRCODE = '22023';
  END IF;
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'مقدار صفر سے زیادہ مکمل عدد ہونی چاہیے۔' USING ERRCODE = '22023';
  END IF;
  IF p_product_type NOT IN ('500ml', '1.5L', '6L') THEN
    RAISE EXCEPTION 'پروڈکٹ کی قسم درست نہیں۔' USING ERRCODE = '22023';
  END IF;

  -- Serialize concurrent sales of the same product to prevent overselling.
  PERFORM pg_advisory_xact_lock(hashtextextended('finished-stock:' || p_product_type, 0));

  v_unit := CASE WHEN p_product_type = '6L' THEN 'bottle' ELSE 'carton' END;
  v_price := CASE
    WHEN p_product_type = '6L' THEN 55
    WHEN p_quantity = 100 THEN 270
    ELSE 280
  END;
  v_total := p_quantity * v_price;

  SELECT
    COALESCE((SELECT SUM(quantity) FROM public.finished_goods
              WHERE product_type = p_product_type AND unit = v_unit), 0)
    - COALESCE((SELECT SUM(quantity) FROM public.product_sales
                WHERE product_type = p_product_type AND unit = v_unit), 0)
    + COALESCE((SELECT SUM(CASE
                  WHEN adjustment_type = 'increase' THEN quantity
                  WHEN adjustment_type = 'decrease' THEN -quantity
                  ELSE 0 END)
               FROM public.finished_stock_adjustments
               WHERE product_type = p_product_type), 0)
  INTO v_available;

  IF p_quantity > v_available THEN
    RAISE EXCEPTION 'تیار مال کا اسٹاک کم ہے۔ دستیاب مقدار: %', GREATEST(0, v_available)
      USING ERRCODE = '23514';
  END IF;

  INSERT INTO public.product_sales
    (sale_date, product_type, quantity, unit, unit_price, total_amount, notes)
  VALUES
    (p_sale_date, p_product_type, p_quantity, v_unit, v_price, v_total, NULL)
  RETURNING id::text INTO v_sale_id;

  IF p_product_type <> '6L' THEN
    INSERT INTO public.business_expenses
      (expense_date, category, amount, details)
    VALUES
      (p_sale_date, 'کارٹن تیار کرنے کی مزدوری', p_quantity * 10,
       p_product_type || ' کے ' || p_quantity || ' کارٹن × Rs.10');
  END IF;

  RETURN jsonb_build_object(
    'sale_id', v_sale_id,
    'product_type', p_product_type,
    'quantity', p_quantity,
    'unit', v_unit,
    'unit_price', v_price,
    'total_amount', v_total,
    'labor_amount', CASE WHEN p_product_type = '6L' THEN 0 ELSE p_quantity * 10 END
  );
END;
$$;

REVOKE ALL ON FUNCTION public.record_product_sale(date, text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_product_sale(date, text, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.record_product_sale(date, text, integer) TO authenticated;
