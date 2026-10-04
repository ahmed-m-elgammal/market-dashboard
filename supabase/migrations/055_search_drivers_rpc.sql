-- Migration 055: search_drivers RPC
--
-- Replaces the in-memory driver search in GET /api/drivers (apps/admin/src/
-- app/api/drivers/route.ts). Previously the route paginated on the DB with
-- .range(from, to), then filtered the resulting 50-row page in JavaScript
-- by full_name/phone/vehicle_plate. This caused three problems:
--   1. Incorrect pagination metadata (count was the unfiltered DB count,
--      but data.length was the post-filter length).
--   2. Empty pages when matches were on other pages.
--   3. Inefficiency — fetching 50 rows to return 3.
--
-- This RPC does the ILIKE search server-side with correct LIMIT/OFFSET
-- pagination and returns both the page of rows AND the filtered total count
-- in a single call.
--
-- Parameters:
--   p_search      TEXT  — NULL or '' for no search filter; otherwise a
--                         substring matched against full_name, phone, or
--                         vehicle_plate (case-insensitive).
--   p_status      TEXT  — NULL or 'all' for no status filter; otherwise
--                         a verification_status value.
--   p_page        INT   — 1-indexed page number (clamped to >= 1).
--   p_page_size   INT   — page size (clamped to [1, 50]).
--
-- Returns: TABLE(...) — one row per matching driver, with the same columns
--   the route previously selected via the join. The route issues a separate
--   COUNT(*) query for the total (kept simple to avoid overloading the RPC's
--   return shape).
--
-- Security:
--   - SECURITY DEFINER so the function can read drivers + profiles without
--     the caller needing direct SELECT grants. RLS still applies.
--   - SET search_path = '' per the migration hardening convention (S16).
--   - STABLE: reads only, no side effects.

CREATE OR REPLACE FUNCTION public.search_drivers(
  p_search text,
  p_status text,
  p_page int,
  p_page_size int
)
RETURNS TABLE (
  id uuid,
  verification_status text,
  is_active boolean,
  is_online boolean,
  vehicle_type text,
  vehicle_plate text,
  vehicle_color text,
  vehicle_model text,
  rating numeric,
  total_deliveries int,
  total_earnings numeric,
  created_at timestamptz,
  profile_id uuid,
  profile_full_name text,
  profile_phone text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    d.id,
    d.verification_status::text,
    d.is_active,
    d.is_online,
    d.vehicle_type::text,
    d.vehicle_plate,
    d.vehicle_color,
    d.vehicle_model,
    d.rating,
    d.total_deliveries,
    d.total_earnings,
    d.created_at,
    p.id AS profile_id,
    p.full_name AS profile_full_name,
    p.phone AS profile_phone
  FROM public.drivers d
  LEFT JOIN public.profiles p ON p.id = d.id
  WHERE
    (p_search IS NULL OR p_search = ''
     OR p.full_name ILIKE '%' || p_search || '%'
     OR p.phone ILIKE '%' || p_search || '%'
     OR d.vehicle_plate ILIKE '%' || p_search || '%')
    AND (p_status IS NULL OR p_status = 'all'
     OR d.verification_status = p_status)
  ORDER BY d.created_at DESC
  LIMIT LEAST(GREATEST(p_page_size, 1), 50)
  OFFSET (GREATEST(p_page, 1) - 1) * LEAST(GREATEST(p_page_size, 1), 50);
$$;

-- Companion function: returns the filtered total count for pagination
-- metadata. Kept separate so the search_drivers return shape stays a clean
-- table of driver rows.
CREATE OR REPLACE FUNCTION public.count_drivers(
  p_search text,
  p_status text
)
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT COUNT(*)
  FROM public.drivers d
  LEFT JOIN public.profiles p ON p.id = d.id
  WHERE
    (p_search IS NULL OR p_search = ''
     OR p.full_name ILIKE '%' || p_search || '%'
     OR p.phone ILIKE '%' || p_search || '%'
     OR d.vehicle_plate ILIKE '%' || p_search || '%')
    AND (p_status IS NULL OR p_status = 'all'
     OR d.verification_status = p_status);
$$;

GRANT EXECUTE ON FUNCTION public.search_drivers(text, text, int, int)
  TO service_role, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.count_drivers(text, text)
  TO service_role, authenticated, anon;
