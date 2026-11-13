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


## Additional verified changes merged later on 2026-11-13

- Supplier replacement returns now follow the 1:1 exchange rule: a defective bottle is returned to the supplier and the same number of good replacements is recorded. The RPC no longer requires finished stock to already contain the replacement units; this avoids blocking a valid same-day supplier exchange when shop finished stock is zero.
- Return writes are serialized by request ID. Reusing an idempotency token with a different return payload is rejected. The return record does not create a sale, cash refund, water movement or duplicate finished-stock deduction.
- Product sales can now be made on credit only to an active store that an admin has explicitly approved. Cash remains the default. There is no automatic credit limit or due date.
- Stores are added by admins and start with credit approval disabled. Admins must explicitly approve a store before it appears in the credit-sale selector.
- Store credit is attached to an individual sale. Partial or full receipts are recorded against that sale; the system rejects overpayment, payment dates before the sale date, sub-paisa precision, duplicate requests and request-ID payload changes.
- Credit sales count as sales revenue once. They do not count as cash collections until a receipt is recorded. Partial receipts increase cash collections and reduce receivables without counting revenue a second time.
- Store credit balances, full sale history and receipt history are available in the admin sales workflow. Stores can be deactivated or have credit approval revoked without deleting their historical balances.
- The current Supabase project has the approved-store credit migration applied. Transaction-only tests using the authenticated role passed for store creation, approved credit sale, full/partial receipt, dashboard balance changes, cash sale compatibility, RLS access, and all negative guards. All test stores, sales, payments, purchases and production rows were rolled back.
- Supabase performance advisor now reports no unindexed foreign keys and no auth RLS initialization-plan warning. The two new user foreign-key indexes are expected to appear as unused until stores and credit receipts are actually entered.

## Current app entry points

- To add a store or approve it for credit: open **سیل / مال کا اخراج** and choose **منظور شدہ دکانیں / ادھار وصولی**.
- To record a credit sale: choose **ادھار — منظور شدہ دکان**, then select an approved active store. Otherwise keep the default **نقد وصولی**.
- To collect a partial/full payment: open the same store-credit page, choose the store and the outstanding sale, enter the received amount and method, then save.
- To view paid and unpaid credit sales and their receipts, use the complete history sections on that page.

## Remaining release gates (unchanged)

- Verify the deployed website/PWA is serving the latest `main` build and that the installed phone app refreshes to service-worker cache v109. Repository merge and browser smoke tests do not prove that a separate hosting provider has deployed it.
- Run one controlled real customer signup, privacy isolation, delivery, payment, bill approval and notification cycle before relying on month-end automation.
- Verify push on an actually subscribed device. SMS/WhatsApp is not enabled without a configured provider.
- Supabase leaked-password protection remains unavailable on the current Free plan.

- Later-returned 19L company empties now have a separate admin-only custody movement, so a return on a later date reduces the customer's company-bottle balance without editing an old delivery.
- Bottle refunds are linked to a specific recorded return. A refund cannot exceed the returned quantity, cannot be dated before the return, and requires explicit admin confirmation. This avoids issuing a Rs1,600 refund without recording the actual bottle return.
- Customer archive checks and history include late-return records. The company-bottle custody guard now considers both delivery-day empties and later returns, so edits cannot silently create negative bottle custody.
- Rollback-only integration tests passed for two bottle deposits, two later returns, linked refunds, partial held-deposit balances, over-return and over-refund rejection, idempotent retry, and dashboard exposure. All test rows were rolled back.
- Service worker cache advanced to v111 for the latest customer bottle return and refund UI.
