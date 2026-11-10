-- Enable Realtime INSERT events for admin-side pending customer signup notices.
-- RLS on public.customers restricts row visibility to admins and active owners of their own rows.
ALTER PUBLICATION supabase_realtime ADD TABLE public.customers;
