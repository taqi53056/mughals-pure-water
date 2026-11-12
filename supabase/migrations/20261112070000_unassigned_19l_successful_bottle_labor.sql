-- Unassigned 19L revenue and labor follow the same successful-bottle rule as customer deliveries.
-- Water consumption remains based on all filled bottles delivered.
ALTER TABLE public.unassigned_19l_deliveries
  ALTER COLUMN labor_amount SET EXPRESSION AS (empty_bottles_returned::numeric * labor_rate);

CREATE OR REPLACE FUNCTION public.record_unassigned_19l_delivery(p_delivery_date date, p_worker_id bigint, p_bottles_delivered integer, p_empty_bottles_returned integer DEFAULT 0, p_details text DEFAULT NULL::text, p_request_id uuid DEFAULT NULL::uuid, p_damaged_caps integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_existing public.unassigned_19l_deliveries%rowtype;
  v_id bigint;
  v_available numeric := 0;
  v_consumed numeric := 0;
  v_today date := (now() at time zone 'Asia/Karachi')::date;
  v_worker public.workers%rowtype;
  v_labor_amount numeric := 0;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'صرف مجاز ایڈمن یہ اندراج کر سکتا ہے۔' using errcode='42501';
  end if;
  if p_request_id is null then
    raise exception 'درخواست کی شناخت موجود نہیں۔' using errcode='22023';
  end if;
  if p_delivery_date is null or p_delivery_date > v_today then
    raise exception 'مستقبل کی تاریخ پر سپلائی درج نہیں ہو سکتی۔' using errcode='22023';
  end if;
  if p_bottles_delivered is null or p_bottles_delivered <= 0 then
    raise exception 'بوتلوں کی تعداد ایک یا زیادہ ہونی چاہیے۔' using errcode='22023';
  end if;
  if coalesce(p_empty_bottles_returned,0) < 0
     or coalesce(p_empty_bottles_returned,0) > p_bottles_delivered then
    raise exception 'واپس آنے والی خالی بوتلوں کی تعداد درست درج کریں۔' using errcode='22023';
  end if;
  if coalesce(p_damaged_caps,0)<0 then
    raise exception 'خراب ڈھکنوں کی تعداد صفر یا زیادہ ہونی چاہیے۔' using errcode='22023';
  end if;

  v_labor_amount := coalesce(p_empty_bottles_returned,0)::numeric * 20;

  select * into v_existing
  from public.unassigned_19l_deliveries
  where request_id = p_request_id;
  if found then
    if v_existing.delivery_date <> p_delivery_date
       or v_existing.worker_id <> p_worker_id
       or v_existing.bottles_delivered <> p_bottles_delivered
       or v_existing.empty_bottles_returned <> coalesce(p_empty_bottles_returned,0)
       or v_existing.damaged_caps <> coalesce(p_damaged_caps,0)
       or v_existing.details is distinct from nullif(btrim(p_details),'') then
      raise exception 'یہ درخواست پہلے مختلف تفصیل کے ساتھ محفوظ ہو چکی ہے۔' using errcode='23505';
    end if;
    return jsonb_build_object('id',v_existing.id,'worker_id',v_existing.worker_id,
      'bottles_delivered',v_existing.bottles_delivered,'successful_bottles',v_existing.empty_bottles_returned,
      'damaged_caps',v_existing.damaged_caps,'labor_amount',v_existing.labor_amount,
      'already_saved',true);
  end if;

  select * into v_worker
  from public.workers
  where id=p_worker_id and is_active=true and is_owner=false
    and work_categories @> array['19L delivery']::text[];
  if not found then
    raise exception 'منتخب ورکر فعال نہیں یا 19L ڈیلیوری کے لیے مقرر نہیں۔' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('mpw-month-close-'||date_trunc('month',p_delivery_date)::date::text,0));
  if exists(select 1 from public.business_month_closings c
      where c.month_start=date_trunc('month',p_delivery_date)::date and c.status='closed') then
    raise exception 'یہ مہینہ بند ہو چکا ہے؛ اس تاریخ کا اندراج ممکن نہیں۔' using errcode='55000';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('water-pool-shop',0));
  select
    coalesce((select sum(tanker_count*1000) from public.water_tanker_purchases
      where water_use='shop_counter' and purchase_date<=p_delivery_date),0)
    + coalesce((select sum(litres) from public.water_opening_stock
      where water_use='shop_counter' and as_of_date<=p_delivery_date),0)
  into v_available;

  select
    coalesce((select sum(bottles_delivered*19) from public.customer_19l_deliveries
      where delivery_date<=p_delivery_date),0)
    + coalesce((select sum(total_litres) from public.counter_water_sales
      where sale_date<=p_delivery_date),0)
    + coalesce((select sum(quantity*6) from public.production
      where product_type='6L' and production_date<=p_delivery_date),0)
    + coalesce((select sum(bottles_delivered*19) from public.unassigned_19l_deliveries
      where delivery_date<=p_delivery_date),0)
  into v_consumed;

  if v_available-v_consumed < p_bottles_delivered*19 then
    raise exception 'دکان والی ٹنکی کا پانی ناکافی ہے۔ دستیاب لیٹر: %، درکار: %',
      greatest(v_available-v_consumed,0),p_bottles_delivered*19 using errcode='23514';
  end if;

  insert into public.unassigned_19l_deliveries(
    delivery_date,worker_id,bottles_delivered,empty_bottles_returned,damaged_caps,details,request_id,entered_by
  ) values (
    p_delivery_date,p_worker_id,p_bottles_delivered,coalesce(p_empty_bottles_returned,0),coalesce(p_damaged_caps,0),
    nullif(btrim(p_details),''),p_request_id,auth.uid()
  ) returning id into v_id;

  if v_labor_amount > 0 then
    insert into public.worker_ledger(
      worker_id,entry_date,entry_type,work_category,amount,note,source_table,source_id,entered_by,request_id
    ) values (
      p_worker_id,p_delivery_date,'earning','19L delivery',v_labor_amount,
      'غیر منسلک 19L سپلائی — '||coalesce(p_empty_bottles_returned,0)||' کامیاب بوتلیں',
      'unassigned_19l_deliveries',v_id,auth.uid(),p_request_id
    );
  end if;

  return jsonb_build_object('id',v_id,'worker_id',p_worker_id,
    'bottles_delivered',p_bottles_delivered,'successful_bottles',coalesce(p_empty_bottles_returned,0),
    'damaged_caps',coalesce(p_damaged_caps,0),'labor_amount',v_labor_amount,
    'already_saved',false);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.build_business_monthly_report(p_month_start date, p_month_end date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_water_litres numeric:=0; v_water_amount numeric:=0; v_water_per_litre numeric;
  v_fill_water_litres numeric:=0; v_fill_water_amount numeric:=0; v_fill_water_rate numeric;
  v_shop_water_litres numeric:=0; v_shop_water_amount numeric:=0; v_shop_water_rate numeric;
  v_fill_water_used numeric:=0; v_shop_water_used numeric:=0;
  v_delivered numeric:=0; v_unassigned_delivered numeric:=0; v_unassigned_successful numeric:=0; v_unassigned_labor numeric:=0;
  v_bottles numeric:=0; v_caps numeric:=0; v_delivery_labor numeric:=0;
  v_counter_litres numeric:=0; v_counter_amount numeric:=0;
  v_bottle500 numeric; v_bottle15 numeric; v_bottle6 numeric; v_cap500 numeric; v_cap15 numeric; v_cap6 numeric;
  v_carton500 numeric; v_carton15 numeric; v_tape numeric; v_cap19_cutover date; v_sticker numeric;
  v_cost500 numeric; v_cost15 numeric; v_cost6 numeric;
  v_rev500 numeric:=0; v_rev15 numeric:=0; v_rev6 numeric:=0;
  v_sold500 numeric:=0; v_sold15 numeric:=0; v_sold6 numeric:=0;
  v_return500 numeric:=0; v_return15 numeric:=0; v_return6 numeric:=0;
  v_labor500 numeric:=0; v_labor15 numeric:=0; v_labor6 numeric:=0;
  v_support_labor numeric:=0; v_exp19 numeric:=0; v_exp_products numeric:=0; v_exp_general numeric:=0;
  v_other_income numeric:=0; v_interest_income numeric:=0; v_interest_expense numeric:=0;
  v_depreciation numeric:=0; v_inventory_loss numeric:=0;
  v_owner1 numeric:=0; v_owner2 numeric:=0; v_owner3 numeric:=0; v_owner4 numeric:=0;
  v_capital numeric:=0; v_loan_received numeric:=0; v_loan_repaid numeric:=0;
  v_loan_given numeric:=0; v_loan_collected numeric:=0;
  v_raw_purchase_period numeric:=0; v_tanker_purchase_period numeric:=0;
  v_used_water numeric:=0; v_water_cost numeric:=0; v_cap_cost numeric:=0;
  v_revenue19 numeric:=0; v_profit19 numeric:=0; v_product_revenue numeric:=0;
  v_product_cogs numeric:=0; v_return_loss numeric:=0; v_production_labor numeric:=0;
  v_profit_products numeric:=0; v_net numeric:=0;
  v_missing text[]:=array[]::text[];
  v_has_activity boolean:=false; v_has_pnl_activity boolean:=false;
  v_stock jsonb;
begin
  if p_month_start is null or p_month_end is null or p_month_start>p_month_end then
    raise exception 'درست ماہانہ تاریخ درکار ہے۔' using errcode='22023';
  end if;

  select
    coalesce((select sum(tanker_count*1000) from public.water_tanker_purchases where purchase_date<=p_month_end and water_use='shop_counter'),0)
      +coalesce((select sum(litres) from public.water_opening_stock where as_of_date<=p_month_end and water_use='shop_counter'),0),
    coalesce((select sum(total_amount) from public.water_tanker_purchases where purchase_date<=p_month_end and water_use='shop_counter'),0)
      +coalesce((select sum(total_value) from public.water_opening_stock where as_of_date<=p_month_end and water_use='shop_counter'),0),
    coalesce((select sum(total_amount) from public.water_tanker_purchases where purchase_date between p_month_start and p_month_end),0)
  into v_water_litres,v_water_amount,v_tanker_purchase_period;
  v_water_per_litre:=v_water_amount/nullif(v_water_litres,0);
  SELECT coalesce((SELECT sum(tanker_count*1000) FROM public.water_tanker_purchases WHERE purchase_date<=p_month_end AND water_use='product_filling'),0)+coalesce((SELECT sum(litres) FROM public.water_opening_stock WHERE as_of_date<=p_month_end AND water_use='product_filling'),0), coalesce((SELECT sum(total_amount) FROM public.water_tanker_purchases WHERE purchase_date<=p_month_end AND water_use='product_filling'),0)+coalesce((SELECT sum(total_value) FROM public.water_opening_stock WHERE as_of_date<=p_month_end AND water_use='product_filling'),0) INTO v_fill_water_litres,v_fill_water_amount;
  v_fill_water_rate:=v_fill_water_amount/nullif(v_fill_water_litres,0);
  v_shop_water_litres:=v_water_litres;
  v_shop_water_amount:=v_water_amount;
  v_shop_water_rate:=v_water_per_litre;

  select coalesce(sum(bottles_delivered),0),coalesce(sum(successful_bottles),0),coalesce(sum(damaged_caps),0),coalesce(sum(delivery_labor),0)
  into v_delivered,v_bottles,v_caps,v_delivery_labor
  from public.customer_19l_deliveries
  where delivery_date between p_month_start and p_month_end;

  select coalesce(sum(bottles_delivered),0),coalesce(sum(empty_bottles_returned),0),coalesce(sum(labor_amount),0)
  into v_unassigned_delivered,v_unassigned_successful,v_unassigned_labor
  from public.unassigned_19l_deliveries
  where delivery_date between p_month_start and p_month_end;

  select coalesce(sum(total_litres),0),coalesce(sum(total_amount),0)
  into v_counter_litres,v_counter_amount
  from public.counter_water_sales where sale_date between p_month_start and p_month_end;

  select sum(total_amount)/nullif(sum(quantity),0) into v_bottle500
  from public.raw_material_purchases where material_type='bottle_500ml' and purchase_date<=p_month_end;
  select sum(total_amount)/nullif(sum(quantity),0) into v_bottle15
  from public.raw_material_purchases where material_type='bottle_1_5l' and purchase_date<=p_month_end;
  select sum(total_amount)/nullif(sum(quantity),0) into v_bottle6
  from public.raw_material_purchases where material_type='bottle_6l' and purchase_date<=p_month_end;
  select sum(total_amount)/nullif(sum(quantity),0) into v_cap500
  from public.raw_material_purchases where material_type='cap_500ml' and purchase_date<=p_month_end;
  select sum(total_amount)/nullif(sum(quantity),0) into v_cap15
  from public.raw_material_purchases where material_type='cap_1_5l' and purchase_date<=p_month_end;
  select sum(total_amount)/nullif(sum(quantity),0) into v_cap6
  from public.raw_material_purchases where material_type='cap_6l' and purchase_date<=p_month_end;
  select sum(total_amount)/nullif(sum(quantity),0) into v_carton500
  from public.raw_material_purchases where material_type='carton_500ml' and purchase_date<=p_month_end;
  select sum(total_amount)/nullif(sum(quantity),0) into v_carton15
  from public.raw_material_purchases where material_type='carton_1_5l' and purchase_date<=p_month_end;
  select sum(total_amount)/nullif(sum(quantity),0) into v_tape
  from public.raw_material_purchases where material_type='tape_bundle' and purchase_date<=p_month_end;
  select min(purchase_date) into v_cap19_cutover
  from public.raw_material_purchases
  where material_type='cap_19l' and record_type='opening_stock';
  select sum(total_amount)/nullif(sum(quantity),0) into v_sticker
  from public.raw_material_purchases where material_type='sticker' and purchase_date<=p_month_end;
  -- Sticker cost remains unknown until an actual sticker opening stock or purchase is recorded.

  if v_bottle500 is not null and v_cap500 is not null and v_carton500 is not null and v_tape is not null and v_sticker is not null then
    v_cost500:=v_bottle500*24+v_cap500*24+v_carton500+v_tape/200+24*v_sticker;
  end if;
  if v_bottle15 is not null and v_cap15 is not null and v_carton15 is not null and v_tape is not null and v_sticker is not null then
    v_cost15:=v_bottle15*12+v_cap15*12+v_carton15+v_tape/200+12*v_sticker;
  end if;
  if v_bottle6 is not null and v_cap6 is not null and v_sticker is not null then v_cost6:=v_bottle6+v_cap6+v_sticker; end if;

  select
    coalesce(sum(total_amount) filter(where product_type='500ml'),0),
    coalesce(sum(total_amount) filter(where product_type='1.5L'),0),
    coalesce(sum(total_amount) filter(where product_type='6L'),0),
    coalesce(sum(quantity) filter(where product_type='500ml'),0),
    coalesce(sum(quantity) filter(where product_type='1.5L'),0),
    coalesce(sum(quantity) filter(where product_type='6L'),0)
  into v_rev500,v_rev15,v_rev6,v_sold500,v_sold15,v_sold6
  from public.product_sales where sale_date between p_month_start and p_month_end;

  select
    coalesce(sum(replacement_quantity) filter(where product_type='500ml'),0),
    coalesce(sum(replacement_quantity) filter(where product_type='1.5L'),0),
    coalesce(sum(replacement_quantity) filter(where product_type='6L'),0)
  into v_return500,v_return15,v_return6
  from public.product_returns where return_date between p_month_start and p_month_end;

  select
    coalesce((select sum(labor_amount)/nullif(sum(quantity),0) from public.production where product_type='500ml' and production_date<=p_month_end),(select labor_per_unit from public.product_settings where product_type='500ml'),0)*(v_sold500+v_return500/24),
    coalesce((select sum(labor_amount)/nullif(sum(quantity),0) from public.production where product_type='1.5L' and production_date<=p_month_end),(select labor_per_unit from public.product_settings where product_type='1.5L'),0)*(v_sold15+v_return15/12),
    coalesce((select sum(labor_amount)/nullif(sum(quantity),0) from public.production where product_type='6L' and production_date<=p_month_end),(select labor_per_unit from public.product_settings where product_type='6L'),0)*(v_sold6+v_return6)
  into v_labor500,v_labor15,v_labor6;

  select coalesce(sum(amount),0) into v_support_labor
  from public.worker_ledger
  where entry_date between p_month_start and p_month_end and entry_type='earning'
    and work_category in ('carton loading/unloading','cleaning','bottle washing','manual adjustment');

  select
    coalesce(sum(amount) filter(where business_segment='19L'),0),
    coalesce(sum(amount) filter(where business_segment='finished_goods'),0),
    coalesce(sum(amount) filter(where business_segment is null or business_segment='general'),0)
  into v_exp19,v_exp_products,v_exp_general
  from public.business_expenses where expense_date between p_month_start and p_month_end;

  select coalesce(sum(amount),0) into v_other_income
  from public.business_income where income_date between p_month_start and p_month_end;

  select
    coalesce(sum(amount) filter(where entry_type='interest_income'),0),
    coalesce(sum(amount) filter(where entry_type='interest_expense'),0),
    coalesce(sum(amount) filter(where entry_type='depreciation_expense'),0),
    coalesce(sum(amount) filter(where entry_type='inventory_loss'),0),
    coalesce(sum(amount) filter(where entry_type='owner_withdrawal' and counterparty IN ('محمد اسامہ مغل','M.Usama Mughal','M. Usama Mughal')),0),
    coalesce(sum(amount) filter(where entry_type='owner_withdrawal' and counterparty IN ('محمد مزمل مغل','M. Muzamil Mughal')),0),
    coalesce(sum(amount) filter(where entry_type='owner_withdrawal' and counterparty IN ('محمد تقی مغل','M.Taqi Mughal')),0),
    coalesce(sum(amount) filter(where entry_type='owner_withdrawal' and counterparty IN ('محمد رفیع مغل','M. Rafi Mughal')),0)
  into v_interest_income,v_interest_expense,v_depreciation,v_inventory_loss,
    v_owner1,v_owner2,v_owner3,v_owner4
  from public.business_finance_ledger where entry_date between p_month_start and p_month_end;

  select
    coalesce(sum(amount) filter(where entry_type='capital_in'),0),
    coalesce(sum(amount) filter(where entry_type='loan_received'),0),
    coalesce(sum(amount) filter(where entry_type='loan_repaid'),0),
    coalesce(sum(amount) filter(where entry_type='loan_given'),0),
    coalesce(sum(amount) filter(where entry_type='loan_collected'),0)
  into v_capital,v_loan_received,v_loan_repaid,v_loan_given,v_loan_collected
  from public.business_finance_ledger where entry_date<=p_month_end;

  select coalesce(sum(total_amount),0) into v_raw_purchase_period
  from public.raw_material_purchases where purchase_date between p_month_start and p_month_end and record_type='purchase';

  v_used_water:=(v_delivered+v_unassigned_delivered)*19;
  v_fill_water_used:=coalesce((SELECT sum(quantity*CASE product_type WHEN '500ml' THEN 12 WHEN '1.5L' THEN 18 ELSE 0 END) FROM public.product_sales WHERE sale_date BETWEEN p_month_start AND p_month_end),0)+coalesce((SELECT sum(replacement_quantity*CASE product_type WHEN '500ml' THEN 0.5 WHEN '1.5L' THEN 1.5 ELSE 0 END) FROM public.product_returns WHERE return_date BETWEEN p_month_start AND p_month_end),0);
  v_shop_water_used:=v_counter_litres+coalesce((SELECT sum(quantity*6) FROM public.product_sales WHERE product_type='6L' AND sale_date BETWEEN p_month_start AND p_month_end),0)+coalesce((SELECT sum(replacement_quantity*6) FROM public.product_returns WHERE product_type='6L' AND return_date BETWEEN p_month_start AND p_month_end),0);
  v_water_cost:=v_used_water*coalesce(v_water_per_litre,0);
  select coalesce(sum(q.caps_used * coalesce((
    select sum(r.total_amount)/nullif(sum(r.quantity),0)
    from public.raw_material_purchases r
    where r.material_type='cap_19l' and r.purchase_date<=q.usage_date
  ),0)),0)
  into v_cap_cost
  from (
    select d.delivery_date as usage_date, sum(d.damaged_caps) as caps_used
    from public.customer_19l_deliveries d
    where d.delivery_date between p_month_start and p_month_end
    group by d.delivery_date
    union all
    select d.delivery_date, sum(d.damaged_caps)
    from public.unassigned_19l_deliveries d
    where d.delivery_date between p_month_start and p_month_end
    group by d.delivery_date
  ) q;
  v_revenue19:=v_bottles*100+v_unassigned_successful*100+v_caps*10+v_counter_amount;
  v_profit19:=v_revenue19-v_water_cost-v_cap_cost-v_delivery_labor-v_unassigned_labor-v_exp19-v_counter_litres*coalesce(v_shop_water_rate,0);
  v_product_revenue:=v_rev500+v_rev15+v_rev6;
  v_product_cogs:=v_sold500*coalesce(v_cost500,0)+v_sold15*coalesce(v_cost15,0)+v_sold6*coalesce(v_cost6,0);
  v_return_loss:=v_return500*coalesce(v_cost500,0)/24+v_return15*coalesce(v_cost15,0)/12+v_return6*coalesce(v_cost6,0);
  v_production_labor:=v_labor500+v_labor15+v_labor6;
  v_profit_products:=v_product_revenue-v_product_cogs-v_return_loss-v_production_labor-v_support_labor-v_exp_products-v_fill_water_used*coalesce(v_fill_water_rate,0)-(v_shop_water_used-v_counter_litres)*coalesce(v_shop_water_rate,0);
  v_net:=v_profit19+v_profit_products+v_other_income+v_interest_income-v_exp_general-v_interest_expense-v_depreciation-v_inventory_loss;

  if v_used_water>0 and v_water_per_litre is null then v_missing:=array_append(v_missing,'ٹینکر خریداری'); end if;
  if exists (
    select 1
    from (
      select d.delivery_date as usage_date, sum(d.damaged_caps) as caps_used
      from public.customer_19l_deliveries d
      where d.delivery_date between p_month_start and p_month_end
      group by d.delivery_date
      union all
      select d.delivery_date, sum(d.damaged_caps)
      from public.unassigned_19l_deliveries d
      where d.delivery_date between p_month_start and p_month_end
      group by d.delivery_date
    ) q
    where q.caps_used>0
      and not exists (
        select 1 from public.raw_material_purchases r
        where r.material_type='cap_19l' and r.purchase_date<=q.usage_date
      )
  ) then v_missing:=array_append(v_missing,'19L ڈھکن خریداری'); end if;
  if v_sold500+v_return500>0 and v_cost500 is null then v_missing:=array_append(v_missing,'500ml خام مال / پیکنگ'); end if;
  if v_sold15+v_return15>0 and v_cost15 is null then v_missing:=array_append(v_missing,'1.5L خام مال / پیکنگ'); end if;
  if v_sold6+v_return6>0 and v_cost6 is null then v_missing:=array_append(v_missing,'6L بوتل'); end if;
  if v_fill_water_used>0 and v_fill_water_rate is null then v_missing:=array_append(v_missing,'500ml / 1.5L فلنگ پانی کی خریداری یا ابتدائی اسٹاک'); end if;
  if v_shop_water_used>0 and v_shop_water_rate is null then v_missing:=array_append(v_missing,'6L / کاؤنٹر پانی کی خریداری یا ابتدائی اسٹاک'); end if;


  select exists(
    select 1 from public.customer_19l_deliveries where delivery_date between p_month_start and p_month_end
    union all select 1 from public.unassigned_19l_deliveries where delivery_date between p_month_start and p_month_end
    union all select 1 from public.counter_water_sales where sale_date between p_month_start and p_month_end
    union all select 1 from public.product_sales where sale_date between p_month_start and p_month_end
    union all select 1 from public.product_returns where return_date between p_month_start and p_month_end
    union all select 1 from public.business_expenses where expense_date between p_month_start and p_month_end
    union all select 1 from public.business_income where income_date between p_month_start and p_month_end
    union all select 1 from public.production where production_date between p_month_start and p_month_end
    union all select 1 from public.raw_material_purchases where purchase_date between p_month_start and p_month_end
    union all select 1 from public.water_tanker_purchases where purchase_date between p_month_start and p_month_end
    union all select 1 from public.water_opening_stock where as_of_date between p_month_start and p_month_end
    union all select 1 from public.finished_goods where entry_date between p_month_start and p_month_end
    union all select 1 from public.finished_stock_adjustments where adjustment_date between p_month_start and p_month_end
    union all select 1 from public.business_finance_ledger where entry_date between p_month_start and p_month_end
    union all select 1 from public.worker_ledger where entry_date between p_month_start and p_month_end
  ) into v_has_activity;
  select exists(
    select 1 from public.customer_19l_deliveries where delivery_date between p_month_start and p_month_end
    union all select 1 from public.unassigned_19l_deliveries where delivery_date between p_month_start and p_month_end
    union all select 1 from public.counter_water_sales where sale_date between p_month_start and p_month_end
    union all select 1 from public.product_sales where sale_date between p_month_start and p_month_end
    union all select 1 from public.product_returns where return_date between p_month_start and p_month_end
    union all select 1 from public.business_expenses where expense_date between p_month_start and p_month_end
    union all select 1 from public.business_income where income_date between p_month_start and p_month_end
    union all select 1 from public.production where production_date between p_month_start and p_month_end
    union all select 1 from public.worker_ledger where entry_date between p_month_start and p_month_end and entry_type='earning'
    union all select 1 from public.business_finance_ledger where entry_date between p_month_start and p_month_end
      and entry_type in ('interest_income','interest_expense','depreciation_expense','inventory_loss')
  ) into v_has_pnl_activity;

  select jsonb_build_object(
    'water_litres',coalesce((select sum(tanker_count*1000) from public.water_tanker_purchases where purchase_date<=p_month_end),0)
      +coalesce((select sum(litres) from public.water_opening_stock where as_of_date<=p_month_end),0)
      -(coalesce((select sum(bottles_delivered) from public.customer_19l_deliveries where delivery_date<=p_month_end),0)*19
        +coalesce((select sum(bottles_delivered)*19 from public.unassigned_19l_deliveries where delivery_date<=p_month_end),0)
        +coalesce((select sum(total_litres) from public.counter_water_sales where sale_date<=p_month_end),0)
        +coalesce((select sum(quantity*CASE product_type WHEN '500ml' THEN 12 WHEN '1.5L' THEN 18 ELSE 0 END) from public.production where production_date<=p_month_end),0)
        +coalesce((select sum(quantity*6) from public.production where product_type='6L' and production_date<=p_month_end),0)),
    
    'water_shop_pool_litres',
      coalesce((select sum(tanker_count*1000) from public.water_tanker_purchases where purchase_date<=p_month_end and water_use='shop_counter'),0)
      +coalesce((select sum(litres) from public.water_opening_stock where as_of_date<=p_month_end and water_use='shop_counter'),0)
      -(coalesce((select sum(bottles_delivered)*19 from public.customer_19l_deliveries where delivery_date<=p_month_end),0)
        +coalesce((select sum(bottles_delivered)*19 from public.unassigned_19l_deliveries where delivery_date<=p_month_end),0)
        +coalesce((select sum(total_litres) from public.counter_water_sales where sale_date<=p_month_end),0)
        +coalesce((select sum(quantity*6) from public.production where product_type='6L' and production_date<=p_month_end),0)),
    'water_product_filling_litres',
      coalesce((select sum(tanker_count*1000) from public.water_tanker_purchases where purchase_date<=p_month_end and water_use='product_filling'),0)
      +coalesce((select sum(litres) from public.water_opening_stock where as_of_date<=p_month_end and water_use='product_filling'),0)
      -coalesce((select sum(quantity*case product_type when '500ml' then 12 when '1.5L' then 18 else 0 end) from public.production where production_date<=p_month_end),0),
    'water_shop_pool_remaining_litres',
      coalesce((select sum(tanker_count*1000) from public.water_tanker_purchases where purchase_date<=p_month_end and water_use='shop_counter'),0)
      +coalesce((select sum(litres) from public.water_opening_stock where as_of_date<=p_month_end and water_use='shop_counter'),0)
      -coalesce((select sum(bottles_delivered)*19 from public.customer_19l_deliveries where delivery_date<=p_month_end),0)
      -coalesce((select sum(bottles_delivered)*19 from public.unassigned_19l_deliveries where delivery_date<=p_month_end),0)
      -coalesce((select sum(total_litres) from public.counter_water_sales where sale_date<=p_month_end),0)
      -coalesce((select sum(quantity*6) from public.production where product_type='6L' and production_date<=p_month_end),0),
    'raw_19l_caps',
      coalesce((select sum(r.quantity) from public.raw_material_purchases r
        where r.material_type='cap_19l' and r.purchase_date<=p_month_end
          and (v_cap19_cutover is null or p_month_end<v_cap19_cutover
            or r.record_type='opening_stock' or r.purchase_date>=v_cap19_cutover)),0)
      -coalesce((select sum(d.damaged_caps) from public.customer_19l_deliveries d
        where d.delivery_date<=p_month_end
          and (v_cap19_cutover is null or p_month_end<v_cap19_cutover or d.delivery_date>=v_cap19_cutover)),0)
      -coalesce((select sum(d.damaged_caps) from public.unassigned_19l_deliveries d
        where d.delivery_date<=p_month_end
          and (v_cap19_cutover is null or p_month_end<v_cap19_cutover or d.delivery_date>=v_cap19_cutover)),0)
      -coalesce((select sum(quantity) from public.production where product_type='500ml' and production_date<=p_month_end),0)*24,
    'raw_500ml_caps',coalesce((select sum(quantity) from public.raw_material_purchases where material_type='cap_500ml' and purchase_date<=p_month_end),0)
      -coalesce((select sum(quantity) from public.production where product_type='500ml' and production_date<=p_month_end),0)*24,
    'raw_1_5l_bottles',coalesce((select sum(quantity) from public.raw_material_purchases where material_type='bottle_1_5l' and purchase_date<=p_month_end),0)
      -coalesce((select sum(quantity) from public.production where product_type='1.5L' and production_date<=p_month_end),0)*12,
    'raw_1_5l_caps',coalesce((select sum(quantity) from public.raw_material_purchases where material_type='cap_1_5l' and purchase_date<=p_month_end),0)
      -coalesce((select sum(quantity) from public.production where product_type='1.5L' and production_date<=p_month_end),0)*12,
    'raw_6l_bottles',coalesce((select sum(quantity) from public.raw_material_purchases where material_type='bottle_6l' and purchase_date<=p_month_end),0)
      -coalesce((select sum(quantity) from public.production where product_type='6L' and production_date<=p_month_end),0),
    'raw_6l_caps',coalesce((select sum(quantity) from public.raw_material_purchases where material_type='cap_6l' and purchase_date<=p_month_end),0)
      -coalesce((select sum(quantity) from public.production where product_type='6L' and production_date<=p_month_end),0),
    'cartons_500ml',coalesce((select sum(quantity) from public.raw_material_purchases where material_type='carton_500ml' and purchase_date<=p_month_end),0)
      -coalesce((select sum(quantity) from public.production where product_type='500ml' and production_date<=p_month_end),0),
    'cartons_1_5l',coalesce((select sum(quantity) from public.raw_material_purchases where material_type='carton_1_5l' and purchase_date<=p_month_end),0)
      -coalesce((select sum(quantity) from public.production where product_type='1.5L' and production_date<=p_month_end),0),
    'tape_bundles',coalesce((select sum(quantity) from public.raw_material_purchases where material_type='tape_bundle' and purchase_date<=p_month_end),0)
      -(coalesce((select sum(quantity) from public.production where product_type='500ml' and production_date<=p_month_end),0)::numeric
        +coalesce((select sum(quantity) from public.production where product_type='1.5L' and production_date<=p_month_end),0)::numeric)/200,
    'stickers',coalesce((select sum(quantity) from public.raw_material_purchases where material_type='sticker' and purchase_date<=p_month_end),0)
      -(coalesce((select sum(quantity) from public.production where product_type='500ml' and production_date<=p_month_end),0)*24
        +coalesce((select sum(quantity) from public.production where product_type='1.5L' and production_date<=p_month_end),0)*12
        +coalesce((select sum(quantity) from public.production where product_type='6L' and production_date<=p_month_end),0)),
    'finished_500ml_cartons',coalesce((select sum(quantity) from public.finished_goods where product_type='500ml' and unit='carton' and entry_date<=p_month_end),0)
      +coalesce((select sum(quantity) from public.production where product_type='500ml' and production_date<=p_month_end),0)
      -coalesce((select sum(quantity) from public.product_sales where product_type='500ml' and sale_date<=p_month_end),0)
      -coalesce((select sum(replacement_quantity) from public.product_returns where product_type='500ml' and return_date<=p_month_end),0)::numeric/24
      +coalesce((select sum(case when adjustment_type='increase' then quantity when adjustment_type='decrease' then -quantity else 0 end) from public.finished_stock_adjustments where product_type='500ml' and adjustment_date<=p_month_end),0),
    'finished_1_5l_cartons',coalesce((select sum(quantity) from public.finished_goods where product_type='1.5L' and unit='carton' and entry_date<=p_month_end),0)
      +coalesce((select sum(quantity) from public.production where product_type='1.5L' and production_date<=p_month_end),0)
      -coalesce((select sum(quantity) from public.product_sales where product_type='1.5L' and sale_date<=p_month_end),0)
      -coalesce((select sum(replacement_quantity) from public.product_returns where product_type='1.5L' and return_date<=p_month_end),0)::numeric/12
      +coalesce((select sum(case when adjustment_type='increase' then quantity when adjustment_type='decrease' then -quantity else 0 end) from public.finished_stock_adjustments where product_type='1.5L' and adjustment_date<=p_month_end),0),
    'finished_6l_bottles',coalesce((select sum(quantity) from public.finished_goods where product_type='6L' and unit='bottle' and entry_date<=p_month_end),0)
      +coalesce((select sum(quantity) from public.production where product_type='6L' and production_date<=p_month_end),0)
      -coalesce((select sum(quantity) from public.product_sales where product_type='6L' and sale_date<=p_month_end),0)
      -coalesce((select sum(replacement_quantity) from public.product_returns where product_type='6L' and return_date<=p_month_end),0)
      +coalesce((select sum(case when adjustment_type='increase' then quantity when adjustment_type='decrease' then -quantity else 0 end) from public.finished_stock_adjustments where product_type='6L' and adjustment_date<=p_month_end),0)
  ) into v_stock;

  return jsonb_build_object(
    'month_start',p_month_start,'month_end',p_month_end,'generated_at',now(),
    'has_activity',v_has_activity,'has_pnl_activity',v_has_pnl_activity,'complete',cardinality(v_missing)=0,'missing_costs',to_jsonb(v_missing),
    'segments',jsonb_build_object(
      '19L',jsonb_build_object('revenue',v_revenue19,'water_cost',v_water_cost,'counter_water_cost',v_counter_litres*coalesce(v_shop_water_rate,0),'counter_water_litres',v_counter_litres,'water_rate_per_litre',v_water_per_litre,'cap_cost',v_cap_cost,
        'delivery_labor',v_delivery_labor+v_unassigned_labor,
        'unassigned_bottles',v_unassigned_delivered,'unassigned_successful_bottles',v_unassigned_successful,
        'unassigned_delivery_labor',v_unassigned_labor,
        'segment_expenses',v_exp19,'profit_before_shared',v_profit19),
      'finished_goods',jsonb_build_object('revenue',v_product_revenue,'material_packaging_cost',v_product_cogs,'filling_water_litres',v_fill_water_used,'filling_water_cost',v_fill_water_used*coalesce(v_fill_water_rate,0),'shop_water_cost_for_6l',(v_shop_water_used-v_counter_litres)*coalesce(v_shop_water_rate,0),
        'replacement_loss',v_return_loss,'production_labor',v_production_labor,'support_labor',v_support_labor,
        'segment_expenses',v_exp_products,'profit_before_shared',v_profit_products),
      'shared',jsonb_build_object('general_expenses',v_exp_general,'interest_expense',v_interest_expense,
        'depreciation',v_depreciation,'inventory_loss',v_inventory_loss,'other_income',v_other_income+v_interest_income),
      'net_profit',v_net
    ),
    'products',jsonb_build_object(
      '500ml',jsonb_build_object('revenue',v_rev500,'quantity',v_sold500,'unit_cost',v_cost500,
        'material_cost',v_sold500*coalesce(v_cost500,0),'returns',v_return500,'return_loss',v_return500*coalesce(v_cost500,0)/24,'production_labor',v_labor500),
      '1.5L',jsonb_build_object('revenue',v_rev15,'quantity',v_sold15,'unit_cost',v_cost15,
        'material_cost',v_sold15*coalesce(v_cost15,0),'returns',v_return15,'return_loss',v_return15*coalesce(v_cost15,0)/12,'production_labor',v_labor15),
      '6L',jsonb_build_object('revenue',v_rev6,'quantity',v_sold6,'unit_cost',v_cost6,
        'material_cost',v_sold6*coalesce(v_cost6,0),'returns',v_return6,'return_loss',v_return6*coalesce(v_cost6,0),'production_labor',v_labor6)
    ),
    'owner_withdrawals',jsonb_build_object(
      'M.Usama Mughal',v_owner1,'M. Muzamil Mughal',v_owner2,'M.Taqi Mughal',v_owner3,'M. Rafi Mughal',v_owner4,
      'total',v_owner1+v_owner2+v_owner3+v_owner4),
    'capital_and_loans',jsonb_build_object('capital',v_capital,'loan_received',v_loan_received,
      'loan_repaid',v_loan_repaid,'loan_balance',v_loan_received-v_loan_repaid,
      'loan_given',v_loan_given,'loan_collected',v_loan_collected,'receivable_balance',v_loan_given-v_loan_collected),
    'purchases',jsonb_build_object('raw_material_period',v_raw_purchase_period,'water_tanker_period',v_tanker_purchase_period),
    'stock_estimate',v_stock,
    'notes','اسٹاک کا اندازہ کلیم کے بدلے مفت آنے والی بوتلوں کے بغیر ہے؛ ان کی مقدار درج نہ ہونے سے خام مال کا اسٹاک اندازاً ہوگا۔'
  );
end;
$function$
;

DO $migration_check$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.unassigned_19l_deliveries d
    LEFT JOIN public.worker_ledger l
      ON l.source_table='unassigned_19l_deliveries'
     AND l.source_id=d.id
     AND l.entry_type='earning'
    WHERE coalesce(l.amount,0) <> d.labor_amount
  ) THEN
    RAISE EXCEPTION 'Unassigned delivery labor and worker ledger do not reconcile; aborting migration.';
  END IF;
END;
$migration_check$;
