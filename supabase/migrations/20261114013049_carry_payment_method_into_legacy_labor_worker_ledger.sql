ALTER TABLE public.labor_payments
  ADD COLUMN IF NOT EXISTS payment_method text NOT NULL DEFAULT 'cash';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='labor_payments_payment_method_check') THEN
    ALTER TABLE public.labor_payments
      ADD CONSTRAINT labor_payments_payment_method_check
      CHECK (payment_method = ANY (ARRAY['cash','bank','jazzcash','easypaisa','other']));
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.sync_labor_payment_worker_ledger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF TG_OP <> 'INSERT' THEN
    DELETE FROM public.worker_ledger
    WHERE source_table='labor_payments' AND source_id=OLD.id;
  END IF;

  IF TG_OP <> 'DELETE' AND NEW.worker_id IS NOT NULL AND COALESCE(NEW.amount,0)>0 THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.workers
      WHERE id=NEW.worker_id AND is_active=true AND is_owner=false
    ) THEN
      RAISE EXCEPTION 'مالک کو ورکر کی اجرت یا ایڈوانس ادا نہیں کیا جا سکتا؛ Owner کی بچت الگ رپورٹ میں ہے۔';
    END IF;

    INSERT INTO public.worker_ledger(
      worker_id,entry_date,entry_type,work_category,amount,note,
      payment_method,source_table,source_id,entered_by
    )
    VALUES(
      NEW.worker_id,NEW.payment_date,'payment',COALESCE(NEW.labor_type,'manual'),
      NEW.amount,'مزدوری کی ادائیگی',NEW.payment_method,
      'labor_payments',NEW.id,NEW.entered_by
    );
  END IF;

  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$function$;
