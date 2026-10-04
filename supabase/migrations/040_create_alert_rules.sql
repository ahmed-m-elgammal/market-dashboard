-- Migration 040: Create alert_rules table
-- Per 20-MONITORING-OBSERVABILITY.md:
--   Configurable alert rules for the admin panel monitoring system.
--   Each rule defines a metric, condition, threshold, and notification channels.
--   Pre-configured with built-in rules for common operational alerts.

-- =============================================================================
-- ALERT_RULES TABLE
-- Configurable alert rules for the admin monitoring system.
-- =============================================================================

CREATE TABLE alert_rules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Rule definition
  name TEXT NOT NULL,
  description TEXT,

  -- What to monitor
  metric TEXT NOT NULL,           -- e.g., 'online_drivers', 'order_cancellation_rate', 'payment_failures'
  condition TEXT NOT NULL,        -- e.g., 'less_than', 'greater_than', 'equals'
  threshold NUMERIC NOT NULL,     -- The value to compare against
  duration_seconds INTEGER DEFAULT 300,  -- How long the condition must persist before alerting

  -- Alert configuration
  severity TEXT NOT NULL DEFAULT 'warning' CHECK (severity IN ('info', 'warning', 'critical')),
  is_active BOOLEAN NOT NULL DEFAULT true,
  notification_channels TEXT[] DEFAULT ARRAY['admin_panel'],  -- 'slack', 'email', 'admin_panel'

  -- Metadata
  created_by UUID REFERENCES public.profiles(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ
);

-- =============================================================================
-- INDEXES
-- =============================================================================

CREATE INDEX idx_alert_rules_active
  ON public.alert_rules(severity, is_active)
  WHERE is_active = true;

-- =============================================================================
-- ENABLE RLS
-- =============================================================================

ALTER TABLE public.alert_rules ENABLE ROW LEVEL SECURITY;

-- Service role only — admin panel manages alert rules via server-side client

-- =============================================================================
-- SEED: Built-in Alert Rules
-- =============================================================================

INSERT INTO public.alert_rules (name, description, metric, condition, threshold, duration_seconds, severity, is_active, notification_channels) VALUES
  (
    'No Drivers Online',
    'No drivers are online in any city for more than 10 minutes',
    'online_drivers', 'equals', 0, 600, 'critical',
    true, ARRAY['slack', 'email', 'admin_panel']
  ),
  (
    'High Order Cancellation Rate',
    'Order cancellation rate exceeds 20% in the last hour',
    'order_cancellation_rate', 'greater_than', 20, 3600, 'warning',
    true, ARRAY['slack', 'admin_panel']
  ),
  (
    'Payment Processing Failures',
    'More than 3 payment failures in 5 minutes',
    'payment_failures_5min', 'greater_than', 3, 300, 'critical',
    true, ARRAY['slack', 'email', 'admin_panel']
  ),
  (
    'Driver Verification Backlog',
    'More than 10 drivers pending verification for over 24 hours',
    'pending_verifications_24h', 'greater_than', 10, 86400, 'warning',
    true, ARRAY['slack', 'admin_panel']
  ),
  (
    'High Average Delivery Time',
    'Average delivery time exceeds 60 minutes in the last hour',
    'avg_delivery_time_minutes', 'greater_than', 60, 3600, 'warning',
    true, ARRAY['slack', 'admin_panel']
  ),
  (
    'Low Rating Driver',
    'A driver with 10+ deliveries has rating below 3.0',
    'driver_low_rating', 'less_than', 3.0, 0, 'warning',
    true, ARRAY['admin_panel']
  ),
  (
    'Storage Nearly Full',
    'Storage usage exceeds 80% of plan limit',
    'storage_usage_pct', 'greater_than', 80, 0, 'info',
    true, ARRAY['admin_panel']
  ),
  (
    'Rate Limit Threshold Approaching',
    'Edge Function rate limit usage exceeds 80%',
    'rate_limit_usage_pct', 'greater_than', 80, 0, 'info',
    true, ARRAY['admin_panel']
  );

-- =============================================================================
-- COMMENTS
-- =============================================================================

COMMENT ON TABLE public.alert_rules IS 'Configurable alert rules for the admin monitoring system. Pre-seeded with 8 built-in rules for common operational alerts.';
