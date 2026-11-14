DO $$
DECLARE
  v_definition text;
BEGIN
  SELECT pg_get_functiondef('private.prepare_customer_archive(bigint)'::regprocedure)
    INTO v_definition;

  v_definition := replace(v_definition, '  r record;', '  v_entered_by_table record;');
  v_definition := replace(v_definition,
    'FROM public.customer_19l_bottle_returns r WHERE r.customer_id=p_customer_id',
    'FROM public.customer_19l_bottle_returns ret WHERE ret.customer_id=p_customer_id');
  v_definition := replace(v_definition, 'r.return_date', 'ret.return_date');
  v_definition := replace(v_definition, 'FOR r IN SELECT table_name', 'FOR v_entered_by_table IN SELECT table_name');
  v_definition := replace(v_definition, 'r.table_name', 'v_entered_by_table.table_name');

  IF position('customer_19l_bottle_returns r WHERE r.customer_id' in v_definition) > 0
     OR position('r.return_date' in v_definition) > 0
     OR position('FOR r IN SELECT table_name' in v_definition) > 0
     OR position('v_entered_by_table' in v_definition) = 0
     OR position('ret.return_date' in v_definition) = 0 THEN
    RAISE EXCEPTION 'Archive function rewrite verification failed; migration aborted.';
  END IF;

  EXECUTE v_definition;
END $$;