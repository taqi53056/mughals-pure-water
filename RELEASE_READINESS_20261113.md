# MUGHAL'S PURE WATER — Release Readiness (2026-11-13)

## Release changes now merged to `main`

- 19L customer delivery records support multiple deliveries for the same customer on the same date.
- Each delivery records total filled bottles and customer-owned bottles separately. Every filled bottle remains billable; customer-owned bottles do not increase company bottle stock.
- Company bottle custody is checked across dates. Returning company empties from previous deliveries is allowed, but returning more company empties than the outstanding company balance is rejected.
- Delivery labor is calculated on every filled bottle. Owner-performed work is tracked as labor saving rather than worker wage expense.
- Unassigned 19L deliveries remain company-bottle movements and are billed by filled bottles; collections are recorded separately to avoid double-counting revenue.
- Sticker purchases use kg with fixed yields: 500ml = 1,900 pieces/kg; shared 1.5L/6L = 1,200 pieces/kg. The UI uses one shared immutable yield configuration for preview and stock valuation.
- Sticker kg quantities support three decimal places; non-sticker raw-material quantities remain whole units. The database validates the material/unit pairing.
- Production stock guards, opening-stock corrections, monthly unit-cost calculations and stock reporting use the separate sticker pools.
- Service-worker cache was advanced for the sticker purchase workflow.

## Verification performed

- GitHub Actions static release checks and desktop/mobile Playwright smoke tests passed on the final validation branch before merge.
- Live Supabase migrations for the above changes are recorded in migration history; do not replay them manually.
- Transaction-only tests passed for:
  - 500ml: 1 kg sticker purchase followed by 1 carton production.
  - 1.5L: 1 kg shared sticker purchase followed by 1 carton production.
  - 6L: shared sticker purchase plus bottle purchase followed by 1 bottle production.
  - 0.5 kg 500ml sticker purchase converts to 950 sticker-equivalent pieces.
  - Invalid sticker unit and more-than-three-decimal kg precision are rejected.
  - Multiple same-day customer deliveries, customer-owned bottle separation, and return of prior company empties.
  - Company-empty over-return is rejected.
- All transactional test data was rolled back. No test customers, purchases, production, or delivery rows were retained.
- Current live data has three admin profiles; no registered customers, customer bills/payments, production rows, or product sales rows. This is an intentionally clean business dataset, not proof that those workflows have been tested with real customer accounts.
- Month-end billing and monthly business-report cron jobs are active. Their scheduled production run with real customers is still pending.

## Financial and stock safety notes

- The dashboard distinguishes recorded collections, receivables, payables and cash movement. It does not invent a cash balance when no opening cash/bank balance or reconciliation exists.
- Shop-counter water litres are estimated from entered counter sales; the report labels resulting water balance and net profit as estimated.
- The month remains open. Expense confirmation is required before month close; unentered expenses must not be treated as zero-cost business activity.
- Sticker opening stock is currently zero. Production must not begin until the actual sticker kg purchase/opening stock is entered.
- 6L raw bottle opening stock is currently zero. 6L production must not begin until actual 6L bottle stock is entered.
- No financial or stock opening values were changed by the rollback-only tests.

## Remaining controlled release gates

1. Verify the deployed PWA is serving the latest `main` build and that the installed phone app refreshes to the current service-worker cache.
2. Complete a real, approved customer signup and verify that the customer can see only their own profile, deliveries, bills, payments and notices.
3. Verify one real customer delivery, partial payment, month-end bill approval and customer notice end-to-end before relying on automated month-end billing.
4. Verify push delivery on a subscribed device. SMS/WhatsApp delivery is not enabled until a provider/channel is configured and approved.
5. Review the four admin-guarded SECURITY DEFINER RPC warnings. Each currently checks `auth.uid()` and `public.is_admin()` and uses an empty `search_path`; any refactor must preserve these controls.
6. Supabase leaked-password protection is unavailable on the current Free plan; this is an external plan limitation, not an app-side switch.

## Operating rules that must remain unchanged

- 19L filled bottle charge: Rs.100 each, regardless of who owns the container.
- 19L labor: Rs.20 per filled bottle for a non-owner worker; owner labor is a saving, not a wage expense.
- Damaged 19L cap customer charge: Rs.10 each.
- 500ml: 24 bottles/carton; 1.5L: 12 bottles/carton; 6L: individual bottles.
- 500ml and 1.5L default carton price: Rs.280; configured special-100 rate: Rs.270. 6L minimum price: Rs.55.
- Production labor: Rs.10 per carton for 500ml/1.5L; 6L labor is zero.
- 500ml sticker yield: 1,900/kg; shared 1.5L/6L sticker yield: 1,200/kg.

