-- Allow signed-in users to read only the customer lifecycle timestamps.
-- RLS continues to restrict each customer to their own row and admins to all rows.
-- These fields are required by the admin pending-customer list and billing eligibility UI.
-- Sensitive PIN fields remain inaccessible to authenticated users.
GRANT SELECT (created_at, approved_at)
ON TABLE public.customers
TO authenticated;
