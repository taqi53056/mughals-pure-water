# MUGHAL'S PURE WATER

اردو RTL پانی کے کاروبار کی مینجمنٹ ایپ (PWA)۔

- تفصیلی اردو تکنیکی/ڈپلائمنٹ نوٹس: [README_UR.txt](README_UR.txt)
- مختصر ریلیز نوٹس: [README_URDU.txt](README_URDU.txt)
- موجودہ release gates اور اگلے verification steps: [RELEASE_READINESS_20261109.md](RELEASE_READINESS_20261109.md)
- 2026-11-10 adaptive enterprise workspace candidate اور اس کی QA حدود: [RELEASE_READINESS_20261110.md](RELEASE_READINESS_20261110.md)

**Security note:** Supabase organization is on the Free plan. Supabase documents leaked-password protection as Pro-and-above, so it cannot be enabled on the current plan. The only remaining SECURITY DEFINER app RPC is `mark_customer_notification_read`, which updates only the notice belonging to the authenticated active customer.

**Deployment warning:** static validation اور Playwright desktop/mobile smoke tests پاس ہیں؛ rollback-only database tests نے production allocation، sales/stock، billing arithmetic، 19L exchange constraints، owner protection اور price guards verify کیے۔ ابھی حقیقی customer sign-in کے ذریعے دو الگ customer accounts کی RLS isolation اور active customers کے ساتھ scheduled month-end cron/notification کا production end-to-end test باقی ہے۔ ان کی تصدیق سے پہلے `main` پر merge/deploy نہ کریں۔

**Database warning:** موجودہ Supabase پر پہلے سے موجود V2/master schema اور incremental migrations کو دوبارہ نہ چلائیں۔ `MUGHALS_SECURITY_PERFORMANCE_REPAIR_20261109.sql`، `MUGHALS_RLS_POLICY_CONSOLIDATION_20261109.sql` اور `MUGHALS_PRODUCT_PRICE_SETTINGS_GUARD_20261109.sql`، `MUGHALS_19L_DELIVERY_GUARD_20261109.sql`، `MUGHALS_BILLING_GUARD_20261109.sql` اور `MUGHALS_OWNER_WORKER_GUARD_20261109.sql` میں 2026-11-09 کو live database پر لاگو کی گئی اضافی repairs کا ریکارڈ ہے؛ انہیں اسی live project پر دوبارہ چلانے کی ضرورت نہیں۔ بنیادی V2/master schema اس repository میں شامل نہیں۔
