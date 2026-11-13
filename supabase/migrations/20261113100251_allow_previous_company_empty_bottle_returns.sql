
ALTER TABLE public.unassigned_19l_deliveries
  DROP CONSTRAINT IF EXISTS unassigned_19l_deliveries_check;
ALTER TABLE public.unassigned_19l_deliveries
  ADD CONSTRAINT unassigned_19l_deliveries_check
  CHECK (empty_bottles_returned >= 0);

CREATE OR REPLACE FUNCTION private.guard_unassigned_19l_bottle_custody()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
DECLARE
  v_negative_date date;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('mpw-unassigned-bottle-custody',0));
  WITH movements AS (
    SELECT d.delivery_date,
      SUM(d.bottles_delivered)::bigint AS company_in,
      SUM(d.empty_bottles_returned)::bigint AS company_out
    FROM public.unassigned_19l_deliveries d
    WHERE TG_OP<>'UPDATE' OR d.id IS DISTINCT FROM OLD.id
    GROUP BY d.delivery_date
    UNION ALL
    SELECT NEW.delivery_date,NEW.bottles_delivered,NEW.empty_bottles_returned
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
    RAISE EXCEPTION 'غیر منسلک سپلائی میں واپس آنے والی کمپنی خالی بوتلیں، پہلے دی گئی کمپنی بوتلوں سے زیادہ ہیں۔ تاریخ: %',v_negative_date
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS mpw_unassigned_19l_bottle_custody_guard
  ON public.unassigned_19l_deliveries;
CREATE TRIGGER mpw_unassigned_19l_bottle_custody_guard
BEFORE INSERT OR UPDATE ON public.unassigned_19l_deliveries
FOR EACH ROW EXECUTE FUNCTION private.guard_unassigned_19l_bottle_custody();

DO $migration$
DECLARE
  v_oid oid;
  v_def text;
  v_old text := 'if coalesce(p_empty_bottles_returned,0)<0 or coalesce(p_empty_bottles_returned,0)>p_bottles_delivered then raise exception ''واپس آنے والی خالی بوتلوں کی تعداد درست درج کریں۔'' using errcode=''22023''; end if;';
  v_new text := 'if coalesce(p_empty_bottles_returned,0)<0 then raise exception ''واپس آنے والی خالی بوتلوں کی تعداد منفی نہیں ہو سکتی۔'' using errcode=''22023''; end if;';
BEGIN
  SELECT p.oid INTO v_oid
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='record_unassigned_19l_delivery'
    AND pg_get_function_identity_arguments(p.oid)=
      'p_delivery_date date, p_worker_id bigint, p_bottles_delivered integer, p_empty_bottles_returned integer, p_details text, p_request_id uuid, p_damaged_caps integer, p_performed_by_owner boolean'
  LIMIT 1;
  IF v_oid IS NULL THEN RAISE EXCEPTION 'Unassigned delivery function signature not found'; END IF;
  v_def:=pg_get_functiondef(v_oid);
  IF position(v_old in v_def)=0 THEN
    IF position('if coalesce(p_empty_bottles_returned,0)<0 then' in v_def)=0 THEN
      RAISE EXCEPTION 'Expected empty-bottle validation not found';
    END IF;
  ELSE
    v_def:=replace(v_def,v_old,v_new);
    EXECUTE v_def;
  END IF;
END;
$migration$;
