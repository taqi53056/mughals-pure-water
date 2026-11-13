
-- Delivery labor is based on every filled bottle, never on returned empties.
CREATE OR REPLACE FUNCTION public.sync_19l_worker_ledger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_is_owner boolean := false;
  v_success integer;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    DELETE FROM public.worker_ledger
    WHERE source_table='customer_19l_deliveries' AND source_id=OLD.id;
  END IF;

  IF TG_OP <> 'DELETE' AND NEW.worker_id IS NOT NULL THEN
    SELECT w.is_owner INTO v_is_owner
    FROM public.workers w
    WHERE w.id=NEW.worker_id AND w.is_active=true
      AND (w.is_owner=true OR w.work_categories @> ARRAY['19L delivery']::text[]);
    IF NOT FOUND THEN
      RAISE EXCEPTION 'منتخب ورکر فعال نہیں یا 19L ڈیلیوری کے لیے مقرر نہیں۔';
    END IF;

    v_success := COALESCE(NEW.successful_bottles,0);
    IF v_success<0 THEN RAISE EXCEPTION 'کامیاب بوتلوں کی تعداد منفی نہیں ہو سکتی۔'; END IF;

    IF v_success>0 AND NOT COALESCE(v_is_owner,false) THEN
      INSERT INTO public.worker_ledger(
        worker_id,entry_date,entry_type,work_category,amount,note,
        source_table,source_id,entered_by
      )
      VALUES(
        NEW.worker_id,NEW.delivery_date,'earning','19L delivery',v_success*20,
        '19L کامیاب بوتلوں کی مزدوری','customer_19l_deliveries',NEW.id,auth.uid()
      );
    END IF;

    NEW.delivery_labor := CASE WHEN COALESCE(v_is_owner,false) THEN 0 ELSE v_success*20 END;
    RETURN NEW;
  END IF;

  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  NEW.delivery_labor := 0;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.sync_19l_worker_ledger() FROM PUBLIC, anon, authenticated;
