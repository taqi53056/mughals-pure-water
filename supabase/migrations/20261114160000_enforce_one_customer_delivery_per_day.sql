-- Enforce the business rule: one 19L delivery record per customer per calendar day.
-- Existing data was checked for duplicates before applying this index.
create unique index if not exists customer_19l_deliveries_one_per_customer_day_uidx
on public.customer_19l_deliveries (customer_id, delivery_date);
