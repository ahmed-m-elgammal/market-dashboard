-- Migration 053: Enable Supabase Realtime publication for admin dashboard tables
--
-- The admin dashboard subscribes to postgres_changes events on the following
-- tables via Supabase Realtime (WebSocket). For these events to fire, each
-- table must be added to the `supabase_realtime` publication.
--
-- Supabase projects created after 2023-01-01 have all public tables in the
-- realtime publication by default. This migration is a safety net for
-- self-hosted or older projects where the publication may not include all
-- tables.
--
-- Sprint: Real-time dashboard updates (SSE/WebSocket)
-- See: docs/plans/ADMIN-PANEL-FULL-UPGRADE.md Phase 5 — Realtime

-- Drop and recreate the publication to ensure a clean state.
-- This is safe because the publication only controls which tables broadcast
-- change events — it does NOT affect data or RLS.
DROP PUBLICATION IF EXISTS supabase_realtime;

CREATE PUBLICATION supabase_realtime FOR TABLE
  public.profiles,
  public.merchants,
  public.operating_hours,
  public.categories,
  public.items,
  public.item_options,
  public.item_option_choices,
  public.orders,
  public.order_items,
  public.order_status_history,
  public.drivers,
  public.driver_documents,
  public.driver_status_history,
  public.driver_earnings,
  public.addresses,
  public.promo_codes,
  public.promo_code_usage,
  public.promoted_slots,
  public.alert_rules,
  public.audit_logs,
  public.data_access_log,
  public.platform_config,
  public.notifications,
  public.reviews,
  public.favorites,
  public.cancellation_rules,
  public.wallet_audit_log
  WITH (publish = 'insert, update, delete');

-- Verify the publication includes all tables
COMMENT ON PUBLICATION supabase_realtime IS 'Supabase Realtime publication — includes all admin-dashboard-tracked tables for postgres_changes events. Sprint: Real-time dashboard updates.';
