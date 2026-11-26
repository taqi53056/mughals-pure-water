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
  v_rafi_withdrawals numeric;
  v_other_legacy numeric;
  v_notes text;
begin
  v_report:=public.build_business_monthly_report_legacy(p_month_start,p_month_end);
  v_shop_balance:=private.mpw_shop_water_balance_as_of(p_month_end);
  v_fill_balance:=coalesce((v_report #>> '{stock_estimate,water_product_filling_litres}')::numeric,0);
  v_total_water:=v_shop_balance+v_fill_balance;
  v_one_time_due:=coalesce((v_report #>> '{segments,19L,unassigned_delivery_cash_unclassified}')::numeric,0);
  v_rafi_withdrawals:=coalesce((select sum(f.amount) from public.business_finance_ledger f
    where f.entry_type='owner_withdrawal' and f.counterparty='M. Rafi Mughal'
      and f.entry_date between p_month_start and p_month_end),0);
  v_other_legacy:=greatest(coalesce((v_report #>> '{owner_withdrawals,other_legacy_recipients}')::numeric,0)-v_rafi_withdrawals,0);

  v_report:=jsonb_set(v_report,'{stock_estimate,water_shop_pool_litres}',to_jsonb(v_shop_balance),true);
  v_report:=jsonb_set(v_report,'{stock_estimate,water_shop_pool_remaining_litres}',to_jsonb(v_shop_balance),true);
  v_report:=jsonb_set(v_report,'{stock_estimate,water_litres}',to_jsonb(v_total_water),true);
  v_report:=jsonb_set(v_report,'{stock_estimate,water_shop_pool_remaining_litres_is_estimate}',to_jsonb(true),true);
  v_report:=jsonb_set(v_report,'{water_litres}',to_jsonb(v_total_water),true);
  v_report:=jsonb_set(v_report,'{segments,19L,one_time_delivery_receivable}',to_jsonb(v_one_time_due),true);
  v_report:=jsonb_set(v_report,'{owner_withdrawals,M. Rafi Mughal}',to_jsonb(v_rafi_withdrawals),true);
  v_report:=jsonb_set(v_report,'{owner_withdrawals,other_legacy_recipients}',to_jsonb(v_other_legacy),true);

  v_notes:=coalesce(v_report->>'notes','');
  v_notes:=regexp_replace(
    v_notes,
    'نئے روزانہ اندراج میں.*?کاؤنٹر 19L پانی کا تخمینہ بنایا جاتا ہے۔',
    'نئے روزانہ اندراج میں صرف 19L کاؤنٹر کی مجموعی وصولی درج کریں؛ اس مجموعی رقم میں اسی دن وصول شدہ ایک وقتی سپلائی کی رقم لازماً شامل کریں، نظام اسے خود منہا کرتا ہے۔ 500ml، 1.5L اور 6L کی الگ مصنوعات کی فروخت اس رقم میں شامل نہ کریں؛ اسے الگ درج کریں۔ باقی رقم کو 50 روپے فی 19L بوتل کے حساب سے کاؤنٹر 19L پانی کا تخمینہ بنایا جاتا ہے۔',
    's'
  );
  v_notes:=replace(
    v_notes,
    'پرانے روزانہ ریکارڈ اپنے سابقہ لیٹر اندراج کے ساتھ محفوظ ہیں۔',
    'پرانے روزانہ ریکارڈ اپنے سابقہ لیٹر اندراج کے ساتھ محفوظ ہیں؛ ان کی رقم اور لیٹر 50 روپے فی 19L کے تناسب سے مختلف ہوسکتے ہیں، اس لیے ان کا پانی خرچ تخمینی ہے۔'
  );
  v_report:=jsonb_set(v_report,'{notes}',to_jsonb(v_notes),true);

  return v_report;
end;
$$;

revoke all on function public.build_business_monthly_report(date,date) from public,anon,authenticated,service_role;