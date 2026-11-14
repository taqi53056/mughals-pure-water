CREATE OR REPLACE FUNCTION private.mpw_require_linked_unassigned_income()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF NEW.category='غیر منسلک 19L سپلائی کی وصولی'
     AND NOT EXISTS (
       SELECT 1
       FROM public.unassigned_19l_delivery_collections c
       WHERE c.business_income_id=NEW.id
     ) THEN
    RAISE EXCEPTION 'غیر منسلک 19L وصولی عمومی آمدن میں الگ سے درج نہیں ہو سکتی؛ مخصوص سپلائی وصولی کا عمل استعمال کریں۔'
      USING errcode='23514';
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION private.mpw_require_linked_unassigned_income() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS business_income_unassigned_collection_link_guard ON public.business_income;
CREATE CONSTRAINT TRIGGER business_income_unassigned_collection_link_guard
AFTER INSERT OR UPDATE ON public.business_income
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION private.mpw_require_linked_unassigned_income();
