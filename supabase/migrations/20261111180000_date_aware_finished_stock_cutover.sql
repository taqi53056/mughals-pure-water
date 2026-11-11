-- Treat finished-goods opening stock as a physical cutover and calculate
-- stock availability as of each transaction date. This prevents historical
-- production/sales from being counted twice and prevents backdated sales from
-- consuming stock produced later.

CREATE OR REPLACE FUNCTION private.get_finished_stock_balance(
  p_product_type text,
  p_as_of_date date,
  p_opening_quantity_override numeric DEFAULT NULL,
  p_opening_date_override date DEFAULT NULL,
  p_exclude_adjustment_id bigint DEFAULT NULL
)
RETURNS TABLE(
  manual_stock numeric,
  production_stock numeric,
  sold_quantity numeric,
  adjustment_quantity numeric,
  available_quantity numeric
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO ''
AS $function$
DECLARE
  v_cutover_date date;
  v_business_today date;
  v_factor numeric;
  v_manual_stock numeric := 0;
  v_production_stock numeric := 0;
  v_sold_quantity numeric := 0;
  v_adjustment_quantity numeric := 0;
BEGIN
  v_business_today:=(now() AT TIME ZONE 'Asia/Karachi')::date;

  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'صرف ایڈمن تیار مال کا حساب دیکھ سکتا ہے۔'
      USING ERRCODE='42501';
  END IF;

  IF p_product_type NOT IN ('500ml','1.5L','6L') OR p_as_of_date IS NULL THEN
    RAISE EXCEPTION 'پروڈکٹ اور اسٹاک کی تاریخ درست درج کریں۔'
      USING ERRCODE='22023';
  END IF;
  IF p_as_of_date>v_business_today THEN
    RAISE EXCEPTION 'مستقبل کی تاریخ پر تیار مال کا حساب یا اندراج نہیں ہو سکتا۔'
      USING ERRCODE='22023';
  END IF;

  v_factor:=CASE p_product_type
    WHEN '500ml' THEN 24
    WHEN '1.5L' THEN 12
    ELSE 1
  END;

  IF p_opening_date_override IS NOT NULL THEN
    IF p_opening_date_override>v_business_today THEN
      RAISE EXCEPTION 'ابتدائی تیار مال کی تاریخ مستقبل کی نہیں ہو سکتی۔'
        USING ERRCODE='22023';
    END IF;
    v_cutover_date:=p_opening_date_override;
    v_manual_stock:=CASE
      WHEN p_opening_date_override<=p_as_of_date
        THEN coalesce(p_opening_quantity_override,0)
      ELSE 0
    END;
  ELSE
    SELECT min(f.entry_date)
      INTO v_cutover_date
    FROM public.finished_goods f
    WHERE f.product_type=p_product_type;

    SELECT coalesce(sum(f.quantity),0)
      INTO v_manual_stock
    FROM public.finished_goods f
    WHERE f.product_type=p_product_type
      AND f.entry_date<=p_as_of_date;
  END IF;

  SELECT coalesce(sum(sl.quantity),0)
    INTO v_production_stock
  FROM public.stock_ledger sl
  WHERE sl.product_type=p_product_type
    AND sl.movement_type IN ('production','production_reversal')
    AND sl.movement_date<=p_as_of_date
    AND (v_cutover_date IS NULL
      OR p_as_of_date<v_cutover_date
      OR sl.movement_date>=v_cutover_date);

  SELECT coalesce(sum(ps.quantity),0)
    INTO v_sold_quantity
  FROM public.product_sales ps
  WHERE ps.product_type=p_product_type
    AND ps.sale_date<=p_as_of_date
    AND (v_cutover_date IS NULL
      OR p_as_of_date<v_cutover_date
      OR ps.sale_date>=v_cutover_date);

  SELECT
    coalesce((SELECT sum(
      CASE a.adjustment_type
        WHEN 'increase' THEN a.quantity
        WHEN 'decrease' THEN -a.quantity
        ELSE 0
      END
    )
    FROM public.finished_stock_adjustments a
    WHERE a.product_type=p_product_type
      AND a.adjustment_date<=p_as_of_date
      AND (v_cutover_date IS NULL
        OR p_as_of_date<v_cutover_date
        OR a.adjustment_date>=v_cutover_date)
      AND (p_exclude_adjustment_id IS NULL
        OR a.id IS DISTINCT FROM p_exclude_adjustment_id)),0)
    - coalesce((SELECT sum(r.replacement_quantity)/v_factor
      FROM public.product_returns r
      WHERE r.product_type=p_product_type
        AND r.return_date<=p_as_of_date
        AND (v_cutover_date IS NULL
          OR p_as_of_date<v_cutover_date
          OR r.return_date>=v_cutover_date)),0)
    INTO v_adjustment_quantity;

  RETURN QUERY
  SELECT
    v_manual_stock,
    v_production_stock,
    v_sold_quantity,
    v_adjustment_quantity,
    v_manual_stock+v_production_stock-v_sold_quantity+v_adjustment_quantity;
END;
$function$;

REVOKE ALL ON FUNCTION private.get_finished_stock_balance(text,date,numeric,date,bigint)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.get_finished_stock_balance(text,date,numeric,date,bigint)
  TO authenticated;

-- Finished-goods opening stock is a cutover, not an extra historical purchase.
DO $migration$
DECLARE
  v_definition text;
  v_old text;
  v_new text;
BEGIN
  SELECT pg_get_functiondef(
    'private.mpw_guard_finished_goods_opening_stock()'::regprocedure
  ) INTO v_definition;

  v_old := $old$  select
    coalesce((select sum(f.quantity) from public.finished_goods f
      where f.product_type=new.product_type and f.unit=v_unit
        and (v_old_id is null or f.id is distinct from v_old_id)),0)
    + new.quantity
    + coalesce((select sum(sl.quantity) from public.stock_ledger sl
      where sl.product_type=new.product_type
        and sl.movement_type in ('production','production_reversal')),0)
    - coalesce((select sum(ps.quantity) from public.product_sales ps
      where ps.product_type=new.product_type and ps.unit=v_unit),0)
    - coalesce((select sum(r.replacement_quantity)/v_factor from public.product_returns r
      where r.product_type=new.product_type),0)
    + coalesce((select sum(case when a.adjustment_type='increase' then a.quantity
                                when a.adjustment_type='decrease' then -a.quantity else 0 end)
      from public.finished_stock_adjustments a where a.product_type=new.product_type),0)
  into v_available;$old$;
  v_new := $new$  select b.available_quantity
    into v_available
  from private.get_finished_stock_balance(
    new.product_type,(now() AT TIME ZONE 'Asia/Karachi')::date,new.quantity,new.entry_date,null::bigint
  ) b;$new$;
  v_definition:=replace(v_definition,v_old,v_new);
  IF position('private.get_finished_stock_balance' IN v_definition)=0 THEN
    RAISE EXCEPTION 'Could not safely align finished-goods opening-stock guard.';
  END IF;
  EXECUTE v_definition;

  SELECT pg_get_functiondef(
    'private.mpw_guard_finished_stock_adjustment()'::regprocedure
  ) INTO v_definition;

  v_old := $old$  select
    coalesce((select sum(f.quantity) from public.finished_goods f
      where f.product_type=new.product_type and f.unit=v_unit),0)
    + coalesce((select sum(sl.quantity) from public.stock_ledger sl
      where sl.product_type=new.product_type
        and sl.movement_type in ('production','production_reversal')),0)
    - coalesce((select sum(ps.quantity) from public.product_sales ps
      where ps.product_type=new.product_type and ps.unit=v_unit),0)
    - coalesce((select sum(r.replacement_quantity)/v_factor from public.product_returns r
      where r.product_type=new.product_type),0)
    + coalesce((select sum(case when a.adjustment_type='increase' then a.quantity
                                when a.adjustment_type='decrease' then -a.quantity else 0 end)
      from public.finished_stock_adjustments a
      where a.product_type=new.product_type and a.id is distinct from new.id),0)
  into v_available;$old$;
  v_new := $new$  select b.available_quantity
    into v_available
  from private.get_finished_stock_balance(
    new.product_type,new.adjustment_date,null::numeric,null::date,new.id
  ) b;$new$;
  v_definition:=replace(v_definition,v_old,v_new);
  IF position('private.get_finished_stock_balance' IN v_definition)=0 THEN
    RAISE EXCEPTION 'Could not safely align finished-stock adjustment guard.';
  END IF;
  EXECUTE v_definition;

  -- Sale stock is evaluated at the sale date, never against later production.
  SELECT pg_get_functiondef(
    'private.record_product_sale(date,text,integer,bigint,numeric,text,uuid)'::regprocedure
  ) INTO v_definition;

  v_old := $old$  select
    coalesce((select sum(quantity) from public.finished_goods where product_type=p_product_type and unit=v_unit),0)
    +coalesce((select sum(quantity) from public.stock_ledger where product_type=p_product_type and movement_type in ('production','production_reversal')),0)
    -coalesce((select sum(quantity) from public.product_sales where product_type=p_product_type and unit=v_unit),0)
    -coalesce((select sum(replacement_quantity) /
      case when p_product_type='500ml' then 24::numeric
           when p_product_type='1.5L' then 12::numeric else 1::numeric end
      from public.product_returns where product_type=p_product_type),0)
    +coalesce((select sum(case when adjustment_type='increase' then quantity
      when adjustment_type='decrease' then -quantity else 0 end)
      from public.finished_stock_adjustments where product_type=p_product_type),0)
  into v_available;$old$;
  v_new := $new$  select b.available_quantity
    into v_available
  from private.get_finished_stock_balance(p_product_type,p_sale_date) b;$new$;
  v_definition:=replace(v_definition,v_old,v_new);
  IF position('private.get_finished_stock_balance(p_product_type,p_sale_date)' IN v_definition)=0 THEN
    RAISE EXCEPTION 'Could not safely align product-sale stock validation.';
  END IF;
  EXECUTE v_definition;

  -- Returned replacements are also limited to stock available on return date.
  SELECT pg_get_functiondef(
    'private.record_product_return(date,text,integer,text,uuid)'::regprocedure
  ) INTO v_definition;

  v_old := $old$ select
  (coalesce((select sum(quantity) from public.finished_goods where product_type=p_product_type and unit=v_unit),0)
  +coalesce((select sum(quantity) from public.stock_ledger where product_type=p_product_type and movement_type in ('production','production_reversal')),0)
  -coalesce((select sum(quantity) from public.product_sales where product_type=p_product_type and unit=v_unit),0)
  +coalesce((select sum(case when adjustment_type='increase' then quantity
    when adjustment_type='decrease' then -quantity else 0 end)
    from public.finished_stock_adjustments where product_type=p_product_type),0))*v_factor
  -coalesce((select sum(replacement_quantity) from public.product_returns where product_type=p_product_type),0)
 into v_available_bottles;$old$;
  v_new := $new$ select b.available_quantity*v_factor
 into v_available_bottles
 from private.get_finished_stock_balance(p_product_type,p_return_date) b;$new$;
  v_definition:=replace(v_definition,v_old,v_new);
  IF position('private.get_finished_stock_balance(p_product_type,p_return_date)' IN v_definition)=0 THEN
    RAISE EXCEPTION 'Could not safely align product-return stock validation.';
  END IF;
  EXECUTE v_definition;

  -- The current stock summary uses exactly the same date-aware balance logic.
  EXECUTE $summary$
    CREATE OR REPLACE FUNCTION public.get_finished_stock_summary()
    RETURNS TABLE(
      product_type text,
      unit text,
      manual_stock numeric,
      production_stock numeric,
      sold_quantity numeric,
      adjustment_quantity numeric,
      available_quantity numeric
    )
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $function$
    BEGIN
      IF auth.uid() IS NULL OR NOT public.is_admin() THEN
        RAISE EXCEPTION 'صرف ایڈمن تیار مال کا اسٹاک دیکھ سکتا ہے۔'
          USING ERRCODE='42501';
      END IF;
      RETURN QUERY
      WITH products(product_type,unit) AS (
        VALUES ('500ml'::text,'carton'::text),
               ('1.5L'::text,'carton'::text),
               ('6L'::text,'bottle'::text)
      )
      SELECT p.product_type,p.unit,
        b.manual_stock,b.production_stock,b.sold_quantity,
        b.adjustment_quantity,b.available_quantity
      FROM products p
      CROSS JOIN LATERAL private.get_finished_stock_balance(p.product_type,(now() AT TIME ZONE 'Asia/Karachi')::date) b
      ORDER BY p.product_type;
    END;
    $function$
  $summary$;

  -- No future-dated production may be used as stock for an earlier sale.
  SELECT pg_get_functiondef(
    'private.mpw_guard_operational_stock()'::regprocedure
  ) INTO v_definition;
  v_old := $old$  elsif tg_table_name = 'production' then
    v_date := new.production_date;$old$;
  v_new := $new$  elsif tg_table_name = 'production' then
    IF new.production_date>(now() AT TIME ZONE 'Asia/Karachi')::date THEN
      RAISE EXCEPTION 'مستقبل کی تاریخ پر پروڈکشن درج نہیں ہو سکتی۔'
        USING ERRCODE='22023';
    END IF;
    v_date := new.production_date;$new$;
  v_definition:=replace(v_definition,v_old,v_new);
  IF position('new.production_date>(now() AT TIME ZONE ''Asia/Karachi'')::date' IN v_definition)=0 THEN
    RAISE EXCEPTION 'Could not safely reject future-dated production.';
  END IF;
  EXECUTE v_definition;
END;
$migration$;
