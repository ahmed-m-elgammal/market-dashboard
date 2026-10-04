-- Migration 013: Create notifications table
-- P1D-03: Create notifications table
-- P1D-04: Add (user_id, is_read, created_at DESC) index on notifications

-- =============================================================================
-- NOTIFICATIONS TABLE (P1D-03)
-- In-app notifications for users. Inserted by Edge Functions (service role).
-- Push notifications are sent separately via Expo Push API.
-- =============================================================================
CREATE TABLE notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Recipient user
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,

  -- Notification type (for icon/routing in the app)
  type TEXT NOT NULL DEFAULT 'general'
    CHECK (type IN (
      'order_status',
      'order_assigned',
      'order_delivered',
      'order_cancelled',
      'promo',
      'driver_verified',
      'driver_rejected',
      'driver_deactivated',
      'driver_request',
      'review_request',
      'wallet',
      'general'
    )),

  -- Bilingual title and body
  title_ar TEXT NOT NULL,
  title_en TEXT NOT NULL,
  body_ar TEXT NOT NULL,
  body_en TEXT NOT NULL,

  -- Deep link / route to navigate when tapped (e.g., /order/{order_id})
  data JSONB NOT NULL DEFAULT '{}'::jsonb,

  -- Read status
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  read_at TIMESTAMPTZ,

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- P1D-04: INDEX FOR NOTIFICATIONS QUERY
-- Primary query: fetch a user's notifications, unread first, then by date.
-- =============================================================================
CREATE INDEX idx_notifications_user_read_created
  ON notifications(user_id, is_read, created_at DESC);

-- Index: count unread notifications (badge count)
CREATE INDEX idx_notifications_unread
  ON notifications(user_id) WHERE is_read = FALSE;

-- =============================================================================
-- COMMENTS
-- =============================================================================
COMMENT ON TABLE notifications IS 'In-app notifications. Inserted by Edge Functions via service role. Push notifications sent separately via Expo Push API.';
COMMENT ON COLUMN notifications.type IS 'Notification type for icon selection and deep linking in the app.';
COMMENT ON COLUMN notifications.data IS 'JSONB payload for deep linking. E.g., {"order_id": "...", "screen": "order_tracking"}.';
COMMENT ON COLUMN notifications.is_read IS 'False=unread (shown with dot/badge), True=read.';
