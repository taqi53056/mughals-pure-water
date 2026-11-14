ALTER TABLE public.worker_ledger
  DROP CONSTRAINT IF EXISTS worker_ledger_payment_method_check;

ALTER TABLE public.worker_ledger
  ADD CONSTRAINT worker_ledger_payment_method_check
  CHECK (
    (
      entry_type IN ('payment','advance')
      AND payment_method IS NOT NULL
      AND payment_method = ANY (ARRAY['cash','bank','jazzcash','easypaisa','other'])
    )
    OR
    (
      entry_type NOT IN ('payment','advance')
      AND payment_method IS NULL
    )
  );
