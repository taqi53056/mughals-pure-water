do $migration$
declare v_def text; v_old text; v_new text;
begin
  v_def := pg_get_functiondef('public.build_business_monthly_report(date,date)'::regprocedure);
  v_old := $frag$    'tape_bundles',null,$frag$;
  v_new := $frag$    'tape_bundles',
      coalesce((
        select sum(r.quantity)
        from public.raw_material_purchases r
        where r.material_type='tape_bundle'
          and r.purchase_date<=p_month_end
          and (
            not exists (
              select 1 from public.raw_material_purchases opening
              where opening.material_type='tape_bundle' and opening.record_type='opening_stock'
            )
            or r.record_type='opening_stock'
            or r.purchase_date >= (
              select min(opening.purchase_date)
              from public.raw_material_purchases opening
              where opening.material_type='tape_bundle' and opening.record_type='opening_stock'
            )
          )
      ),0)
      -coalesce((
        select sum(p.quantity/70::numeric)
        from public.production p
        where p.product_type in ('500ml','1.5L')
          and p.production_date<=p_month_end
          and (
            not exists (
              select 1 from public.raw_material_purchases opening
              where opening.material_type='tape_bundle' and opening.record_type='opening_stock'
            )
            or p.production_date >= (
              select min(opening.purchase_date)
              from public.raw_material_purchases opening
              where opening.material_type='tape_bundle' and opening.record_type='opening_stock'
            )
          )
      ),0),$frag$;
  if position(v_old in v_def)=0 then raise exception 'Monthly tape stock estimate insertion point not found'; end if;
  v_def := replace(v_def,v_old,v_new);
  execute v_def;
end
$migration$;
