
ALTER TABLE public.customer_19l_deliveries
  DROP CONSTRAINT IF EXISTS customer_19l_delivery_exchange_invariants_check;

ALTER TABLE public.customer_19l_deliveries
  ADD CONSTRAINT customer_19l_delivery_exchange_invariants_check
  CHECK (
    bottles_delivered > 0
    AND empty_bottles_returned >= 0
    AND successful_bottles = bottles_delivered
    AND bottle_difference = GREATEST(
      bottles_delivered - customer_owned_bottles - empty_bottles_returned, 0
    )
    AND damaged_caps >= 0
    AND delivery_labor >= 0
  );

CREATE OR REPLACE FUNCTION public.guard_customer_19l_bottle_custody()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
DECLARE
  v_customer_id bigint;
  v_negative_date date;
BEGIN
  IF TG_OP='UPDATE' AND NEW.customer_id IS DISTINCT FROM OLD.customer_id THEN
    RAISE EXCEPTION 'محفوظ ڈلیوری کو دوسرے گاہک کے اکاؤنٹ میں منتقل نہیں کیا جا سکتا۔'
      USING ERRCODE='22023';
  END IF;

  v_customer_id:=NEW.customer_id;
  PERFORM pg_advisory_xact_lock(
    hashtextextended('mpw-customer-bottle-custody-'||v_customer_id::text,0)
  );

  WITH movements AS (
    SELECT d.delivery_date,
           SUM(d.bottles_delivered-d.customer_owned_bottles)::bigint AS company_in,
           SUM(d.empty_bottles_returned)::bigint AS company_out
    FROM public.customer_19l_deliveries d
    WHERE d.customer_id=v_customer_id
      AND (TG_OP<>'UPDATE' OR d.id IS DISTINCT FROM OLD.id)
    GROUP BY d.delivery_date
    UNION ALL
    SELECT NEW.delivery_date,
           NEW.bottles_delivered-NEW.customer_owned_bottles,
           NEW.empty_bottles_returned
  ),
  daily AS (
    SELECT delivery_date,SUM(company_in) company_in,SUM(company_out) company_out
    FROM movements GROUP BY delivery_date
  ),
  running AS (
    SELECT delivery_date,
      SUM(company_in-company_out) OVER (
        ORDER BY delivery_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      ) outstanding
    FROM daily
  )
  SELECT delivery_date INTO v_negative_date
  FROM running WHERE outstanding<0 ORDER BY delivery_date LIMIT 1;

  IF v_negative_date IS NOT NULL THEN
    RAISE EXCEPTION 'کمپنی کی واپس آنے والی خالی بوتلیں، پہلے دی گئی کمپنی بوتلوں سے زیادہ ہیں۔ تاریخ: %',v_negative_date
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS mpw_customer_19l_bottle_custody_guard
  ON public.customer_19l_deliveries;
CREATE TRIGGER mpw_customer_19l_bottle_custody_guard
BEFORE INSERT OR UPDATE ON public.customer_19l_deliveries
FOR EACH ROW EXECUTE FUNCTION public.guard_customer_19l_bottle_custody();
