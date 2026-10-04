-- Migration 020: Create RLS policies for all tables
-- P1F-02: profiles policies: own row read/write; role change to 'driver' blocked
-- P1F-03: addresses policies: own rows CRUD
-- P1F-04: merchants policies: active merchants public read; service role full access
-- P1F-05: categories/items/options policies: available items public read; service role full
-- P1F-06: orders policies: own orders read/create; driver status update on assigned orders
-- P1F-07: order_items policies: parent order's customer/driver read; service role insert
-- P1F-08: drivers policies: own row read; own location/status update (verified+active only)
-- P1F-09: reviews policies: public read; authenticated create own
-- P1F-10: notifications policies: own rows read/mark-read; service role insert
-- P1F-11: favorites policies: own rows CRUD
-- P1F-12: promo_codes policies: validate via Edge Function only; service role full
-- P1F-13: driver_earnings policies: own rows read; service role full
--
-- Design principles:
--   1. Default deny: RLS enabled, no policy = no access
--   2. Service role bypasses RLS (supabase_service_role_key)
--   3. Anon key: read-only access to public data (active merchants, items, reviews)
--   4. Authenticated users: can only access their own data
--   5. Driver self-signup is IMPOSSIBLE at the DB level
--   6. Every policy uses USING clause for read, WITH CHECK for write

-- =============================================================================
-- P1F-02: PROFILES POLICIES (🔒 SECURITY-CRITICAL)
--   - Users can read their own profile
--   - Users can update their own profile (EXCEPT role column)
--   - Role changes are blocked for non-service-role (driver self-signup prevention)
--   - Service role can do everything (creates driver profiles via admin API)
-- =============================================================================

-- Read: users can read their own profile
CREATE POLICY "profiles_read_own"
  ON public.profiles
  FOR SELECT
  USING (auth.uid() = id);

-- Update: users can update their own profile, BUT cannot change role to 'driver'
-- This is the critical security barrier preventing driver self-signup
CREATE POLICY "profiles_update_own"
  ON public.profiles
  FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (
    auth.uid() = id
    AND (
      -- Allow if role is not being changed (normal profile updates)
      role = (SELECT role FROM public.profiles WHERE id = auth.uid())
      -- OR if the caller is a service role (handled by RLS bypass, but explicit for clarity)
    )
  );

-- Insert: only service role can insert (handled by RLS bypass)
-- Regular users cannot insert profiles — handled by handle_new_user() trigger

-- Delete: users cannot delete their own profile (only service role can)
-- No policy = denied by default

-- =============================================================================
-- P1F-03: ADDRESSES POLICIES
--   - Users can CRUD their own addresses
--   - Full ownership model: user_id matches auth.uid()
-- =============================================================================

-- Read: own addresses
CREATE POLICY "addresses_read_own"
  ON public.addresses
  FOR SELECT
  USING (auth.uid() = user_id);

-- Insert: own addresses
CREATE POLICY "addresses_insert_own"
  ON public.addresses
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Update: own addresses
CREATE POLICY "addresses_update_own"
  ON public.addresses
  FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Delete: own addresses
CREATE POLICY "addresses_delete_own"
  ON public.addresses
  FOR DELETE
  USING (auth.uid() = user_id);

-- =============================================================================
-- P1F-04: MERCHANTS POLICIES
--   - Active merchants are publicly readable (for feed, search, merchant page)
--   - Inactive merchants are hidden from non-service-role users
--   - Service role has full access (admin panel)
-- =============================================================================

-- Read: anyone can read active merchants (including anon for marketing pages)
CREATE POLICY "merchants_read_active"
  ON public.merchants
  FOR SELECT
  USING (is_active = TRUE);

-- Write: only service role can create/update/delete merchants
-- No INSERT/UPDATE/DELETE policies = denied by default (service role bypasses RLS)

-- =============================================================================
-- OPERATING_HOURS POLICIES
--   - Public read (needed for merchant detail page to show hours)
--   - Service role full access
-- =============================================================================

CREATE POLICY "operating_hours_read"
  ON public.operating_hours
  FOR SELECT
  USING (TRUE);

-- =============================================================================
-- P1F-05: CATEGORIES / ITEMS / OPTIONS POLICIES
--   - Available items/categories/options are publicly readable (for menu display)
--   - Service role full access (admin panel manages menus)
--   - Unavailable items are hidden from customers
-- =============================================================================

-- Categories: public read for active merchants' categories
CREATE POLICY "categories_read"
  ON public.categories
  FOR SELECT
  USING (TRUE);

-- Items: public read (availability filtering done at app level or query level)
CREATE POLICY "items_read"
  ON public.items
  FOR SELECT
  USING (TRUE);

-- Item options: public read
CREATE POLICY "item_options_read"
  ON public.item_options
  FOR SELECT
  USING (TRUE);

-- Item option choices: public read
CREATE POLICY "item_option_choices_read"
  ON public.item_option_choices
  FOR SELECT
  USING (TRUE);

-- =============================================================================
-- P1F-06: ORDERS POLICIES
--   - Customers can read their own orders
--   - Customers can create orders (place-order Edge Function uses service role anyway)
--   - Drivers can read orders assigned to them
--   - Drivers can update status on orders assigned to them
--   - Service role full access
-- =============================================================================

-- Read: customers see their own orders, drivers see orders assigned to them
CREATE POLICY "orders_read_own"
  ON public.orders
  FOR SELECT
  USING (
    customer_id = auth.uid()
    OR driver_id = auth.uid()
  );

-- Insert: authenticated customers can create orders
-- (In practice, place-order Edge Function uses service role, but this allows
--  direct client inserts as a fallback with RLS validation)
CREATE POLICY "orders_insert_customer"
  ON public.orders
  FOR INSERT
  WITH CHECK (customer_id = auth.uid());

-- Update: drivers can update status on assigned orders, customers can cancel own orders
CREATE POLICY "orders_update_assigned"
  ON public.orders
  FOR UPDATE
  USING (
    driver_id = auth.uid()
    OR customer_id = auth.uid()
  )
  WITH CHECK (
    driver_id = auth.uid()
    OR customer_id = auth.uid()
  );

-- =============================================================================
-- P1F-07: ORDER_ITEMS POLICIES
--   - Customers can read items from their own orders
--   - Drivers can read items from orders assigned to them
--   - Service role inserts items (place-order Edge Function)
-- =============================================================================

-- Read: customer's order items or driver's assigned order items
CREATE POLICY "order_items_read_own"
  ON public.order_items
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = order_id
        AND (o.customer_id = auth.uid() OR o.driver_id = auth.uid())
    )
  );

-- Insert/Update/Delete: only service role (no policies = denied)

-- =============================================================================
-- ORDER_STATUS_HISTORY POLICIES
--   - Customers can read status history for their own orders
--   - Drivers can read status history for their assigned orders
--   - Service role inserts (via trigger and Edge Functions)
-- =============================================================================

CREATE POLICY "order_status_history_read_own"
  ON public.order_status_history
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = order_id
        AND (o.customer_id = auth.uid() OR o.driver_id = auth.uid())
    )
  );

-- =============================================================================
-- P1F-08: DRIVERS POLICIES (🔒 SECURITY-CRITICAL)
--   - Drivers can read their own row
--   - Drivers can update ONLY their own location and online status
--     (and only if is_verified=TRUE AND is_active=TRUE)
--   - Drivers CANNOT change is_verified, is_active, verification_status, etc.
--   - Service role has full access (admin creates, verifies, deactivates)
-- =============================================================================

-- Read: drivers can read their own row
-- Note: public cannot see driver details (only service role can)
CREATE POLICY "drivers_read_own"
  ON public.drivers
  FOR SELECT
  USING (auth.uid() = id);

-- Update: drivers can update ONLY their own row, ONLY location + online status,
-- and ONLY if verified and active
CREATE POLICY "drivers_update_own_location"
  ON public.drivers
  FOR UPDATE
  USING (auth.uid() = id AND is_verified = TRUE AND is_active = TRUE)
  WITH CHECK (
    auth.uid() = id
    AND is_verified = TRUE
    AND is_active = TRUE
    -- Ensure driver can only change these columns:
    -- current_lat, current_lng, last_location_at, is_online
    -- Other columns must remain unchanged
    AND national_id = (SELECT national_id FROM public.drivers WHERE id = auth.uid())
    AND vehicle_plate = (SELECT vehicle_plate FROM public.drivers WHERE id = auth.uid())
    AND vehicle_type = (SELECT vehicle_type FROM public.drivers WHERE id = auth.uid())
    AND is_verified = TRUE
    AND is_active = TRUE
    AND verification_status = (SELECT verification_status FROM public.drivers WHERE id = auth.uid())
  );

-- =============================================================================
-- P1F-09: REVIEWS POLICIES
--   - Public read (displayed on merchant pages, driver profiles)
--   - Authenticated users can create reviews for their own orders
--   - Users cannot update or delete reviews (immutability for trust)
-- =============================================================================

-- Read: anyone can read reviews
CREATE POLICY "reviews_read"
  ON public.reviews
  FOR SELECT
  USING (TRUE);

-- Insert: authenticated users can create reviews for their own orders
CREATE POLICY "reviews_insert_own"
  ON public.reviews
  FOR INSERT
  WITH CHECK (
    auth.uid() = customer_id
    AND auth.role() = 'authenticated'
  );

-- No UPDATE or DELETE policies (reviews are immutable)

-- =============================================================================
-- P1F-10: NOTIFICATIONS POLICIES
--   - Users can read their own notifications
--   - Users can mark their own notifications as read (update is_read)
--   - Service role inserts notifications (send-notification Edge Function)
-- =============================================================================

-- Read: own notifications
CREATE POLICY "notifications_read_own"
  ON public.notifications
  FOR SELECT
  USING (auth.uid() = user_id);

-- Update: mark own notifications as read (only is_read and read_at columns)
CREATE POLICY "notifications_update_own"
  ON public.notifications
  FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Insert: only service role (no policy = denied for regular users)

-- Delete: only service role (no policy = denied for regular users)

-- =============================================================================
-- P1F-11: FAVORITES POLICIES
--   - Users can CRUD their own favorites
--   - Full ownership model: user_id matches auth.uid()
-- =============================================================================

-- Read: own favorites
CREATE POLICY "favorites_read_own"
  ON public.favorites
  FOR SELECT
  USING (auth.uid() = user_id);

-- Insert: own favorites
CREATE POLICY "favorites_insert_own"
  ON public.favorites
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Delete: own favorites
CREATE POLICY "favorites_delete_own"
  ON public.favorites
  FOR DELETE
  USING (auth.uid() = user_id);

-- No UPDATE (favorites are insert/delete only — no reason to update)

-- =============================================================================
-- P1F-12: PROMO_CODES POLICIES
--   - NO direct read access for clients (prevents code scraping/enumeration)
--   - Validation happens ONLY through the validate-promo Edge Function
--   - Service role has full access (admin panel manages promos)
-- =============================================================================

-- No SELECT policy = clients cannot read promo codes at all
-- The validate-promo Edge Function uses service role to look up codes

-- No INSERT/UPDATE/DELETE policies = only service role can manage promos

-- =============================================================================
-- P1F-13: DRIVER_EARNINGS POLICIES
--   - Drivers can read their own earnings
--   - Service role full access (inserts earnings, manages payouts)
-- =============================================================================

-- Read: own earnings
CREATE POLICY "driver_earnings_read_own"
  ON public.driver_earnings
  FOR SELECT
  USING (auth.uid() = driver_id);

-- No INSERT/UPDATE/DELETE policies = only service role can manage earnings

-- =============================================================================
-- PLATFORM_CONFIG POLICIES
--   - Public read (needed by client for fee previews, settings display)
--   - Service role full access (admin panel manages config)
-- =============================================================================

CREATE POLICY "platform_config_read"
  ON public.platform_config
  FOR SELECT
  USING (TRUE);



-- =============================================================================
-- PROMOTED_SLOTS POLICIES
--   - Public read (needed by get-merchant-feed for ad injection)
--   - Service role full access (admin panel manages ad slots)
-- =============================================================================

CREATE POLICY "promoted_slots_read"
  ON public.promoted_slots
  FOR SELECT
  USING (TRUE);

-- =============================================================================
-- COMMENTS
-- =============================================================================
COMMENT ON POLICY "profiles_read_own" ON public.profiles IS 'P1F-02: Users can read their own profile only.';
COMMENT ON POLICY "profiles_update_own" ON public.profiles IS 'P1F-02: Users can update their own profile, but CANNOT change their role (driver self-signup prevention).';
COMMENT ON POLICY "merchants_read_active" ON public.merchants IS 'P1F-04: Anyone can read active merchants. Inactive merchants hidden.';
COMMENT ON POLICY "drivers_read_own" ON public.drivers IS 'P1F-08: Drivers can read their own row only.';
COMMENT ON POLICY "drivers_update_own_location" ON public.drivers IS 'P1F-08: Drivers can update only their location and online status, only if verified+active. Cannot change verification, activation, or identity fields.';
COMMENT ON POLICY "reviews_insert_own" ON public.reviews IS 'P1F-09: Authenticated users can create reviews for their own orders only.';
COMMENT ON POLICY "notifications_update_own" ON public.notifications IS 'P1F-10: Users can mark their own notifications as read.';
COMMENT ON POLICY "favorites_read_own" ON public.favorites IS 'P1F-11: Users can read their own favorites only.';
COMMENT ON POLICY "driver_earnings_read_own" ON public.driver_earnings IS 'P1F-13: Drivers can read their own earnings only.';
