# MUGHAL'S PURE WATER

اردو RTL پانی کے کاروبار کی مینجمنٹ ایپ (PWA)۔

- تفصیلی اردو تکنیکی/ڈپلائمنٹ نوٹس: [README_UR.txt](README_UR.txt)
- مختصر ریلیز نوٹس: [README_URDU.txt](README_URDU.txt)
- موجودہ release gates اور اگلے verification steps: [RELEASE_READINESS_20261109.md](RELEASE_READINESS_20261109.md)
- 2026-11-10 برانڈ اور تاریخی ڈلیوری جانچ: [RELEASE_READINESS_20261110.md](RELEASE_READINESS_20261110.md)
- 2026-11-13 تازہ ریلیز، 19L بوتل کسٹڈی، اسٹیکر کلوگرام اسٹاک اور تصدیقی نتائج: [RELEASE_READINESS_20261113.md](RELEASE_READINESS_20261113.md)

**Security note:** Supabase organization is on the Free plan. Supabase documents leaked-password protection as Pro-and-above, so it cannot be enabled on the current plan. Four authenticated SECURITY DEFINER RPC endpoints remain intentionally exposed for admin-only operations: `record_production_with_workers`, `record_unassigned_19l_collection`, `record_unassigned_19l_delivery`, and `save_raw_material_purchase_atomic`. Each checks `auth.uid()` and `public.is_admin()` and pins `search_path` to an empty value. Supabase Advisor reports them for review because authenticated users can execute the RPCs; do not remove the admin checks or revoke access without replacing the app workflow. The leaked-password warning remains a plan limitation.

**Deployment warning:** static validation and desktop/mobile Playwright smoke tests pass. These tests do not simulate authenticated customer accounts or full live business transactions. Rollback-only database tests now cover sticker kg purchase/yield/production for all three product types and 19L multiple-same-day/customer-owned bottle custody. Live end-to-end customer isolation, real customer payment/billing, push delivery, external messaging and scheduled month-end notification still require separate controlled verification. Do not interpret smoke tests as proof that every live workflow is error-free.

**Database warning:** موجودہ Supabase پر پہلے سے موجود V2/master schema اور incremental migrations کو دوبارہ نہ چلائیں۔ `MUGHALS_SECURITY_PERFORMANCE_REPAIR_20261109.sql`، `MUGHALS_RLS_POLICY_CONSOLIDATION_20261109.sql` اور `MUGHALS_PRODUCT_PRICE_SETTINGS_GUARD_20261109.sql`، `MUGHALS_19L_DELIVERY_GUARD_20261109.sql`، `MUGHALS_BILLING_GUARD_20261109.sql` اور `MUGHALS_OWNER_WORKER_GUARD_20261109.sql` میں 2026-11-09 کو live database پر لاگو کی گئی اضافی repairs کا ریکارڈ ہے؛ انہیں اسی live project پر دوبارہ چلانے کی ضرورت نہیں۔ بنیادی V2/master schema اس repository میں شامل نہیں۔
