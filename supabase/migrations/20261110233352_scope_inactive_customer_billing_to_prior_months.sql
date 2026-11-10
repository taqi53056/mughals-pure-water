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

  v_count integer := 0;
  v_message text;
BEGIN
  IF v_local_date <>
    (date_trunc('month', v_local_date::timestamp)
      + interval '1 month - 1 day')::date
  THEN
    RETURN 0;
  END IF;

  v_month := date_trunc('month', v_local_date::timestamp)::date;
  v_next := (v_month + interval '1 month')::date;

  FOR c IN
    SELECT customer.id, customer.name, customer.is_active
    FROM public.customers AS customer
    WHERE customer.is_active = true
       OR (
         customer.approved_at IS NOT NULL
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
          WHEN payment_type IN ('advance', 'bill_payment')
            THEN amount
          WHEN payment_type = 'refund'
            THEN -amount
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

    v_advance_used :=
      LEAST(v_prev_advance, v_prev_due + v_charges);

    v_due :=
      GREATEST(
        v_prev_due + v_charges - v_advance_used - v_paid,
        0
      );

    v_closing_advance :=
      GREATEST(
        v_prev_advance + v_paid - v_prev_due - v_charges,
        0
      );

    INSERT INTO public.customer_monthly_bills (
      customer_id,
      bill_month,
      bottles_19l,
      bottle_amount,
      damaged_caps,
      cap_amount,
      previous_balance,
      payments,
      advance_used,
      current_due,
      closing_advance
    )
    VALUES (
      c.id,
      v_month,
      v_bottles,
      v_bottle_amount,
      v_caps,
      v_cap_amount,
      v_prev_due,
      v_paid,
      v_advance_used,
      v_due,
      v_closing_advance
    )
    ON CONFLICT (customer_id, bill_month)
    DO UPDATE SET
      bottles_19l = EXCLUDED.bottles_19l,
      bottle_amount = EXCLUDED.bottle_amount,
      damaged_caps = EXCLUDED.damaged_caps,
      cap_amount = EXCLUDED.cap_amount,
      previous_balance = EXCLUDED.previous_balance,
      payments = EXCLUDED.payments,
      advance_used = EXCLUDED.advance_used,
      current_due = EXCLUDED.current_due,
      closing_advance = EXCLUDED.closing_advance;

    v_message := format(
      'السلام علیکم %s صاحب!

MUGHAL''S PURE WATER کا %s کا ماہانہ بل تیار ہے۔

19 لیٹر کی کامیاب بوتلیں: %s
بوتلوں کی رقم: Rs. %s

خراب ڈھکن: %s
ڈھکنوں کی رقم: Rs. %s

کل ماہانہ چارجز: Rs. %s
سابقہ بقایا: Rs. %s
سابقہ ایڈوانس: Rs. %s
استعمال شدہ ایڈوانس: Rs. %s

اس ماہ موصولہ ادائیگیاں: Rs. %s

اب قابلِ ادائیگی بقایا: Rs. %s
اختتامی ایڈوانس: Rs. %s

آپ کے اعتماد کا شکریہ۔
MUGHAL''S PURE WATER',
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
        customer_id,
        title,
        message,
        notification_type,
        reference_key
      )
      VALUES (
        c.id,
        'ماہانہ بل تیار ہے',
        v_message,
        'bill',
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
$function$
;

CREATE OR REPLACE FUNCTION private.close_business_month(p_month_start date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_start date;
  v_end date;
  v_today date := timezone('Asia/Karachi',now())::date;
  v_report jsonb;
  v_missing jsonb;
  v_negative text;
  v_unbilled integer;
  v_flags jsonb := '[]'::jsonb;
  v_existing public.business_month_closings%rowtype;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'صرف مستقل ایڈمن ماہانہ کلوزنگ کر سکتا ہے۔' using errcode='42501';
  end if;
  if p_month_start is null or p_month_start<>date_trunc('month',p_month_start)::date then
    raise exception 'ماہانہ کلوزنگ کے لیے مہینے کی پہلی تاریخ منتخب کریں۔' using errcode='22023';
  end if;

  v_start:=p_month_start;
  v_end:=(v_start + interval '1 month - 1 day')::date;

  if v_end>=date_trunc('month',v_today)::date then
    raise exception 'موجودہ یا آئندہ مہینہ بند نہیں کیا جا سکتا۔ پہلے مہینہ مکمل ہونے دیں۔' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('mpw-month-close-'||v_start::text,0));

  select * into v_existing from public.business_month_closings where month_start=v_start;
  if found then
    return jsonb_build_object('status','already_closed','month_start',v_start,'month_end',v_end,'closed_at',v_existing.closed_at,'report',v_existing.report);
  end if;

  select count(*) into v_unbilled
  from public.customers c
  where (
    c.is_active=true
    or (
      c.approved_at is not null
      and (
        exists (select 1 from public.customer_monthly_bills prior_bill where prior_bill.customer_id=c.id and prior_bill.bill_month<v_start)
        or exists (select 1 from public.customer_19l_deliveries d where d.customer_id=c.id and d.delivery_date between v_start and v_end)
        or exists (select 1 from public.customer_payments p where p.customer_id=c.id and p.payment_date between v_start and v_end)
      )
    )
  )
  and not exists (
    select 1 from public.customer_monthly_bills b
    where b.customer_id=c.id and b.bill_month=v_start
  );
  if v_unbilled>0 then
    raise exception 'ماہانہ بل مکمل نہیں بنے؛ % اہل گاہکوں کے بل باقی ہیں۔ پہلے بلنگ مکمل کریں۔',v_unbilled
      using errcode='55000';
  end if;

  v_report:=public.build_business_monthly_report(v_start,v_end);
  v_missing:=coalesce(v_report->'missing_costs','[]'::jsonb);
  if coalesce((v_report->>'complete')::boolean,false)=false or jsonb_array_length(v_missing)>0 then
    raise exception 'ماہانہ حساب نامکمل ہے؛ پہلے لاگت کی کمی درست کریں: %',v_missing
      using errcode='55000';
  end if;

  select string_agg(key,', ' order by key) into v_negative
  from jsonb_each_text(coalesce(v_report->'stock_estimate','{}'::jsonb))
  where value ~ '^-?[0-9]+(\.[0-9]+)?$' and value::numeric<0;

  if v_negative is not null then
    raise exception 'اسٹاک میں منفی مقدار موجود ہے؛ کلوزنگ سے پہلے درست کریں: %',v_negative
      using errcode='55000';
  end if;

  if coalesce((v_report->>'has_activity')::boolean,false)=false then
    v_flags:=v_flags||jsonb_build_array('اس مہینے کوئی کاروباری سرگرمی درج نہیں ہوئی۔');
  end if;
  if nullif(v_report->>'notes','') is not null then
    v_flags:=v_flags||jsonb_build_array(v_report->>'notes');
  end if;

  insert into public.business_monthly_report_snapshots(month_start,month_end,report,generated_at)
  values(v_start,v_end,v_report,now())
  on conflict(month_start) do update
    set month_end=excluded.month_end,report=excluded.report,generated_at=excluded.generated_at;

  insert into public.business_month_closings(month_start,month_end,status,report,quality_flags,closed_by)
  values(v_start,v_end,'closed',v_report,v_flags,auth.uid());

  insert into public.audit_log(table_name,record_id,action,old_data,new_data,changed_by)
  values('business_month_closings',v_start::text,'MONTH_CLOSED',null,
    jsonb_build_object('month_start',v_start,'month_end',v_end,'quality_flags',v_flags),auth.uid());

  return jsonb_build_object('status','closed','month_start',v_start,'month_end',v_end,'quality_flags',v_flags,'report',v_report);
end;
$function$
;
