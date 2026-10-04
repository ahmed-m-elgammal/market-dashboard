-- Migration 087: get_driver_kpis SQL RPC
--
-- P2 fix from money-movement-gap-analysis.md §4.3 (HIGH performance):
-- The GET /api/drivers/[id] admin route previously ran FOUR separate
-- Supabase queries to compute KPIs (week earnings, month earnings, pending
-- earnings, last paid settlement), then JS-reduced the SUMs. A driver with
-- 1000 deliveries in 30 days meant 1000 rows transferred just to compute
-- three numbers — the classic "fetch all rows then reduce" anti-pattern
-- called out in SKILLs/code-reviewer/AGENTS.md §"Avoid N+1 Query Problem".
--
-- This migration adds a single SQL RPC that runs all three SUMs + counts
-- in ONE query (Postgres FILTER clause) and returns the result as a single
-- row. The admin route then makes one RPC call instead of three selects +
-- JS reduce.
--
-- Performance characteristics:
--   * Before: 3 round-trips + N rows transferred (N = deliveries in window)
--   * After:  1 round-trip + 1 row transferred
--   * DB work: scans driver_earnings ONCE with FILTER aggregates (single
--     pass over the rows matching driver_id, applying 3 WHERE filters in
--     parallel) instead of 3 separate scans
--
-- The RPC is STABLE (no side effects, same inputs → same outputs within a
-- transaction) and SECURITY DEFINER (so it can be called from the admin
-- route's service-role client without needing RLS policies on
-- driver_earnings — the existing driver_earnings RLS already gates access
-- to drivers + admins, and this RPC only reads, never writes).

CREATE OR REPLACE FUNCTION public.get_driver_kpis(p_driver_id UUID)
RETURNS TABLE (
  week_earnings NUMERIC,
  week_deliveries INTEGER,
  month_earnings NUMERIC,
  month_deliveries INTEGER,
  pending_earnings NUMERIC,
  pending_count INTEGER,
  last_settlement JSONB
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    COALESCE(SUM(net_earnings) FILTER (WHERE created_at >= NOW() - INTERVAL '7 days'), 0)::NUMERIC,
    (COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '7 days'))::INTEGER,
    COALESCE(SUM(net_earnings) FILTER (WHERE created_at >= NOW() - INTERVAL '30 days'), 0)::NUMERIC,
    (COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '30 days'))::INTEGER,
    COALESCE(SUM(net_earnings) FILTER (WHERE payout_status = 'pending'), 0)::NUMERIC,
    (COUNT(*) FILTER (WHERE payout_status = 'pending'))::INTEGER,
    (
      SELECT to_jsonb(s)
      FROM public.driver_settlements s
      WHERE s.driver_id = p_driver_id AND s.status = 'paid'
      ORDER BY s.paid_at DESC
      LIMIT 1
    )
  FROM public.driver_earnings
  WHERE driver_id = p_driver_id;
$$;

COMMENT ON FUNCTION public.get_driver_kpis(UUID) IS 'Returns a single-row summary of a driver earnings KPIs: 7-day + 30-day SUMs and counts, pending payout SUM and count, and the most recent paid settlement as JSONB. Replaces the 4-query + JS-reduce pattern in apps/admin/src/app/api/drivers/[id]/route.ts (gap-analysis §4.3). STABLE — read-only. SECURITY DEFINER — service role only (called from the admin route).';

REVOKE ALL ON FUNCTION public.get_driver_kpis(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_driver_kpis(UUID) TO service_role;
