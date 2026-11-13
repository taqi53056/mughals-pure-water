-- Validate production cap and packaging consumption against every later
-- production event so a backdated production entry cannot create a later deficit.
create or replace function private.mpw_guard_production_cap_stock()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare
  v_material_type text;
  v_cutover_date date;
  v_event_date date;
  v_required numeric := 0;
  v_available numeric := 0;
  v_consumed numeric := 0;
begin
  if new.product_type not in ('500ml','1.5L','6L') then return new; end if;
  perform pg_advisory_xact_lock(hashtextextended('production-inputs',0));
  v_material_type:=case new.product_type when '500ml' then 'cap_500ml' when '1.5L' then 'cap_1_5l' else 'cap_6l' end;
  v_required:=new.quantity*case new.product_type when '500ml' then 24 when '1.5L' then 12 else 1 end;
  select min(purchase_date) into v_cutover_date from public.raw_material_purchases
    where material_type=v_material_type and record_type='opening_stock';

  for v_event_date in
    select distinct event_date from (
      select p.production_date event_date from public.production p
        where p.product_type=new.product_type and p.id is distinct from new.id
      union all select new.production_date
    ) events where event_date is not null order by event_date
  loop
    select coalesce(sum(r.quantity),0) into v_available
    from public.raw_material_purchases r
    where r.material_type=v_material_type and r.purchase_date<=v_event_date
      and (v_cutover_date is null or v_event_date<v_cutover_date
        or r.record_type='opening_stock' or r.purchase_date>=v_cutover_date);

    select coalesce(sum(p.quantity*case p.product_type when '500ml' then 24 when '1.5L' then 12 else 1 end),0)
    into v_consumed from public.production p
    where p.product_type=new.product_type and p.production_date<=v_event_date
      and (v_cutover_date is null or v_event_date<v_cutover_date or p.production_date>=v_cutover_date)
      and p.id is distinct from new.id;

    if new.production_date<=v_event_date and
       (v_cutover_date is null or v_event_date<v_cutover_date or new.production_date>=v_cutover_date) then
      v_consumed:=v_consumed+v_required;
    end if;

    if v_available<v_consumed then
      raise exception 'اس پروڈکٹ کے ڈھکنوں کی انٹری سے بعد کی پروڈکشن میں اسٹاک منفی ہوگا۔ میٹریل: %، تاریخ: %، دستیاب: %، استعمال: %',
        v_material_type,v_event_date,greatest(v_available,0),v_consumed using errcode='23514';
    end if;
  end loop;
  return new;
end;
$function$;

create or replace function private.mpw_guard_production_packaging_stock()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare
  v_requirement record;
  v_cutover_date date;
  v_event_date date;
  v_available numeric := 0;
  v_consumed numeric := 0;
begin
  perform pg_advisory_xact_lock(hashtextextended('production-inputs',0));
  for v_requirement in
    select material_type,required_quantity from (values
      ('bottle_500ml'::text,case when new.product_type='500ml' then new.quantity*24 else 0 end),
      ('carton_500ml'::text,case when new.product_type='500ml' then new.quantity else 0 end),
      ('bottle_1_5l'::text,case when new.product_type='1.5L' then new.quantity*12 else 0 end),
      ('carton_1_5l'::text,case when new.product_type='1.5L' then new.quantity else 0 end),
      ('bottle_6l'::text,case when new.product_type='6L' then new.quantity else 0 end),
      ('tape_bundle'::text,0::numeric),
      ('sticker_500ml'::text,case when new.product_type='500ml' then new.quantity*24 else 0 end),
      ('sticker_1_5l_6l'::text,case new.product_type when '1.5L' then new.quantity*12 when '6L' then new.quantity else 0 end)
    ) requirements(material_type,required_quantity)
    where required_quantity>0
  loop
    select min(r.purchase_date) into v_cutover_date from public.raw_material_purchases r
      where r.material_type=v_requirement.material_type and r.record_type='opening_stock';

    for v_event_date in
      select distinct event_date from (
        select p.production_date event_date from public.production p where p.id is distinct from new.id
        union all select new.production_date
      ) events where event_date is not null order by event_date
    loop
      select coalesce(sum(r.quantity*case r.material_type
        when 'sticker_500ml' then 1900::numeric when 'sticker_1_5l_6l' then 1200::numeric else 1::numeric end),0)
      into v_available from public.raw_material_purchases r
      where r.material_type=v_requirement.material_type and r.purchase_date<=v_event_date
        and (v_cutover_date is null or v_event_date<v_cutover_date
          or r.record_type='opening_stock' or r.purchase_date>=v_cutover_date);

      select coalesce(sum(case v_requirement.material_type
        when 'bottle_500ml' then case when p.product_type='500ml' then p.quantity*24 else 0 end
        when 'carton_500ml' then case when p.product_type='500ml' then p.quantity else 0 end
        when 'bottle_1_5l' then case when p.product_type='1.5L' then p.quantity*12 else 0 end
        when 'carton_1_5l' then case when p.product_type='1.5L' then p.quantity else 0 end
        when 'bottle_6l' then case when p.product_type='6L' then p.quantity else 0 end
        when 'sticker_500ml' then case when p.product_type='500ml' then p.quantity*24 else 0 end
        when 'sticker_1_5l_6l' then case p.product_type when '1.5L' then p.quantity*12 when '6L' then p.quantity else 0 end
        else 0 end),0)
      into v_consumed from public.production p
      where p.production_date<=v_event_date
        and (v_cutover_date is null or v_event_date<v_cutover_date or p.production_date>=v_cutover_date)
        and p.id is distinct from new.id;

      if new.production_date<=v_event_date and
         (v_cutover_date is null or v_event_date<v_cutover_date or new.production_date>=v_cutover_date) then
        v_consumed:=v_consumed+v_requirement.required_quantity;
      end if;

      if v_available<v_consumed then
        raise exception 'خام مال % کی اس پروڈکشن سے بعد کی تاریخ کا اسٹاک منفی ہوگا۔ تاریخ: %، دستیاب: %، استعمال: %',
          v_requirement.material_type,v_event_date,greatest(v_available,0),v_consumed using errcode='23514';
      end if;
    end loop;
  end loop;
  return new;
end;
$function$;
