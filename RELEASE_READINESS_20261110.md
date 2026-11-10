# MUGHAL'S PURE WATER — Enterprise Workspace Release Candidate

Date: 2026-11-10  
Branch: `release/enterprise-admin-experience-20261110`

## Changes in this candidate
- Reorganized the administrator workspace into routine operations, inventory/production, finance, management/reports, and all-modules navigation.
- Moved the navigation controls above the module tiles so mobile users can filter before scrolling through the full module list.
- Added an adaptive layout: compact two-column task tiles on phones; a persistent navigation rail and larger work area on wide desktop screens; a tablet layout between them.
- Removed tile descriptions from the visual foreground while retaining their descriptions as hover text and accessible labels.
- Added keyboard activation to all 20 administrator module tiles.
- Moved module-specific instructions into a collapsed “section guidance” disclosure.
- Changed the detailed report to call the same server-side management report used by the executive dashboard and month closing, rather than maintaining a second client-side profit formula.
- Fixed the report result container collision: the report output now uses `reportResult`, leaving the shared `moduleTable` target unique.
- Retained the customer payment amount until the bill and notification steps have completed, so a retry can reuse the same idempotency token.
- Added idempotent request tokens for worker creation and customer complaints; added a normalized worker-name/mobile uniqueness guard.
- Added a unique opening-stock guard and conflict retry handling.
- Included manually recorded worker payments/advances in recorded cash outflows while excluding ledger rows already mirrored from `labor_payments`, preventing double counting.
- Bumped the PWA cache to `mughals-pure-water-v71-enterprise-workspace`.

## Verification performed
- All 3 inline JavaScript blocks parse successfully.
- Service Worker JavaScript parses; manifest JSON parses.
- 20/20 administrator tiles have keyboard support and accessible labels.
- Navigation placement and filter behavior were checked for operations and finance; the other categories remain to be included in a browser-level smoke test.
- Worker request-id duplicate protection, complaint request-id duplicate protection, normalized worker identity protection, and opening-stock uniqueness were tested in rollback-only database transactions.
- Dashboard cash-outflow test returned Rs.120 for Rs.50 manually recorded worker payment plus Rs.70 legacy labor payment; the mirrored ledger row was not double-counted.
- Dashboard RPC returned successfully under an authenticated administrator session.
- Test transactions were rolled back. Current live counts: 3 admin profiles, 0 customers, 1 active owner worker, 0 complaints, 0 pending archive jobs.
- Supabase Health Advisor: no findings. No public table is missing RLS.
- Performance Advisor: 6 unused-index INFO notices only; duplicate-index warning introduced during this work was removed.
  
## Release blockers / limits
- This branch has not been merged to `main` or deployed to GitHub Pages.
- Real browser end-to-end testing of login, customer isolation, delivery, payment, production, sales, worker workflows, push notifications, and month-end cron has not been run in this session.
- Security Advisor still reports 3 authenticated SECURITY DEFINER RPC warnings. Each function has an explicit admin check; do not revoke or change them without redesigning the protected workflow.
- Leaked-password protection remains disabled on the current Supabase plan.
- The product remains an SME operational and management-accounting system, not a full double-entry ERP/IFRS accounting package. Formal chart of accounts, journals, balance sheet, bank reconciliation, and supplier/customer ageing remain separate future scope.
- Do not treat this candidate as production-ready until the browser-level end-to-end tests and deployment verification pass.

## Data safety
No customer, admin, owner, or business setup records were intentionally changed by the UI work. QA records used for database tests were inside transactions and rolled back.
