create or replace function public.build_business_monthly_report(p_month_start date,p_month_end date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_report jsonb;
  v_shop_balance numeric;
  v_fill_balance numeric;
  v_total_water numeric;
  v_one_time_due numeric;
begin
  v_report:=public.build_business_monthly_report_legacy(p_month_start,p_month_end);
  v_shop_balance:=private.mpw_shop_water_balance_as_of(p_month_end);
  v_fill_balance:=coalesce((v_report #>> '{stock_estimate,water_product_filling_litres}')::numeric,0);
  v_total_water:=v_shop_balance+v_fill_balance;
  v_one_time_due:=coalesce((v_report #>> '{segments,19L,unassigned_delivery_cash_unclassified}')::numeric,0);

  v_report:=jsonb_set(v_report,'{stock_estimate,water_shop_pool_litres}',to_jsonb(v_shop_balance),true);
  v_report:=jsonb_set(v_report,'{stock_estimate,water_shop_pool_remaining_litres}',to_jsonb(v_shop_balance),true);
  v_report:=jsonb_set(v_report,'{stock_estimate,water_litres}',to_jsonb(v_total_water),true);
  v_report:=jsonb_set(v_report,'{stock_estimate,water_shop_pool_remaining_litres_is_estimate}',to_jsonb(true),true);
  v_report:=jsonb_set(v_report,'{water_litres}',to_jsonb(v_total_water),true);
  v_report:=jsonb_set(v_report,'{segments,19L,one_time_delivery_receivable}',to_jsonb(v_one_time_due),true);

  return v_report;
end;
$$;

revoke all on function public.build_business_monthly_report(date,date) from public,anon,authenticated,service_role;