MUGHAL'S PURE WATER — مختصر ریلیز نوٹس

برانچ: integration-access-check-20261109
موجودہ Service Worker cache: v19

اہم فائلیں:
- index.html — مکمل فرنٹ اینڈ
- manifest.webmanifest — PWA سیٹنگز
- SW.js — cache اور offline shell
- icon.svg، icon-192.png، icon-512.png — آئیکنز
- MUGHALS_FINAL_OWNER_MIGRATION.sql — Owner/ورکر اجرت کی علیحدگی
- MUGHALS_CARTON_PRICE_FLOOR_REPAIR.sql — کم از کم قیمت اور سیل RPC
- MUGHALS_SECURITY_PERFORMANCE_REPAIR_20261109.sql — live Supabase security/performance repairs کا ریکارڈ

قیمتوں کے اصول:
- 500ml کارٹن: 24 یونٹ، کم از کم Rs.280
- 1.5L کارٹن: 12 یونٹ، کم از کم Rs.280
- 6L: 18 بوتلوں کا پیک، Rs.55 فی بوتل
- کارٹن مزدوری: Rs.10 فی کارٹن
- 19L: Rs.100 فی کامیاب بوتل، ڈلیوری مزدوری Rs.20، خراب ڈھکن Rs.10

Supabase:
- 27 public tables پر RLS فعال اور verify ہے۔
- تین مستقل admin profiles اور موجودہ قیمتیں verify ہیں۔
- trigger/legacy RPC search_path درست؛ 16 FK indexes شامل؛ customer-scoped RLS policies optimize؛ duplicate monthly bill unique constraint صاف۔
- ماہانہ cron فعال ہے، لیکن حقیقی month-end run ابھی نہیں ہوا کیونکہ active customers صفر ہیں۔
- موجودہ database پر پرانی migrations دوبارہ نہ چلائیں؛ بنیادی V2/master schema اس repository میں شامل نہیں۔
- SECURITY DEFINER warnings میں admin/customer ownership checks کی موجودگی verify کی گئی ہے؛ انہیں blind revoke نہیں کیا گیا۔
- leaked-password protection کی setting ابھی dashboard پر باقی ہے۔

اس برانچ میں شامل کام:
- مکمل کسٹمر اکاؤنٹ ویو
- بڑی انٹری کی تصدیق
- شکایات اور ایڈمن جواب
- آمدن/اخراجات edit/delete
- audit log میں before/after details
- Owner savings اور worker wages کی علیحدگی
- ماہانہ بل کی تفصیلی اطلاع
- سکیورٹی اور کارکردگی کی database repairs

ریلیز کی حد:
- static syntax checks اور database-side checks پاس ہیں۔
- live browser، حقیقی کسٹمر RLS isolation، stock/production/sales/worker ledger اور مکمل ماہانہ notification کے end-to-end tests باقی ہیں۔
- ان tests کے مکمل ہونے تک اسے final production-verified release نہ کہیں اور main میں merge/deploy نہ کریں۔
