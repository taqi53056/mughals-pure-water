-- Keep archive operations serialized with month close and prevent deletion
-- of customer activity that has not yet been captured in a closed-month snapshot.

CREATE OR REPLACE FUNCTION private.mpw_guard_closed_period()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_date date;
  v_old_date date;
  v_new_month date;
  v_old_month date;
  v_lock_month date;
BEGIN
  IF TG_OP IN ('INSERT','UPDATE') THEN
    v_date := nullif(to_jsonb(NEW)->>TG_ARGV[0],'')::date;
    IF v_date IS NOT NULL THEN
      v_new_month := date_trunc('month',v_date)::date;
    END IF;
  END IF;

  IF TG_OP IN ('UPDATE','DELETE') THEN
    v_old_date := nullif(to_jsonb(OLD)->>TG_ARGV[0],'')::date;
    IF v_old_date IS NOT NULL THEN
      v_old_month := date_trunc('month',v_old_date)::date;
    END IF;
  END IF;

  IF v_new_month IS NOT NULL AND v_old_month IS NOT NULL
     AND v_new_month IS DISTINCT FROM v_old_month THEN
    FOR v_lock_month IN
      SELECT month_start
      FROM (VALUES (v_new_month),(v_old_month)) AS months(month_start)
      ORDER BY month_start
    LOOP
      PERFORM pg_advisory_xact_lock(
        hashtextextended('mpw-month-close-'||v_lock_month::text,0)
      );
    END LOOP;
  ELSIF v_new_month IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(
      hashtextextended('mpw-month-close-'||v_new_month::text,0)
    );
  ELSIF v_old_month IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(
      hashtextextended('mpw-month-close-'||v_old_month::text,0)
    );
  END IF;

  -- Archive mode may bypass closed-period rejection, but never the lock.
  IF current_setting('mpw.archive_mode',true)='on' AND public.is_admin() THEN
    IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;

  IF v_new_month IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.business_month_closings c
    WHERE c.month_start=v_new_month AND c.status='closed'
  ) THEN
    RAISE EXCEPTION 'یہ مہینہ بند ہو چکا ہے؛ پرانے ریکارڈ میں تبدیلی کی اجازت نہیں۔ موجودہ مہینے میں اصلاحی اندراج کریں۔'
      USING ERRCODE='55000';
  END IF;

  IF v_old_month IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.business_month_closings c
    WHERE c.month_start=v_old_month AND c.status='closed'
  ) THEN
    RAISE EXCEPTION 'بند مہینے کا اصل ریکارڈ تبدیل یا حذف نہیں کیا جا سکتا۔'
      USING ERRCODE='55000';
  END IF;

  IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION private.prepare_customer_archive(p_customer_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_customer public.customers%rowtype;
  v_auth_user_id uuid;
  v_bottles bigint:=0;
  v_caps bigint:=0;
  v_owner_saving numeric(14,2):=0;
  v_billed numeric(14,2):=0;
  v_paid numeric(14,2):=0;
  v_refunds numeric(14,2):=0;
  v_due numeric(14,2):=0;
  v_advance numeric(14,2):=0;
  v_archive_id bigint;
  v_archive_ref text;
  v_job_id bigint;
  v_current_month date;
  v_lock_month date;
  r record;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'صرف مستقل ایڈمن کسٹمر آرکائیو کر سکتا ہے۔' USING ERRCODE='42501';
  END IF;
  IF p_customer_id IS NULL THEN
    RAISE EXCEPTION 'کسٹمر منتخب کرنا ضروری ہے۔' USING ERRCODE='22023';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended('mpw-customer-archive-'||p_customer_id::text,0)
  );

  -- Acquire month locks before the customer row lock. Business-entry triggers
  -- take month locks before FK checks, so this preserves a consistent lock order.
  v_current_month := date_trunc('month',timezone('Asia/Karachi',now())::date)::date;
  FOR v_lock_month IN
    SELECT month_start
    FROM (
      SELECT v_current_month AS month_start
      UNION
      SELECT date_trunc('month',d.delivery_date)::date
        FROM public.customer_19l_deliveries d WHERE d.customer_id=p_customer_id
      UNION
      SELECT date_trunc('month',p.payment_date)::date
        FROM public.customer_payments p WHERE p.customer_id=p_customer_id
      UNION
      SELECT date_trunc('month',b.bill_month)::date
        FROM public.customer_monthly_bills b WHERE b.customer_id=p_customer_id
    ) AS months
    ORDER BY month_start
  LOOP
    PERFORM pg_advisory_xact_lock(
      hashtextextended('mpw-month-close-'||v_lock_month::text,0)
    );
  END LOOP;

  SELECT * INTO v_customer
  FROM public.customers
  WHERE id=p_customer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'یہ کسٹمر موجود نہیں یا پہلے ہی آرکائیو ہو چکا ہے۔' USING ERRCODE='P0002';
  END IF;
  v_auth_user_id := v_customer.auth_user_id;

  -- Do not delete records from any month whose business snapshot is still open.
  IF EXISTS (
    SELECT 1
    FROM (
      SELECT date_trunc('month',d.delivery_date)::date AS month_start
        FROM public.customer_19l_deliveries d WHERE d.customer_id=p_customer_id
      UNION
      SELECT date_trunc('month',p.payment_date)::date
        FROM public.customer_payments p WHERE p.customer_id=p_customer_id
      UNION
      SELECT date_trunc('month',b.bill_month)::date
        FROM public.customer_monthly_bills b WHERE b.customer_id=p_customer_id
    ) AS activity
    WHERE NOT EXISTS (
      SELECT 1 FROM public.business_month_closings c
      WHERE c.month_start=activity.month_start AND c.status='closed'
    )
  ) THEN
    RAISE EXCEPTION 'کسٹمر آرکائیو سے پہلے اس کے تمام متعلقہ کاروباری مہینوں کی کلوزنگ مکمل کریں؛ کھلے مہینے کا ریکارڈ حذف نہیں کیا جا سکتا۔'
      USING ERRCODE='55000';
  END IF;

  SELECT
    coalesce(sum(successful_bottles),0),
    coalesce(sum(damaged_caps),0),
    coalesce(sum(owner_labor_saving),0)
  INTO v_bottles,v_caps,v_owner_saving
  FROM public.customer_19l_deliveries
  WHERE customer_id=p_customer_id;

  SELECT coalesce(sum(bottle_amount+cap_amount),0)
    INTO v_billed
  FROM public.customer_monthly_bills
  WHERE customer_id=p_customer_id;

  IF NOT EXISTS (
    SELECT 1 FROM public.customer_monthly_bills WHERE customer_id=p_customer_id
  ) THEN
    v_billed := v_bottles*100+v_caps*10;
  END IF;

  SELECT
    coalesce(sum(amount) filter(where payment_type in ('bill_payment','advance')),0),
    coalesce(sum(amount) filter(where payment_type='refund'),0)
  INTO v_paid,v_refunds
  FROM public.customer_payments
  WHERE customer_id=p_customer_id;

  SELECT coalesce(current_due,0),coalesce(closing_advance,0)
    INTO v_due,v_advance
  FROM public.customer_monthly_bills
  WHERE customer_id=p_customer_id
  ORDER BY bill_month DESC
  LIMIT 1;

  INSERT INTO public.customer_archive_summaries(
    total_19l_bottles,damaged_caps,billed_amount,payments_received,refunds,net_collected,
    final_due,final_advance,owner_labor_saving,lifetime_profit,profit_note,summary
  ) VALUES (
    v_bottles,v_caps,v_billed,v_paid,v_refunds,v_paid-v_refunds,
    v_due,v_advance,v_owner_saving,null,
    'کسٹمر کی اصل لاگت الگ مختص نہیں؛ اس لیے لائف ٹائم منافع کا اندازہ نہیں لگایا گیا۔',
    jsonb_build_object(
      'total_19l_bottles',v_bottles,'damaged_caps',v_caps,'billed_amount',v_billed,
      'payments_received',v_paid,'refunds',v_refunds,'net_collected',v_paid-v_refunds,
      'final_due',v_due,'final_advance',v_advance,'owner_labor_saving',v_owner_saving,
      'profit_calculated',false
    )
  ) RETURNING id INTO v_archive_id;

  v_archive_ref := 'ARCH-'||to_char(timezone('Asia/Karachi',now()),'YYYYMMDD')||'-'||lpad(v_archive_id::text,6,'0');
  UPDATE public.customer_archive_summaries
  SET archive_ref=v_archive_ref
  WHERE id=v_archive_id;

  INSERT INTO public.customer_archive_jobs(archive_id,auth_user_id,status,completed_at)
  VALUES(
    v_archive_id,v_auth_user_id,
    case when v_auth_user_id is null then 'completed' else 'pending_auth_deletion' end,
    case when v_auth_user_id is null then now() else null end
  )
  RETURNING id INTO v_job_id;

  PERFORM set_config('mpw.archive_mode','on',true);

  DELETE FROM public.delivery_daily WHERE customer_id=p_customer_id;
  DELETE FROM public.customer_19l_deliveries WHERE customer_id=p_customer_id;
  DELETE FROM public.customer_payments WHERE customer_id=p_customer_id;
  DELETE FROM public.customer_monthly_bills WHERE customer_id=p_customer_id;
  DELETE FROM public.customer_notifications WHERE customer_id=p_customer_id;
  DELETE FROM public.customer_push_subscriptions WHERE customer_id=p_customer_id;
  DELETE FROM public.customer_complaints WHERE customer_id=p_customer_id;
  DELETE FROM public.customers WHERE id=p_customer_id;

  DELETE FROM public.audit_log
  WHERE (table_name='customers' AND record_id=p_customer_id::text)
     OR old_data->>'customer_id'=p_customer_id::text
     OR new_data->>'customer_id'=p_customer_id::text;

  IF v_auth_user_id IS NOT NULL THEN
    FOR r IN
      SELECT table_name
      FROM information_schema.columns
      WHERE table_schema='public' AND column_name='entered_by' AND is_nullable='YES'
    LOOP
      EXECUTE format('UPDATE public.%I SET entered_by=NULL WHERE entered_by=$1',r.table_name)
      USING v_auth_user_id;
    END LOOP;
    UPDATE public.audit_log SET changed_by=NULL WHERE changed_by=v_auth_user_id;
  END IF;

  INSERT INTO public.audit_log(table_name,record_id,action,old_data,new_data,changed_by)
  VALUES(
    'customer_archive_summaries',v_archive_id::text,'CUSTOMER_ARCHIVED',NULL,
    jsonb_build_object('archive_ref',v_archive_ref,'personal_data_removed',true,'auth_user_pending_deletion',v_auth_user_id IS NOT NULL),
    auth.uid()
  );

  RETURN jsonb_build_object(
    'job_id',v_job_id,'archive_id',v_archive_id,'archive_ref',v_archive_ref,
    'auth_user_id',v_auth_user_id,
    'status',case when v_auth_user_id is null then 'completed' else 'pending_auth_deletion' end
  );
END;
$function$;
