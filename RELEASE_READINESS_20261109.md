# Release readiness handoff — 2026-11-09

## GitHub state
- Repository: `taqi53056/mughals-pure-water`
- Working branch: `integration-access-check-20261109`
- Base branch: `main`
- Main base commit at handoff: `5f1e5b31adc5f0cb68636d6fc2d8b407c07a2f45`
- Working branch head at handoff: `2cd25cf3fb0547ea2f57df53138846a5173e69c9`
- Branch comparison: 106 commits ahead, 0 behind.
- Do not merge to `main`, publish a release ZIP, or deploy until the remaining live checks below are addressed.

## Supabase state
- Project ref: `tosxnmnqlufeuknrhxzr`
- Supabase project label still says `Kiswa Pure Water`; this is the dashboard project label, not the app branding.
- Project status: ACTIVE_HEALTHY; PostgreSQL 17.
- Three fixed admin profiles remain: M. Muzamil Mughal, M.Taqi Mughal, M.Usama Mughal.
- One active permanent Owner worker record remains.
- Customer/business data remains clean: customers, 19L deliveries, bills, payments, notifications, complaints are all zero. Auth users remain the three admins.
- RLS enabled on all 27 public tables. No direct table privileges for anon/PUBLIC. Customer PIN columns are not selectable or updateable by authenticated users.
- Customer/admin RLS policies have been consolidated. No multiple-permissive-policy warnings remain.
- `is_admin()` is SECURITY INVOKER, null-safe, and uses the fixed admin UUID allowlist.
- App-facing admin data RPCs use SECURITY INVOKER. `mark_customer_notification_read` intentionally remains SECURITY DEFINER; it only marks a notice belonging to the authenticated active customer as read.
- Permanent Owner worker guard is SECURITY INVOKER, has no anon/authenticated EXECUTE grants, and is invoked only by its table trigger.
- Trigger functions and the legacy three-argument product-sale wrapper have fixed empty search_path settings.
- Product settings currently: 500ml carton 24 units, Rs.280 default/special, Rs.10 labor; 1.5L carton 12 units, Rs.280 default/special, Rs.10 labor; 6L pack 18 bottles, Rs.55, zero labor.
- Database constraints enforce carton price floor Rs.280, special bulk rate not above default, fixed pack/labor rules, fixed 6L Rs.55, 19L bottle-exchange invariants, and monthly bill arithmetic/non-null fields.
- Month-end cron `mughal-month-end-billing` is active at `55 18 28-31 * *` (23:55 Pakistan time); function checks that the local date is the final day of the month. No cron run is recorded yet because the current date is not month-end and there are no active customers.

## Applied Supabase migrations
The live project migration history includes the hardening sequence, including:
- trigger/legacy RPC search-path hardening
- missing foreign-key indexes and customer RLS auth.uid() optimization
- duplicate monthly-bill index removal
- customer sensitive-column access restriction
- production worker wage-ledger repair
- unused internal RPC EXECUTE revocation
- SECURITY INVOKER conversion and admin guard hardening
- customer/admin RLS policy consolidation
- bulk special price ceiling
- fixed pack/labor/6L price constraints
- 19L delivery exchange constraints
- monthly bill arithmetic and NOT NULL constraints
- permanent Owner worker guard and trigger-only execution

Corresponding SQL records in this branch:
- `MUGHALS_SECURITY_PERFORMANCE_REPAIR_20261109.sql`
- `MUGHALS_RLS_POLICY_CONSOLIDATION_20261109.sql`
- `MUGHALS_PRODUCT_PRICE_SETTINGS_GUARD_20261109.sql`
- `MUGHALS_19L_DELIVERY_GUARD_20261109.sql`
- `MUGHALS_BILLING_GUARD_20261109.sql`
- `MUGHALS_OWNER_WORKER_GUARD_20261109.sql`

These files document changes already applied to the current live project. Do not re-run them against that project.

## Verified tests
- GitHub Actions static release validation passes.
- Playwright desktop/mobile smoke tests pass: page load, RTL layout, PWA manifest and service worker, no horizontal overflow, login/signup navigation, 19L exchange/labor calculations, owner labor saving, admin price floor, bulk special price, fixed 6L price.
- Rollback-only database tests pass for production allocation labor and worker ledger, sale/stock RPC, billing calculations for valid opening due/advance cases, 19L exchange constraints, product price update/audit, owner protection, and admin-only RPC denial.
- All rollback-only business test rows were rolled back; no test customers, workers, sales, or bills remain.
- Performance advisor: no unindexed FK, RLS initplan, duplicate-index, or multiple-permissive-policy findings. Nineteen unused-index INFO notices remain because the business tables are empty; retain useful FK/lookup indexes.
- Health advisor: no findings.

## Remaining release gates
1. **Supabase leaked-password protection:** the Supabase organization is on the Free plan. Supabase documents this Auth feature as Pro-and-above, so it cannot be enabled on the current plan. No paid plan upgrade was authorized.
2. **Live customer isolation:** re-run a real authenticated two-customer isolation test after the final RLS consolidation. No customer accounts are currently present; do not create fake live customer records without authorization.
3. **Month-end production run:** the scheduled cron has not yet reached a month-end with active customers. Verify the actual run and customer notification when real active customer data exists.
4. **External messaging:** customer notifications are in-app only. SMS/WhatsApp provider and channel were not finalized.

## Release rule
Keep all work on the working branch. Do not merge to `main` or claim 100% production completion until the live customer-isolation and month-end gates are verified and the Supabase plan decision is resolved.
