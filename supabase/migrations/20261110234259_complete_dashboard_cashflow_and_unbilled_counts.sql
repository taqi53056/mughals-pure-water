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
  v_due_customers integer:=0;
  v_active_customers integer:=0;
  v_unbilled_customers integer:=0;
  v_collections numeric(14,2):=0;
  v_cash_out numeric(14,2):=0;
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
    c.is_active=true
    or (
      c.approved_at is not null
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
    into v_due,v_due_customers
  from (
    select distinct on(customer_id) customer_id,current_due
    from public.customer_monthly_bills
    order by customer_id,bill_month desc
  ) latest;

  select
    coalesce((select sum(case when payment_type='refund' then -amount else amount end)
      from public.customer_payments where payment_date between p_month_start and p_month_end),0)
    +coalesce((select sum(total_amount) from public.product_sales where sale_date between p_month_start and p_month_end),0)
    +coalesce((select sum(total_amount) from public.counter_water_sales where sale_date between p_month_start and p_month_end),0)
    +coalesce((select sum(amount) from public.business_income where income_date between p_month_start and p_month_end),0)
    +coalesce((select sum(amount) from public.business_finance_ledger
      where entry_date between p_month_start and p_month_end
        and entry_type in ('capital_in','loan_received','loan_collected','fixed_asset_sale','interest_income')),0)
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
    into v_cash_out;

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

alter table public.business_finance_ledger
  add constraint business_finance_ledger_payment_method_cashflow_check
  check (
    (
      entry_type in ('inventory_loss','depreciation_expense')
      and (payment_method is null or payment_method in ('نقد','بینک','جاز کیش','ایزی پیسہ','دیگر','cash','bank','jazzcash','easypaisa','other'))
    )
    or
    (
      entry_type not in ('inventory_loss','depreciation_expense')
      and payment_method is not null
      and payment_method in ('نقد','بینک','جاز کیش','ایزی پیسہ','دیگر','cash','bank','jazzcash','easypaisa','other')
    )
  );
