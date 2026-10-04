-- Migration 064: Add driver_order_requests to realtime publication (B2-G1)
--
-- The driver_order_requests table (created in migration 060) tracks driver
-- assignment requests (pending/accepted/declined/expired). The admin dashboard
-- needs realtime updates when a driver accepts or declines an order so the
-- order detail sheet can refresh without manual polling.
--
-- Migration 053 created the supabase_realtime publication with 27 tables but
-- did not include driver_order_requests (which didn't exist yet). Migration
-- 058 added alert_incidents. This migration adds driver_order_requests.
--
-- Without this, the admin UI receives no postgres_changes events for
-- driver_order_requests, so the order detail sheet's "driver assignment"
-- section stays stale until the next manual refresh or order-detail
-- invalidation triggered by an orders table update.

ALTER PUBLICATION supabase_realtime ADD TABLE public.driver_order_requests;

COMMENT ON PUBLICATION supabase_realtime IS 'Supabase Realtime publication — includes all admin-dashboard-tracked tables for postgres_changes events. Migration 064 added driver_order_requests.';
