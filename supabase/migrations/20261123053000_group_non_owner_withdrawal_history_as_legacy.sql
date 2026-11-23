do $patch$
declare
  v_def text;
  v_new text;
  v_old_filter text := 'counterparty IN (''محمد رفیع مغل'',''M. Rafi Mughal'')';
  v_new_filter text := 'counterparty IS DISTINCT FROM ''محمد اسامہ مغل'' AND counterparty IS DISTINCT FROM ''M.Usama Mughal'' AND counterparty IS DISTINCT FROM ''M. Usama Mughal'' AND counterparty IS DISTINCT FROM ''محمد مزمل مغل'' AND counterparty IS DISTINCT FROM ''M. Muzamil Mughal'' AND counterparty IS DISTINCT FROM ''محمد تقی مغل'' AND counterparty IS DISTINCT FROM ''M.Taqi Mughal''';
begin
  select pg_get_functiondef('public.build_business_monthly_report(date,date)'::regprocedure) into v_def;
  v_new:=replace(v_def,v_old_filter,v_new_filter);
  v_new:=replace(v_new,'''M. Rafi Mughal'',v_owner4','''other_legacy_recipients'',v_owner4');
  if v_new=v_def then
    if position('other_legacy_recipients' in v_def)>0 then return; end if;
    raise exception 'Could not safely identify legacy recipient fields in monthly report.';
  end if;
  if position('other_legacy_recipients' in v_new)=0 or position(v_new_filter in v_new)=0 then
    raise exception 'Monthly report owner grouping verification failed.';
  end if;
  execute v_new;
end
$patch$;
