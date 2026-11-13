
-- Supplier exchanges are 1:1 replacements received from the supplier.
-- They do not consume the shop's finished-goods stock and are not new sales.
-- Serialize by request id, validate idempotency payloads, and retain admin-only access.
CREATE OR REPLACE FUNCTION private.record_product_return(
  p_return_date date,
  p_product_type text,
  p_quantity integer,
  p_reason text,
  p_request_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_return_id bigint;
  v_existing public.product_returns%rowtype;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'صرف ایڈمن خراب مال کی واپسی درج کر سکتا ہے۔'
      USING ERRCODE='42501';
  END IF;

  IF p_request_id IS NULL
     OR p_return_date IS NULL
     OR p_quantity IS NULL
     OR p_quantity<=0
     OR p_product_type NOT IN ('500ml','1.5L','6L')
     OR nullif(btrim(p_reason),'') IS NULL
     OR length(btrim(p_reason))>200 THEN
    RAISE EXCEPTION 'تاریخ، پروڈکٹ، مثبت مقدار، 200 حروف تک وجہ اور درخواست شناخت لازمی ہیں۔'
      USING ERRCODE='22023';
  END IF;

  -- A supplier replacement is received in the same quantity; it is not
  -- withdrawn from finished stock, because the defective item is exchanged.
  PERFORM pg_advisory_xact_lock(
    hashtextextended('mpw-product-return-'||p_request_id::text,0)
  );

  SELECT * INTO v_existing
  FROM public.product_returns
  WHERE request_id=p_request_id;

  IF FOUND THEN
    IF v_existing.return_date IS DISTINCT FROM p_return_date
       OR v_existing.product_type IS DISTINCT FROM p_product_type
       OR v_existing.quantity IS DISTINCT FROM p_quantity
       OR v_existing.replacement_quantity IS DISTINCT FROM p_quantity
       OR v_existing.reason IS DISTINCT FROM btrim(p_reason) THEN
      RAISE EXCEPTION 'درخواست کی شناخت پہلے مختلف واپسی کے لیے استعمال ہو چکی ہے۔'
        USING ERRCODE='23505';
    END IF;

    RETURN jsonb_build_object(
      'return_id',v_existing.id,
      'product_type',v_existing.product_type,
      'quantity',v_existing.quantity,
      'replacement_quantity',v_existing.replacement_quantity,
      'already_recorded',true
    );
  END IF;

  INSERT INTO public.product_returns(
    return_date,product_type,quantity,replacement_quantity,
    reason,entered_by,request_id
  )
  VALUES(
    p_return_date,p_product_type,p_quantity,p_quantity,
    btrim(p_reason),auth.uid(),p_request_id
  )
  ON CONFLICT(request_id) DO NOTHING
  RETURNING id INTO v_return_id;

  IF v_return_id IS NULL THEN
    SELECT * INTO v_existing
    FROM public.product_returns
    WHERE request_id=p_request_id;

    IF NOT FOUND
       OR v_existing.return_date IS DISTINCT FROM p_return_date
       OR v_existing.product_type IS DISTINCT FROM p_product_type
       OR v_existing.quantity IS DISTINCT FROM p_quantity
       OR v_existing.replacement_quantity IS DISTINCT FROM p_quantity
       OR v_existing.reason IS DISTINCT FROM btrim(p_reason) THEN
      RAISE EXCEPTION 'درخواست کی شناخت پہلے مختلف واپسی کے لیے استعمال ہو چکی ہے۔'
        USING ERRCODE='23505';
    END IF;

    v_return_id:=v_existing.id;
  END IF;

  RETURN jsonb_build_object(
    'return_id',v_return_id,
    'product_type',p_product_type,
    'quantity',p_quantity,
    'replacement_quantity',p_quantity,
    'already_recorded',false
  );
END;
$function$;
