-- Allow partial tanker allocations while preserving legacy 1,000L units.
-- A value of 0.700 represents 700L; the existing stock guards multiply by 1,000.
begin;
alter table public.water_tanker_purchases
  drop constraint if exists water_tanker_total_amount_matches_count_rate;
drop trigger if exists set_water_tanker_total_amount_trigger
  on public.water_tanker_purchases;
alter table public.water_tanker_purchases
  drop column if exists total_amount;
alter table public.water_tanker_purchases
  alter column tanker_count type numeric(10,3)
  using tanker_count::numeric;
alter table public.water_tanker_purchases
  add column total_amount numeric(14,2)
  generated always as (round(tanker_count * rate_per_tanker, 2)) stored;
alter table public.water_tanker_purchases
  add constraint water_tanker_total_amount_matches_count_rate
  check (total_amount = round(tanker_count * rate_per_tanker, 2));
commit;
