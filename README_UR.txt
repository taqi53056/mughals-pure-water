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

اہم حفاظتی نوٹ:
1. لائیو Supabase میں Owner migration اور Carton price repair پہلے کامیابی سے چلائی جا چکی ہیں۔ موجودہ ڈیٹابیس پر انہیں دوبارہ نہ چلائیں۔
2. یہ repository مکمل ابتدائی Supabase schema نہیں ہے۔ نئے Supabase project کے لیے بنیادی V2 schema اور MUGHALS_MASTER_SUPABASE.sql درکار ہیں؛ وہ master SQL اس repository میں شامل نہیں۔ اس package کو اکیلے نئے ڈیٹابیس کی تنصیب نہ سمجھیں۔
3. GitHub branch پر موجود SQL فائلیں تاریخی/منتخب migration فائلیں ہیں، روزمرہ deployment کے لیے دوبارہ چلانے کی ہدایت نہیں۔
4. ایپ میں 500ml اور 1.5L کے کارٹن کی قیمت کم از کم Rs.280 ہے؛ 6L کی قیمت Rs.55 ہے۔ کارٹن مزدوری Rs.10 فی کارٹن ہے۔
5. 19L کامیاب بوتل Rs.100، ڈلیوری مزدوری Rs.20 فی بوتل، خراب ڈھکن Rs.10 ہے۔
6. ماہانہ بل اور notification function لائیو Supabase میں اپڈیٹ ہے؛ cron schedule 23:55 پاکستان وقت (28 تا 31 تاریخ) ہے۔ اصل ماہانہ run اور کسٹمر notification کا end-to-end ثبوت ابھی موجود نہیں کیونکہ فعال کسٹمر صفر ہیں اور حالیہ cron run درج نہیں۔

اس برانچ میں موجود ایپ تبدیلیاں:
- ایڈمن کے لیے کسٹمر کا مکمل اکاؤنٹ: پروفائل، بل، ادائیگیاں، ڈلیوری ہسٹری اور بیلنس۔
- بڑی مقدار/رقم پر save سے پہلے تصدیق۔
- شکایات کے جواب اور متعلقہ customer notification۔
- آمدن/اخراجات میں ترمیم اور حذف۔
- آڈٹ لاگ میں پرانی اور نئی تفصیل۔
- Owner کی بچت اور ورکر کی واجب الادا مزدوری الگ۔
- تفصیلی ماہانہ بل notification اور کسٹمر بل breakdown۔
- Service Worker cache version v19۔

تصدیق کی موجودہ حد:
- HTML/JavaScript syntax، Service Worker syntax، manifest JSON، IDs اور onclick function references کی جامد جانچ پاس ہوئی۔
- GitHub branch main سے 4 commits آگے ہے؛ ابھی main میں merge/deploy نہیں ہوئی۔
- اس مرحلے پر live browser runtime، تمام Supabase RPC، RLS isolation، حقیقی stock/production/sales/labor اور ماہانہ billing کا مکمل end-to-end test نہیں ہوا۔
- GitHub Pages پر publish کرنے سے پہلے یہ عملی ٹیسٹ ضروری ہیں۔ صرف syntax پاس ہونا production readiness کا ثبوت نہیں۔

Deployment اصول:
- صرف مکمل جانچ کے بعد اس branch کو main میں merge کریں۔
- GitHub Pages کے لیے repository root کی index.html، manifest، SW اور icons برقرار رکھیں۔
- merge/deploy کے بعد cache update اور login smoke test کریں۔
