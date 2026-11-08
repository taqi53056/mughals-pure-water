-- MUGHAL'S PURE WATER
-- Protect the single permanent Owner worker record.
-- Applied and verified on live Supabase on 2026-11-09.

CREATE OR REPLACE FUNCTION public.guard_fixed_owner_worker()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF TG_OP='DELETE' AND OLD.is_owner THEN
    RAISE EXCEPTION 'The permanent MUGHAL''S PURE WATER Owner worker record cannot be deleted.';
  END IF;

  IF TG_OP='UPDATE' AND OLD.is_owner AND (
    NEW.id IS DISTINCT FROM OLD.id
    OR NEW.is_owner IS DISTINCT FROM true
    OR NEW.is_active IS DISTINCT FROM true
  ) THEN
    RAISE EXCEPTION 'The permanent Owner worker record cannot be reassigned, demoted, or deactivated.';
  END IF;

  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS protect_fixed_owner_worker ON public.workers;
CREATE TRIGGER protect_fixed_owner_worker
BEFORE UPDATE OR DELETE ON public.workers
FOR EACH ROW EXECUTE FUNCTION public.guard_fixed_owner_worker();

-- Verification: exactly one active owner remains.
SELECT count(*) AS active_owner_count
FROM public.workers
WHERE is_owner=true AND is_active=true;
