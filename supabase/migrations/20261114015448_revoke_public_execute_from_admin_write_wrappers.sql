-- Keep privileged store-credit and product-sale write wrappers unavailable to anon.
-- Authenticated execution remains available; the private helpers enforce admin authorization.
REVOKE EXECUTE ON FUNCTION public.record_product_sale(date,text,integer,bigint,numeric,text,uuid,bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.record_store_credit_payment(bigint,date,numeric,text,uuid,text) FROM PUBLIC;
