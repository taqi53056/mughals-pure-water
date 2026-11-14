# MUGHAL'S PURE WATER

اردو RTL پانی کے کاروبار کی مینجمنٹ ایپ (PWA)۔

- تفصیلی اردو تکنیکی/ڈپلائمنٹ نوٹس: [README_UR.txt](README_UR.txt)
- مختصر ریلیز نوٹس: [README_URDU.txt](README_URDU.txt)
- موجودہ release gates اور اگلے verification steps: [RELEASE_READINESS_20261109.md](RELEASE_READINESS_20261109.md)
- 2026-11-10 برانڈ اور تاریخی ڈلیوری جانچ: [RELEASE_READINESS_20261110.md](RELEASE_READINESS_20261110.md)
- 2026-11-13 تازہ ریلیز اور 19L/اسٹاک تصدیقی نتائج: [RELEASE_READINESS_20261113.md](RELEASE_READINESS_20261113.md)
- 2026-11-14 جامع سکیورٹی، ایڈمن نیویگیشن، آج کی سرگرمی اور ڈیٹا سالمیت آڈٹ: [RELEASE_READINESS_20261114.md](RELEASE_READINESS_20261114.md)

**Security note:** Supabase organization is on the Free plan. Leaked-password protection is a Pro-and-above feature and is unavailable on this plan. Public admin write RPCs use SECURITY INVOKER wrappers; their privileged private helpers enforce `auth.uid()` and `public.is_admin()` with a pinned empty `search_path`. The admin product-sale and store-credit receipt wrappers no longer inherit PUBLIC execution. Do not remove the private admin checks or revoke authenticated execution without replacing the app workflow. Current Security Advisor reports only the leaked-password plan limitation.

**Deployment warning:** static validation and desktop/mobile Playwright smoke tests pass. These tests do not simulate authenticated customer accounts or full live business transactions. Rollback-only database tests now cover sticker kg purchase/yield/production for all three product types and 19L multiple-same-day/customer-owned bottle custody. Live end-to-end customer isolation, real customer payment/billing, push delivery, external messaging and scheduled month-end notification still require separate controlled verification. Do not interpret smoke tests as proof that every live workflow is error-free.

**Database warning:** موجودہ Supabase پر پہلے سے موجود V2/master schema اور incremental migrations کو دوبارہ نہ چلائیں۔ `MUGHALS_SECURITY_PERFORMANCE_REPAIR_20261109.sql`، `MUGHALS_RLS_POLICY_CONSOLIDATION_20261109.sql` اور `MUGHALS_PRODUCT_PRICE_SETTINGS_GUARD_20261109.sql`، `MUGHALS_19L_DELIVERY_GUARD_20261109.sql`، `MUGHALS_BILLING_GUARD_20261109.sql` اور `MUGHALS_OWNER_WORKER_GUARD_20261109.sql` میں 2026-11-09 کو live database پر لاگو کی گئی اضافی repairs کا ریکارڈ ہے؛ انہیں اسی live project پر دوبارہ چلانے کی ضرورت نہیں۔ بنیادی V2/master schema اس repository میں شامل نہیں۔
