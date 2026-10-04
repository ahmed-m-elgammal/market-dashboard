-- =============================================================================
-- LOCAL TEST BOOTSTRAP
-- Stubs for the Supabase-managed objects a vanilla PostgreSQL 18 install does
-- not provide. Applied to the throwaway `marketak_test` database BEFORE the
-- real migrations, so `supabase db reset` behaviour can be reproduced locally.
--
-- NOTHING HERE IS DEPLOYED. This file is test scaffolding only. On Supabase
-- these objects already exist and this file is never run.
--
-- Supplied:
--   auth schema    -- auth.users table + auth.uid() / auth.jwt() / auth.role()
--   storage schema -- storage.buckets / storage.objects (migration 025 only)
--   postgis shims  -- ST_MakePoint / ST_Distance / geography (driver + feed
--                     distance maths only; NOT used by the catalog)
--   pg_cron shims  -- cron.schedule as a no-op recorder
--   vault shim     -- vault.create_secret / read / list as a settings table
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. auth
-- -----------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS auth;

CREATE TABLE IF NOT EXISTS auth.users (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email              text UNIQUE,
  raw_user_meta_data jsonb DEFAULT '{}'::jsonb,
  created_at         timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS auth.identities (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  provider_id   text,
  provider      text
);

-- auth.uid(): reads the JWT claims Supabase injects. Locally, tests set these
-- with  SELECT set_config('request.jwt.claims', '{"sub":"<uuid>","role":"authenticated"}', true)
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claim.sub', true), ''),
    (NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;

CREATE OR REPLACE FUNCTION auth.role() RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claim.role', true), ''),
    (NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
    'anon'
  )
$$;

CREATE OR REPLACE FUNCTION auth.jwt() RETURNS jsonb
LANGUAGE sql STABLE AS $$
  SELECT COALESCE(NULLIF(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb)
$$;

CREATE OR REPLACE FUNCTION auth.email() RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT auth.jwt() ->> 'email'
$$;

-- -----------------------------------------------------------------------------
-- 2. storage (migration 025 only)
-- -----------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS storage;

CREATE TABLE IF NOT EXISTS storage.buckets (
  id                 text PRIMARY KEY,
  name               text NOT NULL,
  public             boolean NOT NULL DEFAULT false,
  file_size_limit    bigint,
  allowed_mime_types text[],
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS storage.objects (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bucket_id  text REFERENCES storage.buckets(id),
  name       text,
  owner      uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- storage.foldername(): returns text[] of the folder segments in an object
-- path. Migration 025 subscripts it -- `(storage.foldername(name))[1]` -- to
-- scope policies to the first path segment, so the return type must be an
-- array, not text.
CREATE OR REPLACE FUNCTION storage.foldername(p_name text)
RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN p_name IS NULL OR position('/' IN p_name) = 0 THEN ARRAY[]::text[]
    ELSE (string_to_array(p_name, '/'))[1:array_length(string_to_array(p_name, '/'), 1) - 1]
  END
$$;

-- -----------------------------------------------------------------------------
-- 3. postgis shims
-- Real PostGIS is unavailable locally. Only distance maths on lat/lng is used,
-- and only by driver-location and get_merchant-feed. Haversine is accurate
-- enough to test behaviour; it is NOT a substitute for PostGIS in production.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ST_MakePoint(lng double precision, lat double precision)
RETURNS point LANGUAGE sql IMMUTABLE AS $$ SELECT point(lng, lat) $$;

CREATE OR REPLACE FUNCTION public.ST_Distance(a point, b point)
RETURNS double precision LANGUAGE sql IMMUTABLE AS $$
  SELECT 2 * 6371000 * asin(LEAST(1.0, sqrt(
    power(sin(radians(a[1] - b[1]) / 2), 2)
    + cos(radians(a[2])) * cos(radians(b[2]))
    * power(sin(radians(a[2] - b[2]) / 2), 2)
  )))
$$;

-- `geography` is a type in PostGIS. PostGIS also casts point -> geography
-- implicitly in several places, so provide the cast target as a domain.
-- CREATE DOMAIN has no IF NOT EXISTS, hence the existence guard.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE t.typname = 'geography' AND n.nspname = 'public'
  ) THEN
    CREATE DOMAIN public.geography AS point;
  END IF;
END
$$;

-- -----------------------------------------------------------------------------
-- 4. pg_cron shim -- records the schedule, never fires.
-- -----------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS cron;

-- Column names mirror pg_cron's own catalog: migrations 089 and 095 look up
-- `cron.job.jobname` and call cron.unschedule(name).
CREATE TABLE IF NOT EXISTS cron.job (
  jobid    bigserial PRIMARY KEY,
  jobname  text,
  schedule text,
  command  text,
  database text,
  username text,
  active   boolean NOT NULL DEFAULT true
);

CREATE OR REPLACE FUNCTION cron.schedule(p_name text, p_schedule text, p_command text)
RETURNS bigint LANGUAGE sql AS $$
  INSERT INTO cron.job (jobname, schedule, command) VALUES (p_name, p_schedule, p_command)
  RETURNING jobid
$$;

CREATE OR REPLACE FUNCTION cron.schedule(p_schedule text, p_command text)
RETURNS bigint LANGUAGE sql AS $$
  INSERT INTO cron.job (jobname, schedule, command) VALUES (NULL, p_schedule, p_command)
  RETURNING jobid
$$;

CREATE OR REPLACE FUNCTION cron.unschedule(p_jobid bigint)
RETURNS boolean LANGUAGE sql AS $$ SELECT true $$;

CREATE OR REPLACE FUNCTION cron.unschedule(p_name text)
RETURNS boolean LANGUAGE sql AS $$
  DELETE FROM cron.job WHERE jobname = p_name RETURNING true
$$;

-- -----------------------------------------------------------------------------
-- 5. vault shim -- plain settings table, same call surface.
-- -----------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS vault;

CREATE TABLE IF NOT EXISTS vault.secrets (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name       text UNIQUE NOT NULL,
  secret     text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION vault.create_secret(p_name text, p_secret text)
RETURNS void LANGUAGE sql AS $$
  INSERT INTO vault.secrets (name, secret) VALUES (p_name, p_secret)
  ON CONFLICT (name) DO UPDATE SET secret = EXCLUDED.secret
$$;

CREATE OR REPLACE FUNCTION vault.read_secret(p_name text)
RETURNS text LANGUAGE sql AS $$ SELECT secret FROM vault.secrets WHERE name = p_name $$;

CREATE OR REPLACE FUNCTION vault.list_secrets()
RETURNS TABLE(name text, description text, secret text)
LANGUAGE sql AS $$ SELECT name, ''::text, secret FROM vault.secrets $$;

-- pgmq shim (Supabase queues) -- migration 034/094 era helpers.
CREATE SCHEMA IF NOT EXISTS pgmq;

-- -----------------------------------------------------------------------------
-- 6. Supabase roles
-- Migrations GRANT/REVOKE to anon, authenticated and service_role. Vanilla
-- PostgreSQL has none of them, and `GRANT ... TO anon` is a hard error, so the
-- first GRANT aborts its whole migration. Create them as NOLOGIN roles.
-- -----------------------------------------------------------------------------
DO $$
DECLARE r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
      EXECUTE format('CREATE ROLE %I NOLOGIN NOINHERIT', r);
    END IF;
  END LOOP;
END
$$;

-- -----------------------------------------------------------------------------
-- 7. Realtime publication
-- Several migrations do ALTER PUBLICATION supabase_realtime ADD TABLE ...
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;
  END IF;
END
$$;