-- Enforce all non-cap production packaging inputs before a production row is saved.
-- The existing cap guard remains responsible for cap_500ml/cap_1_5l/cap_6l.
-- This guard covers bottles, cartons, tape and stickers using the same lock as
-- the raw-material opening-stock guard so production and opening-stock edits
-- cannot race each other.

CREATE OR REPLACE FUNCTION private.mpw_guard_production_packaging_stock()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
DECLARE
  v_requirement record;
  v_available numeric := 0;
  v_consumed numeric := 0;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('production-inputs', 0));

  FOR v_requirement IN
    SELECT material_type, required_quantity
    FROM (VALUES
      ('bottle_500ml'::text,
        CASE WHEN NEW.product_type='500ml' THEN NEW.quantity*24 ELSE 0 END),
      ('carton_500ml'::text,
        CASE WHEN NEW.product_type='500ml' THEN NEW.quantity ELSE 0 END),
      ('bottle_1_5l'::text,
        CASE WHEN NEW.product_type='1.5L' THEN NEW.quantity*12 ELSE 0 END),
      ('carton_1_5l'::text,
        CASE WHEN NEW.product_type='1.5L' THEN NEW.quantity ELSE 0 END),
      ('bottle_6l'::text,
        CASE WHEN NEW.product_type='6L' THEN NEW.quantity ELSE 0 END),
      ('tape_bundle'::text,
        CASE WHEN NEW.product_type IN ('500ml','1.5L')
          THEN NEW.quantity/200::numeric ELSE 0 END),
      ('sticker'::text,
        CASE NEW.product_type
          WHEN '500ml' THEN NEW.quantity*24
          WHEN '1.5L' THEN NEW.quantity*12
          WHEN '6L' THEN NEW.quantity
          ELSE 0
        END)
    ) AS requirements(material_type, required_quantity)
    WHERE required_quantity > 0
  LOOP
    SELECT coalesce(sum(r.quantity),0)
      INTO v_available
    FROM public.raw_material_purchases r
    WHERE r.material_type=v_requirement.material_type
      AND r.purchase_date<=NEW.production_date;

    SELECT coalesce(sum(
      CASE v_requirement.material_type
        WHEN 'bottle_500ml' THEN
          CASE WHEN p.product_type='500ml' THEN p.quantity*24 ELSE 0 END
        WHEN 'carton_500ml' THEN
          CASE WHEN p.product_type='500ml' THEN p.quantity ELSE 0 END
        WHEN 'bottle_1_5l' THEN
          CASE WHEN p.product_type='1.5L' THEN p.quantity*12 ELSE 0 END
        WHEN 'carton_1_5l' THEN
          CASE WHEN p.product_type='1.5L' THEN p.quantity ELSE 0 END
        WHEN 'bottle_6l' THEN
          CASE WHEN p.product_type='6L' THEN p.quantity ELSE 0 END
        WHEN 'tape_bundle' THEN
          CASE WHEN p.product_type IN ('500ml','1.5L')
            THEN p.quantity/200::numeric ELSE 0 END
        WHEN 'sticker' THEN
          CASE p.product_type
            WHEN '500ml' THEN p.quantity*24
            WHEN '1.5L' THEN p.quantity*12
            WHEN '6L' THEN p.quantity
            ELSE 0
          END
        ELSE 0
      END
    ),0)
      INTO v_consumed
    FROM public.production p
    WHERE p.production_date<=NEW.production_date
      AND p.id IS DISTINCT FROM NEW.id;

    IF v_available-v_consumed < v_requirement.required_quantity THEN
      RAISE EXCEPTION
        'خام مال % ناکافی ہے۔ دستیاب: %، پہلے استعمال: %، اس پروڈکشن کے لیے درکار: %',
        v_requirement.material_type,
        greatest(v_available-v_consumed,0),
        v_consumed,
        v_requirement.required_quantity
        USING ERRCODE='23514';
    END IF;
  END LOOP;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS mpw_production_all_material_stock_guard ON public.production;
CREATE TRIGGER mpw_production_all_material_stock_guard
BEFORE INSERT OR UPDATE OF product_type, quantity, production_date
ON public.production
FOR EACH ROW
EXECUTE FUNCTION private.mpw_guard_production_packaging_stock();
