
-- The private deposit writer must insert the return FK in the same statement;
-- a later UPDATE cannot pass the ledger's return-link check constraint.
DO $migration$
DECLARE v_def text; v_old text; v_new text;
BEGIN
 v_def:=pg_get_functiondef('private.record_customer_bottle_deposit(bigint,date,text,integer,text,uuid,text,boolean)'::regprocedure);

 v_old:=$old$  v_held_amount numeric(14,2);
  v_id bigint;$old$;
 v_new:=$new$  v_held_amount numeric(14,2);
  v_id bigint;
  v_bottle_return_id bigint;$new$;
 IF position(v_new in v_def)=0 THEN
  IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'Deposit return variable anchor missing'; END IF;
  v_def:=replace(v_def,v_old,v_new);
 END IF;

 v_old:=$old$  INSERT INTO public.customer_bottle_deposit_ledger(
    customer_id,transaction_date,transaction_type,quantity,unit_amount,
    payment_method,bottle_return_confirmed,details,request_id,entered_by
  )
  VALUES(
    p_customer_id,p_transaction_date,p_transaction_type,p_quantity,1600,
    p_payment_method,p_bottle_return_confirmed,nullif(btrim(p_details),''),p_request_id,auth.uid()
  )$old$;
 v_new:=$new$  v_bottle_return_id:=nullif(current_setting('mpw.customer_bottle_return_id',true),'')::bigint;

  INSERT INTO public.customer_bottle_deposit_ledger(
    customer_id,transaction_date,transaction_type,quantity,unit_amount,
    payment_method,bottle_return_confirmed,details,bottle_return_id,request_id,entered_by
  )
  VALUES(
    p_customer_id,p_transaction_date,p_transaction_type,p_quantity,1600,
    p_payment_method,p_bottle_return_confirmed,nullif(btrim(p_details),''),v_bottle_return_id,p_request_id,auth.uid()
  )$new$;
 IF position(v_new in v_def)=0 THEN
  IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'Deposit return insert anchor missing'; END IF;
  v_def:=replace(v_def,v_old,v_new);
 END IF;
 EXECUTE v_def;
END;
$migration$;

CREATE OR REPLACE FUNCTION public.record_customer_bottle_deposit(
  p_customer_id bigint,
  p_transaction_date date,
  p_transaction_type text,
  p_quantity integer,
  p_payment_method text,
  p_request_id uuid,
  p_details text,
  p_bottle_return_confirmed boolean,
  p_bottle_return_id bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_existing public.customer_bottle_deposit_ledger%rowtype;
  v_return public.customer_19l_bottle_returns%rowtype;
  v_refunded integer;
  v_result jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'کمپنی بوتل کی ضمانت/واپسی صرف ایڈمن درج کر سکتا ہے۔' USING ERRCODE='42501';
  END IF;
  IF p_customer_id IS NULL OR p_request_id IS NULL OR p_transaction_date IS NULL THEN
    RAISE EXCEPTION 'کسٹمر، تاریخ اور درخواست شناخت لازمی ہیں۔' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('mpw-customer-bottle-deposit-request-'||p_request_id::text,0));
  SELECT * INTO v_existing FROM public.customer_bottle_deposit_ledger WHERE request_id=p_request_id;
  IF FOUND THEN
    IF v_existing.bottle_return_id IS DISTINCT FROM p_bottle_return_id THEN
      RAISE EXCEPTION 'یہ درخواست پہلے مختلف بوتل واپسی کے ساتھ محفوظ ہے۔' USING ERRCODE='23505';
    END IF;
    PERFORM set_config('mpw.customer_bottle_return_id',coalesce(p_bottle_return_id::text,''),true);
    RETURN private.record_customer_bottle_deposit(
      p_customer_id,p_transaction_date,p_transaction_type,p_quantity,p_payment_method,
      p_request_id,p_details,p_bottle_return_confirmed
    );
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('mpw-month-close-'||date_trunc('month',p_transaction_date)::date::text,0));
  IF p_transaction_type='deposit_received' THEN
    IF p_bottle_return_id IS NOT NULL THEN
      RAISE EXCEPTION 'ضمانت وصولی کے ساتھ واپسی کا ریکارڈ منسلک نہیں ہونا چاہیے۔' USING ERRCODE='22023';
    END IF;
  ELSIF p_transaction_type='deposit_refunded' THEN
    IF p_bottle_return_id IS NULL OR NOT p_bottle_return_confirmed THEN
      RAISE EXCEPTION 'ریفنڈ کے لیے کمپنی بوتل واپسی کا ریکارڈ اور تصدیق لازمی ہے۔' USING ERRCODE='22023';
    END IF;
    SELECT * INTO v_return FROM public.customer_19l_bottle_returns
    WHERE id=p_bottle_return_id AND customer_id=p_customer_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'اس کسٹمر کی کمپنی بوتل واپسی کا ریکارڈ نہیں ملا۔' USING ERRCODE='P0002'; END IF;
    IF p_transaction_date<v_return.return_date THEN
      RAISE EXCEPTION 'ضمانت ریفنڈ کی تاریخ بوتل واپسی کی تاریخ سے پہلے نہیں ہو سکتی۔' USING ERRCODE='22023';
    END IF;
    SELECT coalesce(sum(quantity),0)::integer INTO v_refunded
    FROM public.customer_bottle_deposit_ledger
    WHERE bottle_return_id=p_bottle_return_id AND transaction_type='deposit_refunded';
    IF p_quantity>v_return.quantity-v_refunded THEN
      RAISE EXCEPTION 'اس واپسی پر دستیاب ریفنڈ مقدار صرف % بوتلیں ہے۔',greatest(v_return.quantity-v_refunded,0) USING ERRCODE='23514';
    END IF;
  ELSE
    RAISE EXCEPTION 'ضمانت کی قسم درست منتخب کریں۔' USING ERRCODE='22023';
  END IF;

  PERFORM set_config('mpw.customer_bottle_return_id',coalesce(p_bottle_return_id::text,''),true);
  v_result:=private.record_customer_bottle_deposit(
    p_customer_id,p_transaction_date,p_transaction_type,p_quantity,p_payment_method,
    p_request_id,p_details,p_bottle_return_confirmed
  );
  IF p_transaction_type='deposit_refunded' THEN
    UPDATE public.customer_bottle_deposit_ledger SET bottle_return_id=p_bottle_return_id
    WHERE request_id=p_request_id AND bottle_return_id IS DISTINCT FROM p_bottle_return_id;
  END IF;
  PERFORM set_config('mpw.customer_bottle_return_id','',true);
  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.record_customer_bottle_deposit(bigint,date,text,integer,text,uuid,text,boolean,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.record_customer_bottle_deposit(bigint,date,text,integer,text,uuid,text,boolean,bigint) TO authenticated;
