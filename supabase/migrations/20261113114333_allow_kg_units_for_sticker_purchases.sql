
-- Allow kg-based sticker purchases while keeping all other raw-material quantities integral.
ALTER TABLE public.raw_material_purchases
  DROP CONSTRAINT IF EXISTS raw_material_purchase_unit_matches_type,
  DROP CONSTRAINT IF EXISTS raw_material_purchases_material_type_check,
  DROP CONSTRAINT IF EXISTS raw_material_purchases_quantity_integer_check,
  DROP CONSTRAINT IF EXISTS raw_material_purchases_unit_check;

ALTER TABLE public.raw_material_purchases
  ADD CONSTRAINT raw_material_purchases_material_type_check
    CHECK (material_type = ANY (ARRAY[
      'bottle_500ml','bottle_1_5l','bottle_6l',
      'cap_500ml','cap_1_5l','cap_6l','cap_19l',
      'carton_500ml','carton_1_5l','tape_bundle','sticker',
      'sticker_500ml','sticker_1_5l_6l'
    ])),
  ADD CONSTRAINT raw_material_purchases_unit_check
    CHECK (unit = ANY (ARRAY['bottle','carton','bundle','piece','kg'])),
  ADD CONSTRAINT raw_material_purchase_unit_matches_type
    CHECK (
      (material_type = ANY (ARRAY['bottle_500ml','bottle_1_5l','bottle_6l']) AND unit='bottle')
      OR (material_type = ANY (ARRAY['cap_500ml','cap_1_5l','cap_6l','cap_19l','sticker']) AND unit='piece')
      OR (material_type = ANY (ARRAY['sticker_500ml','sticker_1_5l_6l']) AND unit='kg')
      OR (material_type = ANY (ARRAY['carton_500ml','carton_1_5l']) AND unit='carton')
      OR (material_type='tape_bundle' AND unit='bundle')
    ),
  ADD CONSTRAINT raw_material_purchases_quantity_precision_check
    CHECK (
      (material_type = ANY (ARRAY['sticker_500ml','sticker_1_5l_6l']) AND quantity=round(quantity,3))
      OR (material_type <> ALL (ARRAY['sticker_500ml','sticker_1_5l_6l']) AND quantity=trunc(quantity))
    );

DO $migration$
DECLARE v_def text; v_old text; v_new text;
BEGIN
  v_def:=pg_get_functiondef('public.save_raw_material_purchase_atomic(jsonb,uuid,uuid)'::regprocedure);
  v_old:=$old$     OR (v_type IN ('sticker_500ml','sticker_1_5l_6l') AND v_quantity > 100000)
     OR v_amount IS NULL$old$;
  v_new:=$new$     OR (v_type IN ('sticker_500ml','sticker_1_5l_6l') AND (v_quantity > 100000 OR v_quantity<>round(v_quantity,3)))
     OR v_amount IS NULL$new$;
  IF position(v_new in v_def)=0 THEN
    IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'Sticker kg precision validation anchor missing'; END IF;
    v_def:=replace(v_def,v_old,v_new);
  END IF;
  EXECUTE v_def;
END;
$migration$;
