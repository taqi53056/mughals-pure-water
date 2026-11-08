# Release readiness handoff — 2026-11-09

## GitHub state
- Repository: `taqi53056/mughals-pure-water`
- Working branch: `integration-access-check-20261109`
- Base branch: `main`
- Main base commit at handoff: `5f1e5b31adc5f0cb68636d6fc2d8b407c07a2f45`
- Working branch head recorded at initial handoff: `2cd25cf3fb0547ea2f57df53138846a5173e69c9` (branch has advanced since this snapshot).
- Branch comparison at initial handoff: 106 commits ahead, 0 behind.
- Keep release changes on this branch until the final CI result and complete diff review are confirmed.

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
- Month-end cron `mughal-month-end-billing` is active at `55 18 28-31 * *` (23:55 Pakistan time); function checks that the local date is the final day of the month. A rollback-only end-to-end simulation forced the function's local date to 2026-11-30, generated the November bill and personalized notification, and then rolled back every test row and the temporary function definition. The real scheduled run will naturally occur at month-end when real active customers exist.

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
- Two-customer RLS isolation was verified using two disposable Auth identities created through the real signup trigger inside a transaction. Each identity saw exactly its own customer, delivery, bill, payment, and notification rows. Both identities and all associated records were rolled back.
- Month-end generation and notification were end-to-end simulated against the actual production function body with only the Karachi date expression temporarily pinned to month-end inside a transaction. Verified 3 successful bottles (Rs.300), 2 damaged caps (Rs.20), Rs.50 previous due, Rs.80 payment, Rs.290 closing due, customer name, full charge breakdown, and notification reference `bill:2026-11`. The original function definition was restored by rollback.
- All rollback-only business test rows were rolled back; no test customers, workers, sales, or bills remain.
- Performance advisor: no unindexed FK, RLS initplan, duplicate-index, or multiple-permissive-policy findings. Nineteen unused-index INFO notices remain because the business tables are empty; retain useful FK/lookup indexes.
- Health advisor: no findings.

## Accepted platform limitation and scope
1. **Leaked-password protection:** the Supabase organization is on the Free plan. Supabase documents this Auth feature as Pro-and-above, so it cannot be enabled without a plan upgrade. No paid upgrade was authorized. This is a documented platform hardening limitation, not a failed application test.
2. **Actual scheduled month-end execution:** the full billing function and notification flow have passed a transaction-only month-end simulation. The real cron occurrence will be confirmed automatically at the next month-end with active customers; no customer data should be fabricated just to create a live cron run.
3. **External messaging:** notifications are in-app only. SMS/WhatsApp provider and channel were not finalized and are outside this release's implemented scope.

## Release rule
Customer isolation and month-end billing logic are verified by rollback-only end-to-end database simulations. Do not claim that a real scheduled month-end cron run has already occurred. Do not upgrade the Supabase plan without explicit authorization.
