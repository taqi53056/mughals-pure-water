# MUGHAL'S PURE WATER

اردو RTL پانی کے کاروبار کی مینجمنٹ ایپ (PWA)۔

- تفصیلی اردو تکنیکی/ڈپلائمنٹ نوٹس: [README_UR.txt](README_UR.txt)
- مختصر ریلیز نوٹس: [README_URDU.txt](README_URDU.txt)

**Deployment warning:** static validation اور Playwright desktop/mobile smoke tests پاس ہیں (RTL، login/signup navigation، PWA manifest، no horizontal overflow، 19L labor math، bulk carton pricing، admin price-floor controls)؛ تاہم real authenticated customer isolation، stock/sales/production، worker ledger اور حقیقی month-end billing/notification کے end-to-end tests ابھی مکمل نہیں۔ ان کی تصدیق سے پہلے `main` پر merge/deploy نہ کریں۔

**Database warning:** موجودہ Supabase پر پہلے سے موجود V2/master schema اور incremental migrations کو دوبارہ نہ چلائیں۔ `MUGHALS_SECURITY_PERFORMANCE_REPAIR_20261109.sql`، `MUGHALS_RLS_POLICY_CONSOLIDATION_20261109.sql` اور `MUGHALS_PRODUCT_PRICE_SETTINGS_GUARD_20261109.sql` میں 2026-11-09 کو live database پر لاگو کی گئی اضافی repairs کا ریکارڈ ہے؛ انہیں اسی live project پر دوبارہ چلانے کی ضرورت نہیں۔ بنیادی V2/master schema اس repository میں شامل نہیں۔
