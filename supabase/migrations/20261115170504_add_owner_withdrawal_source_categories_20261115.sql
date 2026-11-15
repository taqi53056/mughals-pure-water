alter table public.business_finance_ledger
  add column if not exists withdrawal_source text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.business_finance_ledger'::regclass
      and conname = 'business_finance_ledger_withdrawal_source_check'
  ) then
    alter table public.business_finance_ledger
      add constraint business_finance_ledger_withdrawal_source_check
      check (withdrawal_source is null or withdrawal_source in ('counter_cash', 'product_sales'));
  end if;
end $$;

comment on column public.business_finance_ledger.withdrawal_source is
  'Owner withdrawal source: counter cash or combined 500ml+1.5L product sales proceeds; null means historical source not verified.';

update public.business_finance_ledger
set withdrawal_source = 'counter_cash',
    details = concat_ws(' ', nullif(details, ''), 'ماخذ کی تصدیق: دکان کے کاؤنٹر کی نقد دراز۔')
where id = 21
  and entry_type = 'owner_withdrawal'
  and amount = 50
  and counterparty = 'M. Muzamil Mughal'
  and entry_date = date '2026-11-15'
  and withdrawal_source is null;
