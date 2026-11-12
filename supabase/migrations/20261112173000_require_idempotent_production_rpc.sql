-- Remove the legacy production RPC that allowed writes without a request id.
REVOKE ALL ON FUNCTION public.record_production_with_workers(date,text,integer,jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_production_with_workers(date,text,integer,jsonb,uuid) TO authenticated;
