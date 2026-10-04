-- Seed data for development environment
-- Per 09-EXECUTION-ORDER.md step 1.5: seed.sql
-- Creates test data for development: admin, merchants, drivers, customers, orders
--
-- ⚠️ WARNING: This file is for development ONLY. Remove or password-protect
-- all test accounts before production deployment.
--
-- Sprint 3 fix: this seed now creates auth.users entries FIRST (with known
-- UUIDs that match the profile UUIDs), then inserts profiles. Previously
-- the seed inserted profiles with hardcoded UUIDs but no corresponding
-- auth.users rows — which failed on a fresh DB because profiles.id has a
-- FK REFERENCES auth.users(id) ON DELETE CASCADE.
--
-- The seed also sets `app.allow_driver_role_change = 'true'` before
-- inserting driver profiles, because the prevent_driver_role_escalation
-- trigger (migration 024, hardened in 052) blocks role='driver' inserts
-- unless the caller is service_role or this session flag is set.
-- `supabase db push` runs as service_role, but the trigger checks
-- JWT claims which aren't set during db push — so we set the flag
-- explicitly to allow the seed to run.

-- =============================================================================
-- 0. SESSION FLAGS — allow driver-role inserts for seed data
-- =============================================================================
-- The prevent_driver_role_escalation trigger (migration 052/S15) blocks
-- role='driver' unless the caller is service_role (checked via JWT claims)
-- OR app.allow_driver_role_change = 'true'. During `supabase db push` there
-- is no JWT, so we set this flag to allow the seed's driver profiles.
SET LOCAL app.allow_driver_role_change = 'true';

-- =============================================================================
-- 1. AUTH USERS — must exist before profiles (FK constraint)
-- =============================================================================
-- Create auth.users entries with known UUIDs that match the profile UUIDs
-- below. Passwords are hashed with crypt() + bf (bcrypt) — the same format
-- Supabase Auth uses. Test password for all seed accounts: 'Seed@1234'
--
-- These INSERTs use ON CONFLICT DO NOTHING so re-running the seed is safe.

INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, role, aud, instance_id, created_at, updated_at)
VALUES
  -- Customers
  ('a0000001-0000-0000-0000-000000000001', 'ahmed@example.com', crypt('Seed@1234', gen_salt('bf')), NOW(), 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', NOW(), NOW()),
  ('a0000001-0000-0000-0000-000000000002', 'fatma@example.com', crypt('Seed@1234', gen_salt('bf')), NOW(), 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', NOW(), NOW()),
  ('a0000001-0000-0000-0000-000000000003', 'mohamed@example.com', crypt('Seed@1234', gen_salt('bf')), NOW(), 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', NOW(), NOW()),
  -- Drivers
  ('a0000001-0000-0000-0000-000000000010', 'driver.sayed@example.com', crypt('Seed@1234', gen_salt('bf')), NOW(), 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', NOW(), NOW()),
  ('a0000001-0000-0000-0000-000000000011', 'driver.mahmoud@example.com', crypt('Seed@1234', gen_salt('bf')), NOW(), 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', NOW(), NOW())
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- 2. TEST CUSTOMERS (profiles)
-- =============================================================================
-- Note: the handle_new_user trigger (migration 002) auto-creates a profile
-- when an auth.users row is inserted. But that trigger only sets role=
-- 'customer' and copies name from raw_user_meta_data. We insert explicit
-- profiles here with ON CONFLICT DO NOTHING so the trigger's auto-created
-- row (if any) is left alone, and our richer seed data is used for rows
-- that don't yet exist.

INSERT INTO public.profiles (id, full_name, phone, role, preferred_language, wallet_balance) VALUES
  ('a0000001-0000-0000-0000-000000000001', 'أحمد محمد', '+201012345678', 'customer', 'ar', 50.00),
  ('a0000001-0000-0000-0000-000000000002', 'Fatma Ali', '+201098765432', 'customer', 'en', 25.00),
  ('a0000001-0000-0000-0000-000000000003', 'محمد حسن', '+201055566677', 'customer', 'ar', 0.00)
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- 3. TEST MERCHANTS (Cairo-based)
-- =============================================================================

INSERT INTO public.merchants (id, name_ar, name_en, category, logo_url, cover_url, description_ar, description_en, address, lat, lng, city, area, phone, is_active, rating, rating_count, min_order_amount, estimated_delivery_minutes, delivery_fee_override, commission_pct) VALUES
  -- Restaurant 1: Egyptian food
  ('b0000001-0000-0000-0000-000000000001',
   'مطعم أكلنا هني', 'Aklana Henny Restaurant',
   'restaurant', NULL, NULL,
   'أفضل أكل مصري أصيل', 'Best authentic Egyptian food',
   '15 شارع التحرير، الدقي', 30.0384, 31.2028,
   'Cairo', 'Dokki', '+20233334444',
   TRUE, 4.5, 120, 30.00, 35, NULL, 15.00),

  -- Restaurant 2: Fast food
  ('b0000001-0000-0000-0000-000000000002',
   'برجر ستارز', 'Burger Stars',
   'restaurant', NULL, NULL,
   'أفضل برجر في القاهرة', 'Best burgers in Cairo',
   '42 شارع جامعة الدول العربية، المهندسين', 30.0444, 31.2057,
   'Cairo', 'Mohandessin', '+20244445555',
   TRUE, 4.2, 85, 50.00, 25, NULL, 15.00),

  -- Restaurant 3: Shawarma
  ('b0000001-0000-0000-0000-000000000003',
   'شاورما الشام', 'Al Sham Shawarma',
   'restaurant', NULL, NULL,
   'شاورما أصلية على الطريقة الشامية', 'Authentic Levantine shawarma',
   '8 شارع 9، المعادي', 29.9602, 31.2569,
   'Cairo', 'Maadi', '+20266667777',
   TRUE, 4.7, 200, 25.00, 20, NULL, 15.00),

  -- Pharmacy 1
  ('b0000001-0000-0000-0000-000000000004',
   'صيدلية العزبي', 'El Ezaby Pharmacy',
   'pharmacy', NULL, NULL,
   'صيدلية 24 ساعة', '24-hour pharmacy',
   '25 شارع الجمهورية، مصر الجديدة', 30.0876, 31.3278,
   'Cairo', 'Heliopolis', '+20288889999',
   TRUE, 4.3, 60, 0.00, 30, 10.00, 10.00),

  -- Pharmacy 2
  ('b0000001-0000-0000-0000-000000000005',
   'صيدلية سيف', 'Seif Pharmacy',
   'pharmacy', NULL, NULL,
   'أكبر سلسلة صيدليات', 'Largest pharmacy chain',
   '3 شارع النزهة، مدينة نصر', 30.0506, 31.3442,
   'Cairo', 'Nasr City', '+20211112222',
   TRUE, 4.1, 45, 0.00, 25, NULL, 10.00)
ON CONFLICT DO NOTHING;

-- =============================================================================
-- 4. OPERATING HOURS (7 days for each merchant)
-- =============================================================================

INSERT INTO public.operating_hours (merchant_id, day_of_week, open_time, close_time, is_closed)
SELECT m.id, d.dow,
  CASE WHEN d.dow IN (5) THEN '10:00' ELSE '09:00' END, -- Friday late opening
  CASE WHEN d.dow IN (4, 5) THEN '01:00' ELSE '23:00' END, -- Thu/Fri late closing
  FALSE
FROM public.merchants m
CROSS JOIN (
  VALUES (0), (1), (2), (3), (4), (5), (6)
) AS d(dow)
WHERE m.id IN ('b0000001-0000-0000-0000-000000000001',
               'b0000001-0000-0000-0000-000000000002',
               'b0000001-0000-0000-0000-000000000003',
               'b0000001-0000-0000-0000-000000000004',
               'b0000001-0000-0000-0000-000000000005')
ON CONFLICT DO NOTHING;

-- =============================================================================
-- 5. MENU CATEGORIES + ITEMS
-- =============================================================================

-- Categories for Restaurant 1 (Aklana Henny)
INSERT INTO public.categories (id, merchant_id, name_ar, name_en, sort_order) VALUES
  ('c0000001-0000-0000-0000-000000000001', 'b0000001-0000-0000-0000-000000000001', 'الأطباق الرئيسية', 'Main Dishes', 1),
  ('c0000001-0000-0000-0000-000000000002', 'b0000001-0000-0000-0000-000000000001', 'المشويات', 'Grills', 2),
  ('c0000001-0000-0000-0000-000000000003', 'b0000001-0000-0000-0000-000000000001', 'المشروبات', 'Drinks', 3)
ON CONFLICT DO NOTHING;

-- Items for Main Dishes
INSERT INTO public.items (id, merchant_id, category_id, name_ar, name_en, price, is_available, sort_order) VALUES
  ('d0000001-0000-0000-0000-000000000001', 'b0000001-0000-0000-0000-000000000001', 'c0000001-0000-0000-0000-000000000001', 'كشري', 'Koshari', 45.00, TRUE, 1),
  ('d0000001-0000-0000-0000-000000000002', 'b0000001-0000-0000-0000-000000000001', 'c0000001-0000-0000-0000-000000000001', 'ملوخية بالأرنب', 'Molokhia with Rabbit', 120.00, TRUE, 2),
  ('d0000001-0000-0000-0000-000000000003', 'b0000001-0000-0000-0000-000000000001', 'c0000001-0000-0000-0000-000000000001', 'حمص بالطحينة', 'Hummus with Tahini', 35.00, TRUE, 3),
  ('d0000001-0000-0000-0000-000000000004', 'b0000001-0000-0000-0000-000000000001', 'c0000001-0000-0000-0000-000000000002', 'شيش طاووق', 'Shish Tawook', 85.00, TRUE, 1),
  ('d0000001-0000-0000-0000-000000000005', 'b0000001-0000-0000-0000-000000000001', 'c0000001-0000-0000-0000-000000000002', 'كفتة مشوية', 'Grilled Kofta', 90.00, TRUE, 2),
  ('d0000001-0000-0000-0000-000000000006', 'b0000001-0000-0000-0000-000000000001', 'c0000001-0000-0000-0000-000000000003', 'عصير برتقان طازج', 'Fresh Orange Juice', 25.00, TRUE, 1),
  ('d0000001-0000-0000-0000-000000000007', 'b0000001-0000-0000-0000-000000000001', 'c0000001-0000-0000-0000-000000000003', 'شاي كشك', 'Koshk Tea', 15.00, TRUE, 2)
ON CONFLICT DO NOTHING;

-- Item options for Koshari (size)
INSERT INTO public.item_options (id, item_id, name_ar, name_en, is_required, max_selections, min_selections, sort_order) VALUES
  ('e0000001-0000-0000-0000-000000000001', 'd0000001-0000-0000-0000-000000000001', 'الحجم', 'Size', TRUE, 1, 1, 1),
  ('e0000001-0000-0000-0000-000000000002', 'd0000001-0000-0000-0000-000000000001', 'إضافات', 'Extras', FALSE, NULL, 0, 2)
ON CONFLICT DO NOTHING;

INSERT INTO public.item_option_choices (option_id, name_ar, name_en, price_modifier, is_default, sort_order) VALUES
  ('e0000001-0000-0000-0000-000000000001', 'صغير', 'Small', 0.00, TRUE, 1),
  ('e0000001-0000-0000-0000-000000000001', 'وسط', 'Medium', 10.00, FALSE, 2),
  ('e0000001-0000-0000-0000-000000000001', 'كبير', 'Large', 20.00, FALSE, 3),
  ('e0000001-0000-0000-0000-000000000002', 'صلصة إضافية', 'Extra Sauce', 5.00, FALSE, 1),
  ('e0000001-0000-0000-0000-000000000002', 'بصل مقرمش', 'Crispy Onions', 5.00, FALSE, 2),
  ('e0000001-0000-0000-0000-000000000002', 'دقة', 'Dakka', 3.00, FALSE, 3)
ON CONFLICT DO NOTHING;

-- Categories + Items for Burger Stars
INSERT INTO public.categories (id, merchant_id, name_ar, name_en, sort_order) VALUES
  ('c0000001-0000-0000-0000-000000000004', 'b0000001-0000-0000-0000-000000000002', 'برجر', 'Burgers', 1),
  ('c0000001-0000-0000-0000-000000000005', 'b0000001-0000-0000-0000-000000000002', 'أطباق جانبية', 'Sides', 2)
ON CONFLICT DO NOTHING;

INSERT INTO public.items (id, merchant_id, category_id, name_ar, name_en, price, is_available, sort_order) VALUES
  ('d0000001-0000-0000-0000-000000000008', 'b0000001-0000-0000-0000-000000000002', 'c0000001-0000-0000-0000-000000000004', 'كلاسيك برجر', 'Classic Burger', 75.00, TRUE, 1),
  ('d0000001-0000-0000-0000-000000000009', 'b0000001-0000-0000-0000-000000000002', 'c0000001-0000-0000-0000-000000000004', 'دبل تشيز برجر', 'Double Cheese Burger', 110.00, TRUE, 2),
  ('d0000001-0000-0000-0000-000000000010', 'b0000001-0000-0000-0000-000000000002', 'c0000001-0000-0000-0000-000000000005', 'بطاطس مقلية', 'French Fries', 30.00, TRUE, 1),
  ('d0000001-0000-0000-0000-000000000011', 'b0000001-0000-0000-0000-000000000002', 'c0000001-0000-0000-0000-000000000005', 'بصل حلقات', 'Onion Rings', 35.00, TRUE, 2)
ON CONFLICT DO NOTHING;

-- Categories + Items for Pharmacy
INSERT INTO public.categories (id, merchant_id, name_ar, name_en, sort_order) VALUES
  ('c0000001-0000-0000-0000-000000000006', 'b0000001-0000-0000-0000-000000000004', 'أدوية بدون وصفة', 'OTC Medicine', 1),
  ('c0000001-0000-0000-0000-000000000007', 'b0000001-0000-0000-0000-000000000004', 'العناية الشخصية', 'Personal Care', 2)
ON CONFLICT DO NOTHING;

INSERT INTO public.items (id, merchant_id, category_id, name_ar, name_en, price, is_available, sort_order) VALUES
  ('d0000001-0000-0000-0000-000000000012', 'b0000001-0000-0000-0000-000000000004', 'c0000001-0000-0000-0000-000000000006', 'بنادول إكسترا', 'Panadol Extra', 25.00, TRUE, 1),
  ('d0000001-0000-0000-0000-000000000013', 'b0000001-0000-0000-0000-000000000004', 'c0000001-0000-0000-0000-000000000006', 'فلاجيل', 'Flagyl', 35.00, TRUE, 2),
  ('d0000001-0000-0000-0000-000000000014', 'b0000001-0000-0000-0000-000000000004', 'c0000001-0000-0000-0000-000000000007', 'واقي شمس', 'Sunscreen SPF50', 120.00, TRUE, 1),
  ('d0000001-0000-0000-0000-000000000015', 'b0000001-0000-0000-0000-000000000004', 'c0000001-0000-0000-0000-000000000007', 'غسول وجه', 'Face Wash', 65.00, TRUE, 2)
ON CONFLICT DO NOTHING;

-- =============================================================================
-- 6. TEST ADDRESSES
-- =============================================================================

INSERT INTO public.addresses (id, user_id, label, address, lat, lng, city, area, is_default) VALUES
  ('f0000001-0000-0000-0000-000000000001', 'a0000001-0000-0000-0000-000000000001', 'home', '25 شارع التحرير، الدقي، الجيزة', 30.0384, 31.2028, 'Cairo', 'Dokki', TRUE),
  ('f0000001-0000-0000-0000-000000000002', 'a0000001-0000-0000-0000-000000000001', 'work', '5 شارع 9، المعادي', 29.9602, 31.2569, 'Cairo', 'Maadi', FALSE),
  ('f0000001-0000-0000-0000-000000000003', 'a0000001-0000-0000-0000-000000000002', 'home', '10 شارع النزهة، مدينة نصر', 30.0506, 31.3442, 'Cairo', 'Nasr City', TRUE)
ON CONFLICT DO NOTHING;

-- =============================================================================
-- 7. TEST DRIVERS (profiles + driver records)
-- =============================================================================
-- Driver profiles: role='driver' is allowed because we set
-- app.allow_driver_role_change='true' at the top of this seed.

INSERT INTO public.profiles (id, full_name, phone, role, preferred_language) VALUES
  ('a0000001-0000-0000-0000-000000000010', 'سيد أحمد', '+201011110000', 'driver', 'ar'),
  ('a0000001-0000-0000-0000-000000000011', 'Mahmoud Hassan', '+201011110001', 'driver', 'en')
ON CONFLICT (id) DO NOTHING;

-- Driver records
INSERT INTO public.drivers (id, national_id, vehicle_type, vehicle_plate, vehicle_color, vehicle_model, is_verified, is_active, is_online, verification_status, current_lat, current_lng, last_location_at, rating, rating_count, total_deliveries) VALUES
  ('a0000001-0000-0000-0000-000000000010', '29001011234567', 'motorcycle', 'س ر ق 1234', 'أسود', 'Honda Wave 125', TRUE, TRUE, TRUE, 'approved', 30.0400, 31.2100, NOW(), 4.8, 50, 150),
  ('a0000001-0000-0000-0000-000000000011', '29001017654321', 'car', 'أ ب ج 5678', 'أبيض', 'Chevrolet Lanos', TRUE, TRUE, FALSE, 'approved', NULL, NULL, NULL, 4.5, 30, 80)
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- 8. TEST PROMO CODES
-- =============================================================================

INSERT INTO public.promo_codes (id, code, discount_type, discount_value, max_discount_amount, starts_at, expires_at, is_active, max_usage, current_usage, max_usage_per_user, min_order_amount, description_ar, description_en) VALUES
  ('g0000001-0000-0000-0000-000000000001', 'WELCOME20', 'percentage', 20.00, 50.00, NOW() - INTERVAL '30 days', NOW() + INTERVAL '30 days', TRUE, 1000, 0, 1, 50.00, 'خصم 20% للعملاء الجدد', '20% off for new customers'),
  ('g0000001-0000-0000-0000-000000000002', 'FLAT15', 'flat', 15.00, 15.00, NOW() - INTERVAL '7 days', NOW() + INTERVAL '7 days', TRUE, 500, 0, 2, 30.00, 'خصم 15 جنيه', '15 EGP off'),
  ('g0000001-0000-0000-0000-000000000003', 'EXPIRED10', 'percentage', 10.00, 30.00, NOW() - INTERVAL '60 days', NOW() - INTERVAL '30 days', TRUE, 100, 0, 1, 0.00, 'كود منتهي الصلاحية', 'Expired code')
ON CONFLICT DO NOTHING;

-- =============================================================================
-- 9. TEST ORDERS (various statuses)
-- =============================================================================

INSERT INTO public.orders (id, customer_id, merchant_id, driver_id, status, delivery_address, subtotal, delivery_fee, platform_fee, discount_amount, total, payment_method, payment_status, promo_code, distance_km, estimated_delivery_minutes, idempotency_key, merchant_commission_pct) VALUES
  -- Delivered order
  ('h0000001-0000-0000-0000-000000000001',
   'a0000001-0000-0000-0000-000000000001',
   'b0000001-0000-0000-0000-000000000001',
   'a0000001-0000-0000-0000-000000000010',
   'delivered',
   '{"address": "25 شارع التحرير، الدقي", "lat": 30.0384, "lng": 31.2028, "city": "Cairo", "area": "Dokki"}',
   130.00, 25.00, 3.00, 0, 158.00, 'cash', 'paid', NULL, 2.5, 30, 'seed-order-001', 15.00),

  -- Preparing order
  ('h0000001-0000-0000-0000-000000000002',
   'a0000001-0000-0000-0000-000000000002',
   'b0000001-0000-0000-0000-000000000002',
   NULL,
   'preparing',
   '{"address": "10 شارع النزهة، مدينة نصر", "lat": 30.0506, "lng": 31.3442, "city": "Cairo", "area": "Nasr City"}',
   110.00, 25.00, 3.00, 0, 138.00, 'card', 'paid', NULL, 3.0, 25, 'seed-order-002', 15.00),

  -- Pending order
  ('h0000001-0000-0000-0000-000000000003',
   'a0000001-0000-0000-0000-000000000001',
   'b0000001-0000-0000-0000-000000000003',
   NULL,
   'pending',
   '{"address": "25 شارع التحرير، الدقي", "lat": 30.0384, "lng": 31.2028, "city": "Cairo", "area": "Dokki"}',
   85.00, 25.00, 3.00, 15.00, 98.00, 'cash', 'pending_cash', 'FLAT15', 1.8, 20, 'seed-order-003', 15.00)
ON CONFLICT DO NOTHING;

-- Order items for delivered order
INSERT INTO public.order_items (order_id, item_id, item_name_ar, item_name_en, item_price, quantity, total_price, selected_options) VALUES
  ('h0000001-0000-0000-0000-000000000001', 'd0000001-0000-0000-0000-000000000001', 'كشري', 'Koshari', 45.00, 2, 90.00, '[{"option_name_en": "Size", "choice_name_en": "Medium", "price_modifier": 10.00}]'),
  ('h0000001-0000-0000-0000-000000000001', 'd0000001-0000-0000-0000-000000000006', 'عصير برتقان طازج', 'Fresh Orange Juice', 25.00, 1, 25.00, '[]'),
  ('h0000001-0000-0000-0000-000000000001', 'd0000001-0000-0000-0000-000000000003', 'حمص بالطحينة', 'Hummus with Tahini', 35.00, 1, 35.00, '[]')
ON CONFLICT DO NOTHING;

-- Order items for preparing order
INSERT INTO public.order_items (order_id, item_id, item_name_ar, item_name_en, item_price, quantity, total_price, selected_options) VALUES
  ('h0000001-0000-0000-0000-000000000002', 'd0000001-0000-0000-0000-000000000009', 'دبل تشيز برجر', 'Double Cheese Burger', 110.00, 1, 110.00, '[]')
ON CONFLICT DO NOTHING;

-- Order items for pending order
INSERT INTO public.order_items (order_id, item_id, item_name_ar, item_name_en, item_price, quantity, total_price, selected_options) VALUES
  ('h0000001-0000-0000-0000-000000000003', 'd0000001-0000-0000-0000-000000000004', 'شيش طاووق', 'Shish Tawook', 85.00, 1, 85.00, '[]')
ON CONFLICT DO NOTHING;

-- =============================================================================
-- 10. TEST REVIEWS
-- =============================================================================

INSERT INTO public.reviews (order_id, customer_id, merchant_id, driver_id, merchant_rating, driver_rating, merchant_comment, driver_comment) VALUES
  ('h0000001-0000-0000-0000-000000000001',
   'a0000001-0000-0000-0000-000000000001',
   'b0000001-0000-0000-0000-000000000001',
   'a0000001-0000-0000-0000-000000000010',
   5, 4, 'أكل لذيذ جداً!', 'Very tasty food!', 'سائق محترم', 'Polite driver')
ON CONFLICT DO NOTHING;

-- =============================================================================
-- 11. TEST NOTIFICATIONS
-- =============================================================================

INSERT INTO public.notifications (user_id, type, title_ar, title_en, body_ar, body_en, data) VALUES
  ('a0000001-0000-0000-0000-000000000001', 'order_status', 'تم تأكيد طلبك', 'Order Confirmed',
   'طلبك رقم ORD-000001 تم تأكيد', 'Your order ORD-000001 has been confirmed',
   '{"order_id": "h0000001-0000-0000-0000-000000000001"}'),
  ('a0000001-0000-0000-0000-000000000001', 'order_delivered', 'تم التوصيل', 'Order Delivered',
   'تم توصيل طلبك رقم ORD-000001', 'Your order ORD-000001 has been delivered',
   '{"order_id": "h0000001-0000-0000-0000-000000000001"}')
ON CONFLICT DO NOTHING;

-- =============================================================================
-- 12. RESET SESSION FLAG — no more driver-role inserts after this point
-- =============================================================================
RESET app.allow_driver_role_change;

-- =============================================================================
-- 13. REFRESH MATERIALIZED VIEWS
-- =============================================================================

-- Refresh the merchant open status view so it has data immediately
REFRESH MATERIALIZED VIEW CONCURRENTLY public.merchants_with_open_status;

-- =============================================================================
-- 14. COMPUTE INITIAL KPIs
-- =============================================================================

SELECT public.compute_admin_kpis();

-- =============================================================================
-- DONE — test accounts summary (password for all: Seed@1234)
-- =============================================================================
-- Customers:
--   ahmed@example.com     (Arabic, 50 EGP wallet)
--   fatma@example.com     (English, 25 EGP wallet)
--   mohamed@example.com   (Arabic, 0 EGP wallet)
-- Drivers:
--   driver.sayed@example.com    (online, motorcycle)
--   driver.mahmoud@example.com  (offline, car)
-- =============================================================================
