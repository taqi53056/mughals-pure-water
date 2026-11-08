MUGHAL'S PURE WATER — مختصر ریلیز نوٹس

برانچ: integration-access-check-20261109
موجودہ Service Worker cache: v23

اہم فائلیں:
- index.html — مکمل فرنٹ اینڈ
- manifest.webmanifest — PWA سیٹنگز
- SW.js — cache اور offline shell
- icon.svg، icon-192.png، icon-512.png — آئیکنز
- MUGHALS_FINAL_OWNER_MIGRATION.sql — Owner/ورکر اجرت کی علیحدگی
- MUGHALS_CARTON_PRICE_FLOOR_REPAIR.sql — کم از کم قیمت اور سیل RPC
- MUGHALS_SECURITY_PERFORMANCE_REPAIR_20261109.sql — live Supabase security/performance repairs کا ریکارڈ
- MUGHALS_RLS_POLICY_CONSOLIDATION_20261109.sql — final RLS policy consolidation اور invoker RPC hardening
- MUGHALS_PRODUCT_PRICE_SETTINGS_GUARD_20261109.sql — bulk special price، fixed pack/labor، اور fixed 6L rate database guards

قیمتوں کے اصول:
- 500ml کارٹن: 24 یونٹ، کم از کم Rs.280
- 1.5L کارٹن: 12 یونٹ، کم از کم Rs.280
- 6L: 18 بوتلوں کا پیک، Rs.55 فی بوتل
- کارٹن مزدوری: Rs.10 فی کارٹن
- 19L: Rs.100 فی کامیاب بوتل، ڈلیوری مزدوری Rs.20، خراب ڈھکن Rs.10

Supabase:
- 27 public tables پر RLS فعال اور verify ہے۔
- تین مستقل admin profiles اور موجودہ قیمتیں verify ہیں؛ customer PIN fields کی browser access بند ہے۔
- trigger/legacy RPC search_path درست؛ 16 FK indexes شامل؛ customer-scoped RLS policies optimize؛ duplicate monthly bill unique constraint صاف۔
- ماہانہ cron فعال ہے، لیکن حقیقی month-end run ابھی نہیں ہوا کیونکہ active customers صفر ہیں۔
- موجودہ database پر پرانی migrations دوبارہ نہ چلائیں؛ بنیادی V2/master schema اس repository میں شامل نہیں۔
- admin-facing RPCs اب SECURITY INVOKER ہیں؛ صرف customer notification-read helper SECURITY DEFINER ہے اور customer ownership check کرتا ہے۔ Multiple permissive policy warnings صفر ہیں۔
- leaked-password protection کی setting ابھی dashboard پر باقی ہے۔

اس برانچ میں شامل کام:
- مکمل کسٹمر اکاؤنٹ ویو
- ایڈمن کنٹرول سینٹر سے محفوظ پروڈکٹ قیمت ترمیم؛ 100+ کارٹن پر خصوصی قیمت خود لاگو؛ یہ default قیمت سے زیادہ یا Rs.280 سے کم نہیں ہوسکتی۔ 6L قیمت Rs.55 مقرر
- بڑی انٹری کی تصدیق (مالی رقم Rs.1,000 سے اوپر؛ پیداوار/اسٹاک/ڈلیوری مقدار پر الگ حد)
- شکایات اور ایڈمن جواب
- آمدن/اخراجات edit/delete
- audit log میں before/after details
- Owner savings اور worker wages کی علیحدگی
- ماہانہ بل کی تفصیلی اطلاع
- سکیورٹی اور کارکردگی کی database repairs

ریلیز کی حد:
- GitHub Actions static validation پاس ہے؛ database-side schema، RLS، admin guard اور rollback-only billing math checks بھی verify ہیں۔
- desktop/mobile browser smoke test میں RTL/PWA، 19L حساب، مالک کی مزدوری بچت، admin price floor اور 100+ carton special rate کے ٹیسٹ پاس ہیں؛ حقیقی کسٹمر RLS isolation، stock/production/sales/worker ledger اور مکمل ماہانہ notification کے end-to-end tests باقی ہیں۔
- ان tests کے مکمل ہونے تک اسے final production-verified release نہ کہیں اور main میں merge/deploy نہ کریں۔
