CREATE OR REPLACE FUNCTION private.mpw_guard_shop_water_full_balance()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
DECLARE
  v_event_date date;
  v_available numeric := 0;
  v_consumed numeric := 0;
  v_old_id bigint := NULL;
  v_new_source_date date := NULL;
  v_new_source_litres numeric := 0;
BEGIN
  IF TG_OP='UPDATE' THEN
    v_old_id := OLD.id;
  END IF;

  IF TG_TABLE_NAME='water_tanker_purchases' THEN
    IF NEW.water_use='shop_counter' THEN
      v_new_source_date:=NEW.purchase_date;
      v_new_source_litres:=NEW.tanker_count*1000;
    END IF;
  ELSIF TG_TABLE_NAME='water_opening_stock' THEN
    IF NEW.water_use='shop_counter' THEN
      v_new_source_date:=NEW.as_of_date;
      v_new_source_litres:=NEW.litres;
    END IF;
  ELSE
    RAISE EXCEPTION 'غیر معاون پانی کے ریکارڈ پر یہ حفاظتی فنکشن نہیں چل سکتا۔'
      USING ERRCODE='22023';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('water-pool-shop',0));

  FOR v_event_date IN
    SELECT DISTINCT event_date
    FROM (
      SELECT d.delivery_date AS event_date FROM public.customer_19l_deliveries d
      UNION ALL SELECT d.delivery_date FROM public.unassigned_19l_deliveries d
      UNION ALL SELECT c.sale_date FROM public.counter_water_sales c
      UNION ALL SELECT p.production_date FROM public.production p WHERE p.product_type='6L'
    ) e
    WHERE event_date IS NOT NULL
    ORDER BY event_date
  LOOP
    SELECT
      COALESCE((SELECT sum(t.tanker_count*1000)
        FROM public.water_tanker_purchases t
        WHERE t.water_use='shop_counter'
          AND t.purchase_date<=v_event_date
          AND (TG_TABLE_NAME<>'water_tanker_purchases' OR v_old_id IS NULL OR t.id IS DISTINCT FROM v_old_id)),0)
      + COALESCE((SELECT sum(w.litres)
        FROM public.water_opening_stock w
        WHERE w.water_use='shop_counter'
          AND w.as_of_date<=v_event_date
          AND (TG_TABLE_NAME<>'water_opening_stock' OR v_old_id IS NULL OR w.id IS DISTINCT FROM v_old_id)),0)
      + CASE WHEN v_new_source_date<=v_event_date THEN v_new_source_litres ELSE 0 END
    INTO v_available;

    SELECT
      COALESCE((SELECT sum(d.bottles_delivered*19)
        FROM public.customer_19l_deliveries d WHERE d.delivery_date<=v_event_date),0)
      + COALESCE((SELECT sum(d.bottles_delivered*19)
        FROM public.unassigned_19l_deliveries d WHERE d.delivery_date<=v_event_date),0)
      + COALESCE((SELECT sum(c.total_litres)
        FROM public.counter_water_sales c WHERE c.sale_date<=v_event_date),0)
      + COALESCE((SELECT sum(p.quantity*6)
        FROM public.production p WHERE p.product_type='6L' AND p.production_date<=v_event_date),0)
    INTO v_consumed;

    IF v_available<v_consumed THEN
      RAISE EXCEPTION
        'دکان والی ٹنکی کا پانی غیر متوازن ہوگا۔ تاریخ: %، دستیاب: %، استعمال: %',
        v_event_date,greatest(v_available,0),v_consumed
        USING ERRCODE='23514';
    END IF;
  END LOOP;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS z_mpw_shop_water_full_balance_guard ON public.water_opening_stock;
CREATE TRIGGER z_mpw_shop_water_full_balance_guard
BEFORE INSERT OR UPDATE ON public.water_opening_stock
FOR EACH ROW EXECUTE FUNCTION private.mpw_guard_shop_water_full_balance();

DROP TRIGGER IF EXISTS z_mpw_shop_water_full_balance_guard ON public.water_tanker_purchases;
CREATE TRIGGER z_mpw_shop_water_full_balance_guard
BEFORE UPDATE ON public.water_tanker_purchases
FOR EACH ROW EXECUTE FUNCTION private.mpw_guard_shop_water_full_balance();