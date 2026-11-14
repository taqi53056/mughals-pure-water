DROP INDEX public.raw_material_one_opening_row_per_type;
CREATE UNIQUE INDEX raw_material_one_opening_row_per_type ON public.raw_material_purchases (material_type) WHERE record_type='opening_stock' AND quantity > 0;

DO $$
DECLARE
  v_definition text;
  v_old text := 'ON CONFLICT (material_type) WHERE record_type=''opening_stock''';
  v_new text := 'ON CONFLICT (material_type) WHERE record_type=''opening_stock'' AND quantity > 0';
  v_count integer;
BEGIN
  SELECT pg_get_functiondef('private.save_raw_material_purchase_atomic(jsonb,uuid,uuid)'::regprocedure) INTO v_definition;
  v_count := (length(v_definition) - length(replace(v_definition,v_old,''))) / length(v_old);
  IF v_count <> 2 THEN RAISE EXCEPTION 'Expected exactly two opening-stock conflict clauses; found %',v_count; END IF;
  v_definition := replace(v_definition,v_old,v_new);
  IF (length(v_definition) - length(replace(v_definition,v_new,''))) / length(v_new) <> 2 THEN RAISE EXCEPTION 'Opening-stock RPC rewrite verification failed'; END IF;
  EXECUTE v_definition;
END $$;
