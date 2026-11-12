-- Force all raw-material writes through the atomic paired-bottle/cap RPC.
-- The RPC retains admin checks and stock validation; clients may only read rows.
ALTER FUNCTION public.save_raw_material_purchase_atomic(jsonb,uuid,uuid) SECURITY DEFINER;
ALTER FUNCTION public.save_raw_material_purchase_atomic(jsonb,uuid,uuid) SET search_path = '';
REVOKE ALL ON FUNCTION public.save_raw_material_purchase_atomic(jsonb,uuid,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_raw_material_purchase_atomic(jsonb,uuid,uuid) TO authenticated;
DROP POLICY IF EXISTS "Admins insert raw material purchases" ON public.raw_material_purchases;
DROP POLICY IF EXISTS "Admins update raw material purchases" ON public.raw_material_purchases;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.raw_material_purchases FROM anon, authenticated;
GRANT SELECT ON TABLE public.raw_material_purchases TO authenticated;
