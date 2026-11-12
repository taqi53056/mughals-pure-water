create or replace view public.delivery_worker_wage_balance as
select
  coalesce((
    select sum(wl.amount)
    from public.worker_ledger wl
    where wl.entry_type='earning'
      and wl.work_category='19L delivery'
  ),0)::numeric as total_earned,
  coalesce((
    select sum(lp.amount)
    from public.labor_payments lp
    where lp.labor_type='delivery'
  ),0)::numeric as total_paid,
  (
    coalesce((
      select sum(wl.amount)
      from public.worker_ledger wl
      where wl.entry_type='earning'
        and wl.work_category='19L delivery'
    ),0)
    -
    coalesce((
      select sum(lp.amount)
      from public.labor_payments lp
      where lp.labor_type='delivery'
    ),0)
  )::numeric as balance_due;
