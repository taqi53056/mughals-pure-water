-- Keep the private SECURITY DEFINER implementation inaccessible to clients.
-- The public wrapper is the only authenticated entry point and runs as its trusted owner.
ALTER FUNCTION public.record_production_with_workers(date,text,integer,jsonb,uuid) SECURITY DEFINER;
ALTER FUNCTION public.record_production_with_workers(date,text,integer,jsonb,uuid) SET search_path = '';
REVOKE ALL ON FUNCTION private.record_production_with_workers(date,text,integer,jsonb,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_production_with_workers(date,text,integer,jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_production_with_workers(date,text,integer,jsonb,uuid) TO authenticated;
