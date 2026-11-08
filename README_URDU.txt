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

قیمتوں کے اصول:
- 500ml کارٹن: 24 یونٹ، کم از کم Rs.280
- 1.5L کارٹن: 12 یونٹ، کم از کم Rs.280
- 6L: 18 بوتلوں کا پیک، Rs.55 فی بوتل
- کارٹن مزدوری: Rs.10 فی کارٹن
- 19L: Rs.100 فی کامیاب بوتل، ڈلیوری مزدوری Rs.20، خراب ڈھکن Rs.10

اہم:
- دونوں incremental SQL migrations لائیو Supabase میں پہلے چل چکی ہیں؛ انہیں دوبارہ نہ چلائیں۔
- بنیادی V2/master Supabase schema اس repository میں موجود نہیں؛ یہ repository اکیلی نئے Supabase project کی مکمل setup نہیں۔
- پرانی 3-parameter/ Rs.270 والی سیل SQL فائل متروک تھی اور ہٹا دی گئی ہے۔ موجودہ UI پانچ parameters والا RPC استعمال کرتا ہے۔
- ماہانہ cron 23:55 پاکستان وقت پر فعال ہے؛ مگر حقیقی ماہانہ execution ابھی ثابت نہیں۔
- جامد syntax checks پاس ہیں، مگر live browser اور مکمل end-to-end workflow tests باقی ہیں۔
- جب تک عملی ٹیسٹ مکمل نہ ہوں، اسے final production verified release نہ کہیں۔

اس برانچ میں شامل کام:
- مکمل کسٹمر اکاؤنٹ ویو
- بڑی انٹری کی تصدیق
- شکایات اور ایڈمن جواب
- آمدن/اخراجات edit/delete
- audit log میں before/after details
- Owner savings اور worker wages کی علیحدگی
- ماہانہ بل کی تفصیلی اطلاع
