do $migration$
declare v_def text; v_old text; v_new text;
begin
  v_def := pg_get_functiondef('public.build_business_monthly_report(date,date)'::regprocedure);
  v_old := 'and v_sticker500 is not null then';
  v_new := 'and v_sticker500 is not null and v_tape is not null then';
  if position(v_old in v_def)=0 then raise exception '500ml cost completeness condition not found'; end if;
  v_def := replace(v_def,v_old,v_new);
  v_old := 'and v_sticker_shared is not null then';
  v_new := 'and v_sticker_shared is not null and v_tape is not null then';
  if position(v_old in v_def)=0 then raise exception '1.5L cost completeness condition not found'; end if;
  v_def := replace(v_def,v_old,v_new);
  execute v_def;
end
$migration$;