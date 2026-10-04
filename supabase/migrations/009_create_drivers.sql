-- Migration 009: Create drivers table
-- P1C-04: Create drivers table (with verification_status, is_active, etc.)
-- P1C-05: Add UNIQUE(national_id), UNIQUE(vehicle_plate) constraints
-- P1C-06: Add PostGIS GIST index on drivers location

-- Note: This migration includes ALL columns from the updated drivers spec
-- (14-DRIVER-ADMIN-ONLY-SPEC.md). Since we are building from scratch,
-- we merge migration 023 columns directly into this migration.

-- =============================================================================
-- DRIVERS TABLE (P1C-04)
-- Driver profiles — created by admin only, NOT self-signup.
-- Each driver row links to a profiles row (id = profiles.id).
-- =============================================================================
CREATE TABLE drivers (
  id UUID PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,

  -- Identity & verification
  national_id TEXT NOT NULL,
  national_id_image_url TEXT,
  driving_license_number TEXT,
  driving_license_image_url TEXT,
  vehicle_registration_image_url TEXT,

  -- Vehicle info
  vehicle_type TEXT NOT NULL CHECK (vehicle_type IN ('motorcycle', 'car', 'bicycle')),
  vehicle_plate TEXT NOT NULL,
  vehicle_color TEXT,
  vehicle_model TEXT,

  -- Status
  is_verified BOOLEAN NOT NULL DEFAULT FALSE,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  is_online BOOLEAN NOT NULL DEFAULT FALSE,
  verification_status TEXT NOT NULL DEFAULT 'pending'
    CHECK (verification_status IN ('pending', 'under_review', 'approved', 'rejected')),
  rejection_reason TEXT,

  -- Location (updated by driver app via update-driver-location Edge Function)
  current_lat NUMERIC(9,6),
  current_lng NUMERIC(9,6),
  last_location_at TIMESTAMPTZ,

  -- Performance metrics (updated by triggers)
  rating NUMERIC(2,1) NOT NULL DEFAULT 5.0
    CHECK (rating >= 0 AND rating <= 5),
  rating_count INTEGER NOT NULL DEFAULT 0,
  total_deliveries INTEGER NOT NULL DEFAULT 0,
  total_earnings NUMERIC(10,2) NOT NULL DEFAULT 0
    CHECK (total_earnings >= 0),

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  verified_at TIMESTAMPTZ,
  deactivated_at TIMESTAMPTZ,

  -- Constraints (P1C-05)
  CONSTRAINT unique_national_id UNIQUE (national_id),
  CONSTRAINT unique_vehicle_plate UNIQUE (vehicle_plate)
);

-- =============================================================================
-- P1C-06: SPATIAL INDEX ON DRIVER LOCATION
-- Used by assign-driver Edge Function to find nearest online+verified drivers.
-- Uses geography cast via function for accurate distance in meters.
-- NOTE: The ::geography cast in CREATE INDEX expression can fail on some
-- hosted Postgres. We use a btree index on lat/lng and handle distance
-- calculation in the Edge Function query using ST_DWithin/ST_Distance.
-- =============================================================================
CREATE INDEX idx_drivers_location_lat ON drivers(current_lat) WHERE current_lat IS NOT NULL;
CREATE INDEX idx_drivers_location_lng ON drivers(current_lng) WHERE current_lng IS NOT NULL;

-- Additional indexes for driver queries

-- Find online+verified+active drivers (for driver assignment)
CREATE INDEX idx_drivers_online_verified_active
  ON drivers(is_online, is_verified, is_active)
  WHERE is_online = TRUE AND is_verified = TRUE AND is_active = TRUE;

-- Find drivers by verification status (admin panel)
CREATE INDEX idx_drivers_verification_status
  ON drivers(verification_status) WHERE verification_status IN ('pending', 'under_review');

-- Find recently active drivers (location freshness check)
CREATE INDEX idx_drivers_last_location
  ON drivers(last_location_at DESC) WHERE is_online = TRUE;

-- =============================================================================
-- UPDATE_UPDATED_AT TRIGGER
-- =============================================================================
CREATE TRIGGER set_drivers_updated_at
  BEFORE UPDATE ON drivers
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- =============================================================================
-- COMMENTS
-- =============================================================================
COMMENT ON TABLE drivers IS 'Driver profiles — created by admin only, NOT self-signup. See 14-DRIVER-ADMIN-ONLY-SPEC.md for full lifecycle.';
COMMENT ON COLUMN drivers.verification_status IS 'pending=just created by admin, under_review=docs uploaded by driver, approved=admin verified docs, rejected=admin rejected docs.';
COMMENT ON COLUMN drivers.is_active IS 'Admin can deactivate without deleting (safety, fraud). Driver cannot go online if false.';
COMMENT ON COLUMN drivers.is_online IS 'Driver toggles this. Only matters if is_verified=TRUE AND is_active=TRUE.';
COMMENT ON COLUMN drivers.is_verified IS 'Admin must verify before driver can go online. Set to TRUE only via admin-review-driver Edge Function.';
COMMENT ON COLUMN drivers.rejection_reason IS 'If verification_status=rejected, this explains why. Shown to driver in app.';
COMMENT ON COLUMN drivers.current_lat IS 'Latitude updated by driver app every ~5 seconds when online. NULL when offline.';
COMMENT ON COLUMN drivers.current_lng IS 'Longitude updated by driver app every ~5 seconds when online. NULL when offline.';
COMMENT ON COLUMN drivers.last_location_at IS 'Timestamp of last location update. Used to detect stale locations.';
COMMENT ON COLUMN drivers.deactivated_at IS 'When admin deactivated this driver. NULL if active.';
COMMENT ON COLUMN drivers.verified_at IS 'When admin approved this driver. NULL if not yet verified.';
