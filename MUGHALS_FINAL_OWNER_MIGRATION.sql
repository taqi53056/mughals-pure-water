-- MUGHAL'S PURE WATER: hardened Owner / worker separation
-- Additive and transactional. Preserves existing customer, stock, delivery, production and wage history.
-- PREREQUISITE: the V2 base schema and MUGHALS_MASTER_SUPABASE.sql migration are already applied.
-- Run this owner/workers migration ONCE after taking a database backup. Do not rerun the master migration here.
BEGIN;

-- Fail closed before making any change if the live schema is incomplete.
DO $$
DECLARE missing text[] := ARRAY[]::text[];
BEGIN
  IF to_regclass('public.workers') IS NULL THEN missing:=array_append(missing,'public.workers'); END IF;
  IF to_regclass('public.worker_ledger') IS NULL THEN missing:=array_append(missing,'public.worker_ledger'); END IF;
  IF to_regclass('public.production') IS NULL THEN missing:=array_append(missing,'public.production'); END IF;
  IF to_regclass('public.production_worker_allocations') IS NULL THEN missing:=array_append(missing,'public.production_worker_allocations'); END IF;
  IF to_regclass('public.customer_19l_deliveries') IS NULL THEN missing:=array_append(missing,'public.customer_19l_deliveries'); END IF;
  IF to_regclass('public.product_sales') IS NULL THEN missing:=array_append(missing,'public.product_sales'); END IF;
  IF to_regclass('public.labor_payments') IS NULL THEN missing:=array_append(missing,'public.labor_payments'); END IF;
  IF to_regprocedure('public.is_admin()') IS NULL THEN missing:=array_append(missing,'public.is_admin()'); END IF;
  IF cardinality(missing)>0 THEN RAISE EXCEPTION 'Owner migration preflight failed; missing: %',array_to_string(missing,', '); END IF;
END $$;

-- V2 has no is_owner column yet, so add it before querying it.
ALTER TABLE public.workers ADD COLUMN IF NOT EXISTS is_owner boolean NOT NULL DEFAULT false;
DO $$
BEGIN
  IF (SELECT COUNT(*) FROM public.workers WHERE is_owner=true)>1 THEN
    RAISE EXCEPTION 'ایک سے زیادہ Owner ریکارڈ موجود ہیں؛ پہلے انہیں دستی طور پر reconcile کریں۔';
  END IF;
END $$;
CREATE UNIQUE INDEX IF NOT EXISTS workers_single_owner_idx ON public.workers(is_owner) WHERE is_owner=true;
INSERT INTO public.workers(full_name,work_categories,is_active,is_owner)
SELECT 'Owner',ARRAY['19L delivery','carton loading/unloading'],true,true
WHERE NOT EXISTS (SELECT 1 FROM public.workers WHERE is_owner=true);

-- Owner must never acquire a payable worker-ledger balance, including manual entries.
CREATE OR REPLACE FUNCTION public.prevent_owner_worker_ledger()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.workers w WHERE w.id=NEW.worker_id AND w.is_owner=true) THEN
    RAISE EXCEPTION 'مالک کی محنت ممکنہ بچت ہے؛ اسے ورکر کی قابلِ ادائیگی مزدوری میں درج نہیں کیا جا سکتا۔';
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS worker_ledger_owner_guard ON public.worker_ledger;
CREATE TRIGGER worker_ledger_owner_guard BEFORE INSERT OR UPDATE OF worker_id,entry_type ON public.worker_ledger
FOR EACH ROW EXECUTE FUNCTION public.prevent_owner_worker_ledger();

-- 19L: Owner savings are not wages; ordinary workers receive Rs.20 per successful bottle.
CREATE OR REPLACE FUNCTION public.sync_19l_worker_ledger()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_is_owner boolean := false; v_success integer;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    DELETE FROM public.worker_ledger WHERE source_table='customer_19l_deliveries' AND source_id=OLD.id;
  END IF;
  IF TG_OP <> 'DELETE' AND NEW.worker_id IS NOT NULL THEN
    SELECT w.is_owner INTO v_is_owner FROM public.workers w
    WHERE w.id=NEW.worker_id AND w.is_active=true
      AND (w.is_owner=true OR w.work_categories @> ARRAY['19L delivery']::text[]);
    IF NOT FOUND THEN RAISE EXCEPTION 'منتخب ورکر فعال نہیں یا 19L ڈیلیوری کے لیے مقرر نہیں۔'; END IF;
    v_success := COALESCE(NEW.successful_bottles,0);
    IF v_success<0 THEN RAISE EXCEPTION 'کامیاب بوتلوں کی تعداد منفی نہیں ہو سکتی۔'; END IF;
    IF v_success>0 AND NOT COALESCE(v_is_owner,false) THEN
      INSERT INTO public.worker_ledger(worker_id,entry_date,entry_type,work_category,amount,note,source_table,source_id,entered_by)
      VALUES(NEW.worker_id,NEW.delivery_date,'earning','19L delivery',v_success*20,'19L کامیاب بوتلوں کی مزدوری','customer_19l_deliveries',NEW.id,auth.uid());
    END IF;
    NEW.delivery_labor := CASE WHEN COALESCE(v_is_owner,false) THEN 0 ELSE v_success*20 END;
    RETURN NEW;
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  NEW.delivery_labor := 0;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS customer_19l_worker_ledger_trigger ON public.customer_19l_deliveries;
CREATE TRIGGER customer_19l_worker_ledger_trigger BEFORE INSERT OR UPDATE OR DELETE ON public.customer_19l_deliveries
FOR EACH ROW EXECUTE FUNCTION public.sync_19l_worker_ledger();

-- Allocation rows are the single source of truth for new production worker wages.
CREATE OR REPLACE FUNCTION public.sync_production_allocation_ledger()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_production_date date; v_is_owner boolean := false;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    DELETE FROM public.worker_ledger WHERE source_table='production_worker_allocations' AND source_id=OLD.id;
  END IF;
  IF TG_OP <> 'DELETE' THEN
    SELECT p.production_date INTO v_production_date FROM public.production p WHERE p.id=NEW.production_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'پروڈکشن ریکارڈ موجود نہیں۔'; END IF;
    SELECT w.is_owner INTO v_is_owner FROM public.workers w WHERE w.id=NEW.worker_id AND w.is_active=true
      AND (w.is_owner=true OR w.work_categories @> ARRAY['production']::text[]);
    IF NOT FOUND THEN RAISE EXCEPTION 'منتخب ورکر فعال نہیں یا پروڈکشن کے لیے مقرر نہیں۔'; END IF;
    IF NOT COALESCE(v_is_owner,false) THEN
      INSERT INTO public.worker_ledger(worker_id,entry_date,entry_type,work_category,amount,note,source_table,source_id,entered_by)
      VALUES(NEW.worker_id,v_production_date,'earning','production',NEW.labor_amount,
        format('پروڈکشن: %s کارٹن × Rs.10',NEW.cartons),'production_worker_allocations',NEW.id,auth.uid());
    END IF;
    RETURN NEW;
  END IF;
  RETURN OLD;
END; $$;
DROP TRIGGER IF EXISTS production_allocation_ledger_trigger ON public.production_worker_allocations;
CREATE TRIGGER production_allocation_ledger_trigger AFTER INSERT OR UPDATE OR DELETE ON public.production_worker_allocations
FOR EACH ROW EXECUTE FUNCTION public.sync_production_allocation_ledger();

-- Atomic production + allocation insert. Every 500ml / 1.5L carton must be assigned exactly once.
CREATE OR REPLACE FUNCTION public.record_production_with_workers(
  p_production_date date, p_product_type text, p_quantity integer, p_allocations jsonb DEFAULT '[]'::jsonb
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_production_id bigint; v_labor_amount numeric(12,2); v_worker_labor_total numeric(12,2):=0;
  v_owner_saved_labor numeric(12,2):=0; v_owner_cartons integer:=0; v_item jsonb;
  v_count integer:=0; v_sum bigint:=0; v_distinct_workers integer:=0;
  v_worker_id bigint; v_cartons integer; v_is_owner boolean;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN RAISE EXCEPTION 'صرف ایڈمن پروڈکشن درج کر سکتا ہے۔' USING ERRCODE='42501'; END IF;
  IF p_production_date IS NULL OR p_quantity IS NULL OR p_quantity<=0 THEN RAISE EXCEPTION 'تاریخ اور مکمل مثبت مقدار درج کریں۔' USING ERRCODE='22023'; END IF;
  IF p_product_type NOT IN ('500ml','1.5L','6L') THEN RAISE EXCEPTION 'پروڈکٹ کی قسم درست نہیں۔' USING ERRCODE='22023'; END IF;
  IF jsonb_typeof(p_allocations) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'تقسیم فہرست کی صورت میں ہونی چاہیے۔' USING ERRCODE='22023'; END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_allocations) e(value)
    WHERE jsonb_typeof(e.value)<>'object' OR NOT(e.value?'worker_id') OR NOT(e.value?'cartons')
      OR jsonb_typeof(e.value->'worker_id')<>'number' OR jsonb_typeof(e.value->'cartons')<>'number'
      OR (e.value->>'worker_id') !~ '^[1-9][0-9]*$' OR (e.value->>'cartons') !~ '^[1-9][0-9]*$')
    THEN RAISE EXCEPTION 'ہر شخص کے لیے درست worker_id اور مثبت کارٹن تعداد ضروری ہے۔' USING ERRCODE='22023'; END IF;
  SELECT COUNT(*)::integer,COALESCE(SUM((e.value->>'cartons')::integer),0),
    COUNT(DISTINCT (e.value->>'worker_id')::bigint)::integer
    INTO v_count,v_sum,v_distinct_workers FROM jsonb_array_elements(p_allocations) e(value);
  IF v_count<>v_distinct_workers THEN RAISE EXCEPTION 'ایک شخص کو ایک ہی پروڈکشن میں ایک بار درج کریں۔' USING ERRCODE='22023'; END IF;
  IF p_product_type='6L' AND v_count>0 THEN RAISE EXCEPTION '6L پروڈکشن پر مزدوری نہیں؛ تقسیم درج نہ کریں۔' USING ERRCODE='22023'; END IF;
  IF p_product_type IN ('500ml','1.5L') AND (v_count=0 OR v_sum<>p_quantity) THEN
    RAISE EXCEPTION 'مالک اور مزدوروں کے کارٹنوں کا مجموعہ کل پروڈکشن کے برابر ہونا لازم ہے۔' USING ERRCODE='23514';
  END IF;
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_allocations) LOOP
    v_worker_id:=(v_item->>'worker_id')::bigint; v_cartons:=(v_item->>'cartons')::integer;
    SELECT w.is_owner INTO v_is_owner FROM public.workers w WHERE w.id=v_worker_id AND w.is_active=true
      AND (w.is_owner=true OR w.work_categories @> ARRAY['production']::text[]);
    IF NOT FOUND THEN RAISE EXCEPTION 'منتخب ورکر فعال نہیں یا پروڈکشن کے لیے مقرر نہیں۔'; END IF;
    IF COALESCE(v_is_owner,false) THEN v_owner_cartons:=v_owner_cartons+v_cartons;
    ELSE v_worker_labor_total:=v_worker_labor_total+(v_cartons*10); END IF;
  END LOOP;
  v_owner_saved_labor:=v_owner_cartons*CASE WHEN p_product_type='6L' THEN 0 ELSE 10 END;
  INSERT INTO public.production(product_type,quantity,production_date,labor_rate,labor_amount,entered_by,worker_id)
  VALUES(p_product_type,p_quantity,p_production_date,CASE WHEN p_product_type='6L' THEN 0 ELSE 10 END,v_worker_labor_total,auth.uid(),NULL)
  RETURNING id,labor_amount INTO v_production_id,v_labor_amount;
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_allocations) LOOP
    INSERT INTO public.production_worker_allocations(production_id,worker_id,cartons)
    VALUES(v_production_id,(v_item->>'worker_id')::bigint,(v_item->>'cartons')::integer);
  END LOOP;
  RETURN jsonb_build_object('production_id',v_production_id,'product_type',p_product_type,'quantity',p_quantity,
    'labor_amount',COALESCE(v_labor_amount,0),'worker_labor_total',v_worker_labor_total,
    'owner_saved_labor',v_owner_saved_labor,'owner_cartons',v_owner_cartons,'worker_count',v_count);
END; $$;
REVOKE ALL ON FUNCTION public.record_production_with_workers(date,text,integer,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_production_with_workers(date,text,integer,jsonb) TO authenticated;

-- Owner cannot be paid through the separate labor_payments table either.
CREATE OR REPLACE FUNCTION public.sync_labor_payment_worker_ledger()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF TG_OP <> 'INSERT' THEN
    DELETE FROM public.worker_ledger WHERE source_table='labor_payments' AND source_id=OLD.id;
  END IF;
  IF TG_OP <> 'DELETE' AND NEW.worker_id IS NOT NULL AND COALESCE(NEW.amount,0)>0 THEN
    IF NOT EXISTS (SELECT 1 FROM public.workers WHERE id=NEW.worker_id AND is_active=true AND is_owner=false) THEN
      RAISE EXCEPTION 'مالک کو ورکر کی اجرت یا ایڈوانس ادا نہیں کیا جا سکتا؛ Owner کی بچت الگ رپورٹ میں ہے۔';
    END IF;
    INSERT INTO public.worker_ledger(worker_id,entry_date,entry_type,work_category,amount,note,source_table,source_id,entered_by)
    VALUES(NEW.worker_id,NEW.payment_date,'payment',COALESCE(NEW.labor_type,'manual'),NEW.amount,'مزدوری کی ادائیگی','labor_payments',NEW.id,NEW.entered_by);
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS labor_payment_worker_ledger_trigger ON public.labor_payments;
CREATE TRIGGER labor_payment_worker_ledger_trigger AFTER INSERT OR UPDATE OR DELETE ON public.labor_payments
FOR EACH ROW EXECUTE FUNCTION public.sync_labor_payment_worker_ledger();

-- Carton loading/unloading: Owner gets no payable ledger row.
CREATE OR REPLACE FUNCTION public.sync_carton_worker_ledger()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_is_owner boolean := false;
BEGIN
  IF TG_OP <> 'INSERT' THEN DELETE FROM public.worker_ledger WHERE source_table='product_sales' AND source_id=OLD.id; END IF;
  IF TG_OP <> 'DELETE' AND NEW.worker_id IS NOT NULL AND NEW.unit='carton' AND COALESCE(NEW.quantity,0)>0 THEN
    SELECT w.is_owner INTO v_is_owner FROM public.workers w WHERE w.id=NEW.worker_id AND w.is_active=true
      AND (w.is_owner=true OR w.work_categories @> ARRAY['carton loading/unloading']::text[]);
    IF NOT FOUND THEN RAISE EXCEPTION 'منتخب ورکر فعال نہیں یا کارٹن کے کام کے لیے مقرر نہیں۔'; END IF;
    IF NOT COALESCE(v_is_owner,false) THEN
      INSERT INTO public.worker_ledger(worker_id,entry_date,entry_type,work_category,amount,note,source_table,source_id,entered_by)
      VALUES(NEW.worker_id,NEW.sale_date,'earning','carton loading/unloading',NEW.quantity*10,'کارٹن کی مزدوری: Rs.10 فی کارٹن','product_sales',NEW.id,auth.uid());
    END IF;
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS carton_worker_ledger_trigger ON public.product_sales;
CREATE TRIGGER carton_worker_ledger_trigger AFTER INSERT OR UPDATE OR DELETE ON public.product_sales
FOR EACH ROW EXECUTE FUNCTION public.sync_carton_worker_ledger();

-- Match the app's RPC contract and distinguish Owner savings from worker pay.
CREATE OR REPLACE FUNCTION public.record_product_sale(
  p_sale_date date, p_product_type text, p_quantity integer, p_worker_id bigint
)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
DECLARE
  v_unit text; v_price numeric; v_available numeric; v_sale_id text; v_total numeric;
  v_is_owner boolean := false;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN RAISE EXCEPTION 'صرف ایڈمن سیل درج کر سکتا ہے۔' USING ERRCODE='42501'; END IF;
  IF p_sale_date IS NULL OR p_quantity IS NULL OR p_quantity<=0 THEN RAISE EXCEPTION 'تاریخ اور مثبت مکمل مقدار ضروری ہے۔' USING ERRCODE='22023'; END IF;
  IF p_product_type NOT IN ('500ml','1.5L','6L') THEN RAISE EXCEPTION 'پروڈکٹ کی قسم درست نہیں۔' USING ERRCODE='22023'; END IF;
  IF p_product_type='6L' AND p_worker_id IS NOT NULL THEN RAISE EXCEPTION '6L سیل کے لیے کارٹن مزدور منتخب نہ کریں۔'; END IF;
  IF p_worker_id IS NOT NULL THEN
    SELECT w.is_owner INTO v_is_owner FROM public.workers w
    WHERE w.id=p_worker_id AND w.is_active=true
      AND (w.is_owner=true OR w.work_categories @> ARRAY['carton loading/unloading']::text[]);
    IF NOT FOUND THEN RAISE EXCEPTION 'منتخب ورکر فعال نہیں یا کارٹن کے کام کے لیے مقرر نہیں۔'; END IF;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('finished-stock:'||p_product_type,0));
  v_unit:=CASE WHEN p_product_type='6L' THEN 'bottle' ELSE 'carton' END;
  v_price:=CASE WHEN p_product_type='6L' THEN 55 ELSE 280 END;
  v_total:=p_quantity*v_price;
  SELECT COALESCE((SELECT SUM(quantity) FROM public.finished_goods WHERE product_type=p_product_type AND unit=v_unit),0)
    + COALESCE((SELECT SUM(quantity) FROM public.stock_ledger WHERE product_type=p_product_type AND movement_type IN ('production','production_reversal')),0)
    - COALESCE((SELECT SUM(quantity) FROM public.product_sales WHERE product_type=p_product_type AND unit=v_unit),0)
    + COALESCE((SELECT SUM(CASE WHEN adjustment_type='increase' THEN quantity WHEN adjustment_type='decrease' THEN -quantity ELSE 0 END)
      FROM public.finished_stock_adjustments WHERE product_type=p_product_type),0) INTO v_available;
  IF p_quantity>v_available THEN RAISE EXCEPTION 'تیار مال کا اسٹاک کم ہے۔ دستیاب مقدار: %',GREATEST(0,v_available) USING ERRCODE='23514'; END IF;
  INSERT INTO public.product_sales(sale_date,product_type,quantity,unit,unit_price,total_amount,notes,worker_id)
  VALUES(p_sale_date,p_product_type,p_quantity,v_unit,v_price,v_total,NULL,p_worker_id) RETURNING id::text INTO v_sale_id;
  RETURN jsonb_build_object('sale_id',v_sale_id,'product_type',p_product_type,'quantity',p_quantity,'unit',v_unit,
    'unit_price',v_price,'total_amount',v_total,
    'labor_amount',CASE WHEN p_product_type='6L' OR p_worker_id IS NULL OR v_is_owner THEN 0 ELSE p_quantity*10 END,
    'owner_saved_labor',CASE WHEN p_product_type='6L' OR NOT v_is_owner THEN 0 ELSE p_quantity*10 END);
END; $$;
REVOKE ALL ON FUNCTION public.record_product_sale(date,text,integer,bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_product_sale(date,text,integer,bigint) TO authenticated;

-- Accurate all-time Owner savings summary (avoids browser's 1,000-row API limit).
CREATE OR REPLACE FUNCTION public.get_owner_work_summary()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_owner_id bigint; v_prod_cartons bigint; v_delivery_bottles bigint; v_sales_cartons bigint;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN RAISE EXCEPTION 'صرف ایڈمن مالک کی رپورٹ دیکھ سکتا ہے۔' USING ERRCODE='42501'; END IF;
  SELECT id INTO v_owner_id FROM public.workers WHERE is_owner=true AND is_active=true LIMIT 1;
  IF v_owner_id IS NULL THEN RAISE EXCEPTION 'Owner ریکارڈ موجود نہیں یا غیر فعال ہے۔'; END IF;
  SELECT COALESCE(SUM(cartons),0) INTO v_prod_cartons FROM public.production_worker_allocations WHERE worker_id=v_owner_id;
  SELECT COALESCE(SUM(successful_bottles),0) INTO v_delivery_bottles FROM public.customer_19l_deliveries WHERE worker_id=v_owner_id;
  SELECT COALESCE(SUM(quantity),0) INTO v_sales_cartons FROM public.product_sales WHERE worker_id=v_owner_id AND unit='carton';
  RETURN jsonb_build_object('owner_id',v_owner_id,'production_cartons',v_prod_cartons,'production_saving',v_prod_cartons*10,
    'delivery_bottles',v_delivery_bottles,'delivery_saving',v_delivery_bottles*20,
    'sales_cartons',v_sales_cartons,'sales_saving',v_sales_cartons*10,
    'total_saving',v_prod_cartons*10+v_delivery_bottles*20+v_sales_cartons*10);
END; $$;
REVOKE ALL ON FUNCTION public.get_owner_work_summary() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_owner_work_summary() TO authenticated;

COMMIT;

-- Post-migration verification report (the transaction above has committed).
SELECT check_name, status, detail FROM (
  SELECT 'single_owner_record'::text AS check_name,
    CASE WHEN COUNT(*)=1 THEN 'OK' ELSE 'CHECK' END AS status,
    'Owner records: '||COUNT(*)::text AS detail
  FROM public.workers WHERE is_owner=true
  UNION ALL
  SELECT 'owner_ledger_guard',
    CASE WHEN EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='worker_ledger_owner_guard' AND NOT tgisinternal) THEN 'OK' ELSE 'CHECK' END,
    'Owner cannot receive worker-ledger entries'
  UNION ALL
  SELECT 'delivery_ledger_trigger',
    CASE WHEN EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='customer_19l_worker_ledger_trigger' AND NOT tgisinternal) THEN 'OK' ELSE 'CHECK' END,
    '19L worker wages are synchronized'
  UNION ALL
  SELECT 'production_allocation_trigger',
    CASE WHEN EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='production_allocation_ledger_trigger' AND NOT tgisinternal) THEN 'OK' ELSE 'CHECK' END,
    'Production allocation wages are synchronized'
  UNION ALL
  SELECT 'carton_ledger_trigger',
    CASE WHEN EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='carton_worker_ledger_trigger' AND NOT tgisinternal) THEN 'OK' ELSE 'CHECK' END,
    'Carton loading wages are synchronized'
  UNION ALL
  SELECT 'owner_summary_rpc',
    CASE WHEN to_regprocedure('public.get_owner_work_summary()') IS NOT NULL THEN 'OK' ELSE 'CHECK' END,
    'Owner savings summary RPC is installed'
) checks ORDER BY check_name;
