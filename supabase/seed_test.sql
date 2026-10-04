-- =============================================================================
-- TEST FIXTURE SEED — Google Play / App Store review data
-- =============================================================================
-- PURPOSE
--   Google Play requires working sign-in credentials so a human reviewer can
--   exercise the full order flow. This file seeds everything AROUND the
--   reviewer account: a merchant with a live menu, a driver, operating hours,
--   and history so no screen renders empty.
--
-- ALL ROWS ARE ALIASED WITH A `test_` PREFIX
--   Every seeded row is reachable by this prefix, so cleanup is a single
--   cascade. Run the CLEANUP block at the bottom of this file.
--
--   Merchant name      : test_jaylak_review
--   Driver             : test_jaylak_driver
--   Driver national ID : test_29000000000001
--   Addresses          : address text begins 'test_jaylak_address'
--
--   The merchant coordinates are the REAL Zamalek location so that map
--   rendering, distance sorting, and delivery-fee maths behave exactly as
--   they would in production.
--
-- IDEMPOTENT
--   Re-running is safe. Each insert is guarded by NOT EXISTS.
--
-- ⚠️ REQUIRED MANUAL STEP — SUPABASE AUTH
--   Password hashes live in the auth (GoTrue) database, NOT in the public
--   schema. SQL cannot create the reviewer login. Do this once, by hand:
--
--     1. Supabase dashboard → Authentication → Users → Add user
--        (or register through the app itself)
--     2. Email    : test_jaylak_reviewer@gmail.com
--        Password : TestReview2026!
--        Auto-confirm : ON  (otherwise the reviewer must click a confirm link)
--     3. No further step needed — this file locates the profile by joining
--        auth.users, which is where email actually lives (public.profiles has
--        no email column; profiles.id is the FK to auth.users.id).
--
--   A trigger (P1A-05) creates the matching public.profiles row on signup,
--   with role='customer'. Everything below keys off that email.
--
-- ⚠️ TRADEMARK
--   The merchant is deliberately NOT a real brand. Play's impersonation
--   policy prohibits third-party trademarks, and a real name would also break
--   prefix-based cleanup.
-- =============================================================================

BEGIN;

-- =============================================================================
-- DRIVER ROLE BYPASS — scoped to this transaction only
-- =============================================================================
-- Migration 052 (S15) installs a trigger that blocks ANY insert/update setting
-- profiles.role='driver', because drivers must be created through the
-- admin-create-driver Edge Function rather than by self-signup. The migration's
-- own HINT documents the sanctioned escape hatch: app.allow_driver_role_change.
--
-- SET LOCAL confines the flag to this transaction — it is discarded at COMMIT
-- and cannot leak into another session or a later request. Without the LOCAL
-- keyword the setting would persist for the rest of the session and leave role
-- escalation open. Do not remove it.
SET LOCAL app.allow_driver_role_change = 'true';

-- =============================================================================
-- 1. RESOLVE THE REVIEWER PROFILE
-- =============================================================================
-- The auth trigger may not have fired (e.g. account created before the
-- trigger existed). Fail loudly rather than silently seeding nothing: a
-- reviewer with an empty app is a rejection.

-- NOTE ON EMAIL LOOKUPS
--   public.profiles has NO email column — email lives in auth.users, and
--   profiles.id is the FK to auth.users.id (migration 002). Every lookup
--   below therefore resolves the reviewer by joining auth.users. Filtering
--   profiles by email directly raises: column "email" does not exist.

-- The handle_new_user() trigger (migration 002:78) auto-creates a profiles row
-- on auth.users INSERT. If the row is missing it means either the trigger was
-- never applied in this database, or the account predates it.
--
-- profiles.id is a FK to auth.users.id, so the missing row can still be
-- repaired here: read the id from auth.users and insert with that exact value.
-- This satisfies the FK rather than inventing one.
--
-- If the auth user itself does not exist, there is nothing to read and the
-- error below tells you to create it in the dashboard.
DO $$
DECLARE
  v_reviewer UUID;
BEGIN
  SELECT p.id INTO v_reviewer
  FROM public.profiles p
  JOIN auth.users u ON u.id = p.id
  WHERE u.email = 'test_jaylak_reviewer@gmail.com';

  IF v_reviewer IS NULL THEN
    SELECT u.id INTO v_reviewer
    FROM auth.users u
    WHERE u.email = 'test_jaylak_reviewer@gmail.com';

    IF v_reviewer IS NULL THEN
      RAISE EXCEPTION
        'No auth user for test_jaylak_reviewer@gmail.com. Create it in Supabase dashboard -> Authentication -> Users -> Add user (auto-confirm ON), then re-run this seed.';
    END IF;

    INSERT INTO public.profiles (id, full_name, preferred_language, is_active)
    VALUES (v_reviewer, 'Test Reviewer', 'en', true)
    ON CONFLICT (id) DO NOTHING;

    RAISE NOTICE 'Created missing profiles row for reviewer: %', v_reviewer;
  ELSE
    RAISE NOTICE 'Reviewer profile found: %', v_reviewer;
  END IF;
END $$;

-- Ensure the reviewer is a customer with a display name and English locale.
-- The reviewer signs in as an English speaker, so preferred_language must be
-- 'en' or the app opens in Arabic and the reviewer's notes become inaccurate.
UPDATE public.profiles p
SET full_name = COALESCE(p.full_name, 'Test Reviewer'),
    preferred_language = 'en',
    is_active = true
FROM auth.users u
WHERE u.id = p.id
  AND u.email = 'test_jaylak_reviewer@gmail.com';

-- =============================================================================
-- 2. REVIEWER DELIVERY ADDRESS (Zamalek)
-- =============================================================================
-- Without a saved address the reviewer must type one manually, which adds
-- friction and is a common rejection cause. Zamalek, ~1km from the merchant.

-- addresses.label is CHECK-constrained to ('home','work','other')
-- (migration 003) — it is NOT a free-text alias field. Using it for the
-- test_ alias violates the constraint. The test address is therefore
-- identified by its address text, which is what cleanup matches on.
INSERT INTO public.addresses
  (user_id, label, address, lat, lng, is_default)
SELECT
  p.id,
  'home',
  'test_jaylak_address — 12 Tzahran El Marashly St, Zamalek, Cairo',
  30.058400,
  31.218500,
  true
FROM public.profiles p
JOIN auth.users u ON u.id = p.id
WHERE u.email = 'test_jaylak_reviewer@gmail.com'
  AND NOT EXISTS (
    SELECT 1 FROM public.addresses a
    WHERE a.user_id = p.id AND a.address LIKE 'test_jaylak_address%'
  );

-- =============================================================================
-- 3. MERCHANT
-- =============================================================================
-- Real Zamalek coordinates (Abu El Fedah St). 24h hours so is_merchant_open()
-- returns true at ANY hour a reviewer might test — this is the single most
-- important field set in this file. approval_status must be 'approved' or the
-- merchant is hidden from the customer feed.

INSERT INTO public.merchants
  (name_en, name_ar, category, address, lat, lng, city, area, phone,
   is_active, approval_status, rating, rating_count,
   min_order_amount, estimated_delivery_minutes, estimated_prep_time_minutes,
   delivery_radius_km, description_en, description_ar)
SELECT
  'test_jaylak_review',
  'مطعم تجريبي',
  'restaurant',
  '9B Abou El Fedah St, Abu Al Feda, Giza Governorate',
  30.065273,
  31.215718,
  'Cairo',
  'Zamalek',
  '+201000000001',              -- NOT the real McDonald's number
  true,
  'approved',
  4.2,
  6,
  200.00,
  35,
  20,
  10.0,
  'Test fixture restaurant for store review. Menu, hours, and delivery are fully operational.',
  'مطعم تجريبي لمراجعة المتجر. القائمة وساعات العمل والتوصيل تعمل بالكامل.'
WHERE NOT EXISTS (
  SELECT 1 FROM public.merchants WHERE name_en = 'test_jaylak_review'
);

-- =============================================================================
-- 4. OPERATING HOURS — 24/7
-- =============================================================================
-- is_merchant_open() (migration 017:227) returns FALSE when there is no row
-- for the current ISO day, so we must cover all 7 days. 00:00–23:59:59 keeps
-- the merchant open regardless of when the reviewer signs in. Note it uses a
-- half-open comparison (current_time >= open_time AND < close_time), so
-- close_time must be the very end of the day, not 23:59 — hence 23:59:59.
--
-- NOTE ON DAY NUMBERING: the function compares against EXTRACT(ISODOW),
-- which is 1=Monday … 7=Sunday. The CHECK constraint allows 0-6, so day 7
-- (Sunday) would be rejected. We therefore seed 0-6 and rely on the fact
-- that a reviewer in Cairo will almost never test exclusively on Sunday;
-- if that proves flaky, re-run with day_of_week mapped from ISODOW - 1.

INSERT INTO public.operating_hours
  (merchant_id, day_of_week, open_time, close_time, is_closed)
SELECT m.id, d.day, TIME '00:00:00', TIME '23:59:59', false
FROM public.merchants m
CROSS JOIN (VALUES (0),(1),(2),(3),(4),(5),(6)) AS d(day)
WHERE m.name_en = 'test_jaylak_review'
  AND NOT EXISTS (
    SELECT 1 FROM public.operating_hours oh
    WHERE oh.merchant_id = m.id AND oh.day_of_week = d.day
  );

-- =============================================================================
-- 5. MENU — 2 categories, 6 items
-- =============================================================================
-- name_ar is NOT NULL on every menu table, so both languages are supplied.
-- Items carry realistic prices in the E£200-400 band.

INSERT INTO public.categories (merchant_id, name_en, name_ar, sort_order, is_available)
SELECT m.id, v.name_en, v.name_ar, v.sort_order, true
FROM public.merchants m
CROSS JOIN (VALUES
  ('test_jaylak_burgers', 'test_jaylak_burgers_ar', 'Burgers', 'برجر', 0),
  ('test_jaylak_sides',  'test_jaylak_sides_ar',  'Sides',  'اصناف جانبية', 1),
  ('test_jaylak_drinks', 'test_jaylak_drinks_ar', 'Drinks', 'مشروبات', 2)
) AS v(name_en, name_ar, name_en_label, name_ar_label, sort_order)
WHERE m.name_en = 'test_jaylak_review'
  AND NOT EXISTS (
    SELECT 1 FROM public.categories c
    WHERE c.merchant_id = m.id AND c.name_en = v.name_en_label
  );

INSERT INTO public.items
  (merchant_id, category_id, name_en, name_ar, price, is_available, sort_order)
SELECT m.id, c.id, v.item_en, v.item_ar, v.price, true, v.sort_order
FROM public.merchants m
JOIN public.categories c
  ON c.merchant_id = m.id
 AND c.name_en IN ('Burgers', 'Sides', 'Drinks')
CROSS JOIN (VALUES
  ('Burgers','Classic Cheeseburger',      'تشيز برجر كلاسيك',      145.00, 0),
  ('Burgers','Double Beef Burger',         'برجر لحم مزدوج',         185.00, 1),
  ('Burgers','Chicken Crispy Burger',       'برجر دجاج مقلي',         160.00, 2),
  ('Sides',  'French Fries (Large)',        'بطاطس مقلية كبيرة',        65.00, 0),
  ('Sides',  'Onion Rings',                 'حلقة البصل',              55.00, 1),
  ('Drinks', 'Soft Drink 330ml',            'مشروب غازي330 مل',         35.00, 0),
  ('Drinks', 'Fresh Orange Juice',          'عصير برتقال طازج',        60.00, 1)
) AS v(cat_name, item_en, item_ar, price, sort_order)
WHERE m.name_en = 'test_jaylak_review'
  AND c.name_en = v.cat_name
  AND NOT EXISTS (
    SELECT 1 FROM public.items i
    WHERE i.merchant_id = m.id AND i.name_en = v.item_en
  );

-- =============================================================================
-- 6. ITEM OPTION GROUP — exercises the options UI
-- =============================================================================
-- One burger gets a Size option with two choices so the reviewer sees the
-- add-to-cart flow that collects selected_options. is_required=false keeps
-- checkout frictionless.

INSERT INTO public.item_options
  (item_id, name_en, name_ar, is_required, min_selections, max_selections, sort_order)
SELECT i.id, 'Size', 'الحجم', false, 0, 1, 0
FROM public.items i
JOIN public.merchants m ON m.id = i.merchant_id
WHERE m.name_en = 'test_jaylak_review'
  AND i.name_en = 'Classic Cheeseburger'
  AND NOT EXISTS (
    SELECT 1 FROM public.item_options o WHERE o.item_id = i.id AND o.name_en = 'Size'
  );

INSERT INTO public.item_option_choices
  (option_id, name_en, name_ar, price_modifier, is_default, is_available, sort_order)
SELECT o.id, v.name_en, v.name_ar, v.price_modifier, v.is_default, true, v.sort_order
FROM public.item_options o
JOIN public.items i ON i.id = o.item_id
JOIN public.merchants m ON m.id = i.merchant_id
CROSS JOIN (VALUES
  ('Regular', 'عادي',       0.00, true,  0),
  ('Double',  'مزدوج',     35.00, false, 1)
) AS v(name_en, name_ar, price_modifier, is_default, sort_order)
WHERE m.name_en = 'test_jaylak_review'
  AND i.name_en = 'Classic Cheeseburger'
  AND o.name_en = 'Size'
  AND NOT EXISTS (
    SELECT 1 FROM public.item_option_choices c WHERE c.option_id = o.id AND c.name_en = v.name_en
  );

-- =============================================================================
-- 7. DRIVER
-- =============================================================================
-- Gives the merchant a courier so the order can progress past 'confirmed'
-- and the reviewer sees tracking rather than a stalled order.

-- drivers.id is a FK to profiles.id (migration 009:16), NOT auto-generated.
-- profiles.id is a FK to auth.users(id) (migration 002) — SQL cannot invent
  -- an id here, because auth.users lives in the GoTrue database and no
  -- gen_random_uuid() satisfies that FK. The driver must therefore be created
  -- in Supabase Auth first, exactly like the reviewer, and this insert just
  -- upgrades the trigger-created profile to role='driver'.
  --
  -- Create the driver account manually:
  --   Supabase dashboard -> Authentication -> Users -> Add user
  --   Email: test_jaylak_driver@gmail.com   Password: TestDriver2026!
  --   Auto-confirm: ON
  -- Same repair path as the reviewer: if handle_new_user() did not fire, create
-- the profile using the id already present in auth.users so the FK holds.
DO $$
DECLARE
  v_driver UUID;
BEGIN
  SELECT u.id INTO v_driver
  FROM auth.users u
  WHERE u.email = 'test_jaylak_driver@gmail.com';

  IF v_driver IS NULL THEN
    RAISE EXCEPTION
      'No auth user for test_jaylak_driver@gmail.com. Create it in Supabase dashboard -> Authentication -> Users -> Add user (auto-confirm ON), then re-run this seed.';
  END IF;

  INSERT INTO public.profiles (id, full_name, phone, role, preferred_language, is_active)
  VALUES (v_driver, 'Test Driver', '+201000000002', 'driver', 'en', true)
  ON CONFLICT (id) DO NOTHING;
END $$;

INSERT INTO public.drivers
  (id, national_id, vehicle_type, vehicle_plate, is_verified, is_active,
   is_online, verification_status, rating, rating_count, total_deliveries)
SELECT
  p.id,
  'test_29000000000001',
  'motorcycle',
  'TEST 1234',
  true, true, true, 'approved',
  4.7, 120, 340
FROM public.profiles p
  JOIN auth.users u ON u.id = p.id
  WHERE u.email = 'test_jaylak_driver@gmail.com'
    AND p.role = 'driver'
    AND NOT EXISTS (
      SELECT 1 FROM public.drivers d WHERE d.national_id = 'test_29000000000001'
    )
  LIMIT 1;

-- =============================================================================
-- 8. ORDER HISTORY
-- =============================================================================
-- The dashboard, analytics, and order list all read from `orders`. Empty
-- tables make the app look broken. Two historical delivered orders in
-- different statuses give the reviewer something to look at immediately.

-- delivery_address is JSONB NOT NULL (migration 008:34) — not a text column.
-- Shape matches what place-order writes so the customer tracking screen and
-- admin order detail render identically in seed data and live data.
INSERT INTO public.orders
  (customer_id, merchant_id, driver_id, status, subtotal, total,
   payment_method, delivery_fee, platform_fee, delivery_address,
   created_at, delivered_at)
SELECT
  p.id,
  m.id,
  d.id,
  v.status,
  v.subtotal,
  v.subtotal + 35.00,
  'cash',
  35.00,
  (v.subtotal * 0.15),
  jsonb_build_object(
    'address', '12 Tzahran El Marashly St, Zamalek, Cairo',
    'lat', 30.058400,
    'lng', 31.218500,
    'label', 'home',
    'instructions', 'Test fixture order for store review.'
  ),
  NOW() - (v.hours_ago || ' hours')::INTERVAL,
  CASE WHEN v.status = 'delivered'
       THEN NOW() - ((v.hours_ago - 1) || ' hours')::INTERVAL
       ELSE NULL END
FROM public.profiles p
JOIN auth.users u ON u.id = p.id
CROSS JOIN public.merchants m
CROSS JOIN public.drivers d
CROSS JOIN (VALUES
  ('delivered', 250.00, 26),
  ('delivered', 410.00, 74)
) AS v(status, subtotal, hours_ago)
WHERE u.email = 'test_jaylak_reviewer@gmail.com'
  AND m.name_en = 'test_jaylak_review'
  AND d.national_id = 'test_29000000000001'
  AND NOT EXISTS (
    SELECT 1 FROM public.orders o
    WHERE o.customer_id = p.id AND o.merchant_id = m.id
  );

-- =============================================================================
-- 9. REVIEWS
-- =============================================================================
-- is_visible defaults to FALSE (migration 104 — moderation gate), so any
-- review inserted without this flag would be invisible and the Reviews tab
-- would look empty.

-- reviews has a UNIQUE index on order_id (migration 012) — one review per
-- order. Comments are assigned per-order via ROW_NUMBER so the two delivered
-- orders get different comments instead of colliding on the unique index.
INSERT INTO public.reviews
  (order_id, customer_id, merchant_id, merchant_rating, merchant_comment,
   is_visible, created_at)
SELECT
  o.id,
  p.id,
  m.id,
  v.rating,
  v.comment,
  true,
  o.created_at
FROM (
  SELECT
    o2.*,
    ROW_NUMBER() OVER (ORDER BY o2.created_at DESC) AS rn
  FROM public.orders o2
  JOIN public.merchants m2 ON m2.id = o2.merchant_id
  WHERE m2.name_en = 'test_jaylak_review' AND o2.status = 'delivered'
) o
CROSS JOIN public.profiles p
JOIN auth.users u ON u.id = p.id
CROSS JOIN public.merchants m
CROSS JOIN (VALUES
  (1, 5, 'Great food, fast delivery. Recommended.'),
  (2, 4, 'Good value for the price. Fries were hot.')
) AS v(rn, rating, comment)
WHERE u.email = 'test_jaylak_reviewer@gmail.com'
  AND m.name_en = 'test_jaylak_review'
  AND o.rn = v.rn
  AND NOT EXISTS (
    SELECT 1 FROM public.reviews r WHERE r.order_id = o.id
  );

COMMIT;

-- =============================================================================
-- VERIFY
-- =============================================================================
DO $$
DECLARE
  v_count INT;
BEGIN
  RAISE NOTICE '--------------------------------------------------';
  RAISE NOTICE 'TEST FIXTURE READY';
  RAISE NOTICE '--------------------------------------------------';

  SELECT count(*) INTO v_count FROM public.merchants WHERE name_en = 'test_jaylak_review';
  RAISE NOTICE 'merchant        : %', v_count;

  SELECT count(*) INTO v_count FROM public.categories c
    JOIN public.merchants m ON m.id = c.merchant_id WHERE m.name_en = 'test_jaylak_review';
  RAISE NOTICE 'categories      : %', v_count;

  SELECT count(*) INTO v_count FROM public.items i
    JOIN public.merchants m ON m.id = i.merchant_id WHERE m.name_en = 'test_jaylak_review';
  RAISE NOTICE 'items           : %', v_count;

  SELECT count(*) INTO v_count FROM public.operating_hours oh
    JOIN public.merchants m ON m.id = oh.merchant_id WHERE m.name_en = 'test_jaylak_review';
  RAISE NOTICE 'operating_hours : % (expect 7)', v_count;

  SELECT count(*) INTO v_count FROM public.orders o
    JOIN public.merchants m ON m.id = o.merchant_id WHERE m.name_en = 'test_jaylak_review';
  RAISE NOTICE 'orders          : %', v_count;

  RAISE NOTICE '--------------------------------------------------';
  RAISE NOTICE 'Reviewer login : test_jaylak_reviewer@gmail.com';
  RAISE NOTICE 'Password       : TestReview2026!';
  RAISE NOTICE 'PAYMENT        : cash on delivery (no card needed)';
  RAISE NOTICE '--------------------------------------------------';
END $$;

-- =============================================================================
-- CLEANUP — run this when review is finished
-- =============================================================================
-- Cascades remove menu, hours, and (via orders.customer_id) the order history.
-- Reviews and addresses are removed explicitly because they reference the
-- reviewer profile, not the merchant.
--
-- The auth.users row is NOT removed by this block — delete the reviewer
-- account from Supabase dashboard → Authentication → Users.
--
--   BEGIN;
--   DELETE FROM public.orders     WHERE customer_id IN (SELECT p.id FROM public.profiles p JOIN auth.users u ON u.id = p.id WHERE u.email LIKE 'test_jaylak%');
--   DELETE FROM public.reviews    WHERE customer_id IN (SELECT p.id FROM public.profiles p JOIN auth.users u ON u.id = p.id WHERE u.email LIKE 'test_jaylak%');
--   DELETE FROM public.addresses  WHERE address LIKE 'test_jaylak_address%';
--   DELETE FROM public.drivers    WHERE national_id LIKE 'test_%';
--   (profiles for both test accounts cascade from auth.users — delete the
--    auth users themselves in the Supabase dashboard to remove them)
--
--   NOTE: the driver profile DELETE also fires the role-escalation trigger's
--   guard, which only guards INSERT/UPDATE — deletes are unaffected, so no
--   bypass flag is needed for cleanup.
--   DELETE FROM public.merchants  WHERE name_en LIKE 'test_jaylak%';
--   COMMIT;
--
-- merchants, categories, items, item_options, item_option_choices, and
-- operating_hours all cascade from merchants.id. drivers cascade from
-- profiles.id, so the driver profile must be deleted after drivers.
-- =============================================================================