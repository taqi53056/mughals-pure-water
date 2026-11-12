DO $migration$
DECLARE
  v_definition text;
  v_replacement text;
  v_count integer;
  v_guard_count integer;
BEGIN
  v_definition := pg_get_functiondef(
    'private.record_production_with_workers(date,text,integer,jsonb,uuid)'::regprocedure
  );

  v_replacement := $guard$IF FOUND THEN
      IF v_existing.production_date IS DISTINCT FROM p_production_date
         OR v_existing.product_type IS DISTINCT FROM p_product_type
         OR v_existing.quantity IS DISTINCT FROM p_quantity
         OR EXISTS (
           SELECT a.worker_id, a.cartons
           FROM public.production_worker_allocations a
           WHERE a.production_id = v_existing.id
           EXCEPT
           SELECT (e.value->>'worker_id')::bigint, (e.value->>'cartons')::integer
           FROM jsonb_array_elements(p_allocations) e(value)
         )
         OR EXISTS (
           SELECT (e.value->>'worker_id')::bigint, (e.value->>'cartons')::integer
           FROM jsonb_array_elements(p_allocations) e(value)
           EXCEPT
           SELECT a.worker_id, a.cartons
           FROM public.production_worker_allocations a
           WHERE a.production_id = v_existing.id
         ) THEN
        RAISE EXCEPTION 'یہ درخواست پہلے مختلف پروڈکشن یا مزدوروں کی تقسیم کے لیے استعمال ہو چکی ہے۔'
          USING ERRCODE='23505';
      END IF;$guard$;

  v_count := (length(v_definition) - length(replace(v_definition, 'IF FOUND THEN', '')))
             / length('IF FOUND THEN');
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'Expected exactly 2 idempotency guards; found %; migration stopped.', v_count;
  END IF;

  v_definition := replace(v_definition, 'IF FOUND THEN', v_replacement);
  v_guard_count := (length(v_definition) - length(replace(v_definition,
    'یہ درخواست پہلے مختلف پروڈکشن یا مزدوروں کی تقسیم کے لیے استعمال ہو چکی ہے۔', '')))
    / length('یہ درخواست پہلے مختلف پروڈکشن یا مزدوروں کی تقسیم کے لیے استعمال ہو چکی ہے۔');
  IF v_guard_count <> 2 THEN
    RAISE EXCEPTION 'Expected 2 installed mismatch checks; found %; migration stopped.', v_guard_count;
  END IF;

  EXECUTE v_definition;
END
$migration$;