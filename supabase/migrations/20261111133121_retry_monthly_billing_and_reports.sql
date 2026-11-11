-- Retry customer month-end billing daily until every eligible account has a bill.
-- On the actual last day, bill the current month; on other days, catch up the
-- previous month. Existing bills are skipped, making retries idempotent.
CREATE OR REPLACE FUNCTION public.generate_month_end_customer_bills()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_local_date date := timezone('Asia/Karachi', now())::date;
  v_month date;
  v_next date;
  c record;
  v_bottles integer;
  v_caps integer;
  v_prev_due numeric(12,2);
  v_prev_advance numeric(12,2);
  v_paid numeric(12,2);
  v_bottle_amount numeric(12,2);
  v_cap_amount numeric(12,2);
  v_charges numeric(12,2);
  v_advance_used numeric(12,2);
  v_due numeric(12,2);
  v_closing_advance numeric(12,2);
  v_bill_id bigint;
  v_count integer := 0;
  v_message text;
BEGIN
  IF v_local_date =
     (date_trunc('month', v_local_date::timestamp)
       + interval '1 month - 1 day')::date
  THEN
    v_month := date_trunc('month', v_local_date::timestamp)::date;
  ELSE
    v_month := (date_trunc('month', v_local_date::timestamp)
      - interval '1 month')::date;
  END IF;
  v_next := (v_month + interval '1 month')::date;

  FOR c IN
    SELECT customer.id, customer.name, customer.is_active
    FROM public.customers AS customer
    WHERE (
      (
        customer.is_active = true
        AND coalesce(customer.approved_at, customer.created_at)
          < (v_next::timestamp AT TIME ZONE 'Asia/Karachi')
      )
      OR
      (
        customer.approved_at IS NOT NULL
        AND customer.approved_at < (v_next::timestamp AT TIME ZONE 'Asia/Karachi')
        AND (
          EXISTS (
            SELECT 1 FROM public.customer_monthly_bills AS prior_bill
            WHERE prior_bill.customer_id = customer.id
              AND prior_bill.bill_month < v_month
          )
          OR EXISTS (
            SELECT 1 FROM public.customer_monthly_bills AS current_bill
            WHERE current_bill.customer_id = customer.id
              AND current_bill.bill_month = v_month
          )
          OR EXISTS (
            SELECT 1 FROM public.customer_19l_deliveries AS delivery
            WHERE delivery.customer_id = customer.id
              AND delivery.delivery_date >= v_month
              AND delivery.delivery_date < v_next
          )
          OR EXISTS (
            SELECT 1 FROM public.customer_payments AS payment
            WHERE payment.customer_id = customer.id
              AND payment.payment_date >= v_month
              AND payment.payment_date < v_next
          )
        )
      )
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.customer_monthly_bills AS existing_bill
      WHERE existing_bill.customer_id = customer.id
        AND existing_bill.bill_month = v_month
    )
  LOOP
    v_prev_due := 0;
    v_prev_advance := 0;
    v_paid := 0;

    SELECT
      COALESCE(SUM(successful_bottles), 0),
      COALESCE(SUM(damaged_caps), 0)
    INTO v_bottles, v_caps
    FROM public.customer_19l_deliveries
    WHERE customer_id = c.id
      AND delivery_date >= v_month
      AND delivery_date < v_next;

    SELECT
      COALESCE(current_due, 0),
      COALESCE(closing_advance, 0)
    INTO v_prev_due, v_prev_advance
    FROM public.customer_monthly_bills
    WHERE customer_id = c.id
      AND bill_month < v_month
    ORDER BY bill_month DESC
    LIMIT 1;

    v_prev_due := COALESCE(v_prev_due, 0);
    v_prev_advance := COALESCE(v_prev_advance, 0);

    SELECT COALESCE(
      SUM(
        CASE
          WHEN payment_type IN ('advance', 'bill_payment') THEN amount
          WHEN payment_type = 'refund' THEN -amount
          ELSE 0
        END
      ), 0
    )
    INTO v_paid
    FROM public.customer_payments
    WHERE customer_id = c.id
      AND payment_date >= v_month
      AND payment_date < v_next;

    v_bottle_amount := v_bottles * 100;
    v_cap_amount := v_caps * 10;
    v_charges := v_bottle_amount + v_cap_amount;
    v_advance_used := LEAST(v_prev_advance, v_prev_due + v_charges);
    v_due := GREATEST(
      v_prev_due + v_charges - v_prev_advance - v_paid,
      0
    );
    v_closing_advance := GREATEST(
      v_prev_advance + v_paid - v_prev_due - v_charges,
      0
    );

    INSERT INTO public.customer_monthly_bills (
      customer_id, bill_month, bottles_19l, bottle_amount, damaged_caps,
      cap_amount, previous_balance, payments, advance_used, current_due,
      closing_advance
    )
    VALUES (
      c.id, v_month, v_bottles, v_bottle_amount, v_caps, v_cap_amount,
      v_prev_due, v_paid, v_advance_used, v_due, v_closing_advance
    )
    ON CONFLICT (customer_id, bill_month) DO NOTHING
    RETURNING id INTO v_bill_id;

    IF NOT FOUND THEN
      CONTINUE;
    END IF;

    v_message := format(
      'السلام علیکم %s صاحب!\n\nMUGHAL''S PURE WATER کا %s کا ماہانہ بل تیار ہے۔\n\n19 لیٹر کی کامیاب بوتلیں: %s\nبوتلوں کی رقم: Rs. %s\n\nخراب ڈھکن: %s\nڈھکنوں کی رقم: Rs. %s\n\nکل ماہانہ چارجز: Rs. %s\nسابقہ بقایا: Rs. %s\nسابقہ ایڈوانس: Rs. %s\nاستعمال شدہ ایڈوانس: Rs. %s\n\nاس ماہ موصولہ ادائیگیاں: Rs. %s\n\nاب قابلِ ادائیگی بقایا: Rs. %s\nاختتامی ایڈوانس: Rs. %s\n\nآپ کے اعتماد کا شکریہ۔\nMUGHAL''S PURE WATER',
      COALESCE(c.name, 'محترم کسٹمر'),
      to_char(v_month, 'YYYY-MM'),
      v_bottles,
      to_char(v_bottle_amount, 'FM999999990.00'),
      v_caps,
      to_char(v_cap_amount, 'FM999999990.00'),
      to_char(v_charges, 'FM999999990.00'),
      to_char(v_prev_due, 'FM999999990.00'),
      to_char(v_prev_advance, 'FM999999990.00'),
      to_char(v_advance_used, 'FM999999990.00'),
      to_char(v_paid, 'FM999999990.00'),
      to_char(v_due, 'FM999999990.00'),
      to_char(v_closing_advance, 'FM999999990.00')
    );

    IF c.is_active = true THEN
      INSERT INTO public.customer_notifications (
        customer_id, title, message, notification_type, reference_key
      )
      VALUES (
        c.id, 'ماہانہ بل تیار ہے', v_message, 'bill',
        'bill:' || to_char(v_month, 'YYYY-MM')
      )
      ON CONFLICT (customer_id, reference_key)
        WHERE reference_key IS NOT NULL
      DO UPDATE SET
        message = EXCLUDED.message,
        title = EXCLUDED.title,
        created_at = now(),
        is_read = false;
    END IF;

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$function$;

-- Refresh the previous month's snapshot daily until it is formally closed.
CREATE OR REPLACE FUNCTION public.capture_monthly_business_report()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_today date := timezone('Asia/Karachi', now())::date;
  v_month_start date;
  v_month_end date;
  v_report jsonb;
BEGIN
  v_month_start :=
    (date_trunc('month', v_today::timestamp)::date - interval '1 month')::date;
  v_month_end :=
    (date_trunc('month', v_today::timestamp)::date - interval '1 day')::date;

  IF EXISTS (
    SELECT 1
    FROM public.business_month_closings
    WHERE month_start = v_month_start
      AND status = 'closed'
  ) THEN
    RETURN;
  END IF;

  v_report := public.build_business_monthly_report(v_month_start, v_month_end);

  INSERT INTO public.business_monthly_report_snapshots (
    month_start, month_end, report, generated_at
  )
  VALUES (v_month_start, v_month_end, v_report, now())
  ON CONFLICT (month_start)
  DO UPDATE SET
    month_end = EXCLUDED.month_end,
    report = EXCLUDED.report,
    generated_at = EXCLUDED.generated_at;
END;
$function$;

DO $migration$
DECLARE
  v_billing_job_id bigint;
  v_report_job_id bigint;
BEGIN
  SELECT jobid INTO STRICT v_billing_job_id
  FROM cron.job
  WHERE jobname = 'mughal-month-end-billing';

  SELECT jobid INTO STRICT v_report_job_id
  FROM cron.job
  WHERE jobname = 'mughal-monthly-business-report';

  PERFORM cron.alter_job(v_billing_job_id, schedule => '55 18 * * *');
  PERFORM cron.alter_job(v_report_job_id, schedule => '5 19 * * *');
END;
$migration$;
