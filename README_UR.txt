MUGHAL'S PURE WATER — UPDATED DEPLOYMENT PACKAGE

اس پیکج میں
- index.html — اپڈیٹ شدہ اردو RTL ایپ
- manifest.webmanifest — PWA معلومات
- SW.js — سروس ورکر؛ نیا cache version تاکہ نئی فائل لوڈ ہو
- MUGHALS_CARTON_PRICE_FLOOR_REPAIR.sql — کارٹن کی کم از کم قیمت Rs.280 اور 6L کی Rs.55 کی database پابندی
- icon-192.png / icon-512.png — ایپ آئیکنز
- MUGHALS_FINAL_OWNER_MIGRATION.sql — Owner اور ورکر اجرت کی علیحدگی کی حتمی migration

اہم SQL نوٹ
اس پروجیکٹ میں دونوں migration فائلیں شامل ہیں۔ موجودہ live project میں Owner migration اور Carton price floor repair پہلے ہی کامیابی سے چلائی جا چکی ہیں؛ اس لیے اس deployment کے لیے انہیں دوبارہ چلانے کی ضرورت نہیں۔ اگر کسی نئے/بحال شدہ Supabase project پر setup کرنا ہو تو پہلے بنیادی V2 schema اور MUGHALS_MASTER_SUPABASE.sql مکمل کریں، پھر Owner migration اور آخر میں Carton price floor repair چلائیں۔ کسی موجودہ live database پر SQL دوبارہ چلانے سے پہلے backup اور موجودہ schema کی تصدیق ضروری ہے۔

ایپ میں شامل اصلاحات
- ایڈمن گاہکوں کی فہرست سے مکمل اکاؤنٹ کھول سکتا ہے: profile، تمام ماہانہ بل، تمام ادائیگیاں، 19L ڈلیوری ہسٹری، تازہ بقایا اور closing advance۔ queries منتخب customer_id تک محدود ہیں۔
- غیر معمولی بڑی مقدار/رقم پر save سے پہلے تصدیق۔
- Official branding: MUGHAL'S PURE WATER۔

اہم حد
اس پیکج کی فائلیں اور JavaScript syntax مقامی طور پر چیک کی گئی ہیں۔ Live Supabase پر پہلے سے چلائی گئی migrations کی کامیابی کے علاوہ، اس مرحلے پر deployed PWA کے ذریعے end-to-end browser test نہیں کیا گیا، اور GitHub deployment بھی نہیں کیا گیا۔ حقیقی login، RLS، billing، stock اور worker workflow کی آخری تصدیق live deployed app پر ضروری ہے۔


اس اپڈیٹ میں اضافی درستگی
- 500ml اور 1.5L پروڈکشن محفوظ کرنے سے پہلے مالک اور مزدوروں کی تقسیم لازمی ہے؛ تقسیم شدہ کارٹن کل پروڈکشن کے عین برابر ہونے چاہئیں۔
- Service Worker cache version اپڈیٹ کیا گیا ہے تاکہ نیا کوڈ پرانے cache سے نہ چلے۔
- یہ مقامی فائل کی اصلاح ہے؛ live Supabase یا GitHub پر کوئی تبدیلی نہیں کی گئی۔
