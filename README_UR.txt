MUGHAL'S PURE WATER — موجودہ برانچ کی تکنیکی دستاویز

برانچ: integration-access-check-20261109
ایپ: اردو RTL، موبائل/ڈیسک ٹاپ، PWA
مرکزی فائلیں:
- index.html — ایپ، لاگ اِن، کسٹمر/ایڈمن پینل اور تمام ماڈیولز
- manifest.webmanifest — PWA شناخت
- SW.js — Service Worker؛ موجودہ cache version v23
- icon.svg، icon-192.png، icon-512.png — ایپ آئیکنز
- MUGHALS_FINAL_OWNER_MIGRATION.sql — Owner اور ورکر اجرت کی علیحدگی
- MUGHALS_CARTON_PRICE_FLOOR_REPAIR.sql — کارٹن قیمت کی کم از کم حد اور 5-parameter سیل RPC
- MUGHALS_SECURITY_PERFORMANCE_REPAIR_20261109.sql — live Supabase پر لاگو اضافی security/performance repairs کا ریکارڈ
- MUGHALS_RLS_POLICY_CONSOLIDATION_20261109.sql — final RLS policy consolidation اور invoker RPC hardening
- MUGHALS_PRODUCT_PRICE_SETTINGS_GUARD_20261109.sql — 100+ کارٹن خصوصی قیمت، مقررہ پیک سائز/مزدوری اور 6L کی Rs.55 قیمت کے database guards
- MUGHALS_19L_DELIVERY_GUARD_20261109.sql — 19L بوتل/واپسی/کامیاب بوتل/فرق/ڈھکن کی backend حدود
- MUGHALS_BILLING_GUARD_20261109.sql — ماہانہ بل میں بوتل/ڈھکن چارج، بقایا، ایڈوانس اور closing due کی consistency

اہم حفاظتی نوٹ:
1. لائیو Supabase میں Owner migration، Carton price repair اور 2026-11-09 کی security/performance repairs کامیابی سے لاگو ہو چکی ہیں۔ موجودہ ڈیٹابیس پر انہیں دوبارہ چلانے کی ضرورت نہیں۔
2. یہ repository مکمل ابتدائی Supabase schema نہیں ہے۔ نئے Supabase project کے لیے بنیادی V2 schema اور MUGHALS_MASTER_SUPABASE.sql درکار ہیں؛ وہ master SQL اس repository میں شامل نہیں۔ اس package کو اکیلے نئے ڈیٹابیس کی تنصیب نہ سمجھیں۔
3. GitHub branch پر موجود SQL فائلیں تاریخی/منتخب migration فائلیں ہیں؛ production database پر دوبارہ چلانے سے پہلے target schema اور migration state لازماً چیک کریں۔
4. ایپ میں 500ml اور 1.5L کے کارٹن کی قیمت کم از کم Rs.280 ہے؛ 6L کی قیمت Rs.55 ہے۔ کارٹن مزدوری Rs.10 فی کارٹن ہے۔
5. 19L کامیاب بوتل Rs.100، ڈلیوری مزدوری Rs.20 فی بوتل، خراب ڈھکن Rs.10 ہے۔
6. ماہانہ بل اور notification function لائیو Supabase میں موجود ہے؛ cron schedule 23:55 پاکستان وقت (28 تا 31 تاریخ) ہے۔ 2026-11-09 کو non-month-end guard test نے 0 واپس کیا۔ اصل ماہانہ run اور کسٹمر notification کا end-to-end ثبوت ابھی موجود نہیں کیونکہ فعال کسٹمر صفر ہیں اور حالیہ cron run درج نہیں۔

اس برانچ میں موجود ایپ تبدیلیاں:
- ایڈمن کے لیے کسٹمر کا مکمل اکاؤنٹ: پروفائل، بل، ادائیگیاں، ڈلیوری ہسٹری اور بیلنس۔
- ترتیبات/کنٹرول سینٹر میں پروڈکٹ قیمتوں کی محفوظ ترمیم؛ 500ml/1.5L کارٹن Rs.280 اور 6L Rs.55 سے کم نہیں ہوسکتے۔ 100 یا زیادہ کارٹن پر configured special_100_rate خود لاگو ہوتی ہے۔ ہر تبدیلی audit log میں درج ہوتی ہے۔
- بڑی مقدار/رقم پر save سے پہلے تصدیق؛ مالی انٹری Rs.1,000 سے اوپر ہو تو دوبارہ تصدیق، جبکہ بڑی پیداوار/اسٹاک/ڈلیوری مقدار پر الگ حد۔
- شکایات کے جواب اور متعلقہ customer notification۔
- آمدن/اخراجات میں ترمیم اور حذف۔
- آڈٹ لاگ میں پرانی اور نئی تفصیل۔
- Owner کی بچت اور ورکر کی واجب الادا مزدوری الگ۔
- تفصیلی ماہانہ بل notification اور کسٹمر بل breakdown۔
- Service Worker cache version v23۔

Supabase live verification:
- 27/27 public tables پر RLS فعال؛ کوئی public table RLS کے بغیر نہیں۔
- تین مستقل admin profiles اور تین Auth users برقرار ہیں؛ کوئی اضافی test user نہیں۔
- 19L customers/deliveries/bills/payments/notifications/complaints کا کاروباری ڈیٹا صفر ہے؛ کوئی فرضی customer یا billing test record شامل نہیں کیا گیا۔
- تین trigger/legacy RPC function search_path درست کیا اور دوبارہ verify کیا۔
- 16 unindexed foreign-key columns کے indexes شامل کیے؛ verification میں missing FK indexes صفر۔
- customer-scoped policies میں auth.uid() کو statement-level subquery میں wrap کیا۔
- rollback-only billing calculation test میں 3 بوتلیں، 2 خراب ڈھکن، Rs.80 خالص ادائیگی، Rs.20 سابقہ ایڈوانس اور Rs.50 سابقہ بقایا سے Rs.270 بقایا درست نکلا؛ تمام test rows rollback ہو گئیں۔
- خالی customer table میں اگلا customer code rollback-only test سے C001 verify ہوا۔
- پروڈکشن allocation کا rollback-only test پاس: 10 کارٹن پر generated allocation labor Rs.100، worker ledger Rs.100، اور production labor Rs.100؛ تمام test rows rollback ہو گئیں۔
- سیل RPC کا rollback-only test پاس: ایک 500ml کارٹن Rs.300 میں درج ہوا، stock صفر ہوا، مالک کی مزدوری بچت Rs.10 رپورٹ ہوئی؛ تمام test rows rollback ہو گئیں۔
- product_settings کا rollback-only admin update test پاس: default Rs.300، special Rs.290 محفوظ ہوئے اور audit actor درست ریکارڈ ہوا؛ تبدیلی rollback ہوگئی۔ Database نے Rs.280 سے کم carton price اور default سے زیادہ special price دونوں رد کیے۔
- duplicate monthly-bill unique constraint ہٹایا؛ بنیادی (customer_id, bill_month) unique constraint برقرار ہے۔
- customers table پر column-level grants لگائے: browser users صرف ضروری account columns پڑھ/اپڈیٹ کر سکتے ہیں؛ PIN، PIN hash اور PIN enabled fields تک رسائی بند ہے۔
- تمام admin-facing data RPCs کو SECURITY INVOKER پر منتقل کیا اور is_admin() کو fixed admin UUID allowlist پر مبنی SECURITY INVOKER بنایا؛ صرف mark_customer_notification_read SECURITY DEFINER رہتا ہے کیونکہ کسٹمر کو notification content پر براہِ راست UPDATE حق نہیں دیا گیا، اور فنکشن صرف اسی auth.uid() سے منسلک کسٹمر کی اطلاع پڑھا ہوا نشان زد کرتا ہے۔
- RLS policy consolidation کے بعد multiple permissive policy warnings صفر ہیں۔ صرف mark_customer_notification_read کا ایک intentional SECURITY DEFINER warning باقی ہے؛ Supabase organization Free plan پر ہے، اور leaked-password protection Supabase کے مطابق Pro یا اس سے اوپر کے plan میں دستیاب ہے، اس لیے موجودہ plan پر فعال نہیں ہوسکتی۔
- Performance advisor کے unused-index نوٹس نئی/خالی tables کے سبب ہیں؛ production workload کے بغیر انہیں حذف نہیں کیا گیا۔

تصدیق کی موجودہ حد:
- GitHub Actions static validation اور Playwright desktop/mobile browser smoke tests کامیابی سے پاس ہوئے: HTML shell، unique IDs، local assets، onclick handlers، manifest JSON، inline JavaScript، Service Worker، RTL layout، login/signup navigation، 19L کامیاب بوتل/مزدوری حساب، مالک کی بچت، 100+ کارٹن خصوصی قیمت، قیمت کی کم از کم حد اور پرانی Kiswa branding۔
- GitHub branch ابھی main میں merge/deploy نہیں ہوئی۔
- بنیادی browser smoke test پاس ہے، مگر حقیقی customer sign-in کے ذریعے RLS isolation، مکمل stock/production/sales/worker ledger UI workflows اور ماہانہ cron notification کا مکمل end-to-end test ابھی باقی ہے۔
- GitHub Pages پر publish کرنے سے پہلے یہ عملی ٹیسٹ ضروری ہیں۔ صرف syntax یا database advisor صاف ہونا production readiness کا مکمل ثبوت نہیں۔

Deployment اصول:
- صرف مکمل عملی جانچ کے بعد اس branch کو main میں merge کریں۔
- GitHub Pages کے لیے repository root کی index.html، manifest، SW اور icons برقرار رکھیں۔
- merge/deploy کے بعد cache update اور login smoke test کریں۔
