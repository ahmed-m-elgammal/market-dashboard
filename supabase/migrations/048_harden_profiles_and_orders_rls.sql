-- Migration 048: Harden profiles + orders RLS policies (Sprint 0 security fixes)
--
-- Fixes audit issues:
--   S01 + S14: profiles_update_own allowed users to set their own wallet_balance,
--             expo_push_token, phone, etc. to arbitrary values. Replace with a
--             column-restricted policy that blocks wallet_balance and role
--             (must equal previous value), while still allowing the legitimate
--             user-editable fields (full_name, phone, avatar_url,
--             preferred_language, expo_push_token) used by auth.service.ts
--             updateProfile() and updateExpoPushToken().
--
--   S02:      orders_update_assigned allowed customers/drivers to rewrite ANY
--             field on their orders (total, payment_status, status, delivered_at).
--             Drop the policy entirely. All order mutations now go through:
--               - cancel_order RPC (migration 033, service-role only) via the
--                 cancel-order Edge Function (customer cancels)
--               - driver-actions Edge Function (driver status updates)
--               - admin API routes (admin updates)
--             No direct client UPDATE on orders is permitted.
--
-- Pattern: mirrors drivers_update_own_location (migration 020:243-260) — every
-- column the user must NOT change is pinned to its previous value via a
-- correlated subquery.

-- =============================================================================
-- S01 + S14: Replace profiles_update_own with a column-restricted policy
-- =============================================================================

DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;

-- Users can update their own profile, BUT cannot change:
--   - wallet_balance (must go through adjust_wallet_balance RPC, migration 034)
--   - role          (driver self-signup prevention — also enforced by trigger 024)
-- Allowed to change: full_name, phone, avatar_url, preferred_language, expo_push_token.
CREATE POLICY "profiles_update_own"
  ON public.profiles
  FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (
    auth.uid() = id
    -- wallet_balance must be unchanged (blocks direct wallet top-up fraud)
    AND wallet_balance IS NOT DISTINCT FROM (
      SELECT wallet_balance FROM public.profiles WHERE id = auth.uid()
    )
    -- role must be unchanged (defense-in-depth; also enforced by trigger 024)
    AND role IS NOT DISTINCT FROM (
      SELECT role FROM public.profiles WHERE id = auth.uid()
    )
  );

COMMENT ON POLICY "profiles_update_own" ON public.profiles IS 'S01/S14 fix: Users can update own profile EXCEPT wallet_balance and role (must equal previous value). Wallet changes must go through adjust_wallet_balance RPC; role changes are admin-only.';

-- =============================================================================
-- S02: Drop orders_update_assigned — no direct client UPDATE on orders
-- =============================================================================

DROP POLICY IF EXISTS "orders_update_assigned" ON public.orders;

COMMENT ON TABLE public.orders IS 'S02 fix: No direct client UPDATE policy. All order mutations go through cancel_order RPC (migration 033, via cancel-order Edge Function), driver-actions Edge Function, or admin API routes (service role).';
