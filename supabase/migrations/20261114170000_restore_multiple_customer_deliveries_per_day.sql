-- The business workflow permits multiple 19L delivery trips to the same customer on one day.
-- Keep request_id idempotency, but do not impose a customer/date uniqueness rule.
drop index if exists public.customer_19l_deliveries_one_per_customer_day_uidx;
