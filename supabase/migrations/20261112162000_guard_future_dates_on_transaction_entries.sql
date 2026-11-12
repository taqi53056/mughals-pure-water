CREATE OR REPLACE FUNCTION private.mpw_guard_no_future_transaction_date()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
DECLARE
  v_entry_date date;
  v_today date := (now() AT TIME ZONE 'Asia/Karachi')::date;
BEGIN
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;

  v_entry_date := NULLIF(to_jsonb(NEW)->>TG_ARGV[0], '')::date;
  IF v_entry_date IS NULL THEN
    RAISE EXCEPTION 'اندراج کی تاریخ لازمی ہے۔'
      USING ERRCODE = '22023';
  END IF;

  IF v_entry_date > v_today THEN
    RAISE EXCEPTION 'مستقبل کی تاریخ پر کاروباری اندراج محفوظ نہیں ہو سکتا۔ آج کی تاریخ: %', v_today
      USING ERRCODE = '22023';
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION private.mpw_guard_no_future_transaction_date() FROM PUBLIC, anon, authenticated;

DO $install$
DECLARE
  v_item record;
  v_table regclass;
BEGIN
  FOR v_item IN
    SELECT * FROM (VALUES
      ('business_capital_entries','entry_date'),
      ('business_expenses','expense_date'),
      ('business_finance_ledger','entry_date'),
      ('business_income','income_date'),
      ('counter_water_sales','sale_date'),
      ('customer_19l_deliveries','delivery_date'),
      ('customer_payments','payment_date'),
      ('daily_cleaning_labor','labor_date'),
      ('delivery_daily','delivery_date'),
      ('finished_stock_adjustments','adjustment_date'),
      ('labor_payments','payment_date'),
      ('product_returns','return_date'),
      ('product_sales','sale_date'),
      ('raw_material_purchases','purchase_date'),
      ('unassigned_19l_deliveries','delivery_date'),
      ('water_tanker_purchases','purchase_date'),
      ('worker_ledger','entry_date')
    ) AS x(table_name,date_column)
  LOOP
    v_table := to_regclass(format('public.%I', v_item.table_name));
    IF v_table IS NULL THEN
      RAISE EXCEPTION 'Required transaction table public.% does not exist; migration stopped.', v_item.table_name;
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM pg_attribute
      WHERE attrelid=v_table AND attname=v_item.date_column
        AND atttypid='date'::regtype AND attnum>0 AND NOT attisdropped
    ) THEN
      RAISE EXCEPTION 'Expected date column %.% is missing or not DATE; migration stopped.',
        v_item.table_name, v_item.date_column;
    END IF;

    EXECUTE format('DROP TRIGGER IF EXISTS a_mpw_no_future_date_guard ON %s', v_table);
    EXECUTE format(
      'CREATE TRIGGER a_mpw_no_future_date_guard BEFORE INSERT OR UPDATE ON %s FOR EACH ROW EXECUTE FUNCTION private.mpw_guard_no_future_transaction_date(%L)',
      v_table, v_item.date_column
    );
  END LOOP;
END;
$install$;