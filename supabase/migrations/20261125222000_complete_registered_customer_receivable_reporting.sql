CREATE OR REPLACE FUNCTION private.get_management_dashboard(p_month_start date, p_month_end date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_report jsonb;
  v_previous jsonb;
  v_due numeric(14,2):=0;
  v_registered_customer_due numeric(14,2):=0;
  v_due_customers integer:=0;
  v_active_customers integer:=0;
  v_unbilled_customers integer:=0;
  v_collections numeric(14,2):=0;
  v_cash_out numeric(14,2):=0;
  v_unassigned_due numeric(14,2):=0;
  v_monthly_account_due numeric(14,2):=0;
  v_pending_review_due numeric(14,2):=0;
  v_store_credit_due numeric(14,2):=0;
  v_store_credit_collections numeric(14,2):=0;
  v_bottle_deposit_held numeric(14,2):=0;
  v_bottle_deposit_received numeric(14,2):=0;
  v_bottle_deposit_refunded numeric(14,2):=0;
  v_worker_payables numeric(14,2):=0;
  v_loan_payables numeric(14,2):=0;
  v_payables numeric(14,2):=0;
  v_owner_withdrawals numeric(14,2):=0;
  v_closed boolean:=false;
  v_prev_start date;
  v_prev_end date;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'صرف مالکین/ایڈمن ڈیش بورڈ دیکھ سکتے ہیں۔' using errcode='42501';
  end if;
  if p_month_start is null or p_month_end is null or p_month_start>p_month_end then
    raise exception 'رپورٹ کی تاریخیں درست منتخب کریں۔' using errcode='22023';
  end if;

  v_report:=public.build_business_monthly_report(p_month_start,p_month_end);
  v_prev_start:=(date_trunc('month',p_month_start)::date-interval '1 month')::date;
  v_prev_end:=(v_prev_start+interval '1 month - 1 day')::date;
  v_previous:=public.build_business_monthly_report(v_prev_start,v_prev_end);

  select count(*) into v_active_customers from public.customers where is_active=true;
  select count(*) into v_unbilled_customers
  from public.customers c
  where (
    (
      c.is_active=true
      and coalesce(c.approved_at,c.created_at) < ((p_month_end + 1)::timestamp at time zone 'Asia/Karachi')
    )
    or (
      c.approved_at is not null
      and c.approved_at < ((p_month_end + 1)::timestamp at time zone 'Asia/Karachi')
      and (
        exists(select 1 from public.customer_monthly_bills prior_bill
          where prior_bill.customer_id=c.id
            and prior_bill.bill_month<date_trunc('month',p_month_start)::date)
        or exists(select 1 from public.customer_19l_deliveries d
          where d.customer_id=c.id and d.delivery_date between p_month_start and p_month_end)
        or exists(select 1 from public.customer_payments p
          where p.customer_id=c.id and p.payment_date between p_month_start and p_month_end)
      )
    )
  )
  and not exists(select 1 from public.customer_monthly_bills b
    where b.customer_id=c.id and b.bill_month=date_trunc('month',p_month_start)::date);

  select coalesce(sum(current_due),0),count(*) filter(where current_due>0)
    into v_registered_customer_due,v_due_customers
  from (
    select distinct on(customer_id) customer_id,current_due
    from public.customer_monthly_bills
    where bill_month<=date_trunc('month',p_month_end)::date
    order by customer_id,bill_month desc
  ) latest;
  v_due:=v_registered_customer_due;

  SELECT greatest(
    coalesce((SELECT sum(d.bottles_delivered::numeric*100+d.damaged_caps::numeric*10)
      FROM public.unassigned_19l_deliveries d
      WHERE d.customer_classification='one_time' AND d.delivery_date<=p_month_end),0)
    - coalesce((SELECT sum(c.amount) FROM public.unassigned_19l_delivery_collections c
      JOIN public.unassigned_19l_deliveries d ON d.id=c.delivery_id
      WHERE d.customer_classification='one_time' AND c.received_date<=p_month_end),0),0)
  INTO v_unassigned_due;

  SELECT coalesce(sum(greatest(
    coalesce((SELECT sum(d.bottles_delivered::numeric*100+d.damaged_caps::numeric*10)
      FROM public.unassigned_19l_deliveries d
      WHERE d.monthly_customer_id=mc.id
        AND d.customer_classification='monthly' AND d.delivery_date<=p_month_end),0)
    - private.unregistered_monthly_customer_paid_before(mc.id,p_month_end+1),0
  )),0)
  INTO v_monthly_account_due
  FROM public.unregistered_monthly_customers mc
  WHERE mc.created_at < ((p_month_end+1)::timestamp at time zone 'Asia/Karachi');

  SELECT greatest(
    coalesce((SELECT sum(d.bottles_delivered::numeric*100+d.damaged_caps::numeric*10)
      FROM public.unassigned_19l_deliveries d
      WHERE d.customer_classification='monthly_pending_review' AND d.delivery_date<=p_month_end),0)
    - coalesce((SELECT sum(c.amount) FROM public.unassigned_19l_delivery_collections c
      JOIN public.unassigned_19l_deliveries d ON d.id=c.delivery_id
      WHERE d.customer_classification='monthly_pending_review' AND c.received_date<=p_month_end),0),0)
  INTO v_pending_review_due;

  SELECT coalesce(sum(greatest(ps.total_amount-coalesce(paid.total_paid,0),0)),0)
    INTO v_store_credit_due
  FROM public.product_sales ps
  LEFT JOIN LATERAL (
    SELECT sum(p.amount) AS total_paid
    FROM public.store_credit_payments p
    WHERE p.sale_id=ps.id AND p.payment_date<=p_month_end
  ) paid ON true
  WHERE ps.payment_method='credit' AND ps.sale_date<=p_month_end;

  v_due:=v_due+v_unassigned_due+v_monthly_account_due+v_pending_review_due+v_store_credit_due
    +greatest(coalesce((v_report->'capital_and_loans'->>'receivable_balance')::numeric,0),0);

  SELECT
    coalesce(sum(total_amount) FILTER(WHERE transaction_type='deposit_received'),0),
    coalesce(sum(total_amount) FILTER(WHERE transaction_type='deposit_refunded'),0)
    INTO v_bottle_deposit_received,v_bottle_deposit_refunded
  FROM public.customer_bottle_deposit_ledger
  WHERE transaction_date<=p_month_end;
  v_bottle_deposit_held:=v_bottle_deposit_received-v_bottle_deposit_refunded;

  select
    coalesce((select sum(case when payment_type='refund' then -amount else amount end)
      from public.customer_payments where payment_date between p_month_start and p_month_end),0)
    +coalesce((select sum(total_amount) from public.customer_bottle_deposit_ledger
      where transaction_type='deposit_received' and transaction_date between p_month_start and p_month_end),0)
    +coalesce((select sum(total_amount) from public.product_sales where sale_date between p_month_start and p_month_end and payment_method<>'credit'),0)
    +coalesce((select sum(amount) from public.store_credit_payments where payment_date between p_month_start and p_month_end),0)
    +coalesce((select sum(total_amount) from public.counter_water_sales where sale_date between p_month_start and p_month_end),0)
    +coalesce((select sum(amount) from public.business_income where income_date between p_month_start and p_month_end),0)
    +coalesce((select sum(amount) from public.business_finance_ledger
      where entry_date between p_month_start and p_month_end
        and entry_type in ('capital_in','loan_received','loan_collected','fixed_asset_sale','interest_income')),0)
    +coalesce((select sum(greatest(r.amount-coalesce((
        select sum(c.amount)
        from jsonb_array_elements(coalesce(r.allocations,'[]'::jsonb)) a
        join public.unassigned_19l_delivery_collections c
          on c.id=(a->>'collection_id')::bigint
      ),0),0))
      from private.unregistered_monthly_customer_receipts r
      where r.received_date between p_month_start and p_month_end),0)
    into v_collections;

  select
    coalesce((select sum(amount) from public.business_expenses where expense_date between p_month_start and p_month_end),0)
    +coalesce((select sum(total_amount) from public.raw_material_purchases where purchase_date between p_month_start and p_month_end and record_type='purchase'),0)
    +coalesce((select sum(total_amount) from public.water_tanker_purchases where purchase_date between p_month_start and p_month_end),0)
    +coalesce((select sum(amount) from public.labor_payments where payment_date between p_month_start and p_month_end),0)
    +coalesce((select sum(amount) from public.worker_ledger
      where entry_date between p_month_start and p_month_end
        and entry_type in ('payment','advance')
        and coalesce(source_table,'')<>'labor_payments'),0)
    +coalesce((select sum(amount) from public.business_finance_ledger
      where entry_date between p_month_start and p_month_end
        and entry_type in ('owner_withdrawal','loan_repaid','loan_given','inventory_purchase','fixed_asset_purchase','interest_expense')),0)
    +coalesce((select sum(total_amount) from public.customer_bottle_deposit_ledger
      where transaction_type='deposit_refunded' and transaction_date between p_month_start and p_month_end),0)
    into v_cash_out;

  SELECT greatest(coalesce(sum(CASE
      WHEN entry_type='earning' THEN amount
      WHEN entry_type IN ('payment','advance','deduction') THEN -amount
      ELSE 0 END),0),0)
    INTO v_worker_payables
  FROM public.worker_ledger WHERE entry_date<=p_month_end;
  v_loan_payables:=greatest(coalesce((v_report->'capital_and_loans'->>'loan_balance')::numeric,0),0);
  v_payables:=v_worker_payables+v_loan_payables;

  select coalesce(sum(amount),0) into v_owner_withdrawals
  from public.business_finance_ledger
  where entry_date between p_month_start and p_month_end and entry_type='owner_withdrawal';

  select exists(select 1 from public.business_month_closings where month_start=date_trunc('month',p_month_start)::date)
    into v_closed;

  return jsonb_build_object(
    'period',jsonb_build_object('start',p_month_start,'end',p_month_end),
    'profit_and_loss',v_report,'previous_period',v_previous,
    'active_customers',v_active_customers,'unbilled_customers',v_unbilled_customers,
    'customers_with_due',v_due_customers,'receivables',v_due,
    'registered_customer_receivables',v_registered_customer_due,
    'unassigned_receivables',v_unassigned_due,
    'monthly_unregistered_receivables',v_monthly_account_due,
    'historical_pending_19l_receivables',v_pending_review_due,
    'store_credit_receivables',v_store_credit_due,
    'store_credit_collections',coalesce((select sum(amount) from public.store_credit_payments where payment_date between p_month_start and p_month_end),0),
    'customer_bottle_deposit_held',v_bottle_deposit_held,
    'customer_bottle_deposit_received',coalesce((select sum(total_amount) from public.customer_bottle_deposit_ledger
      where transaction_type='deposit_received' and transaction_date between p_month_start and p_month_end),0),
    'customer_bottle_deposit_refunded',coalesce((select sum(total_amount) from public.customer_bottle_deposit_ledger
      where transaction_type='deposit_refunded' and transaction_date between p_month_start and p_month_end),0),
    'payables',v_payables,'worker_payables',v_worker_payables,'loan_payables',v_loan_payables,
    'recorded_collections',v_collections,'recorded_cash_outflows',v_cash_out,
    'recorded_net_cash_movement',v_collections-v_cash_out,
    'owner_withdrawals',v_owner_withdrawals,'month_closed',v_closed,
    'cash_balance_available',false,
    'cash_balance_note','ابتدائی نقد/بینک بیلنس اور مکمل بینک ریکنسیلی ایشن موجود نہیں؛ اس لیے نقد بیلنس نہیں دکھایا جاتا۔',
    'quality_flags',jsonb_build_array('یہ انتظامی رپورٹ ہے، مکمل IFRS یا دوہری اندراج جنرل لیجر نہیں۔')
  );
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
  v_bottles numeric:=0; v_caps numeric:=0; v_unassigned_caps numeric:=0; v_delivery_labor numeric:=0;
  v_counter_litres numeric:=0; v_counter_amount numeric:=0;
  v_bottle500 numeric; v_bottle15 numeric; v_bottle6 numeric; v_cap500 numeric; v_cap15 numeric; v_cap6 numeric;
  v_carton500 numeric; v_carton15 numeric; v_tape numeric; v_cap19_cutover date; v_sticker numeric;
  v_sticker500 numeric; v_sticker_shared numeric;
  v_cost500 numeric; v_cost15 numeric; v_cost6 numeric;
  v_rev500 numeric:=0; v_rev15 numeric:=0; v_rev6 numeric:=0;
  v_sold500 numeric:=0; v_sold15 numeric:=0; v_sold6 numeric:=0;
  v_return500 numeric:=0; v_return15 numeric:=0; v_return6 numeric:=0;
  v_labor500 numeric:=0; v_labor15 numeric:=0; v_labor6 numeric:=0;
  v_labor_rate500 numeric:=0; v_labor_rate15 numeric:=0; v_labor_rate6 numeric:=0;
  v_support_labor numeric:=0; v_exp19 numeric:=0; v_exp_products numeric:=0; v_exp_general numeric:=0;
  v_other_income numeric:=0; v_interest_income numeric:=0; v_interest_expense numeric:=0;
  v_depreciation numeric:=0; v_inventory_loss numeric:=0; v_finished_stock_loss numeric:=0;
  v_owner1 numeric:=0; v_owner2 numeric:=0; v_owner3 numeric:=0; v_owner4 numeric:=0;
  v_capital numeric:=0; v_loan_received numeric:=0; v_loan_repaid numeric:=0;
  v_loan_given numeric:=0; v_loan_collected numeric:=0;
  v_raw_purchase_period numeric:=0; v_tanker_purchase_period numeric:=0;
  v_used_water numeric:=0; v_water_cost numeric:=0; v_cap_cost numeric:=0;
  v_revenue19 numeric:=0; v_profit19 numeric:=0; v_product_revenue numeric:=0; v_unassigned_receipts numeric:=0; v_unassigned_unclassified numeric:=0; v_monthly_account_receipts numeric:=0; v_monthly_account_receivable numeric:=0; v_pending_review_receipts numeric:=0; v_pending_review_receivable numeric:=0; v_registered_customer_receipts numeric:=0; v_registered_customer_receivable numeric:=0;
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

  select coalesce(sum(bottles_delivered),0),coalesce(sum(bottles_delivered),0),coalesce(sum(labor_amount),0),coalesce(sum(damaged_caps),0)
  into v_unassigned_delivered,v_unassigned_successful,v_unassigned_labor,v_unassigned_caps
  from public.unassigned_19l_deliveries
  where delivery_date between p_month_start and p_month_end;

  select
    coalesce(sum(private.mpw_counter_water_litres(c.sale_date,c.total_litres,c.counter_water_litres)),0),
    coalesce(sum(c.total_amount),0)
  into v_counter_litres,v_counter_amount
  from public.counter_water_sales c where c.sale_date between p_month_start and p_month_end;

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
  select sum(total_amount)/nullif(sum(quantity*1900),0) into v_sticker500
  from public.raw_material_purchases where material_type='sticker_500ml' and purchase_date<=p_month_end;
  select sum(total_amount)/nullif(sum(quantity*1100),0) into v_sticker_shared
  from public.raw_material_purchases where material_type='sticker_1_5l_6l' and purchase_date<=p_month_end;
  v_sticker500:=coalesce(v_sticker500,v_sticker);
  v_sticker_shared:=coalesce(v_sticker_shared,v_sticker);
  -- Shared 1.5L/6L sticker yield is 1,100 pieces per kilogram (33 pieces per 30 grams); production consumes 12 per 1.5L carton and 1 per 6L bottle.

  if v_bottle500 is not null and v_cap500 is not null and v_carton500 is not null and v_sticker500 is not null and v_tape is not null then
    v_cost500:=v_bottle500*24+v_cap500*24+v_carton500+24*v_sticker500+coalesce(v_tape,0)/70;
  end if;
  if v_bottle15 is not null and v_cap15 is not null and v_carton15 is not null and v_sticker_shared is not null and v_tape is not null then
    v_cost15:=v_bottle15*12+v_cap15*12+v_carton15+12*v_sticker_shared+coalesce(v_tape,0)/70;
  end if;
  if v_bottle6 is not null and v_cap6 is not null and v_sticker_shared is not null and v_tape is not null then v_cost6:=v_bottle6+v_cap6+v_sticker_shared; end if;

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

  select
    coalesce((select sum(labor_amount)/nullif(sum(quantity),0) from public.production where product_type='500ml' and production_date<=p_month_end),(select labor_per_unit from public.product_settings where product_type='500ml'),0),
    coalesce((select sum(labor_amount)/nullif(sum(quantity),0) from public.production where product_type='1.5L' and production_date<=p_month_end),(select labor_per_unit from public.product_settings where product_type='1.5L'),0),
    coalesce((select sum(labor_amount)/nullif(sum(quantity),0) from public.production where product_type='6L' and production_date<=p_month_end),(select labor_per_unit from public.product_settings where product_type='6L'),0)
  into v_labor_rate500,v_labor_rate15,v_labor_rate6;

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
  from public.business_income where income_date between p_month_start and p_month_end
    and category is distinct from 'غیر منسلک 19L سپلائی کی وصولی';

  select coalesce(sum(rc.amount),0) into v_unassigned_receipts
  from public.unassigned_19l_delivery_collections rc
  join public.unassigned_19l_deliveries d on d.id=rc.delivery_id
  where d.customer_classification='one_time'
    and rc.received_date between p_month_start and p_month_end;

  select greatest(
    (select coalesce(sum(d.bottles_delivered::numeric*100+d.damaged_caps::numeric*10),0)
     from public.unassigned_19l_deliveries d
     where d.customer_classification='one_time' and d.delivery_date<=p_month_end)
    -
    (select coalesce(sum(rc.amount),0)
     from public.unassigned_19l_delivery_collections rc
     join public.unassigned_19l_deliveries d on d.id=rc.delivery_id
     where d.customer_classification='one_time' and rc.received_date<=p_month_end),
    0
  ) into v_unassigned_unclassified;

  select coalesce(sum(
    private.unregistered_monthly_customer_paid_before(mc.id,p_month_end+1)
    - private.unregistered_monthly_customer_paid_before(mc.id,p_month_start)
  ),0) into v_monthly_account_receipts
  from public.unregistered_monthly_customers mc
  where mc.created_at < ((p_month_end+1)::timestamp at time zone 'Asia/Karachi');

  select coalesce(sum(greatest(
    coalesce((select sum(d.bottles_delivered::numeric*100+d.damaged_caps::numeric*10)
      from public.unassigned_19l_deliveries d
      where d.monthly_customer_id=mc.id
        and d.customer_classification='monthly' and d.delivery_date<=p_month_end),0)
    - private.unregistered_monthly_customer_paid_before(mc.id,p_month_end+1),0
  )),0) into v_monthly_account_receivable
  from public.unregistered_monthly_customers mc
  where mc.created_at < ((p_month_end+1)::timestamp at time zone 'Asia/Karachi');

  select coalesce(sum(case when payment_type='refund' then -amount else amount end),0)
    into v_registered_customer_receipts
  from public.customer_payments
  where payment_date between p_month_start and p_month_end;

  select coalesce(sum(current_due),0)
    into v_registered_customer_receivable
  from public.customer_monthly_bills
  where bill_month=date_trunc('month',p_month_end)::date;

  select coalesce(sum(rc.amount),0) into v_pending_review_receipts
  from public.unassigned_19l_delivery_collections rc
  join public.unassigned_19l_deliveries d on d.id=rc.delivery_id
  where d.customer_classification='monthly_pending_review'
    and rc.received_date between p_month_start and p_month_end;

  select greatest(
    (select coalesce(sum(d.bottles_delivered::numeric*100+d.damaged_caps::numeric*10),0)
     from public.unassigned_19l_deliveries d
     where d.customer_classification='monthly_pending_review' and d.delivery_date<=p_month_end)
    -
    (select coalesce(sum(rc.amount),0)
     from public.unassigned_19l_delivery_collections rc
     join public.unassigned_19l_deliveries d on d.id=rc.delivery_id
     where d.customer_classification='monthly_pending_review' and rc.received_date<=p_month_end),
    0
  ) into v_pending_review_receivable;

  select
    coalesce(sum(amount) filter(where entry_type='interest_income'),0),
    coalesce(sum(amount) filter(where entry_type='interest_expense'),0),
    coalesce(sum(amount) filter(where entry_type='depreciation_expense'),0),
    coalesce(sum(amount) filter(where entry_type='inventory_loss'),0),
    coalesce(sum(amount) filter(where entry_type='owner_withdrawal' and counterparty IN ('محمد اسامہ مغل','M.Usama Mughal','M. Usama Mughal')),0),
    coalesce(sum(amount) filter(where entry_type='owner_withdrawal' and counterparty IN ('محمد مزمل مغل','M. Muzamil Mughal')),0),
    coalesce(sum(amount) filter(where entry_type='owner_withdrawal' and counterparty IN ('محمد تقی مغل','M.Taqi Mughal')),0),
    coalesce(sum(amount) filter(where entry_type='owner_withdrawal' and counterparty IS DISTINCT FROM 'محمد اسامہ مغل' AND counterparty IS DISTINCT FROM 'M.Usama Mughal' AND counterparty IS DISTINCT FROM 'M. Usama Mughal' AND counterparty IS DISTINCT FROM 'محمد مزمل مغل' AND counterparty IS DISTINCT FROM 'M. Muzamil Mughal' AND counterparty IS DISTINCT FROM 'محمد تقی مغل' AND counterparty IS DISTINCT FROM 'M.Taqi Mughal'),0)
  into v_interest_income,v_interest_expense,v_depreciation,v_inventory_loss,
    v_owner1,v_owner2,v_owner3,v_owner4
  from public.business_finance_ledger where entry_date between p_month_start and p_month_end;

  select coalesce(sum(loss_amount),0)
    into v_finished_stock_loss
  from public.finished_stock_adjustments
  where adjustment_date between p_month_start and p_month_end;
  v_inventory_loss:=v_inventory_loss+v_finished_stock_loss;

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
  v_fill_water_used:=coalesce((SELECT sum(quantity*CASE product_type WHEN '500ml' THEN 12 WHEN '1.5L' THEN 18 ELSE 0 END) FROM public.production WHERE production_date BETWEEN p_month_start AND p_month_end),0);
  v_shop_water_used:=v_used_water+v_counter_litres+coalesce((SELECT sum(quantity*6) FROM public.production WHERE product_type='6L' AND production_date BETWEEN p_month_start AND p_month_end),0);
  v_water_cost:=v_used_water*coalesce(v_water_per_litre,0);
  select coalesce(sum(q.caps_used * coalesce(r.unit_cost,0)),0)
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
  ) q
  left join lateral (
    select sum(r.total_amount)/nullif(sum(r.quantity),0) as unit_cost
    from public.raw_material_purchases r
    where r.material_type='cap_19l' and r.purchase_date<=q.usage_date
  ) r on true;
  v_revenue19:=v_bottles*100+v_unassigned_successful*100+(v_caps+v_unassigned_caps)*10+v_counter_amount;
  v_profit19:=v_revenue19-v_water_cost-v_cap_cost-v_delivery_labor-v_unassigned_labor-v_exp19-v_counter_litres*coalesce(v_shop_water_rate,0);
  v_product_revenue:=v_rev500+v_rev15+v_rev6;
  v_product_cogs:=v_sold500*coalesce(v_cost500,0)+v_sold15*coalesce(v_cost15,0)+v_sold6*coalesce(v_cost6,0);
  v_return_loss:=v_return500*coalesce(v_cost500,0)/24+v_return15*coalesce(v_cost15,0)/12+v_return6*coalesce(v_cost6,0);
  v_production_labor:=v_labor500+v_labor15+v_labor6;
  v_profit_products:=v_product_revenue-v_product_cogs-v_return_loss-v_production_labor-v_support_labor-v_exp_products-v_fill_water_used*coalesce(v_fill_water_rate,0)-(v_shop_water_used-v_counter_litres-v_used_water)*coalesce(v_shop_water_rate,0);
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
    union all select 1 from public.finished_stock_adjustments
      where adjustment_date between p_month_start and p_month_end and loss_amount>0
  ) into v_has_pnl_activity;

  select jsonb_build_object(
    'water_litres',coalesce((select sum(tanker_count*1000) from public.water_tanker_purchases where purchase_date<=p_month_end),0)
      +coalesce((select sum(litres) from public.water_opening_stock where as_of_date<=p_month_end),0)
      -(0
        +coalesce((select sum(d.bottles_delivered*19) from public.customer_19l_deliveries d where d.delivery_date<=p_month_end),0)
        +coalesce((select sum(d.bottles_delivered*19) from public.unassigned_19l_deliveries d where d.delivery_date<=p_month_end),0)
        +coalesce((select sum(private.mpw_counter_water_litres(s.sale_date,s.total_litres,s.counter_water_litres)) from public.counter_water_sales s where s.sale_date<=p_month_end),0)
        +coalesce((select sum(quantity*CASE product_type WHEN '500ml' THEN 12 WHEN '1.5L' THEN 18 ELSE 0 END) from public.production where production_date<=p_month_end),0)
        +coalesce((select sum(quantity*6) from public.production where product_type='6L' and production_date<=p_month_end),0)),
    
    'water_shop_pool_litres',
      coalesce((select sum(tanker_count*1000) from public.water_tanker_purchases where purchase_date<=p_month_end and water_use='shop_counter'),0)
      +coalesce((select sum(litres) from public.water_opening_stock where as_of_date<=p_month_end and water_use='shop_counter'),0)
      -(0
        +coalesce((select sum(d.bottles_delivered*19) from public.customer_19l_deliveries d where d.delivery_date<=p_month_end),0)
        +coalesce((select sum(d.bottles_delivered*19) from public.unassigned_19l_deliveries d where d.delivery_date<=p_month_end),0)
        +coalesce((select sum(private.mpw_counter_water_litres(s.sale_date,s.total_litres,s.counter_water_litres)) from public.counter_water_sales s where s.sale_date<=p_month_end),0)
        +coalesce((select sum(quantity*6) from public.production where product_type='6L' and production_date<=p_month_end),0)),
    'water_product_filling_litres',
      coalesce((select sum(tanker_count*1000) from public.water_tanker_purchases where purchase_date<=p_month_end and water_use='product_filling'),0)
      +coalesce((select sum(litres) from public.water_opening_stock where as_of_date<=p_month_end and water_use='product_filling'),0)
      -coalesce((select sum(quantity*case product_type when '500ml' then 12 when '1.5L' then 18 else 0 end) from public.production where production_date<=p_month_end),0),
    'water_shop_pool_remaining_litres_is_estimate',true,'water_shop_pool_remaining_litres',
      coalesce((select sum(tanker_count*1000) from public.water_tanker_purchases where purchase_date<=p_month_end and water_use='shop_counter'),0)
      +coalesce((select sum(litres) from public.water_opening_stock where as_of_date<=p_month_end and water_use='shop_counter'),0)
      -coalesce((select sum(d.bottles_delivered*19) from public.customer_19l_deliveries d where d.delivery_date<=p_month_end),0)
      -coalesce((select sum(d.bottles_delivered*19) from public.unassigned_19l_deliveries d where d.delivery_date<=p_month_end),0)
      -coalesce((select sum(private.mpw_counter_water_litres(s.sale_date,s.total_litres,s.counter_water_litres)) from public.counter_water_sales s where s.sale_date<=p_month_end),0)
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
      ,
    'raw_500ml_bottles',coalesce((select sum(quantity) from public.raw_material_purchases where material_type='bottle_500ml' and purchase_date<=p_month_end),0)
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
    'tape_bundles',
      coalesce((
        select sum(r.quantity)
        from public.raw_material_purchases r
        where r.material_type='tape_bundle'
          and r.purchase_date<=p_month_end
          and (
            not exists (
              select 1 from public.raw_material_purchases opening
              where opening.material_type='tape_bundle' and opening.record_type='opening_stock'
            )
            or r.record_type='opening_stock'
            or r.purchase_date >= (
              select min(opening.purchase_date)
              from public.raw_material_purchases opening
              where opening.material_type='tape_bundle' and opening.record_type='opening_stock'
            )
          )
      ),0)
      -coalesce((
        select sum(p.quantity/70::numeric)
        from public.production p
        where p.product_type in ('500ml','1.5L')
          and p.production_date<=p_month_end
          and (
            not exists (
              select 1 from public.raw_material_purchases opening
              where opening.material_type='tape_bundle' and opening.record_type='opening_stock'
            )
            or p.production_date >= (
              select min(opening.purchase_date)
              from public.raw_material_purchases opening
              where opening.material_type='tape_bundle' and opening.record_type='opening_stock'
            )
          )
      ),0),
    'tape_bundles_recorded',coalesce((select sum(quantity) from public.raw_material_purchases where material_type='tape_bundle' and purchase_date<=p_month_end),0),
    'stickers',null,
    'stickers_500ml',coalesce((select sum(quantity*1900) from public.raw_material_purchases where material_type='sticker_500ml' and purchase_date<=p_month_end),0)
      -coalesce((select sum(quantity*24) from public.production where product_type='500ml' and production_date<=p_month_end),0),
    'stickers_1_5l_6l',coalesce((select sum(quantity*1100) from public.raw_material_purchases where material_type='sticker_1_5l_6l' and purchase_date<=p_month_end),0)
      -coalesce((select sum(quantity*CASE product_type WHEN '1.5L' THEN 12 ELSE 1 END) from public.production where product_type IN ('1.5L','6L') and production_date<=p_month_end),0),
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
      '19L',jsonb_build_object('revenue',v_revenue19,'customer_delivery_revenue',v_bottles*100,'unassigned_delivery_revenue',v_unassigned_successful*100+v_unassigned_caps*10,
        'unassigned_delivery_damaged_cap_revenue',v_unassigned_caps*10,
        'unassigned_delivery_cash_collected',v_unassigned_receipts,
        'unassigned_delivery_cash_unclassified',v_unassigned_unclassified,'registered_customer_cash_collected',v_registered_customer_receipts,'registered_customer_receivable',v_registered_customer_receivable,'monthly_account_cash_collected',v_monthly_account_receipts,'monthly_account_receivable',v_monthly_account_receivable,'pending_review_delivery_cash_collected',v_pending_review_receipts,'pending_review_delivery_receivable',v_pending_review_receivable,'total_19l_cash_collected',v_registered_customer_receipts+v_monthly_account_receipts+v_pending_review_receipts+v_unassigned_receipts,'total_19l_receivable',v_registered_customer_receivable+v_monthly_account_receivable+v_pending_review_receivable+v_unassigned_unclassified,'damaged_cap_revenue',(v_caps+v_unassigned_caps)*10,
        'customer_damaged_cap_revenue',v_caps*10,'counter_water_revenue',v_counter_amount,'water_cost',v_water_cost,'counter_water_cost',v_counter_litres*coalesce(v_shop_water_rate,0),'estimated_counter_water_cost',v_counter_litres*coalesce(v_shop_water_rate,0),'counter_water_litres',v_counter_litres,
        'daily_total_water_litres',v_counter_litres+v_used_water,
        'nineteen_litre_delivery_water_litres',v_used_water,'counter_water_litres_is_estimate',true,'counter_bottles_estimated',v_counter_litres/19,'counter_water_cost_is_estimate',true,'net_profit_before_counter_water_estimate',v_net+v_counter_litres*coalesce(v_shop_water_rate,0),
        'successful_delivery_bottles',v_bottles+v_unassigned_successful,
        'delivery_revenue_per_successful_bottle',(v_bottles*100+v_unassigned_successful*100+v_caps*10)/nullif(v_bottles+v_unassigned_successful,0),
        'delivery_water_cost_per_bottle_delivered',v_water_cost/nullif(v_delivered+v_unassigned_delivered,0),
        'delivery_labor_per_successful_bottle',(v_delivery_labor+v_unassigned_labor)/nullif(v_bottles+v_unassigned_successful,0),
        'delivery_contribution_per_successful_bottle',(v_bottles*100+v_unassigned_successful*100+(v_caps+v_unassigned_caps)*10-v_water_cost-v_cap_cost-v_delivery_labor-v_unassigned_labor)/nullif(v_bottles+v_unassigned_successful,0),
        'counter_average_price_per_estimated_litre',v_counter_amount/nullif(v_counter_litres,0),
        'counter_contribution_per_estimated_litre',v_counter_amount/nullif(v_counter_litres,0)-v_shop_water_rate,
        'water_rate_per_litre',v_water_per_litre,'cap_cost',v_cap_cost,
        'delivery_labor',v_delivery_labor+v_unassigned_labor,
        'customer_delivery_labor',v_delivery_labor,
        'unassigned_bottles',v_unassigned_delivered,'unassigned_successful_bottles',v_unassigned_successful,
        'unassigned_delivery_labor',v_unassigned_labor,
        'segment_expenses',v_exp19,'profit_before_shared',v_profit19),
      'finished_goods',jsonb_build_object('revenue',v_product_revenue,'material_packaging_cost',v_product_cogs,'filling_water_litres',v_fill_water_used,'filling_water_rate_per_litre',v_fill_water_rate,'filling_water_cost',v_fill_water_used*coalesce(v_fill_water_rate,0),'shop_water_cost_for_6l',(v_shop_water_used-v_counter_litres-v_used_water)*coalesce(v_shop_water_rate,0),
        'replacement_loss',v_return_loss,'production_labor',v_production_labor,'support_labor',v_support_labor,
        'segment_expenses',v_exp_products,'profit_before_shared',v_profit_products),
      'shared',jsonb_build_object('general_expenses',v_exp_general,'interest_expense',v_interest_expense,
        'depreciation',v_depreciation,'inventory_loss',v_inventory_loss,'other_income',v_other_income+v_interest_income),
      'net_profit',v_net
    ),
    'products',jsonb_build_object(
      '500ml',jsonb_build_object('revenue',v_rev500,'quantity',v_sold500,'unit_cost',v_cost500,
        'average_sale_price',v_rev500/nullif(v_sold500,0),'labor_per_unit',v_labor_rate500,
        'water_cost_per_unit',12*v_fill_water_rate,
        'direct_unit_cost',case when v_cost500 is not null and v_fill_water_rate is not null then v_cost500+v_labor_rate500+12*v_fill_water_rate else null end,
        'unit_contribution',case when v_rev500>0 and v_cost500 is not null and v_fill_water_rate is not null then v_rev500/nullif(v_sold500,0)-(v_cost500+v_labor_rate500+12*v_fill_water_rate) else null end,
        'material_cost',v_sold500*coalesce(v_cost500,0),'returns',v_return500,'return_loss',v_return500*coalesce(v_cost500,0)/24,'production_labor',v_labor500),
      '1.5L',jsonb_build_object('revenue',v_rev15,'quantity',v_sold15,'unit_cost',v_cost15,
        'average_sale_price',v_rev15/nullif(v_sold15,0),'labor_per_unit',v_labor_rate15,
        'water_cost_per_unit',18*v_fill_water_rate,
        'direct_unit_cost',case when v_cost15 is not null and v_fill_water_rate is not null then v_cost15+v_labor_rate15+18*v_fill_water_rate else null end,
        'unit_contribution',case when v_rev15>0 and v_cost15 is not null and v_fill_water_rate is not null then v_rev15/nullif(v_sold15,0)-(v_cost15+v_labor_rate15+18*v_fill_water_rate) else null end,
        'material_cost',v_sold15*coalesce(v_cost15,0),'returns',v_return15,'return_loss',v_return15*coalesce(v_cost15,0)/12,'production_labor',v_labor15),
      '6L',jsonb_build_object('revenue',v_rev6,'quantity',v_sold6,'unit_cost',v_cost6,
        'average_sale_price',v_rev6/nullif(v_sold6,0),'labor_per_unit',v_labor_rate6,
        'water_cost_per_unit',6*v_shop_water_rate,
        'direct_unit_cost',case when v_cost6 is not null and v_shop_water_rate is not null then v_cost6+v_labor_rate6+6*v_shop_water_rate else null end,
        'unit_contribution',case when v_rev6>0 and v_cost6 is not null and v_shop_water_rate is not null then v_rev6/nullif(v_sold6,0)-(v_cost6+v_labor_rate6+6*v_shop_water_rate) else null end,
        'material_cost',v_sold6*coalesce(v_cost6,0),'returns',v_return6,'return_loss',v_return6*coalesce(v_cost6,0),'production_labor',v_labor6)
    ),
    'owner_withdrawals',jsonb_build_object(
      'M.Usama Mughal',v_owner1,'M. Muzamil Mughal',v_owner2,'M.Taqi Mughal',v_owner3,'other_legacy_recipients',v_owner4,
      'total',v_owner1+v_owner2+v_owner3+v_owner4),
    'capital_and_loans',jsonb_build_object('capital',v_capital,'loan_received',v_loan_received,
      'loan_repaid',v_loan_repaid,'loan_balance',v_loan_received-v_loan_repaid,
      'loan_given',v_loan_given,'loan_collected',v_loan_collected,'receivable_balance',v_loan_given-v_loan_collected),
    'expense_entry_count',(select count(*) from public.business_expenses where expense_date between p_month_start and p_month_end),
     'expense_entry_confirmation_required',true,
     'purchases',jsonb_build_object('raw_material_period',v_raw_purchase_period,'water_tanker_period',v_tanker_purchase_period),
    'stock_estimate',v_stock,
    'net_profit_is_estimated',(v_counter_litres>0 OR (v_sold500+v_sold15+v_return500+v_return15)>0),'counter_water_usage_is_estimated',true,'notes','یہ رپورٹ درج شدہ آمدن اور اخراجات پر مبنی ہے۔ پیکنگ ٹیپ کا حساب ایک بنڈل فی 70 عدد 500ml یا 1.5L کارٹن کے تناسب سے ہے؛ فی کارٹن ٹیپ لاگت اوسط درج شدہ بنڈل قیمت/70 ہے۔ نئے روزانہ اندراج میں تمام مصنوعات سمیت مجموعی کاؤنٹر وصولی درج ہوتی ہے؛ اسی دن موصول غیر منسلک سپلائی اور الگ درج نقد مصنوعات کی رقم منہا کرکے باقی رقم کو 50 روپے فی 19L بوتل کے حساب سے کاؤنٹر 19L پانی کا تخمینہ بنایا جاتا ہے۔ کاؤنٹر بوتلیں اور پانی 50 روپے فی 19L بوتل کے حساب سے تخمینی ہیں؛ کسٹمر اور غیر منسلک سپلائی کے لیٹر الگ بوتلوں کے اندراج سے شمار ہوتے ہیں۔ پرانے روزانہ ریکارڈ اپنے سابقہ لیٹر اندراج کے ساتھ محفوظ ہیں۔ پانی کے تخمینے سے پہلے نتیجے میں یہ تخمینی لاگت شامل نہیں۔ پیٹرول، مرمت یا کوئی دوسرا خرچ درج نہ ہو تو وہ منافع سے منہا نہیں ہوگا۔ سپلائر سے مفت کلیم میں آنے والی مقدار خام مال کے مفت کلیم اندراج سے درج کریں؛ جو کلیم درج نہیں ہوگا وہ خام مال کے اسٹاک کے اندازے میں شامل نہیں ہوگا۔'
  );
end;
$function$
;