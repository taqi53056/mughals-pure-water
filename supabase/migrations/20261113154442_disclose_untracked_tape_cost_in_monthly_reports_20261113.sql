DO $$
DECLARE v_oid oid; v_def text; v_old text; v_new text;
BEGIN
 SELECT p.oid INTO v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='build_business_monthly_report'
 AND pg_get_function_identity_arguments(p.oid)='p_month_start date, p_month_end date';
 IF v_oid IS NULL THEN RAISE EXCEPTION 'Monthly business report function not found'; END IF;
 v_def:=pg_get_functiondef(v_oid);
 v_old:=$old$'net_profit_is_estimated',v_counter_litres>0$old$;
 v_new:=$new$'net_profit_is_estimated',(v_counter_litres>0 OR (v_sold500+v_sold15+v_return500+v_return15)>0)$new$;
 IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'Net profit estimate flag not found'; END IF;
 v_def:=replace(v_def,v_old,v_new);
 v_old:=$old$یہ رپورٹ درج شدہ آمدن اور اخراجات پر مبنی ہے۔$old$;
 v_new:=$new$یہ رپورٹ درج شدہ آمدن اور اخراجات پر مبنی ہے۔ پیکنگ ٹیپ کا حقیقی استعمال ابھی متعین نہیں؛ اسے اسٹاک کے باقی بیلنس اور 500ml/1.5L مصنوعات کی فی یونٹ لاگت سے خارج رکھا گیا ہے، اس لیے ان مصنوعات کا حقیقی منافع ٹیپ کی لاگت شامل ہونے تک زیادہ دکھ سکتا ہے۔$new$;
 IF position(v_old in v_def)=0 THEN RAISE EXCEPTION 'Monthly report notes not found'; END IF;
 v_def:=replace(v_def,v_old,v_new);
 EXECUTE v_def;
END $$;
