-- Trigger-only SECURITY DEFINER functions are not callable as ordinary RPCs.
-- Remove their default PUBLIC EXECUTE grant; existing triggers remain attached.
REVOKE EXECUTE ON FUNCTION private.mpw_guard_credit_sale_store() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION private.mpw_guard_worker_payout_balance() FROM PUBLIC;
