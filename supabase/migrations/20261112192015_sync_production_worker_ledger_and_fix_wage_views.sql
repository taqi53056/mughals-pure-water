create or replace function private.sync_production_worker_ledger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_production_date date;
  v_entered_by uuid;
  v_is_owner boolean;
  v_is_active boolean;
  v_categories text[];
begin
  if tg_op in ('UPDATE','DELETE') then
    delete from public.worker_ledger
    where source_table='production_worker_allocations'
      and source_id=old.id;
  end if;

  if tg_op='DELETE' then
    return old;
  end if;

  select p.production_date,p.entered_by,w.is_owner,w.is_active,w.work_categories
    into v_production_date,v_entered_by,v_is_owner,v_is_active,v_categories
  from public.production p
  join public.workers w on w.id=new.worker_id
  where p.id=new.production_id;

  if not found then
    raise exception 'پروڈکشن یا منتخب ورکر کا ریکارڈ نہیں ملا۔' using errcode='23503';
  end if;

  if not coalesce(v_is_active,false)
     or (not coalesce(v_is_owner,false) and not coalesce(v_categories @> array['production']::text[],false)) then
    raise exception 'منتخب ورکر فعال نہیں یا پروڈکشن کے لیے مقرر نہیں۔' using errcode='23514';
  end if;

  if not coalesce(v_is_owner,false) and new.cartons>0 then
    insert into public.worker_ledger(
      worker_id,entry_date,entry_type,work_category,amount,note,
      source_table,source_id,entered_by
    )
    values(
      new.worker_id,v_production_date,'earning','production',new.cartons*10,
      'پروڈکشن — '||new.cartons||' کارٹن',
      'production_worker_allocations',new.id,v_entered_by
    );
  end if;

  return new;
end;
$function$;

revoke all on function private.sync_production_worker_ledger() from public,anon,authenticated;

drop trigger if exists production_worker_ledger_sync on public.production_worker_allocations;
create trigger production_worker_ledger_sync
after insert or update or delete on public.production_worker_allocations
for each row execute function private.sync_production_worker_ledger();

create or replace view public.carton_worker_wage_balance as
select
  coalesce((
    select sum(wl.amount)
    from public.worker_ledger wl
    where wl.entry_type='earning'
      and wl.work_category='production'
  ),0)::numeric as total_earned,
  coalesce((
    select sum(wl.amount)
    from public.worker_ledger wl
    where wl.entry_type<>'earning'
      and wl.work_category='production'
  ),0)::numeric as total_paid,
  (
    coalesce((
      select sum(wl.amount)
      from public.worker_ledger wl
      where wl.entry_type='earning'
        and wl.work_category='production'
    ),0)
    -
    coalesce((
      select sum(wl.amount)
      from public.worker_ledger wl
      where wl.entry_type<>'earning'
        and wl.work_category='production'
    ),0)
  )::numeric as balance_due;

create or replace view public.delivery_worker_wage_balance as
select
  coalesce((
    select sum(wl.amount)
    from public.worker_ledger wl
    where wl.entry_type='earning'
      and wl.work_category='19L delivery'
  ),0)::numeric as total_earned,
  coalesce((
    select sum(wl.amount)
    from public.worker_ledger wl
    where wl.entry_type<>'earning'
      and wl.work_category='19L delivery'
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
      select sum(wl.amount)
      from public.worker_ledger wl
      where wl.entry_type<>'earning'
        and wl.work_category='19L delivery'
    ),0)
  )::numeric as balance_due;
