-- Make a bottle and its included cap one atomic, idempotent inventory operation.
CREATE OR REPLACE FUNCTION public.save_raw_material_purchase_atomic(
  p_purchase jsonb,
  p_request_id uuid DEFAULT NULL,
  p_cap_request_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
  v_type text;
  v_record_type text;
  v_unit text;
  v_pair_type text;
  v_date date;
  v_quantity numeric;
  v_amount numeric;
  v_supplier text;
  v_payment text;
  v_details text;
  v_primary_id bigint;
  v_cap_id bigint;
  v_existing public.raw_material_purchases%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'صرف مجاز منتظم خام مال درج کر سکتا ہے۔' USING ERRCODE='42501';
  END IF;
  IF p_purchase IS NULL OR jsonb_typeof(p_purchase) <> 'object' THEN
    RAISE EXCEPTION 'خام مال کا اندراج درست نہیں۔' USING ERRCODE='22023';
  END IF;

  v_type := p_purchase->>'material_type';
  v_record_type := p_purchase->>'record_type';
  v_date := NULLIF(p_purchase->>'purchase_date','')::date;
  v_quantity := NULLIF(p_purchase->>'quantity','')::numeric;
  v_amount := NULLIF(p_purchase->>'total_amount','')::numeric;
  v_supplier := NULLIF(btrim(p_purchase->>'supplier'),'');
  v_payment := p_purchase->>'payment_method';
  v_details := NULLIF(btrim(p_purchase->>'details'),'');

  v_unit := CASE v_type
    WHEN 'bottle_500ml' THEN 'bottle'
    WHEN 'bottle_1_5l' THEN 'bottle'
    WHEN 'bottle_6l' THEN 'bottle'
    WHEN 'cap_19l' THEN 'piece'
    WHEN 'carton_500ml' THEN 'carton'
    WHEN 'carton_1_5l' THEN 'carton'
    WHEN 'tape_bundle' THEN 'bundle'
    WHEN 'sticker' THEN 'piece'
    ELSE NULL
  END;
  v_pair_type := CASE v_type
    WHEN 'bottle_500ml' THEN 'cap_500ml'
    WHEN 'bottle_1_5l' THEN 'cap_1_5l'
    WHEN 'bottle_6l' THEN 'cap_6l'
    ELSE NULL
  END;

  IF v_unit IS NULL OR v_record_type IS NULL OR v_record_type NOT IN ('purchase','opening_stock')
     OR v_payment IS NULL OR v_date IS NULL OR v_quantity IS NULL OR v_quantity <= 0
     OR v_quantity <> trunc(v_quantity)
     OR v_amount IS NULL OR v_amount <= 0
     OR length(coalesce(v_supplier,'')) > 120
     OR length(coalesce(v_details,'')) > 300 THEN
    RAISE EXCEPTION 'خام مال کی قسم، تاریخ، مقدار یا رقم درست نہیں۔' USING ERRCODE='22023';
  END IF;
  IF p_purchase->>'unit' IS DISTINCT FROM v_unit THEN
    RAISE EXCEPTION 'خام مال کی اکائی درست نہیں۔' USING ERRCODE='22023';
  END IF;
  IF v_record_type='opening_stock' THEN
    IF v_payment <> 'opening' OR p_request_id IS NOT NULL OR p_cap_request_id IS NOT NULL THEN
      RAISE EXCEPTION 'ابتدائی اسٹاک کی ادائیگی یا درخواست کی شناخت درست نہیں۔' USING ERRCODE='22023';
    END IF;
  ELSE
    IF v_payment NOT IN ('cash','bank','jazzcash','easypaisa','other')
       OR p_request_id IS NULL
       OR (v_pair_type IS NOT NULL AND (p_cap_request_id IS NULL OR p_cap_request_id=p_request_id))
       OR (v_pair_type IS NULL AND p_cap_request_id IS NOT NULL) THEN
      RAISE EXCEPTION 'خریداری کی ادائیگی یا درخواست کی شناخت درست نہیں۔' USING ERRCODE='22023';
    END IF;
  END IF;

  IF v_record_type='opening_stock' THEN
    INSERT INTO public.raw_material_purchases
      (purchase_date,record_type,material_type,quantity,unit,total_amount,supplier,payment_method,details,entered_by)
    VALUES
      (v_date,v_record_type,v_type,v_quantity,v_unit,v_amount,v_supplier,v_payment,v_details,auth.uid())
    ON CONFLICT (material_type) WHERE record_type='opening_stock'
    DO UPDATE SET
      purchase_date=EXCLUDED.purchase_date,
      quantity=EXCLUDED.quantity,
      unit=EXCLUDED.unit,
      total_amount=EXCLUDED.total_amount,
      supplier=EXCLUDED.supplier,
      payment_method=EXCLUDED.payment_method,
      details=EXCLUDED.details,
      entered_by=EXCLUDED.entered_by
    RETURNING id INTO v_primary_id;
  ELSE
    INSERT INTO public.raw_material_purchases
      (purchase_date,record_type,material_type,quantity,unit,total_amount,supplier,payment_method,details,entered_by,request_id)
    VALUES
      (v_date,v_record_type,v_type,v_quantity,v_unit,v_amount,v_supplier,v_payment,v_details,auth.uid(),p_request_id)
    ON CONFLICT (request_id) DO NOTHING
    RETURNING id INTO v_primary_id;

    IF v_primary_id IS NULL THEN
      SELECT * INTO v_existing
      FROM public.raw_material_purchases
      WHERE request_id=p_request_id;
      IF NOT FOUND
         OR v_existing.purchase_date IS DISTINCT FROM v_date
         OR v_existing.record_type IS DISTINCT FROM v_record_type
         OR v_existing.material_type IS DISTINCT FROM v_type
         OR v_existing.quantity IS DISTINCT FROM v_quantity
         OR v_existing.unit IS DISTINCT FROM v_unit
         OR v_existing.total_amount IS DISTINCT FROM v_amount
         OR v_existing.supplier IS DISTINCT FROM v_supplier
         OR v_existing.payment_method IS DISTINCT FROM v_payment
         OR v_existing.details IS DISTINCT FROM v_details THEN
        RAISE EXCEPTION 'درخواست کی شناخت پہلے کسی مختلف خریداری کے لیے استعمال ہو چکی ہے۔' USING ERRCODE='23505';
      END IF;
      v_primary_id := v_existing.id;
    END IF;
  END IF;

  IF v_pair_type IS NOT NULL THEN
    IF v_record_type='opening_stock' THEN
      INSERT INTO public.raw_material_purchases
        (purchase_date,record_type,material_type,quantity,unit,total_amount,supplier,payment_method,details,entered_by)
      VALUES
        (v_date,v_record_type,v_pair_type,v_quantity,'piece',0,NULL,'opening',
         'بوتل کے ساتھ شامل ڈھکن؛ رقم بوتل کی مالیت میں شامل ہے',auth.uid())
      ON CONFLICT (material_type) WHERE record_type='opening_stock'
      DO UPDATE SET
        quantity=EXCLUDED.quantity,
        unit=EXCLUDED.unit,
        total_amount=EXCLUDED.total_amount,
        supplier=EXCLUDED.supplier,
        payment_method=EXCLUDED.payment_method,
        details=EXCLUDED.details,
        entered_by=EXCLUDED.entered_by
      RETURNING id INTO v_cap_id;
    ELSE
      INSERT INTO public.raw_material_purchases
        (purchase_date,record_type,material_type,quantity,unit,total_amount,supplier,payment_method,details,entered_by,request_id)
      VALUES
        (v_date,v_record_type,v_pair_type,v_quantity,'piece',0,NULL,v_payment,
         'بوتل کے ساتھ شامل ڈھکن؛ رقم بوتل کی مالیت میں شامل ہے',auth.uid(),p_cap_request_id)
      ON CONFLICT (request_id) DO NOTHING
      RETURNING id INTO v_cap_id;

      IF v_cap_id IS NULL THEN
        SELECT * INTO v_existing
        FROM public.raw_material_purchases
        WHERE request_id=p_cap_request_id;
        IF NOT FOUND
           OR v_existing.purchase_date IS DISTINCT FROM v_date
           OR v_existing.record_type IS DISTINCT FROM v_record_type
           OR v_existing.material_type IS DISTINCT FROM v_pair_type
           OR v_existing.quantity IS DISTINCT FROM v_quantity
           OR v_existing.unit IS DISTINCT FROM 'piece'
           OR v_existing.total_amount IS DISTINCT FROM 0::numeric
           OR v_existing.supplier IS NOT NULL
           OR v_existing.payment_method IS DISTINCT FROM v_payment
           OR v_existing.details IS DISTINCT FROM 'بوتل کے ساتھ شامل ڈھکن؛ رقم بوتل کی مالیت میں شامل ہے' THEN
          RAISE EXCEPTION 'ڈھکن کی درخواست کی شناخت پہلے کسی مختلف اندراج کے لیے استعمال ہو چکی ہے۔' USING ERRCODE='23505';
        END IF;
        v_cap_id := v_existing.id;
      END IF;
    END IF;
  END IF;

  RETURN jsonb_build_object('primary_id',v_primary_id,'paired_cap_id',v_cap_id,
    'material_type',v_type,'paired_cap_type',v_pair_type,'record_type',v_record_type);
END;
$function$;

REVOKE ALL ON FUNCTION public.save_raw_material_purchase_atomic(jsonb,uuid,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_raw_material_purchase_atomic(jsonb,uuid,uuid) TO authenticated;
