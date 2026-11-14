do $migration$
declare v_def text; v_old text; v_new text;
begin
  v_def := pg_get_functiondef('private.record_production_with_workers(date,text,integer,jsonb,uuid)'::regprocedure);
  v_old := '-- ٹیپ کا استعمال الگ جسمانی گنتی/درست ریکارڈ کے بغیر خودکار طور پر منہا نہیں کیا جاتا.';
  v_new := '-- Tape is consumed and validated at one bundle per 70 cartons by the production packaging stock guard.';
  if position(v_old in v_def)=0 then raise exception 'Outdated tape policy comment not found in production RPC'; end if;
  v_def := replace(v_def,v_old,v_new);
  execute v_def;
end
$migration$;
