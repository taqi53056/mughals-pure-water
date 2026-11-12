-- Prevent direct admin RPC calls from recalculating customer bills in a closed period.
-- The same month advisory lock serializes this check with source writes and month closing.

CREATE OR REPLACE FUNCTION public.calculate_customer_bill(p_customer_id bigint, p_bill_month date)
RETURNS void
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
DECLARE
  v_month date := date_trunc('month', p_bill_month)::date;
  v_next date := (date_trunc('month', p_bill_month) + interval '1 month')::date;
  v_current_month date := date_trunc('month', timezone('Asia/Karachi', now()))::date;
  v_bottles integer := 0;
  v_caps integer := 0;
  v_bottle_amount numeric(12,2) := 0;
  v_cap_amount numeric(12,2) := 0;
  v_previous_due numeric(12,2) := 0;
  v_previous_advance numeric(12,2) := 0;
  v_net_payments numeric(12,2) := 0;
  v_charges numeric(12,2) := 0;
  v_advance_used numeric(12,2) := 0;
  v_due numeric(12,2) := 0;
  v_closing_advance numeric(12,2) := 0;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin access required' USING ERRCODE = '42501';
  END IF;

  IF p_customer_id IS NULL OR p_bill_month IS NULL THEN
    RAISE EXCEPTION 'Customer and billing month are required' USING ERRCODE = '22023';
  END IF;

  IF v_month > v_current_month THEN
    RAISE EXCEPTION 'Future customer bills cannot be calculated.' USING ERRCODE = '22023';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended('mpw-month-close-' || v_month::text, 0)
  );

  IF EXISTS (
    SELECT 1
    FROM public.business_month_closings
    WHERE month_start = v_month
      AND status = 'closed'
  ) THEN
    RAISE EXCEPTION 'Closed billing periods cannot be recalculated.'
      USING ERRCODE = '55000';
  END IF;

  SELECT COALESCE(SUM(successful_bottles), 0), COALESCE(SUM(damaged_caps), 0)
  INTO v_bottles, v_caps
  FROM public.customer_19l_deliveries
  WHERE customer_id = p_customer_id
    AND delivery_date >= v_month AND delivery_date < v_next;

  SELECT COALESCE(current_due, 0), COALESCE(closing_advance, 0)
  INTO v_previous_due, v_previous_advance
  FROM public.customer_monthly_bills
  WHERE customer_id = p_customer_id AND bill_month < v_month
  ORDER BY bill_month DESC LIMIT 1;

  v_previous_due := COALESCE(v_previous_due, 0);
  v_previous_advance := COALESCE(v_previous_advance, 0);

  SELECT COALESCE(SUM(CASE
    WHEN payment_type IN ('advance', 'bill_payment') THEN amount
    WHEN payment_type = 'refund' THEN -amount
    ELSE 0
  END), 0)
  INTO v_net_payments
  FROM public.customer_payments
  WHERE customer_id = p_customer_id
    AND payment_date >= v_month AND payment_date < v_next;

  v_bottle_amount := v_bottles * 100;
  v_cap_amount := v_caps * 10;
  v_charges := v_bottle_amount + v_cap_amount;
  v_advance_used := LEAST(v_previous_advance, v_previous_due + v_charges);
  v_due := GREATEST(v_previous_due + v_charges - v_previous_advance - v_net_payments, 0);
  v_closing_advance := GREATEST(v_previous_advance + v_net_payments - v_previous_due - v_charges, 0);

  INSERT INTO public.customer_monthly_bills (
    customer_id, bill_month, bottles_19l, bottle_amount, damaged_caps,
    cap_amount, previous_balance, payments, advance_used, current_due, closing_advance
  )
  VALUES (
    p_customer_id, v_month, v_bottles, v_bottle_amount, v_caps,
    v_cap_amount, v_previous_due, v_net_payments, v_advance_used, v_due, v_closing_advance
  )
  ON CONFLICT (customer_id, bill_month)
  DO UPDATE SET
    bottles_19l = EXCLUDED.bottles_19l,
    bottle_amount = EXCLUDED.bottle_amount,
    damaged_caps = EXCLUDED.damaged_caps,
    cap_amount = EXCLUDED.cap_amount,
    previous_balance = EXCLUDED.previous_balance,
    payments = EXCLUDED.payments,
    advance_used = EXCLUDED.advance_used,
    current_due = EXCLUDED.current_due,
    closing_advance = EXCLUDED.closing_advance;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.calculate_customer_bill(bigint,date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.calculate_customer_bill(bigint,date) TO authenticated;
