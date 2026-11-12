REVOKE ALL ON FUNCTION public.record_product_return(date,text,integer,text)
  FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.record_product_sale(date,text,integer)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_product_sale(date,text,integer,bigint)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_product_sale(date,text,integer,bigint,numeric)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_product_sale(date,text,integer,bigint,numeric,text)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.record_product_return(date,text,integer,text,uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_product_sale(date,text,integer,bigint,numeric,text,uuid)
  TO authenticated;