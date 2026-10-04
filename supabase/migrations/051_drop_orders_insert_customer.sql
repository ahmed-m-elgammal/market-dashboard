-- Migration 051: Drop orders_insert_customer policy (Sprint 1 fix S19)
--
-- Audit issue S19: orders_insert_customer allowed any authenticated customer
-- to INSERT directly into orders via RLS, bypassing the place_order_with_items
-- RPC. The RPC enforces duplicate-order detection, max-items, merchant-active
-- check, atomic fee calculation, atomic promo usage enforcement, and
-- idempotency-key tracking. A direct INSERT skipped all of these — a customer
-- could create an order with total: 0 and payment_status: 'paid'.
--
-- Fix: drop the policy. With no INSERT policy, only the service role can
-- INSERT (which is the actual production path — the place-order Edge Function
-- uses the service role to invoke place_order_with_items).

DROP POLICY IF EXISTS "orders_insert_customer" ON public.orders;

COMMENT ON TABLE public.orders IS 'S02/S19 fix: No direct client INSERT or UPDATE policies. All order mutations go through cancel_order RPC (migration 033, via cancel-order Edge Function), place_order_with_items RPC (migration 045, via place-order Edge Function), driver-actions Edge Function, or admin API routes (service role).';
