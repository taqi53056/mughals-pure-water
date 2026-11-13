
-- Owner labor saving is calculated from filled bottles, not returned empties.
DO $migration$
DECLARE
  v_oid oid;
  v_def text;
  v_old text := 'p_empty_bottles_returned::numeric*20';
  v_new text := 'p_bottles_delivered::numeric*20';
BEGIN
  SELECT p.oid INTO v_oid
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public'
    AND p.proname='record_unassigned_19l_delivery'
    AND pg_get_function_identity_arguments(p.oid)=
      'p_delivery_date date, p_worker_id bigint, p_bottles_delivered integer, p_empty_bottles_returned integer, p_details text, p_request_id uuid, p_damaged_caps integer, p_performed_by_owner boolean'
  LIMIT 1;
  IF v_oid IS NULL THEN RAISE EXCEPTION 'Unassigned 19L delivery RPC not found'; END IF;
  v_def:=pg_get_functiondef(v_oid);
  IF position(v_old in v_def)>0 THEN
    v_def:=replace(v_def,v_old,v_new);
    EXECUTE v_def;
  ELSIF position(v_new in v_def)=0 THEN
    RAISE EXCEPTION 'Expected owner labor-saving expression not found';
  END IF;
END;
$migration$;
