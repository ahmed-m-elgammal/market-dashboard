-- Migration 004: Create platform_config table + default values
-- P1A-09: Create platform_config table (runtime key-value config)
-- P1A-10: Insert default platform config values

-- =============================================================================
-- PLATFORM_CONFIG TABLE
-- Key-value store for runtime configuration.
-- Values can be edited from the admin panel WITHOUT code deployment.
-- Used by DB functions (calculate_delivery_fee, etc.) and edge functions.
-- =============================================================================
CREATE TABLE platform_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Configuration key (unique identifier)
  key TEXT NOT NULL UNIQUE,

  -- Configuration value (stored as text, cast by consuming functions)
  value TEXT NOT NULL,

  -- Description for admin UI
  description TEXT,

  -- Value type hint for admin UI rendering (number, string, boolean, json)
  value_type TEXT NOT NULL DEFAULT 'string'
    CHECK (value_type IN ('string', 'number', 'boolean', 'json')),

  -- Whether this config is editable from admin panel
  is_editable BOOLEAN NOT NULL DEFAULT TRUE,

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- UPDATE_UPDATED_AT TRIGGER
-- =============================================================================
CREATE TRIGGER set_platform_config_updated_at
  BEFORE UPDATE ON platform_config
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- =============================================================================
-- P1A-10: INSERT DEFAULT PLATFORM CONFIG VALUES
-- These values are used by DB functions and edge functions.
-- Prices in EGP (Egyptian Pounds).
-- =============================================================================

-- Delivery fee calculation parameters
INSERT INTO platform_config (key, value, description, value_type) VALUES
  ('delivery_base_fee', '25.00', 'Base delivery fee in EGP', 'number'),
  ('delivery_per_km_rate', '5.00', 'Per-kilometer delivery fee in EGP', 'number'),
  ('delivery_free_threshold', '200.00', 'Order amount (EGP) above which delivery is free', 'number'),
  ('delivery_max_distance_km', '15', 'Maximum delivery distance in kilometers', 'number'),

  -- Platform fee
  ('platform_fee', '3.00', 'Platform service fee per order in EGP', 'number'),
  ('platform_fee_percentage', '0', 'Platform fee as percentage of order total (0 = fixed fee)', 'number'),

  -- Merchant commission
  ('default_commission_pct', '15.00', 'Default merchant commission percentage', 'number'),

  -- Driver earnings
  ('driver_earnings_pct', '80.00', 'Driver gets this percentage of delivery fee', 'number'),
  ('driver_min_earnings', '10.00', 'Minimum driver earnings per delivery in EGP', 'number'),

  -- Order settings
  ('order_auto_cancel_minutes', '30', 'Minutes before unconfirmed order is auto-cancelled', 'number'),
  ('order_duplicate_threshold_seconds', '10', 'Seconds to check for duplicate orders from same customer', 'number'),

  -- Driver assignment
  ('driver_search_radius_km', '5', 'Radius in km to search for available drivers', 'number'),
  ('driver_request_timeout_seconds', '30', 'Seconds to wait for driver response before trying next', 'number'),
  ('driver_max_location_update_interval_seconds', '5', 'Minimum seconds between driver location updates', 'number'),

  -- App behavior
  ('max_items_per_order', '50', 'Maximum number of items in a single order', 'number'),
  ('max_addresses_per_user', '10', 'Maximum saved addresses per user', 'number'),
  ('min_order_amount', '0.00', 'Minimum order amount in EGP (0 = no minimum)', 'number'),

  -- Promo defaults
  ('promo_max_discount_amount', '100.00', 'Maximum discount from a single promo code in EGP', 'number');

-- =============================================================================
-- COMMENTS
-- =============================================================================
COMMENT ON TABLE platform_config IS 'Runtime configuration key-value store. Editable from admin panel without code deployment. Used by DB functions and edge functions.';
COMMENT ON COLUMN platform_config.key IS 'Unique configuration key. Used by functions to fetch values.';
COMMENT ON COLUMN platform_config.value IS 'Configuration value stored as text. Consuming functions cast to appropriate type.';
