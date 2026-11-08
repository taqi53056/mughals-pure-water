MUGHAL'S PURE WATER — موجودہ برانچ کی تکنیکی دستاویز

برانچ: integration-access-check-20261109
ایپ: اردو RTL، موبائل/ڈیسک ٹاپ، PWA
مرکزی فائلیں:
- index.html — ایپ، لاگ اِن، کسٹمر/ایڈمن پینل اور تمام ماڈیولز
- manifest.webmanifest — PWA شناخت
- SW.js — Service Worker؛ موجودہ cache version v19
- icon.svg، icon-192.png، icon-512.png — ایپ آئیکنز
- MUGHALS_FINAL_OWNER_MIGRATION.sql — Owner اور ورکر اجرت کی علیحدگی
- MUGHALS_CARTON_PRICE_FLOOR_REPAIR.sql — کارٹن قیمت کی کم از کم حد اور 5-parameter سیل RPC
- MUGHALS_SECURITY_PERFORMANCE_REPAIR_20261109.sql — live Supabase پر لاگو اضافی security/performance repairs کا ریکارڈ

اہم حفاظتی نوٹ:
1. لائیو Supabase میں Owner migration، Carton price repair اور 2026-11-09 کی security/performance repairs کامیابی سے لاگو ہو چکی ہیں۔ موجودہ ڈیٹابیس پر انہیں دوبارہ چلانے کی ضرورت نہیں۔
2. یہ repository مکمل ابتدائی Supabase schema نہیں ہے۔ نئے Supabase project کے لیے بنیادی V2 schema اور MUGHALS_MASTER_SUPABASE.sql درکار ہیں؛ وہ master SQL اس repository میں شامل نہیں۔ اس package کو اکیلے نئے ڈیٹابیس کی تنصیب نہ سمجھیں۔
3. GitHub branch پر موجود SQL فائلیں تاریخی/منتخب migration فائلیں ہیں؛ production database پر دوبارہ چلانے سے پہلے target schema اور migration state لازماً چیک کریں۔
4. ایپ میں 500ml اور 1.5L کے کارٹن کی قیمت کم از کم Rs.280 ہے؛ 6L کی قیمت Rs.55 ہے۔ کارٹن مزدوری Rs.10 فی کارٹن ہے۔
5. 19L کامیاب بوتل Rs.100، ڈلیوری مزدوری Rs.20 فی بوتل، خراب ڈھکن Rs.10 ہے۔
6. ماہانہ بل اور notification function لائیو Supabase میں موجود ہے؛ cron schedule 23:55 پاکستان وقت (28 تا 31 تاریخ) ہے۔ 2026-11-09 کو non-month-end guard test نے 0 واپس کیا۔ اصل ماہانہ run اور کسٹمر notification کا end-to-end ثبوت ابھی موجود نہیں کیونکہ فعال کسٹمر صفر ہیں اور حالیہ cron run درج نہیں۔

اس برانچ میں موجود ایپ تبدیلیاں:
- ایڈمن کے لیے کسٹمر کا مکمل اکاؤنٹ: پروفائل، بل، ادائیگیاں، ڈلیوری ہسٹری اور بیلنس۔
- بڑی مقدار/رقم پر save سے پہلے تصدیق؛ مالی انٹری Rs.1,000 سے اوپر ہو تو دوبارہ تصدیق، جبکہ بڑی پیداوار/اسٹاک/ڈلیوری مقدار پر الگ حد۔
- شکایات کے جواب اور متعلقہ customer notification۔
- آمدن/اخراجات میں ترمیم اور حذف۔
- آڈٹ لاگ میں پرانی اور نئی تفصیل۔
- Owner کی بچت اور ورکر کی واجب الادا مزدوری الگ۔
- تفصیلی ماہانہ بل notification اور کسٹمر بل breakdown۔
- Service Worker cache version v19۔

Supabase live verification:
- 27/27 public tables پر RLS فعال؛ کوئی public table RLS کے بغیر نہیں۔
- تین مستقل admin profiles اور تین Auth users برقرار ہیں؛ کوئی اضافی test user نہیں۔
- 19L customers/deliveries/bills/payments/notifications/complaints کا کاروباری ڈیٹا صفر ہے؛ کوئی فرضی customer یا billing test record شامل نہیں کیا گیا۔
- تین trigger/legacy RPC function search_path درست کیا اور دوبارہ verify کیا۔
- 16 unindexed foreign-key columns کے indexes شامل کیے؛ verification میں missing FK indexes صفر۔
- customer-scoped policies میں auth.uid() کو statement-level subquery میں wrap کیا۔
- rollback-only billing calculation test میں 3 بوتلیں، 2 خراب ڈھکن، Rs.80 خالص ادائیگی، Rs.20 سابقہ ایڈوانس اور Rs.50 سابقہ بقایا سے Rs.270 بقایا درست نکلا؛ تمام test rows rollback ہو گئیں۔
- خالی customer table میں اگلا customer code rollback-only test سے C001 verify ہوا۔
- duplicate monthly-bill unique constraint ہٹایا؛ بنیادی (customer_id, bill_month) unique constraint برقرار ہے۔
- Security advisors میں اب بھی authenticated SECURITY DEFINER RPC warnings ہیں؛ متعلقہ functions میں admin/customer ownership checks موجود ہیں، اس لیے انہیں blindly revoke نہیں کیا گیا۔ Leaked-password protection dashboard-level setting ابھی فعال نہیں۔
- Performance advisor کے unused-index نوٹس نئی/خالی tables کے سبب ہیں؛ production workload کے بغیر انہیں حذف نہیں کیا گیا۔

تصدیق کی موجودہ حد:
- GitHub Actions static validation workflow کامیابی سے پاس ہوا: HTML shell، unique IDs، local assets، onclick handlers، manifest JSON، inline JavaScript، Service Worker syntax اور پرانی Kiswa branding۔
- GitHub branch ابھی main میں merge/deploy نہیں ہوئی۔
- Live browser runtime، حقیقی customer sign-in کے ذریعے RLS isolation، stock/production/sales/worker ledger اور مکمل ماہانہ billing notification کا end-to-end test ابھی مکمل نہیں۔
- GitHub Pages پر publish کرنے سے پہلے یہ عملی ٹیسٹ ضروری ہیں۔ صرف syntax یا database advisor صاف ہونا production readiness کا مکمل ثبوت نہیں۔

Deployment اصول:
- صرف مکمل عملی جانچ کے بعد اس branch کو main میں merge کریں۔
- GitHub Pages کے لیے repository root کی index.html، manifest، SW اور icons برقرار رکھیں۔
- merge/deploy کے بعد cache update اور login smoke test کریں۔
