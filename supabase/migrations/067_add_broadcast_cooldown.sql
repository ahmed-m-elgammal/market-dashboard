-- Migration 067: Add broadcast cooldown columns
--
-- P1-5 fix (MARKETING-IMPROVEMENT-PLAN.md Task 1.7):
-- The /api/promo-codes/[id]/push and /api/promoted-ads/[id]/push routes
-- invoke the send-notification Edge Function with broadcast: true, fanning
-- out to every user. There was no cooldown — an admin (or a script with a
-- stolen session) could spam the button and send unlimited push notifications.
--
-- This migration adds a last_broadcast_at column to both tables. The push
-- routes reject with 429 if the last broadcast was less than 1 hour ago,
-- and update the column to now() after a successful broadcast.

ALTER TABLE promo_codes    ADD COLUMN IF NOT EXISTS last_broadcast_at TIMESTAMPTZ;
ALTER TABLE promoted_slots ADD COLUMN IF NOT EXISTS last_broadcast_at TIMESTAMPTZ;

COMMENT ON COLUMN promo_codes.last_broadcast_at IS
  'P1-5: Timestamp of the last successful broadcast push. The /push route rejects with 429 if this is less than 1 hour ago.';
COMMENT ON COLUMN promoted_slots.last_broadcast_at IS
  'P1-5: Timestamp of the last successful broadcast push. The /push route rejects with 429 if this is less than 1 hour ago.';
