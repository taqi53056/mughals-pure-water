-- The existing customer_notifications_guard_update trigger already enforces
-- that customers may only mark their own notification as read. Remove the
-- redundant second guard introduced in the previous migration.
drop trigger if exists mpw_customer_notification_update_guard on public.customer_notifications;
drop function if exists private.mpw_guard_customer_notification_update();
