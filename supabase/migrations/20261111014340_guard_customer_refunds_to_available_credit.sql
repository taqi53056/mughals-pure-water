-- Prevent customer refunds from exceeding credit actually available on the refund date.
-- The calculation uses the previous month's closing balance plus payments and
-- delivery charges recorded up to the refund date. It excludes the row being
-- edited, and serializes refunds for the same customer to prevent double refunds.

CREATE OR REPLACE FUNCTION private.mpw_guard_customer_refund_credit()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
DECLARE
  v_month_start date;
  v_exclude_payment_id bigint;
  v_previous_due numeric(12,2) := 0;
  v_previous_advance numeric(12,2) := 0;
  v_month_charges numeric(12,2) := 0;
  v_month_net_payments numeric(12,2) := 0;
  v_available_credit numeric(12,2) := 0;
BEGIN
  IF NEW.payment_type IS DISTINCT FROM 'refund' THEN
    RETURN NEW;
  END IF;

  IF NEW.customer_id IS NULL OR NEW.payment_date IS NULL
     OR NEW.amount IS NULL OR NEW.amount <= 0 THEN
    RAISE EXCEPTION 'ریفنڈ کے لیے گاہک، تاریخ اور مثبت رقم ضروری ہے۔'
      USING ERRCODE = '22023';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended('customer-refund:' || NEW.customer_id::text, 0)
  );

  v_month_start := date_trunc('month', NEW.payment_date::timestamp)::date;

  IF TG_OP = 'UPDATE' THEN
    v_exclude_payment_id := OLD.id;
  END IF;

  SELECT
    COALESCE(b.current_due, 0),
    COALESCE(b.closing_advance, 0)
  INTO v_previous_due, v_previous_advance
  FROM public.customer_monthly_bills AS b
  WHERE b.customer_id = NEW.customer_id
    AND b.bill_month < v_month_start
  ORDER BY b.bill_month DESC
  LIMIT 1;

  v_previous_due := COALESCE(v_previous_due, 0);
  v_previous_advance := COALESCE(v_previous_advance, 0);

  SELECT COALESCE(
    SUM(d.successful_bottles::numeric * 100
      + d.damaged_caps::numeric * 10),
    0
  )
  INTO v_month_charges
  FROM public.customer_19l_deliveries AS d
  WHERE d.customer_id = NEW.customer_id
    AND d.delivery_date >= v_month_start
    AND d.delivery_date <= NEW.payment_date;

  SELECT COALESCE(
    SUM(
      CASE
        WHEN p.payment_type IN ('advance', 'bill_payment') THEN p.amount
        WHEN p.payment_type = 'refund' THEN -p.amount
        ELSE 0
      END
    ),
    0
  )
  INTO v_month_net_payments
  FROM public.customer_payments AS p
  WHERE p.customer_id = NEW.customer_id
    AND p.payment_date >= v_month_start
    AND p.payment_date <= NEW.payment_date
    AND (v_exclude_payment_id IS NULL OR p.id <> v_exclude_payment_id);

  v_available_credit := GREATEST(
    v_previous_advance
      + v_month_net_payments
      - v_previous_due
      - v_month_charges,
    0
  );

  IF NEW.amount > v_available_credit THEN
    RAISE EXCEPTION
      'ریفنڈ محفوظ نہیں ہوا۔ دستیاب ایڈوانس/کریڈٹ: Rs. %، مطلوبہ ریفنڈ: Rs. %',
      to_char(v_available_credit, 'FM999999990.00'),
      to_char(NEW.amount, 'FM999999990.00')
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION private.mpw_guard_customer_refund_credit()
  FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS mpw_guard_customer_refund_credit
  ON public.customer_payments;

CREATE TRIGGER mpw_guard_customer_refund_credit
BEFORE INSERT OR UPDATE OF customer_id, payment_date, amount, payment_type
ON public.customer_payments
FOR EACH ROW
EXECUTE FUNCTION private.mpw_guard_customer_refund_credit();
