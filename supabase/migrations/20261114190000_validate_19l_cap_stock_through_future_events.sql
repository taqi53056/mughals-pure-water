-- First-pass future-event guard; immediately superseded by the corrected
-- chronological implementation in 20261114191000.
create or replace function private.mpw_guard_19l_cap_stock()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare
  v_cutover_date date;
  v_event_date date;
  v_available numeric := 0;
  v_consumed numeric := 0;
  v_old_id bigint := null;
begin
  if tg_table_name not in ('customer_19l_deliveries','unassigned_19l_deliveries') then
    return new;
  end if;
  if tg_op='UPDATE' then v_old_id:=old.id; end if;
  perform pg_advisory_xact_lock(hashtextextended('raw-material-cap-19l',0));
  select min(purchase_date) into v_cutover_date
  from public.raw_material_purchases
  where material_type='cap_19l' and record_type='opening_stock';
  for v_event_date in
    select distinct event_date
    from (
      select d.delivery_date event_date from public.customer_19l_deliveries d
      where v_old_id is null or d.id is distinct from v_old_id
      union all
      select d.delivery_date from public.unassigned_19l_deliveries d
      where v_old_id is null or d.id is distinct from v_old_id
      union all select new.delivery_date
    ) events
    where event_date is not null
      and (v_cutover_date is null or event_date>=v_cutover_date
           or not exists (select 1 from public.raw_material_purchases r
             where r.material_type='cap_19l' and r.record_type='opening_stock'))
    order by event_date
  loop
    select coalesce(sum(r.quantity),0)
      + case when new.delivery_date<=v_event_date then 0::numeric else 0::numeric end
    into v_available
    from public.raw_material_purchases r
    where r.material_type='cap_19l' and r.purchase_date<=v_event_date
      and (v_cutover_date is null
        or (v_event_date<v_cutover_date and r.record_type<>'opening_stock')
        or (v_event_date>=v_cutover_date
          and (r.record_type='opening_stock' or r.purchase_date>=v_cutover_date)));
    select
      coalesce((select sum(d.damaged_caps) from public.customer_19l_deliveries d
        where d.delivery_date<=v_event_date
          and (v_old_id is null or d.id is distinct from v_old_id)
          and (v_cutover_date is null or v_event_date<v_cutover_date or d.delivery_date>=v_cutover_date)),0)
      + coalesce((select sum(d.damaged_caps) from public.unassigned_19l_deliveries d
        where d.delivery_date<=v_event_date
          and (v_old_id is null or d.id is distinct from v_old_id)
          and (v_cutover_date is null or v_event_date<v_cutover_date or d.delivery_date>=v_cutover_date)),0)
      + case when new.delivery_date<=v_event_date
          and (v_cutover_date is null or v_event_date<v_cutover_date or new.delivery_date>=v_cutover_date)
        then coalesce(new.damaged_caps,0) else 0 end
    into v_consumed;
    if v_available<v_consumed then
      raise exception '19L ڈھکنوں کی اس انٹری سے بعد کی تاریخ کا اسٹاک منفی ہوگا۔ تاریخ: %، دستیاب: %، استعمال: %',
        v_event_date,greatest(v_available,0),v_consumed using errcode='23514';
    end if;
  end loop;
  return new;
end;
$function$;
