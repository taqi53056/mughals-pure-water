# MUGHAL'S PURE WATER — Comprehensive Audit (2026-11-14)

## Result

The current main build passes static validation and desktop/mobile browser smoke tests. The admin home, daily-activity panel, key database safeguards, and security permissions received targeted fixes during this audit. This is not a claim that every live business workflow has been end-to-end tested: the production dataset intentionally contains no customers, and no fake customer or financial transaction was created.

## Changes applied

- Admin home now has 20 unique module routes, grouped as 5 daily operations, 4 stock, 4 finance, and 7 management controls.
- Removed the duplicate detailed-reports shortcut because it opened the same report module as profit/loss.
- Moved expenses into the finance category so expense, income, profit/loss and owner withdrawals are grouped together.
- All 20 admin tiles support keyboard activation.
- Today's activity is displayed before the longer monthly dashboard. Its data sources load in parallel; individual read failures are shown rather than hiding the whole panel.
- Today's activity now reads 17 sources in parallel. Unassigned-19L collections are shown separately and excluded from generic other income to avoid double counting; customer refunds are separated from receipts; finished-goods quantities are grouped by product and unit; opening/free raw-material entries are not counted as purchases.
- The expanded 17-source panel's table columns and authenticated SELECT permissions were checked. A read-only transaction under the authenticated admin role successfully read all 17 source tables and the daily dashboard RPC with RLS active; the separate browser smoke tests also pass. A fresh post-deploy PostgREST session for every expanded read has not yet been observed in request logs.
- Empty-day P&L now uses the database's has_pnl_activity flag: on 2026-11-14, a tanker purchase makes has_activity=true while has_pnl_activity=false, so the panel reports no P&L activity instead of presenting Rs. 0 as a profit result; the estimated-profit qualifier is hidden in that state.
- Worker wage balance views carton_worker_wage_balance and delivery_worker_wage_balance now use security_invoker=true.
- Removed implicit PUBLIC execution from the admin product-sale and store-credit receipt wrappers. Authenticated execution remains available; the private implementations enforce admin authorization.
- The service-worker cache is mughals-pure-water-v136-pnl-empty-qualifier.
- Customer-facing app source, PWA manifest and service worker contain no legacy Kiswa branding. The Supabase Dashboard's internal project display name still reads “Kiswa Pure Water”; it is not shown to customers and could not be renamed with the available project-management actions.

## Security and database verification

- Exactly 3 admin profiles remain; all 3 match the fixed is_admin() allowlist. No unexpected admin profile was found.
- Every public base table has RLS enabled; no public table lacks RLS, and the anon role has no direct table/view privileges in the public schema.
- Public admin write wrappers are SECURITY INVOKER and call private SECURITY DEFINER helpers with auth.uid() and is_admin() checks. The two store-credit/product-sale wrappers previously inheriting PUBLIC execution are now authenticated-only.
- archive-customer and send-customer-push both require JWTs, check the caller's admin identity, and restrict CORS to the app origin. No service-role secret was found in the browser app files; service-role use is confined to Edge Functions.
- Both worker wage views have no anon/authenticated SELECT grant and now enforce invoker security.
- Supabase Health Advisor reports no lints.
- Security Advisor reports only auth_leaked_password_protection: leaked-password protection remains disabled. The connected project tools do not expose the Auth settings toggle, so it was not changed and must be enabled by the project owner in Supabase Auth settings.
- Performance Advisor reports 11 unused-index INFO notices. These indexes were not dropped because the business tables are largely empty and there is no representative production workload to justify removal.
- Last-24-hour logs: 437 edge requests, 336 PostgREST requests and 11 Auth requests; zero HTTP 4xx/5xx in those sources. PostgreSQL logs contain 5 SQLSTATE 42601 syntax-error events from management/API maintenance statements or test attempts, not app HTTP requests; the affected intended changes were subsequently applied and their current state verified.

## Data integrity checks

- No duplicate request IDs were found across all 22 public tables carrying request_id; each has a unique request_id index. No duplicate worker-ledger source rows were found.
- The two special unassigned-19L income entries each match exactly one collection record; no amount, payment-method or date mismatch was found.
- No duplicate worker-ledger source rows or missing worker earnings were found for linked delivery/production sources.
- No negative finished stock and no future-dated expense, income, product-sale or worker-ledger entries were found.
- Current dataset: 3 admins, 0 customers, 2 active workers, 0 customer deliveries/payments/monthly bills, 1 production row, 0 product-sales rows, 0 expense rows, 2 linked unassigned-19L income rows, 0 general finance-ledger rows and 1 worker-ledger row.
- For Pakistan date 2026-11-14, today's panel inputs show 2 tanker allocation rows totaling 1.000 tanker / 1,000 litres / Rs 1,200; no customer deliveries, unassigned deliveries/collections, product sales, counter sales, production, raw purchases, finished-goods entries, customer payments, worker-ledger entries, owner withdrawals, cleaning savings, returns, adjustments, business expenses or other income for that date.
- Finished stock: 1.5L = 10 cartons; 500ml = 0; 6L = 0.
- The two unassigned-19L receipts are linked to their delivery records and are not counted as independent extra revenue.

- November 1–14 management-dashboard reconciliation: recorded collections Rs. 2,720; recorded outflows Rs. 3,600; net cash movement -Rs. 880; receivables Rs. 1,400; worker payable Rs. 100 (M. Aqib); owner withdrawals Rs. 0. This is movement, not a closing cash/bank balance; opening balances are absent.
- The November P&L currently reports Rs. 2,336.40 estimated net profit, not a final profit. Counter-water usage/cost are estimated and there are zero expense entries; unentered real expenses would overstate profit.
- Current 19L cap stock is zero; recorded tape balance is 0.857142857 bundle. Verify and enter physical 19L cap opening stock before recording damaged caps.

## Admin navigation

The 20 module routes were checked against openModule(): 20 distinct routes, no missing route, no keyboard-inaccessible tile. The duplicate report shortcut was removed. The default view opens the daily-operations category, while the remaining tools are available through their category filters.

## Scheduled operations

The month-end billing and monthly business-report cron jobs remain active. Their latest recorded runs (2026-11-13) succeeded. Real customer billing and notification delivery remain unverified in production because there are currently no customer accounts.

## Remaining controlled verification

1. Customer E2E: a real, approved customer must sign up before a complete customer-only profile/delivery/bill/payment/notification isolation cycle can be verified. No dummy customer was created.
2. Push delivery: requires a real subscribed device and browser permission; not tested by a synthetic production subscription.
3. SMS/WhatsApp: no external provider/channel is configured, so external messaging is not enabled.
4. Cash/bank/JazzCash reconciliation: no opening balances or reconciliation records are present. The app must not invent account balances; enter verified opening figures before relying on account-wise cash balances.
5. Profit accuracy: shop-counter water usage and net profit remain marked estimated where source litres/costs are not exact. Zero expense rows do not prove that no expenses occurred; enter real expenses before relying on net profit or closing a month.
6. Supabase leaked-password protection: remains disabled. The connected tools do not expose the Auth settings toggle; the project owner must enable it in Supabase Auth settings.
7. Fresh-project rebuild / migration archive: the remote Supabase history lists 245 applied migrations while the repository contains 127 migration SQL files; older history still has missing or version-mismatched files. Recent 2026-11-14 migrations have matching SQL files, but the repository is not a complete fresh-database installer. Do not use it alone to create a new Supabase project.

## Release verification

The app release at commit eb181b2 (2026-11-14) passed App static validation, including desktop/mobile browser smoke tests, and GitHub Pages deployment; the audit report was subsequently updated separately. A successful build/deploy is not proof of authenticated customer E2E or of every business transaction.

## Follow-up audit — 2026-11-14 17:49 UTC

- Rechecked the live Supabase project after the customer notification security migrations.
- Current live customer data is no longer empty: exactly 1 active customer record (C001) exists, with 1 delivery, 1 monthly bill, 2 in-app notifications, and 1 active push subscription. Do not rely on the earlier “0 customers” snapshot above.
- Exactly 3 admin profiles remain. All public base tables have RLS enabled; no public table lacks RLS; the anon role has no direct public table grants. No Storage buckets or Storage policies are configured. All 14 public views inspected have security_invoker=true.
- SECURITY DEFINER functions inspected in public/private schemas all have pinned search_path settings; none are executable by anon. The private schema is not USAGE-accessible to anon. Authenticated access to selected private helpers is intentional through checked SECURITY INVOKER wrappers and private helper authorization.
- Found and fixed a real customer-archive RPC failure. PostgreSQL logs showed private.prepare_customer_archive failing with SQLSTATE 55000 because the PL/pgSQL record variable `r` conflicted with the table alias `r` in the customer bottle-return month query. Renamed the table alias to `ret` and the loop record to `v_entered_by_table`. Migration `20261114174913_fix_customer_archive_record_alias_conflict_20261114` was applied; post-migration checks confirm the old alias is absent and the renamed references are present.
- The failing archive requests occurred before the correction. The live customer row, its delivery, and its bill remain present and active after the fix; no customer was archived or deleted as part of this repair.
- The three most recent scheduled month-end billing/report job runs recorded for Nov 11–13 succeeded. Current schedules remain 18:55 UTC for billing and 19:05 UTC for the monthly report.
- Push endpoint logs show authenticated admin POST requests returning HTTP 200. This proves the Edge Function requests completed at the HTTP layer; it does not independently prove that a notification appeared on the customer's physical device.
- Security Advisor still reports only leaked-password protection disabled (not available on the connected Free plan). Performance Advisor still reports six unused-index INFO notices; no index was removed without production workload evidence. Health Advisor remains clear.
- Five historical PostgreSQL errors reading `"array_agg" is an aggregate function` were traced to management/API inspection queries that attempted to call `pg_get_functiondef` on aggregate functions; these were not application request errors. The archive RPC failure was separately identified and fixed as described above.
- Latest GitHub main commit before this follow-up was `3f8f954d0d284540ccccee4eac03f575383edf12`; static validation, desktop/mobile Playwright smoke tests, and Pages build/deploy runs completed successfully. These checks do not replace live customer transaction and physical-device verification.

- Additional safe verification after the archive repair: invoked the public archive wrapper under the fixed admin identity using a deliberately nonexistent customer ID. The call traversed the archive month-lock query and reached the expected “customer not found” guard; the transaction made no data changes. The real C001 customer was not passed to the archive function. Its November 2026 business month is not yet closed, so the designed archive guard would correctly prevent deleting its open-period records.
- Fresh authenticated-role simulation using C001's actual linked Auth identity: visible customers=1, deliveries=1, bills=1, notifications=2, push subscriptions=1; visible expenses=0, audit rows=0, workers=0, worker-ledger rows=0. An attempted no-op UPDATE against customer notifications affected 0 rows. All checks ran in rollback-only transactions.
- The archive repair migration SQL is committed at `supabase/migrations/20261114174913_fix_customer_archive_record_alias_conflict_20261114.sql`; live migration version `20261114174913` is recorded.

## Latest live operations snapshot — 2026-11-14 17:54 UTC

- Customer C001: one delivery on Nov 14, 4 company bottles delivered, 4 empties returned, 4 successful bottles, 0 damaged caps, owner labor saving Rs.80. November bill is 4 × Rs.100 = Rs.400; no payment is recorded and current due is Rs.400.
- Unassigned 19L deliveries: 17 successful bottles. The report records Rs.300 collected and Rs.1,400 unclassified/uncollected; total receivables are Rs.1,800 (C001 Rs.400 + unassigned Rs.1,400).
- November 1–14 recorded collections Rs.2,720; recorded outflows Rs.3,600; net cash movement -Rs.880. This is not a cash/bank closing balance: opening cash/bank figures and reconciliation are absent.
- Worker payable is Rs.100 (one worker-ledger earning row, no payout recorded). There is one active non-owner worker and one active owner.
- Finished stock view: 1.5L = 10 cartons; 500ml = 0; 6L = 0.
- Remaining raw-material estimate: 500ml bottles/caps 5,587 each and cartons 250; 1.5L bottles/caps 2,930 each and cartons 240; sticker balances 3,800 (500ml) and 2,280 (1.5L/6L); tape 0.857142857 bundle. 6L raw bottles/caps are 0.
- Product-filling water estimate is 1,020 litres. Shop-counter water remaining is 1,001 litres and explicitly estimated, not a measured balance.
- No `cap_19l` opening-stock row exists; available 19L caps therefore calculate as zero. Damaged caps currently recorded are zero. Enter the verified physical 19L-cap opening quantity before recording any damaged caps; do not invent a quantity.
- Current P&L reports Rs.2,645.20 estimated net profit (Rs.3,725.20 before the estimated shop-counter water cost). Counter-water litres/cost are estimates, and no general business-expense rows are recorded. Unentered real expenses would overstate profit; do not treat this as final profit.
- November is still open and has not been closed. Customer archive is intentionally blocked while the active customer's November activity period remains open.

## User-directed stock correction — 2026-11-14

- Removed mistaken production row `production.id=87`: 1.5L, quantity 10 cartons, effective production date 2026-11-11, entered 2026-11-13 19:04 UTC.
- Deleting the production row cascaded its 10-carton worker allocation (id 30). The production stock-sync trigger added a matching `production_reversal` of -10 to the stock ledger. Net effect for reference 87 is zero; no finished stock remains from that mistaken production.
- Two unverified opening carton balances were zeroed, not physically deleted, to preserve the audit trail: `raw_material_purchases.id=149` (1.5L, 250 cartons, Rs.8,750) and id 150 (500ml, 250 cartons, Rs.8,750). Both now have quantity=0 and total_amount=0 with explicit correction notes.
- Added a narrow CHECK-constraint allowance for zero-quantity opening-stock correction rows only when total_amount=0 and details begin `اصلاحی اندراج:`. Normal opening stock and purchase rows remain positive; raw-material delete guard remains enabled.
- Live migration version: `20261114183659`, mirrored at `supabase/migrations/20261114183659_allow_audited_zero_opening_stock_corrections.sql`.
- Verification: production id 87 absent; allocation id 30 absent; both opening carton rows zero; stock ledger contains +10 original production and -10 reversal; current finished stock view shows 1.5L=0, 500ml=0, 6L=0.
- User will recount physical cartons and enter verified opening carton stock and production quantities later. Do not infer or add any stock until they provide the measured counts.
