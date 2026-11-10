# MUGHAL'S PURE WATER

اردو RTL پانی کے کاروبار کی مینجمنٹ ایپ (PWA)۔

- تفصیلی اردو تکنیکی/ڈپلائمنٹ نوٹس: [README_UR.txt](README_UR.txt)
- مختصر ریلیز نوٹس: [README_URDU.txt](README_URDU.txt)
- موجودہ release gates اور اگلے verification steps: [RELEASE_READINESS_20261109.md](RELEASE_READINESS_20261109.md)
- 2026-11-10 برانڈ، یومیہ ڈلیوری پابندی اور ریلیز جانچ: [RELEASE_READINESS_20261110.md](RELEASE_READINESS_20261110.md)

**Security note:** Supabase organization is on the Free plan. Supabase documents leaked-password protection as Pro-and-above, so it cannot be enabled on the current plan. Three authenticated SECURITY DEFINER RPCs remain: `close_business_month`, `get_management_dashboard`, and `prepare_customer_archive`. Each must retain its explicit admin authorization check; Supabase reports these as warnings for review, not as evidence that the admin checks are absent.

**Deployment warning:** static validation and desktop/mobile Playwright smoke tests pass. These tests do not simulate authenticated customer accounts or full live business transactions. Live end-to-end customer isolation, delivery, payment, production, sales, worker workflows, push delivery and scheduled month-end notification still require separate controlled verification. Do not interpret smoke tests as proof that every live workflow is error-free.

**Database warning:** موجودہ Supabase پر پہلے سے موجود V2/master schema اور incremental migrations کو دوبارہ نہ چلائیں۔ `MUGHALS_SECURITY_PERFORMANCE_REPAIR_20261109.sql`، `MUGHALS_RLS_POLICY_CONSOLIDATION_20261109.sql` اور `MUGHALS_PRODUCT_PRICE_SETTINGS_GUARD_20261109.sql`، `MUGHALS_19L_DELIVERY_GUARD_20261109.sql`، `MUGHALS_BILLING_GUARD_20261109.sql` اور `MUGHALS_OWNER_WORKER_GUARD_20261109.sql` میں 2026-11-09 کو live database پر لاگو کی گئی اضافی repairs کا ریکارڈ ہے؛ انہیں اسی live project پر دوبارہ چلانے کی ضرورت نہیں۔ بنیادی V2/master schema اس repository میں شامل نہیں۔
