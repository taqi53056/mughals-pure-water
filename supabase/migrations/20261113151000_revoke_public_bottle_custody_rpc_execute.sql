
-- Invoker wrappers are admin-only API operations; do not inherit PostgreSQL's default PUBLIC EXECUTE.
REVOKE ALL ON FUNCTION public.record_customer_19l_bottle_return(bigint,date,integer,uuid,text)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.record_customer_bottle_deposit(bigint,date,text,integer,text,uuid,text,boolean,bigint)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_customer_19l_bottle_return(bigint,date,integer,uuid,text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_customer_bottle_deposit(bigint,date,text,integer,text,uuid,text,boolean,bigint)
  TO authenticated;
