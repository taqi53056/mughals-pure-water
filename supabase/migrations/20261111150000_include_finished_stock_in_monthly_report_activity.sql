-- Finished-goods opening balances and manual stock adjustments are reportable
-- activity even when no sale/production/expense was recorded in that month.
-- Preserve the existing report function, owner, ACLs and security attributes by
-- patching only its activity-detection UNION in the live function definition.

DO $migration$
DECLARE
  v_definition text;
  v_old text := $old$
    union all select 1 from public.water_opening_stock where as_of_date between p_month_start and p_month_end
    union all select 1 from public.business_finance_ledger where entry_date between p_month_start and p_month_end
$old$;
  v_new text := $new$
    union all select 1 from public.water_opening_stock where as_of_date between p_month_start and p_month_end
    union all select 1 from public.finished_goods where entry_date between p_month_start and p_month_end
    union all select 1 from public.finished_stock_adjustments where adjustment_date between p_month_start and p_month_end
    union all select 1 from public.business_finance_ledger where entry_date between p_month_start and p_month_end
$new$;
BEGIN
  SELECT pg_get_functiondef(
    'public.build_business_monthly_report(date,date)'::regprocedure
  )
  INTO v_definition;

  IF position(
    'union all select 1 from public.finished_goods where entry_date between p_month_start and p_month_end'
    IN v_definition
  ) > 0
  AND position(
    'union all select 1 from public.finished_stock_adjustments where adjustment_date between p_month_start and p_month_end'
    IN v_definition
  ) > 0 THEN
    RETURN;
  END IF;

  IF position(v_old IN v_definition) = 0 THEN
    RAISE EXCEPTION
      'Monthly report activity section changed; refusing an unsafe automatic patch.';
  END IF;

  EXECUTE replace(v_definition, v_old, v_new);
END;
$migration$;
