# MUGHAL'S PURE WATER — Brand and Single-Delivery Guard Release

Date: 2026-11-10  
Base: `357000100903eb1a14322b8fb2023de79d1ce1dd`

## Included changes
- Replaced the previous crown/wordmark artwork with a single scalable emerald, water and champagne-gold MPW identity.
- Unified the same `logo.svg` across favicon, app header, PWA manifest and push notification icon.
- Refined the brand header, responsive spacing, app install control and PWA theme colours.
- Enforced the business rule: one 19L delivery record per customer per date.
- Added a unique database index on `(customer_id, delivery_date)`; existing live table had zero rows before applying it.
- Delivery screen now loads an existing customer/date record and edits that record instead of creating another one.
- Duplicate delivery attempts are rejected by the database even if the browser is refreshed or two requests race.
- Delivery worker ledger and monthly bill recalculation remain database-triggered for insert/update/delete; removed duplicate client-side bill recalculation after delivery and payment writes.
- Cleared tanker purchase quantity/rate fields after a confirmed save to reduce accidental repeat purchases.
- Counter sales explicitly behave as one daily aggregate per date; the existing daily total is loaded and updated, not added as a second row.
- Added desktop/mobile smoke assertions that the unified SVG logo is present and visible.
- Split bill read-only summary from explicit bill recalculation so normal screen refreshes and payment workflows do not recalculate the same bill twice.
- Existing payment idempotency by request ID retained; multiple legitimate payments on the same day remain allowed.

## Verification
- Existing main commit had passing static and Playwright desktop/mobile smoke checks.
- Existing live delivery table had 0 records and 0 invalid customer/date keys before the unique index.
- Live trigger inspection confirmed worker ledger synchronization and customer bill recalculation run on delivery insert/update/delete, and payment-trigger recalculation runs on payment insert/update/delete.
- Release branch must pass CI before merge.
- Full authenticated business E2E remains distinct from static/browser smoke tests.

## Known external constraints
- Supabase Security Advisor continues to warn about three authenticated SECURITY DEFINER functions with explicit admin checks.
- Leaked password protection remains unavailable on the current Supabase plan.
- Push notification delivery requires a customer's active device subscription and browser permission.
