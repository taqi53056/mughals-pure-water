-- Keep the shared shop-water pool and 19L cap inventory from going negative.
-- This guard is server-side so admin UI retries or concurrent requests cannot bypass it.
CREATE OR REPLACE FUNCTION private.mpw_guard_operational_stock()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
DECLARE
  v_date date;
  v_available numeric:=0;
  v_consumed numeric:=0;
  v_required numeric:=0;
BEGIN
  IF TG_TABLE_NAME='customer_19l_deliveries' THEN
    v_date:=NEW.delivery_date;
    v_required:=coalesce(NEW.successful_bottles,0)*19;

    PERFORM pg_advisory_xact_lock(hashtextextended('water-pool-shop',0));
    SELECT
      coalesce((SELECT sum(tanker_count*1000) FROM public.water_tanker_purchases
        WHERE water_use='shop_counter' AND purchase_date<=v_date),0)
      +coalesce((SELECT sum(litres) FROM public.water_opening_stock
        WHERE water_use='shop_counter' AND as_of_date<=v_date),0)
    INTO v_available;
    SELECT
      coalesce((SELECT sum(successful_bottles*19) FROM public.customer_19l_deliveries
        WHERE delivery_date<=v_date AND id IS DISTINCT FROM NEW.id),0)
      +coalesce((SELECT sum(total_litres) FROM public.counter_water_sales
        WHERE sale_date<=v_date),0)
      +coalesce((SELECT sum(quantity*6) FROM public.production
        WHERE product_type='6L' AND production_date<=v_date),0)
    INTO v_consumed;
    IF v_available-v_consumed<v_required THEN
      RAISE EXCEPTION 'دکان والی ٹنکی کا پانی ناکافی ہے۔ دستیاب لیٹر: %، درکار: %',
        greatest(v_available-v_consumed,0),v_required USING ERRCODE='23514';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended('raw-material-cap-19l',0));
    SELECT coalesce(sum(quantity),0) INTO v_available
    FROM public.raw_material_purchases
    WHERE material_type='cap_19l' AND purchase_date<=v_date;
    SELECT coalesce(sum(successful_bottles+damaged_caps),0) INTO v_consumed
    FROM public.customer_19l_deliveries
    WHERE delivery_date<=v_date AND id IS DISTINCT FROM NEW.id;
    v_required:=coalesce(NEW.successful_bottles,0)+coalesce(NEW.damaged_caps,0);
    IF v_available-v_consumed<v_required THEN
      RAISE EXCEPTION '19L ڈھکن ناکافی ہیں۔ دستیاب: %، درکار: %',
        greatest(v_available-v_consumed,0),v_required USING ERRCODE='23514';
    END IF;
    RETURN NEW;

  ELSIF TG_TABLE_NAME='counter_water_sales' THEN
    v_date:=NEW.sale_date;
    v_required:=NEW.total_litres;

    PERFORM pg_advisory_xact_lock(hashtextextended('water-pool-shop',0));
    SELECT
      coalesce((SELECT sum(tanker_count*1000) FROM public.water_tanker_purchases
        WHERE water_use='shop_counter' AND purchase_date<=v_date),0)
      +coalesce((SELECT sum(litres) FROM public.water_opening_stock
        WHERE water_use='shop_counter' AND as_of_date<=v_date),0)
    INTO v_available;
    SELECT
      coalesce((SELECT sum(successful_bottles*19) FROM public.customer_19l_deliveries
        WHERE delivery_date<=v_date),0)
      +coalesce((SELECT sum(total_litres) FROM public.counter_water_sales
        WHERE sale_date<=v_date AND id IS DISTINCT FROM NEW.id),0)
      +coalesce((SELECT sum(quantity*6) FROM public.production
        WHERE product_type='6L' AND production_date<=v_date),0)
    INTO v_consumed;
    IF v_available-v_consumed<v_required THEN
      RAISE EXCEPTION 'دکان والی ٹنکی کا پانی ناکافی ہے۔ دستیاب لیٹر: %، درکار: %',
        greatest(v_available-v_consumed,0),v_required USING ERRCODE='23514';
    END IF;
    RETURN NEW;

  ELSIF TG_TABLE_NAME='production' THEN
    v_date:=NEW.production_date;
    IF NEW.product_type='6L' THEN
      v_required:=NEW.quantity*6;
      PERFORM pg_advisory_xact_lock(hashtextextended('water-pool-shop',0));
      SELECT
        coalesce((SELECT sum(tanker_count*1000) FROM public.water_tanker_purchases
          WHERE water_use='shop_counter' AND purchase_date<=v_date),0)
        +coalesce((SELECT sum(litres) FROM public.water_opening_stock
          WHERE water_use='shop_counter' AND as_of_date<=v_date),0)
      INTO v_available;
      SELECT
        coalesce((SELECT sum(successful_bottles*19) FROM public.customer_19l_deliveries
          WHERE delivery_date<=v_date),0)
        +coalesce((SELECT sum(total_litres) FROM public.counter_water_sales
          WHERE sale_date<=v_date),0)
        +coalesce((SELECT sum(quantity*6) FROM public.production
          WHERE product_type='6L' AND production_date<=v_date),0)
      INTO v_consumed;
    ELSE
      v_required:=NEW.quantity*CASE NEW.product_type WHEN '500ml' THEN 12 ELSE 18 END;
      PERFORM pg_advisory_xact_lock(hashtextextended('water-pool-filling',0));
      SELECT
        coalesce((SELECT sum(tanker_count*1000) FROM public.water_tanker_purchases
          WHERE water_use='product_filling' AND purchase_date<=v_date),0)
        +coalesce((SELECT sum(litres) FROM public.water_opening_stock
          WHERE water_use='product_filling' AND as_of_date<=v_date),0)
      INTO v_available;
      SELECT coalesce(sum(quantity*CASE product_type WHEN '500ml' THEN 12 WHEN '1.5L' THEN 18 ELSE 0 END),0)
      INTO v_consumed
      FROM public.production
      WHERE product_type IN ('500ml','1.5L') AND production_date<=v_date;
    END IF;
    IF v_available-v_consumed<v_required THEN
      RAISE EXCEPTION 'پروڈکشن کے لیے متعلقہ ٹنکی کا پانی ناکافی ہے۔ دستیاب لیٹر: %، درکار: %',
        greatest(v_available-v_consumed,0),v_required USING ERRCODE='23514';
    END IF;
    RETURN NEW;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS mpw_shop_water_stock_guard ON public.customer_19l_deliveries;
CREATE TRIGGER mpw_shop_water_stock_guard
BEFORE INSERT OR UPDATE ON public.customer_19l_deliveries
FOR EACH ROW EXECUTE FUNCTION private.mpw_guard_operational_stock();

DROP TRIGGER IF EXISTS mpw_shop_water_stock_guard ON public.counter_water_sales;
CREATE TRIGGER mpw_shop_water_stock_guard
BEFORE INSERT OR UPDATE ON public.counter_water_sales
FOR EACH ROW EXECUTE FUNCTION private.mpw_guard_operational_stock();

DROP TRIGGER IF EXISTS mpw_production_water_stock_guard ON public.production;
CREATE TRIGGER mpw_production_water_stock_guard
BEFORE INSERT ON public.production
FOR EACH ROW EXECUTE FUNCTION private.mpw_guard_operational_stock();
