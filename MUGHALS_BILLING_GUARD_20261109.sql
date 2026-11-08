-- MUGHAL'S PURE WATER
-- Enforce arithmetic consistency in monthly customer bills.
-- Applied and validated on live Supabase on 2026-11-09.
-- Payments may be negative because refunds are represented as negative net payments.

-- Required arithmetic fields cannot be NULL.
ALTER TABLE public.customer_monthly_bills
  ALTER COLUMN bottles_19l SET NOT NULL,
  ALTER COLUMN bottle_amount SET NOT NULL,
  ALTER COLUMN damaged_caps SET NOT NULL,
  ALTER COLUMN cap_amount SET NOT NULL,
  ALTER COLUMN previous_balance SET NOT NULL,
  ALTER COLUMN payments SET NOT NULL,
  ALTER COLUMN advance_used SET NOT NULL,
  ALTER COLUMN current_due SET NOT NULL,
  ALTER COLUMN closing_advance SET NOT NULL;

ALTER TABLE public.customer_monthly_bills
ADD CONSTRAINT customer_monthly_bills_amount_consistency_check
CHECK (
  bottles_19l >= 0
  AND damaged_caps >= 0
  AND bottle_amount = bottles_19l * 100
  AND cap_amount = damaged_caps * 10
  AND previous_balance >= 0
  AND advance_used >= 0
  AND current_due >= 0
  AND closing_advance >= 0
  AND NOT (current_due > 0 AND closing_advance > 0)
) NOT VALID;

ALTER TABLE public.customer_monthly_bills
VALIDATE CONSTRAINT customer_monthly_bills_amount_consistency_check;

-- Verification: should return true.
SELECT convalidated AS monthly_bill_consistency_guard_validated
FROM pg_constraint
WHERE conrelid='public.customer_monthly_bills'::regclass
  AND conname='customer_monthly_bills_amount_consistency_check';
