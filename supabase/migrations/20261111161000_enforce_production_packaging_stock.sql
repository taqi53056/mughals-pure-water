-- Enforce all non-cap production packaging inputs before a production row is saved.
-- The existing cap guard remains responsible for cap_500ml/cap_1_5l/cap_6l.
-- All guards share the production-inputs transaction advisory lock.
-- A raw-material opening_stock row is a physical cutover: purchases and
-- production/delivery consumption before that date must not be counted again.

CREATE OR REPLACE FUNCTION private.mpw_guard_production_packaging_stock()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
DECLARE
  v_requirement record;
  v_cutover_date date;
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
    SELECT min(r.purchase_date)
      INTO v_cutover_date
    FROM public.raw_material_purchases r
    WHERE r.material_type=v_requirement.material_type
      AND r.record_type='opening_stock';

    SELECT coalesce(sum(r.quantity),0)
      INTO v_available
    FROM public.raw_material_purchases r
    WHERE r.material_type=v_requirement.material_type
      AND r.purchase_date<=NEW.production_date
      AND (v_cutover_date IS NULL OR NEW.production_date < v_cutover_date
        OR r.record_type='opening_stock' OR r.purchase_date>=v_cutover_date);

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
      AND (v_cutover_date IS NULL OR NEW.production_date < v_cutover_date
        OR p.production_date>=v_cutover_date)
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

-- Align existing cap, 19L-cap and raw-material correction guards with the
-- same physical opening-stock cutover used by the app's raw-stock summary.
DO $migration$
DECLARE
  v_definition text;
  v_old text;
  v_new text;
BEGIN
  -- Production caps.
  SELECT pg_get_functiondef(
    'private.mpw_guard_production_cap_stock()'::regprocedure
  ) INTO v_definition;

  v_old := $old$  v_material_type text;
  v_required numeric := 0;$old$;
  v_new := $new$  v_material_type text;
  v_cutover_date date;
  v_required numeric := 0;$new$;
  v_definition := replace(v_definition,v_old,v_new);

  v_old := $old$  PERFORM pg_advisory_xact_lock(hashtextextended('production-inputs',0));

  v_material_type := CASE NEW.product_type$old$;
  v_new := $new$  PERFORM pg_advisory_xact_lock(hashtextextended('production-inputs',0));

  v_material_type := CASE NEW.product_type$new$;
  v_definition := replace(v_definition,v_old,v_new);

  v_old := $old$  SELECT coalesce(sum(quantity),0)
    INTO v_available
  FROM public.raw_material_purchases
  WHERE material_type=v_material_type
    AND purchase_date<=NEW.production_date;$old$;
  v_new := $new$  SELECT min(purchase_date)
    INTO v_cutover_date
  FROM public.raw_material_purchases
  WHERE material_type=v_material_type AND record_type='opening_stock';

  SELECT coalesce(sum(quantity),0)
    INTO v_available
  FROM public.raw_material_purchases
  WHERE material_type=v_material_type
    AND purchase_date<=NEW.production_date
    AND (v_cutover_date IS NULL OR NEW.production_date < v_cutover_date
      OR record_type='opening_stock' OR purchase_date>=v_cutover_date);$new$;
  v_definition := replace(v_definition,v_old,v_new);

  v_old := $old$    AND production_date<=NEW.production_date
    AND id IS DISTINCT FROM NEW.id;$old$;
  v_new := $new$    AND production_date<=NEW.production_date
    AND (v_cutover_date IS NULL OR NEW.production_date < v_cutover_date
      OR production_date>=v_cutover_date)
    AND id IS DISTINCT FROM NEW.id;$new$;
  v_definition := replace(v_definition,v_old,v_new);

  IF position('v_cutover_date date;' IN v_definition)=0
     OR position('record_type=''opening_stock''' IN v_definition)=0
     OR position('production_date>=v_cutover_date' IN v_definition)=0 THEN
    RAISE EXCEPTION 'Could not safely align production cap stock guard with opening-stock cutover.';
  END IF;
  EXECUTE v_definition;

  -- Raw-material opening-stock and purchase corrections.
  SELECT pg_get_functiondef(
    'private.mpw_guard_raw_material_opening_stock()'::regprocedure
  ) INTO v_definition;

  v_old := $old$  v_event_date date;
  v_available numeric := 0;$old$;
  v_new := $new$  v_event_date date;
  v_cutover_date date;
  v_available numeric := 0;$new$;
  v_definition := replace(v_definition,v_old,v_new);

  v_old := $old$  perform pg_advisory_xact_lock(hashtextextended('production-inputs',0));

  for v_event_date in$old$;
  v_new := $new$  perform pg_advisory_xact_lock(hashtextextended('production-inputs',0));

  if new.record_type='opening_stock' then
    v_cutover_date:=new.purchase_date;
  else
    select min(r.purchase_date) into v_cutover_date
    from public.raw_material_purchases r
    where r.material_type=new.material_type
      and r.record_type='opening_stock';
  end if;

  for v_event_date in$new$;
  v_definition := replace(v_definition,v_old,v_new);

  v_old := $old$    where event_date is not null
    order by event_date$old$;
  v_new := $new$    where event_date is not null
      and (new.record_type<>'opening_stock' or v_cutover_date is null or event_date>=v_cutover_date)
    order by event_date$new$;
  v_definition := replace(v_definition,v_old,v_new);

  v_old := $old$    select coalesce(sum(r.quantity),0)
      + case when new.purchase_date<=v_event_date then new.quantity else 0 end
    into v_available
    from public.raw_material_purchases r
    where r.material_type=new.material_type
      and r.purchase_date<=v_event_date
      and (v_old_id is null or r.id is distinct from v_old_id);$old$;
  v_new := $new$    select coalesce(sum(r.quantity),0)
      + case when new.purchase_date<=v_event_date
          and (v_cutover_date is null
            or (v_event_date<v_cutover_date and new.record_type<>'opening_stock')
            or (v_event_date>=v_cutover_date
              and (new.record_type='opening_stock' or new.purchase_date>=v_cutover_date)))
        then new.quantity else 0 end
    into v_available
    from public.raw_material_purchases r
    where r.material_type=new.material_type
      and r.purchase_date<=v_event_date
      and (v_cutover_date is null
        or (v_event_date<v_cutover_date and r.record_type<>'opening_stock')
        or (v_event_date>=v_cutover_date
          and (r.record_type='opening_stock' or r.purchase_date>=v_cutover_date)))
      and (v_old_id is null or r.id is distinct from v_old_id);$new$;
  v_definition := replace(v_definition,v_old,v_new);

  v_old := $old$    where p.production_date<=v_event_date
      and ($old$;
  v_new := $new$    where p.production_date<=v_event_date
      and (v_cutover_date is null or v_event_date<v_cutover_date
        or p.production_date>=v_cutover_date)
      and ($new$;
  v_definition := replace(v_definition,v_old,v_new);

  v_old := $old$      where d.delivery_date<=v_event_date;$old$;
  v_new := $new$      where d.delivery_date<=v_event_date
        and (v_cutover_date is null or v_event_date<v_cutover_date
          or d.delivery_date>=v_cutover_date);$new$;
  v_definition := replace(v_definition,v_old,v_new);

  IF position('v_cutover_date date;' IN v_definition)=0
     OR position('event_date>=v_cutover_date' IN v_definition)=0
     OR position('p.production_date>=v_cutover_date' IN v_definition)=0
     OR position('d.delivery_date>=v_cutover_date' IN v_definition)=0 THEN
    RAISE EXCEPTION 'Could not safely align raw-material correction guard with opening-stock cutover.';
  END IF;
  EXECUTE v_definition;

  -- 19L damaged/replacement cap validation.
  SELECT pg_get_functiondef(
    'private.mpw_guard_operational_stock()'::regprocedure
  ) INTO v_definition;

  v_old := $old$  v_required numeric := 0;
begin$old$;
  v_new := $new$  v_required numeric := 0;
  v_cutover_date date;
begin$new$;
  v_definition := replace(v_definition,v_old,v_new);

  v_old := $old$    perform pg_advisory_xact_lock(hashtextextended('raw-material-cap-19l',0));
    select coalesce(sum(quantity),0) into v_available
    from public.raw_material_purchases
    where material_type='cap_19l' and purchase_date<=v_date;$old$;
  v_new := $new$    perform pg_advisory_xact_lock(hashtextextended('raw-material-cap-19l',0));
    select min(purchase_date) into v_cutover_date
    from public.raw_material_purchases
    where material_type='cap_19l' and record_type='opening_stock';
    select coalesce(sum(quantity),0) into v_available
    from public.raw_material_purchases
    where material_type='cap_19l' and purchase_date<=v_date
      and (v_cutover_date is null or v_date<v_cutover_date
        or record_type='opening_stock' or purchase_date>=v_cutover_date);$new$;
  v_definition := replace(v_definition,v_old,v_new);

  v_old := $old$    where delivery_date<=v_date and id is distinct from new.id;$old$;
  v_new := $new$    where delivery_date<=v_date and id is distinct from new.id
      and (v_cutover_date is null or v_date<v_cutover_date
          or delivery_date>=v_cutover_date);$new$;
  v_definition := replace(v_definition,v_old,v_new);

  IF position('v_cutover_date date;' IN v_definition)=0
     OR position('record_type=''opening_stock''' IN v_definition)=0
     OR position('delivery_date>=v_cutover_date' IN v_definition)=0 THEN
    RAISE EXCEPTION 'Could not safely align 19L cap guard with opening-stock cutover.';
  END IF;
  EXECUTE v_definition;
END;
$migration$;
