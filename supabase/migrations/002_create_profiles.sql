-- Migration 002: Create profiles table + auto-profile trigger
-- P1A-04: Create profiles table (extends Supabase auth.users)
-- P1A-05: Create auto-profile trigger (auth.users INSERT -> profiles row, role='customer')
-- P1A-06: Create update_updated_at trigger on profiles

-- =============================================================================
-- PROFILES TABLE
-- Extends Supabase auth.users with app-specific data.
-- One row per auth.users row, linked by id = auth.users.id.
-- =============================================================================
CREATE TABLE profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Identity
  full_name TEXT,
  phone TEXT,
  avatar_url TEXT,

  -- Role system: customer (default), driver (admin-created only), admin (manual)
  role TEXT NOT NULL DEFAULT 'customer'
    CHECK (role IN ('customer', 'driver', 'admin')),

  -- Preferences
  preferred_language TEXT NOT NULL DEFAULT 'ar'
    CHECK (preferred_language IN ('ar', 'en')),

  -- Wallet (for refunds, promotions — NOT for payment)
  wallet_balance NUMERIC(10,2) NOT NULL DEFAULT 0.00
    CHECK (wallet_balance >= 0),

  -- Expo push notification token
  expo_push_token TEXT,

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for looking up profiles by role (admin queries, driver listing)
CREATE INDEX idx_profiles_role ON profiles(role);

-- Index for looking up profile by phone
CREATE INDEX idx_profiles_phone ON profiles(phone) WHERE phone IS NOT NULL;

-- =============================================================================
-- COMMENTS
-- =============================================================================
COMMENT ON TABLE profiles IS 'Extends auth.users with app-specific profile data. Auto-created on signup.';
COMMENT ON COLUMN profiles.role IS 'customer=self-signup, driver=admin-created only, admin=manual insert. RLS prevents self-assignment to driver.';
COMMENT ON COLUMN profiles.wallet_balance IS 'Platform wallet for refunds and promotional credits. Not used for payments.';
COMMENT ON COLUMN profiles.preferred_language IS 'ar=Arabic (default for Egypt), en=English';

-- =============================================================================
-- P1A-05: AUTO-PROFILE TRIGGER
-- When a new user signs up (row inserted into auth.users), automatically
-- create a corresponding profiles row with role='customer'.
-- This is CRITICAL for security: ensures every new signup is a customer.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, avatar_url, preferred_language)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', ''),
    COALESCE(NEW.raw_user_meta_data->>'avatar_url', ''),
    COALESCE(NEW.raw_user_meta_data->>'preferred_language', 'ar')
  );
  RETURN NEW;
END;
$$;

-- Attach the trigger to auth.users
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

COMMENT ON FUNCTION public.handle_new_user() IS 'Security-critical: Auto-creates a profiles row with role=customer on every new auth.users insert. Prevents unauthenticated role escalation.';

-- =============================================================================
-- P1A-06: UPDATE_UPDATED_AT TRIGGER
-- Automatically updates the updated_at column on every row update.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE TRIGGER set_profiles_updated_at
  BEFORE UPDATE ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();
