-- Migration 019: Enable Row Level Security on ALL tables
-- P1F-01: Enable RLS on ALL tables (🔒 SECURITY-CRITICAL)
--
-- RLS is the foundation of data security in Supabase.
-- Default deny: no rows visible unless a policy explicitly grants access.
-- Service role (supabase_service_role_key) bypasses RLS entirely.
-- Anon key (supabase_anon_key) can only access what policies allow.
--
-- This migration enables RLS on every table. Individual policies
-- are defined in 020_create_rls_policies.sql and 023_update_rls_for_admin_driver.sql.

-- =============================================================================
-- P1F-01: ENABLE RLS ON ALL TABLES
-- Order: follow migration creation order for consistency
-- =============================================================================

-- Core user tables (from 002, 003, 004)
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_config ENABLE ROW LEVEL SECURITY;

-- Merchant + menu tables (from 005, 006, 007)
ALTER TABLE public.merchants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.operating_hours ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.item_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.item_option_choices ENABLE ROW LEVEL SECURITY;

-- Orders + driver tables (from 008, 009, 010)
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_status_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.drivers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.driver_earnings ENABLE ROW LEVEL SECURITY;

-- Supporting tables (from 011, 012, 013, 014, 015)
ALTER TABLE public.promo_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.promoted_slots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.favorites ENABLE ROW LEVEL SECURITY;


-- =============================================================================
-- VERIFY: All tables have RLS enabled
-- Run this query in the SQL editor to verify:
--   SELECT tablename, rowsecurity FROM pg_tables
--   WHERE schemaname = 'public' AND rowsecurity = false;
-- Expected: 0 rows (all tables have RLS enabled)
-- =============================================================================
