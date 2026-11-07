MUGHAL'S PURE WATER — تازہ ایپ پیکج

فائلیں:
- index.html: ایپ کا مرکزی صفحہ
- manifest.webmanifest: PWA شناخت اور انسٹال سیٹنگز
- SW.js: Service Worker اور cache version v18
- icon.svg: ایپ آئیکن
- MUGHALS_CARTON_PRICE_FLOOR_REPAIR.sql: پہلے سے چلائی گئی DB repair (دوبارہ نہ چلائیں)

اہم قیمت اصول:
- 500ml اور 1.5L کارٹن: کم از کم Rs.280؛ ایڈمن زیادہ قیمت درج کر سکتا ہے۔
- 6L: Rs.55 فی بوتل۔
- کارٹن مزدوری: Rs.10 فی کارٹن۔

تبدیلیاں:
- پرانا Rs.270 / 100-carton special rate ہٹا دیا گیا۔
- سیل انٹری اب record_product_sale کے 5-parameter RPC کو کال کرتی ہے۔
- UI میں قیمت کی حد بھی چیک ہوتی ہے؛ اصل enforcement Supabase میں پہلے commit ہو چکی ہے۔

GitHub Pages پر اپڈیٹ کرتے وقت ZIP کے اندر کی تمام فائلیں repository کے اسی publish folder میں upload/replace کریں۔
یہ ZIP خودکار طور پر GitHub پر deploy نہیں کرتی۔
