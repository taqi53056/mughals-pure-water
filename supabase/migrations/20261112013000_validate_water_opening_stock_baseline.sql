CREATE OR REPLACE FUNCTION private.mpw_guard_water_opening_stock()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
DECLARE
  v_old_id bigint;
  v_event_date date;
  v_available numeric := 0;
  v_consumed numeric := 0;
  v_lock_key text;
BEGIN
  IF TG_OP='DELETE' THEN
    RAISE EXCEPTION 'ابتدائی پانی کا اسٹاک حذف نہیں کیا جا سکتا؛ درستگی کے لیے مقدار اپڈیٹ کریں۔'
      USING ERRCODE='55000';
  END IF;

  IF TG_OP='UPDATE' THEN
    IF NEW.water_use IS DISTINCT FROM OLD.water_use
       OR NEW.as_of_date IS DISTINCT FROM OLD.as_of_date THEN
      RAISE EXCEPTION 'پانی کے ابتدائی اسٹاک کا پول اور تاریخ تبدیل نہیں کیے جا سکتے۔'
        USING ERRCODE='55000';
    END IF;
    v_old_id:=OLD.id;
  END IF;

  IF NEW.water_use NOT IN ('shop_counter','product_filling') OR NEW.litres<=0 THEN
    RAISE EXCEPTION 'پانی کا پول اور مثبت لیٹر مقدار درست درج کریں۔'
      USING ERRCODE='22023';
  END IF;
  IF NEW.as_of_date>(now() AT TIME ZONE 'Asia/Karachi')::date THEN
    RAISE EXCEPTION 'ابتدائی پانی کا اسٹاک مستقبل کی تاریخ پر درج نہیں ہو سکتا۔'
      USING ERRCODE='22023';
  END IF;

  -- Opening stock is the starting balance, not an extra top-up after operations
  -- have already begun in the same pool.
  IF NEW.water_use='shop_counter' THEN
    IF EXISTS (SELECT 1 FROM public.water_tanker_purchases
        WHERE water_use='shop_counter' AND purchase_date<NEW.as_of_date)
       OR EXISTS (SELECT 1 FROM public.customer_19l_deliveries
        WHERE delivery_date<NEW.as_of_date)
       OR EXISTS (SELECT 1 FROM public.counter_water_sales
        WHERE sale_date<NEW.as_of_date)
       OR EXISTS (SELECT 1 FROM public.production
        WHERE product_type='6L' AND production_date<NEW.as_of_date) THEN
      RAISE EXCEPTION 'دکان والی ٹنکی کا ابتدائی اسٹاک پہلی خریداری یا استعمال کی تاریخ سے بعد میں نہیں ہو سکتا۔ درست ابتدائی تاریخ درج کریں۔'
        USING ERRCODE='23514';
    END IF;
  ELSE
    IF EXISTS (SELECT 1 FROM public.water_tanker_purchases
        WHERE water_use='product_filling' AND purchase_date<NEW.as_of_date)
       OR EXISTS (SELECT 1 FROM public.production
        WHERE product_type IN ('500ml','1.5L') AND production_date<NEW.as_of_date) THEN
      RAISE EXCEPTION 'پروڈکشن والی ٹنکی کا ابتدائی اسٹاک پہلی خریداری یا پروڈکشن کی تاریخ سے بعد میں نہیں ہو سکتا۔ درست ابتدائی تاریخ درج کریں۔'
        USING ERRCODE='23514';
    END IF;
  END IF;

  v_lock_key:=CASE WHEN NEW.water_use='shop_counter' THEN 'water-pool-shop' ELSE 'water-pool-filling' END;
  PERFORM pg_advisory_xact_lock(hashtextextended(v_lock_key,0));

  IF NEW.water_use='shop_counter' THEN
    FOR v_event_date IN
      SELECT DISTINCT event_date FROM (
        SELECT d.delivery_date AS event_date FROM public.customer_19l_deliveries d
        UNION ALL SELECT c.sale_date FROM public.counter_water_sales c
        UNION ALL SELECT p.production_date FROM public.production p WHERE p.product_type='6L'
      ) e WHERE event_date IS NOT NULL ORDER BY event_date
    LOOP
      SELECT
        COALESCE((SELECT sum(t.tanker_count*1000) FROM public.water_tanker_purchases t
          WHERE t.water_use='shop_counter' AND t.purchase_date<=v_event_date),0)
        + COALESCE((SELECT sum(w.litres) FROM public.water_opening_stock w
          WHERE w.water_use='shop_counter' AND w.as_of_date<=v_event_date
            AND (v_old_id IS NULL OR w.id IS DISTINCT FROM v_old_id)),0)
        + CASE WHEN NEW.as_of_date<=v_event_date THEN NEW.litres ELSE 0 END
      INTO v_available;

      SELECT
        COALESCE((SELECT sum(d.bottles_delivered*19) FROM public.customer_19l_deliveries d
          WHERE d.delivery_date<=v_event_date),0)
        + COALESCE((SELECT sum(c.total_litres) FROM public.counter_water_sales c
          WHERE c.sale_date<=v_event_date),0)
        + COALESCE((SELECT sum(p.quantity*6) FROM public.production p
          WHERE p.product_type='6L' AND p.production_date<=v_event_date),0)
      INTO v_consumed;

      IF v_available<v_consumed THEN
        RAISE EXCEPTION 'دکان والی ٹنکی کے ابتدائی پانی میں کمی سے سابقہ استعمال غیر متوازن ہوگا۔ تاریخ: %، دستیاب: %، استعمال: %',
          v_event_date,greatest(v_available,0),v_consumed USING ERRCODE='23514';
      END IF;
    END LOOP;
  ELSE
    FOR v_event_date IN
      SELECT DISTINCT p.production_date
      FROM public.production p
      WHERE p.product_type IN ('500ml','1.5L')
      ORDER BY p.production_date
    LOOP
      SELECT
        COALESCE((SELECT sum(t.tanker_count*1000) FROM public.water_tanker_purchases t
          WHERE t.water_use='product_filling' AND t.purchase_date<=v_event_date),0)
        + COALESCE((SELECT sum(w.litres) FROM public.water_opening_stock w
          WHERE w.water_use='product_filling' AND w.as_of_date<=v_event_date
            AND (v_old_id IS NULL OR w.id IS DISTINCT FROM v_old_id)),0)
        + CASE WHEN NEW.as_of_date<=v_event_date THEN NEW.litres ELSE 0 END
      INTO v_available;

      SELECT COALESCE(sum(p.quantity*CASE p.product_type WHEN '500ml' THEN 12 ELSE 18 END),0)
      INTO v_consumed
      FROM public.production p
      WHERE p.product_type IN ('500ml','1.5L') AND p.production_date<=v_event_date;

      IF v_available<v_consumed THEN
        RAISE EXCEPTION 'پروڈکشن والی ٹنکی کے ابتدائی پانی میں کمی سے سابقہ پروڈکشن غیر متوازن ہوگی۔ تاریخ: %، دستیاب: %، استعمال: %',
          v_event_date,greatest(v_available,0),v_consumed USING ERRCODE='23514';
      END IF;
    END LOOP;
  END IF;

  RETURN NEW;
END;
$function$;
