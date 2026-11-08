-- MUGHAL'S PURE WATER
-- Backend invariants for 19L bottle exchange entries.
-- Applied and validated on live Supabase on 2026-11-09.
-- Delivery must be positive; returned empties cannot exceed bottles delivered;
-- successful bottles equal returned empties; difference is the outstanding
-- bottle count; damaged caps and worker labor cannot be negative.

ALTER TABLE public.customer_19l_deliveries
ADD CONSTRAINT customer_19l_delivery_exchange_invariants_check
CHECK (
  bottles_delivered > 0
  AND empty_bottles_returned >= 0
  AND empty_bottles_returned <= bottles_delivered
  AND successful_bottles = empty_bottles_returned
  AND bottle_difference = bottles_delivered - empty_bottles_returned
  AND damaged_caps >= 0
  AND delivery_labor >= 0
) NOT VALID;

ALTER TABLE public.customer_19l_deliveries
VALIDATE CONSTRAINT customer_19l_delivery_exchange_invariants_check;

-- Verification: should return true.
SELECT convalidated AS delivery_exchange_guard_validated
FROM pg_constraint
WHERE conrelid='public.customer_19l_deliveries'::regclass
  AND conname='customer_19l_delivery_exchange_invariants_check';
