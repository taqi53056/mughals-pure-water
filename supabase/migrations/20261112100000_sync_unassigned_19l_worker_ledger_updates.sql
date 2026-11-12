CREATE OR REPLACE FUNCTION public.sync_unassigned_19l_worker_ledger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_labor numeric;
BEGIN
  IF TG_OP IN ('UPDATE','DELETE') THEN
    DELETE FROM public.worker_ledger
    WHERE source_table='unassigned_19l_deliveries' AND source_id=OLD.id;
  END IF;

  IF TG_OP='DELETE' THEN
    RETURN OLD;
  END IF;

  IF NEW.worker_id IS NULL THEN
    RAISE EXCEPTION 'غیر منسلک 19L ڈیلیوری کے لیے فعال ورکر منتخب کرنا ضروری ہے۔'
      USING ERRCODE='23514';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.workers w
    WHERE w.id=NEW.worker_id AND w.is_active=true AND w.is_owner=false
      AND w.work_categories @> ARRAY['19L delivery']::text[]
  ) THEN
    RAISE EXCEPTION 'منتخب ورکر فعال نہیں یا 19L ڈیلیوری کے لیے مقرر نہیں۔'
      USING ERRCODE='23514';
  END IF;

  v_labor := COALESCE(NEW.empty_bottles_returned,0)::numeric * 20;

  IF v_labor>0 THEN
    INSERT INTO public.worker_ledger(
      worker_id,entry_date,entry_type,work_category,amount,note,
      source_table,source_id,entered_by,request_id
    ) VALUES (
      NEW.worker_id,NEW.delivery_date,'earning','19L delivery',v_labor,
      'غیر منسلک 19L سپلائی — '||COALESCE(NEW.empty_bottles_returned,0)||' کامیاب بوتلیں',
      'unassigned_19l_deliveries',NEW.id,NEW.entered_by,NEW.request_id
    );
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS unassigned_19l_worker_ledger_sync ON public.unassigned_19l_deliveries;
CREATE TRIGGER unassigned_19l_worker_ledger_sync
AFTER UPDATE OR DELETE ON public.unassigned_19l_deliveries
FOR EACH ROW EXECUTE FUNCTION public.sync_unassigned_19l_worker_ledger();