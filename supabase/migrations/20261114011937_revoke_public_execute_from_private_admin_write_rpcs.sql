-- Revoke implicit PUBLIC execution from privileged private-schema write RPCs.
-- Authenticated admin access remains explicitly granted; function-level admin checks remain in place.
REVOKE EXECUTE ON FUNCTION private.record_customer_19l_bottle_return(bigint,date,integer,uuid,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION private.record_customer_bottle_deposit_v2(bigint,date,text,integer,text,uuid,text,boolean,bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION private.record_product_sale_with_store_credit(date,text,integer,bigint,numeric,text,uuid,bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION private.record_store_credit_payment(bigint,date,numeric,text,uuid,text) FROM PUBLIC;
