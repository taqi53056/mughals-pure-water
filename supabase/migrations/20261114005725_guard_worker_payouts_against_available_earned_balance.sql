create or replace function private.mpw_guard_worker_payout_balance()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_old_worker_id bigint;
  v_new_worker_id bigint;
  v_old_id bigint;
  v_worker_id bigint;
  v_balance numeric(14,2);
  v_day record;
  v_available numeric(14,2);
begin
  if tg_op <> 'INSERT' then
    v_old_worker_id := old.worker_id;
    v_old_id := old.id;
  end if;
  if tg_op <> 'DELETE' then
    v_new_worker_id := new.worker_id;
  end if;

  for v_worker_id in
    select distinct x.worker_id
    from unnest(array[v_old_worker_id,v_new_worker_id]) as x(worker_id)
    where x.worker_id is not null
    order by x.worker_id
  loop
    perform pg_advisory_xact_lock(
      hashtextextended('mpw-worker-ledger-balance-'||v_worker_id::text,0)
    );

    v_balance := 0;
    for v_day in
      select q.entry_date,
        coalesce(sum(q.amount) filter(where q.entry_type='earning'),0)::numeric(14,2) as earnings,
        coalesce(sum(q.amount) filter(where q.entry_type='advance'),0)::numeric(14,2) as advances,
        coalesce(sum(q.amount) filter(where q.entry_type='payment'),0)::numeric(14,2) as payments,
        coalesce(sum(q.amount) filter(where q.entry_type='deduction'),0)::numeric(14,2) as deductions
      from (
        select l.entry_date,l.entry_type,l.amount
        from public.worker_ledger l
        where l.worker_id=v_worker_id
          and (v_old_id is null or l.id<>v_old_id)
        union all
        select new.entry_date,new.entry_type,new.amount
        where tg_op<>'DELETE' and new.worker_id=v_worker_id
      ) q
      group by q.entry_date
      order by q.entry_date
    loop
      v_available := greatest(v_balance+v_day.earnings-v_day.advances,0);
      if v_day.payments+v_day.deductions>v_available then
        raise exception
          'ورکر کی ادائیگی/کٹوتی محفوظ نہیں ہوئی۔ تاریخ: %، دستیاب واجب الادا رقم: Rs. %، مطلوبہ ادائیگی و کٹوتی: Rs. %۔ اضافی رقم کے لیے ایڈوانس منتخب کریں۔',
          v_day.entry_date,
          to_char(v_available,'FM999999999990.00'),
          to_char(v_day.payments+v_day.deductions,'FM999999999990.00')
          using errcode='23514';
      end if;
      v_balance := v_balance+v_day.earnings-v_day.advances-v_day.payments-v_day.deductions;
    end loop;
  end loop;

  if tg_op='DELETE' then return old; end if;
  return new;
end;
$function$;

drop trigger if exists worker_ledger_payout_balance_guard on public.worker_ledger;
create trigger worker_ledger_payout_balance_guard
before insert or update or delete on public.worker_ledger
for each row execute function private.mpw_guard_worker_payout_balance();
