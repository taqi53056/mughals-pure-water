do $migration$
declare v_def text; v_old text; v_new text;
begin
  v_def := pg_get_functiondef('private.mpw_guard_production_packaging_stock()'::regprocedure);
  v_old := $frag$('tape_bundle'::text,0::numeric),$frag$;
  v_new := $frag$('tape_bundle'::text,case when new.product_type in ('500ml','1.5L') then new.quantity/70::numeric else 0 end),$frag$;
  if position(v_old in v_def)=0 then raise exception 'Expected tape requirement fragment not found'; end if;
  v_def := replace(v_def,v_old,v_new);

  v_old := $frag$          when 'sticker_500ml' then case when p.product_type='500ml' then p.quantity*24 else 0 end$frag$;
  v_new := $frag$          when 'tape_bundle' then coalesce(sum(p.quantity/70::numeric) filter(where p.product_type in ('500ml','1.5L')),0)
          when 'sticker_500ml' then case when p.product_type='500ml' then p.quantity*24 else 0 end$frag$;
  if position(v_old in v_def)=0 then raise exception 'Expected tape consumption CASE insertion point not found'; end if;
  v_def := replace(v_def,v_old,v_new);
  execute v_def;

  v_def := pg_get_functiondef('private.mpw_guard_raw_material_opening_stock()'::regprocedure);
  v_old := $frag$        WHEN 'tape_bundle' THEN 0::numeric$frag$;
  v_new := $frag$        WHEN 'tape_bundle' THEN coalesce(sum(p.quantity/70::numeric) FILTER(WHERE p.product_type IN ('500ml','1.5L')),0)$frag$;
  if position(v_old in v_def)=0 then raise exception 'Expected tape opening-stock consumption fragment not found'; end if;
  v_def := replace(v_def,v_old,v_new);
  execute v_def;

  v_def := pg_get_functiondef('public.build_business_monthly_report(date,date)'::regprocedure);
  v_old := 'v_carton500+24*v_sticker500';
  v_new := 'v_carton500+24*v_sticker500+coalesce(v_tape,0)/70';
  if position(v_old in v_def)=0 then raise exception '500ml tape cost insertion point not found'; end if;
  v_def := replace(v_def,v_old,v_new);
  v_old := 'v_carton15+12*v_sticker_shared';
  v_new := 'v_carton15+12*v_sticker_shared+coalesce(v_tape,0)/70';
  if position(v_old in v_def)=0 then raise exception '1.5L tape cost insertion point not found'; end if;
  v_def := replace(v_def,v_old,v_new);
  v_old := 'پیکنگ ٹیپ کا حقیقی استعمال ابھی متعین نہیں؛ اسے اسٹاک کے باقی بیلنس اور 500ml/1.5L مصنوعات کی فی یونٹ لاگت سے خارج رکھا گیا ہے، اس لیے ان مصنوعات کا حقیقی منافع ٹیپ کی لاگت شامل ہونے تک زیادہ دکھ سکتا ہے۔';
  v_new := 'پیکنگ ٹیپ کا حساب ایک بنڈل فی 70 عدد 500ml یا 1.5L کارٹن کے تناسب سے ہے؛ فی کارٹن ٹیپ لاگت اوسط درج شدہ بنڈل قیمت/70 ہے۔';
  if position(v_old in v_def)=0 then raise exception 'Monthly report tape disclosure text not found'; end if;
  v_def := replace(v_def,v_old,v_new);
  execute v_def;
end
$migration$;