-- Serialize month close against every dated business entry.
-- The trigger and close RPC use the same per-month advisory transaction lock:
-- if an entry wins the lock, close includes it; if close wins, the entry is rejected.

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
  IF current_setting('mpw.archive_mode',true)='on' AND public.is_admin() THEN
    IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;

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
