-- The generic legacy sticker counter no longer represents inventory after
-- sticker stock was split into 500ml and shared 1.5L/6L units.
DO $migration$
DECLARE
  v_definition text;
  v_start integer;
  v_next integer;
BEGIN
  SELECT pg_get_functiondef('public.build_business_monthly_report(date,date)'::regprocedure)
    INTO v_definition;
  v_start := position($marker$'stickers',coalesce$marker$ in v_definition);
  v_next := position($marker$'stickers_500ml'$marker$ in v_definition);
  IF v_start=0 OR v_next=0 OR v_next<=v_start THEN
    RAISE EXCEPTION 'Expected sticker stock keys were not found; no change applied';
  END IF;
  v_definition := left(v_definition,v_start-1)
    || $replacement$'stickers',null,
    $replacement$
    || substring(v_definition from v_next);
  EXECUTE v_definition;
END
$migration$;
