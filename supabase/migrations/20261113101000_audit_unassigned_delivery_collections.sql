drop trigger if exists audit_unassigned_19l_delivery_collections on public.unassigned_19l_delivery_collections;
create trigger audit_unassigned_19l_delivery_collections
after insert or update or delete on public.unassigned_19l_delivery_collections
for each row execute function public.log_changes();
revoke all on sequence public.unassigned_19l_delivery_collections_id_seq from anon, authenticated;
