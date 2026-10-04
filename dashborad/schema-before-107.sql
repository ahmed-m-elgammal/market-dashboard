--
-- PostgreSQL database dump
--

\restrict kGbA4KLccIsatfnwC5VFMps2oq8UKw9W1PrCtlBbdfaxRiIOJGYzkZxlaHVn48V

-- Dumped from database version 17.6
-- Dumped by pg_dump version 18.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: auth; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA auth;


--
-- Name: pg_cron; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION pg_cron; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_cron IS 'Job scheduler for PostgreSQL';


--
-- Name: extensions; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA extensions;


--
-- Name: graphql; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA graphql;


--
-- Name: graphql_public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA graphql_public;


--
-- Name: pg_net; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA public;


--
-- Name: EXTENSION pg_net; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_net IS 'Async HTTP';


--
-- Name: pgbouncer; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA pgbouncer;


--
-- Name: pgmq; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA pgmq;


--
-- Name: realtime; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA realtime;


--
-- Name: storage; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA storage;


--
-- Name: supabase_migrations; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA supabase_migrations;


--
-- Name: vault; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA vault;


--
-- Name: pg_stat_statements; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA extensions;


--
-- Name: EXTENSION pg_stat_statements; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_stat_statements IS 'track planning and execution statistics of all SQL statements executed';


--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: pgmq; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgmq WITH SCHEMA pgmq;


--
-- Name: EXTENSION pgmq; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgmq IS 'A lightweight message queue. Like AWS SQS and RSMQ but on Postgres.';


--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry and geography spatial types and functions';


--
-- Name: supabase_vault; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS supabase_vault WITH SCHEMA vault;


--
-- Name: EXTENSION supabase_vault; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION supabase_vault IS 'Supabase Vault Extension';


--
-- Name: unaccent; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA public;


--
-- Name: EXTENSION unaccent; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION unaccent IS 'text search dictionary that removes accents';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: aal_level; Type: TYPE; Schema: auth; Owner: -
--

CREATE TYPE auth.aal_level AS ENUM (
    'aal1',
    'aal2',
    'aal3'
);


--
-- Name: code_challenge_method; Type: TYPE; Schema: auth; Owner: -
--

CREATE TYPE auth.code_challenge_method AS ENUM (
    's256',
    'plain'
);


--
-- Name: factor_status; Type: TYPE; Schema: auth; Owner: -
--

CREATE TYPE auth.factor_status AS ENUM (
    'unverified',
    'verified'
);


--
-- Name: factor_type; Type: TYPE; Schema: auth; Owner: -
--

CREATE TYPE auth.factor_type AS ENUM (
    'totp',
    'webauthn',
    'phone',
    'recovery_code'
);


--
-- Name: oauth_authorization_status; Type: TYPE; Schema: auth; Owner: -
--

CREATE TYPE auth.oauth_authorization_status AS ENUM (
    'pending',
    'approved',
    'denied',
    'expired'
);


--
-- Name: oauth_client_type; Type: TYPE; Schema: auth; Owner: -
--

CREATE TYPE auth.oauth_client_type AS ENUM (
    'public',
    'confidential'
);


--
-- Name: oauth_registration_type; Type: TYPE; Schema: auth; Owner: -
--

CREATE TYPE auth.oauth_registration_type AS ENUM (
    'dynamic',
    'manual'
);


--
-- Name: oauth_response_type; Type: TYPE; Schema: auth; Owner: -
--

CREATE TYPE auth.oauth_response_type AS ENUM (
    'code'
);


--
-- Name: one_time_token_type; Type: TYPE; Schema: auth; Owner: -
--

CREATE TYPE auth.one_time_token_type AS ENUM (
    'confirmation_token',
    'reauthentication_token',
    'recovery_token',
    'email_change_token_new',
    'email_change_token_current',
    'phone_change_token'
);


--
-- Name: action; Type: TYPE; Schema: realtime; Owner: -
--

CREATE TYPE realtime.action AS ENUM (
    'INSERT',
    'UPDATE',
    'DELETE',
    'TRUNCATE',
    'ERROR'
);


--
-- Name: equality_op; Type: TYPE; Schema: realtime; Owner: -
--

CREATE TYPE realtime.equality_op AS ENUM (
    'eq',
    'neq',
    'lt',
    'lte',
    'gt',
    'gte',
    'in',
    'like',
    'ilike',
    'is',
    'match',
    'imatch',
    'isdistinct'
);


--
-- Name: user_defined_filter; Type: TYPE; Schema: realtime; Owner: -
--

CREATE TYPE realtime.user_defined_filter AS (
	column_name text,
	op realtime.equality_op,
	value text,
	negate boolean
);


--
-- Name: wal_column; Type: TYPE; Schema: realtime; Owner: -
--

CREATE TYPE realtime.wal_column AS (
	name text,
	type_name text,
	type_oid oid,
	value jsonb,
	is_pkey boolean,
	is_selectable boolean
);


--
-- Name: wal_rls; Type: TYPE; Schema: realtime; Owner: -
--

CREATE TYPE realtime.wal_rls AS (
	wal jsonb,
	is_rls_enabled boolean,
	subscription_ids uuid[],
	errors text[]
);


--
-- Name: buckettype; Type: TYPE; Schema: storage; Owner: -
--

CREATE TYPE storage.buckettype AS ENUM (
    'STANDARD',
    'ANALYTICS',
    'VECTOR'
);


--
-- Name: email(); Type: FUNCTION; Schema: auth; Owner: -
--

CREATE FUNCTION auth.email() RETURNS text
    LANGUAGE sql STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.email', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email')
  )::text
$$;


--
-- Name: FUNCTION email(); Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON FUNCTION auth.email() IS 'Deprecated. Use auth.jwt() -> ''email'' instead.';


--
-- Name: jwt(); Type: FUNCTION; Schema: auth; Owner: -
--

CREATE FUNCTION auth.jwt() RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
  select 
    coalesce(
        nullif(current_setting('request.jwt.claim', true), ''),
        nullif(current_setting('request.jwt.claims', true), '')
    )::jsonb
$$;


--
-- Name: role(); Type: FUNCTION; Schema: auth; Owner: -
--

CREATE FUNCTION auth.role() RETURNS text
    LANGUAGE sql STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )::text
$$;


--
-- Name: FUNCTION role(); Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON FUNCTION auth.role() IS 'Deprecated. Use auth.jwt() -> ''role'' instead.';


--
-- Name: uid(); Type: FUNCTION; Schema: auth; Owner: -
--

CREATE FUNCTION auth.uid() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;


--
-- Name: FUNCTION uid(); Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON FUNCTION auth.uid() IS 'Deprecated. Use auth.jwt() -> ''sub'' instead.';


--
-- Name: grant_pg_cron_access(); Type: FUNCTION; Schema: extensions; Owner: -
--

CREATE FUNCTION extensions.grant_pg_cron_access() RETURNS event_trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
BEGIN
  IF EXISTS (
    SELECT
    FROM pg_event_trigger_ddl_commands() AS ev
    JOIN pg_extension AS ext
    ON ev.objid = ext.oid
    WHERE ext.extname = 'pg_cron'
  )
  THEN
    grant usage on schema cron to postgres with grant option;

    alter default privileges in schema cron grant all on tables to postgres with grant option;
    alter default privileges in schema cron grant all on functions to postgres with grant option;
    alter default privileges in schema cron grant all on sequences to postgres with grant option;

    alter default privileges for user supabase_admin in schema cron grant all
        on sequences to postgres with grant option;
    alter default privileges for user supabase_admin in schema cron grant all
        on tables to postgres with grant option;
    alter default privileges for user supabase_admin in schema cron grant all
        on functions to postgres with grant option;

    grant all privileges on all tables in schema cron to postgres with grant option;
    revoke all on table cron.job from postgres;
    grant select on table cron.job to postgres with grant option;
    revoke trigger on cron.job_run_details from postgres;
  END IF;
END;
$$;


--
-- Name: FUNCTION grant_pg_cron_access(); Type: COMMENT; Schema: extensions; Owner: -
--

COMMENT ON FUNCTION extensions.grant_pg_cron_access() IS 'Grants access to pg_cron';


--
-- Name: grant_pg_graphql_access(); Type: FUNCTION; Schema: extensions; Owner: -
--

CREATE FUNCTION extensions.grant_pg_graphql_access() RETURNS event_trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $_$
begin
    if not exists (
        select 1
        from pg_catalog.pg_event_trigger_ddl_commands() ev
        join pg_catalog.pg_extension e on ev.objid = e.oid
        where e.extname = 'pg_graphql'
    ) then
        return;
    end if;

    drop function if exists graphql_public.graphql;
    create or replace function graphql_public.graphql(
        "operationName" text default null,
        query text default null,
        variables jsonb default null,
        extensions jsonb default null
    )
        returns jsonb
        language sql
    as $$
        select graphql.resolve(
            query := query,
            variables := coalesce(variables, '{}'),
            "operationName" := "operationName",
            extensions := extensions
        );
    $$;

    -- Attach the wrapper to the extension so DROP EXTENSION cascades to it,
    -- which in turn triggers set_graphql_placeholder to reinstall the "not enabled" stub.
    alter extension pg_graphql add function graphql_public.graphql(text, text, jsonb, jsonb);

    grant usage on schema graphql to postgres, anon, authenticated, service_role;
    grant execute on function graphql.resolve to postgres, anon, authenticated, service_role;
    grant usage on schema graphql to postgres with grant option;
    grant usage on schema graphql_public to postgres with grant option;
end;
$_$;


--
-- Name: FUNCTION grant_pg_graphql_access(); Type: COMMENT; Schema: extensions; Owner: -
--

COMMENT ON FUNCTION extensions.grant_pg_graphql_access() IS 'Grants access to pg_graphql';


--
-- Name: grant_pg_net_access(); Type: FUNCTION; Schema: extensions; Owner: -
--

CREATE FUNCTION extensions.grant_pg_net_access() RETURNS event_trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_event_trigger_ddl_commands() AS ev
    JOIN pg_extension AS ext
    ON ev.objid = ext.oid
    WHERE ext.extname = 'pg_net'
  )
  THEN
    IF NOT EXISTS (
      SELECT 1
      FROM pg_roles
      WHERE rolname = 'supabase_functions_admin'
    )
    THEN
      CREATE USER supabase_functions_admin NOINHERIT CREATEROLE LOGIN NOREPLICATION;
    END IF;

    GRANT USAGE ON SCHEMA net TO supabase_functions_admin, postgres, anon, authenticated, service_role;

    IF EXISTS (
      SELECT FROM pg_extension
      WHERE extname = 'pg_net'
      -- all versions in use on existing projects as of 2025-02-20
      -- version 0.12.0 onwards don't need these applied
      AND extversion IN ('0.2', '0.6', '0.7', '0.7.1', '0.8.0', '0.10.0', '0.11.0')
    ) THEN
      ALTER function net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) SECURITY DEFINER;
      ALTER function net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) SECURITY DEFINER;

      ALTER function net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) SET search_path = net;
      ALTER function net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) SET search_path = net;

      REVOKE ALL ON FUNCTION net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) FROM PUBLIC;
      REVOKE ALL ON FUNCTION net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) FROM PUBLIC;

      GRANT EXECUTE ON FUNCTION net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) TO supabase_functions_admin, postgres, anon, authenticated, service_role;
      GRANT EXECUTE ON FUNCTION net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) TO supabase_functions_admin, postgres, anon, authenticated, service_role;
    END IF;
  END IF;
END;
$$;


--
-- Name: FUNCTION grant_pg_net_access(); Type: COMMENT; Schema: extensions; Owner: -
--

COMMENT ON FUNCTION extensions.grant_pg_net_access() IS 'Grants access to pg_net';


--
-- Name: pgrst_ddl_watch(); Type: FUNCTION; Schema: extensions; Owner: -
--

CREATE FUNCTION extensions.pgrst_ddl_watch() RETURNS event_trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN SELECT * FROM pg_event_trigger_ddl_commands()
  LOOP
    IF cmd.command_tag IN (
      'CREATE SCHEMA', 'ALTER SCHEMA'
    , 'CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO', 'ALTER TABLE'
    , 'CREATE FOREIGN TABLE', 'ALTER FOREIGN TABLE'
    , 'CREATE VIEW', 'ALTER VIEW'
    , 'CREATE MATERIALIZED VIEW', 'ALTER MATERIALIZED VIEW'
    , 'CREATE FUNCTION', 'ALTER FUNCTION'
    , 'CREATE TRIGGER'
    , 'CREATE TYPE', 'ALTER TYPE'
    , 'CREATE RULE'
    , 'COMMENT'
    )
    -- don't notify in case of CREATE TEMP table or other objects created on pg_temp
    AND cmd.schema_name is distinct from 'pg_temp'
    THEN
      NOTIFY pgrst, 'reload schema';
    END IF;
  END LOOP;
END; $$;


--
-- Name: pgrst_drop_watch(); Type: FUNCTION; Schema: extensions; Owner: -
--

CREATE FUNCTION extensions.pgrst_drop_watch() RETURNS event_trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
DECLARE
  obj record;
BEGIN
  FOR obj IN SELECT * FROM pg_event_trigger_dropped_objects()
  LOOP
    IF obj.object_type IN (
      'schema'
    , 'table'
    , 'foreign table'
    , 'view'
    , 'materialized view'
    , 'function'
    , 'trigger'
    , 'type'
    , 'rule'
    )
    AND obj.is_temporary IS false -- no pg_temp objects
    THEN
      NOTIFY pgrst, 'reload schema';
    END IF;
  END LOOP;
END; $$;


--
-- Name: set_graphql_placeholder(); Type: FUNCTION; Schema: extensions; Owner: -
--

CREATE FUNCTION extensions.set_graphql_placeholder() RETURNS event_trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $_$
    DECLARE
    graphql_is_dropped bool;
    BEGIN
    graphql_is_dropped = (
        SELECT ev.schema_name = 'graphql_public'
        FROM pg_event_trigger_dropped_objects() AS ev
        WHERE ev.schema_name = 'graphql_public'
    );

    IF graphql_is_dropped
    THEN
        create or replace function graphql_public.graphql(
            "operationName" text default null,
            query text default null,
            variables jsonb default null,
            extensions jsonb default null
        )
            returns jsonb
            language plpgsql
            set search_path to ''
        as $$
            DECLARE
                server_version float;
            BEGIN
                server_version = (SELECT (SPLIT_PART((select version()), ' ', 2))::float);

                IF server_version >= 14 THEN
                    RETURN jsonb_build_object(
                        'errors', jsonb_build_array(
                            jsonb_build_object(
                                'message', 'pg_graphql extension is not enabled.'
                            )
                        )
                    );
                ELSE
                    RETURN jsonb_build_object(
                        'errors', jsonb_build_array(
                            jsonb_build_object(
                                'message', 'pg_graphql is only available on projects running Postgres 14 onwards.'
                            )
                        )
                    );
                END IF;
            END;
        $$;
    END IF;

    END;
$_$;


--
-- Name: FUNCTION set_graphql_placeholder(); Type: COMMENT; Schema: extensions; Owner: -
--

COMMENT ON FUNCTION extensions.set_graphql_placeholder() IS 'Reintroduces placeholder function for graphql_public.graphql';


--
-- Name: graphql(text, text, jsonb, jsonb); Type: FUNCTION; Schema: graphql_public; Owner: -
--

CREATE FUNCTION graphql_public.graphql("operationName" text DEFAULT NULL::text, query text DEFAULT NULL::text, variables jsonb DEFAULT NULL::jsonb, extensions jsonb DEFAULT NULL::jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
            DECLARE
                server_version float;
            BEGIN
                server_version = (SELECT (SPLIT_PART((select version()), ' ', 2))::float);

                IF server_version >= 14 THEN
                    RETURN jsonb_build_object(
                        'errors', jsonb_build_array(
                            jsonb_build_object(
                                'message', 'pg_graphql extension is not enabled.'
                            )
                        )
                    );
                ELSE
                    RETURN jsonb_build_object(
                        'errors', jsonb_build_array(
                            jsonb_build_object(
                                'message', 'pg_graphql is only available on projects running Postgres 14 onwards.'
                            )
                        )
                    );
                END IF;
            END;
        $$;


--
-- Name: get_auth(text); Type: FUNCTION; Schema: pgbouncer; Owner: -
--

CREATE FUNCTION pgbouncer.get_auth(p_usename text) RETURNS TABLE(username text, password text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
  BEGIN
      RAISE DEBUG 'PgBouncer auth request: %', p_usename;

      RETURN QUERY
      SELECT
          rolname::text,
          CASE WHEN rolvaliduntil < now()
              THEN null
              ELSE rolpassword::text
          END
      FROM pg_authid
      WHERE rolname=$1 and rolcanlogin;
  END;
  $_$;


--
-- Name: adjust_wallet_balance(uuid, numeric, text, text, uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.adjust_wallet_balance(p_user_id uuid, p_amount numeric, p_change_type text, p_reference_type text DEFAULT NULL::text, p_reference_id uuid DEFAULT NULL::uuid, p_changed_by uuid DEFAULT NULL::uuid, p_reason text DEFAULT NULL::text) RETURNS TABLE(user_id uuid, balance_before numeric, balance_after numeric)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_balance_before NUMERIC;
  v_balance_after NUMERIC;
BEGIN
  -- Security check
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: adjust_wallet_balance is service-role only.';
  END IF;

  -- Get current balance
  SELECT wallet_balance INTO v_balance_before
  FROM public.profiles WHERE id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User not found';
  END IF;

  v_balance_after := v_balance_before + p_amount;

  -- Prevent negative balance
  IF v_balance_after < 0 THEN
    RAISE EXCEPTION 'Wallet balance cannot go negative. Current: %, Adjustment: %',
      v_balance_before, p_amount;
  END IF;

  -- Update balance
  UPDATE public.profiles
  SET wallet_balance = v_balance_after
  WHERE id = p_user_id;

  -- The trigger_wallet_balance_audit trigger will auto-log the change,
  -- but we update the log with proper change_type and reference info
  UPDATE public.wallet_audit_log
  SET change_type = p_change_type,
      reference_type = p_reference_type,
      reference_id = p_reference_id,
      changed_by = p_changed_by,
      reason = p_reason
  WHERE id = (
    SELECT id FROM public.wallet_audit_log
    WHERE user_id = p_user_id
      AND balance_before = v_balance_before
      AND balance_after = v_balance_after
    ORDER BY created_at DESC
    LIMIT 1
  );

  RETURN QUERY SELECT p_user_id, v_balance_before, v_balance_after;
END;
$$;


--
-- Name: FUNCTION adjust_wallet_balance(p_user_id uuid, p_amount numeric, p_change_type text, p_reference_type text, p_reference_id uuid, p_changed_by uuid, p_reason text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.adjust_wallet_balance(p_user_id uuid, p_amount numeric, p_change_type text, p_reference_type text, p_reference_id uuid, p_changed_by uuid, p_reason text) IS 'Safe wallet balance adjustment with audit logging. Prevents negative balances. SECURITY DEFINER — service role only.';


--
-- Name: admin_cancel_order(uuid, uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_cancel_order(p_order_id uuid, p_admin_id uuid, p_reason text, p_note text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_current_status text;
  v_updated_count int;
BEGIN
  -- Lock the order row for the duration of the transaction so concurrent
  -- cancel requests serialize. This is the key concurrency fix: two
  -- simultaneous cancels can't both pass the status check.
  SELECT status INTO v_current_status
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN 'not_found';
  END IF;

  IF v_current_status = 'cancelled' THEN
    RETURN 'already_cancelled';
  END IF;

  IF v_current_status = 'delivered' THEN
    RETURN 'already_delivered';
  END IF;

  -- Conditional update: only transition if status hasn't changed under us
  -- (belt-and-suspenders alongside the FOR UPDATE lock).
  UPDATE public.orders
  SET
    status = 'cancelled',
    cancelled_by = p_admin_id,
    cancellation_reason = p_reason,
    cancelled_at = NOW()
  WHERE id = p_order_id
    AND status = v_current_status;

  GET DIAGNOSTICS v_updated_count = ROW_COUNT;

  IF v_updated_count = 0 THEN
    -- Status changed between the SELECT and UPDATE — treat as already
    -- cancelled by a concurrent request.
    RETURN 'already_cancelled';
  END IF;

  -- Insert the timeline entry. If this fails the whole transaction rolls
  -- back (including the order status update) — which is the whole point of
  -- wrapping them together (review M1).
  INSERT INTO public.order_status_history (
    order_id, status, changed_by, changed_by_role, note
  ) VALUES (
    p_order_id,
    'cancelled',
    p_admin_id,
    'admin',
    CASE WHEN p_note IS NOT NULL AND p_note <> '' THEN p_reason || ': ' || p_note
         ELSE p_reason END
  );

  RETURN 'cancelled';
END;
$$;


--
-- Name: admin_create_driver(uuid, uuid, text, text, text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_create_driver(p_admin_id uuid, p_user_id uuid, p_national_id text, p_vehicle_type text, p_vehicle_plate text, p_phone text DEFAULT NULL::text, p_vehicle_color text DEFAULT NULL::text, p_vehicle_model text DEFAULT NULL::text) RETURNS TABLE(driver_id uuid, profile_role text, verification_status text, created_at timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_current_role TEXT;
  v_driver_id UUID;
  v_verification_status TEXT := 'pending';
  v_created_at TIMESTAMPTZ;
BEGIN
  -- =====================================================================
  -- SECURITY CHECK: Verify caller is service role
  -- =====================================================================
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: admin_create_driver can only be called by service role.'
      USING HINT = 'Use the admin-create-driver Edge Function.';
  END IF;

  -- =====================================================================
  -- VALIDATION: Verify the user exists in auth.users
  -- =====================================================================
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User not found in auth.users. Create the auth user first.'
      USING HINT = 'The admin-create-driver Edge Function should create the auth user before calling this function.';
  END IF;

  -- =====================================================================
  -- VALIDATION: Check user isn't already a driver
  -- =====================================================================
  SELECT role INTO v_current_role FROM public.profiles WHERE id = p_user_id;
  IF v_current_role = 'driver' THEN
    RAISE EXCEPTION 'User is already a driver.';
  END IF;
  IF v_current_role = 'admin' THEN
    RAISE EXCEPTION 'Cannot convert an admin to a driver.';
  END IF;

  -- =====================================================================
  -- VALIDATION: Check national_id uniqueness
  -- =====================================================================
  IF EXISTS (SELECT 1 FROM public.drivers WHERE national_id = p_national_id) THEN
    RAISE EXCEPTION 'A driver with this national ID already exists.';
  END IF;

  -- =====================================================================
  -- VALIDATION: Check vehicle_plate uniqueness
  -- =====================================================================
  IF EXISTS (SELECT 1 FROM public.drivers WHERE vehicle_plate = p_vehicle_plate) THEN
    RAISE EXCEPTION 'A driver with this vehicle plate already exists.';
  END IF;

  -- =====================================================================
  -- ATOMIC OPERATION: Update profile + create driver in one transaction
  -- =====================================================================

  -- Step 1: Update profile role to 'driver'
  -- The prevent_driver_role_escalation trigger (from migration 024) will
  -- NOT block this because we're running as SECURITY DEFINER with service_role
  UPDATE public.profiles
  SET role = 'driver',
      phone = COALESCE(p_phone, phone)
  WHERE id = p_user_id;

  -- Step 2: Create driver row
  INSERT INTO public.drivers (
    id, national_id, vehicle_type, vehicle_plate,
    vehicle_color, vehicle_model, verification_status,
    is_verified, is_active, is_online
  ) VALUES (
    p_user_id,
    p_national_id,
    p_vehicle_type,
    p_vehicle_plate,
    p_vehicle_color,
    p_vehicle_model,
    v_verification_status,
    FALSE,  -- is_verified: admin must verify later
    TRUE,   -- is_active
    FALSE   -- is_online
  )
  RETURNING id, verification_status, created_at
  INTO v_driver_id, v_verification_status, v_created_at;

  -- Step 3: Log the driver status creation in driver_status_history
  INSERT INTO public.driver_status_history (
    driver_id, previous_status, new_status, changed_by, reason
  ) VALUES (
    v_driver_id,
    'none',
    'pending',
    p_admin_id,
    'Driver account created by admin'
  );

  -- Step 4: Log admin action in data_access_log
  INSERT INTO public.data_access_log (
    admin_id, action, resource_type, resource_id,
    field_name, reason
  ) VALUES (
    p_admin_id,
    'create',
    'driver',
    v_driver_id,
    'driver_account',
    'Created driver account via admin panel'
  );

  -- =====================================================================
  -- RETURN RESULT
  -- =====================================================================
  RETURN QUERY SELECT
    v_driver_id AS driver_id,
    'driver' AS profile_role,
    v_verification_status,
    v_created_at;
END;
$$;


--
-- Name: FUNCTION admin_create_driver(p_admin_id uuid, p_user_id uuid, p_national_id text, p_vehicle_type text, p_vehicle_plate text, p_phone text, p_vehicle_color text, p_vehicle_model text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.admin_create_driver(p_admin_id uuid, p_user_id uuid, p_national_id text, p_vehicle_type text, p_vehicle_plate text, p_phone text, p_vehicle_color text, p_vehicle_model text) IS 'Atomically creates a driver: updates profile role + creates driver row + logs status history + audit log. Must be called AFTER auth user creation. SECURITY DEFINER — service role only.';


--
-- Name: admin_deactivate_driver(uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_deactivate_driver(p_admin_id uuid, p_driver_id uuid, p_reason text) RETURNS TABLE(driver_id uuid, is_active boolean, deactivated_at timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  -- Sprint 2 fix (S17): added missing declarations for the RETURNING INTO
  -- targets below. Previous version raised "v_driver_id is not a known
  -- variable" at function-creation time.
  v_was_active BOOLEAN;
  v_driver_id UUID;
  v_deactivated_at TIMESTAMPTZ;
BEGIN
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: admin_deactivate_driver can only be called by service role.';
  END IF;

  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'Deactivation reason is required.';
  END IF;

  SELECT is_active INTO v_was_active FROM public.drivers WHERE id = p_driver_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Driver not found.';
  END IF;
  IF NOT v_was_active THEN
    RAISE EXCEPTION 'Driver is already deactivated.';
  END IF;

  UPDATE public.drivers
  SET is_active = FALSE,
      is_online = FALSE,
      deactivated_at = NOW()
  WHERE id = p_driver_id
  RETURNING id, is_active, deactivated_at
  INTO v_driver_id, v_was_active, v_deactivated_at;

  INSERT INTO public.driver_status_history (
    driver_id, previous_status, new_status, changed_by, reason
  ) VALUES (
    p_driver_id, 'active', 'deactivated', p_admin_id, p_reason
  );

  INSERT INTO public.notifications (
    user_id, type, title_ar, title_en, body_ar, body_en, data
  ) VALUES (
    p_driver_id, 'driver_deactivated',
    'تم إلغاء تفعيل حسابك', 'Account Deactivated',
    'تم إلغاء تفعيل حسابك. السبب: ' || p_reason,
    'Your account has been deactivated. Reason: ' || p_reason,
    jsonb_build_object('driver_id', p_driver_id, 'reason', p_reason)
  );

  INSERT INTO public.data_access_log (
    admin_id, action, resource_type, resource_id, field_name, reason
  ) VALUES (
    p_admin_id, 'modify', 'driver', p_driver_id,
    'is_active', 'Deactivated driver: ' || p_reason
  );

  RETURN QUERY SELECT p_driver_id, FALSE, NOW()::TIMESTAMPTZ;
END;
$$;


--
-- Name: FUNCTION admin_deactivate_driver(p_admin_id uuid, p_driver_id uuid, p_reason text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.admin_deactivate_driver(p_admin_id uuid, p_driver_id uuid, p_reason text) IS 'Sprint 2 fix (S17): declared missing v_driver_id and v_deactivated_at variables. Atomic driver deactivation.';


--
-- Name: admin_review_driver(uuid, uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_review_driver(p_admin_id uuid, p_driver_id uuid, p_action text, p_rejection_reason text DEFAULT NULL::text) RETURNS TABLE(driver_id uuid, verification_status text, is_verified boolean)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_previous_status TEXT;
  v_new_status TEXT;
  v_is_verified BOOLEAN;
BEGIN
  -- Security check
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: admin_review_driver can only be called by service role.';
  END IF;

  -- Validate action
  IF p_action NOT IN ('approve', 'reject') THEN
    RAISE EXCEPTION 'Invalid action: must be approve or reject.';
  END IF;

  -- Get current status
  SELECT verification_status INTO v_previous_status
  FROM public.drivers WHERE id = p_driver_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Driver not found.';
  END IF;

  IF v_previous_status = 'approved' THEN
    RAISE EXCEPTION 'Driver is already approved.';
  END IF;

  -- Determine new status
  IF p_action = 'approve' THEN
    v_new_status := 'approved';
    v_is_verified := TRUE;
  ELSE
    v_new_status := 'rejected';
    v_is_verified := FALSE;
  END IF;

  -- Atomic update
  UPDATE public.drivers
  SET verification_status = v_new_status,
      is_verified = v_is_verified,
      rejection_reason = CASE WHEN p_action = 'reject' THEN p_rejection_reason ELSE NULL END,
      verified_at = CASE WHEN p_action = 'approve' THEN NOW() ELSE verified_at END
  WHERE id = p_driver_id;

  -- Log status change
  INSERT INTO public.driver_status_history (
    driver_id, previous_status, new_status, changed_by, reason
  ) VALUES (
    p_driver_id,
    v_previous_status,
    v_new_status,
    p_admin_id,
    CASE WHEN p_action = 'reject' THEN COALESCE(p_rejection_reason, 'Rejected by admin')
         ELSE 'Approved by admin' END
  );

  -- Create notification for the driver
  INSERT INTO public.notifications (
    user_id, type, title_ar, title_en, body_ar, body_en, data
  ) VALUES (
    p_driver_id,
    CASE WHEN p_action = 'approve' THEN 'driver_verified' ELSE 'driver_rejected' END,
    CASE WHEN p_action = 'approve' THEN 'تم التحقق من حسابك' ELSE 'تم رفض التحقق' END,
    CASE WHEN p_action = 'approve' THEN 'Account Verified' ELSE 'Verification Rejected' END,
    CASE WHEN p_action = 'approve' THEN 'تم التحقق من حسابك بنجاح! يمكنك الآن بدء العمل.'
         ELSE 'تم رفض التحقق من حسابك. السبب: ' || COALESCE(p_rejection_reason, 'غير محدد') END,
    CASE WHEN p_action = 'approve' THEN 'Your account has been verified! You can now start working.'
         ELSE 'Your account verification was rejected. Reason: ' || COALESCE(p_rejection_reason, 'Not specified') END,
    jsonb_build_object('driver_id', p_driver_id, 'action', p_action)
  );

  -- Log admin action
  INSERT INTO public.data_access_log (
    admin_id, action, resource_type, resource_id, field_name, reason
  ) VALUES (
    p_admin_id,
    'modify',
    'driver',
    p_driver_id,
    'verification_status',
    CASE WHEN p_action = 'approve' THEN 'Approved driver verification'
         ELSE 'Rejected driver verification: ' || COALESCE(p_rejection_reason, '') END
  );

  RETURN QUERY SELECT p_driver_id, v_new_status, v_is_verified;
END;
$$;


--
-- Name: FUNCTION admin_review_driver(p_admin_id uuid, p_driver_id uuid, p_action text, p_rejection_reason text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.admin_review_driver(p_admin_id uuid, p_driver_id uuid, p_action text, p_rejection_reason text) IS 'Atomically reviews a driver: updates verification + logs + notifies + audits. SECURITY DEFINER — service role only.';


--
-- Name: auto_offline_stale_drivers(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auto_offline_stale_drivers() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_count INTEGER;
  v_threshold_seconds INTEGER;
BEGIN
  -- Sprint 2 fix (S10): defense-in-depth — fail closed if GRANT is widened.
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: auto_offline_stale_drivers is service-role only.';
  END IF;

  SELECT COALESCE(
    (SELECT value::INTEGER FROM public.platform_config WHERE key = 'driver_max_location_update_interval_seconds'),
    120
  ) INTO v_threshold_seconds;

  UPDATE public.drivers
  SET is_online = FALSE
  WHERE is_online = TRUE
    AND is_verified = TRUE
    AND is_active = TRUE
    AND (
      last_location_at IS NULL
      OR last_location_at < NOW() - (v_threshold_seconds * 5 || ' seconds')::INTERVAL
    );

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;


--
-- Name: FUNCTION auto_offline_stale_drivers(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.auto_offline_stale_drivers() IS 'Sprint 2 fix (S10): added in-body service-role check. Sets is_online=FALSE for stale drivers.';


--
-- Name: calculate_delivery_fee(uuid, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculate_delivery_fee(p_merchant_id uuid, p_distance_km numeric, p_order_subtotal numeric DEFAULT 0) RETURNS numeric
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  v_base_fee NUMERIC;
  v_per_km_rate NUMERIC;
  v_free_threshold NUMERIC;
  v_max_distance NUMERIC;
  v_override_fee NUMERIC;
  v_total_fee NUMERIC;
BEGIN
  -- Check if merchant has a delivery fee override
  SELECT delivery_fee_override INTO v_override_fee
  FROM public.merchants
  WHERE id = p_merchant_id;

  -- If merchant has an override, use it
  IF v_override_fee IS NOT NULL THEN
    -- Still check free delivery threshold
    SELECT COALESCE(
      (SELECT value::NUMERIC FROM public.platform_config WHERE key = 'delivery_free_threshold'),
      200.00
    ) INTO v_free_threshold;

    IF p_order_subtotal >= v_free_threshold THEN
      RETURN 0;
    END IF;

    RETURN v_override_fee;
  END IF;

  -- Fetch config values
  SELECT COALESCE(
    (SELECT value::NUMERIC FROM public.platform_config WHERE key = 'delivery_base_fee'),
    25.00
  ) INTO v_base_fee;

  SELECT COALESCE(
    (SELECT value::NUMERIC FROM public.platform_config WHERE key = 'delivery_per_km_rate'),
    5.00
  ) INTO v_per_km_rate;

  SELECT COALESCE(
    (SELECT value::NUMERIC FROM public.platform_config WHERE key = 'delivery_free_threshold'),
    200.00
  ) INTO v_free_threshold;

  SELECT COALESCE(
    (SELECT value::NUMERIC FROM public.platform_config WHERE key = 'delivery_max_distance_km'),
    15
  ) INTO v_max_distance;

  -- Check if distance exceeds max delivery range
  IF p_distance_km > v_max_distance THEN
    RETURN -1;
  END IF;

  -- Check if order qualifies for free delivery
  IF p_order_subtotal >= v_free_threshold THEN
    RETURN 0;
  END IF;

  -- Calculate: base fee + (per-km rate * distance)
  v_total_fee := v_base_fee + (v_per_km_rate * p_distance_km);

  -- Ensure fee is never negative
  RETURN GREATEST(v_total_fee, 0);
END;
$$;


--
-- Name: FUNCTION calculate_delivery_fee(p_merchant_id uuid, p_distance_km numeric, p_order_subtotal numeric); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.calculate_delivery_fee(p_merchant_id uuid, p_distance_km numeric, p_order_subtotal numeric) IS 'P1E-09: Calculates delivery fee in EGP based on platform_config and distance. Returns -1 if out of delivery range. Checks merchant override first, then applies base + per-km formula.';


--
-- Name: cancel_order(uuid, uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cancel_order(p_order_id uuid, p_initiator_id uuid, p_initiator_role text, p_reason text DEFAULT NULL::text) RETURNS TABLE(order_id uuid, status text, refund_amount numeric, cancellation_fee numeric, driver_compensation numeric, refund_percentage numeric, merchant_payout numeric, payout_recomputed_at timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
DECLARE
  v_order RECORD;
  v_rule RECORD;
  v_can_cancel BOOLEAN;
  v_refund_percentage NUMERIC;
  v_cancellation_fee_pct NUMERIC;
  v_cancellation_fee_min NUMERIC;
  v_driver_compensation NUMERIC;
  v_requires_reason BOOLEAN;
  v_refund_amount NUMERIC;
  v_cancellation_fee NUMERIC;
  v_new_payment_status TEXT;
  v_adjusted_merchant_payout NUMERIC(10,2);
  v_updated_count INT;
BEGIN
  -- Security check
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: cancel_order can only be called by service role (via Edge Function).';
  END IF;

  -- =====================================================================
  -- 1. FETCH ORDER AND VALIDATE (WITH FOR UPDATE LOCK)
  -- =====================================================================
  -- §5.5 fix: explicit column list instead of SELECT *. Only the fields
  -- the RPC actually uses are fetched — resilient to future schema changes
  -- (a new NOT NULL column on orders won't break this RPC). The FOR UPDATE
  -- lock is on the row, not the columns, so locking behavior is unchanged.
  SELECT
    id, customer_id, driver_id, status, subtotal, total,
    payment_method, payment_status, merchant_payout, order_number
  INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF v_order.status = 'cancelled' THEN
    RAISE EXCEPTION 'Order is already cancelled';
  END IF;

  IF v_order.status = 'delivered' THEN
    RAISE EXCEPTION 'Delivered orders cannot be cancelled through this function';
  END IF;

  -- =====================================================================
  -- 2. LOOK UP CANCELLATION RULES
  -- =====================================================================
  -- §5.5 fix: explicit column list instead of SELECT *.
  SELECT
    can_cancel, refund_percentage, cancellation_fee_percentage,
    cancellation_fee_min, driver_compensation, requires_reason
  INTO v_rule
  FROM public.cancellation_rules
  WHERE order_status = v_order.status AND initiator = p_initiator_role;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No cancellation rule found for status=% and initiator=%', v_order.status, p_initiator_role;
  END IF;

  v_can_cancel := v_rule.can_cancel;
  v_refund_percentage := v_rule.refund_percentage;
  v_cancellation_fee_pct := v_rule.cancellation_fee_percentage;
  v_cancellation_fee_min := v_rule.cancellation_fee_min;
  v_driver_compensation := v_rule.driver_compensation;
  v_requires_reason := v_rule.requires_reason;

  -- =====================================================================
  -- 3. VALIDATE CANCELLATION
  -- =====================================================================
  IF NOT v_can_cancel THEN
    RAISE EXCEPTION 'Cancellation not allowed for status=% by initiator=%', v_order.status, p_initiator_role;
  END IF;

  IF v_requires_reason AND (p_reason IS NULL OR trim(p_reason) = '') THEN
    RAISE EXCEPTION 'Cancellation reason is required for status=%', v_order.status;
  END IF;

  -- =====================================================================
  -- 4. CALCULATE FINANCIALS
  -- =====================================================================
  v_refund_amount := v_order.total * (v_refund_percentage / 100);

  v_cancellation_fee := GREATEST(
    v_order.subtotal * (v_cancellation_fee_pct / 100),
    v_cancellation_fee_min
  );

  v_cancellation_fee := LEAST(v_cancellation_fee, v_order.total);

  IF v_refund_percentage = 100 THEN
    v_new_payment_status := 'refunded';
  ELSIF v_refund_percentage > 0 THEN
    v_new_payment_status := 'partial_refund';
  ELSE
    v_new_payment_status := v_order.payment_status;
  END IF;

  -- S2: Compute adjusted merchant_payout based on refund percentage.
  v_adjusted_merchant_payout := CASE
    WHEN v_refund_percentage = 100 THEN 0
    WHEN v_refund_percentage = 0 THEN v_order.merchant_payout
    ELSE ROUND(
      v_order.merchant_payout * (1 - v_refund_percentage / 100),
      2
    )
  END;

  -- =====================================================================
  -- 5. ATOMIC UPDATE: Order + Status History
  -- =====================================================================
  -- Status history stays in the main transaction — it's audit data that
  -- must be consistent with the order status change.

  UPDATE public.orders
  SET status = 'cancelled',
      cancelled_by = p_initiator_id,
      cancellation_reason = p_reason,
      cancellation_fee = v_cancellation_fee,
      cancelled_at = NOW(),
      refund_amount = v_refund_amount,
      refund_status = v_new_payment_status,
      merchant_payout = v_adjusted_merchant_payout,
      payout_recomputed_at = NOW(),
      payment_status = CASE
        WHEN v_order.payment_method = 'cash' AND v_refund_percentage = 100 THEN 'pending_cash'
        ELSE v_new_payment_status
      END
  WHERE id = p_order_id
    AND status = v_order.status;

  GET DIAGNOSTICS v_updated_count = ROW_COUNT;

  IF v_updated_count = 0 THEN
    RAISE EXCEPTION 'Order status changed concurrently during cancellation processing';
  END IF;

  INSERT INTO public.order_status_history (order_id, status, changed_by, changed_by_role, note)
  VALUES (
    p_order_id,
    'cancelled',
    p_initiator_id,
    p_initiator_role,
    'Cancelled by ' || p_initiator_role || '. Reason: ' || COALESCE(p_reason, 'Not specified') ||
    '. Refund: ' || v_refund_amount || ' EGP (' || v_refund_percentage || '%). Fee: ' || v_cancellation_fee || ' EGP.'
  );

  -- =====================================================================
  -- 5b. NOTIFICATIONS — wrapped in a subtransaction (§3.8 fix, from mig 086)
  -- =====================================================================
  -- Notifications are NOT money-critical. A failed notification insert
  -- should NOT roll back the cancellation. The customer should still see
  -- "Order cancelled" in the app, even if the push notification delivery
  -- is delayed. The driver_earnings insert below is money-moving and
  -- stays in the main transaction (outside the subtransaction).
  BEGIN
    INSERT INTO public.notifications (user_id, type, title_ar, title_en, body_ar, body_en, data)
    VALUES (
      v_order.customer_id,
      'order_cancelled',
      'تم إلغاء طلبك', 'Order Cancelled',
      'تم إلغاء طلبك رقم ' || v_order.order_number || '. المبلغ المسترد: ' || v_refund_amount || ' ج.م',
      'Your order ' || v_order.order_number || ' has been cancelled. Refund: ' || v_refund_amount || ' EGP',
      jsonb_build_object('order_id', p_order_id, 'refund_amount', v_refund_amount)
    );

    IF v_order.driver_id IS NOT NULL THEN
      INSERT INTO public.notifications (user_id, type, title_ar, title_en, body_ar, body_en, data)
      VALUES (
        v_order.driver_id,
        'order_cancelled',
        'تم إلغاء الطلب', 'Order Cancelled',
        'تم إلغاء الطلب رقم ' || v_order.order_number || '. تعويض: ' || v_driver_compensation || ' ج.م',
        'Order ' || v_order.order_number || ' has been cancelled. Compensation: ' || v_driver_compensation || ' EGP',
        jsonb_build_object('order_id', p_order_id, 'compensation', v_driver_compensation)
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    -- Swallow the notification failure — the cancellation itself is already
    -- committed to the orders table (the UPDATE above succeeded). Log a
    -- NOTICE so ops can grep for "Notification insert failed" in the EF
    -- logs and investigate if a notification subsystem is broken.
    RAISE NOTICE 'Notification insert failed for order %: %', p_order_id, SQLERRM;
  END;

  -- =====================================================================
  -- 5c. DRIVER COMPENSATION — stays in main transaction (money-moving)
  -- =====================================================================
  -- This MUST roll back if it fails — a missing compensation earning is a
  -- money leak that finance would have to reconcile manually. Keeping it
  -- outside the notification subtransaction preserves that guarantee.

  IF v_order.driver_id IS NOT NULL AND v_driver_compensation > 0 THEN
    INSERT INTO public.driver_earnings (
      driver_id, order_id, delivery_fee_earned, platform_fee_deducted,
      net_earnings, earnings_pct_used, is_cancellation_compensation, compensation_reason
    ) VALUES (
      v_order.driver_id,
      p_order_id,
      v_driver_compensation,
      0,
      v_driver_compensation,
      100,
      TRUE,
      'Cancellation compensation for order ' || v_order.order_number
    );
  END IF;

  -- =====================================================================
  -- 6. RETURN RESULT (8 columns — unchanged from migration 082)
  -- =====================================================================
  RETURN QUERY SELECT
    p_order_id,
    'cancelled'::TEXT,
    v_refund_amount,
    v_cancellation_fee,
    v_driver_compensation,
    v_refund_percentage,
    v_adjusted_merchant_payout,
    NOW()::TIMESTAMPTZ;
END;
$$;


--
-- Name: FUNCTION cancel_order(p_order_id uuid, p_initiator_id uuid, p_initiator_role text, p_reason text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.cancel_order(p_order_id uuid, p_initiator_id uuid, p_initiator_role text, p_reason text) IS 'Atomically cancels an order with row-level locking: validates rules, calculates fees/refunds, updates order + status history, notifies stakeholders (in a subtransaction so a notification failure does NOT roll back the cancellation — gap-analysis §3.8), compensates driver. Recomputes merchant_payout (proportional reduction on cancellation, zeroed on full refund) and stamps payout_recomputed_at. Uses explicit column lists instead of SELECT * (gap-analysis §5.5). SECURITY DEFINER — service role only.';


--
-- Name: cancel_stale_orders(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cancel_stale_orders() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_config JSONB;
  v_order RECORD;
  v_minutes INT;
  v_cancelled INT := 0;
  v_failed INT := 0;
  v_session_cleaned INT;
BEGIN
  -- pg_cron doesn't set request.jwt.claims, but cancel_order RPC requires it for
  -- its service-role guard. Set it ourselves — safe because we're SECURITY DEFINER
  -- and this is an internal cron, not user-invokable.
  PERFORM set_config('request.jwt.claims', '{"role": "service_role"}', true);

  -- Batch-fetch all config thresholds in one query
  SELECT jsonb_object_agg(key, value) INTO v_config
  FROM public.platform_config
  WHERE key IN (
    'auto_cancel_pending_minutes',
    'auto_cancel_no_driver_minutes',
    'auto_cancel_ready_timeout_minutes'
  );

  -- Rule 1: pending orders past threshold
  -- G6: with payment dispatch gating ON, a paid digital order legitimately
  -- sits at status='pending' waiting for the webhook/reconcile assign. Never
  -- sweep it — payment_status <> 'paid' is the guard.
  v_minutes := COALESCE((v_config->>'auto_cancel_pending_minutes')::INT, 15);
  FOR v_order IN
    SELECT id FROM public.orders
    WHERE status = 'pending'
      AND payment_status IS DISTINCT FROM 'paid'
      AND created_at < NOW() - (v_minutes || ' minutes')::INTERVAL
    ORDER BY created_at ASC
    LIMIT 50
  LOOP
    BEGIN
      PERFORM public.cancel_order(v_order.id, NULL::UUID, 'system',
        'Auto-cancelled: merchant did not confirm within timeout');
      v_cancelled := v_cancelled + 1;
    EXCEPTION WHEN OTHERS THEN
      v_failed := v_failed + 1;
      RAISE WARNING 'cancel_stale_orders: failed to cancel order % (pending rule): %',
        v_order.id, SQLERRM;
    END;
  END LOOP;

  -- Rule 2: confirmed + no driver past threshold
  -- G6: skip paid orders (customer already charged — surface them via the
  -- 'payment_paid_unassigned' alert instead of silently cancelling) and skip
  -- orders already queued for a refund (an admin refund is in flight; a
  -- cancel here would overwrite refund_amount/refund_status mid-flight).
  v_minutes := COALESCE((v_config->>'auto_cancel_no_driver_minutes')::INT, 30);
  FOR v_order IN
    SELECT id FROM public.orders
    WHERE status = 'confirmed' AND driver_id IS NULL
      AND payment_status IS DISTINCT FROM 'paid'
      AND (refund_status IS NULL OR refund_status NOT IN ('pending_refund', 'refund_failed'))
      AND created_at < NOW() - (v_minutes || ' minutes')::INTERVAL
    ORDER BY created_at ASC
    LIMIT 50
  LOOP
    BEGIN
      PERFORM public.cancel_order(v_order.id, NULL::UUID, 'system',
        'Auto-cancelled: no driver assigned within timeout');
      v_cancelled := v_cancelled + 1;
    EXCEPTION WHEN OTHERS THEN
      v_failed := v_failed + 1;
      RAISE WARNING 'cancel_stale_orders: failed to cancel order % (no-driver rule): %',
        v_order.id, SQLERRM;
    END;
  END LOOP;

  -- Rule 3: ready orders (no pickup) past threshold — UNCHANGED by 094.
  -- A paid order reaching 'ready' then expiring SHOULD be swept: cancel_order
  -- recomputes the refund from cancellation_rules and reconcile-payments
  -- executes it, so this is the correct self-healing path.
  v_minutes := COALESCE((v_config->>'auto_cancel_ready_timeout_minutes')::INT, 60);
  FOR v_order IN
    SELECT id FROM public.orders
    WHERE status = 'ready'
      AND created_at < NOW() - (v_minutes || ' minutes')::INTERVAL
    ORDER BY created_at ASC
    LIMIT 50
  LOOP
    BEGIN
      PERFORM public.cancel_order(v_order.id, NULL::UUID, 'system',
        'Auto-cancelled: order not picked up within timeout');
      v_cancelled := v_cancelled + 1;
    EXCEPTION WHEN OTHERS THEN
      v_failed := v_failed + 1;
      RAISE WARNING 'cancel_stale_orders: failed to cancel order % (ready rule): %',
        v_order.id, SQLERRM;
    END;
  END LOOP;

  -- B1-G5: cleanup expired admin sessions
  SELECT public.cleanup_expired_admin_sessions() INTO v_session_cleaned;

  RAISE NOTICE 'cancel_stale_orders complete: cancelled=%, failed=%, sessions_cleaned=%',
    v_cancelled, v_failed, v_session_cleaned;
END;
$$;


--
-- Name: FUNCTION cancel_stale_orders(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.cancel_stale_orders() IS 'W1.2 (patched by 094): pg_cron replacement for auto-cancel-stale-orders EF. Cancels orders stuck in pending/confirmed/ready past configurable timeouts. 094: pending + confirmed-no-driver rules skip paid / in-refund orders (money-linked orders surface via payment alerts instead). Also cleans up expired admin sessions.';


--
-- Name: check_and_trigger_alerts(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_and_trigger_alerts() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  r RECORD;
  v_val NUMERIC;
  v_triggered BOOLEAN;
  v_msg TEXT;
BEGIN
  FOR r IN SELECT * FROM public.alert_rules WHERE is_active = true LOOP
    -- Evaluate metric
    IF r.metric = 'online_drivers' THEN
      SELECT COUNT(*) INTO v_val FROM public.drivers WHERE is_online = true;
    ELSIF r.metric = 'order_cancellation_rate' THEN
      SELECT COALESCE(ROUND(100.0 * COUNT(*) FILTER (WHERE status = 'cancelled') / NULLIF(COUNT(*), 0), 2), 0)
      INTO v_val FROM public.orders WHERE created_at >= NOW() - INTERVAL '1 hour';
    ELSIF r.metric = 'payment_failures_5min' OR r.metric = 'payment_failures' THEN
      SELECT COUNT(*) INTO v_val FROM public.orders WHERE payment_status = 'failed' AND updated_at >= NOW() - INTERVAL '5 minutes';
    ELSIF r.metric = 'pending_verifications_24h' OR r.metric = 'pending_verifications' THEN
      SELECT COUNT(*) INTO v_val FROM public.drivers WHERE verification_status = 'pending' AND created_at <= NOW() - INTERVAL '24 hours';
    ELSIF r.metric = 'avg_delivery_time_minutes' THEN
      SELECT COALESCE(ROUND(AVG(EXTRACT(EPOCH FROM (delivered_at - created_at)) / 60)::numeric, 1), 0)
      INTO v_val FROM public.orders WHERE status = 'delivered' AND delivered_at >= NOW() - INTERVAL '1 hour';
    ELSIF r.metric = 'driver_rating_avg' OR r.metric = 'driver_low_rating' THEN
      SELECT COALESCE(MIN(rating), 5.0) INTO v_val FROM public.drivers WHERE total_deliveries >= 10;
    ELSIF r.metric = 'pending_orders' THEN
      SELECT COUNT(*) INTO v_val FROM public.orders WHERE status = 'pending';
    ELSIF r.metric = 'active_orders' THEN
      SELECT COUNT(*) INTO v_val FROM public.orders WHERE status NOT IN ('delivered', 'cancelled');
    ELSIF r.metric = 'revenue_today' THEN
      SELECT COALESCE(SUM(platform_fee + delivery_fee), 0) INTO v_val FROM public.orders WHERE status = 'delivered' AND delivered_at >= CURRENT_DATE;
    ELSIF r.metric = 'payment_refunds_stuck' THEN
      -- G9: refunds stuck > 1h. updated_at is bumped on ANY order update, so
      -- "no update in the last hour while still in a refund-pending state"
      -- means the reconcile cron is not making progress on it.
      SELECT COUNT(*) INTO v_val FROM public.orders
      WHERE refund_status IN ('pending_refund', 'refund_failed')
        AND refund_amount > 0
        AND updated_at <= NOW() - INTERVAL '1 hour';
    ELSIF r.metric = 'payment_paid_unassigned' THEN
      -- G5 companion: paid orders still without a driver after 15 minutes.
      -- With dispatch gating ON these mean the webhook AND the reconcile
      -- fallback both failed to assign; with gating OFF they mean the
      -- place-order assignment itself failed. Either way ops must look.
      SELECT COUNT(*) INTO v_val FROM public.orders
      WHERE payment_status = 'paid'
        AND driver_id IS NULL
        AND status NOT IN ('delivered', 'cancelled')
        AND updated_at <= NOW() - INTERVAL '15 minutes';
    ELSIF r.metric = 'storage_usage_pct' THEN
      v_val := 42.5; -- Simulated typical storage usage
    ELSIF r.metric = 'rate_limit_usage_pct' THEN
      v_val := 84.2; -- Simulated approaching limit (will trigger the default seed alert)
    ELSE
      v_val := 0;
    END IF;

    -- Evaluate condition
    v_triggered := false;
    IF r.condition = 'less_than' THEN
      IF v_val < r.threshold THEN v_triggered := true; END IF;
    ELSIF r.condition = 'greater_than' THEN
      IF v_val > r.threshold THEN v_triggered := true; END IF;
    ELSIF r.condition = 'equals' THEN
      IF v_val = r.threshold THEN v_triggered := true; END IF;
    END IF;

    -- Handle incident state
    IF v_triggered THEN
      -- If active incident does not exist, insert it
      IF NOT EXISTS (
        SELECT 1 FROM public.alert_incidents
        WHERE rule_id = r.id AND status IN ('triggered', 'acknowledged')
      ) THEN
        v_msg := 'Rule "' || r.name || '" breached threshold. Current metric value for ' || r.metric || ' is ' || v_val || ' (Condition: ' || r.condition || ' ' || r.threshold || ').';
        INSERT INTO public.alert_incidents (rule_id, metric, severity, message, trigger_value, status, triggered_at)
        VALUES (r.id, r.metric, r.severity, v_msg, v_val, 'triggered', NOW());
      END IF;
    ELSE
      -- If active incident exists, automatically resolve it
      UPDATE public.alert_incidents
      SET status = 'resolved',
          resolved_at = NOW(),
          resolution_notes = 'Automatically resolved: metric value (' || v_val || ') no longer breaches threshold.'
      WHERE rule_id = r.id AND status IN ('triggered', 'acknowledged');
    END IF;
  END LOOP;
END;
$$;


--
-- Name: check_driver_suspension(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_driver_suspension() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
  IF NEW.is_online = TRUE AND (OLD.is_online = FALSE OR OLD.is_online = TRUE) THEN
    IF NEW.suspended_until IS NOT NULL AND NEW.suspended_until > NOW() THEN
      RAISE EXCEPTION 'Driver is temporarily suspended until %', NEW.suspended_until;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: check_promo_fraud(uuid, inet); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_promo_fraud(p_promo_code_id uuid, p_ip_address inet) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_distinct_users INTEGER;
  v_promo_code TEXT;
  v_msg TEXT;
  v_rule_id UUID;
BEGIN
  -- Count distinct users who redeemed this promo from this IP in the last 24h
  SELECT COUNT(DISTINCT user_id) INTO v_distinct_users
  FROM public.promo_code_usage
  WHERE promo_code_id = p_promo_code_id
    AND ip_address = p_ip_address
    AND used_at > NOW() - INTERVAL '24 hours';

  -- If >= 3, insert an alert incident (if one doesn't already exist)
  IF v_distinct_users >= 3 THEN
    SELECT code INTO v_promo_code FROM public.promo_codes WHERE id = p_promo_code_id;

    -- Find the seeded promo_fraud alert rule
    SELECT id INTO v_rule_id FROM public.alert_rules WHERE metric = 'promo_fraud' LIMIT 1;

    IF v_rule_id IS NOT NULL THEN
      -- Check for an existing active incident for this promo + IP
      IF NOT EXISTS (
        SELECT 1 FROM public.alert_incidents
        WHERE rule_id = v_rule_id
          AND status IN ('triggered', 'acknowledged')
          AND message LIKE '%' || v_promo_code || '%'
          AND message LIKE '%' || host(p_ip_address) || '%'
      ) THEN
        v_msg := 'Promo fraud detected: code "' || v_promo_code || '" redeemed by '
          || v_distinct_users || ' distinct users from IP ' || host(p_ip_address)
          || ' in the last 24 hours.';
        INSERT INTO public.alert_incidents (rule_id, metric, severity, message, trigger_value, status, triggered_at)
        VALUES (v_rule_id, 'promo_fraud', 'critical', v_msg, v_distinct_users, 'triggered', NOW());
      END IF;
    END IF;
  END IF;

  RETURN v_distinct_users;
END;
$$;


--
-- Name: FUNCTION check_promo_fraud(p_promo_code_id uuid, p_ip_address inet); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.check_promo_fraud(p_promo_code_id uuid, p_ip_address inet) IS 'P2-7: Counts distinct users who redeemed a promo from a given IP in the last 24h. If >= 3, inserts a critical alert_incident. Idempotent — skips if an active incident already exists for this promo + IP.';


--
-- Name: cleanup_expired_admin_sessions(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cleanup_expired_admin_sessions() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_count INTEGER;
BEGIN
  UPDATE public.admin_sessions
  SET invalidated_at = NOW(),
      invalidation_reason = 'timeout'
  WHERE invalidated_at IS NULL
    AND expires_at < NOW();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;


--
-- Name: FUNCTION cleanup_expired_admin_sessions(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.cleanup_expired_admin_sessions() IS 'Marks expired admin sessions as invalidated. Call periodically via cron. Returns count of cleaned sessions.';


--
-- Name: compute_admin_kpis(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.compute_admin_kpis() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_dashboard JSONB;
  v_orders JSONB;
  v_drivers JSONB;
  v_revenue JSONB;
  v_customers JSONB;
BEGIN
  -- Dashboard overview KPIs
  SELECT jsonb_build_object(
    'active_orders', COUNT(*) FILTER (WHERE status NOT IN ('delivered', 'cancelled')),
    'pending_orders', COUNT(*) FILTER (WHERE status = 'pending'),
    'confirmed_orders', COUNT(*) FILTER (WHERE status = 'confirmed'),
    'preparing_orders', COUNT(*) FILTER (WHERE status = 'preparing'),
    'ready_orders', COUNT(*) FILTER (WHERE status = 'ready'),
    'in_delivery_orders', COUNT(*) FILTER (WHERE status IN ('picked_up', 'on_the_way')),
    'delivered_today', COUNT(*) FILTER (WHERE status = 'delivered' AND delivered_at >= CURRENT_DATE),
    'cancelled_today', COUNT(*) FILTER (WHERE status = 'cancelled' AND cancelled_at >= CURRENT_DATE),
    'total_orders_today', COUNT(*) FILTER (WHERE created_at >= CURRENT_DATE)
  ) INTO v_dashboard
  FROM public.orders;

  -- Order metrics
  SELECT jsonb_build_object(
    'total_orders', COUNT(*),
    'avg_order_value', ROUND(AVG(total), 2),
    'avg_delivery_time_minutes', ROUND(AVG(
      EXTRACT(EPOCH FROM (delivered_at - created_at)) / 60
    ) FILTER (WHERE status = 'delivered' AND delivered_at IS NOT NULL), 1),
    'cash_orders_pct', ROUND(
      100.0 * COUNT(*) FILTER (WHERE payment_method = 'cash') / NULLIF(COUNT(*), 0), 1
    ),
    'digital_orders_pct', ROUND(
      100.0 * COUNT(*) FILTER (WHERE payment_method != 'cash') / NULLIF(COUNT(*), 0), 1
    )
  ) INTO v_orders
  FROM public.orders
  WHERE created_at >= CURRENT_DATE;

  -- Driver metrics
  SELECT jsonb_build_object(
    'total_drivers', COUNT(*),
    'online_drivers', COUNT(*) FILTER (WHERE is_online = TRUE),
    'verified_drivers', COUNT(*) FILTER (WHERE is_verified = TRUE),
    'pending_verification', COUNT(*) FILTER (WHERE verification_status = 'pending'),
    'active_on_order', COUNT(*) FILTER (WHERE is_online = TRUE AND EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.driver_id = drivers.id
        AND o.status IN ('confirmed', 'preparing', 'ready', 'picked_up', 'on_the_way')
    ))
  ) INTO v_drivers
  FROM public.drivers;

  -- Revenue metrics
  SELECT jsonb_build_object(
    'revenue_today', COALESCE(SUM(platform_fee + delivery_fee) FILTER (WHERE status = 'delivered' AND delivered_at >= CURRENT_DATE), 0),
    'revenue_this_week', COALESCE(SUM(platform_fee + delivery_fee) FILTER (WHERE status = 'delivered' AND delivered_at >= DATE_TRUNC('week', CURRENT_DATE)), 0),
    'revenue_this_month', COALESCE(SUM(platform_fee + delivery_fee) FILTER (WHERE status = 'delivered' AND delivered_at >= DATE_TRUNC('month', CURRENT_DATE)), 0),
    'gross_order_value_today', COALESCE(SUM(total) FILTER (WHERE status = 'delivered' AND delivered_at >= CURRENT_DATE), 0),
    'pending_cash_total', COALESCE(SUM(total) FILTER (WHERE payment_status = 'pending_cash'), 0)
  ) INTO v_revenue
  FROM public.orders;

  -- Customer metrics
  SELECT jsonb_build_object(
    'total_customers', (SELECT COUNT(*) FROM public.profiles WHERE role = 'customer'),
    'new_customers_today', (SELECT COUNT(*) FROM public.profiles WHERE role = 'customer' AND created_at >= CURRENT_DATE),
    'active_customers_week', (SELECT COUNT(DISTINCT customer_id) FROM public.orders WHERE created_at >= CURRENT_DATE - INTERVAL '7 days')
  ) INTO v_customers;

  -- Upsert all KPIs
  INSERT INTO public.admin_kpi_cache (key, value, computed_at) VALUES
    ('dashboard', v_dashboard, NOW()),
    ('orders', v_orders, NOW()),
    ('drivers', v_drivers, NOW()),
    ('revenue', v_revenue, NOW()),
    ('customers', v_customers, NOW())
  ON CONFLICT (key) DO UPDATE SET
    value = EXCLUDED.value,
    computed_at = EXCLUDED.computed_at;

  -- Evaluate and trigger alerts
  PERFORM public.check_and_trigger_alerts();
END;
$$;


--
-- Name: FUNCTION compute_admin_kpis(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.compute_admin_kpis() IS 'Pre-computes all admin dashboard KPIs and evaluates alerts. Stores results in admin_kpi_cache and alert_incidents.';


--
-- Name: count_drivers(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.count_drivers(p_search text, p_status text) RETURNS bigint
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
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


--
-- Name: create_admin_session(uuid, text, inet, text, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_admin_session(p_admin_id uuid, p_session_token text, p_ip_address inet DEFAULT NULL::inet, p_user_agent text DEFAULT NULL::text, p_device_fingerprint text DEFAULT NULL::text, p_duration_hours integer DEFAULT 8) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_session_id UUID;
BEGIN
  -- Invalidate any existing active sessions for this admin
  UPDATE public.admin_sessions
  SET invalidated_at = NOW(),
      invalidation_reason = 'new_login'
  WHERE admin_id = p_admin_id
    AND invalidated_at IS NULL;

  -- Create the new session
  INSERT INTO public.admin_sessions (
    admin_id, session_token, ip_address, user_agent,
    device_fingerprint, expires_at
  ) VALUES (
    p_admin_id,
    p_session_token,
    p_ip_address,
    p_user_agent,
    p_device_fingerprint,
    NOW() + (p_duration_hours || ' hours')::INTERVAL
  )
  RETURNING id INTO v_session_id;

  RETURN v_session_id;
END;
$$;


--
-- Name: FUNCTION create_admin_session(p_admin_id uuid, p_session_token text, p_ip_address inet, p_user_agent text, p_device_fingerprint text, p_duration_hours integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.create_admin_session(p_admin_id uuid, p_session_token text, p_ip_address inet, p_user_agent text, p_device_fingerprint text, p_duration_hours integer) IS 'Creates a new admin session and invalidates all previous sessions. Enforces one active session per admin. Returns new session ID.';


--
-- Name: create_driver_settlement(uuid, timestamp with time zone, timestamp with time zone, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_driver_settlement(p_driver_id uuid, p_period_start timestamp with time zone, p_period_end timestamp with time zone, p_payout_method text DEFAULT 'cash'::text) RETURNS TABLE(settlement_id uuid, net_payable numeric, delivery_count integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_settlement_id UUID;
  v_delivery_count INTEGER;
  v_gross NUMERIC(10,2);
  v_platform_fee NUMERIC(10,2);
  v_cancel_comp NUMERIC(10,2);
  v_net NUMERIC(10,2);
BEGIN
  -- Security: service-role only (cron EF + admin API both use service role)
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: create_driver_settlement can only be called by service role.';
  END IF;

  -- Lock the driver row to prevent concurrent settlement creation
  PERFORM 1 FROM public.drivers WHERE id = p_driver_id FOR UPDATE;

  -- Check no overlapping pending/approved settlement exists
  IF EXISTS (
    SELECT 1 FROM public.driver_settlements
    WHERE driver_id = p_driver_id
      AND status IN ('pending', 'approved')
      AND period_start <= p_period_end
      AND period_end >= p_period_start
  ) THEN
    RAISE EXCEPTION 'A pending or approved settlement already exists for this period';
  END IF;

  -- Aggregate eligible earnings: pending + not already in a settlement +
  -- created in the period window.
  SELECT
    COUNT(de.id),
    COALESCE(SUM(de.delivery_fee_earned), 0),
    COALESCE(SUM(de.platform_fee_deducted), 0),
    COALESCE(SUM(CASE WHEN de.is_cancellation_compensation THEN de.net_earnings ELSE 0 END), 0)
  INTO v_delivery_count, v_gross, v_platform_fee, v_cancel_comp
  FROM public.driver_earnings de
  WHERE de.driver_id = p_driver_id
    AND de.created_at >= p_period_start
    AND de.created_at < p_period_end
    AND de.payout_status = 'pending'
    AND NOT EXISTS (
      SELECT 1 FROM public.driver_settlement_earnings dse WHERE dse.earning_id = de.id
    );

  IF v_delivery_count = 0 THEN
    RAISE EXCEPTION 'No eligible earnings for settlement in this period';
  END IF;

  v_net := v_gross - v_platform_fee + v_cancel_comp;
  IF v_net < 0 THEN
    v_net := 0;
  END IF;

  INSERT INTO public.driver_settlements (
    driver_id, period_start, period_end,
    delivery_count, gross_earnings, platform_fee_deducted,
    cancellation_compensation, net_payable, status, payout_method
  ) VALUES (
    p_driver_id, p_period_start, p_period_end,
    v_delivery_count, v_gross, v_platform_fee,
    v_cancel_comp, v_net, 'pending', p_payout_method
  )
  RETURNING id INTO v_settlement_id;

  -- Link earnings to the settlement (snapshot net_earnings for audit)
  INSERT INTO public.driver_settlement_earnings (settlement_id, earning_id, net_earnings_at_settlement)
    SELECT v_settlement_id, de.id, de.net_earnings
    FROM public.driver_earnings de
    WHERE de.driver_id = p_driver_id
      AND de.created_at >= p_period_start
      AND de.created_at < p_period_end
      AND de.payout_status = 'pending'
      AND NOT EXISTS (
        SELECT 1 FROM public.driver_settlement_earnings dse WHERE dse.earning_id = de.id
      );

  -- Flip the linked earnings to 'paid' so they don't get re-settled
  UPDATE public.driver_earnings
    SET payout_status = 'paid',
        paid_at = NOW(),
        payout_method = p_payout_method
    WHERE id IN (
      SELECT earning_id FROM public.driver_settlement_earnings WHERE settlement_id = v_settlement_id
    );

  RETURN QUERY SELECT v_settlement_id, v_net, v_delivery_count;
END;
$$;


--
-- Name: FUNCTION create_driver_settlement(p_driver_id uuid, p_period_start timestamp with time zone, p_period_end timestamp with time zone, p_payout_method text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.create_driver_settlement(p_driver_id uuid, p_period_start timestamp with time zone, p_period_end timestamp with time zone, p_payout_method text) IS 'Aggregates a drivers pending driver_earnings for the period into a settlement row, marks them paid, returns (settlement_id, net_payable, delivery_count). Idempotency: raises on overlapping pending/approved settlement. SECURITY DEFINER — service role only.';


--
-- Name: create_merchant_payout(uuid, timestamp with time zone, timestamp with time zone, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_merchant_payout(p_merchant_id uuid, p_period_start timestamp with time zone, p_period_end timestamp with time zone, p_payout_method text DEFAULT 'bank_transfer'::text) RETURNS TABLE(payout_id uuid, net_payable numeric, order_count integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_payout_id UUID;
  v_order_count INTEGER;
  v_gross NUMERIC(10,2);
  v_commission NUMERIC(10,2);
  v_discount_share NUMERIC(10,2);
  v_cancel_adj NUMERIC(10,2);
  v_net NUMERIC(10,2);
BEGIN
  -- Security: service-role only (cron EF + admin API both use service role)
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: create_merchant_payout can only be called by service role.';
  END IF;

  -- Lock the merchant row to prevent concurrent payout creation
  PERFORM 1 FROM public.merchants WHERE id = p_merchant_id FOR UPDATE;

  -- Check no overlapping pending/approved payout exists
  IF EXISTS (
    SELECT 1 FROM public.merchant_payouts
    WHERE merchant_id = p_merchant_id
      AND status IN ('pending', 'approved')
      AND period_start <= p_period_end
      AND period_end >= p_period_start
  ) THEN
    RAISE EXCEPTION 'A pending or approved payout already exists for this period';
  END IF;

  -- Aggregate eligible orders: delivered + in period + not already in a payout
  SELECT
    COUNT(o.id),
    COALESCE(SUM(o.subtotal), 0),
    COALESCE(SUM(o.subtotal * COALESCE(o.merchant_commission_pct, 0) / 100), 0),
    COALESCE(SUM(
      CASE
        WHEN o.promo_funded_by = 'merchant' THEN o.discount_amount
        WHEN o.promo_funded_by = 'shared' THEN
          ROUND(o.discount_amount * COALESCE(o.promo_merchant_share_pct, 50) / 100, 2)
        ELSE 0
      END
    ), 0),
    0  -- v_cancel_adj: cancellations are already reflected per-order in merchant_payout (S2)
  INTO v_order_count, v_gross, v_commission, v_discount_share, v_cancel_adj
  FROM public.orders o
  WHERE o.merchant_id = p_merchant_id
    AND o.status = 'delivered'
    AND o.delivered_at IS NOT NULL
    AND o.delivered_at >= p_period_start
    AND o.delivered_at < p_period_end
    AND NOT EXISTS (
      SELECT 1 FROM public.merchant_payout_orders mpo WHERE mpo.order_id = o.id
    );

  IF v_order_count = 0 THEN
    RAISE EXCEPTION 'No eligible orders for payout in this period';
  END IF;

  -- net_payable = sum of per-order merchant_payout (already correct post-S1+S2)
  SELECT COALESCE(SUM(o.merchant_payout), 0)
    INTO v_net
  FROM public.orders o
  WHERE o.merchant_id = p_merchant_id
    AND o.status = 'delivered'
    AND o.delivered_at IS NOT NULL
    AND o.delivered_at >= p_period_start
    AND o.delivered_at < p_period_end
    AND NOT EXISTS (
      SELECT 1 FROM public.merchant_payout_orders mpo WHERE mpo.order_id = o.id
    );

  IF v_net < 0 THEN
    v_net := 0;
  END IF;

  INSERT INTO public.merchant_payouts (
    merchant_id, period_start, period_end,
    order_count, gross_subtotal, commission_deducted,
    promo_discount_merchant_share, cancellation_adjustment,
    net_payable, status, payout_method
  ) VALUES (
    p_merchant_id, p_period_start, p_period_end,
    v_order_count, v_gross, v_commission,
    v_discount_share, v_cancel_adj,
    v_net, 'pending', p_payout_method
  )
  RETURNING id INTO v_payout_id;

  -- Link orders to the payout (snapshot merchant_payout at settlement)
  INSERT INTO public.merchant_payout_orders (payout_id, order_id, merchant_payout_at_settlement)
    SELECT v_payout_id, o.id, o.merchant_payout
    FROM public.orders o
    WHERE o.merchant_id = p_merchant_id
      AND o.status = 'delivered'
      AND o.delivered_at IS NOT NULL
      AND o.delivered_at >= p_period_start
      AND o.delivered_at < p_period_end
      AND NOT EXISTS (
        SELECT 1 FROM public.merchant_payout_orders mpo WHERE mpo.order_id = o.id
      );

  RETURN QUERY SELECT v_payout_id, v_net, v_order_count;
END;
$$;


--
-- Name: FUNCTION create_merchant_payout(p_merchant_id uuid, p_period_start timestamp with time zone, p_period_end timestamp with time zone, p_payout_method text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.create_merchant_payout(p_merchant_id uuid, p_period_start timestamp with time zone, p_period_end timestamp with time zone, p_payout_method text) IS 'Aggregates a merchants delivered orders for the period into a payout row, snapshots merchant_payout per order, returns (payout_id, net_payable, order_count). Idempotency: raises on overlapping pending/approved payout. SECURITY DEFINER — service role only. Mirrors create_driver_settlement (migration 083).';


--
-- Name: decrypt_national_id(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.decrypt_national_id(p_encrypted text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_key TEXT;
  v_decrypted TEXT;
BEGIN
  IF p_encrypted IS NULL THEN
    RETURN NULL;
  END IF;

  -- Get the encryption key from Supabase Vault
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'national_id_encryption_key';

  IF v_key IS NULL OR v_key = '' THEN
    RAISE EXCEPTION 'National ID encryption key not configured in Vault.';
  END IF;

  -- Decrypt using pgcrypto
  v_decrypted := pg_sym_decrypt(p_encrypted::bytea, v_key, 'cipher=aes256, mode=cfb');

  RETURN v_decrypted;
END;
$$;


--
-- Name: FUNCTION decrypt_national_id(p_encrypted text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.decrypt_national_id(p_encrypted text) IS 'Decrypts an encrypted national ID using AES-256 via pgcrypto. SECURITY DEFINER — only service role should call this. Access is logged.';


--
-- Name: detect_suspicious_orders(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.detect_suspicious_orders(p_hours integer DEFAULT 24) RETURNS TABLE(customer_id uuid, customer_name text, order_count integer, total_amount numeric, cancellation_count integer, avg_order_amount numeric, suspicion_reason text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
  RETURN QUERY
  -- High cancellation rate
  SELECT
    o.customer_id,
    p.full_name AS customer_name,
    COUNT(*)::INTEGER AS order_count,
    SUM(o.total)::NUMERIC AS total_amount,
    COUNT(*) FILTER (WHERE o.status = 'cancelled')::INTEGER AS cancellation_count,
    ROUND(AVG(o.total), 2)::NUMERIC AS avg_order_amount,
    'High cancellation rate: ' ||
      COUNT(*) FILTER (WHERE o.status = 'cancelled') || '/' || COUNT(*) ||
      ' orders cancelled in ' || p_hours || 'h' AS suspicion_reason
  FROM public.orders o
  JOIN public.profiles p ON p.id = o.customer_id
  WHERE o.created_at > NOW() - (p_hours || ' hours')::INTERVAL
  GROUP BY o.customer_id, p.full_name
  HAVING COUNT(*) FILTER (WHERE o.status = 'cancelled') > 3
     AND COUNT(*) FILTER (WHERE o.status = 'cancelled')::FLOAT / COUNT(*) > 0.5

  UNION ALL

  -- Unusually high order volume
  SELECT
    o.customer_id,
    p.full_name,
    COUNT(*)::INTEGER,
    SUM(o.total)::NUMERIC,
    COUNT(*) FILTER (WHERE o.status = 'cancelled')::INTEGER,
    ROUND(AVG(o.total), 2)::NUMERIC,
    'High order volume: ' || COUNT(*) || ' orders in ' || p_hours || 'h'
  FROM public.orders o
  JOIN public.profiles p ON p.id = o.customer_id
  WHERE o.created_at > NOW() - (p_hours || ' hours')::INTERVAL
  GROUP BY o.customer_id, p.full_name
  HAVING COUNT(*) > 20

  ORDER BY order_count DESC;
END;
$$;


--
-- Name: FUNCTION detect_suspicious_orders(p_hours integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.detect_suspicious_orders(p_hours integer) IS 'Detects potentially fraudulent orders: high cancellation rate, high volume. Used by admin security monitoring.';


--
-- Name: encrypt_national_id(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.encrypt_national_id(p_plaintext text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_key TEXT;
BEGIN
  -- Get the encryption key from Supabase Vault
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'national_id_encryption_key';

  IF v_key IS NULL OR v_key = '' THEN
    RAISE EXCEPTION 'National ID encryption key not configured in Vault.'
      USING HINT = 'Add secret to vault: INSERT INTO vault.secrets (secret, name, description) VALUES (encode(gen_random_bytes(32), ''base64''), ''national_id_encryption_key'', ''AES-256-GCM key for encrypting driver national IDs'');';
  END IF;

  -- Use pgcrypto symmetric encryption with AES-256-CFB
  RETURN pg_sym_encrypt(p_plaintext, v_key, 'cipher=aes256, mode=cfb');
END;
$$;


--
-- Name: FUNCTION encrypt_national_id(p_plaintext text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.encrypt_national_id(p_plaintext text) IS 'Encrypts a national ID using AES-256 via pgcrypto. Key from Supabase Vault. SECURITY DEFINER — only service role should call this.';


--
-- Name: enforce_driver_settlement_transitions(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enforce_driver_settlement_transitions() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_legal_targets TEXT[];
BEGIN
  -- Determine the legal target statuses for the OLD row's status.
  v_legal_targets := CASE OLD.status
    WHEN 'pending'  THEN ARRAY['approved', 'cancelled', 'paid']::TEXT[]
    WHEN 'approved' THEN ARRAY['cancelled', 'paid']::TEXT[]
    WHEN 'cancelled' THEN ARRAY[]::TEXT[]
    WHEN 'paid'     THEN ARRAY[]::TEXT[]
    WHEN 'failed'   THEN ARRAY['pending']::TEXT[]
    ELSE ARRAY[]::TEXT[]
  END;

  -- If status is changing, the new status must be in the legal set.
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NOT (NEW.status = ANY(v_legal_targets)) THEN
      RAISE EXCEPTION 'Illegal driver_settlements transition: % → %',
        OLD.status, NEW.status
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  -- Immutability: once paid, payout fields cannot be touched.
  -- This catches the PATCH {payout_reference: 'NEW'} attack on a paid row.
  IF OLD.status = 'paid' AND NEW.status = 'paid' THEN
    IF NEW.payout_method         IS DISTINCT FROM OLD.payout_method
    OR NEW.payout_reference      IS DISTINCT FROM OLD.payout_reference
    OR NEW.paymob_transaction_id IS DISTINCT FROM OLD.paymob_transaction_id
    OR NEW.paid_at               IS DISTINCT FROM OLD.paid_at
    OR NEW.paid_by               IS DISTINCT FROM OLD.paid_by THEN
      RAISE EXCEPTION 'Cannot edit payout fields on a paid driver_settlement (id=%)',
        OLD.id
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: FUNCTION enforce_driver_settlement_transitions(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.enforce_driver_settlement_transitions() IS 'Enforces the driver_settlements state machine (pending → approved → paid; cancelled/failed terminal) and payout-field immutability on paid rows. Added by migration 084 (gap-analysis §3.1). The trigger is intentionally permissive about pending → paid (the mark_driver_settlement_paid RPC uses approved → paid but admin can also mark pending → paid directly).';


--
-- Name: enforce_merchant_payout_transitions(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enforce_merchant_payout_transitions() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_legal_targets TEXT[];
BEGIN
  -- Determine the legal target statuses for the OLD row's status.
  v_legal_targets := CASE OLD.status
    WHEN 'pending'  THEN ARRAY['approved', 'cancelled', 'paid']::TEXT[]
    WHEN 'approved' THEN ARRAY['cancelled', 'paid']::TEXT[]
    WHEN 'cancelled' THEN ARRAY[]::TEXT[]
    WHEN 'paid'     THEN ARRAY[]::TEXT[]
    WHEN 'failed'   THEN ARRAY['pending']::TEXT[]
    ELSE ARRAY[]::TEXT[]
  END;

  -- If status is changing, the new status must be in the legal set.
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NOT (NEW.status = ANY(v_legal_targets)) THEN
      RAISE EXCEPTION 'Illegal merchant_payouts transition: % → %',
        OLD.status, NEW.status
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  -- Immutability: once paid, payout fields cannot be touched.
  IF OLD.status = 'paid' AND NEW.status = 'paid' THEN
    IF NEW.payout_method         IS DISTINCT FROM OLD.payout_method
    OR NEW.payout_reference      IS DISTINCT FROM OLD.payout_reference
    OR NEW.paymob_transaction_id IS DISTINCT FROM OLD.paymob_transaction_id
    OR NEW.paid_at               IS DISTINCT FROM OLD.paid_at
    OR NEW.paid_by               IS DISTINCT FROM OLD.paid_by THEN
      RAISE EXCEPTION 'Cannot edit payout fields on a paid merchant_payout (id=%)',
        OLD.id
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: FUNCTION enforce_merchant_payout_transitions(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.enforce_merchant_payout_transitions() IS 'Enforces the merchant_payouts state machine (pending → approved → paid; cancelled/failed terminal) and payout-field immutability on paid rows. Baked in from day one (mirrors migration 084 for driver_settlements).';


--
-- Name: f_unaccent(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f_unaccent(p_input text) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
    SET search_path TO 'public', 'extensions'
    AS $_$
  SELECT unaccent('unaccent', $1)
$_$;


--
-- Name: find_nearest_available_driver(numeric, numeric, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.find_nearest_available_driver(p_merchant_lat numeric, p_merchant_lng numeric, p_search_radius_meters integer DEFAULT 5000, p_max_candidates integer DEFAULT 3) RETURNS TABLE(driver_id uuid, distance_meters numeric, current_lat numeric, current_lng numeric)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
  -- Security: only service role can find drivers (called by assign-driver EF)
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: find_nearest_available_driver is service-role only.';
  END IF;

  RETURN QUERY
  WITH nearest_drivers AS (
    SELECT
      d.id,
      d.current_lat,
      d.current_lng,
      ST_Distance(
        ST_SetSRID(ST_MakePoint(d.current_lng, d.current_lat), 4326)::geography,
        ST_SetSRID(ST_MakePoint(p_merchant_lng, p_merchant_lat), 4326)::geography
      ) AS distance
    FROM public.drivers d
    WHERE d.is_online = TRUE
      AND d.is_verified = TRUE
      AND d.is_active = TRUE
      AND d.current_lat IS NOT NULL
      AND d.current_lng IS NOT NULL
      -- Only drivers with recent location (< 60 seconds ago)
      AND d.last_location_at > NOW() - INTERVAL '60 seconds'
      -- Within search radius
      AND ST_DWithin(
        ST_SetSRID(ST_MakePoint(d.current_lng, d.current_lat), 4326)::geography,
        ST_SetSRID(ST_MakePoint(p_merchant_lng, p_merchant_lat), 4326)::geography,
        p_search_radius_meters
      )
      -- Exclude drivers who already have active orders
      AND NOT EXISTS (
        SELECT 1 FROM public.orders o
        WHERE o.driver_id = d.id
          AND o.status IN ('confirmed', 'preparing', 'ready', 'picked_up', 'on_the_way')
      )
    ORDER BY distance
    LIMIT p_max_candidates
  )
  SELECT
    nd.id AS driver_id,
    nd.distance AS distance_meters,
    nd.current_lat,
    nd.current_lng
  FROM nearest_drivers nd
  ORDER BY nd.distance;
END;
$$;


--
-- Name: FUNCTION find_nearest_available_driver(p_merchant_lat numeric, p_merchant_lng numeric, p_search_radius_meters integer, p_max_candidates integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.find_nearest_available_driver(p_merchant_lat numeric, p_merchant_lng numeric, p_search_radius_meters integer, p_max_candidates integer) IS 'Finds nearest available verified+active+online drivers within radius. Excludes drivers with active orders. RED-04: use with SELECT FOR UPDATE SKIP LOCKED in the Edge Function for atomic assignment.';


--
-- Name: fn_check_promoted_slot_overlap(text, text, text, timestamp with time zone, timestamp with time zone, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_check_promoted_slot_overlap(p_slot_type text, p_city text, p_category text, p_starts_at timestamp with time zone, p_expires_at timestamp with time zone, p_exclude_id uuid DEFAULT NULL::uuid) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_count INTEGER;
BEGIN
  -- Count active slots that conflict with the proposed booking.
  -- Overlap test: existing.starts_at < proposed.expires_at
  --                AND existing.expires_at > proposed.starts_at
  -- (half-open intervals; touching endpoints do NOT conflict.)
  SELECT COUNT(*) INTO v_count
  FROM public.promoted_slots
  WHERE is_active = TRUE
    AND slot_type = p_slot_type
    AND city = p_city
    AND COALESCE(category, '__ALL__') = COALESCE(p_category, '__ALL__')
    AND starts_at < p_expires_at
    AND expires_at > p_starts_at
    AND (p_exclude_id IS NULL OR id != p_exclude_id);

  -- TRUE = no overlap (safe), FALSE = conflict found
  RETURN v_count = 0;
END;
$$;


--
-- Name: FUNCTION fn_check_promoted_slot_overlap(p_slot_type text, p_city text, p_category text, p_starts_at timestamp with time zone, p_expires_at timestamp with time zone, p_exclude_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_check_promoted_slot_overlap(p_slot_type text, p_city text, p_category text, p_starts_at timestamp with time zone, p_expires_at timestamp with time zone, p_exclude_id uuid) IS 'P1-3: Returns TRUE if no active promoted_slot overlaps the proposed (slot_type, city, category, [starts_at, expires_at]) window. p_exclude_id skips the row being updated (for PUT self-update). SECURITY DEFINER so the admin API (service role) can call it.';


--
-- Name: generate_order_number(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.generate_order_number() RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
  next_val BIGINT;
  order_num TEXT;
BEGIN
  next_val := nextval('public.order_number_seq');
  order_num := 'ORD-' || LPAD(next_val::TEXT, 6, '0');
  RETURN order_num;
END;
$$;


--
-- Name: FUNCTION generate_order_number(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.generate_order_number() IS 'P1E-08: Generates unique order numbers in ORD-XXXXXX format using a dedicated sequence. Called by trigger on orders INSERT.';


--
-- Name: get_admin_access_summary(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_admin_access_summary(p_hours integer DEFAULT 24) RETURNS TABLE(admin_id uuid, admin_name text, total_accesses integer, reveal_count integer, export_count integer, flagged_count integer, last_access timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
  RETURN QUERY
  SELECT
    dal.admin_id,
    p.full_name AS admin_name,
    COUNT(*)::INTEGER AS total_accesses,
    COUNT(*) FILTER (WHERE dal.action = 'reveal')::INTEGER AS reveal_count,
    COUNT(*) FILTER (WHERE dal.action = 'export')::INTEGER AS export_count,
    COUNT(*) FILTER (WHERE dal.is_flagged = TRUE)::INTEGER AS flagged_count,
    MAX(dal.created_at) AS last_access
  FROM public.data_access_log dal
  JOIN public.profiles p ON p.id = dal.admin_id
  WHERE dal.created_at > NOW() - (p_hours || ' hours')::INTERVAL
  GROUP BY dal.admin_id, p.full_name
  ORDER BY total_accesses DESC;
END;
$$;


--
-- Name: FUNCTION get_admin_access_summary(p_hours integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.get_admin_access_summary(p_hours integer) IS 'Returns PII access summary per admin for the last N hours. Used by security dashboard.';


--
-- Name: get_admin_kpi(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_admin_kpi(p_key text) RETURNS TABLE(key text, value jsonb, computed_at timestamp with time zone, age_seconds integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
  -- Sprint 2 fix (S27): converted from STABLE to SECURITY DEFINER with an
  -- in-body service-role check, matching the codebase's hardening standard
  -- (migration 044). RLS on admin_kpi_cache already blocks non-service-role
  -- SELECTs, but this is the documented defense-in-depth pattern.
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: get_admin_kpi is service-role only.';
  END IF;

  RETURN QUERY
  SELECT
    akc.key,
    akc.value,
    akc.computed_at,
    EXTRACT(EPOCH FROM NOW() - akc.computed_at)::INTEGER AS age_seconds
  FROM public.admin_kpi_cache akc
  WHERE akc.key = p_key;
END;
$$;


--
-- Name: FUNCTION get_admin_kpi(p_key text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.get_admin_kpi(p_key text) IS 'Sprint 2 fix (S27): converted to SECURITY DEFINER with in-body service-role check. Returns cached admin KPI with age in seconds.';


--
-- Name: get_analytics_summary(timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_analytics_summary(p_from timestamp with time zone, p_to timestamp with time zone) RETURNS json
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO ''
    AS $$
  SELECT json_build_object(
    'orders', (
      SELECT json_build_object(
        'total', COUNT(*),
        'completed', COUNT(*) FILTER (WHERE status = 'delivered'),
        'cancelled', COUNT(*) FILTER (WHERE status = 'cancelled'),
        'pending', COUNT(*) FILTER (WHERE status NOT IN ('delivered', 'cancelled')),
        'completionRate', CASE WHEN COUNT(*) > 0
          THEN ROUND((COUNT(*) FILTER (WHERE status = 'delivered'))::numeric * 100 / COUNT(*), 1)
          ELSE 0 END,
        'cancellationRate', CASE WHEN COUNT(*) > 0
          THEN ROUND((COUNT(*) FILTER (WHERE status = 'cancelled'))::numeric * 100 / COUNT(*), 1)
          ELSE 0 END
      )
      FROM public.orders
      WHERE created_at BETWEEN p_from AND p_to
    ),
    'financials', (
      SELECT json_build_object(
        'totalSales', COALESCE(SUM(total) FILTER (WHERE status = 'delivered'), 0),
        'totalPlatformFees', COALESCE(SUM(platform_fee) FILTER (WHERE status = 'delivered'), 0),
        'totalDeliveryFees', COALESCE(SUM(delivery_fee) FILTER (WHERE status = 'delivered'), 0),
        'averageOrderValue', CASE WHEN COUNT(*) FILTER (WHERE status = 'delivered') > 0
          THEN ROUND(SUM(total) FILTER (WHERE status = 'delivered')::numeric
            / COUNT(*) FILTER (WHERE status = 'delivered'), 2)
          ELSE 0 END,
        'netRevenue', COALESCE(SUM(platform_fee) FILTER (WHERE status = 'delivered'), 0)
                     + COALESCE(SUM(delivery_fee) FILTER (WHERE status = 'delivered'), 0)
      )
      FROM public.orders
      WHERE created_at BETWEEN p_from AND p_to
    ),
    'cancellations', COALESCE(
      (SELECT json_agg(json_build_object('reason', reason, 'count', cnt) ORDER BY cnt DESC)
       FROM (
         SELECT COALESCE(NULLIF(cancellation_reason, ''), 'Unspecified') AS reason,
                COUNT(*) AS cnt
         FROM public.orders
         WHERE created_at BETWEEN p_from AND p_to
           AND status = 'cancelled'
         GROUP BY 1
       ) c),
      '[]'::json
    ),
    'cancellationsByRole', (
      SELECT json_build_object(
        'customer', COUNT(*) FILTER (WHERE p.role = 'customer'),
        'driver',   COUNT(*) FILTER (WHERE p.role = 'driver'),
        'merchant', COUNT(*) FILTER (WHERE p.role = 'merchant'),
        'admin',    COUNT(*) FILTER (WHERE p.role = 'admin'),
        'unknown',  COUNT(*) FILTER (WHERE o.cancelled_by IS NOT NULL AND (p.role IS NULL OR p.role NOT IN ('customer', 'driver', 'merchant', 'admin')))
      )
      FROM public.orders o
      LEFT JOIN public.profiles p ON o.cancelled_by = p.id
      WHERE o.created_at BETWEEN p_from AND p_to
        AND o.status = 'cancelled'
    ),
    'drivers', (
      SELECT json_build_object(
        'total', COUNT(*),
        'online', COUNT(*) FILTER (WHERE is_online),
        'active', COUNT(*) FILTER (WHERE is_active),
        'averageRating', CASE WHEN COUNT(*) FILTER (WHERE rating IS NOT NULL) > 0
          THEN ROUND(AVG(rating) FILTER (WHERE rating IS NOT NULL), 2)
          ELSE 0 END,
        'averageDeliveries', CASE WHEN COUNT(*) > 0
          THEN ROUND(AVG(total_deliveries), 1)
          ELSE 0 END,
        'averageEarnings', CASE WHEN COUNT(*) > 0
          THEN ROUND(AVG(total_earnings), 2)
          ELSE 0 END
      )
      FROM public.drivers
    ),
    'recentDailyStats', COALESCE(
      (SELECT json_agg(json_build_object(
          'date', day,
          'orders', order_count,
          'revenue', revenue
        ) ORDER BY day)
       FROM (
         SELECT (created_at AT TIME ZONE 'Africa/Cairo')::date::text AS day,
                COUNT(*) AS order_count,
                COALESCE(SUM(total) FILTER (WHERE status = 'delivered'), 0) AS revenue
         FROM public.orders
         WHERE created_at BETWEEN p_from AND p_to
         GROUP BY 1
       ) d),
      '[]'::json
    )
  );
$$;


--
-- Name: get_avg_order_value(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_avg_order_value() RETURNS numeric
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_avg NUMERIC;
BEGIN
  SELECT COALESCE(AVG(total), 0) INTO v_avg
  FROM public.orders
  WHERE status != 'cancelled'
    AND created_at > NOW() - INTERVAL '30 days';

  RETURN v_avg;
END;
$$;


--
-- Name: FUNCTION get_avg_order_value(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.get_avg_order_value() IS 'P2-8: Returns AVG(total) for non-cancelled orders in the last 30 days. Used by the create-promo dialog estimated-cost preview.';


--
-- Name: get_driver_kpis(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_driver_kpis(p_driver_id uuid) RETURNS TABLE(week_earnings numeric, week_deliveries integer, month_earnings numeric, month_deliveries integer, pending_earnings numeric, pending_count integer, last_settlement jsonb)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  SELECT
    COALESCE(SUM(net_earnings) FILTER (WHERE created_at >= NOW() - INTERVAL '7 days'), 0)::NUMERIC,
    (COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '7 days'))::INTEGER,
    COALESCE(SUM(net_earnings) FILTER (WHERE created_at >= NOW() - INTERVAL '30 days'), 0)::NUMERIC,
    (COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '30 days'))::INTEGER,
    COALESCE(SUM(net_earnings) FILTER (WHERE payout_status = 'pending'), 0)::NUMERIC,
    (COUNT(*) FILTER (WHERE payout_status = 'pending'))::INTEGER,
    (
      SELECT to_jsonb(s)
      FROM public.driver_settlements s
      WHERE s.driver_id = p_driver_id AND s.status = 'paid'
      ORDER BY s.paid_at DESC
      LIMIT 1
    )
  FROM public.driver_earnings
  WHERE driver_id = p_driver_id;
$$;


--
-- Name: FUNCTION get_driver_kpis(p_driver_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.get_driver_kpis(p_driver_id uuid) IS 'Returns a single-row summary of a driver earnings KPIs: 7-day + 30-day SUMs and counts, pending payout SUM and count, and the most recent paid settlement as JSONB. Replaces the 4-query + JS-reduce pattern in apps/admin/src/app/api/drivers/[id]/route.ts (gap-analysis §4.3). STABLE — read-only. SECURITY DEFINER — service role only (called from the admin route).';


--
-- Name: get_driver_location(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_driver_location(p_order_id uuid, p_customer_id uuid) RETURNS TABLE(current_lat numeric, current_lng numeric, last_location_at timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_driver_id UUID;
BEGIN
  -- =====================================================================
  -- SECURITY: caller must be the customer whose UUID is passed.
  -- Service role bypasses this check (uses RLS bypass instead).
  -- =====================================================================
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role'
     AND COALESCE(current_setting('request.jwt.claims', true)::json->>'sub', '')::UUID IS DISTINCT FROM p_customer_id THEN
    RAISE EXCEPTION 'Unauthorized: p_customer_id must match auth.uid()';
  END IF;

  -- Step 1: Verify the order belongs to this customer and has a driver
  SELECT driver_id INTO v_driver_id
  FROM public.orders
  WHERE id = p_order_id
    AND customer_id = p_customer_id
    AND driver_id IS NOT NULL;

  -- If no matching order or no driver assigned, return empty
  IF v_driver_id IS NULL THEN
    RETURN;
  END IF;

  -- Step 2: Return only the location fields from the driver
  RETURN QUERY
  SELECT
    d.current_lat,
    d.current_lng,
    d.last_location_at
  FROM public.drivers d
  WHERE d.id = v_driver_id
    AND d.is_online = TRUE;
END;
$$;


--
-- Name: FUNCTION get_driver_location(p_order_id uuid, p_customer_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.get_driver_location(p_order_id uuid, p_customer_id uuid) IS 'P1E-13: SECURITY DEFINER function to securely retrieve driver location for a customer order. Verifies customer owns the order and driver is assigned. Bypasses RLS but enforces own access control. Migration 050 (S04): added auth.uid() = p_customer_id check and REVOKE FROM PUBLIC.';


--
-- Name: get_merchant_feed(text, text, numeric, numeric, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_merchant_feed(p_city text, p_category text DEFAULT NULL::text, p_lat numeric DEFAULT NULL::numeric, p_lng numeric DEFAULT NULL::numeric, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0) RETURNS TABLE(id uuid, name_ar text, name_en text, category text, logo_url text, cover_url text, city text, area text, lat numeric, lng numeric, rating numeric, rating_count integer, min_order_amount numeric, estimated_delivery_minutes integer, delivery_fee_override numeric, is_currently_open boolean, distance_meters numeric, is_promoted boolean, promoted_position integer)
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
  RETURN QUERY
  SELECT
    mws.id,
    mws.name_ar,
    mws.name_en,
    mws.category,
    mws.logo_url,
    mws.cover_url,
    mws.city,
    mws.area,
    mws.lat,
    mws.lng,
    mws.rating,
    mws.rating_count,
    mws.min_order_amount,
    mws.estimated_delivery_minutes,
    mws.delivery_fee_override,
    mws.is_currently_open,
    -- Distance calculation (only if lat/lng provided)
    CASE
      WHEN p_lat IS NOT NULL AND p_lng IS NOT NULL THEN
        ST_Distance(
          ST_MakePoint(mws.lng, mws.lat)::geography,
          ST_MakePoint(p_lng, p_lat)::geography
        )
      ELSE NULL
    END AS distance_meters,
    -- Promoted status
    CASE WHEN ps.id IS NOT NULL THEN TRUE ELSE FALSE END AS is_promoted,
    -- Promoted position (NULL if not promoted)
    ROW_NUMBER() OVER (PARTITION BY ps.id IS NOT NULL ORDER BY ps.created_at DESC)::INTEGER AS promoted_position
  FROM public.merchants_with_open_status mws
  -- LEFT JOIN promoted slots (inject ads into feed)
  LEFT JOIN public.promoted_slots ps ON ps.merchant_id = mws.id
    AND ps.is_active = TRUE
    AND ps.city = p_city
    AND ps.starts_at <= NOW()
    AND ps.expires_at > NOW()
    AND (ps.category = mws.category OR ps.category IS NULL)
  WHERE mws.city = p_city
    AND (p_category IS NULL OR mws.category = p_category)
  -- Sort: promoted first, then open by distance, then closed
  ORDER BY
    is_promoted DESC,
    mws.is_currently_open DESC,
    CASE
      WHEN p_lat IS NOT NULL AND p_lng IS NOT NULL THEN
        ST_Distance(
          ST_MakePoint(mws.lng, mws.lat)::geography,
          ST_MakePoint(p_lng, p_lat)::geography
        )
      ELSE 0
    END ASC,
    mws.rating DESC
  LIMIT p_limit
  OFFSET p_offset;
END;
$$;


--
-- Name: FUNCTION get_merchant_feed(p_city text, p_category text, p_lat numeric, p_lng numeric, p_limit integer, p_offset integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.get_merchant_feed(p_city text, p_category text, p_lat numeric, p_lng numeric, p_limit integer, p_offset integer) IS 'Optimized merchant feed query with batch-computed open status and distance. No per-row function calls. Sorts: promoted → open by distance → closed. See RED-01, RED-06.';


--
-- Name: get_merchant_kpis(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_merchant_kpis(p_merchant_id uuid) RETURNS json
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO ''
    AS $$
  SELECT json_build_object(
    'order_count', (
      SELECT COUNT(*) FROM public.orders WHERE merchant_id = p_merchant_id
    ),
    'revenue', COALESCE((
      SELECT SUM(total) FROM public.orders WHERE merchant_id = p_merchant_id
    ), 0),
    'item_count', (
      SELECT COUNT(*) FROM public.items WHERE merchant_id = p_merchant_id
    )
  );
$$;


--
-- Name: get_merchant_kpis_range(uuid, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_merchant_kpis_range(p_merchant_id uuid, p_from timestamp with time zone) RETURNS json
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO ''
    AS $$
  SELECT json_build_object(
    'order_count', (
      SELECT COUNT(*) FROM public.orders
      WHERE merchant_id = p_merchant_id
        AND created_at >= p_from
    ),
    'revenue', COALESCE((
      SELECT SUM(total) FROM public.orders
      WHERE merchant_id = p_merchant_id
        AND created_at >= p_from
    ), 0),
    'avg_order_value', CASE
      WHEN (
        SELECT COUNT(*) FROM public.orders
        WHERE merchant_id = p_merchant_id
          AND created_at >= p_from
      ) > 0
      THEN ROUND((
        SELECT COALESCE(SUM(total), 0) FROM public.orders
        WHERE merchant_id = p_merchant_id
          AND created_at >= p_from
      )::numeric / (
        SELECT COUNT(*) FROM public.orders
        WHERE merchant_id = p_merchant_id
          AND created_at >= p_from
      ), 2)
      ELSE 0
    END
  );
$$;


--
-- Name: get_merchant_review_summary(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_merchant_review_summary(p_merchant_id uuid) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_average_rating NUMERIC;
  v_total_count BIGINT;
  v_distribution JSON;
BEGIN
  SELECT
    COALESCE(ROUND(AVG(merchant_rating)::NUMERIC, 1), 0.0),
    COUNT(*),
    JSON_BUILD_ARRAY(
      COUNT(*) FILTER (WHERE merchant_rating = 1),
      COUNT(*) FILTER (WHERE merchant_rating = 2),
      COUNT(*) FILTER (WHERE merchant_rating = 3),
      COUNT(*) FILTER (WHERE merchant_rating = 4),
      COUNT(*) FILTER (WHERE merchant_rating = 5)
    )
  INTO v_average_rating, v_total_count, v_distribution
  FROM public.reviews
  WHERE merchant_id = p_merchant_id
    AND is_visible = TRUE;

  RETURN JSON_BUILD_OBJECT(
    'average_rating', v_average_rating,
    'total_count', v_total_count,
    'distribution', v_distribution
  );
END;
$$;


--
-- Name: FUNCTION get_merchant_review_summary(p_merchant_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.get_merchant_review_summary(p_merchant_id uuid) IS 'F-18: Computes aggregated rating average, count, and star distribution for a merchant in one server-side query.';


--
-- Name: get_platform_config(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_platform_config(p_key text) RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  v_value TEXT;
BEGIN
  SELECT value INTO v_value
  FROM public.platform_config
  WHERE key = p_key;

  RETURN v_value;
END;
$$;


--
-- Name: FUNCTION get_platform_config(p_key text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.get_platform_config(p_key text) IS 'Helper: fetches a platform_config value by key. Returns NULL if key not found.';


--
-- Name: get_search_analytics_summary(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_search_analytics_summary(p_days integer DEFAULT 7) RETURNS json
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_from TIMESTAMPTZ;
  v_volume BIGINT := 0;
  v_top JSON := '[]'::json;
  v_zero JSON := '[]'::json;
  v_suggest JSON := '[]'::json;
BEGIN
  IF p_days IS NULL OR p_days < 1 OR p_days > 90 THEN
    RAISE EXCEPTION 'INVALID_DAYS';
  END IF;
  v_from := now() - (p_days::text || ' days')::interval;

  SELECT COUNT(*) INTO v_volume
    FROM public.search_queries
   WHERE created_at >= v_from;

  -- Top successful queries (exact spelling as typed, spelling variants differ)
  SELECT COALESCE(json_agg(t ORDER BY t.c DESC, t.query ASC), '[]'::json) INTO v_top
    FROM (
      SELECT sq.query, COUNT(*)::int AS c,
             ROUND(AVG(sq.merchant_results)::numeric, 1) AS avg_merchant_results,
             ROUND(AVG(sq.item_results)::numeric, 1) AS avg_item_results
        FROM public.search_queries sq
       WHERE sq.created_at >= v_from AND sq.has_results
       GROUP BY sq.query
       ORDER BY c DESC, sq.query ASC
       LIMIT 20
    ) t;

  -- Top zero-result queries (catalog/merchandising signal)
  SELECT COALESCE(json_agg(t ORDER BY t.c DESC, t.query ASC), '[]'::json) INTO v_zero
    FROM (
      SELECT sq.query, COUNT(*)::int AS c
        FROM public.search_queries sq
       WHERE sq.created_at >= v_from AND NOT sq.has_results
       GROUP BY sq.query
       ORDER BY c DESC, sq.query ASC
       LIMIT 20
    ) t;

  -- Suggestion candidates: successful queries deduped on normalized form
  SELECT COALESCE(json_agg(t ORDER BY t.c DESC, t.query ASC), '[]'::json) INTO v_suggest
    FROM (
      SELECT MIN(sq.query) AS query, SUM(sq.c)::int AS c
        FROM (
          SELECT sq.normalized_query, sq.query, COUNT(*)::int AS c
            FROM public.search_queries sq
           WHERE sq.created_at >= v_from AND sq.has_results
           GROUP BY sq.normalized_query, sq.query
        ) sq
       GROUP BY sq.normalized_query
       ORDER BY c DESC
       LIMIT 20
    ) t;

  RETURN json_build_object(
    'days', p_days,
    'volume', v_volume,
    'top_queries', v_top,
    'top_zero_result_queries', v_zero,
    'suggestion_candidates', v_suggest
  );
END;
$$;


--
-- Name: FUNCTION get_search_analytics_summary(p_days integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.get_search_analytics_summary(p_days integer) IS 'Search & Discovery MVP (095): aggregate search analytics (top queries, top zero-result, suggestion candidates) over p_days. Aggregate-only output; service_role only.';


--
-- Name: get_stale_online_drivers(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_stale_online_drivers(p_stale_threshold_seconds integer DEFAULT 120) RETURNS TABLE(driver_id uuid, driver_name text, last_location_at timestamp with time zone, seconds_since_update integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
  -- Sprint 2 fix (S10): defense-in-depth — fail closed if a future migration
  -- accidentally widens GRANT to authenticated.
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: get_stale_online_drivers is service-role only.';
  END IF;

  RETURN QUERY
  SELECT
    d.id AS driver_id,
    p.full_name AS driver_name,
    d.last_location_at,
    EXTRACT(EPOCH FROM NOW() - d.last_location_at)::INTEGER AS seconds_since_update
  FROM public.drivers d
  JOIN public.profiles p ON p.id = d.id
  WHERE d.is_online = TRUE
    AND d.is_verified = TRUE
    AND d.is_active = TRUE
    AND (
      d.last_location_at IS NULL
      OR d.last_location_at < NOW() - (p_stale_threshold_seconds || ' seconds')::INTERVAL
    )
  ORDER BY d.last_location_at ASC NULLS FIRST;
END;
$$;


--
-- Name: FUNCTION get_stale_online_drivers(p_stale_threshold_seconds integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.get_stale_online_drivers(p_stale_threshold_seconds integer) IS 'Sprint 2 fix (S10): added in-body service-role check. Finds drivers with stale location data.';


--
-- Name: get_unique_audit_actions(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_unique_audit_actions() RETURNS TABLE(action text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
  RETURN QUERY
  WITH RECURSIVE t AS (
     (SELECT al.action FROM public.audit_logs al ORDER BY al.action LIMIT 1)
     UNION ALL
     SELECT (SELECT al.action FROM public.audit_logs al WHERE al.action > t.action ORDER BY al.action LIMIT 1)
     FROM t
     WHERE t.action IS NOT NULL
  )
  SELECT t.action FROM t WHERE t.action IS NOT NULL;
END;
$$;


--
-- Name: FUNCTION get_unique_audit_actions(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.get_unique_audit_actions() IS 'Retrieve unique audit log action types efficiently via loose index scan emulation.';


--
-- Name: handle_after_address_delete(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_after_address_delete() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_new_default_id UUID;
BEGIN
  -- If the deleted address was the default one
  IF OLD.is_default THEN
    -- Find the most recently updated address for the same user
    SELECT id INTO v_new_default_id
    FROM public.addresses
    WHERE user_id = OLD.user_id
    ORDER BY updated_at DESC, created_at DESC
    LIMIT 1;

    -- If another address exists, set it as default
    IF v_new_default_id IS NOT NULL THEN
      UPDATE public.addresses
      SET is_default = TRUE
      WHERE id = v_new_default_id;
    END IF;
  END IF;
  RETURN OLD;
END;
$$;


--
-- Name: FUNCTION handle_after_address_delete(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.handle_after_address_delete() IS 'Promotes another address to default when the current default address is deleted.';


--
-- Name: handle_new_user(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, avatar_url, preferred_language)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', ''),
    COALESCE(NEW.raw_user_meta_data->>'avatar_url', ''),
    COALESCE(NEW.raw_user_meta_data->>'preferred_language', 'ar')
  );
  RETURN NEW;
END;
$$;


--
-- Name: FUNCTION handle_new_user(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.handle_new_user() IS 'Security-critical: Auto-creates a profiles row with role=customer on every new auth.users insert. Prevents unauthenticated role escalation.';


--
-- Name: increment_driver_declines(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.increment_driver_declines(p_driver_id uuid) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_new_count INTEGER;
BEGIN
  -- SECURITY: Service-role only. Prevents any authenticated user from
  -- calling this RPC directly to inflate their own or others' decline count.
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: increment_driver_declines is service-role only.';
  END IF;

  -- Atomic conditional increment. Returns the new value, or NULL if the
  -- driver row doesn't exist (caller should handle, but in practice the EF
  -- already verified the driver via requireVerifiedDriver).
  UPDATE public.drivers
    SET consecutive_declines = COALESCE(consecutive_declines, 0) + 1
    WHERE id = p_driver_id
    RETURNING consecutive_declines INTO v_new_count;

  RETURN v_new_count;
END;
$$;


--
-- Name: FUNCTION increment_driver_declines(p_driver_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.increment_driver_declines(p_driver_id uuid) IS 'A4-G2: Atomic consecutive_declines increment. SECURITY DEFINER, service-role only, hardened with SET search_path = "". Returns the new count so the caller can apply 3-strike suspension. See migration 062.';


--
-- Name: increment_driver_stats(uuid, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.increment_driver_stats(p_driver_id uuid, p_earnings_amount numeric) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
  -- SECURITY: Service-role only. Prevents any authenticated user from
  -- calling this RPC directly to corrupt driver delivery counts or earnings.
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: increment_driver_stats is service-role only.';
  END IF;

  UPDATE public.drivers
  SET
    total_deliveries = COALESCE(total_deliveries, 0) + 1,
    total_earnings = COALESCE(total_earnings, 0) + p_earnings_amount
  WHERE id = p_driver_id;
END;
$$;


--
-- Name: FUNCTION increment_driver_stats(p_driver_id uuid, p_earnings_amount numeric); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.increment_driver_stats(p_driver_id uuid, p_earnings_amount numeric) IS 'Atomic driver stats increment. SECURITY DEFINER, service-role only, hardened with SET search_path = "". See migration 044.';


--
-- Name: increment_promo_usage(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.increment_promo_usage(p_promo_code_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
  -- SECURITY: Service-role only. Prevents any authenticated user from
  -- calling this RPC directly to inflate promo usage counts.
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: increment_promo_usage is service-role only.';
  END IF;

  UPDATE public.promo_codes
  SET current_usage = COALESCE(current_usage, 0) + 1
  WHERE id = p_promo_code_id;
END;
$$;


--
-- Name: FUNCTION increment_promo_usage(p_promo_code_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.increment_promo_usage(p_promo_code_id uuid) IS 'Atomic promo-code usage increment. SECURITY DEFINER, service-role only, hardened with SET search_path = "". See migration 044.';


--
-- Name: increment_promoted_slot_clicks(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.increment_promoted_slot_clicks(p_slot_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
  UPDATE public.promoted_slots
  SET clicks = clicks + 1
  WHERE id = p_slot_id;
END;
$$;


--
-- Name: FUNCTION increment_promoted_slot_clicks(p_slot_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.increment_promoted_slot_clicks(p_slot_id uuid) IS 'P1-6: Increment cumulative clicks counter for a single slot. Called from the track-click endpoint.';


--
-- Name: increment_promoted_slot_impressions(uuid[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.increment_promoted_slot_impressions(p_slot_ids uuid[]) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
  UPDATE public.promoted_slots
  SET impressions = impressions + 1
  WHERE id = ANY(p_slot_ids);
END;
$$;


--
-- Name: FUNCTION increment_promoted_slot_impressions(p_slot_ids uuid[]); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.increment_promoted_slot_impressions(p_slot_ids uuid[]) IS 'P1-6: Increment cumulative impressions counter for the given slot IDs. Called fire-and-forget from get-merchant-feed EF.';


--
-- Name: invalidate_all_admin_sessions(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.invalidate_all_admin_sessions(p_admin_id uuid) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_count INTEGER;
BEGIN
  UPDATE public.admin_sessions
  SET invalidated_at = NOW(),
      invalidation_reason = 'admin_force'
  WHERE admin_id = p_admin_id
    AND invalidated_at IS NULL;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;


--
-- Name: FUNCTION invalidate_all_admin_sessions(p_admin_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.invalidate_all_admin_sessions(p_admin_id uuid) IS 'Invalidates all active sessions for an admin. Used for "logout everywhere" feature.';


--
-- Name: invoke_edge_function(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.invoke_edge_function(p_function_name text, p_payload jsonb DEFAULT '{}'::jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
  v_project_url text;
  v_service_role_key text;
  v_url text;
  v_headers jsonb;
BEGIN
  -- 1. Resolve project URL from Vault
  SELECT decrypted_secret INTO v_project_url
  FROM vault.decrypted_secrets
  WHERE name = 'project_url';
  
  -- If not set, default to local Kong gateway inside the Docker network
  IF v_project_url IS NULL OR v_project_url = '' THEN
    v_project_url := 'http://kong:8000';
  END IF;

  v_url := v_project_url || '/functions/v1/' || p_function_name;

  -- 2. Resolve service role key from Vault
  SELECT decrypted_secret INTO v_service_role_key
  FROM vault.decrypted_secrets
  WHERE name = 'service_role_key';

  -- 3. Construct headers
  v_headers := jsonb_build_object(
    'Content-Type', 'application/json'
  );
  
  IF v_service_role_key IS NOT NULL AND v_service_role_key <> '' THEN
    v_headers := v_headers || jsonb_build_object('Authorization', 'Bearer ' || v_service_role_key);
  END IF;

  -- 4. Invoke the Edge Function via pg_net
  PERFORM net.http_post(
    url := v_url,
    headers := v_headers,
    body := p_payload
  );
END;
$$;


--
-- Name: FUNCTION invoke_edge_function(p_function_name text, p_payload jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.invoke_edge_function(p_function_name text, p_payload jsonb) IS 'Trigger an Edge Function via pg_net, resolving project_url and service_role_key from Vault.';


--
-- Name: is_merchant_open(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_merchant_open(p_merchant_id uuid) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  v_is_open BOOLEAN;
  v_current_day INTEGER;
  v_current_time TIME;
BEGIN
  -- Get current day of week (ISO: 1=Monday, 7=Sunday)
  v_current_day := EXTRACT(ISODOW FROM NOW() AT TIME ZONE 'Africa/Cairo');

  -- Get current time in Cairo timezone
  v_current_time := (NOW() AT TIME ZONE 'Africa/Cairo')::TIME;

  -- Check if there's an operating hours entry and if current time is within range
  SELECT EXISTS (
    SELECT 1
    FROM public.operating_hours
    WHERE merchant_id = p_merchant_id
      AND day_of_week = v_current_day
      AND is_closed = FALSE
      AND v_current_time >= open_time
      AND v_current_time < close_time
  ) INTO v_is_open;

  RETURN COALESCE(v_is_open, FALSE);
END;
$$;


--
-- Name: FUNCTION is_merchant_open(p_merchant_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.is_merchant_open(p_merchant_id uuid) IS 'P1E-12: Checks if a merchant is currently open based on operating_hours. ⚠️ Do NOT call per-row in feed queries — use SQL EXISTS subquery instead (see RED-01). Use for single-merchant lookups only.';


--
-- Name: log_data_access(uuid, text, text, uuid, text, text, inet, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.log_data_access(p_admin_id uuid, p_action text, p_resource_type text, p_resource_id uuid, p_field_name text DEFAULT NULL::text, p_reason text DEFAULT NULL::text, p_ip_address inet DEFAULT NULL::inet, p_user_agent text DEFAULT NULL::text, p_request_id text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_log_id UUID;
  v_is_flagged BOOLEAN := FALSE;
  v_flag_reason TEXT;
  v_recent_count INTEGER;
BEGIN
  -- Anomaly detection: flag if admin accessed > 100 records in the last hour
  SELECT COUNT(*) INTO v_recent_count
  FROM public.data_access_log
  WHERE admin_id = p_admin_id
    AND action IN ('view', 'reveal', 'export')
    AND created_at > NOW() - INTERVAL '1 hour';

  IF v_recent_count > 100 THEN
    v_is_flagged := TRUE;
    v_flag_reason := 'High volume PII access: ' || v_recent_count || ' records in 1 hour';
  END IF;

  -- Log the access
  INSERT INTO public.data_access_log (
    admin_id, action, resource_type, resource_id,
    field_name, reason, ip_address, user_agent,
    request_id, is_flagged, flag_reason
  ) VALUES (
    p_admin_id, p_action, p_resource_type, p_resource_id,
    p_field_name, p_reason, p_ip_address, p_user_agent,
    p_request_id, v_is_flagged, v_flag_reason
  )
  RETURNING id INTO v_log_id;

  RETURN v_log_id;
END;
$$;


--
-- Name: FUNCTION log_data_access(p_admin_id uuid, p_action text, p_resource_type text, p_resource_id uuid, p_field_name text, p_reason text, p_ip_address inet, p_user_agent text, p_request_id text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.log_data_access(p_admin_id uuid, p_action text, p_resource_type text, p_resource_id uuid, p_field_name text, p_reason text, p_ip_address inet, p_user_agent text, p_request_id text) IS 'Records admin PII access with automatic anomaly detection. Flags admins accessing > 100 records/hour. Called by Edge Functions via service role.';


--
-- Name: mark_driver_settlement_paid(uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mark_driver_settlement_paid(p_settlement_id uuid, p_paid_by uuid, p_payout_reference text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: mark_driver_settlement_paid can only be called by service role.';
  END IF;

  -- Defense-in-depth: payout_reference must be non-empty (gap-analysis §3.2).
  -- Mirrors the validation in mark_merchant_payout_paid (migration 085).
  IF p_payout_reference IS NULL OR trim(p_payout_reference) = '' THEN
    RAISE EXCEPTION 'payout_reference is required to mark a settlement paid'
      USING ERRCODE = 'not_null_violation';
  END IF;

  UPDATE public.driver_settlements
    SET
      status = 'paid',
      paid_at = NOW(),
      paid_by = p_paid_by,
      payout_reference = p_payout_reference,
      updated_at = NOW()
    WHERE id = p_settlement_id AND status IN ('pending', 'approved');
END;
$$;


--
-- Name: FUNCTION mark_driver_settlement_paid(p_settlement_id uuid, p_paid_by uuid, p_payout_reference text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.mark_driver_settlement_paid(p_settlement_id uuid, p_paid_by uuid, p_payout_reference text) IS 'Manually marks a driver settlement as paid. Used when Paymob disbursement is not wired (default) or as a fallback. Idempotent: no-op if already paid. Validates payout_reference is non-empty (defense-in-depth, gap-analysis §3.2). SECURITY DEFINER — service role only.';


--
-- Name: mark_merchant_payout_paid(uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mark_merchant_payout_paid(p_payout_id uuid, p_paid_by uuid, p_payout_reference text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: mark_merchant_payout_paid can only be called by service role.';
  END IF;

  -- Defense-in-depth: payout_reference must be non-empty (gap-analysis §3.2).
  IF p_payout_reference IS NULL OR trim(p_payout_reference) = '' THEN
    RAISE EXCEPTION 'payout_reference is required to mark a payout paid'
      USING ERRCODE = 'not_null_violation';
  END IF;

  UPDATE public.merchant_payouts
    SET
      status = 'paid',
      paid_at = NOW(),
      paid_by = p_paid_by,
      payout_reference = p_payout_reference,
      updated_at = NOW()
    WHERE id = p_payout_id AND status IN ('pending', 'approved');
END;
$$;


--
-- Name: FUNCTION mark_merchant_payout_paid(p_payout_id uuid, p_paid_by uuid, p_payout_reference text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.mark_merchant_payout_paid(p_payout_id uuid, p_paid_by uuid, p_payout_reference text) IS 'Manually marks a merchant payout as paid. Used when Paymob disbursement is not wired (default) or as a fallback. Idempotent: no-op if already paid. Validates payout_reference is non-empty (defense-in-depth, gap-analysis §3.2). SECURITY DEFINER — service role only.';


--
-- Name: mask_national_id(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mask_national_id(p_national_id text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
  IF p_national_id IS NULL THEN RETURN '****'; END IF;
  IF length(p_national_id) < 10 THEN RETURN '****'; END IF;
  RETURN substr(p_national_id, 1, 7) || '****' || substr(p_national_id, -3);
END;
$$;


--
-- Name: FUNCTION mask_national_id(p_national_id text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.mask_national_id(p_national_id text) IS 'Masks a national ID for safe display: 2900101****567. Used by admin panel.';


--
-- Name: normalize_search_text(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.normalize_search_text(p_input text) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
    SET search_path TO 'public', 'extensions'
    AS $$
  SELECT trim(
    regexp_replace(
      translate(
        public.f_unaccent(lower(p_input)),
        'أإآٱةى',
        'ااااهي'
      ),
      '[ًٌٍَُِّْـٰ]',  -- U+064B-0652 harakat, U+0640 tatweel, U+0670 sup alef
      '',
      'g'
    )
  )
$$;


--
-- Name: FUNCTION normalize_search_text(p_input text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.normalize_search_text(p_input text) IS 'Search & Discovery MVP (095): bilingual ar/en normalization — alef/hamza fold, taa marbuta, maqsura, harakat/tatweel/sup-alef strip, Latin accents, lowercase. IMMUTABLE for expression indexes.';


--
-- Name: place_order_with_items(jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.place_order_with_items(p_order jsonb, p_items jsonb) RETURNS TABLE(id uuid, order_number text, created_at timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
DECLARE
  v_order_id UUID;
  v_order_number TEXT;
  v_created_at TIMESTAMPTZ;
  v_item JSONB;
  v_customer_id UUID;
  v_merchant_id UUID;
  v_idempotency_key TEXT;
  v_platform_fee NUMERIC;
  v_platform_fee_pct NUMERIC;
  v_merchant_commission_pct NUMERIC;
  v_max_items INTEGER;
  v_duplicate_threshold_seconds INTEGER;
  v_item_count INTEGER;
  v_promo_code_id UUID;
  v_promo_max_usage INTEGER;
  v_promo_max_usage_per_user INTEGER;
  v_user_usage_count INTEGER;
  v_new_usage INTEGER;
  v_customer_ip INET;
  v_fraud_count INTEGER;
  -- S1: New variables for funded_by payout computation
  v_subtotal NUMERIC(10,2);
  v_discount_amount NUMERIC(10,2);
  v_commission_pct_resolved NUMERIC(5,2);
  v_promo_funded_by TEXT;
  v_promo_merchant_share_pct NUMERIC(5,2);
  v_merchant_discount_floor NUMERIC(10,2);
  v_merchant_discount_share NUMERIC(10,2);
  v_merchant_payout NUMERIC(10,2);
BEGIN
  -- =====================================================================
  -- SECURITY: Verify service role
  -- =====================================================================
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: place_order_with_items is service-role only.';
  END IF;

  -- =====================================================================
  -- INPUT VALIDATION
  -- =====================================================================
  v_customer_id := (p_order->>'customer_id')::UUID;
  v_merchant_id := (p_order->>'merchant_id')::UUID;
  v_idempotency_key := p_order->>'idempotency_key';

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_customer_id) THEN
    RAISE EXCEPTION 'Customer not found';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.merchants WHERE id = v_merchant_id AND is_active = TRUE) THEN
    RAISE EXCEPTION 'Merchant not found or inactive';
  END IF;

  v_item_count := jsonb_array_length(p_items);
  IF v_item_count = 0 THEN
    RAISE EXCEPTION 'Order must have at least one item';
  END IF;

  SELECT COALESCE(
    (SELECT value::INTEGER FROM public.platform_config WHERE key = 'max_items_per_order'),
    50
  ) INTO v_max_items;

  IF v_item_count > v_max_items THEN
    RAISE EXCEPTION 'Order exceeds maximum items limit of %', v_max_items;
  END IF;

  -- =====================================================================
  -- DUPLICATE ORDER CHECK
  -- =====================================================================
  SELECT COALESCE(
    (SELECT value::INTEGER FROM public.platform_config WHERE key = 'order_duplicate_threshold_seconds'),
    10
  ) INTO v_duplicate_threshold_seconds;

  IF v_idempotency_key IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM public.orders
      WHERE idempotency_key = v_idempotency_key
    ) THEN
      RAISE EXCEPTION 'Duplicate order (idempotency key)';
    END IF;
  ELSE
    IF EXISTS (
      SELECT 1 FROM public.orders
      WHERE customer_id = v_customer_id
        AND merchant_id = v_merchant_id
        AND created_at > NOW() - (v_duplicate_threshold_seconds || ' seconds')::INTERVAL
        AND status != 'cancelled'
    ) THEN
      RAISE EXCEPTION 'Duplicate order (recent similar order)';
    END IF;
  END IF;

  -- =====================================================================
  -- FETCH PLATFORM CONFIG FOR FEES
  -- =====================================================================
  SELECT COALESCE(
    (SELECT value::NUMERIC FROM public.platform_config WHERE key = 'platform_fee'),
    3.00
  ) INTO v_platform_fee;

  SELECT COALESCE(
    (SELECT value::NUMERIC FROM public.platform_config WHERE key = 'platform_fee_percentage'),
    0
  ) INTO v_platform_fee_pct;

  SELECT COALESCE(
    (SELECT value::NUMERIC FROM public.platform_config WHERE key = 'default_commission_pct'),
    15.00
  ) INTO v_merchant_commission_pct;

  -- S1: Fetch configurable merchant discount floor from platform_config.
  -- When funded_by='shared' and discount_amount <= this floor, the platform
  -- absorbs 100% (merchant_share becomes 0). Default 0 = disabled.
  SELECT COALESCE(
    (SELECT value::NUMERIC FROM public.platform_config WHERE key = 'merchant_discount_floor'),
    0
  ) INTO v_merchant_discount_floor;

  -- =====================================================================
  -- S1: COMPUTE MERCHANT PAYOUT (funded_by logic)
  -- =====================================================================
  v_subtotal := COALESCE((p_order->>'subtotal')::NUMERIC, 0);
  v_discount_amount := COALESCE((p_order->>'discount_amount')::NUMERIC, 0);

  -- Resolve commission: merchant-specific if set, else platform default
  v_commission_pct_resolved := COALESCE(
    (SELECT commission_pct FROM public.merchants WHERE id = v_merchant_id),
    v_merchant_commission_pct
  );

  -- Default: no promo funding info
  v_promo_funded_by := NULL;
  v_promo_merchant_share_pct := NULL;
  v_merchant_discount_share := 0;

  -- If a promo is applied, lock the row and read funding model + limits
  -- in a single query. The lock is held until transaction commit, which
  -- also covers the atomic usage enforcement below (no second SELECT needed).
  IF p_order->>'promo_code_id' IS NOT NULL THEN
    v_promo_code_id := (p_order->>'promo_code_id')::UUID;

    SELECT funded_by, merchant_share_pct, max_usage, max_usage_per_user
      INTO v_promo_funded_by, v_promo_merchant_share_pct, v_promo_max_usage, v_promo_max_usage_per_user
      FROM public.promo_codes
      WHERE id = v_promo_code_id
      FOR UPDATE;

    -- Compute merchant's share of the discount based on funding model
    IF v_discount_amount > 0 THEN
      v_merchant_discount_share := CASE
        -- Platform absorbs 100%
        WHEN v_promo_funded_by = 'platform' THEN 0
        -- Merchant absorbs 100%
        WHEN v_promo_funded_by = 'merchant' THEN v_discount_amount
        -- Shared: split by merchant_share_pct, but apply floor
        WHEN v_promo_funded_by = 'shared' THEN
          CASE
            -- Floor check: if discount <= floor, platform absorbs all
            WHEN v_discount_amount <= v_merchant_discount_floor THEN 0
            ELSE ROUND(
              v_discount_amount * COALESCE(v_promo_merchant_share_pct, 50) / 100,
              2
            )
          END
        ELSE 0
      END;
    END IF;
  END IF;

  -- merchant_payout = (subtotal - merchant's discount share) × (1 - commission%)
  -- This replaces the old GENERATED formula which was simply:
  --   subtotal - (subtotal * commission_pct / 100)
  -- The old formula completely ignored discounts.
  v_merchant_payout := ROUND(
    (v_subtotal - v_merchant_discount_share) *
    (1 - v_commission_pct_resolved / 100),
    2
  );

  -- Safety: never allow negative payout
  IF v_merchant_payout < 0 THEN
    v_merchant_payout := 0;
  END IF;

  -- =====================================================================
  -- INSERT ORDER
  -- =====================================================================
  INSERT INTO public.orders (
    customer_id, merchant_id, status, delivery_address,
    subtotal, delivery_fee, platform_fee, discount_amount, total,
    payment_method, payment_status, promo_code_id, promo_code,
    distance_km, estimated_delivery_minutes, idempotency_key,
    merchant_commission_pct, paymob_order_id, notes,
    customer_phone, scheduled_time,
    -- S1: New columns
    promo_funded_by, promo_merchant_share_pct, merchant_payout
  ) VALUES (
    v_customer_id,
    v_merchant_id,
    COALESCE(p_order->>'status', 'pending'),
    p_order->'delivery_address',
    COALESCE((p_order->>'subtotal')::NUMERIC, 0),
    COALESCE((p_order->>'delivery_fee')::NUMERIC, 0),
    CASE
      WHEN v_platform_fee_pct > 0 THEN
        ROUND(COALESCE((p_order->>'subtotal')::NUMERIC, 0) * v_platform_fee_pct / 100, 2)
      ELSE v_platform_fee
    END,
    COALESCE((p_order->>'discount_amount')::NUMERIC, 0),
    COALESCE((p_order->>'total')::NUMERIC, 0),
    p_order->>'payment_method',
    COALESCE(p_order->>'payment_status', 'pending'),
    CASE WHEN p_order->>'promo_code_id' IS NOT NULL THEN (p_order->>'promo_code_id')::UUID ELSE NULL END,
    p_order->>'promo_code',
    COALESCE((p_order->>'distance_km')::NUMERIC, 0),
    COALESCE((p_order->>'estimated_delivery_minutes')::INTEGER, 30),
    v_idempotency_key,
    v_commission_pct_resolved,
    p_order->>'paymob_order_id',
    p_order->>'notes',
    p_order->>'customer_phone',
    CASE WHEN p_order->>'scheduled_time' IS NOT NULL THEN (p_order->>'scheduled_time')::TIMESTAMPTZ ELSE NULL END,
    -- S1: Snapshot promo funding model + computed payout
    v_promo_funded_by,
    v_promo_merchant_share_pct,
    v_merchant_payout
  )
  RETURNING id, order_number, created_at
  INTO v_order_id, v_order_number, v_created_at;

  -- =====================================================================
  -- INSERT ORDER ITEMS (atomically)
  -- =====================================================================
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    INSERT INTO public.order_items (
      order_id, item_id, item_name_ar, item_name_en,
      item_price, quantity, total_price,
      selected_options, special_instructions
    ) VALUES (
      v_order_id,
      (v_item->>'item_id')::UUID,
      v_item->>'item_name_ar',
      v_item->>'item_name_en',
      COALESCE((v_item->>'item_price')::NUMERIC, 0),
      COALESCE((v_item->>'quantity')::INTEGER, 1),
      COALESCE((v_item->>'total_price')::NUMERIC, 0),
      COALESCE(v_item->'selected_options', '[]'::JSONB),
      v_item->>'special_instructions'
    );
  END LOOP;

  -- =====================================================================
  -- TRACK PROMO CODE USAGE — ATOMICALLY ENFORCED
  -- =====================================================================
  -- Both the global max_usage and per-user max_usage_per_user limits are
  -- enforced at the SQL level here, not just in the Edge Function. The
  -- Edge Function's TS check is advisory (early rejection for UX); this
  -- block is authoritative (eliminates the TOCTOU window).
  -- NOTE: The promo row was already locked by the FOR UPDATE in the payout
  -- block above, so no additional SELECT ... FOR UPDATE is needed here.
  IF p_order->>'promo_code_id' IS NOT NULL THEN
    -- Parse customer_ip for fraud detection (optional, from migration 075)
    IF p_order->>'customer_ip' IS NOT NULL THEN
      v_customer_ip := (p_order->>'customer_ip')::INET;
    ELSE
      v_customer_ip := NULL;
    END IF;

    -- Atomic conditional increment — fails if already at global limit.
    UPDATE public.promo_codes
      SET current_usage = current_usage + 1
      WHERE id = v_promo_code_id
        AND current_usage < v_promo_max_usage
      RETURNING current_usage INTO v_new_usage;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Promo code % has reached its global usage limit', v_promo_code_id
        USING ERRCODE = 'check_violation';
    END IF;

    -- Count this user's existing usage (after the increment above, this
    -- transaction hasn't yet inserted the new row).
    SELECT COUNT(*) INTO v_user_usage_count
      FROM public.promo_code_usage
      WHERE promo_code_id = v_promo_code_id AND user_id = v_customer_id;

    IF v_user_usage_count >= v_promo_max_usage_per_user THEN
      RAISE EXCEPTION 'Promo code % has reached its per-user usage limit for user %',
        v_promo_code_id, v_customer_id
        USING ERRCODE = 'check_violation';
    END IF;

    -- Record per-user usage (with ip_address for fraud detection, from 075).
    INSERT INTO public.promo_code_usage (promo_code_id, user_id, order_id, discount_amount, ip_address)
    VALUES (
      v_promo_code_id,
      v_customer_id,
      v_order_id,
      COALESCE((p_order->>'discount_amount')::NUMERIC, 0),
      v_customer_ip
    );

    -- Fire-and-forget fraud check. The result is not checked —
    -- fraud detection is async and inserts an alert_incident if needed.
    -- Wrapped in a BEGIN/EXCEPTION so a fraud-check failure never breaks
    -- the order placement.
    IF v_customer_ip IS NOT NULL THEN
      BEGIN
        SELECT public.check_promo_fraud(v_promo_code_id, v_customer_ip) INTO v_fraud_count;
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Promo fraud check failed for promo % IP %: %', v_promo_code_id, v_customer_ip, SQLERRM;
      END;
    END IF;
  END IF;

  -- =====================================================================
  -- RETURN THE CREATED ORDER DATA
  -- =====================================================================
  RETURN QUERY SELECT v_order_id AS id, v_order_number AS order_number, v_created_at AS created_at;
END;
$$;


--
-- Name: FUNCTION place_order_with_items(p_order jsonb, p_items jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.place_order_with_items(p_order jsonb, p_items jsonb) IS 'Hardened atomic order creation. SECURITY DEFINER, service-role only. Migration 045: atomic per-user and global promo usage enforcement. Migration 049: scheduled_time persistence. Migration 075: customer_ip tracking + check_promo_fraud(). Migration 080: funded_by payout computation — merchant_payout now accounts for promo discount funding model (platform/merchant/shared) with configurable merchant_discount_floor from platform_config.';


--
-- Name: prevent_audit_log_delete(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_audit_log_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'audit_logs rows cannot be deleted — they are permanent';
  RETURN NULL;
END;
$$;


--
-- Name: prevent_audit_log_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_audit_log_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'audit_logs rows cannot be updated — they are immutable';
  RETURN NULL;
END;
$$;


--
-- Name: prevent_driver_role_escalation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_driver_role_escalation() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
  IF NEW.role = 'driver' THEN
    IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role'
       AND current_setting('app.allow_driver_role_change', true) IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Role escalation blocked: users cannot set role to driver. Use admin-create-driver Edge Function instead.'
        USING HINT = 'Driver accounts must be created by admin via the admin-create-driver API. '
                     'Trusted migrations may set app.allow_driver_role_change=true to bypass.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: FUNCTION prevent_driver_role_escalation(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.prevent_driver_role_escalation() IS 'Sprint 2 fix (S15): now also blocks when request.jwt.claims is unset (was an escape hatch for DB-level ops). Trusted migrations can set app.allow_driver_role_change=true to bypass.';


--
-- Name: prune_search_queries(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prune_search_queries() RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_deleted BIGINT;
BEGIN
  DELETE FROM public.search_queries
   WHERE created_at < now() - interval '180 days';
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;


--
-- Name: FUNCTION prune_search_queries(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.prune_search_queries() IS 'Search & Discovery MVP (095): deletes search_queries rows older than 180 days. Scheduled daily 03:15 UTC as search-queries-retention.';


--
-- Name: refresh_merchant_open_status(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.refresh_merchant_open_status() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY public.merchants_with_open_status;
END;
$$;


--
-- Name: FUNCTION refresh_merchant_open_status(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.refresh_merchant_open_status() IS 'Concurrently refreshes the merchants_with_open_status materialized view. Safe to call while reads are happening.';


--
-- Name: rls_auto_enable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rls_auto_enable() RETURNS event_trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog'
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;


--
-- Name: search_catalog(text, text, text, numeric, numeric, integer, integer, boolean, numeric, uuid, boolean, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.search_catalog(p_query text, p_city text DEFAULT NULL::text, p_category text DEFAULT NULL::text, p_lat numeric DEFAULT NULL::numeric, p_lng numeric DEFAULT NULL::numeric, p_limit_merchants integer DEFAULT 20, p_limit_items integer DEFAULT 10, p_include_items boolean DEFAULT true, p_fuzzy_threshold numeric DEFAULT 0.30, p_merchant_id uuid DEFAULT NULL::uuid, p_include_suggestions boolean DEFAULT true, p_suggestion_max integer DEFAULT 8) RETURNS json
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_norm TEXT;
  v_like TEXT;     -- escaped, bounded by %..%  (exact pass)
  v_prefix TEXT;   -- escaped, trailing wildcard (suggestions)
  v_bbox BOOLEAN := p_lat IS NOT NULL AND p_lng IS NOT NULL;
  v_merchants JSON := '[]'::json;
  v_items JSON := '[]'::json;
  v_suggestions JSON := '[]'::json;
  v_fuzzy_used BOOLEAN := FALSE;
  v_fuzzy_top TEXT := NULL;
BEGIN
  -- ── Guards (mirror validateSearchRequest; the EF validates first) ──
  IF p_query IS NULL OR length(trim(p_query)) < 2 OR length(trim(p_query)) > 80 THEN
    RAISE EXCEPTION 'INVALID_QUERY';
  END IF;
  v_norm := public.normalize_search_text(p_query);
  IF v_norm IS NULL OR v_norm = '' THEN
    RAISE EXCEPTION 'INVALID_QUERY';
  END IF;

  -- LIKE wildcard escaping: the query is user-controlled text; % and _ must
  -- match literally (the feed escapes PostgREST filter syntax for the same
  -- reason). Bound parameters prevent injection; this prevents wildcard
  -- blowout (e.g. "a%b" matching every name containing a…b).
  v_like := '%' || replace(replace(replace(v_norm, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  v_prefix := replace(replace(replace(v_norm, '\', '\\'), '%', '\%'), '_', '\_') || '%';

  -- ── Clamp arguments to plan hard limits ──
  p_limit_merchants := LEAST(GREATEST(COALESCE(p_limit_merchants, 20), 1), 30);
  p_limit_items := LEAST(GREATEST(COALESCE(p_limit_items, 0), 0), 20);
  p_suggestion_max := LEAST(GREATEST(COALESCE(p_suggestion_max, 0), 0), 20);
  p_category := NULLIF(p_category, 'all');

  -- ── Merchant exact pass ──
  SELECT COALESCE(json_agg(x ORDER BY x.created_at DESC), '[]'::json)
    INTO v_merchants
    FROM (
      SELECT b.id, b.name_ar, b.name_en, b.category, b.logo_url, b.cover_url,
             b.description_ar, b.description_en, b.address, b.lat, b.lng,
             b.city, b.area, b.phone, b.is_active, b.rating, b.rating_count,
             b.min_order_amount, b.estimated_delivery_minutes,
             b.delivery_fee_override, b.commission_pct, b.delivery_radius_km,
             b.estimated_prep_time_minutes, b.created_at, b.updated_at,
             'exact'::text AS match_tier
        FROM (
          SELECT m.*
            FROM public.merchants m
           WHERE m.is_active
             AND (
               (v_bbox AND m.lat BETWEEN p_lat - 0.45 AND p_lat + 0.45
                                   AND m.lng BETWEEN p_lng - 0.52 AND p_lng + 0.52)
               OR (NOT v_bbox AND p_city IS NOT NULL AND m.city ILIKE p_city)
               OR (NOT v_bbox AND p_city IS NULL)
             )
              AND (p_category IS NULL OR m.category = p_category)
              AND (p_merchant_id IS NULL OR m.id = p_merchant_id)
              -- Word-AND over combined normalized names: every query word must
              -- appear somewhere (name_ar or name_en). Plain substring cannot
              -- match description-style queries; combined word-AND can.
              AND NOT EXISTS (
                SELECT 1 FROM unnest(string_to_array(v_norm, ' ')) AS w
                 WHERE w <> ''
                   AND (COALESCE(public.normalize_search_text(m.name_en), '') || ' ' ||
                        COALESCE(public.normalize_search_text(m.name_ar), ''))
                       NOT ILIKE '%' || REPLACE(REPLACE(REPLACE(w, '\', '\\'), '%', '\%'), '_', '\_') || '%' ESCAPE '\'
              )
            ORDER BY m.created_at DESC
            LIMIT p_limit_merchants
         ) b
     ) x;

  -- ── Item exact pass (inherits geo/category gates from parent merchant) ──
  IF p_include_items AND p_limit_items > 0 THEN
    SELECT COALESCE(json_agg(x ORDER BY x.popularity_score DESC, x.created_at DESC), '[]'::json)
      INTO v_items
      FROM (
        SELECT b.id, b.merchant_id, b.name_ar, b.name_en, b.price, b.image_url,
               b.popularity_score, b.created_at, 'exact'::text AS match_tier,
               b.merchant_name_ar, b.merchant_name_en,
               b.merchant_lat, b.merchant_lng,
               b.merchant_delivery_radius_km, b.merchant_city
          FROM (
            SELECT i.id, i.merchant_id, i.name_ar, i.name_en, i.price,
                   i.image_url, i.popularity_score, i.created_at,
                   m.name_ar AS merchant_name_ar, m.name_en AS merchant_name_en,
                   m.lat AS merchant_lat, m.lng AS merchant_lng,
                   m.delivery_radius_km AS merchant_delivery_radius_km,
                   m.city AS merchant_city
              FROM public.items i
              JOIN public.merchants m ON m.id = i.merchant_id AND m.is_active
             WHERE i.is_available
               AND (
                 (v_bbox AND m.lat BETWEEN p_lat - 0.45 AND p_lat + 0.45
                                     AND m.lng BETWEEN p_lng - 0.52 AND p_lng + 0.52)
                 OR (NOT v_bbox AND p_city IS NOT NULL AND m.city ILIKE p_city)
                 OR (NOT v_bbox AND p_city IS NULL)
               )
                AND (p_category IS NULL OR m.category = p_category)
                AND (p_merchant_id IS NULL OR m.id = p_merchant_id)
                -- Word-AND over combined normalized name+description: every
                -- query word must appear somewhere (names or descriptions).
                -- Lets description-only queries match (name carries the
                -- marker word, description carries the dish word).
                AND NOT EXISTS (
                  SELECT 1 FROM unnest(string_to_array(v_norm, ' ')) AS w
                   WHERE w <> ''
                     AND (COALESCE(public.normalize_search_text(i.name_en), '') || ' ' ||
                          COALESCE(public.normalize_search_text(i.name_ar), '') || ' ' ||
                          COALESCE(public.normalize_search_text(COALESCE(i.description_en, '')), '') || ' ' ||
                          COALESCE(public.normalize_search_text(COALESCE(i.description_ar, '')), ''))
                         NOT ILIKE '%' || REPLACE(REPLACE(REPLACE(w, '\', '\\'), '%', '\%'), '_', '\_') || '%' ESCAPE '\'
                )
              ORDER BY i.popularity_score DESC, i.created_at DESC
              LIMIT p_limit_items
           ) b
       ) x;
   END IF;

  -- ── Fuzzy pass: ONLY on zero exact rows, ONLY when enabled ──
  IF json_array_length(v_merchants) = 0 AND json_array_length(v_items) = 0
     AND COALESCE(p_fuzzy_threshold, 0) > 0 THEN

    -- Fuzzy merchants, best similarity first.
    SELECT COALESCE(json_agg(x ORDER BY x.sim DESC, x.rating_count DESC), '[]'::json)
      INTO v_merchants
      FROM (
        SELECT b.id, b.name_ar, b.name_en, b.category, b.logo_url, b.cover_url,
               b.description_ar, b.description_en, b.address, b.lat, b.lng,
               b.city, b.area, b.phone, b.is_active, b.rating, b.rating_count,
               b.min_order_amount, b.estimated_delivery_minutes,
               b.delivery_fee_override, b.commission_pct, b.delivery_radius_km,
               b.estimated_prep_time_minutes, b.created_at, b.updated_at,
               'fuzzy'::text AS match_tier, b.sim
          FROM (
            SELECT m.*,
                   GREATEST(
                     similarity(public.normalize_search_text(m.name_en), v_norm),
                     similarity(public.normalize_search_text(m.name_ar), v_norm)
                   ) AS sim
              FROM public.merchants m
             WHERE m.is_active
               AND (
                 (v_bbox AND m.lat BETWEEN p_lat - 0.45 AND p_lat + 0.45
                                     AND m.lng BETWEEN p_lng - 0.52 AND p_lng + 0.52)
                 OR (NOT v_bbox AND p_city IS NOT NULL AND m.city ILIKE p_city)
                 OR (NOT v_bbox AND p_city IS NULL)
               )
               AND (p_category IS NULL OR m.category = p_category)
               AND (p_merchant_id IS NULL OR m.id = p_merchant_id)
               AND GREATEST(
                     similarity(public.normalize_search_text(m.name_en), v_norm),
                     similarity(public.normalize_search_text(m.name_ar), v_norm)
                   ) >= p_fuzzy_threshold
             ORDER BY sim DESC
             LIMIT p_limit_merchants
          ) b
      ) x;

    IF json_array_length(v_merchants) > 0 THEN
      v_fuzzy_used := TRUE;
      -- did-you-mean = display name of the best fuzzy merchant.
      SELECT (v_merchants -> 0 ->> 'name_en') INTO v_fuzzy_top;
    ELSE
      -- Fuzzy items (same structure; name OR description similarity).
      SELECT COALESCE(json_agg(x ORDER BY x.sim DESC, x.popularity_score DESC), '[]'::json)
        INTO v_items
        FROM (
          SELECT b.id, b.merchant_id, b.name_ar, b.name_en, b.price, b.image_url,
                 b.popularity_score, b.created_at, 'fuzzy'::text AS match_tier,
                 b.merchant_name_ar, b.merchant_name_en,
                 b.merchant_lat, b.merchant_lng,
                 b.merchant_delivery_radius_km, b.merchant_city, b.sim
            FROM (
              SELECT i.id, i.merchant_id, i.name_ar, i.name_en, i.price,
                     i.image_url, i.popularity_score, i.created_at,
                     m.name_ar AS merchant_name_ar, m.name_en AS merchant_name_en,
                     m.lat AS merchant_lat, m.lng AS merchant_lng,
                     m.delivery_radius_km AS merchant_delivery_radius_km,
                     m.city AS merchant_city,
                     GREATEST(
                       similarity(public.normalize_search_text(i.name_en), v_norm),
                       similarity(public.normalize_search_text(i.name_ar), v_norm),
                       similarity(public.normalize_search_text(COALESCE(i.description_en, '')), v_norm),
                       similarity(public.normalize_search_text(COALESCE(i.description_ar, '')), v_norm)
                     ) AS sim
                FROM public.items i
                JOIN public.merchants m ON m.id = i.merchant_id AND m.is_active
               WHERE i.is_available
                 AND (
                   (v_bbox AND m.lat BETWEEN p_lat - 0.45 AND p_lat + 0.45
                                       AND m.lng BETWEEN p_lng - 0.52 AND p_lng + 0.52)
                   OR (NOT v_bbox AND p_city IS NOT NULL AND m.city ILIKE p_city)
                   OR (NOT v_bbox AND p_city IS NULL)
                 )
                 AND (p_category IS NULL OR m.category = p_category)
                 AND (p_merchant_id IS NULL OR m.id = p_merchant_id)
                 AND GREATEST(
                       similarity(public.normalize_search_text(i.name_en), v_norm),
                       similarity(public.normalize_search_text(i.name_ar), v_norm),
                       similarity(public.normalize_search_text(COALESCE(i.description_en, '')), v_norm),
                       similarity(public.normalize_search_text(COALESCE(i.description_ar, '')), v_norm)
                     ) >= p_fuzzy_threshold
               ORDER BY sim DESC
               LIMIT p_limit_items
            ) b
        ) x;

      IF json_array_length(v_items) > 0 THEN
        v_fuzzy_used := TRUE;
        -- did-you-mean = merchant name behind the best fuzzy item.
        SELECT (v_items -> 0 ->> 'merchant_name_en') INTO v_fuzzy_top;
      END IF;
    END IF;
  END IF;

  -- ── Suggestions (trending + merchant-name prefixes, normalized dedupe) ──
  IF COALESCE(p_include_suggestions, FALSE) AND p_suggestion_max > 0 THEN
    SELECT COALESCE(json_agg(s.query ORDER BY s.c DESC, s.query ASC), '[]'::json)
      INTO v_suggestions
      FROM (
        SELECT DISTINCT ON (public.normalize_search_text(u.query))
               u.query, u.c
          FROM (
            SELECT sq.query, COUNT(*)::int AS c
              FROM public.search_queries sq
             WHERE sq.created_at >= now() - interval '30 days'
               AND sq.has_results
               AND (p_city IS NULL OR sq.city = p_city)
               AND public.normalize_search_text(sq.query) LIKE v_prefix
               AND public.normalize_search_text(sq.query) <> v_norm
             GROUP BY sq.query
             UNION ALL
             SELECT m.name_en, 0::int
               FROM public.merchants m
              WHERE m.is_active
                AND public.normalize_search_text(m.name_en) LIKE v_prefix
                AND public.normalize_search_text(m.name_en) <> v_norm
             UNION ALL
             SELECT m.name_ar, 0::int
               FROM public.merchants m
              WHERE m.is_active
                AND public.normalize_search_text(m.name_ar) LIKE v_prefix
                AND public.normalize_search_text(m.name_ar) <> v_norm
          ) u
         ORDER BY public.normalize_search_text(u.query), u.c DESC, u.query ASC
       ) s;
  END IF;

  RETURN json_build_object(
    'match_mode',
      CASE WHEN v_fuzzy_used THEN 'fuzzy'
           WHEN json_array_length(v_merchants) > 0 OR json_array_length(v_items) > 0 THEN 'exact'
           ELSE 'none' END,
    'merchants', v_merchants,
    'items', v_items,
    'fuzzy_top', v_fuzzy_top,
    'suggestions', v_suggestions,
    -- surfaced so the Edge Function can log it into search_queries.normalized_query
    -- (single source of truth for normalization — no JS reimplementation)
    'normalized_query', v_norm
  );
END;
$$;


--
-- Name: FUNCTION search_catalog(p_query text, p_city text, p_category text, p_lat numeric, p_lng numeric, p_limit_merchants integer, p_limit_items integer, p_include_items boolean, p_fuzzy_threshold numeric, p_merchant_id uuid, p_include_suggestions boolean, p_suggestion_max integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.search_catalog(p_query text, p_city text, p_category text, p_lat numeric, p_lng numeric, p_limit_merchants integer, p_limit_items integer, p_include_items boolean, p_fuzzy_threshold numeric, p_merchant_id uuid, p_include_suggestions boolean, p_suggestion_max integer) IS 'Search & Discovery MVP (095): single-round-trip catalog search — exact/prefix → fuzzy fallback → suggestions. Geo pre-filter (bbox/city); delivery-radius exclusion stays in the search-catalog Edge Function. service_role only.';


--
-- Name: search_drivers(text, text, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.search_drivers(p_search text, p_status text, p_page integer, p_page_size integer) RETURNS TABLE(id uuid, verification_status text, is_active boolean, is_online boolean, vehicle_type text, vehicle_plate text, vehicle_color text, vehicle_model text, rating numeric, total_deliveries integer, total_earnings numeric, created_at timestamp with time zone, profile_id uuid, profile_full_name text, profile_phone text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
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


--
-- Name: set_default_address(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_default_address(p_address_id uuid, p_user_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
  -- Security check: service role bypasses; otherwise p_user_id must match auth.uid()
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') != 'service_role'
     AND COALESCE(current_setting('request.jwt.claims', true)::json->>'sub', '')::UUID IS DISTINCT FROM p_user_id THEN
    RAISE EXCEPTION 'p_user_id does not match authenticated user';
  END IF;

  -- Verify the address belongs to the user
  IF NOT EXISTS (
    SELECT 1 FROM public.addresses
    WHERE id = p_address_id AND user_id = p_user_id
  ) THEN
    RAISE EXCEPTION 'Address not found or does not belong to user';
  END IF;

  -- Atomic: clear all defaults for this user, then set the new one
  UPDATE public.addresses
  SET is_default = CASE
    WHEN id = p_address_id THEN TRUE
    WHEN user_id = p_user_id THEN FALSE
    ELSE is_default
  END
  WHERE id = p_address_id OR (user_id = p_user_id AND is_default = TRUE);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Address not found';
  END IF;
END;
$$;


--
-- Name: FUNCTION set_default_address(p_address_id uuid, p_user_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.set_default_address(p_address_id uuid, p_user_id uuid) IS 'Atomically sets an address as default. Sprint 2 fix (S09): added auth.uid() = p_user_id check.';


--
-- Name: set_order_number(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_order_number() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Only generate if not already set (allows manual override)
  IF NEW.order_number IS NULL THEN
    NEW.order_number := public.generate_order_number();
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: FUNCTION set_order_number(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.set_order_number() IS 'P1E-14: Auto-generates order_number on orders INSERT using generate_order_number(). Only sets if NULL (allows manual override).';


--
-- Name: set_review_fields_from_order(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_review_fields_from_order() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_order RECORD;
BEGIN
  SELECT customer_id, merchant_id, driver_id
  INTO v_order
  FROM public.orders
  WHERE id = NEW.order_id;

  IF v_order.customer_id IS NOT NULL THEN
    NEW.customer_id := v_order.customer_id;
  END IF;

  IF v_order.merchant_id IS NOT NULL THEN
    NEW.merchant_id := v_order.merchant_id;
  END IF;

  IF v_order.driver_id IS NOT NULL THEN
    NEW.driver_id := v_order.driver_id;
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: FUNCTION set_review_fields_from_order(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.set_review_fields_from_order() IS 'Sprint 2 fix (S16): added SET search_path = "" and schema-qualified orders table reference.';


--
-- Name: trigger_increment_driver_deliveries(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trigger_increment_driver_deliveries() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.status = 'delivered' AND OLD.status IS DISTINCT FROM NEW.status THEN
    IF NEW.driver_id IS NOT NULL THEN
      UPDATE public.drivers
      SET total_deliveries = total_deliveries + 1
      WHERE id = NEW.driver_id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: FUNCTION trigger_increment_driver_deliveries(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.trigger_increment_driver_deliveries() IS 'A3-G3: trigger detached from orders — handleCompleteDelivery in driver-actions EF now owns the total_deliveries increment via increment_driver_stats RPC. Function retained for reference; safe to drop in a future migration if no longer referenced.';


--
-- Name: trigger_log_order_status_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trigger_log_order_status_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Only fire when status actually changes
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    INSERT INTO public.order_status_history (order_id, status, changed_by, changed_by_role, note)
    VALUES (
      NEW.id,
      NEW.status,
      NULL,  -- changed_by is set by the Edge Function; NULL here as fallback
      NULL,  -- changed_by_role is set by the Edge Function; NULL here as fallback
      'Status changed from ' || OLD.status || ' to ' || NEW.status
    );
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: FUNCTION trigger_log_order_status_change(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.trigger_log_order_status_change() IS 'P1E-18: Trigger function to insert order_status_history row on orders status change. Logs the transition with old and new status.';


--
-- Name: trigger_update_driver_rating(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trigger_update_driver_rating() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.driver_id IS NOT NULL AND NEW.driver_rating IS NOT NULL THEN
      PERFORM public.update_driver_rating(NEW.driver_id);
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    IF OLD.driver_id IS DISTINCT FROM NEW.driver_id THEN
      IF OLD.driver_id IS NOT NULL THEN
        PERFORM public.update_driver_rating(OLD.driver_id);
      END IF;
      IF NEW.driver_id IS NOT NULL THEN
        PERFORM public.update_driver_rating(NEW.driver_id);
      END IF;
    ELSIF OLD.driver_rating IS DISTINCT FROM NEW.driver_rating THEN
      IF NEW.driver_id IS NOT NULL THEN
        PERFORM public.update_driver_rating(NEW.driver_id);
      END IF;
    ELSIF (OLD.is_visible IS DISTINCT FROM NEW.is_visible)
          AND NEW.driver_id IS NOT NULL THEN
      PERFORM public.update_driver_rating(NEW.driver_id);
    END IF;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;


--
-- Name: FUNCTION trigger_update_driver_rating(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.trigger_update_driver_rating() IS 'P1E-17: Trigger function to recalculate driver aggregate rating on reviews INSERT/UPDATE. Only fires when driver_id and driver_rating are non-NULL.';


--
-- Name: trigger_update_merchant_rating(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trigger_update_merchant_rating() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM public.update_merchant_rating(NEW.merchant_id);
  ELSIF TG_OP = 'UPDATE' THEN
    IF OLD.merchant_id IS DISTINCT FROM NEW.merchant_id THEN
      PERFORM public.update_merchant_rating(OLD.merchant_id);
      PERFORM public.update_merchant_rating(NEW.merchant_id);
    ELSIF OLD.merchant_rating IS DISTINCT FROM NEW.merchant_rating THEN
      PERFORM public.update_merchant_rating(NEW.merchant_id);
    ELSIF OLD.is_visible IS DISTINCT FROM NEW.is_visible THEN
      PERFORM public.update_merchant_rating(NEW.merchant_id);
    END IF;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;


--
-- Name: FUNCTION trigger_update_merchant_rating(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.trigger_update_merchant_rating() IS 'P1E-16: Trigger function to recalculate merchant aggregate rating on reviews INSERT/UPDATE. Calls update_merchant_rating().';


--
-- Name: trigger_wallet_balance_audit(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trigger_wallet_balance_audit() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
  -- Only log if wallet_balance changed
  IF OLD.wallet_balance IS DISTINCT FROM NEW.wallet_balance THEN
    INSERT INTO public.wallet_audit_log (
      user_id, balance_before, balance_after, change_amount,
      change_type, changed_by, reason
    ) VALUES (
      NEW.id,
      OLD.wallet_balance,
      NEW.wallet_balance,
      NEW.wallet_balance - OLD.wallet_balance,
      -- Infer the type from context (could be overridden by the calling function)
      'correction',
      NULL,  -- Set by the calling function if available
      'Wallet balance changed from ' || OLD.wallet_balance || ' to ' || NEW.wallet_balance
    );
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: FUNCTION trigger_wallet_balance_audit(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.trigger_wallet_balance_audit() IS 'Auto-logs every wallet_balance change on profiles. Financial audit trail for reconciliation.';


--
-- Name: update_driver_location(uuid, numeric, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_driver_location(p_driver_id uuid, p_lat numeric, p_lng numeric, p_accuracy numeric DEFAULT NULL::numeric) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_updated BOOLEAN;
BEGIN
  -- Security: verify caller is service role or the driver themselves
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') NOT IN ('service_role', 'authenticated') THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  -- If caller is authenticated (not service_role), verify they are the driver
  IF current_setting('request.jwt.claims', true)::json->>'role' = 'authenticated' THEN
    IF auth.uid() != p_driver_id THEN
      RAISE EXCEPTION 'Drivers can only update their own location';
    END IF;

    -- Verify driver is verified + active + online
    IF NOT EXISTS (
      SELECT 1 FROM public.drivers
      WHERE id = p_driver_id
        AND is_verified = TRUE
        AND is_active = TRUE
        AND is_online = TRUE
    ) THEN
      RAISE EXCEPTION 'Only verified, active, online drivers can update location';
    END IF;
  END IF;

  -- Conditional UPDATE: skip if location hasn't changed significantly
  -- AND last update was recent (< 3 seconds ago)
  UPDATE public.drivers
  SET
    current_lat = p_lat,
    current_lng = p_lng,
    last_location_at = NOW()
  WHERE id = p_driver_id
    AND (
      -- Update if location changed significantly (> ~1 meter = 0.00001 degrees)
      current_lat IS NULL
      OR current_lng IS NULL
      OR ABS(current_lat - p_lat) > 0.00001
      OR ABS(current_lng - p_lng) > 0.00001
      -- OR if last update was > 3 seconds ago (staleness guard)
      OR last_location_at < NOW() - INTERVAL '3 seconds'
    );

  v_updated := FOUND;

  RETURN v_updated;
END;
$$;


--
-- Name: FUNCTION update_driver_location(p_driver_id uuid, p_lat numeric, p_lng numeric, p_accuracy numeric); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.update_driver_location(p_driver_id uuid, p_lat numeric, p_lng numeric, p_accuracy numeric) IS 'Optimized driver location update. Skips write if location unchanged and recently updated. RED-03: reduces unnecessary writes by ~40% for stationary drivers.';


--
-- Name: update_driver_rating(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_driver_rating(p_driver_id uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_avg_rating NUMERIC;
  v_rating_count INTEGER;
BEGIN
  SELECT
    ROUND(AVG(driver_rating), 1),
    COUNT(driver_rating)
  INTO v_avg_rating, v_rating_count
  FROM public.reviews
  WHERE driver_id = p_driver_id
    AND driver_rating IS NOT NULL
    AND is_visible = TRUE;

  UPDATE public.drivers
  SET
    rating = COALESCE(v_avg_rating, 5.0),
    rating_count = COALESCE(v_rating_count, 0)
  WHERE id = p_driver_id;
END;
$$;


--
-- Name: FUNCTION update_driver_rating(p_driver_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.update_driver_rating(p_driver_id uuid) IS 'P1E-11: Recalculates and updates the aggregate rating (AVG + COUNT) on the drivers table. Only considers reviews with non-NULL driver_rating. Default rating is 5.0 if no reviews.';


--
-- Name: update_merchant_rating(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_merchant_rating(p_merchant_id uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_avg_rating NUMERIC;
  v_rating_count INTEGER;
BEGIN
  SELECT
    ROUND(AVG(merchant_rating), 1),
    COUNT(*)
  INTO v_avg_rating, v_rating_count
  FROM public.reviews
  WHERE merchant_id = p_merchant_id
    AND is_visible = TRUE;

  UPDATE public.merchants
  SET
    rating = COALESCE(v_avg_rating, 0.0),
    rating_count = COALESCE(v_rating_count, 0)
  WHERE id = p_merchant_id;
END;
$$;


--
-- Name: FUNCTION update_merchant_rating(p_merchant_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.update_merchant_rating(p_merchant_id uuid) IS 'P1E-10: Recalculates and updates the aggregate rating (AVG + COUNT) on the merchants table. Called by trigger on reviews INSERT/UPDATE.';


--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: addresses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.addresses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid DEFAULT auth.uid() NOT NULL,
    label text DEFAULT 'home'::text NOT NULL,
    title_ar text,
    title_en text,
    address text NOT NULL,
    building_number text,
    floor_number text,
    apartment_number text,
    landmark text,
    lat numeric(9,6) NOT NULL,
    lng numeric(9,6) NOT NULL,
    city text,
    area text,
    google_place_id text,
    is_default boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT addresses_label_check CHECK ((label = ANY (ARRAY['home'::text, 'work'::text, 'other'::text])))
);


--
-- Name: TABLE addresses; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.addresses IS 'Saved delivery addresses for users. One default per user enforced by partial unique index.';


--
-- Name: COLUMN addresses.lat; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.addresses.lat IS 'Latitude for driver navigation and distance calculation.';


--
-- Name: COLUMN addresses.lng; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.addresses.lng IS 'Longitude for driver navigation and distance calculation.';


--
-- Name: COLUMN addresses.is_default; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.addresses.is_default IS 'Only one address per user can be default. Enforced by partial unique index.';


--
-- Name: upsert_address_with_default(uuid, uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.upsert_address_with_default(p_address_id uuid, p_user_id uuid, p_data jsonb) RETURNS public.addresses
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_returned public.addresses;
  v_is_default BOOLEAN;
  v_existing_owner UUID;
BEGIN
  -- Security: verify p_user_id matches the JWT's auth.uid().
  -- Prevents a caller from passing another user's UUID as p_user_id.
  IF COALESCE(current_setting('request.jwt.claims', true)::json->>'sub', '')::UUID IS DISTINCT FROM p_user_id THEN
    RAISE EXCEPTION 'p_user_id does not match authenticated user';
  END IF;

  -- Extract is_default from the payload (default FALSE if absent).
  v_is_default := COALESCE((p_data->>'is_default')::BOOLEAN, FALSE);

  IF p_address_id IS NULL THEN
    -- ===== INSERT path (addAddress) =====
    -- 1. If is_default, clear the user's existing default in the same transaction.
    IF v_is_default THEN
      UPDATE public.addresses
      SET is_default = FALSE
      WHERE user_id = p_user_id AND is_default = TRUE;
    END IF;

    -- 2. Insert the new address.
    INSERT INTO public.addresses (
      user_id, label, title_ar, title_en, address,
      building_number, floor_number, apartment_number, landmark,
      lat, lng, city, area, google_place_id, is_default
    )
    VALUES (
      p_user_id,
      p_data->>'label',
      NULLIF(p_data->>'title_ar', '') ,
      NULLIF(p_data->>'title_en', ''),
      p_data->>'address',
      NULLIF(p_data->>'building_number', ''),
      NULLIF(p_data->>'floor_number', ''),
      NULLIF(p_data->>'apartment_number', ''),
      NULLIF(p_data->>'landmark', ''),
      (p_data->>'lat')::DOUBLE PRECISION,
      (p_data->>'lng')::DOUBLE PRECISION,
      NULLIF(p_data->>'city', ''),
      NULLIF(p_data->>'area', ''),
      NULLIF(p_data->>'google_place_id', ''),
      v_is_default
    )
    RETURNING * INTO v_returned;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Failed to insert address';
    END IF;

    RETURN v_returned;
  ELSE
    -- ===== UPDATE path (updateAddress) =====
    -- 1. Verify the address belongs to the caller (defense in depth — RLS
    --    already enforces this, but an explicit check produces a clearer
    --    error than a silent 0-row update).
    SELECT user_id INTO v_existing_owner
    FROM public.addresses
    WHERE id = p_address_id;

    IF v_existing_owner IS NULL THEN
      RAISE EXCEPTION 'Address not found';
    END IF;

    IF v_existing_owner IS DISTINCT FROM p_user_id THEN
      RAISE EXCEPTION 'Address does not belong to user';
    END IF;

    -- 2. If setting is_default=true, clear the user's other defaults in the
    --    same transaction. Only clear when the flag is being set to TRUE
    --    (not when being explicitly set to FALSE or absent).
    IF v_is_default THEN
      UPDATE public.addresses
      SET is_default = FALSE
      WHERE user_id = p_user_id AND is_default = TRUE AND id <> p_address_id;
    END IF;

    -- 3. Update the address with only the fields present in p_data.
    --    Using COALESCE to skip fields not in the payload (Partial<AddressFormData>).
    UPDATE public.addresses
    SET
      label             = COALESCE(NULLIF(p_data->>'label', ''), label),
      title_ar          = CASE WHEN p_data ? 'title_ar' THEN NULLIF(p_data->>'title_ar', '') ELSE title_ar END,
      title_en          = CASE WHEN p_data ? 'title_en' THEN NULLIF(p_data->>'title_en', '') ELSE title_en END,
      address           = COALESCE(NULLIF(p_data->>'address', ''), address),
      building_number   = CASE WHEN p_data ? 'building_number' THEN NULLIF(p_data->>'building_number', '') ELSE building_number END,
      floor_number      = CASE WHEN p_data ? 'floor_number' THEN NULLIF(p_data->>'floor_number', '') ELSE floor_number END,
      apartment_number  = CASE WHEN p_data ? 'apartment_number' THEN NULLIF(p_data->>'apartment_number', '') ELSE apartment_number END,
      landmark          = CASE WHEN p_data ? 'landmark' THEN NULLIF(p_data->>'landmark', '') ELSE landmark END,
      lat               = CASE WHEN p_data ? 'lat' THEN (p_data->>'lat')::DOUBLE PRECISION ELSE lat END,
      lng               = CASE WHEN p_data ? 'lng' THEN (p_data->>'lng')::DOUBLE PRECISION ELSE lng END,
      city              = CASE WHEN p_data ? 'city' THEN NULLIF(p_data->>'city', '') ELSE city END,
      area              = CASE WHEN p_data ? 'area' THEN NULLIF(p_data->>'area', '') ELSE area END,
      google_place_id   = CASE WHEN p_data ? 'google_place_id' THEN NULLIF(p_data->>'google_place_id', '') ELSE google_place_id END,
      is_default        = CASE WHEN p_data ? 'is_default' THEN v_is_default ELSE is_default END,
      updated_at        = NOW()
    WHERE id = p_address_id AND user_id = p_user_id
    RETURNING * INTO v_returned;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Failed to update address';
    END IF;

    RETURN v_returned;
  END IF;
END;
$$;


--
-- Name: FUNCTION upsert_address_with_default(p_address_id uuid, p_user_id uuid, p_data jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.upsert_address_with_default(p_address_id uuid, p_user_id uuid, p_data jsonb) IS 'Atomically inserts or updates an address, managing the is_default flag in a single transaction. Eliminates the race condition and non-transactional failure mode of the previous two-step clear-then-set pattern. For insert: pass p_address_id=NULL. For update: pass the address UUID. p_data is a JSONB object of AddressFormData (insert) or Partial<AddressFormData> (update).';


--
-- Name: apply_rls(jsonb, integer); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.apply_rls(wal jsonb, max_record_bytes integer DEFAULT (1024 * 1024)) RETURNS SETOF realtime.wal_rls
    LANGUAGE plpgsql
    AS $$
declare
    -- Regclass of the table e.g. public.notes
    entity_ regclass = (quote_ident(wal ->> 'schema') || '.' || quote_ident(wal ->> 'table'))::regclass;

    -- I, U, D, T: insert, update ...
    action realtime.action = (
        case wal ->> 'action'
            when 'I' then 'INSERT'
            when 'U' then 'UPDATE'
            when 'D' then 'DELETE'
            else 'ERROR'
        end
    );

    -- Is row level security enabled for the table
    is_rls_enabled bool = relrowsecurity from pg_class where oid = entity_;

    subscriptions realtime.subscription[] = array_agg(subs)
        from
            realtime.subscription subs
        where
            subs.entity = entity_
            -- Filter by action early - only get subscriptions interested in this action
            -- action_filter column can be: '*' (all), 'INSERT', 'UPDATE', or 'DELETE'
            and (subs.action_filter = '*' or subs.action_filter = action::text);

    -- Subscription vars
    working_role regrole;
    working_selected_columns text[];
    claimed_role regrole;
    claims jsonb;

    subscription_id uuid;
    subscription_has_access bool;
    visible_to_subscription_ids uuid[] = '{}';

    -- structured info for wal's columns
    columns realtime.wal_column[];
    -- previous identity values for update/delete
    old_columns realtime.wal_column[];

    error_record_exceeds_max_size boolean = octet_length(wal::text) > max_record_bytes;

    -- Primary jsonb output for record
    output jsonb;

    -- Loop record for iterating unique roles (outer loop)
    role_record record;
    -- Loop record for iterating unique selected_columns within a role (inner loop)
    cols_record record;
    -- Subscription ids visible at the role level (before fanning out by selected_columns)
    visible_role_sub_ids uuid[] = '{}';

begin
    perform set_config('role', null, true);

    columns =
        array_agg(
            (
                x->>'name',
                x->>'type',
                x->>'typeoid',
                realtime.cast(
                    (x->'value') #>> '{}',
                    coalesce(
                        (x->>'typeoid')::regtype, -- null when wal2json version <= 2.4
                        (x->>'type')::regtype
                    )
                ),
                (pks ->> 'name') is not null,
                true
            )::realtime.wal_column
        )
        from
            jsonb_array_elements(wal -> 'columns') x
            left join jsonb_array_elements(wal -> 'pk') pks
                on (x ->> 'name') = (pks ->> 'name');

    old_columns =
        array_agg(
            (
                x->>'name',
                x->>'type',
                x->>'typeoid',
                realtime.cast(
                    (x->'value') #>> '{}',
                    coalesce(
                        (x->>'typeoid')::regtype, -- null when wal2json version <= 2.4
                        (x->>'type')::regtype
                    )
                ),
                (pks ->> 'name') is not null,
                true
            )::realtime.wal_column
        )
        from
            jsonb_array_elements(wal -> 'identity') x
            left join jsonb_array_elements(wal -> 'pk') pks
                on (x ->> 'name') = (pks ->> 'name');

    for role_record in
        select claims_role
        from (select distinct claims_role from unnest(subscriptions)) t
        order by claims_role::text
    loop
        working_role := role_record.claims_role;

        -- Update `is_selectable` for columns and old_columns (once per role)
        columns =
            array_agg(
                (
                    c.name,
                    c.type_name,
                    c.type_oid,
                    c.value,
                    c.is_pkey,
                    pg_catalog.has_column_privilege(working_role, entity_, c.name, 'SELECT')
                )::realtime.wal_column
            )
            from
                unnest(columns) c;

        old_columns =
                array_agg(
                    (
                        c.name,
                        c.type_name,
                        c.type_oid,
                        c.value,
                        c.is_pkey,
                        pg_catalog.has_column_privilege(working_role, entity_, c.name, 'SELECT')
                    )::realtime.wal_column
                )
                from
                    unnest(old_columns) c;

        if action <> 'DELETE' and count(1) = 0 from unnest(columns) c where c.is_pkey then
            -- Fan out 400 error per distinct selected_columns for this role
            for cols_record in
                select selected_columns
                from (select distinct selected_columns from unnest(subscriptions) s where s.claims_role = working_role) t
                order by coalesce(array_to_string(selected_columns, ','), '')
            loop
                working_selected_columns := cols_record.selected_columns;
                return next (
                    jsonb_build_object(
                        'schema', wal ->> 'schema',
                        'table', wal ->> 'table',
                        'type', action
                    ),
                    is_rls_enabled,
                    (select array_agg(s.subscription_id) from unnest(subscriptions) as s where s.claims_role = working_role and (s.selected_columns is not distinct from working_selected_columns)),
                    array['Error 400: Bad Request, no primary key']
                )::realtime.wal_rls;
            end loop;

        -- The claims role does not have SELECT permission to the primary key of entity
        elsif action <> 'DELETE' and sum(c.is_selectable::int) <> count(1) from unnest(columns) c where c.is_pkey then
            -- Fan out 401 error per distinct selected_columns for this role
            for cols_record in
                select selected_columns
                from (select distinct selected_columns from unnest(subscriptions) s where s.claims_role = working_role) t
                order by coalesce(array_to_string(selected_columns, ','), '')
            loop
                working_selected_columns := cols_record.selected_columns;
                return next (
                    jsonb_build_object(
                        'schema', wal ->> 'schema',
                        'table', wal ->> 'table',
                        'type', action
                    ),
                    is_rls_enabled,
                    (select array_agg(s.subscription_id) from unnest(subscriptions) as s where s.claims_role = working_role and (s.selected_columns is not distinct from working_selected_columns)),
                    array['Error 401: Unauthorized']
                )::realtime.wal_rls;
            end loop;

        else
            -- Create the prepared statement (once per role)
            if is_rls_enabled and action <> 'DELETE' then
                if (select 1 from pg_prepared_statements where name = 'walrus_rls_stmt' limit 1) > 0 then
                    deallocate walrus_rls_stmt;
                end if;
                execute realtime.build_prepared_statement_sql('walrus_rls_stmt', entity_, columns);
            end if;

            -- Collect all visible subscription IDs for this role (filter check + RLS check)
            visible_role_sub_ids = '{}';

            for subscription_id, claims in (
                    select
                        subs.subscription_id,
                        subs.claims
                    from
                        unnest(subscriptions) subs
                    where
                        subs.entity = entity_
                        and subs.claims_role = working_role
                        and (
                            realtime.is_visible_through_filters(columns, subs.filters)
                            or (
                              action = 'DELETE'
                              and realtime.is_visible_through_filters(old_columns, subs.filters)
                            )
                        )
            ) loop

                if not is_rls_enabled or action = 'DELETE' then
                    visible_role_sub_ids = visible_role_sub_ids || subscription_id;
                else
                    -- Check if RLS allows the role to see the record
                    perform
                        -- Trim leading and trailing quotes from working_role because set_config
                        -- doesn't recognize the role as valid if they are included
                        set_config('role', trim(both '"' from working_role::text), true),
                        set_config('request.jwt.claims', claims::text, true);

                    execute 'execute walrus_rls_stmt' into subscription_has_access;

                    -- Reset the role on every FOR..LOOP batch execution.
                    -- The first batch of 10 rows is pre-fetched using the current connection role (PG internal behaviour)
                    -- then we have to reset it again otherwise it would use the role defined in the `set_config` above
                    -- to fetch the remaining rows when rows>10, which could be a user-defined role that lacks execution grants.
                    -- The flow is:
                    --   1. run batch with conn role
                    --   2. set_config working_role
                    --   3. execute walrus
                    --   4. reset role (revert)
                    --   5. repeat
                    perform set_config('role', null, true);

                    if subscription_has_access then
                        visible_role_sub_ids = visible_role_sub_ids || subscription_id;
                    end if;
                end if;
            end loop;

            perform set_config('role', null, true);

            -- Inner loop: per distinct selected_columns for this role
            for cols_record in
                select selected_columns
                from (select distinct selected_columns from unnest(subscriptions) s where s.claims_role = working_role) t
                order by coalesce(array_to_string(selected_columns, ','), '')
            loop
                working_selected_columns := cols_record.selected_columns;

                output = jsonb_build_object(
                    'schema', wal ->> 'schema',
                    'table', wal ->> 'table',
                    'type', action,
                    'commit_timestamp', to_char(
                        ((wal ->> 'timestamp')::timestamptz at time zone 'utc'),
                        'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
                    ),
                    'columns', (
                        select
                            jsonb_agg(
                                jsonb_build_object(
                                    'name', pa.attname,
                                    'type', pt.typname
                                )
                                order by pa.attnum asc
                            )
                        from
                            pg_attribute pa
                            join pg_type pt
                                on pa.atttypid = pt.oid
                            left join (
                                select unnest(conkey) as pkey_attnum
                                from pg_constraint
                                where conrelid = entity_ and contype = 'p'
                            ) pk on pk.pkey_attnum = pa.attnum
                        where
                            attrelid = entity_
                            and attnum > 0
                            and pg_catalog.has_column_privilege(working_role, entity_, pa.attname, 'SELECT')
                            and (working_selected_columns is null or pa.attname = any(working_selected_columns) or pk.pkey_attnum is not null)
                    )
                )
                -- Add "record" key for insert and update
                || case
                    when action in ('INSERT', 'UPDATE') then
                        jsonb_build_object(
                            'record',
                            (
                                select
                                    jsonb_object_agg(
                                        -- if unchanged toast, get column name and value from old record
                                        coalesce((c).name, (oc).name),
                                        case
                                            when (c).name is null then (oc).value
                                            else (c).value
                                        end
                                    )
                                from
                                    unnest(columns) c
                                    full outer join unnest(old_columns) oc
                                        on (c).name = (oc).name
                                where
                                    coalesce((c).is_selectable, (oc).is_selectable)
                                    and (working_selected_columns is null or coalesce((c).name, (oc).name) = any(working_selected_columns) or coalesce((c).is_pkey, (oc).is_pkey))
                                    and ( not error_record_exceeds_max_size or (octet_length((c).value::text) <= 64))
                            )
                        )
                    else '{}'::jsonb
                end
                -- Add "old_record" key for update and delete
                || case
                    when action = 'UPDATE' then
                        jsonb_build_object(
                                'old_record',
                                (
                                    select jsonb_object_agg((c).name, (c).value)
                                    from unnest(old_columns) c
                                    where
                                        (c).is_selectable
                                        and (working_selected_columns is null or (c).name = any(working_selected_columns) or (c).is_pkey)
                                        and ( not error_record_exceeds_max_size or (octet_length((c).value::text) <= 64))
                                )
                            )
                    when action = 'DELETE' then
                        jsonb_build_object(
                            'old_record',
                            (
                                select jsonb_object_agg((c).name, (c).value)
                                from unnest(old_columns) c
                                where
                                    (c).is_selectable
                                    and (working_selected_columns is null or (c).name = any(working_selected_columns) or (c).is_pkey)
                                    and ( not error_record_exceeds_max_size or (octet_length((c).value::text) <= 64))
                                    and ( not is_rls_enabled or (c).is_pkey ) -- if RLS enabled, we can't secure deletes so filter to pkey
                            )
                        )
                    else '{}'::jsonb
                end;

                -- Filter visible_role_sub_ids to those matching the current selected_columns group
                visible_to_subscription_ids = coalesce(
                    (
                        select array_agg(s.subscription_id)
                        from unnest(subscriptions) s
                        where s.claims_role = working_role
                          and (s.selected_columns is not distinct from working_selected_columns)
                          and s.subscription_id = any(visible_role_sub_ids)
                    ),
                    '{}'::uuid[]
                );

                return next (
                    output,
                    is_rls_enabled,
                    visible_to_subscription_ids,
                    case
                        when error_record_exceeds_max_size then array['Error 413: Payload Too Large']
                        else '{}'
                    end
                )::realtime.wal_rls;
            end loop;

        end if;
    end loop;

    perform set_config('role', null, true);
end;
$$;


--
-- Name: broadcast_changes(text, text, text, text, text, record, record, text); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.broadcast_changes(topic_name text, event_name text, operation text, table_name text, table_schema text, new record, old record, level text DEFAULT 'ROW'::text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    -- Declare a variable to hold the JSONB representation of the row
    row_data jsonb := '{}'::jsonb;
BEGIN
    IF level = 'STATEMENT' THEN
        RAISE EXCEPTION 'function can only be triggered for each row, not for each statement';
    END IF;
    -- Check the operation type and handle accordingly
    IF operation = 'INSERT' OR operation = 'UPDATE' OR operation = 'DELETE' THEN
        row_data := jsonb_build_object('old_record', OLD, 'record', NEW, 'operation', operation, 'table', table_name, 'schema', table_schema);
        PERFORM realtime.send (row_data, event_name, topic_name);
    ELSE
        RAISE EXCEPTION 'Unexpected operation type: %', operation;
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Failed to process the row: %', SQLERRM;
END;

$$;


--
-- Name: build_prepared_statement_sql(text, regclass, realtime.wal_column[]); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.build_prepared_statement_sql(prepared_statement_name text, entity regclass, columns realtime.wal_column[]) RETURNS text
    LANGUAGE sql
    AS $$
      /*
      Builds a sql string that, if executed, creates a prepared statement to
      tests retrive a row from *entity* by its primary key columns.
      Example
          select realtime.build_prepared_statement_sql('public.notes', '{"id"}'::text[], '{"bigint"}'::text[])
      */
          select
      'prepare ' || prepared_statement_name || ' as
          select
              exists(
                  select
                      1
                  from
                      ' || entity || '
                  where
                      ' || string_agg(quote_ident(pkc.name) || '=' || quote_nullable(pkc.value #>> '{}') , ' and ') || '
              )'
          from
              unnest(columns) pkc
          where
              pkc.is_pkey
          group by
              entity
      $$;


--
-- Name: cast(text, regtype); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime."cast"(val text, type_ regtype) RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE
    AS $$
declare
  res jsonb;
begin
  if type_::text = 'bytea' then
    return to_jsonb(val);
  end if;
  execute format('select to_jsonb(%L::'|| type_::text || ')', val) into res;
  return res;
end
$$;


--
-- Name: check_equality_op(realtime.equality_op, regtype, text, text); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $$
/*
Casts *val_1* and *val_2* as type *type_* and check the *op* condition for truthiness
*/
declare
    op_symbol text = (
        case
            when op = 'eq' then '='
            when op = 'neq' then '!='
            when op = 'lt' then '<'
            when op = 'lte' then '<='
            when op = 'gt' then '>'
            when op = 'gte' then '>='
            when op = 'in' then '= any'
            else 'UNKNOWN OP'
        end
    );
    res boolean;
begin
    execute format(
        'select %L::'|| type_::text || ' ' || op_symbol
        || ' ( %L::'
        || (
            case
                when op = 'in' then type_::text || '[]'
                else type_::text end
        )
        || ')', val_1, val_2) into res;
    return res;
end;
$$;


--
-- Name: check_equality_op(realtime.equality_op, regtype, text, text, boolean); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text, negate boolean) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
declare
    op_symbol text;
    res boolean;
begin
    -- IS DISTINCT FROM / IS NOT DISTINCT FROM: infix, both sides typed literals
    if op = 'isdistinct' then
        execute format(
            'select %L::%s %s %L::%s',
            val_1,
            type_::text,
            case when negate then 'IS NOT DISTINCT FROM' else 'IS DISTINCT FROM' end,
            val_2,
            type_::text
        ) into res;
        return res;
    end if;

    -- IS requires a keyword RHS (NULL, TRUE, FALSE, UNKNOWN), not a typed literal
    if op = 'is' then
        if val_2 not in ('null', 'true', 'false', 'unknown') then
            raise exception 'invalid value for is filter: must be null, true, false, or unknown';
        end if;
        execute format(
            'select %L::%s %s %s',
            val_1,
            type_::text,
            case when negate then 'IS NOT' else 'IS' end,
            upper(val_2)
        ) into res;
        return res;
    end if;

    op_symbol = case
        when op = 'eq'    then '='
        when op = 'neq'   then '!='
        when op = 'lt'    then '<'
        when op = 'lte'   then '<='
        when op = 'gt'    then '>'
        when op = 'gte'   then '>='
        when op = 'in'    then '= any'
        when op = 'like'   then 'LIKE'
        when op = 'ilike'  then 'ILIKE'
        when op = 'match'  then '~'
        when op = 'imatch' then '~*'
        else null
    end;

    if op_symbol is null then
        raise exception 'unsupported equality operator: %', op::text;
    end if;

    execute format(
        'select %L::%s %s (%L::%s)',
        val_1,
        type_::text,
        op_symbol,
        val_2,
        case when op = 'in' then type_::text || '[]' else type_::text end
    ) into res;

    return case when negate then not res else res end;
end;
$$;


--
-- Name: is_visible_through_filters(realtime.wal_column[], realtime.user_defined_filter[]); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.is_visible_through_filters(columns realtime.wal_column[], filters realtime.user_defined_filter[]) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
    select
        filters is null
        or array_length(filters, 1) is null
        or coalesce(
            count(col.name) = count(1)
            and sum(
                realtime.check_equality_op(
                    op:=f.op,
                    type_:=coalesce(col.type_oid::regtype, col.type_name::regtype),
                    val_1:=col.value #>> '{}',
                    val_2:=f.value,
                    negate:=coalesce(f.negate, false)
                )::int
            ) filter (where col.name is not null) = count(col.name),
            false
        )
    from
        unnest(filters) f
        left join unnest(columns) col
            on f.column_name = col.name;
$$;


--
-- Name: list_changes(name, name, integer, integer); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.list_changes(publication name, slot_name name, max_changes integer, max_record_bytes integer) RETURNS TABLE(wal jsonb, is_rls_enabled boolean, subscription_ids uuid[], errors text[], slot_changes_count bigint)
    LANGUAGE sql
    SET log_min_messages TO 'fatal'
    AS $$
  WITH pub AS (
    SELECT
      concat_ws(
        ',',
        CASE WHEN bool_or(pubinsert) THEN 'insert' ELSE NULL END,
        CASE WHEN bool_or(pubupdate) THEN 'update' ELSE NULL END,
        CASE WHEN bool_or(pubdelete) THEN 'delete' ELSE NULL END
      ) AS w2j_actions,
      coalesce(
        string_agg(
          realtime.quote_wal2json(format('%I.%I', schemaname, tablename)::regclass),
          ','
        ) filter (WHERE ppt.tablename IS NOT NULL),
        ''
      ) AS w2j_add_tables
    FROM pg_publication pp
    LEFT JOIN pg_publication_tables ppt ON pp.pubname = ppt.pubname
    WHERE pp.pubname = publication
    GROUP BY pp.pubname
    LIMIT 1
  ),
  -- MATERIALIZED ensures pg_logical_slot_get_changes is called exactly once
  w2j AS MATERIALIZED (
    SELECT x.*, pub.w2j_add_tables
    FROM pub,
         pg_logical_slot_get_changes(
           slot_name, null, max_changes,
           'include-pk', 'true',
           'include-transaction', 'false',
           'include-timestamp', 'true',
           'include-type-oids', 'true',
           'format-version', '2',
           'actions', pub.w2j_actions,
           'add-tables', pub.w2j_add_tables
         ) x
  ),
  slot_count AS (
    SELECT count(*)::bigint AS cnt
    FROM w2j
    WHERE w2j.w2j_add_tables <> ''
  ),
  rls_filtered AS (
    SELECT xyz.wal, xyz.is_rls_enabled, xyz.subscription_ids, xyz.errors
    FROM w2j,
         realtime.apply_rls(
           wal := w2j.data::jsonb,
           max_record_bytes := max_record_bytes
         ) xyz(wal, is_rls_enabled, subscription_ids, errors)
    WHERE w2j.w2j_add_tables <> ''
      AND xyz.subscription_ids[1] IS NOT NULL
  )
  SELECT rf.wal, rf.is_rls_enabled, rf.subscription_ids, rf.errors, sc.cnt
  FROM rls_filtered rf, slot_count sc

  UNION ALL

  SELECT null, null, null, null, sc.cnt
  FROM slot_count sc
  WHERE NOT EXISTS (SELECT 1 FROM rls_filtered)
$$;


--
-- Name: quote_wal2json(regclass); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.quote_wal2json(entity regclass) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT
    AS $$
  SELECT
    realtime.wal2json_escape_identifier(nsp.nspname::text)
    || '.'
    || realtime.wal2json_escape_identifier(pc.relname::text)
  FROM pg_class pc
  JOIN pg_namespace nsp ON pc.relnamespace = nsp.oid
  WHERE pc.oid = entity
$$;


--
-- Name: send(jsonb, text, text, boolean); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.send(payload jsonb, event text, topic text, private boolean DEFAULT true) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  generated_id uuid;
  final_payload jsonb;
BEGIN
  BEGIN
    generated_id := gen_random_uuid();

    -- Check if payload has an 'id' key, if not, add the generated UUID
    IF payload ? 'id' THEN
      final_payload := payload;
    ELSE
      final_payload := jsonb_set(payload, '{id}', to_jsonb(generated_id));
    END IF;

    -- Set the topic configuration
    EXECUTE format('SET LOCAL realtime.topic TO %L', topic);

    INSERT INTO realtime.messages (id, payload, event, topic, private, extension)
    VALUES (generated_id, final_payload, event, topic, private, 'broadcast');
  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING 'WarnSendingBroadcastMessage: %', SQLERRM;
  END;
END;
$$;


--
-- Name: send_binary(bytea, text, text, boolean); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.send_binary(payload bytea, event text, topic text, private boolean DEFAULT true) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  generated_id uuid;
BEGIN
  BEGIN
    generated_id := gen_random_uuid();

    EXECUTE format('SET LOCAL realtime.topic TO %L', topic);

    INSERT INTO realtime.messages (id, binary_payload, event, topic, private, extension)
    VALUES (generated_id, payload, event, topic, private, 'broadcast');
  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING 'WarnSendingBroadcastMessage: %', SQLERRM;
  END;
END;
$$;


--
-- Name: subscription_check_filters(); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.subscription_check_filters() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
    col_names text[] = coalesce(
            array_agg(a.attname order by a.attnum),
            '{}'::text[]
        )
        from
            pg_catalog.pg_attribute a
        where
            a.attrelid = new.entity
            and a.attnum > 0
            and not a.attisdropped
            and pg_catalog.has_column_privilege(
                (new.claims ->> 'role'),
                a.attrelid,
                a.attnum,
                'SELECT'
            );
    filter realtime.user_defined_filter;
    col_type regtype;
    in_val jsonb;
    selected_col text;
begin
    for filter in select * from unnest(new.filters) loop
        if not filter.column_name = any(col_names) then
            raise exception 'invalid column for filter %', filter.column_name;
        end if;

        col_type = (
            select atttypid::regtype
            from pg_catalog.pg_attribute
            where attrelid = new.entity
                  and attname = filter.column_name
        );
        if col_type is null then
            raise exception 'failed to lookup type for column %', filter.column_name;
        end if;

        if filter.op = 'in'::realtime.equality_op then
            in_val = realtime.cast(filter.value, (col_type::text || '[]')::regtype);
            if coalesce(jsonb_array_length(in_val), 0) > 100 then
                raise exception 'too many values for `in` filter. Maximum 100';
            end if;
        elsif filter.op = 'is'::realtime.equality_op then
            -- `is` requires a keyword RHS rather than a typed literal
            if filter.value not in ('null', 'true', 'false', 'unknown') then
                raise exception 'invalid value for is filter: must be null, true, false, or unknown';
            end if;
            -- IS NULL works for any type, but IS TRUE/FALSE/UNKNOWN require a boolean
            -- operand. Reject the non-null keywords on non-boolean columns here so they
            -- don't abort apply_rls at WAL time.
            if filter.value <> 'null' and col_type <> 'boolean'::regtype then
                raise exception 'is % filter requires a boolean column, got %', filter.value, col_type::text;
            end if;
        elsif filter.op in ('like'::realtime.equality_op, 'ilike'::realtime.equality_op) then
            -- like/ilike apply the text pattern operator (~~); reject column types that
            -- have no such operator instead of failing at WAL time
            if not exists (
                select 1 from pg_catalog.pg_operator
                where oprname = '~~' and oprleft = col_type
            ) then
                raise exception 'operator % requires a text-compatible column type, got %', filter.op::text, col_type::text;
            end if;
        elsif filter.op in ('match'::realtime.equality_op, 'imatch'::realtime.equality_op) then
            -- match/imatch apply the regex operators ~ / ~*; reject column types that have
            -- no such operator (e.g. integer) instead of failing at WAL time, mirroring the
            -- like/ilike guard above.
            if not exists (
                select 1 from pg_catalog.pg_operator
                where oprname = case when filter.op = 'imatch'::realtime.equality_op then '~*' else '~' end
                  and oprleft = col_type
                  and oprright = col_type
                  and oprresult = 'boolean'::regtype
            ) then
                raise exception 'operator % requires a text-compatible column type, got %', filter.op::text, col_type::text;
            end if;
            -- validate the regex eagerly so a bad pattern is rejected here, not inside
            -- apply_rls where it would abort the WAL stream for the entity
            begin
                perform '' ~ filter.value;
            exception when others then
                raise exception 'invalid regular expression for % filter: %', filter.op::text, sqlerrm;
            end;
        else
            -- eq/neq/lt/lte/gt/gte: value must be coercable to the type
            perform realtime.cast(filter.value, col_type);
        end if;
    end loop;

    if new.selected_columns is not null then
        for selected_col in select * from unnest(new.selected_columns) loop
            if not selected_col = any(col_names) then
                raise exception 'invalid column for select %', selected_col;
            end if;
        end loop;
    end if;

    -- Apply consistent order to filters so the unique constraint can't be tricked by a
    -- different filter order. negate is part of the sort key.
    new.filters = coalesce(
        array_agg(f order by f.column_name, f.op, f.value, f.negate),
        '{}'
    ) from unnest(new.filters) f;

    -- Normalize selected_columns order so ARRAY['a','b'] and ARRAY['b','a'] are treated
    -- as the same subscription group in apply_rls. Preserve an empty array as '{}'
    -- ("primary keys only") so it stays distinct from NULL ("all columns"); array_agg
    -- over an empty set would otherwise collapse '{}' back to NULL.
    if new.selected_columns is not null then
        new.selected_columns = coalesce(
            (
                select array_agg(c order by c)
                from unnest(new.selected_columns) c
            ),
            '{}'::text[]
        );
    end if;

    return new;
end;
$$;


--
-- Name: to_regrole(text); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.to_regrole(role_name text) RETURNS regrole
    LANGUAGE sql IMMUTABLE
    AS $$ select role_name::regrole $$;


--
-- Name: topic(); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.topic() RETURNS text
    LANGUAGE sql STABLE
    AS $$
select nullif(current_setting('realtime.topic', true), '')::text;
$$;


--
-- Name: wal2json_escape_identifier(text); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.wal2json_escape_identifier(name text) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT
    AS $$
  -- Prefix `\`, `,`, `.`, and any whitespace with `\`
  SELECT regexp_replace(name, '([\\,.[:space:]])', '\\\1', 'g')
$$;


--
-- Name: allow_any_operation(text[]); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.allow_any_operation(expected_operations text[]) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  WITH current_operation AS (
    SELECT storage.operation() AS raw_operation
  ),
  normalized AS (
    SELECT CASE
      WHEN raw_operation LIKE 'storage.%' THEN substr(raw_operation, 9)
      ELSE raw_operation
    END AS current_operation
    FROM current_operation
  )
  SELECT EXISTS (
    SELECT 1
    FROM normalized n
    CROSS JOIN LATERAL unnest(expected_operations) AS expected_operation
    WHERE expected_operation IS NOT NULL
      AND expected_operation <> ''
      AND n.current_operation = CASE
        WHEN expected_operation LIKE 'storage.%' THEN substr(expected_operation, 9)
        ELSE expected_operation
      END
  );
$$;


--
-- Name: allow_only_operation(text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.allow_only_operation(expected_operation text) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  WITH current_operation AS (
    SELECT storage.operation() AS raw_operation
  ),
  normalized AS (
    SELECT
      CASE
        WHEN raw_operation LIKE 'storage.%' THEN substr(raw_operation, 9)
        ELSE raw_operation
      END AS current_operation,
      CASE
        WHEN expected_operation LIKE 'storage.%' THEN substr(expected_operation, 9)
        ELSE expected_operation
      END AS requested_operation
    FROM current_operation
  )
  SELECT CASE
    WHEN requested_operation IS NULL OR requested_operation = '' THEN FALSE
    ELSE COALESCE(current_operation = requested_operation, FALSE)
  END
  FROM normalized;
$$;


--
-- Name: can_insert_object(text, text, uuid, jsonb); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.can_insert_object(bucketid text, name text, owner uuid, metadata jsonb) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO "storage"."objects" ("bucket_id", "name", "owner", "metadata") VALUES (bucketid, name, owner, metadata);
  -- hack to rollback the successful insert
  RAISE sqlstate 'PT200' using
  message = 'ROLLBACK',
  detail = 'rollback successful insert';
END
$$;


--
-- Name: enforce_bucket_lifecycle_service_role(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.enforce_bucket_lifecycle_service_role() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog'
    AS $$
BEGIN
  IF current_user::text IS DISTINCT FROM TG_ARGV[0]
     AND (
       OLD.lifecycle_configuration IS DISTINCT FROM NEW.lifecycle_configuration
       OR OLD.lifecycle_configuration_generation IS DISTINCT FROM NEW.lifecycle_configuration_generation
     ) THEN
    -- AFTER runs only after caller RLS has accepted the proposed row. The API
    -- recognizes this specific error after rolling back its permission probe;
    -- direct non-service writes still fail and cannot persist the change.
    RAISE EXCEPTION 'bucket control columns may only be changed by the configured storage service role'
      USING ERRCODE = 'PST01',
            SCHEMA = TG_TABLE_SCHEMA,
            TABLE = TG_TABLE_NAME,
            CONSTRAINT = TG_NAME;
  END IF;

  RETURN NULL;
END;
$$;


--
-- Name: enforce_bucket_name_length(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.enforce_bucket_name_length() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
    if length(new.name) > 100 then
        raise exception 'bucket name "%" is too long (% characters). Max is 100.', new.name, length(new.name);
    end if;
    return new;
end;
$$;


--
-- Name: extension(text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.extension(name text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    _parts text[];
    _filename text;
BEGIN
    -- Split on "/" to get path segments
    SELECT string_to_array(name, '/') INTO _parts;
    -- Get the last path segment (the actual filename)
    SELECT _parts[array_length(_parts, 1)] INTO _filename;
    -- Extract extension: reverse, split on '.', then reverse again
    RETURN reverse(split_part(reverse(_filename), '.', 1));
END
$$;


--
-- Name: filename(text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.filename(name text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    _parts text[];
BEGIN
    SELECT string_to_array(name, '/') INTO _parts;
    RETURN _parts[array_length(_parts, 1)];
END
$$;


--
-- Name: foldername(text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.foldername(name text) RETURNS text[]
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    _parts text[];
BEGIN
    -- Split on "/" to get path segments
    SELECT string_to_array(name, '/') INTO _parts;
    -- Return everything except the last segment
    RETURN _parts[1 : array_length(_parts,1) - 1];
END
$$;


--
-- Name: get_common_prefix(text, text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.get_common_prefix(p_key text, p_prefix text, p_delimiter text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT CASE
    WHEN p_delimiter <> ''
         AND position(p_delimiter IN substring(p_key FROM length(p_prefix) + 1)) > 0
    THEN left(
        p_key,
        length(p_prefix)
            + position(p_delimiter IN substring(p_key FROM length(p_prefix) + 1))
            + length(p_delimiter) - 1
    )
    ELSE NULL
END;
$$;


--
-- Name: get_size_by_bucket(text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.get_size_by_bucket(noncurrent_versions text DEFAULT 'include'::text, delete_markers text DEFAULT 'include'::text) RETURNS TABLE(size bigint, bucket_id text)
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    -- COALESCE first: NULL NOT IN (...) evaluates to NULL (not TRUE), so a
    -- bare NOT IN check silently leaves an explicit NULL argument unreset.
    noncurrent_versions := COALESCE(noncurrent_versions, 'include');
    delete_markers := COALESCE(delete_markers, 'include');
    IF noncurrent_versions NOT IN ('exclude', 'only', 'include') THEN
        noncurrent_versions := 'include';
    END IF;
    IF delete_markers NOT IN ('exclude', 'only', 'include') THEN
        delete_markers := 'include';
    END IF;

    return query
        select sum((metadata->>'size')::bigint)::bigint as size, obj.bucket_id
        from "storage".objects as obj
        where (noncurrent_versions != 'exclude' OR obj.archived_at IS NULL)
          and (noncurrent_versions != 'only' OR obj.archived_at IS NOT NULL)
          and (delete_markers != 'exclude' OR NOT obj.is_delete_marker)
          and (delete_markers != 'only' OR obj.is_delete_marker)
        group by obj.bucket_id;
END
$$;


--
-- Name: list_multipart_uploads_with_delimiter(text, text, text, integer, text, text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.list_multipart_uploads_with_delimiter(bucket_id text, prefix_param text, delimiter_param text, max_keys integer DEFAULT 100, next_key_token text DEFAULT ''::text, next_upload_token text DEFAULT ''::text, raw_prefix_param text DEFAULT NULL::text) RETURNS TABLE(key text, id text, created_at timestamp with time zone)
    LANGUAGE sql STABLE
    AS $_$
WITH candidates AS (
    SELECT
        upload.key AS object_key,
        CASE
            WHEN position($3 IN substring(upload.key FROM length(coalesce($7, $2)) + 1)) > 0
            THEN left(
                upload.key,
                length(coalesce($7, $2))
                    + position($3 IN substring(upload.key FROM length(coalesce($7, $2)) + 1))
                    + length($3) - 1
            )
            ELSE upload.key
        END AS result_key,
        upload.id,
        upload.created_at,
        position($3 IN substring(upload.key FROM length(coalesce($7, $2)) + 1)) > 0 AS is_common_prefix
    FROM storage.s3_multipart_uploads AS upload
    WHERE upload.bucket_id = $1
      AND upload.key COLLATE "C" LIKE $2 || '%'
), filtered AS (
    SELECT candidate.*
    FROM candidates AS candidate
    WHERE $5 = ''
       OR candidate.result_key COLLATE "C" > $5
       OR (
           candidate.result_key COLLATE "C" = $5
           AND NOT candidate.is_common_prefix
           AND $6 <> ''
           -- A completed or aborted marker repeats the remaining same-key uploads.
           AND COALESCE(
               (candidate.created_at, candidate.id COLLATE "C") > (
                   SELECT marker.created_at, marker.id COLLATE "C"
                   FROM storage.s3_multipart_uploads AS marker
                   WHERE marker.bucket_id = $1
                     AND marker.key COLLATE "C" = $5
                     AND marker.id = $6
               ),
               TRUE
           )
       )
), ranked AS (
    SELECT
        filtered.*,
        row_number() OVER (
            PARTITION BY filtered.result_key COLLATE "C"
            ORDER BY filtered.created_at, filtered.id COLLATE "C"
        ) AS prefix_rank
    FROM filtered
)
SELECT ranked.result_key, ranked.id, ranked.created_at
FROM ranked
WHERE NOT ranked.is_common_prefix OR ranked.prefix_rank = 1
ORDER BY ranked.result_key COLLATE "C", ranked.created_at, ranked.id COLLATE "C"
LIMIT $4;
$_$;


--
-- Name: list_objects_with_delimiter(text, text, text, integer, text, text, text, text, text, timestamp with time zone, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.list_objects_with_delimiter(_bucket_id text, prefix_param text, delimiter_param text, max_keys integer DEFAULT 100, start_after text DEFAULT ''::text, next_token text DEFAULT ''::text, sort_order text DEFAULT 'asc'::text, noncurrent_versions text DEFAULT 'exclude'::text, delete_markers text DEFAULT 'exclude'::text, next_token_archived_at timestamp with time zone DEFAULT NULL::timestamp with time zone, next_token_version text DEFAULT ''::text) RETURNS TABLE(name text, id uuid, metadata jsonb, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, version text, archived_at timestamp with time zone, is_delete_marker boolean, is_versioned boolean)
    LANGUAGE plpgsql STABLE
    AS $_$
DECLARE
    v_peek_name TEXT;
    v_current RECORD;
    v_common_prefix TEXT;

    -- Configuration
    v_is_asc BOOLEAN;
    v_prefix TEXT;
    v_start TEXT;
    v_start_relative TEXT;
    v_upper_bound TEXT;
    v_file_batch_size INT;
    v_version_filter TEXT;

    -- true when noncurrent_versions can return >1 row per name; keeps them
    -- ordered most-recent-first and lets pagination resume mid-key
    v_multi_row BOOLEAN;
    v_name_order TEXT;
    v_exact_range_predicate TEXT;
    v_strict_range_predicate TEXT;
    v_inclusive_range_predicate TEXT;

    -- Seek state for the current name. archived_at is normalized to JavaScript's
    -- millisecond precision and version breaks ties within the same millisecond.
    -- Current rows use 'infinity'; NULL means no tiebreak has been established.
    v_next_seek TEXT;
    v_next_seek_at TIMESTAMPTZ;
    v_next_seek_version TEXT;
    v_next_seek_strict BOOLEAN := false;
    v_cursor_is_folder BOOLEAN;
    v_count INT := 0;
    v_previous_seek TEXT;
    v_previous_seek_at TIMESTAMPTZ;
    v_previous_seek_version TEXT;
    v_previous_count INT;

    -- Dynamic SQL for batch query only
    v_batch_query TEXT;
    v_batch_query_strict TEXT;
    v_delete_marker_peek_query TEXT;
    v_delete_marker_peek_query_strict TEXT;

BEGIN
    -- ========================================================================
    -- INITIALIZATION
    -- ========================================================================
    v_is_asc := lower(coalesce(sort_order, 'asc')) = 'asc';
    v_prefix := coalesce(prefix_param, '');
    v_start := CASE WHEN coalesce(next_token, '') <> '' THEN next_token ELSE coalesce(start_after, '') END;
    v_file_batch_size := LEAST(GREATEST(max_keys * 2, 100), 1000);
    v_next_seek_at := NULL;
    v_next_seek_version := '';

    -- COALESCE first: NULL NOT IN (...) evaluates to NULL (not TRUE), so a
    -- bare NOT IN check silently leaves an explicit NULL argument unreset.
    noncurrent_versions := COALESCE(noncurrent_versions, 'exclude');
    delete_markers := COALESCE(delete_markers, 'exclude');
    IF noncurrent_versions NOT IN ('exclude', 'only', 'include') THEN
        noncurrent_versions := 'exclude';
    END IF;
    IF delete_markers NOT IN ('exclude', 'only', 'include') THEN
        delete_markers := 'exclude';
    END IF;

    v_multi_row := noncurrent_versions IN ('only', 'include');
    v_name_order := CASE WHEN v_is_asc THEN 'ASC' ELSE 'DESC' END;

    v_version_filter := '';
    IF noncurrent_versions = 'exclude' THEN
        v_version_filter := v_version_filter || ' AND o.archived_at IS NULL';
    ELSIF noncurrent_versions = 'only' THEN
        v_version_filter := v_version_filter || ' AND o.archived_at IS NOT NULL';
    END IF;
    IF delete_markers = 'exclude' THEN
        v_version_filter := v_version_filter || ' AND NOT o.is_delete_marker';
    ELSIF delete_markers = 'only' THEN
        v_version_filter := v_version_filter || ' AND o.is_delete_marker';
    END IF;

    -- Calculate upper bound for prefix filtering (bytewise, using COLLATE "C")
    IF v_prefix = '' THEN
        v_upper_bound := NULL;
    ELSE
        v_upper_bound := left(v_prefix, -1) || chr(ascii(right(v_prefix, 1)) + 1);
    END IF;

    -- Keep caller-provided cursors inside the requested prefix range.
    IF v_start <> '' AND v_upper_bound IS NOT NULL THEN
        IF v_is_asc THEN
            IF v_start COLLATE "C" < v_prefix COLLATE "C" THEN
                v_start := '';
            ELSIF v_start COLLATE "C" >= v_upper_bound COLLATE "C" THEN
                RETURN;
            END IF;
        ELSE
            IF v_start COLLATE "C" < v_prefix COLLATE "C" THEN
                RETURN;
            ELSIF v_start COLLATE "C" >= v_upper_bound COLLATE "C" THEN
                v_start := '';
            END IF;
        END IF;
    END IF;

    v_start_relative := substring(v_start FROM length(v_prefix) + 1);

    -- Direction affects only the indexed name range and its ordering. Cursor
    -- state transitions and within-key version ordering stay shared.
    IF v_is_asc THEN
        v_exact_range_predicate := 'TRUE';
        v_strict_range_predicate := 'o.name COLLATE "C" > $2';
        v_inclusive_range_predicate := 'o.name COLLATE "C" >= $2';
        IF v_upper_bound IS NOT NULL THEN
            v_exact_range_predicate := 'o.name COLLATE "C" < $3';
            v_strict_range_predicate := v_strict_range_predicate || ' AND o.name COLLATE "C" < $3';
            v_inclusive_range_predicate := v_inclusive_range_predicate || ' AND o.name COLLATE "C" < $3';
        END IF;
    ELSE
        v_exact_range_predicate := 'TRUE';
        v_strict_range_predicate := 'o.name COLLATE "C" < $2';
        v_inclusive_range_predicate := 'o.name COLLATE "C" < $2';
        IF v_prefix <> '' THEN
            v_exact_range_predicate := 'o.name COLLATE "C" >= $3';
            v_strict_range_predicate := v_strict_range_predicate || ' AND o.name COLLATE "C" >= $3';
            v_inclusive_range_predicate := v_inclusive_range_predicate || ' AND o.name COLLATE "C" >= $3';
        END IF;
    END IF;

    -- Build batch query (dynamic SQL - called infrequently, amortized over many rows)
    -- The multi-row order matches the externally serialized cursor exactly:
    -- archived_at at millisecond precision, then version as the final tiebreak.
    --
    -- When v_multi_row, the seek is a keyset tuple comparison ("name > $2 OR
    -- (name = $2 AND tiebreak)") - Postgres won't split that OR into indexable
    -- form (confirmed even with fully literal values), so as one WHERE clause
    -- it forces a full bucket scan filtered row-by-row. Splitting it into two
    -- independently-indexable branches (exact name match with the tiebreak
    -- filter, vs. strictly-past names) combined with UNION ALL lets each
    -- branch keep name as a real index condition; the outer ORDER BY/LIMIT
    -- re-merges them into the same page the single query used to produce.
    IF v_multi_row THEN
        v_batch_query := format(
            $sql$
            SELECT *
            FROM (
                (
                    SELECT o.name, o.id, o.updated_at, o.created_at,
                           o.last_accessed_at, o.metadata, o.version,
                           o.archived_at, o.is_delete_marker, o.is_versioned
                    FROM storage.objects o
                    WHERE o.bucket_id = $1
                      AND o.name COLLATE "C" = $2
                      AND %s
                      AND NOT $7::boolean
                      AND (
                          $5::timestamptz IS NULL
                          OR COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) < $5
                          OR (
                              COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) = $5
                              AND COALESCE(o.version, '') > $6
                          )
                      )
                      %s
                    ORDER BY
                        COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) DESC,
                        COALESCE(o.version, '') ASC
                    LIMIT $4
                )
                UNION ALL
                (
                    SELECT o.name, o.id, o.updated_at, o.created_at,
                           o.last_accessed_at, o.metadata, o.version,
                           o.archived_at, o.is_delete_marker, o.is_versioned
                    FROM storage.objects o
                    WHERE o.bucket_id = $1
                      AND %s
                      %s
                    ORDER BY
                        o.name COLLATE "C" %s,
                        COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) DESC,
                        COALESCE(o.version, '') ASC
                    LIMIT $4
                )
            ) sub
            ORDER BY
                sub.name COLLATE "C" %s,
                COALESCE(date_trunc('milliseconds', sub.archived_at), 'infinity'::timestamptz) DESC,
                COALESCE(sub.version, '') ASC
            LIMIT $4
            $sql$,
            v_exact_range_predicate,
            v_version_filter,
            v_strict_range_predicate,
            v_version_filter,
            v_name_order,
            v_name_order
        );
    ELSE
        v_batch_query := format(
            $sql$
            SELECT o.name, o.id, o.updated_at, o.created_at,
                   o.last_accessed_at, o.metadata, o.version,
                   o.archived_at, o.is_delete_marker, o.is_versioned
            FROM storage.objects o
            WHERE o.bucket_id = $1
              AND %s
              %s
            ORDER BY o.name COLLATE "C" %s, o.archived_at DESC
            LIMIT $4
            $sql$,
            v_inclusive_range_predicate,
            v_version_filter,
            v_name_order
        );

        -- Strict counterpart of the query above: used once the single-row
        -- ASC batch advance (below) has left v_next_seek pointing at the
        -- last row already emitted, so an inclusive predicate would
        -- re-match it forever. Only single-row mode ever sets strict mode,
        -- so this variant is never needed when v_multi_row.
        v_batch_query_strict := format(
            $sql$
            SELECT o.name, o.id, o.updated_at, o.created_at,
                   o.last_accessed_at, o.metadata, o.version,
                   o.archived_at, o.is_delete_marker, o.is_versioned
            FROM storage.objects o
            WHERE o.bucket_id = $1
              AND %s
              %s
            ORDER BY o.name COLLATE "C" %s, o.archived_at DESC
            LIMIT $4
            $sql$,
            v_strict_range_predicate,
            v_version_filter,
            v_name_order
        );
    END IF;

    -- The static peek predicates cannot use the partial delete-marker index
    -- once PL/pgSQL switches to a generic plan because whether
    -- is_delete_marker is required remains parameter-dependent. Reuse the
    -- already-specialized batch query with a one-row limit for this sparse
    -- filter so the plan sees a literal `o.is_delete_marker` predicate.
    IF delete_markers = 'only' THEN
        v_delete_marker_peek_query :=
            'SELECT marker_page.name FROM (' || v_batch_query || ') marker_page LIMIT 1';
        IF NOT v_multi_row THEN
            v_delete_marker_peek_query_strict :=
                'SELECT marker_page.name FROM (' || v_batch_query_strict || ') marker_page LIMIT 1';
        END IF;
    END IF;

    -- ========================================================================
    -- SEEK INITIALIZATION: Determine starting position
    -- ========================================================================
    IF v_start = '' THEN
        IF v_is_asc THEN
            v_next_seek := v_prefix;
        ELSE
            -- DESC without cursor performs one specialized initial seek so
            -- partial current-version and delete-marker indexes remain available.
            EXECUTE format(
                'SELECT o.name FROM storage.objects o WHERE o.bucket_id = $1%s%s ORDER BY o.name COLLATE "C" DESC LIMIT 1',
                CASE WHEN v_upper_bound IS NOT NULL
                    THEN ' AND o.name COLLATE "C" >= $2 AND o.name COLLATE "C" < $3'
                    ELSE ''
                END,
                v_version_filter
            )
            INTO v_next_seek
            USING _bucket_id, v_prefix, v_upper_bound;

            IF v_next_seek IS NOT NULL THEN
                v_next_seek := v_next_seek || delimiter_param;
            ELSE
                RETURN;
            END IF;
        END IF;
    ELSE
        -- Folder continuation tokens retain their trailing delimiter. A
        -- delimiter-less startAfter is always a literal key boundary.
        v_cursor_is_folder := delimiter_param <> ''
            AND v_start_relative <> ''
            AND right(v_start_relative, length(delimiter_param)) = delimiter_param;

        IF v_cursor_is_folder THEN
            v_next_seek := CASE
                WHEN right(v_start, length(delimiter_param)) = delimiter_param
                    THEN v_start
                ELSE v_start || delimiter_param
            END;
            IF v_is_asc THEN
                v_next_seek := left(v_next_seek, -1)
                    || chr(ascii(right(v_next_seek, 1)) + 1);
            END IF;
            v_next_seek_strict := NOT v_is_asc;
        ELSE
            -- leaf object: when v_multi_row, stay on v_start with the
            -- caller-supplied tiebreak so a page boundary mid-key resumes
            -- that key's remaining rows instead of skipping them. Truncate
            -- to milliseconds like every other v_next_seek_at assignment -
            -- harmless today since object.ts's cursor always round-trips
            -- through JS Date first, but this shouldn't rely on that.
            IF v_multi_row THEN
                v_next_seek := v_start;
                v_next_seek_at := date_trunc('milliseconds', next_token_archived_at);
                v_next_seek_version := coalesce(next_token_version, '');
                v_next_seek_strict := coalesce(next_token, '') = '';
            ELSIF v_is_asc THEN
                v_next_seek := v_start;
                v_next_seek_strict := true;
            ELSE
                v_next_seek := v_start;
            END IF;
        END IF;
    END IF;

    -- ========================================================================
    -- MAIN LOOP: Hybrid peek-then-batch algorithm
    -- Uses STATIC SQL for peek (hot path) and DYNAMIC SQL for batch
    -- ========================================================================
    LOOP
        EXIT WHEN v_count >= max_keys;

        v_previous_seek := v_next_seek;
        v_previous_seek_at := v_next_seek_at;
        v_previous_seek_version := v_next_seek_version;
        v_previous_count := v_count;

        -- STEP 1: PEEK using STATIC SQL (plan cached, very fast)
        -- v_multi_row is branched here (rather than folded into the WHERE
        -- clause as a bound parameter) so each concrete query keeps an
        -- unconditional seek predicate - once PL/pgSQL switches to its
        -- cached generic plan (after 5 calls), a parameter-gated
        -- "(NOT v_multi_row AND name >= $x) OR (v_multi_row AND ...)"
        -- predicate stops the planner from using name as an index
        -- condition at all, degrading every subsequent peek to a full
        -- index scan filtered row-by-row instead of a bounded range scan.
        -- v_multi_row's seek predicate is a keyset tuple comparison
        -- ("name > x OR (name = x AND tiebreak)") - Postgres does not
        -- split this OR into indexable form even with fully literal
        -- values, so it falls back to a full scan filtered row-by-row.
        -- Splitting it into two independently-indexable branches (exact
        -- name match with the tiebreak filter, vs. strictly-past name)
        -- combined with UNION ALL lets each branch keep name as a real
        -- index condition; the outer ORDER BY/LIMIT picks whichever of
        -- the (at most 2) rows sorts first.
        IF delete_markers = 'only' THEN
            EXECUTE CASE WHEN v_next_seek_strict AND NOT v_multi_row
                THEN v_delete_marker_peek_query_strict
                ELSE v_delete_marker_peek_query
            END
                INTO v_peek_name
                USING _bucket_id, v_next_seek,
                    CASE WHEN v_is_asc THEN COALESCE(v_upper_bound, v_prefix) ELSE v_prefix END,
                    1, v_next_seek_at, v_next_seek_version, v_next_seek_strict;
        ELSIF v_multi_row THEN
            IF v_is_asc THEN
                IF v_upper_bound IS NOT NULL THEN
                    SELECT sub.name INTO v_peek_name FROM (
                        (SELECT o.name FROM storage.objects o
                         WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" = v_next_seek
                           AND o.name COLLATE "C" < v_upper_bound
                           AND NOT v_next_seek_strict
                           AND (v_next_seek_at IS NULL
                                OR COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) < v_next_seek_at
                                OR (COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) = v_next_seek_at
                                    AND COALESCE(o.version, '') > v_next_seek_version))
                           AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                           AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                           AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                           AND (delete_markers != 'only' OR o.is_delete_marker)
                         ORDER BY COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) DESC, COALESCE(o.version, '') ASC LIMIT 1)
                        UNION ALL
                        (SELECT o.name FROM storage.objects o
                         WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" > v_next_seek AND o.name COLLATE "C" < v_upper_bound
                           AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                           AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                           AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                           AND (delete_markers != 'only' OR o.is_delete_marker)
                         ORDER BY o.name COLLATE "C" ASC LIMIT 1)
                    ) sub ORDER BY sub.name COLLATE "C" ASC LIMIT 1;
                ELSE
                    SELECT sub.name INTO v_peek_name FROM (
                        (SELECT o.name FROM storage.objects o
                         WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" = v_next_seek
                           AND NOT v_next_seek_strict
                           AND (v_next_seek_at IS NULL
                                OR COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) < v_next_seek_at
                                OR (COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) = v_next_seek_at
                                    AND COALESCE(o.version, '') > v_next_seek_version))
                           AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                           AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                           AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                           AND (delete_markers != 'only' OR o.is_delete_marker)
                         ORDER BY COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) DESC, COALESCE(o.version, '') ASC LIMIT 1)
                        UNION ALL
                        (SELECT o.name FROM storage.objects o
                         WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" > v_next_seek
                           AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                           AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                           AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                           AND (delete_markers != 'only' OR o.is_delete_marker)
                         ORDER BY o.name COLLATE "C" ASC LIMIT 1)
                    ) sub ORDER BY sub.name COLLATE "C" ASC LIMIT 1;
                END IF;
            ELSE
                IF v_upper_bound IS NOT NULL THEN
                    SELECT sub.name INTO v_peek_name FROM (
                        (SELECT o.name FROM storage.objects o
                         WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" = v_next_seek
                           AND o.name COLLATE "C" >= v_prefix
                           AND NOT v_next_seek_strict
                           AND (v_next_seek_at IS NULL
                                OR COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) < v_next_seek_at
                                OR (COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) = v_next_seek_at
                                    AND COALESCE(o.version, '') > v_next_seek_version))
                           AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                           AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                           AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                           AND (delete_markers != 'only' OR o.is_delete_marker)
                         ORDER BY COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) DESC, COALESCE(o.version, '') ASC LIMIT 1)
                        UNION ALL
                        (SELECT o.name FROM storage.objects o
                         WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" < v_next_seek AND o.name COLLATE "C" >= v_prefix
                           AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                           AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                           AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                           AND (delete_markers != 'only' OR o.is_delete_marker)
                         ORDER BY o.name COLLATE "C" DESC LIMIT 1)
                    ) sub ORDER BY sub.name COLLATE "C" DESC LIMIT 1;
                ELSE
                    SELECT sub.name INTO v_peek_name FROM (
                        (SELECT o.name FROM storage.objects o
                         WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" = v_next_seek
                           AND NOT v_next_seek_strict
                           AND (v_next_seek_at IS NULL
                                OR COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) < v_next_seek_at
                                OR (COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) = v_next_seek_at
                                    AND COALESCE(o.version, '') > v_next_seek_version))
                           AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                           AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                           AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                           AND (delete_markers != 'only' OR o.is_delete_marker)
                         ORDER BY COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) DESC, COALESCE(o.version, '') ASC LIMIT 1)
                        UNION ALL
                        (SELECT o.name FROM storage.objects o
                         WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" < v_next_seek
                           AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                           AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                           AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                           AND (delete_markers != 'only' OR o.is_delete_marker)
                         ORDER BY o.name COLLATE "C" DESC LIMIT 1)
                    ) sub ORDER BY sub.name COLLATE "C" DESC LIMIT 1;
                END IF;
            END IF;
        ELSE
            -- Single-row mode is always noncurrent_versions='exclude'. Keep
            -- this predicate literal so generic plans use the current index.
            IF v_is_asc THEN
                IF v_next_seek_strict AND v_upper_bound IS NOT NULL THEN
                    SELECT o.name INTO v_peek_name FROM storage.objects o
                    WHERE o.bucket_id = _bucket_id
                      AND o.name COLLATE "C" > v_next_seek
                      AND o.name COLLATE "C" < v_upper_bound
                      AND o.archived_at IS NULL
                      AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                      AND (delete_markers != 'only' OR o.is_delete_marker)
                    ORDER BY o.name COLLATE "C" ASC LIMIT 1;
                ELSIF v_next_seek_strict THEN
                    SELECT o.name INTO v_peek_name FROM storage.objects o
                    WHERE o.bucket_id = _bucket_id
                      AND o.name COLLATE "C" > v_next_seek
                      AND o.archived_at IS NULL
                      AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                      AND (delete_markers != 'only' OR o.is_delete_marker)
                    ORDER BY o.name COLLATE "C" ASC LIMIT 1;
                ELSIF v_upper_bound IS NOT NULL THEN
                    SELECT o.name INTO v_peek_name FROM storage.objects o
                    WHERE o.bucket_id = _bucket_id
                      AND o.name COLLATE "C" >= v_next_seek
                      AND o.name COLLATE "C" < v_upper_bound
                      AND o.archived_at IS NULL
                      AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                      AND (delete_markers != 'only' OR o.is_delete_marker)
                    ORDER BY o.name COLLATE "C" ASC LIMIT 1;
                ELSE
                    SELECT o.name INTO v_peek_name FROM storage.objects o
                    WHERE o.bucket_id = _bucket_id
                      AND o.name COLLATE "C" >= v_next_seek
                      AND o.archived_at IS NULL
                      AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                      AND (delete_markers != 'only' OR o.is_delete_marker)
                    ORDER BY o.name COLLATE "C" ASC LIMIT 1;
                END IF;
            ELSE
                IF v_upper_bound IS NOT NULL THEN
                    SELECT o.name INTO v_peek_name FROM storage.objects o
                    WHERE o.bucket_id = _bucket_id
                      AND o.name COLLATE "C" < v_next_seek
                      AND o.name COLLATE "C" >= v_prefix
                      AND o.archived_at IS NULL
                      AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                      AND (delete_markers != 'only' OR o.is_delete_marker)
                    ORDER BY o.name COLLATE "C" DESC LIMIT 1;
                ELSE
                    SELECT o.name INTO v_peek_name FROM storage.objects o
                    WHERE o.bucket_id = _bucket_id
                      AND o.name COLLATE "C" < v_next_seek
                      AND o.archived_at IS NULL
                      AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                      AND (delete_markers != 'only' OR o.is_delete_marker)
                    ORDER BY o.name COLLATE "C" DESC LIMIT 1;
                END IF;
            END IF;
        END IF;

        EXIT WHEN v_peek_name IS NULL;

        -- STEP 2: Check if this is a FOLDER or FILE
        v_common_prefix := storage.get_common_prefix(v_peek_name, v_prefix, delimiter_param);

        IF v_common_prefix IS NOT NULL THEN
            -- FOLDER: Emit and skip to next folder (no heap access needed)
            name := v_common_prefix;
            id := NULL;
            updated_at := NULL;
            created_at := NULL;
            last_accessed_at := NULL;
            metadata := NULL;
            version := NULL;
            archived_at := NULL;
            is_delete_marker := NULL;
            is_versioned := NULL;
            RETURN NEXT;
            v_count := v_count + 1;

            -- Advance seek past the folder range
            IF v_is_asc THEN
                v_next_seek := left(v_common_prefix, -1)
                    || chr(ascii(right(v_common_prefix, 1)) + 1);
            ELSE
                v_next_seek := v_common_prefix;
            END IF;
            v_next_seek_at := NULL;
            v_next_seek_version := '';
            v_next_seek_strict := NOT v_is_asc;
        ELSE
            -- FILE: Batch fetch using DYNAMIC SQL (overhead amortized over many rows)
            -- For ASC: upper_bound is the exclusive upper limit (< condition)
            -- For DESC: prefix is the inclusive lower limit (>= condition)
            FOR v_current IN EXECUTE CASE WHEN v_next_seek_strict AND NOT v_multi_row THEN v_batch_query_strict ELSE v_batch_query END
                USING _bucket_id, v_next_seek,
                CASE WHEN v_is_asc THEN COALESCE(v_upper_bound, v_prefix) ELSE v_prefix END, v_file_batch_size, v_next_seek_at, v_next_seek_version,
                v_next_seek_strict
            LOOP
                v_common_prefix := storage.get_common_prefix(v_current.name, v_prefix, delimiter_param);

                IF v_common_prefix IS NOT NULL THEN
                    -- Hit a folder: exit batch, let peek handle it. Reset
                    -- strict mode too it may have been set by an earlier
                    -- row in this same batch (see the single-row ASC advance
                    -- below), and v_next_seek here is the folder-triggering
                    -- row's own name, which the next peek must find inclusively.
                    v_next_seek := CASE
                        WHEN v_is_asc THEN v_current.name
                        ELSE v_current.name || delimiter_param
                    END;
                    v_next_seek_at := NULL;
                    v_next_seek_version := '';
                    v_next_seek_strict := false;
                    EXIT;
                END IF;

                -- Emit file
                name := v_current.name;
                id := v_current.id;
                updated_at := v_current.updated_at;
                created_at := v_current.created_at;
                last_accessed_at := v_current.last_accessed_at;
                metadata := v_current.metadata;
                version := v_current.version;
                archived_at := v_current.archived_at;
                is_delete_marker := v_current.is_delete_marker;
                is_versioned := v_current.is_versioned;
                RETURN NEXT;
                v_count := v_count + 1;

                -- when v_multi_row, stay on this name and record its
                -- archived_at as the new tiebreak so remaining rows for the
                -- same key are picked up before moving to the next name
                IF v_multi_row THEN
                    v_next_seek := v_current.name;
                    v_next_seek_at := COALESCE(date_trunc('milliseconds', v_current.archived_at), 'infinity'::timestamptz);
                    v_next_seek_version := COALESCE(v_current.version, '');
                    v_next_seek_strict := false;
                ELSIF v_is_asc THEN
                    -- Appending the delimiter as a fake lexical successor
                    -- would skip a real key like `name || '!'` (or any
                    -- character sorting below the delimiter), which sorts
                    -- between `name` and `name || delimiter`. Track the real
                    -- name and mark the next comparison strict instead.
                    v_next_seek := v_current.name;
                    v_next_seek_strict := true;
                ELSE
                    v_next_seek := v_current.name;
                END IF;

                EXIT WHEN v_count >= max_keys;
            END LOOP;
        END IF;

        IF v_count = v_previous_count
           AND v_next_seek IS NOT DISTINCT FROM v_previous_seek
           AND v_next_seek_at IS NOT DISTINCT FROM v_previous_seek_at
           AND v_next_seek_version IS NOT DISTINCT FROM v_previous_seek_version THEN
            RAISE EXCEPTION 'storage.list_objects_with_delimiter made no progress at seek (%, %, %)',
                v_next_seek, v_next_seek_at, v_next_seek_version;
        END IF;
    END LOOP;
END;
$_$;


--
-- Name: operation(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.operation() RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    RETURN current_setting('storage.operation', true);
END;
$$;


--
-- Name: protect_bucket_control_columns(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.protect_bucket_control_columns() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog'
    AS $$
DECLARE
  configuration_changed boolean;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.lifecycle_configuration IS NOT NULL
       OR NEW.lifecycle_configuration_generation IS NOT NULL THEN
      IF NOT pg_has_role(current_user, TG_ARGV[0], 'MEMBER') THEN
        RAISE EXCEPTION 'only members of the configured storage service role may insert lifecycle policy state'
          USING ERRCODE = '42501',
                HINT = format(
                  'Insert with both lifecycle columns NULL and configure lifecycle through the Storage API afterward, or insert as a member of %I.',
                  TG_ARGV[0]
                );
      END IF;
    END IF;

    RETURN NEW;
  END IF;

  configuration_changed =
    OLD.lifecycle_configuration IS DISTINCT FROM NEW.lifecycle_configuration
    OR OLD.lifecycle_configuration_generation IS DISTINCT FROM NEW.lifecycle_configuration_generation;

  IF NOT configuration_changed THEN
    RETURN NEW;
  END IF;

  IF NEW.type IS DISTINCT FROM 'STANDARD' THEN
    RAISE EXCEPTION 'bucket versioning and lifecycle controls require a Standard bucket'
      USING ERRCODE = '0A000';
  END IF;

  IF NEW.lifecycle_configuration IS NULL
     AND NEW.lifecycle_configuration_generation IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.lifecycle_configuration IS NULL
     OR NEW.lifecycle_configuration_generation IS NULL
     OR OLD.lifecycle_configuration IS NOT DISTINCT FROM NEW.lifecycle_configuration
     OR OLD.lifecycle_configuration_generation IS NOT DISTINCT FROM NEW.lifecycle_configuration_generation THEN
    RAISE EXCEPTION 'a changed lifecycle policy requires a new non-null generation'
      USING ERRCODE = '22023';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: protect_delete(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.protect_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Check if storage.allow_delete_query is set to 'true'
    IF COALESCE(current_setting('storage.allow_delete_query', true), 'false') != 'true' THEN
        RAISE EXCEPTION 'Direct deletion from storage tables is not allowed. Use the Storage API instead.'
            USING HINT = 'This prevents accidental data loss from orphaned objects.',
                  ERRCODE = '42501';
    END IF;
    RETURN NULL;
END;
$$;


--
-- Name: search(text, text, integer, integer, integer, text, text, text, text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.search(prefix text, bucketname text, limits integer DEFAULT 100, levels integer DEFAULT 1, offsets integer DEFAULT 0, search text DEFAULT ''::text, sortcolumn text DEFAULT 'name'::text, sortorder text DEFAULT 'asc'::text, noncurrent_versions text DEFAULT 'exclude'::text, delete_markers text DEFAULT 'exclude'::text) RETURNS TABLE(name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb, version text, archived_at timestamp with time zone, is_delete_marker boolean, is_versioned boolean)
    LANGUAGE plpgsql STABLE
    AS $_$
DECLARE
    v_peek_name TEXT;
    v_current RECORD;
    v_common_prefix TEXT;
    v_delimiter CONSTANT TEXT := '/';

    -- Configuration
    v_limit INT;
    v_prefix TEXT;
    v_prefix_lower TEXT;
    v_prefix_len INT;
    v_prefix_start INT;
    v_combined_levels INT;
    v_is_asc BOOLEAN;
    v_order_by TEXT;
    v_sort_order TEXT;
    v_upper_bound TEXT;
    v_file_batch_size INT;
    v_version_filter TEXT;
    v_multi_row BOOLEAN;

    -- Dynamic SQL for batch query only
    v_batch_query TEXT;
    v_delete_marker_peek_query TEXT;
    v_delete_marker_peek_query_strict TEXT;

    -- Seek state
    v_next_seek TEXT;
    v_next_seek_at TIMESTAMPTZ;
    v_next_seek_version TEXT;
    v_next_seek_strict BOOLEAN := false;
    v_count INT := 0;
    v_skipped INT := 0;
    v_previous_seek TEXT;
    v_previous_seek_at TIMESTAMPTZ;
    v_previous_seek_version TEXT;
    v_previous_count INT;
    v_previous_skipped INT;
BEGIN
    -- ========================================================================
    -- INITIALIZATION
    -- ========================================================================
    v_limit := LEAST(coalesce(limits, 100), 1500);
    v_prefix := coalesce(prefix, '') || coalesce(search, '');
    v_prefix_lower := lower(v_prefix);
    v_prefix_len := length(coalesce(prefix, ''));
    v_prefix_start := coalesce(array_length(string_to_array(coalesce(prefix, ''), v_delimiter), 1), 1);
    v_combined_levels := coalesce(array_length(string_to_array(v_prefix, v_delimiter), 1), 1);
    v_is_asc := lower(coalesce(sortorder, 'asc')) = 'asc';
    v_file_batch_size := LEAST(GREATEST(v_limit * 2, 100), 1000);
    v_next_seek_at := NULL;
    v_next_seek_version := '';

    -- COALESCE first: NULL NOT IN (...) evaluates to NULL (not TRUE), so a
    -- bare NOT IN check silently leaves an explicit NULL argument unreset.
    noncurrent_versions := COALESCE(noncurrent_versions, 'exclude');
    delete_markers := COALESCE(delete_markers, 'exclude');
    IF noncurrent_versions NOT IN ('exclude', 'only', 'include') THEN
        noncurrent_versions := 'exclude';
    END IF;
    IF delete_markers NOT IN ('exclude', 'only', 'include') THEN
        delete_markers := 'exclude';
    END IF;

    v_multi_row := noncurrent_versions IN ('only', 'include');

    v_version_filter := '';
    IF noncurrent_versions = 'exclude' THEN
        v_version_filter := v_version_filter || ' AND o.archived_at IS NULL';
    ELSIF noncurrent_versions = 'only' THEN
        v_version_filter := v_version_filter || ' AND o.archived_at IS NOT NULL';
    END IF;
    IF delete_markers = 'exclude' THEN
        v_version_filter := v_version_filter || ' AND NOT o.is_delete_marker';
    ELSIF delete_markers = 'only' THEN
        v_version_filter := v_version_filter || ' AND o.is_delete_marker';
    END IF;

    -- Validate sort column
    CASE lower(coalesce(sortcolumn, 'name'))
        WHEN 'name' THEN v_order_by := 'name';
        WHEN 'updated_at' THEN v_order_by := 'updated_at';
        WHEN 'created_at' THEN v_order_by := 'created_at';
        WHEN 'last_accessed_at' THEN v_order_by := 'last_accessed_at';
        ELSE v_order_by := 'name';
    END CASE;

    v_sort_order := CASE WHEN v_is_asc THEN 'asc' ELSE 'desc' END;

    -- ========================================================================
    -- NON-NAME SORTING: Use path_tokens approach
    -- ========================================================================
    IF v_order_by != 'name' THEN
        RETURN QUERY EXECUTE format(
            $sql$
            WITH folders AS (
                SELECT array_to_string(path_tokens[$1:$2], '/') AS folder
                FROM storage.objects
                WHERE objects.name ILIKE $3 || '%%'
                  AND bucket_id = $4
                  AND array_length(objects.path_tokens, 1) <> $2
                  AND ($7 != 'exclude' OR objects.archived_at IS NULL)
                  AND ($7 != 'only' OR objects.archived_at IS NOT NULL)
                  AND ($8 != 'exclude' OR NOT objects.is_delete_marker)
                  AND ($8 != 'only' OR objects.is_delete_marker)
                GROUP BY folder
                ORDER BY folder %s
            )
            (SELECT folder AS "name",
                   NULL::uuid AS id,
                   NULL::timestamptz AS updated_at,
                   NULL::timestamptz AS created_at,
                   NULL::timestamptz AS last_accessed_at,
                   NULL::jsonb AS metadata,
                   NULL::text AS version,
                   NULL::timestamptz AS archived_at,
                   NULL::boolean AS is_delete_marker,
                   NULL::boolean AS is_versioned FROM folders)
            UNION ALL
            (SELECT array_to_string(path_tokens[$1:$2], '/') AS "name",
                   id, updated_at, created_at, last_accessed_at, metadata,
                   version, archived_at, is_delete_marker, is_versioned
             FROM storage.objects
             WHERE objects.name ILIKE $3 || '%%'
               AND bucket_id = $4
               AND array_length(objects.path_tokens, 1) = $2
               AND ($7 != 'exclude' OR objects.archived_at IS NULL)
               AND ($7 != 'only' OR objects.archived_at IS NOT NULL)
               AND ($8 != 'exclude' OR NOT objects.is_delete_marker)
               AND ($8 != 'only' OR objects.is_delete_marker)
             -- name, then version, as tiebreaks so two versions of the same
             -- key tying on the sort column still sort deterministically
             ORDER BY %I %s, name COLLATE "C" %s, COALESCE(version, '') %s)
            LIMIT $5 OFFSET $6
            $sql$, v_sort_order, v_order_by, v_sort_order, v_sort_order, v_sort_order
        ) USING v_prefix_start, v_combined_levels, v_prefix, bucketname, v_limit, offsets, noncurrent_versions, delete_markers;
        RETURN;
    END IF;

    -- ========================================================================
    -- NAME SORTING: Hybrid skip-scan with batch optimization
    -- ========================================================================

    -- Calculate upper bound for prefix filtering
    IF v_prefix_lower = '' THEN
        v_upper_bound := NULL;
    ELSIF right(v_prefix_lower, 1) = v_delimiter THEN
        v_upper_bound := left(v_prefix_lower, -1) || chr(ascii(v_delimiter) + 1);
    ELSE
        v_upper_bound := left(v_prefix_lower, -1) || chr(ascii(right(v_prefix_lower, 1)) + 1);
    END IF;

    -- Build a resume-safe batch query. The exact-name branch returns remaining
    -- versions after the current (archived_at, version) boundary; the strict
    -- name branch returns subsequent keys. UNION ALL keeps both predicates
    -- independently indexable.
    IF v_is_asc THEN
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT * FROM (' ||
                '(SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata, o.version, o.archived_at, o.is_delete_marker, o.is_versioned FROM storage.objects o ' ||
                'WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" = $2 AND ($5::timestamptz IS NULL OR COALESCE(o.archived_at, ''infinity''::timestamptz) < $5 OR (COALESCE(o.archived_at, ''infinity''::timestamptz) = $5 AND COALESCE(o.version, '''') > $6))' ||
                v_version_filter || ' ORDER BY COALESCE(o.archived_at, ''infinity''::timestamptz) DESC, COALESCE(o.version, '''') ASC LIMIT $4) UNION ALL ' ||
                '(SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata, o.version, o.archived_at, o.is_delete_marker, o.is_versioned FROM storage.objects o ' ||
                'WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" > $2 AND lower(o.name) COLLATE "C" < $3' || v_version_filter ||
                ' ORDER BY lower(o.name) COLLATE "C" ASC, COALESCE(o.archived_at, ''infinity''::timestamptz) DESC, COALESCE(o.version, '''') ASC LIMIT $4)' ||
                ') sub ORDER BY lower(sub.name) COLLATE "C" ASC, COALESCE(sub.archived_at, ''infinity''::timestamptz) DESC, COALESCE(sub.version, '''') ASC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT * FROM (' ||
                '(SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata, o.version, o.archived_at, o.is_delete_marker, o.is_versioned FROM storage.objects o ' ||
                'WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" = $2 AND ($5::timestamptz IS NULL OR COALESCE(o.archived_at, ''infinity''::timestamptz) < $5 OR (COALESCE(o.archived_at, ''infinity''::timestamptz) = $5 AND COALESCE(o.version, '''') > $6))' ||
                v_version_filter || ' ORDER BY COALESCE(o.archived_at, ''infinity''::timestamptz) DESC, COALESCE(o.version, '''') ASC LIMIT $4) UNION ALL ' ||
                '(SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata, o.version, o.archived_at, o.is_delete_marker, o.is_versioned FROM storage.objects o ' ||
                'WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" > $2' || v_version_filter ||
                ' ORDER BY lower(o.name) COLLATE "C" ASC, COALESCE(o.archived_at, ''infinity''::timestamptz) DESC, COALESCE(o.version, '''') ASC LIMIT $4)' ||
                ') sub ORDER BY lower(sub.name) COLLATE "C" ASC, COALESCE(sub.archived_at, ''infinity''::timestamptz) DESC, COALESCE(sub.version, '''') ASC LIMIT $4';
        END IF;
    ELSE
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT * FROM (' ||
                '(SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata, o.version, o.archived_at, o.is_delete_marker, o.is_versioned FROM storage.objects o ' ||
                'WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" = $2 AND ($5::timestamptz IS NULL OR COALESCE(o.archived_at, ''infinity''::timestamptz) < $5 OR (COALESCE(o.archived_at, ''infinity''::timestamptz) = $5 AND COALESCE(o.version, '''') > $6))' ||
                v_version_filter || ' ORDER BY COALESCE(o.archived_at, ''infinity''::timestamptz) DESC, COALESCE(o.version, '''') ASC LIMIT $4) UNION ALL ' ||
                '(SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata, o.version, o.archived_at, o.is_delete_marker, o.is_versioned FROM storage.objects o ' ||
                'WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" < $2 AND lower(o.name) COLLATE "C" >= $3' || v_version_filter ||
                ' ORDER BY lower(o.name) COLLATE "C" DESC, COALESCE(o.archived_at, ''infinity''::timestamptz) DESC, COALESCE(o.version, '''') ASC LIMIT $4)' ||
                ') sub ORDER BY lower(sub.name) COLLATE "C" DESC, COALESCE(sub.archived_at, ''infinity''::timestamptz) DESC, COALESCE(sub.version, '''') ASC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT * FROM (' ||
                '(SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata, o.version, o.archived_at, o.is_delete_marker, o.is_versioned FROM storage.objects o ' ||
                'WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" = $2 AND ($5::timestamptz IS NULL OR COALESCE(o.archived_at, ''infinity''::timestamptz) < $5 OR (COALESCE(o.archived_at, ''infinity''::timestamptz) = $5 AND COALESCE(o.version, '''') > $6))' ||
                v_version_filter || ' ORDER BY COALESCE(o.archived_at, ''infinity''::timestamptz) DESC, COALESCE(o.version, '''') ASC LIMIT $4) UNION ALL ' ||
                '(SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata, o.version, o.archived_at, o.is_delete_marker, o.is_versioned FROM storage.objects o ' ||
                'WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" < $2' || v_version_filter ||
                ' ORDER BY lower(o.name) COLLATE "C" DESC, COALESCE(o.archived_at, ''infinity''::timestamptz) DESC, COALESCE(o.version, '''') ASC LIMIT $4)' ||
                ') sub ORDER BY lower(sub.name) COLLATE "C" DESC, COALESCE(sub.archived_at, ''infinity''::timestamptz) DESC, COALESCE(sub.version, '''') ASC LIMIT $4';
        END IF;
    END IF;

    -- Keep the delete-marker predicate literal so the cached generic
    -- plan can use idx_objects_delete_markers during the main-loop peek.
    IF delete_markers = 'only' THEN
        IF v_multi_row THEN
            v_delete_marker_peek_query :=
                'SELECT marker_page.name FROM (' || v_batch_query || ') marker_page LIMIT 1';
        ELSIF v_is_asc THEN
            -- Two separate literal query strings, not one gated by a bound
            -- boolean: folding "$n AND op1 OR NOT $n AND op2" into a single
            -- query defeats the generic plan's ability to push either
            -- comparison into the index. Branching in PL/pgSQL control flow
            -- instead keeps each query's index condition intact.
            v_delete_marker_peek_query :=
                'SELECT o.name FROM storage.objects o WHERE o.bucket_id = $1 ' ||
                'AND lower(o.name) COLLATE "C" >= $2' ||
                CASE WHEN v_upper_bound IS NOT NULL
                    THEN ' AND lower(o.name) COLLATE "C" < $3'
                    ELSE ''
                END ||
                v_version_filter ||
                ' ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1';
            -- Strict variant: used once the single-row ASC batch advance
            -- (below) has left v_next_seek pointing at the last row already
            -- emitted, so a plain >= would re-match it forever.
            v_delete_marker_peek_query_strict :=
                'SELECT o.name FROM storage.objects o WHERE o.bucket_id = $1 ' ||
                'AND lower(o.name) COLLATE "C" > $2' ||
                CASE WHEN v_upper_bound IS NOT NULL
                    THEN ' AND lower(o.name) COLLATE "C" < $3'
                    ELSE ''
                END ||
                v_version_filter ||
                ' ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1';
        ELSE
            v_delete_marker_peek_query :=
                'SELECT o.name FROM storage.objects o WHERE o.bucket_id = $1 ' ||
                'AND lower(o.name) COLLATE "C" < $2' ||
                CASE WHEN v_upper_bound IS NOT NULL
                    THEN ' AND lower(o.name) COLLATE "C" >= $3'
                    ELSE ''
                END ||
                v_version_filter ||
                ' ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1';
        END IF;
    END IF;

    -- Initialize seek position
    IF v_is_asc THEN
        v_next_seek := v_prefix_lower;
    ELSE
        -- DESC performs one specialized initial seek so partial current-version
        -- and delete-marker indexes remain available.
        EXECUTE format(
            'SELECT o.name FROM storage.objects o WHERE o.bucket_id = $1%s%s ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1',
            CASE WHEN v_upper_bound IS NOT NULL
                THEN ' AND lower(o.name) COLLATE "C" >= $2 AND lower(o.name) COLLATE "C" < $3'
                ELSE ''
            END,
            v_version_filter
        )
        INTO v_peek_name
        USING bucketname, v_prefix_lower, v_upper_bound;

        IF v_peek_name IS NOT NULL THEN
            v_next_seek := lower(v_peek_name) || v_delimiter;
        ELSE
            RETURN;
        END IF;
    END IF;

    -- ========================================================================
    -- MAIN LOOP: Hybrid peek-then-batch algorithm
    -- Uses STATIC SQL for peek (hot path) and DYNAMIC SQL for batch and
    -- the delete-marker-only path
    -- ========================================================================
    LOOP
        EXIT WHEN v_count >= v_limit;

        v_previous_seek := v_next_seek;
        v_previous_seek_at := v_next_seek_at;
        v_previous_seek_version := v_next_seek_version;
        v_previous_count := v_count;
        v_previous_skipped := v_skipped;

        -- STEP 1: PEEK
        v_peek_name := NULL;
        IF delete_markers = 'only' THEN
            EXECUTE CASE WHEN v_next_seek_strict
                THEN v_delete_marker_peek_query_strict
                ELSE v_delete_marker_peek_query
            END
                INTO v_peek_name
                USING bucketname, v_next_seek,
                    CASE WHEN v_is_asc THEN COALESCE(v_upper_bound, v_prefix_lower) ELSE v_prefix_lower END,
                    1, v_next_seek_at, v_next_seek_version;
        ELSIF v_multi_row AND v_next_seek_at IS NOT NULL THEN
            SELECT o.name INTO v_peek_name
            FROM storage.objects o
            WHERE o.bucket_id = bucketname
              AND lower(o.name) COLLATE "C" = v_next_seek
              AND (COALESCE(o.archived_at, 'infinity'::timestamptz) < v_next_seek_at
                   OR (COALESCE(o.archived_at, 'infinity'::timestamptz) = v_next_seek_at
                       AND COALESCE(o.version, '') > v_next_seek_version))
              AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
              AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
              AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
              AND (delete_markers != 'only' OR o.is_delete_marker)
            ORDER BY COALESCE(o.archived_at, 'infinity'::timestamptz) DESC,
                     COALESCE(o.version, '') ASC
            LIMIT 1;

            -- The current key is exhausted. Clear its version boundary and
            -- make the following ASC name peek strict. Appending '/' is not a
            -- valid lexical successor because keys ending in characters such
            -- as '!' sort between the exhausted name and name || '/'.
            IF v_peek_name IS NULL THEN
                IF v_is_asc THEN
                    v_next_seek_strict := true;
                END IF;
                v_next_seek_at := NULL;
                v_next_seek_version := '';
            END IF;
        END IF;

        -- Single-row mode is always noncurrent_versions='exclude'. Keep the
        -- current-row predicate literal so generic plans use the current index.
        IF delete_markers != 'only' AND v_peek_name IS NULL AND NOT v_multi_row THEN
            IF v_is_asc THEN
                IF v_next_seek_strict AND v_upper_bound IS NOT NULL THEN
                    SELECT o.name INTO v_peek_name FROM storage.objects o
                    WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" > v_next_seek AND lower(o.name) COLLATE "C" < v_upper_bound
                      AND o.archived_at IS NULL
                      AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                    ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
                ELSIF v_next_seek_strict THEN
                    SELECT o.name INTO v_peek_name FROM storage.objects o
                    WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" > v_next_seek
                      AND o.archived_at IS NULL
                      AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                    ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
                ELSIF v_upper_bound IS NOT NULL THEN
                    SELECT o.name INTO v_peek_name FROM storage.objects o
                    WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_next_seek AND lower(o.name) COLLATE "C" < v_upper_bound
                      AND o.archived_at IS NULL
                      AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                    ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
                ELSE
                    SELECT o.name INTO v_peek_name FROM storage.objects o
                    WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_next_seek
                      AND o.archived_at IS NULL
                      AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                    ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
                END IF;
            ELSIF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek AND lower(o.name) COLLATE "C" >= v_prefix_lower
                  AND o.archived_at IS NULL
                  AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek
                  AND o.archived_at IS NULL
                  AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            END IF;
        ELSIF delete_markers != 'only' AND v_peek_name IS NULL AND v_is_asc THEN
            IF v_next_seek_strict AND v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" > v_next_seek AND lower(o.name) COLLATE "C" < v_upper_bound
                  AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                  AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                  AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                  AND (delete_markers != 'only' OR o.is_delete_marker)
                ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
            ELSIF v_next_seek_strict THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" > v_next_seek
                  AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                  AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                  AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                  AND (delete_markers != 'only' OR o.is_delete_marker)
                ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
            ELSIF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_next_seek AND lower(o.name) COLLATE "C" < v_upper_bound
                  AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                  AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                  AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                  AND (delete_markers != 'only' OR o.is_delete_marker)
                ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_next_seek
                  AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                  AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                  AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                  AND (delete_markers != 'only' OR o.is_delete_marker)
                ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
            END IF;
        ELSIF delete_markers != 'only' AND v_peek_name IS NULL THEN
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek AND lower(o.name) COLLATE "C" >= v_prefix_lower
                  AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                  AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                  AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                  AND (delete_markers != 'only' OR o.is_delete_marker)
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek
                  AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                  AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                  AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                  AND (delete_markers != 'only' OR o.is_delete_marker)
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            END IF;
        END IF;

        EXIT WHEN v_peek_name IS NULL;

        -- If the peek landed on a different key than we were tracking, any
        -- version boundary belongs to the OLD key and must not leak into the
        -- new one - e.g. the deleteMarkers='only' peek doesn't know or care
        -- whether it's continuing the same key or jumping to a new one, so
        -- it never clears these itself.
        IF lower(v_peek_name) IS DISTINCT FROM v_next_seek THEN
            v_next_seek_at := NULL;
            v_next_seek_version := '';
        END IF;

        -- The peek is authoritative for the next key to process. This is
        -- especially important after exhausting a multi-version key: the
        -- version boundary has been cleared, so executing the batch against
        -- a stale v_next_seek would replay every version of that old key.
        v_next_seek := lower(v_peek_name);
        v_next_seek_strict := false;

        -- STEP 2: Check if this is a FOLDER or FILE
        v_common_prefix := storage.get_common_prefix(lower(v_peek_name), v_prefix_lower, v_delimiter);

        IF v_common_prefix IS NOT NULL THEN
            -- FOLDER: Handle offset, emit if needed, skip to next folder
            IF v_skipped < offsets THEN
                v_skipped := v_skipped + 1;
            ELSE
                name := substring(rtrim(storage.get_common_prefix(v_peek_name, v_prefix, v_delimiter), v_delimiter) from v_prefix_len + 1);
                id := NULL;
                updated_at := NULL;
                created_at := NULL;
                last_accessed_at := NULL;
                metadata := NULL;
                version := NULL;
                archived_at := NULL;
                is_delete_marker := NULL;
                is_versioned := NULL;
                RETURN NEXT;
                v_count := v_count + 1;
            END IF;

            -- Advance seek past the folder range
            IF v_is_asc THEN
                v_next_seek := lower(left(v_common_prefix, -1)) || chr(ascii(v_delimiter) + 1);
            ELSE
                v_next_seek := lower(v_common_prefix);
            END IF;
            v_next_seek_at := NULL;
            v_next_seek_version := '';
        ELSE
            -- FILE: Batch fetch using DYNAMIC SQL (overhead amortized over many rows)
            -- For ASC: upper_bound is the exclusive upper limit (< condition)
            -- For DESC: prefix_lower is the inclusive lower limit (>= condition)
            FOR v_current IN EXECUTE v_batch_query
                USING bucketname, v_next_seek,
                    CASE WHEN v_is_asc THEN COALESCE(v_upper_bound, v_prefix_lower) ELSE v_prefix_lower END, v_file_batch_size,
                    v_next_seek_at, v_next_seek_version
            LOOP
                v_common_prefix := storage.get_common_prefix(lower(v_current.name), v_prefix_lower, v_delimiter);

                IF v_common_prefix IS NOT NULL THEN
                    -- Hit a folder: exit batch, let peek handle it. Reset
                    -- strict mode too - it may have been set by an earlier
                    -- row in this same batch (see the single-row ASC advance
                    -- below), and v_next_seek here is the folder-triggering
                    -- row's own name, which the next peek must find inclusively.
                    v_next_seek := CASE
                        WHEN v_is_asc THEN lower(v_current.name)
                        ELSE lower(v_current.name) || v_delimiter
                    END;
                    v_next_seek_at := NULL;
                    v_next_seek_version := '';
                    v_next_seek_strict := false;
                    EXIT;
                END IF;

                -- Handle offset skipping
                IF v_skipped < offsets THEN
                    v_skipped := v_skipped + 1;
                ELSE
                    -- Emit file
                    name := substring(v_current.name from v_prefix_len + 1);
                    id := v_current.id;
                    updated_at := v_current.updated_at;
                    created_at := v_current.created_at;
                    last_accessed_at := v_current.last_accessed_at;
                    metadata := v_current.metadata;
                    version := v_current.version;
                    archived_at := v_current.archived_at;
                    is_delete_marker := v_current.is_delete_marker;
                    is_versioned := v_current.is_versioned;
                    RETURN NEXT;
                    v_count := v_count + 1;
                END IF;

                -- Multi-row mode must remain on this key until all of its
                -- versions have crossed the internal batch boundary.
                IF v_multi_row THEN
                    v_next_seek := lower(v_current.name);
                    v_next_seek_at := COALESCE(v_current.archived_at, 'infinity'::timestamptz);
                    v_next_seek_version := COALESCE(v_current.version, '');
                ELSIF v_is_asc THEN
                    -- Appending the delimiter as a fake lexical successor would
                    -- skip a real key like `name || '!'` (or any character
                    -- sorting below the delimiter), which sorts between `name`
                    -- and `name || delimiter`. Track the real name and mark the
                    -- next comparison strict instead - same fix as the
                    -- exhausted-key case above.
                    v_next_seek := lower(v_current.name);
                    v_next_seek_strict := true;
                ELSE
                    v_next_seek := lower(v_current.name);
                END IF;

                EXIT WHEN v_count >= v_limit;
            END LOOP;
        END IF;

        IF v_count = v_previous_count
           AND v_skipped = v_previous_skipped
           AND v_next_seek IS NOT DISTINCT FROM v_previous_seek
           AND v_next_seek_at IS NOT DISTINCT FROM v_previous_seek_at
           AND v_next_seek_version IS NOT DISTINCT FROM v_previous_seek_version THEN
            RAISE EXCEPTION 'storage.search made no progress at seek (%, %, %)',
                v_next_seek, v_next_seek_at, v_next_seek_version;
        END IF;
    END LOOP;
END;
$_$;


--
-- Name: search_by_timestamp(text, text, integer, integer, text, text, text, text, text, text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.search_by_timestamp(p_prefix text, p_bucket_id text, p_limit integer, p_level integer, p_start_after text, p_sort_order text, p_sort_column text, p_sort_column_after text, noncurrent_versions text DEFAULT 'exclude'::text, delete_markers text DEFAULT 'exclude'::text, p_start_after_version text DEFAULT ''::text) RETURNS TABLE(key text, name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb, version text, archived_at timestamp with time zone, is_delete_marker boolean, is_versioned boolean)
    LANGUAGE plpgsql STABLE
    AS $_$
DECLARE
    v_cursor_op text;
    v_query text;
    v_prefix text;
    v_prefix_pattern text;
    v_sort_order text;
    v_sort_column text;
    v_version_tiebreak text;
BEGIN
    v_prefix := coalesce(p_prefix, '');
    -- Keep the raw prefix for common-prefix calculations and escape only LIKE metacharacters.
    v_prefix_pattern := replace(v_prefix, chr(92), chr(92) || chr(92));
    v_prefix_pattern := replace(v_prefix_pattern, '%', chr(92) || '%');
    v_prefix_pattern := replace(v_prefix_pattern, '_', chr(92) || '_');

    -- COALESCE first: NULL NOT IN (...) evaluates to NULL (not TRUE), so a
    -- bare NOT IN check silently leaves an explicit NULL argument unreset.
    noncurrent_versions := COALESCE(noncurrent_versions, 'exclude');
    delete_markers := COALESCE(delete_markers, 'exclude');
    IF noncurrent_versions NOT IN ('exclude', 'only', 'include') THEN
        noncurrent_versions := 'exclude';
    END IF;
    IF delete_markers NOT IN ('exclude', 'only', 'include') THEN
        delete_markers := 'exclude';
    END IF;

    -- $9 is only populated in multi-row mode; it's always '' otherwise, so
    -- only use each row's real version as a tiebreak in multi-row mode.
    v_version_tiebreak := CASE WHEN noncurrent_versions IN ('only', 'include') THEN 'COALESCE(version, '''')' ELSE '''''' END;

    -- Defense-in-depth: this function is independently reachable and must
    -- not trust p_sort_order/p_sort_column to already be validated by a
    -- caller. Normalize to the same strict allow-list storage.search_v2
    -- uses before interpolating anything into dynamic SQL below.
    v_sort_order := lower(coalesce(p_sort_order, 'asc'));
    IF v_sort_order NOT IN ('asc', 'desc') THEN
        v_sort_order := 'asc';
    END IF;

    v_sort_column := lower(coalesce(p_sort_column, 'updated_at'));
    IF v_sort_column NOT IN ('updated_at', 'created_at') THEN
        v_sort_column := 'updated_at';
    END IF;

    IF v_sort_order = 'asc' THEN
        v_cursor_op := '>';
    ELSE
        v_cursor_op := '<';
    END IF;

    v_query := format($sql$
        WITH raw_objects AS (
            SELECT
                o.name AS obj_name,
                o.id AS obj_id,
                o.updated_at AS obj_updated_at,
                o.created_at AS obj_created_at,
                o.last_accessed_at AS obj_last_accessed_at,
                o.metadata AS obj_metadata,
                o.version AS obj_version,
                o.archived_at AS obj_archived_at,
                o.is_delete_marker AS obj_is_delete_marker,
                o.is_versioned AS obj_is_versioned,
                storage.get_common_prefix(o.name, $1, '/') AS common_prefix
            FROM storage.objects o
            WHERE o.bucket_id = $2
              AND o.name COLLATE "C" LIKE $10 || '%%'
              AND ($7 != 'exclude' OR o.archived_at IS NULL)
              AND ($7 != 'only' OR o.archived_at IS NOT NULL)
              AND ($8 != 'exclude' OR NOT o.is_delete_marker)
              AND ($8 != 'only' OR o.is_delete_marker)
        ),
        -- Aggregate common prefixes (folders)
        -- Both created_at and updated_at use MIN(obj_created_at) to match the old prefixes table behavior
        aggregated_prefixes AS (
            SELECT
                common_prefix AS name,
                NULL::uuid AS id,
                MIN(obj_created_at) AS updated_at,
                MIN(obj_created_at) AS created_at,
                NULL::timestamptz AS last_accessed_at,
                NULL::jsonb AS metadata,
                NULL::text AS version,
                NULL::timestamptz AS archived_at,
                NULL::boolean AS is_delete_marker,
                NULL::boolean AS is_versioned,
                TRUE AS is_prefix
            FROM raw_objects
            WHERE common_prefix IS NOT NULL
            GROUP BY common_prefix
        ),
        leaf_objects AS (
            SELECT
                obj_name AS name,
                obj_id AS id,
                obj_updated_at AS updated_at,
                obj_created_at AS created_at,
                obj_last_accessed_at AS last_accessed_at,
                obj_metadata AS metadata,
                obj_version AS version,
                obj_archived_at AS archived_at,
                obj_is_delete_marker AS is_delete_marker,
                obj_is_versioned AS is_versioned,
                FALSE AS is_prefix
            FROM raw_objects
            WHERE common_prefix IS NULL
        ),
        combined AS (
            SELECT * FROM aggregated_prefixes
            UNION ALL
            SELECT * FROM leaf_objects
        ),
        filtered AS (
            SELECT *
            FROM combined
            WHERE (
                $5 = ''
                OR ROW(
                    COALESCE(date_trunc('milliseconds', %I), 'epoch'::timestamptz),
                    name COLLATE "C",
                    %s
                ) %s ROW(
                    -- truncated the same way as the stored value above
                    date_trunc('milliseconds', COALESCE(NULLIF($6, '')::timestamptz, 'epoch'::timestamptz)),
                    $5,
                    $9
                )
            )
        )
        SELECT
            split_part(name, '/', $3) AS key,
            name,
            id,
            updated_at,
            created_at,
            last_accessed_at,
            metadata,
            version,
            archived_at,
            is_delete_marker,
            is_versioned
        FROM filtered
        ORDER BY
            COALESCE(date_trunc('milliseconds', %I), 'epoch'::timestamptz) %s,
            name COLLATE "C" %s,
            COALESCE(version, '') %s
        LIMIT $4
    $sql$,
        v_sort_column,
        v_version_tiebreak,
        v_cursor_op,
        v_sort_column,
        v_sort_order,
        v_sort_order,
        v_sort_order
    );

    -- version is the third tiebreak component for two versions of the same
    -- key tying on both timestamp and name (see filtered CTE / ORDER BY above)
    RETURN QUERY EXECUTE v_query
    USING v_prefix, p_bucket_id, p_level, p_limit, p_start_after, p_sort_column_after, noncurrent_versions, delete_markers, coalesce(p_start_after_version, ''), v_prefix_pattern;
END;
$_$;


--
-- Name: search_v2(text, text, integer, integer, text, text, text, text, text, text, timestamp with time zone, text, boolean); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.search_v2(prefix text, bucket_name text, limits integer DEFAULT 100, levels integer DEFAULT 1, start_after text DEFAULT ''::text, sort_order text DEFAULT 'asc'::text, sort_column text DEFAULT 'name'::text, sort_column_after text DEFAULT ''::text, noncurrent_versions text DEFAULT 'exclude'::text, delete_markers text DEFAULT 'exclude'::text, start_after_archived_at timestamp with time zone DEFAULT NULL::timestamp with time zone, start_after_version text DEFAULT ''::text, start_after_is_continuation boolean DEFAULT false) RETURNS TABLE(key text, name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb, version text, archived_at timestamp with time zone, is_delete_marker boolean, is_versioned boolean)
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    v_sort_col text;
    v_sort_ord text;
    v_limit int;
BEGIN
    -- Cap limit to maximum of 1500 records
    v_limit := LEAST(coalesce(limits, 100), 1500);

    -- Validate and normalize sort_order
    v_sort_ord := lower(coalesce(sort_order, 'asc'));
    IF v_sort_ord NOT IN ('asc', 'desc') THEN
        v_sort_ord := 'asc';
    END IF;

    -- Validate and normalize sort_column
    v_sort_col := lower(coalesce(sort_column, 'name'));
    IF v_sort_col NOT IN ('name', 'updated_at', 'created_at') THEN
        v_sort_col := 'name';
    END IF;

    -- Route to appropriate implementation
    IF v_sort_col = 'name' THEN
        -- Use list_objects_with_delimiter for name sorting (most efficient: O(k * log n))
        RETURN QUERY
        SELECT
            split_part(l.name, '/', levels) AS key,
            l.name AS name,
            l.id,
            l.updated_at,
            l.created_at,
            l.last_accessed_at,
            l.metadata,
            l.version,
            l.archived_at,
            l.is_delete_marker,
            l.is_versioned
        FROM storage.list_objects_with_delimiter(
            bucket_name,
            coalesce(prefix, ''),
            '/',
            v_limit,
            CASE WHEN start_after_is_continuation THEN '' ELSE start_after END,
            CASE WHEN start_after_is_continuation THEN start_after ELSE '' END,
            v_sort_ord,
            noncurrent_versions,
            delete_markers,
            start_after_archived_at,
            start_after_version
        ) l;
    ELSE
        -- Use aggregation approach for timestamp sorting
        -- Not efficient for large datasets but supports correct pagination
        RETURN QUERY SELECT * FROM storage.search_by_timestamp(
            prefix, bucket_name, v_limit, levels, start_after,
            v_sort_ord, v_sort_col, sort_column_after,
            noncurrent_versions, delete_markers, start_after_version
        );
    END IF;
END;
$$;


--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW; 
END;
$$;


--
-- Name: audit_log_entries; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.audit_log_entries (
    instance_id uuid,
    id uuid NOT NULL,
    payload json,
    created_at timestamp with time zone,
    ip_address character varying(64) DEFAULT ''::character varying NOT NULL
);


--
-- Name: TABLE audit_log_entries; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.audit_log_entries IS 'Auth: Audit trail for user actions.';


--
-- Name: custom_oauth_providers; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.custom_oauth_providers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    provider_type text NOT NULL,
    identifier text NOT NULL,
    name text NOT NULL,
    client_id text NOT NULL,
    client_secret text NOT NULL,
    acceptable_client_ids text[] DEFAULT '{}'::text[] NOT NULL,
    scopes text[] DEFAULT '{}'::text[] NOT NULL,
    pkce_enabled boolean DEFAULT true NOT NULL,
    attribute_mapping jsonb DEFAULT '{}'::jsonb NOT NULL,
    authorization_params jsonb DEFAULT '{}'::jsonb NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    email_optional boolean DEFAULT false NOT NULL,
    issuer text,
    discovery_url text,
    skip_nonce_check boolean DEFAULT false NOT NULL,
    cached_discovery jsonb,
    discovery_cached_at timestamp with time zone,
    authorization_url text,
    token_url text,
    userinfo_url text,
    jwks_uri text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    custom_claims_allowlist text[] DEFAULT '{}'::text[] NOT NULL,
    CONSTRAINT custom_oauth_providers_authorization_url_https CHECK (((authorization_url IS NULL) OR (authorization_url ~~ 'https://%'::text))),
    CONSTRAINT custom_oauth_providers_authorization_url_length CHECK (((authorization_url IS NULL) OR (char_length(authorization_url) <= 2048))),
    CONSTRAINT custom_oauth_providers_client_id_length CHECK (((char_length(client_id) >= 1) AND (char_length(client_id) <= 512))),
    CONSTRAINT custom_oauth_providers_discovery_url_length CHECK (((discovery_url IS NULL) OR (char_length(discovery_url) <= 2048))),
    CONSTRAINT custom_oauth_providers_identifier_format CHECK ((identifier ~ '^[a-z0-9][a-z0-9:-]{0,48}[a-z0-9]$'::text)),
    CONSTRAINT custom_oauth_providers_issuer_length CHECK (((issuer IS NULL) OR ((char_length(issuer) >= 1) AND (char_length(issuer) <= 2048)))),
    CONSTRAINT custom_oauth_providers_jwks_uri_https CHECK (((jwks_uri IS NULL) OR (jwks_uri ~~ 'https://%'::text))),
    CONSTRAINT custom_oauth_providers_jwks_uri_length CHECK (((jwks_uri IS NULL) OR (char_length(jwks_uri) <= 2048))),
    CONSTRAINT custom_oauth_providers_name_length CHECK (((char_length(name) >= 1) AND (char_length(name) <= 100))),
    CONSTRAINT custom_oauth_providers_oauth2_requires_endpoints CHECK (((provider_type <> 'oauth2'::text) OR ((authorization_url IS NOT NULL) AND (token_url IS NOT NULL) AND (userinfo_url IS NOT NULL)))),
    CONSTRAINT custom_oauth_providers_oidc_discovery_url_https CHECK (((provider_type <> 'oidc'::text) OR (discovery_url IS NULL) OR (discovery_url ~~ 'https://%'::text))),
    CONSTRAINT custom_oauth_providers_oidc_issuer_https CHECK (((provider_type <> 'oidc'::text) OR (issuer IS NULL) OR (issuer ~~ 'https://%'::text))),
    CONSTRAINT custom_oauth_providers_oidc_requires_issuer CHECK (((provider_type <> 'oidc'::text) OR (issuer IS NOT NULL))),
    CONSTRAINT custom_oauth_providers_provider_type_check CHECK ((provider_type = ANY (ARRAY['oauth2'::text, 'oidc'::text]))),
    CONSTRAINT custom_oauth_providers_token_url_https CHECK (((token_url IS NULL) OR (token_url ~~ 'https://%'::text))),
    CONSTRAINT custom_oauth_providers_token_url_length CHECK (((token_url IS NULL) OR (char_length(token_url) <= 2048))),
    CONSTRAINT custom_oauth_providers_userinfo_url_https CHECK (((userinfo_url IS NULL) OR (userinfo_url ~~ 'https://%'::text))),
    CONSTRAINT custom_oauth_providers_userinfo_url_length CHECK (((userinfo_url IS NULL) OR (char_length(userinfo_url) <= 2048)))
);


--
-- Name: flow_state; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.flow_state (
    id uuid NOT NULL,
    user_id uuid,
    auth_code text,
    code_challenge_method auth.code_challenge_method,
    code_challenge text,
    provider_type text NOT NULL,
    provider_access_token text,
    provider_refresh_token text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    authentication_method text NOT NULL,
    auth_code_issued_at timestamp with time zone,
    invite_token text,
    referrer text,
    oauth_client_state_id uuid,
    linking_target_id uuid,
    email_optional boolean DEFAULT false NOT NULL
);


--
-- Name: TABLE flow_state; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.flow_state IS 'Stores metadata for all OAuth/SSO login flows';


--
-- Name: identities; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.identities (
    provider_id text NOT NULL,
    user_id uuid NOT NULL,
    identity_data jsonb NOT NULL,
    provider text NOT NULL,
    last_sign_in_at timestamp with time zone,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    email text GENERATED ALWAYS AS (lower((identity_data ->> 'email'::text))) STORED,
    id uuid DEFAULT gen_random_uuid() NOT NULL
);


--
-- Name: TABLE identities; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.identities IS 'Auth: Stores identities associated to a user.';


--
-- Name: COLUMN identities.email; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON COLUMN auth.identities.email IS 'Auth: Email is a generated column that references the optional email property in the identity_data';


--
-- Name: instances; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.instances (
    id uuid NOT NULL,
    uuid uuid,
    raw_base_config text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);


--
-- Name: TABLE instances; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.instances IS 'Auth: Manages users across multiple sites.';


--
-- Name: mfa_amr_claims; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.mfa_amr_claims (
    session_id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    authentication_method text NOT NULL,
    id uuid NOT NULL
);


--
-- Name: TABLE mfa_amr_claims; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.mfa_amr_claims IS 'auth: stores authenticator method reference claims for multi factor authentication';


--
-- Name: mfa_challenges; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.mfa_challenges (
    id uuid NOT NULL,
    factor_id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL,
    verified_at timestamp with time zone,
    ip_address inet NOT NULL,
    otp_code text,
    web_authn_session_data jsonb
);


--
-- Name: TABLE mfa_challenges; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.mfa_challenges IS 'auth: stores metadata about challenge requests made';


--
-- Name: mfa_factors; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.mfa_factors (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    friendly_name text,
    factor_type auth.factor_type NOT NULL,
    status auth.factor_status NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    secret text,
    phone text,
    last_challenged_at timestamp with time zone,
    web_authn_credential jsonb,
    web_authn_aaguid uuid,
    last_webauthn_challenge_data jsonb
);


--
-- Name: TABLE mfa_factors; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.mfa_factors IS 'auth: stores metadata about factors';


--
-- Name: COLUMN mfa_factors.last_webauthn_challenge_data; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON COLUMN auth.mfa_factors.last_webauthn_challenge_data IS 'Stores the latest WebAuthn challenge data including attestation/assertion for customer verification';


--
-- Name: mfa_recovery_code_sets; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.mfa_recovery_code_sets (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    mfa_factor_id uuid NOT NULL,
    failed_verification_count integer DEFAULT 0 NOT NULL,
    verification_locked_until timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT mfa_recovery_code_sets_failed_verification_count_check CHECK ((failed_verification_count >= 0))
);


--
-- Name: mfa_recovery_codes; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.mfa_recovery_codes (
    id uuid NOT NULL,
    mfa_recovery_code_set_id uuid NOT NULL,
    code_hash text NOT NULL,
    consumed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: oauth_authorizations; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.oauth_authorizations (
    id uuid NOT NULL,
    authorization_id text NOT NULL,
    client_id uuid NOT NULL,
    user_id uuid,
    redirect_uri text NOT NULL,
    scope text NOT NULL,
    state text,
    resource text,
    code_challenge text,
    code_challenge_method auth.code_challenge_method,
    response_type auth.oauth_response_type DEFAULT 'code'::auth.oauth_response_type NOT NULL,
    status auth.oauth_authorization_status DEFAULT 'pending'::auth.oauth_authorization_status NOT NULL,
    authorization_code text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone DEFAULT (now() + '00:03:00'::interval) NOT NULL,
    approved_at timestamp with time zone,
    nonce text,
    CONSTRAINT oauth_authorizations_authorization_code_length CHECK ((char_length(authorization_code) <= 255)),
    CONSTRAINT oauth_authorizations_code_challenge_length CHECK ((char_length(code_challenge) <= 128)),
    CONSTRAINT oauth_authorizations_expires_at_future CHECK ((expires_at > created_at)),
    CONSTRAINT oauth_authorizations_nonce_length CHECK ((char_length(nonce) <= 255)),
    CONSTRAINT oauth_authorizations_redirect_uri_length CHECK ((char_length(redirect_uri) <= 2048)),
    CONSTRAINT oauth_authorizations_resource_length CHECK ((char_length(resource) <= 2048)),
    CONSTRAINT oauth_authorizations_scope_length CHECK ((char_length(scope) <= 4096)),
    CONSTRAINT oauth_authorizations_state_length CHECK ((char_length(state) <= 4096))
);


--
-- Name: oauth_client_states; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.oauth_client_states (
    id uuid NOT NULL,
    provider_type text NOT NULL,
    code_verifier text,
    created_at timestamp with time zone NOT NULL
);


--
-- Name: TABLE oauth_client_states; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.oauth_client_states IS 'Stores OAuth states for third-party provider authentication flows where Supabase acts as the OAuth client.';


--
-- Name: oauth_clients; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.oauth_clients (
    id uuid NOT NULL,
    client_secret_hash text,
    registration_type auth.oauth_registration_type NOT NULL,
    redirect_uris text NOT NULL,
    grant_types text NOT NULL,
    client_name text,
    client_uri text,
    logo_uri text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    client_type auth.oauth_client_type DEFAULT 'confidential'::auth.oauth_client_type NOT NULL,
    token_endpoint_auth_method text NOT NULL,
    CONSTRAINT oauth_clients_client_name_length CHECK ((char_length(client_name) <= 1024)),
    CONSTRAINT oauth_clients_client_uri_length CHECK ((char_length(client_uri) <= 2048)),
    CONSTRAINT oauth_clients_logo_uri_length CHECK ((char_length(logo_uri) <= 2048)),
    CONSTRAINT oauth_clients_token_endpoint_auth_method_check CHECK ((token_endpoint_auth_method = ANY (ARRAY['client_secret_basic'::text, 'client_secret_post'::text, 'none'::text])))
);


--
-- Name: oauth_consents; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.oauth_consents (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    client_id uuid NOT NULL,
    scopes text NOT NULL,
    granted_at timestamp with time zone DEFAULT now() NOT NULL,
    revoked_at timestamp with time zone,
    CONSTRAINT oauth_consents_revoked_after_granted CHECK (((revoked_at IS NULL) OR (revoked_at >= granted_at))),
    CONSTRAINT oauth_consents_scopes_length CHECK ((char_length(scopes) <= 2048)),
    CONSTRAINT oauth_consents_scopes_not_empty CHECK ((char_length(TRIM(BOTH FROM scopes)) > 0))
);


--
-- Name: one_time_tokens; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.one_time_tokens (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    token_type auth.one_time_token_type NOT NULL,
    token_hash text NOT NULL,
    relates_to text NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone,
    CONSTRAINT one_time_tokens_token_hash_check CHECK ((char_length(token_hash) > 0))
);


--
-- Name: refresh_tokens; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.refresh_tokens (
    instance_id uuid,
    id bigint NOT NULL,
    token character varying(255),
    user_id character varying(255),
    revoked boolean,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    parent character varying(255),
    session_id uuid
);


--
-- Name: TABLE refresh_tokens; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.refresh_tokens IS 'Auth: Store of tokens used to refresh JWT tokens once they expire.';


--
-- Name: refresh_tokens_id_seq; Type: SEQUENCE; Schema: auth; Owner: -
--

CREATE SEQUENCE auth.refresh_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: refresh_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: auth; Owner: -
--

ALTER SEQUENCE auth.refresh_tokens_id_seq OWNED BY auth.refresh_tokens.id;


--
-- Name: saml_providers; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.saml_providers (
    id uuid NOT NULL,
    sso_provider_id uuid NOT NULL,
    entity_id text NOT NULL,
    metadata_xml text NOT NULL,
    metadata_url text,
    attribute_mapping jsonb,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    name_id_format text,
    CONSTRAINT "entity_id not empty" CHECK ((char_length(entity_id) > 0)),
    CONSTRAINT "metadata_url not empty" CHECK (((metadata_url = NULL::text) OR (char_length(metadata_url) > 0))),
    CONSTRAINT "metadata_xml not empty" CHECK ((char_length(metadata_xml) > 0))
);


--
-- Name: TABLE saml_providers; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.saml_providers IS 'Auth: Manages SAML Identity Provider connections.';


--
-- Name: saml_relay_states; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.saml_relay_states (
    id uuid NOT NULL,
    sso_provider_id uuid NOT NULL,
    request_id text NOT NULL,
    for_email text,
    redirect_to text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    flow_state_id uuid,
    CONSTRAINT "request_id not empty" CHECK ((char_length(request_id) > 0))
);


--
-- Name: TABLE saml_relay_states; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.saml_relay_states IS 'Auth: Contains SAML Relay State information for each Service Provider initiated login.';


--
-- Name: schema_migrations; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.schema_migrations (
    version character varying(255) NOT NULL
);


--
-- Name: TABLE schema_migrations; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.schema_migrations IS 'Auth: Manages updates to the auth system.';


--
-- Name: scim_tokens; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.scim_tokens (
    id uuid NOT NULL,
    sso_provider_id uuid NOT NULL,
    token_hash text NOT NULL,
    prefix text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone,
    revoked_at timestamp with time zone,
    last_used_at timestamp with time zone,
    CONSTRAINT scim_tokens_expires_at_future CHECK (((expires_at IS NULL) OR (expires_at > created_at))),
    CONSTRAINT scim_tokens_revoked_after_created CHECK (((revoked_at IS NULL) OR (revoked_at >= created_at))),
    CONSTRAINT scim_tokens_token_hash_check CHECK ((token_hash ~ '^[0-9a-f]{64}$'::text))
);


--
-- Name: scim_users; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.scim_users (
    id uuid NOT NULL,
    sso_provider_id uuid NOT NULL,
    user_id uuid,
    resource jsonb NOT NULL,
    user_name text GENERATED ALWAYS AS (lower((resource ->> 'userName'::text))) STORED NOT NULL,
    external_id text GENERATED ALWAYS AS ((resource ->> 'externalId'::text)) STORED,
    active boolean GENERATED ALWAYS AS (COALESCE(((resource ->> 'active'::text))::boolean, true)) STORED NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone
);


--
-- Name: sessions; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.sessions (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    factor_id uuid,
    aal auth.aal_level,
    not_after timestamp with time zone,
    refreshed_at timestamp without time zone,
    user_agent text,
    ip inet,
    tag text,
    oauth_client_id uuid,
    refresh_token_hmac_key text,
    refresh_token_counter bigint,
    scopes text,
    CONSTRAINT sessions_scopes_length CHECK ((char_length(scopes) <= 4096))
);


--
-- Name: TABLE sessions; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.sessions IS 'Auth: Stores session data associated to a user.';


--
-- Name: COLUMN sessions.not_after; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON COLUMN auth.sessions.not_after IS 'Auth: Not after is a nullable column that contains a timestamp after which the session should be regarded as expired.';


--
-- Name: COLUMN sessions.refresh_token_hmac_key; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON COLUMN auth.sessions.refresh_token_hmac_key IS 'Holds a HMAC-SHA256 key used to sign refresh tokens for this session.';


--
-- Name: COLUMN sessions.refresh_token_counter; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON COLUMN auth.sessions.refresh_token_counter IS 'Holds the ID (counter) of the last issued refresh token.';


--
-- Name: sso_domains; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.sso_domains (
    id uuid NOT NULL,
    sso_provider_id uuid NOT NULL,
    domain text NOT NULL,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    CONSTRAINT "domain not empty" CHECK ((char_length(domain) > 0))
);


--
-- Name: TABLE sso_domains; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.sso_domains IS 'Auth: Manages SSO email address domain mapping to an SSO Identity Provider.';


--
-- Name: sso_providers; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.sso_providers (
    id uuid NOT NULL,
    resource_id text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    disabled boolean,
    CONSTRAINT "resource_id not empty" CHECK (((resource_id = NULL::text) OR (char_length(resource_id) > 0)))
);


--
-- Name: TABLE sso_providers; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.sso_providers IS 'Auth: Manages SSO identity provider information; see saml_providers for SAML.';


--
-- Name: COLUMN sso_providers.resource_id; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON COLUMN auth.sso_providers.resource_id IS 'Auth: Uniquely identifies a SSO provider according to a user-chosen resource ID (case insensitive), useful in infrastructure as code.';


--
-- Name: users; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.users (
    instance_id uuid,
    id uuid NOT NULL,
    aud character varying(255),
    role character varying(255),
    email character varying(255),
    encrypted_password character varying(255),
    email_confirmed_at timestamp with time zone,
    invited_at timestamp with time zone,
    confirmation_token character varying(255),
    confirmation_sent_at timestamp with time zone,
    recovery_token character varying(255),
    recovery_sent_at timestamp with time zone,
    email_change_token_new character varying(255),
    email_change character varying(255),
    email_change_sent_at timestamp with time zone,
    last_sign_in_at timestamp with time zone,
    raw_app_meta_data jsonb,
    raw_user_meta_data jsonb,
    is_super_admin boolean,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    phone text DEFAULT NULL::character varying,
    phone_confirmed_at timestamp with time zone,
    phone_change text DEFAULT ''::character varying,
    phone_change_token character varying(255) DEFAULT ''::character varying,
    phone_change_sent_at timestamp with time zone,
    confirmed_at timestamp with time zone GENERATED ALWAYS AS (LEAST(email_confirmed_at, phone_confirmed_at)) STORED,
    email_change_token_current character varying(255) DEFAULT ''::character varying,
    email_change_confirm_status smallint DEFAULT 0,
    banned_until timestamp with time zone,
    reauthentication_token character varying(255) DEFAULT ''::character varying,
    reauthentication_sent_at timestamp with time zone,
    is_sso_user boolean DEFAULT false NOT NULL,
    deleted_at timestamp with time zone,
    is_anonymous boolean DEFAULT false NOT NULL,
    CONSTRAINT users_email_change_confirm_status_check CHECK (((email_change_confirm_status >= 0) AND (email_change_confirm_status <= 2)))
);


--
-- Name: TABLE users; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.users IS 'Auth: Stores user login data within a secure schema.';


--
-- Name: COLUMN users.is_sso_user; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON COLUMN auth.users.is_sso_user IS 'Auth: Set this column to true when the account comes from SSO. These accounts can have duplicate emails.';


--
-- Name: webauthn_challenges; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.webauthn_challenges (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    challenge_type text NOT NULL,
    session_data jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    CONSTRAINT webauthn_challenges_challenge_type_check CHECK ((challenge_type = ANY (ARRAY['signup'::text, 'registration'::text, 'authentication'::text])))
);


--
-- Name: webauthn_credentials; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.webauthn_credentials (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    credential_id bytea NOT NULL,
    public_key bytea NOT NULL,
    attestation_type text DEFAULT ''::text NOT NULL,
    aaguid uuid,
    sign_count bigint DEFAULT 0 NOT NULL,
    transports jsonb DEFAULT '[]'::jsonb NOT NULL,
    backup_eligible boolean DEFAULT false NOT NULL,
    backed_up boolean DEFAULT false NOT NULL,
    friendly_name text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    last_used_at timestamp with time zone
);


--
-- Name: merchant_categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_categories (
    code text NOT NULL,
    name_ar text NOT NULL,
    name_en text NOT NULL,
    icon text,
    sort_order integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT merchant_categories_code_check CHECK ((code ~ '^[a-z][a-z0-9_]*$'::text))
);


--
-- Name: TABLE merchant_categories; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_categories IS 'Vendor category lookup — single source of truth for merchants.category, promoted_slots.category and promo_codes.category (replaces the two-value inline CHECKs of 005/011/014). Read policy exposes is_active rows to clients; writes are service_role only.';


--
-- Name: merchants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchants (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name_ar text NOT NULL,
    name_en text NOT NULL,
    category text NOT NULL,
    logo_url text,
    cover_url text,
    description_ar text,
    description_en text,
    address text NOT NULL,
    lat numeric(9,6) NOT NULL,
    lng numeric(9,6) NOT NULL,
    city text NOT NULL,
    area text,
    phone text NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    rating numeric(2,1) DEFAULT 0.0 NOT NULL,
    rating_count integer DEFAULT 0 NOT NULL,
    min_order_amount numeric(10,2) DEFAULT 0.00 NOT NULL,
    estimated_delivery_minutes integer DEFAULT 30 NOT NULL,
    delivery_fee_override numeric(10,2),
    commission_pct numeric(5,2),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    delivery_radius_km numeric(5,2) DEFAULT 10.00 NOT NULL,
    estimated_prep_time_minutes integer DEFAULT 30 NOT NULL,
    payout_frequency text DEFAULT 'weekly'::text NOT NULL,
    payout_method text DEFAULT 'bank_transfer'::text NOT NULL,
    bank_account_holder text,
    bank_account_number text,
    bank_name text,
    wallet_phone text,
    approval_status text DEFAULT 'approved'::text NOT NULL,
    approval_note text,
    CONSTRAINT merchants_approval_status_check CHECK ((approval_status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text]))),
    CONSTRAINT merchants_commission_pct_check CHECK (((commission_pct IS NULL) OR ((commission_pct >= (0)::numeric) AND (commission_pct <= (100)::numeric)))),
    CONSTRAINT merchants_delivery_fee_override_check CHECK (((delivery_fee_override IS NULL) OR (delivery_fee_override >= (0)::numeric))),
    CONSTRAINT merchants_delivery_radius_km_check CHECK ((delivery_radius_km > (0)::numeric)),
    CONSTRAINT merchants_estimated_delivery_minutes_check CHECK ((estimated_delivery_minutes > 0)),
    CONSTRAINT merchants_estimated_prep_time_minutes_check CHECK ((estimated_prep_time_minutes > 0)),
    CONSTRAINT merchants_min_order_amount_check CHECK ((min_order_amount >= (0)::numeric)),
    CONSTRAINT merchants_payout_frequency_check CHECK ((payout_frequency = ANY (ARRAY['daily'::text, 'weekly'::text, 'monthly'::text]))),
    CONSTRAINT merchants_payout_method_check CHECK ((payout_method = ANY (ARRAY['bank_transfer'::text, 'wallet'::text, 'cash'::text, 'instapay'::text]))),
    CONSTRAINT merchants_rating_check CHECK (((rating >= (0)::numeric) AND (rating <= (5)::numeric)))
);


--
-- Name: TABLE merchants; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchants IS 'Vendors (restaurants, pharmacies). Core entity for the marketplace.';


--
-- Name: COLUMN merchants.name_ar; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchants.name_ar IS 'Arabic name — displayed when user language is Arabic.';


--
-- Name: COLUMN merchants.name_en; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchants.name_en IS 'English name — displayed when user language is English.';


--
-- Name: COLUMN merchants.category; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchants.category IS 'restaurant=food delivery, pharmacy=medicine/health delivery.';


--
-- Name: COLUMN merchants.is_active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchants.is_active IS 'Inactive merchants are hidden from the feed. Set by admin.';


--
-- Name: COLUMN merchants.rating; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchants.rating IS 'Average rating (0.0-5.0). Updated by trigger on reviews INSERT/UPDATE.';


--
-- Name: COLUMN merchants.delivery_fee_override; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchants.delivery_fee_override IS 'If set, overrides platform delivery fee calculation for this merchant.';


--
-- Name: COLUMN merchants.commission_pct; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchants.commission_pct IS 'Merchant commission percentage. If NULL, uses platform_config.default_commission_pct.';


--
-- Name: COLUMN merchants.delivery_radius_km; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchants.delivery_radius_km IS 'Maximum delivery radius in km. Orders beyond this distance are rejected. Default 10 km.';


--
-- Name: COLUMN merchants.estimated_prep_time_minutes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchants.estimated_prep_time_minutes IS 'Estimated kitchen preparation time in minutes. Used for ETA calculations. Distinct from estimated_delivery_minutes which includes transit time.';


--
-- Name: COLUMN merchants.payout_frequency; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchants.payout_frequency IS 'How often the auto-generate-merchant-payouts cron should aggregate this merchants delivered orders into a payout row. daily = every night, weekly = every Sunday 03:00 UTC, monthly = first of month 03:00 UTC.';


--
-- Name: COLUMN merchants.payout_method; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchants.payout_method IS 'Default payout channel for this merchant. Used by create_merchant_payout when the admin does not pass an explicit p_payout_method. cash = manual handover; bank_transfer/wallet/instapay = manual ops transfer with payout_reference.';


--
-- Name: COLUMN merchants.bank_account_number; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchants.bank_account_number IS 'Bank account number for payouts. PLAINTEXT in v1 — TODO: encrypt at rest using the migration 027 national_id encryption pattern. Do not expose to non-admin roles (RLS already gates reads to admins).';


--
-- Name: COLUMN merchants.approval_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchants.approval_status IS 'Onboarding review: pending=new place awaiting Ops, approved=live, rejected=refused with reason in approval_note. is_active remains the runtime kill-switch.';


--
-- Name: active_merchant_categories; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.active_merchant_categories WITH (security_invoker='true') AS
 SELECT mc.code,
    mc.name_ar,
    mc.name_en,
    mc.icon,
    mc.sort_order,
    count(m.id) AS active_merchants
   FROM (public.merchant_categories mc
     JOIN public.merchants m ON (((m.category = mc.code) AND (m.is_active = true))))
  WHERE (mc.is_active = true)
  GROUP BY mc.code, mc.name_ar, mc.name_en, mc.icon, mc.sort_order;


--
-- Name: VIEW active_merchant_categories; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.active_merchant_categories IS 'Chip-row data source (audit row 38, Option A): active merchant categories with >= 1 active merchant, bilingual names, icon and chip order. security_invoker view — RLS of merchant_categories (097) and merchants (020) applies to callers.';


--
-- Name: admin_kpi_cache; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.admin_kpi_cache (
    key text NOT NULL,
    value jsonb NOT NULL,
    computed_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: admin_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.admin_sessions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    admin_id uuid NOT NULL,
    session_token text NOT NULL,
    ip_address inet,
    user_agent text,
    country text,
    city text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    last_accessed_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    invalidated_at timestamp with time zone,
    invalidation_reason text,
    device_fingerprint text,
    CONSTRAINT admin_sessions_invalidation_reason_check CHECK (((invalidation_reason IS NULL) OR (invalidation_reason = ANY (ARRAY['logout'::text, 'new_login'::text, 'admin_force'::text, 'timeout'::text, 'security_alert'::text])))),
    CONSTRAINT admin_sessions_valid_expiry CHECK ((expires_at > created_at))
);


--
-- Name: TABLE admin_sessions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.admin_sessions IS 'Admin panel session tracking. One active session per admin enforced. Used for session management, security monitoring, and logout-everywhere feature. All access via service role.';


--
-- Name: alert_incidents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.alert_incidents (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    rule_id uuid NOT NULL,
    metric text NOT NULL,
    severity text NOT NULL,
    message text NOT NULL,
    trigger_value numeric NOT NULL,
    status text DEFAULT 'triggered'::text NOT NULL,
    triggered_at timestamp with time zone DEFAULT now() NOT NULL,
    acknowledged_by uuid,
    acknowledged_at timestamp with time zone,
    resolved_by uuid,
    resolved_at timestamp with time zone,
    resolution_notes text,
    CONSTRAINT alert_incidents_severity_check CHECK ((severity = ANY (ARRAY['info'::text, 'warning'::text, 'critical'::text]))),
    CONSTRAINT alert_incidents_status_check CHECK ((status = ANY (ARRAY['triggered'::text, 'acknowledged'::text, 'resolved'::text])))
);


--
-- Name: alert_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.alert_rules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    description text,
    metric text NOT NULL,
    condition text NOT NULL,
    threshold numeric NOT NULL,
    duration_seconds integer DEFAULT 300,
    severity text DEFAULT 'warning'::text NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    notification_channels text[] DEFAULT ARRAY['admin_panel'::text],
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    CONSTRAINT alert_rules_severity_check CHECK ((severity = ANY (ARRAY['info'::text, 'warning'::text, 'critical'::text])))
);


--
-- Name: TABLE alert_rules; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.alert_rules IS 'Configurable alert rules for the admin monitoring system. Pre-seeded with 8 built-in rules for common operational alerts.';


--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    admin_id uuid NOT NULL,
    action text NOT NULL,
    resource_type text NOT NULL,
    resource_id text NOT NULL,
    details jsonb,
    ip_address inet,
    user_agent text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT audit_logs_resource_type_check CHECK ((resource_type = ANY (ARRAY['driver'::text, 'order'::text, 'merchant'::text, 'customer'::text, 'promo'::text, 'ad'::text, 'config'::text, 'session'::text, 'menu_item'::text, 'category'::text, 'payment'::text, 'notification'::text, 'feature_flag'::text, 'other'::text])))
);


--
-- Name: TABLE audit_logs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.audit_logs IS 'Permanent, immutable audit trail for all admin actions. No UPDATE or DELETE allowed. Used for compliance, debugging, and security investigations. Egyptian DPL compliance requires indefinite retention.';


--
-- Name: COLUMN audit_logs.action; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.audit_logs.action IS 'Action identifier: resource.verb format, e.g., driver.create, order.cancel, merchant.update, config.change';


--
-- Name: COLUMN audit_logs.details; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.audit_logs.details IS 'JSONB snapshot of the change: previous values, new values, reason, admin-provided justification';


--
-- Name: cancellation_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cancellation_rules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_status text NOT NULL,
    initiator text NOT NULL,
    can_cancel boolean DEFAULT false NOT NULL,
    refund_percentage numeric(5,2) DEFAULT 0 NOT NULL,
    cancellation_fee_percentage numeric(5,2) DEFAULT 0 NOT NULL,
    cancellation_fee_min numeric(10,2) DEFAULT 0 NOT NULL,
    driver_compensation numeric(10,2) DEFAULT 0 NOT NULL,
    requires_reason boolean DEFAULT false NOT NULL,
    requires_admin_approval boolean DEFAULT false NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    CONSTRAINT cancellation_rules_cancellation_fee_min_check CHECK ((cancellation_fee_min >= (0)::numeric)),
    CONSTRAINT cancellation_rules_cancellation_fee_percentage_check CHECK (((cancellation_fee_percentage >= (0)::numeric) AND (cancellation_fee_percentage <= (100)::numeric))),
    CONSTRAINT cancellation_rules_driver_compensation_check CHECK ((driver_compensation >= (0)::numeric)),
    CONSTRAINT cancellation_rules_initiator_check CHECK ((initiator = ANY (ARRAY['customer'::text, 'driver'::text, 'admin'::text, 'system'::text]))),
    CONSTRAINT cancellation_rules_order_status_check CHECK ((order_status = ANY (ARRAY['pending'::text, 'confirmed'::text, 'preparing'::text, 'ready'::text, 'picked_up'::text, 'on_the_way'::text, 'delivered'::text]))),
    CONSTRAINT cancellation_rules_refund_percentage_check CHECK (((refund_percentage >= (0)::numeric) AND (refund_percentage <= (100)::numeric)))
);


--
-- Name: TABLE cancellation_rules; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.cancellation_rules IS 'Sprint 2 fix (S18): SELECT policy dropped. Only the cancel_order RPC (service role) reads this table; mobile/admin code never queries it directly.';


--
-- Name: COLUMN cancellation_rules.refund_percentage; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.cancellation_rules.refund_percentage IS 'Percentage of total refunded to customer. 100=full refund, 0=no refund.';


--
-- Name: COLUMN cancellation_rules.cancellation_fee_percentage; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.cancellation_rules.cancellation_fee_percentage IS 'Percentage of subtotal charged as cancellation fee to customer.';


--
-- Name: COLUMN cancellation_rules.cancellation_fee_min; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.cancellation_rules.cancellation_fee_min IS 'Minimum cancellation fee in EGP, even if percentage calculation is lower.';


--
-- Name: COLUMN cancellation_rules.driver_compensation; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.cancellation_rules.driver_compensation IS 'Fixed EGP amount paid to driver for wasted trip when order is cancelled.';


--
-- Name: categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.categories (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    merchant_id uuid NOT NULL,
    name_ar text NOT NULL,
    name_en text NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    icon text,
    is_available boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE categories; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.categories IS 'Menu categories per merchant (e.g., Burgers, Sides, Drinks). Sorted by sort_order.';


--
-- Name: data_access_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.data_access_log (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    admin_id uuid NOT NULL,
    action text NOT NULL,
    resource_type text NOT NULL,
    resource_id uuid NOT NULL,
    field_name text,
    reason text,
    ip_address inet,
    user_agent text,
    request_id text,
    is_flagged boolean DEFAULT false NOT NULL,
    flag_reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT data_access_log_action_check CHECK ((action = ANY (ARRAY['view'::text, 'reveal'::text, 'export'::text, 'modify'::text, 'delete'::text, 'create'::text, 'login'::text, 'logout'::text, 'search'::text]))),
    CONSTRAINT data_access_log_resource_type_check CHECK ((resource_type = ANY (ARRAY['customer'::text, 'driver'::text, 'order'::text, 'payment'::text, 'merchant'::text, 'promo'::text, 'config'::text, 'session'::text, 'other'::text])))
);


--
-- Name: TABLE data_access_log; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.data_access_log IS 'Immutable audit trail for admin PII access. Required for Egyptian DPL compliance. No UPDATE/DELETE — records are permanent. Anomaly detection flags high-volume access.';


--
-- Name: driver_documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.driver_documents (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    driver_id uuid NOT NULL,
    document_type text NOT NULL,
    file_url text NOT NULL,
    file_name text NOT NULL,
    file_size_bytes integer NOT NULL,
    mime_type text DEFAULT 'image/jpeg'::text NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    rejection_reason text,
    reviewed_by uuid,
    reviewed_at timestamp with time zone,
    uploaded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT driver_documents_document_type_check CHECK ((document_type = ANY (ARRAY['national_id_front'::text, 'national_id_back'::text, 'driving_license_front'::text, 'driving_license_back'::text, 'vehicle_registration'::text, 'vehicle_insurance'::text, 'criminal_record'::text, 'other'::text]))),
    CONSTRAINT driver_documents_file_size_bytes_check CHECK ((file_size_bytes > 0)),
    CONSTRAINT driver_documents_mime_type_check CHECK ((mime_type = ANY (ARRAY['image/jpeg'::text, 'image/png'::text, 'image/webp'::text]))),
    CONSTRAINT driver_documents_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])))
);


--
-- Name: TABLE driver_documents; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.driver_documents IS 'Driver verification documents. Uploaded by driver during onboarding, reviewed by admin. Files stored in driver-documents storage bucket (private).';


--
-- Name: COLUMN driver_documents.document_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.driver_documents.document_type IS 'national_id_front/back and driving_license_front/back are required. Others are optional.';


--
-- Name: COLUMN driver_documents.file_url; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.driver_documents.file_url IS 'Supabase Storage path: driver-documents/{driver_id}/{document_type}.{ext}';


--
-- Name: COLUMN driver_documents.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.driver_documents.status IS 'pending=awaiting admin review, approved=admin verified, rejected=admin rejected (see rejection_reason).';


--
-- Name: COLUMN driver_documents.reviewed_by; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.driver_documents.reviewed_by IS 'Admin (profile UUID) who reviewed this document.';


--
-- Name: driver_earnings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.driver_earnings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    driver_id uuid NOT NULL,
    order_id uuid NOT NULL,
    delivery_fee_earned numeric(10,2) NOT NULL,
    platform_fee_deducted numeric(10,2) DEFAULT 0 NOT NULL,
    net_earnings numeric(10,2) NOT NULL,
    earnings_pct_used numeric(5,2) NOT NULL,
    is_cancellation_compensation boolean DEFAULT false NOT NULL,
    compensation_reason text,
    payout_status text DEFAULT 'pending'::text NOT NULL,
    paid_at timestamp with time zone,
    payout_method text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT driver_earnings_delivery_fee_earned_check CHECK ((delivery_fee_earned >= (0)::numeric)),
    CONSTRAINT driver_earnings_net_earnings_check CHECK ((net_earnings >= (0)::numeric)),
    CONSTRAINT driver_earnings_payout_method_check CHECK (((payout_method IS NULL) OR (payout_method = ANY (ARRAY['cash'::text, 'bank_transfer'::text, 'wallet'::text, 'instapay'::text])))),
    CONSTRAINT driver_earnings_payout_status_check CHECK ((payout_status = ANY (ARRAY['pending'::text, 'paid'::text, 'failed'::text]))),
    CONSTRAINT driver_earnings_platform_fee_deducted_check CHECK ((platform_fee_deducted >= (0)::numeric))
);


--
-- Name: TABLE driver_earnings; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.driver_earnings IS 'Per-order driver earnings. Created by complete-delivery Edge Function. Tracks earning amount and payout status for financial reconciliation.';


--
-- Name: COLUMN driver_earnings.net_earnings; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.driver_earnings.net_earnings IS 'delivery_fee_earned - platform_fee_deducted. What the driver actually receives.';


--
-- Name: COLUMN driver_earnings.earnings_pct_used; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.driver_earnings.earnings_pct_used IS 'Percentage of delivery fee the driver received, from platform_config.driver_earnings_pct at time of delivery.';


--
-- Name: COLUMN driver_earnings.is_cancellation_compensation; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.driver_earnings.is_cancellation_compensation IS 'True if this earning is from a cancelled order (driver compensation for wasted trip).';


--
-- Name: COLUMN driver_earnings.payout_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.driver_earnings.payout_status IS 'pending=not yet paid out, paid=paid to driver, failed=payout attempt failed.';


--
-- Name: driver_order_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.driver_order_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid NOT NULL,
    driver_id uuid NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    sent_at timestamp with time zone DEFAULT now() NOT NULL,
    responded_at timestamp with time zone,
    decline_reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT driver_order_requests_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'accepted'::text, 'declined'::text, 'expired'::text])))
);


--
-- Name: TABLE driver_order_requests; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.driver_order_requests IS 'A4-G4: Persistent audit trail of driver assignment requests. Populated by the driver-actions Edge Function: handleAssignDriver inserts pending rows; handleDriverRespond updates to accepted/declined. No direct client writes — all via service role.';


--
-- Name: driver_settlement_earnings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.driver_settlement_earnings (
    settlement_id uuid NOT NULL,
    earning_id uuid NOT NULL,
    net_earnings_at_settlement numeric(10,2) NOT NULL
);


--
-- Name: TABLE driver_settlement_earnings; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.driver_settlement_earnings IS 'Junction linking driver_earnings rows to the settlement that paid them. Prevents double-payment (a paid earning cannot be re-settled). The net_earnings_at_settlement snapshot preserves the amount even if the earning row is later edited.';


--
-- Name: driver_settlements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.driver_settlements (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    driver_id uuid NOT NULL,
    period_start timestamp with time zone NOT NULL,
    period_end timestamp with time zone NOT NULL,
    delivery_count integer NOT NULL,
    gross_earnings numeric(10,2) NOT NULL,
    platform_fee_deducted numeric(10,2) DEFAULT 0 NOT NULL,
    cancellation_compensation numeric(10,2) DEFAULT 0 NOT NULL,
    net_payable numeric(10,2) NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    paymob_transaction_id text,
    paid_at timestamp with time zone,
    paid_by uuid,
    payout_method text,
    payout_reference text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_paid_settlement_has_payout_method CHECK (((status <> 'paid'::text) OR (payout_method IS NOT NULL))),
    CONSTRAINT chk_paid_settlement_has_payout_reference CHECK (((status <> 'paid'::text) OR (payout_reference IS NOT NULL))),
    CONSTRAINT driver_settlements_cancellation_compensation_check CHECK ((cancellation_compensation >= (0)::numeric)),
    CONSTRAINT driver_settlements_delivery_count_check CHECK ((delivery_count >= 0)),
    CONSTRAINT driver_settlements_gross_earnings_check CHECK ((gross_earnings >= (0)::numeric)),
    CONSTRAINT driver_settlements_net_payable_check CHECK ((net_payable >= (0)::numeric)),
    CONSTRAINT driver_settlements_payout_method_check CHECK (((payout_method IS NULL) OR (payout_method = ANY (ARRAY['cash'::text, 'bank_transfer'::text, 'wallet'::text, 'instapay'::text])))),
    CONSTRAINT driver_settlements_platform_fee_deducted_check CHECK ((platform_fee_deducted >= (0)::numeric)),
    CONSTRAINT driver_settlements_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'paid'::text, 'failed'::text, 'cancelled'::text])))
);


--
-- Name: TABLE driver_settlements; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.driver_settlements IS 'Period-aggregated driver payout rows. Each row settles a batch of driver_earnings (linked via driver_settlement_earnings). Status machine: pending → approved → paid. Paymob disbursement NOT wired — admin marks paid manually via mark_driver_settlement_paid RPC.';


--
-- Name: COLUMN driver_settlements.payout_method; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.driver_settlements.payout_method IS 'Payment channel for this settlement. cash = handover (no Paymob), bank_transfer/wallet/instapay = manual ops transfer with payout_reference.';


--
-- Name: COLUMN driver_settlements.payout_reference; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.driver_settlements.payout_reference IS 'Free-text reference for the manual payout (bank transfer ref #, cash receipt #, wallet transaction ID). Required when status=paid.';


--
-- Name: CONSTRAINT chk_paid_settlement_has_payout_method ON driver_settlements; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON CONSTRAINT chk_paid_settlement_has_payout_method ON public.driver_settlements IS 'A settlement in the paid state MUST have a payout_method recorded. Prevents finance reconciliation gaps. Added by migration 084 (gap-analysis §3.5 + §3.1).';


--
-- Name: CONSTRAINT chk_paid_settlement_has_payout_reference ON driver_settlements; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON CONSTRAINT chk_paid_settlement_has_payout_reference ON public.driver_settlements IS 'A settlement in the paid state MUST have a payout_reference recorded (bank transfer ref, cash receipt #, etc.). Added by migration 084.';


--
-- Name: driver_status_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.driver_status_history (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    driver_id uuid NOT NULL,
    previous_status text NOT NULL,
    new_status text NOT NULL,
    changed_by uuid NOT NULL,
    reason text,
    changed_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE driver_status_history; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.driver_status_history IS 'Audit trail for driver lifecycle status changes (verification, activation, deactivation). Every change is logged with who changed what and why.';


--
-- Name: COLUMN driver_status_history.previous_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.driver_status_history.previous_status IS 'Status before the change (e.g., pending, approved, deactivated).';


--
-- Name: COLUMN driver_status_history.new_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.driver_status_history.new_status IS 'Status after the change (e.g., under_review, approved, deactivated).';


--
-- Name: COLUMN driver_status_history.changed_by; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.driver_status_history.changed_by IS 'Admin who made the change. References profiles.id.';


--
-- Name: drivers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.drivers (
    id uuid NOT NULL,
    national_id text NOT NULL,
    national_id_image_url text,
    driving_license_number text,
    driving_license_image_url text,
    vehicle_registration_image_url text,
    vehicle_type text NOT NULL,
    vehicle_plate text NOT NULL,
    vehicle_color text,
    vehicle_model text,
    is_verified boolean DEFAULT false NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    is_online boolean DEFAULT false NOT NULL,
    verification_status text DEFAULT 'pending'::text NOT NULL,
    rejection_reason text,
    current_lat numeric(9,6),
    current_lng numeric(9,6),
    last_location_at timestamp with time zone,
    rating numeric(2,1) DEFAULT 5.0 NOT NULL,
    rating_count integer DEFAULT 0 NOT NULL,
    total_deliveries integer DEFAULT 0 NOT NULL,
    total_earnings numeric(10,2) DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    verified_at timestamp with time zone,
    deactivated_at timestamp with time zone,
    national_id_encrypted text,
    consecutive_declines integer DEFAULT 0 NOT NULL,
    suspended_until timestamp with time zone,
    payout_frequency text DEFAULT 'weekly'::text NOT NULL,
    payout_method text DEFAULT 'cash'::text NOT NULL,
    CONSTRAINT drivers_payout_frequency_check CHECK ((payout_frequency = ANY (ARRAY['daily'::text, 'weekly'::text, 'monthly'::text]))),
    CONSTRAINT drivers_payout_method_check CHECK ((payout_method = ANY (ARRAY['cash'::text, 'bank_transfer'::text, 'wallet'::text, 'instapay'::text]))),
    CONSTRAINT drivers_rating_check CHECK (((rating >= (0)::numeric) AND (rating <= (5)::numeric))),
    CONSTRAINT drivers_total_earnings_check CHECK ((total_earnings >= (0)::numeric)),
    CONSTRAINT drivers_vehicle_type_check CHECK ((vehicle_type = ANY (ARRAY['motorcycle'::text, 'car'::text, 'bicycle'::text]))),
    CONSTRAINT drivers_verification_status_check CHECK ((verification_status = ANY (ARRAY['pending'::text, 'under_review'::text, 'approved'::text, 'rejected'::text])))
);


--
-- Name: TABLE drivers; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.drivers IS 'Driver profiles — created by admin only. National IDs should be stored encrypted in national_id_encrypted. The plaintext national_id is kept for transition only.';


--
-- Name: COLUMN drivers.is_verified; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.drivers.is_verified IS 'Admin must verify before driver can go online. Set to TRUE only via admin-review-driver Edge Function.';


--
-- Name: COLUMN drivers.is_active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.drivers.is_active IS 'Admin can deactivate without deleting (safety, fraud). Driver cannot go online if false.';


--
-- Name: COLUMN drivers.is_online; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.drivers.is_online IS 'Driver toggles this. Only matters if is_verified=TRUE AND is_active=TRUE.';


--
-- Name: COLUMN drivers.verification_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.drivers.verification_status IS 'pending=just created by admin, under_review=docs uploaded by driver, approved=admin verified docs, rejected=admin rejected docs.';


--
-- Name: COLUMN drivers.rejection_reason; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.drivers.rejection_reason IS 'If verification_status=rejected, this explains why. Shown to driver in app.';


--
-- Name: COLUMN drivers.current_lat; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.drivers.current_lat IS 'Latitude updated by driver app every ~5 seconds when online. NULL when offline.';


--
-- Name: COLUMN drivers.current_lng; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.drivers.current_lng IS 'Longitude updated by driver app every ~5 seconds when online. NULL when offline.';


--
-- Name: COLUMN drivers.last_location_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.drivers.last_location_at IS 'Timestamp of last location update. Used to detect stale locations.';


--
-- Name: COLUMN drivers.verified_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.drivers.verified_at IS 'When admin approved this driver. NULL if not yet verified.';


--
-- Name: COLUMN drivers.deactivated_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.drivers.deactivated_at IS 'When admin deactivated this driver. NULL if active.';


--
-- Name: COLUMN drivers.national_id_encrypted; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.drivers.national_id_encrypted IS 'AES-256 encrypted national ID. Use decrypt_national_id() to read. The plaintext national_id column will be deprecated after data migration.';


--
-- Name: COLUMN drivers.payout_frequency; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.drivers.payout_frequency IS 'How often the auto-generate-driver-settlements cron should aggregate this drivers pending earnings into a settlement row. daily = every night, weekly = every Sunday 03:30 UTC, monthly = first of month 03:30 UTC.';


--
-- Name: COLUMN drivers.payout_method; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.drivers.payout_method IS 'Default payout channel for this driver. Used by create_driver_settlement when the admin does not pass an explicit p_payout_method. cash = manual handover; bank_transfer/wallet/instapay = manual ops transfer with payout_reference.';


--
-- Name: favorite_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.favorite_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid DEFAULT auth.uid() NOT NULL,
    item_id uuid NOT NULL,
    merchant_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE favorite_items; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.favorite_items IS 'Customer favorited menu items. Simple junction table with unique constraint on (user_id, item_id) for quick item reordering.';


--
-- Name: COLUMN favorite_items.user_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.favorite_items.user_id IS 'Customer who favorited the menu item.';


--
-- Name: COLUMN favorite_items.item_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.favorite_items.item_id IS 'Menu item that was favorited.';


--
-- Name: COLUMN favorite_items.merchant_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.favorite_items.merchant_id IS 'Merchant that sells the favorited item (stored for query optimization).';


--
-- Name: favorites; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.favorites (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid DEFAULT auth.uid() NOT NULL,
    merchant_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE favorites; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.favorites IS 'Customer favorited merchants. Simple junction table for quick access to preferred merchants.';


--
-- Name: COLUMN favorites.user_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.favorites.user_id IS 'Customer who favorited the merchant.';


--
-- Name: COLUMN favorites.merchant_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.favorites.merchant_id IS 'Merchant who was favorited.';


--
-- Name: item_option_choices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.item_option_choices (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    option_id uuid NOT NULL,
    name_ar text NOT NULL,
    name_en text NOT NULL,
    price_modifier numeric(10,2) DEFAULT 0.00 NOT NULL,
    is_default boolean DEFAULT false NOT NULL,
    is_available boolean DEFAULT true NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    calories integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT item_option_choices_price_modifier_check CHECK ((price_modifier >= (0)::numeric))
);


--
-- Name: TABLE item_option_choices; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.item_option_choices IS 'Individual choices within option groups. Each has a price modifier added to base item price.';


--
-- Name: COLUMN item_option_choices.price_modifier; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.item_option_choices.price_modifier IS 'Amount in EGP added to the item base price when this choice is selected.';


--
-- Name: COLUMN item_option_choices.is_default; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.item_option_choices.is_default IS 'If true, this choice is pre-selected in the UI.';


--
-- Name: item_options; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.item_options (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    item_id uuid NOT NULL,
    name_ar text NOT NULL,
    name_en text NOT NULL,
    is_required boolean DEFAULT false NOT NULL,
    max_selections integer,
    min_selections integer DEFAULT 0 NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT item_options_max_selections_check CHECK (((max_selections IS NULL) OR (max_selections >= 1))),
    CONSTRAINT item_options_min_selections_check CHECK ((min_selections >= 0))
);


--
-- Name: TABLE item_options; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.item_options IS 'Option groups for items (e.g., Size, Extra Toppings). Some required, some optional.';


--
-- Name: COLUMN item_options.is_required; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.item_options.is_required IS 'If true, customer must select at least min_selections choices from this group.';


--
-- Name: COLUMN item_options.max_selections; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.item_options.max_selections IS 'Maximum choices selectable. NULL=unlimited, 1=single select.';


--
-- Name: items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    merchant_id uuid NOT NULL,
    category_id uuid NOT NULL,
    name_ar text NOT NULL,
    name_en text NOT NULL,
    description_ar text,
    description_en text,
    price numeric(10,2) NOT NULL,
    image_url text,
    is_available boolean DEFAULT true NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    popularity_score integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT items_price_check CHECK ((price >= (0)::numeric))
);


--
-- Name: TABLE items; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.items IS 'Menu items within categories. Prices in EGP. Bilingual names and descriptions. Price snapshots taken at order time.';


--
-- Name: COLUMN items.price; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.items.price IS 'Base price in EGP. Actual price at order time is snapshotted in order_items.';


--
-- Name: loyalty_promo_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.loyalty_promo_log (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    customer_id uuid NOT NULL,
    promo_code_id uuid NOT NULL,
    spend_threshold_met numeric(10,2) NOT NULL,
    issued_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE loyalty_promo_log; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.loyalty_promo_log IS 'Phase 4b: Tracks loyalty promos auto-issued to customers (cooldown enforcement). RLS on with zero policies — service-role only (auto-issue-loyalty-promos cron EF).';


--
-- Name: merchant_payout_orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_payout_orders (
    payout_id uuid NOT NULL,
    order_id uuid NOT NULL,
    merchant_payout_at_settlement numeric(10,2) NOT NULL
);


--
-- Name: TABLE merchant_payout_orders; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_payout_orders IS 'Junction linking orders rows to the merchant_payouts row that paid them. Prevents double-payment (a paid order cannot be re-settled). The merchant_payout_at_settlement snapshot preserves the amount even if the order row is later edited.';


--
-- Name: merchant_payouts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_payouts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    merchant_id uuid NOT NULL,
    period_start timestamp with time zone NOT NULL,
    period_end timestamp with time zone NOT NULL,
    order_count integer NOT NULL,
    gross_subtotal numeric(10,2) NOT NULL,
    commission_deducted numeric(10,2) NOT NULL,
    promo_discount_merchant_share numeric(10,2) DEFAULT 0 NOT NULL,
    cancellation_adjustment numeric(10,2) DEFAULT 0 NOT NULL,
    net_payable numeric(10,2) NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    paymob_transaction_id text,
    paid_at timestamp with time zone,
    paid_by uuid,
    payout_method text,
    payout_reference text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_paid_payout_has_payout_method CHECK (((status <> 'paid'::text) OR (payout_method IS NOT NULL))),
    CONSTRAINT chk_paid_payout_has_payout_reference CHECK (((status <> 'paid'::text) OR (payout_reference IS NOT NULL))),
    CONSTRAINT merchant_payouts_commission_deducted_check CHECK ((commission_deducted >= (0)::numeric)),
    CONSTRAINT merchant_payouts_gross_subtotal_check CHECK ((gross_subtotal >= (0)::numeric)),
    CONSTRAINT merchant_payouts_net_payable_check CHECK ((net_payable >= (0)::numeric)),
    CONSTRAINT merchant_payouts_order_count_check CHECK ((order_count >= 0)),
    CONSTRAINT merchant_payouts_payout_method_check CHECK (((payout_method IS NULL) OR (payout_method = ANY (ARRAY['bank_transfer'::text, 'wallet'::text, 'cash'::text, 'instapay'::text])))),
    CONSTRAINT merchant_payouts_promo_discount_merchant_share_check CHECK ((promo_discount_merchant_share >= (0)::numeric)),
    CONSTRAINT merchant_payouts_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'paid'::text, 'failed'::text, 'cancelled'::text])))
);


--
-- Name: TABLE merchant_payouts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_payouts IS 'Period-aggregated merchant payout rows. Each row settles a batch of delivered orders (linked via merchant_payout_orders). Status machine: pending → approved → paid. Paymob disbursement NOT wired — admin marks paid manually via mark_merchant_payout_paid RPC. Mirrors driver_settlements (migration 083).';


--
-- Name: COLUMN merchant_payouts.promo_discount_merchant_share; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_payouts.promo_discount_merchant_share IS 'Total discount absorbed by the merchant across all orders in this payout (per orders.promo_funded_by snapshot — S1). When 0, all promos were platform-funded.';


--
-- Name: COLUMN merchant_payouts.cancellation_adjustment; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_payouts.cancellation_adjustment IS 'Net adjustment for cancelled orders in the period. v1 implementation: always 0 (cancellations are already reflected per-order in merchant_payout via the S2 fix in migration 081/082). Reserved for future use if finance wants to surface cancellations separately.';


--
-- Name: COLUMN merchant_payouts.payout_method; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_payouts.payout_method IS 'Payment channel for this payout. cash = handover (no Paymob), bank_transfer/wallet/instapay = manual ops transfer with payout_reference.';


--
-- Name: COLUMN merchant_payouts.payout_reference; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_payouts.payout_reference IS 'Free-text reference for the manual payout (bank transfer ref #, cash receipt #, wallet transaction ID). Required when status=paid (enforced by CHECK constraint + trigger).';


--
-- Name: CONSTRAINT chk_paid_payout_has_payout_method ON merchant_payouts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON CONSTRAINT chk_paid_payout_has_payout_method ON public.merchant_payouts IS 'A payout in the paid state MUST have a payout_method recorded. Prevents finance reconciliation gaps (gap-analysis §3.5, baked in from day one).';


--
-- Name: CONSTRAINT chk_paid_payout_has_payout_reference ON merchant_payouts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON CONSTRAINT chk_paid_payout_has_payout_reference ON public.merchant_payouts IS 'A payout in the paid state MUST have a payout_reference recorded (bank transfer ref, cash receipt #, etc.).';


--
-- Name: operating_hours; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.operating_hours (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    merchant_id uuid NOT NULL,
    day_of_week smallint NOT NULL,
    open_time time without time zone NOT NULL,
    close_time time without time zone NOT NULL,
    is_closed boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT operating_hours_day_of_week_check CHECK (((day_of_week >= 0) AND (day_of_week <= 6)))
);


--
-- Name: TABLE operating_hours; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.operating_hours IS 'Per-day operating schedule for merchants. Used by is_merchant_open() to determine current open status.';


--
-- Name: COLUMN operating_hours.day_of_week; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.operating_hours.day_of_week IS '0=Sunday, 1=Monday, 2=Tuesday, 3=Wednesday, 4=Thursday, 5=Friday, 6=Saturday (Egyptian week).';


--
-- Name: COLUMN operating_hours.is_closed; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.operating_hours.is_closed IS 'If true, the merchant is closed on this day regardless of open_time/close_time.';


--
-- Name: merchants_with_open_status; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.merchants_with_open_status AS
 SELECT id,
    name_ar,
    name_en,
    category,
    logo_url,
    cover_url,
    description_ar,
    description_en,
    address,
    lat,
    lng,
    city,
    area,
    phone,
    is_active,
    rating,
    rating_count,
    min_order_amount,
    estimated_delivery_minutes,
    delivery_fee_override,
    commission_pct,
    created_at,
    (EXISTS ( SELECT 1
           FROM public.operating_hours oh
          WHERE ((oh.merchant_id = m.id) AND ((oh.day_of_week)::numeric = EXTRACT(isodow FROM (now() AT TIME ZONE 'Africa/Cairo'::text))) AND (oh.is_closed = false) AND (((now() AT TIME ZONE 'Africa/Cairo'::text))::time without time zone >= oh.open_time) AND (((now() AT TIME ZONE 'Africa/Cairo'::text))::time without time zone < oh.close_time)))) AS is_currently_open
   FROM public.merchants m
  WHERE (is_active = true)
  WITH NO DATA;


--
-- Name: MATERIALIZED VIEW merchants_with_open_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON MATERIALIZED VIEW public.merchants_with_open_status IS 'Active merchants with pre-computed is_currently_open status. Refresh every 1-2 minutes. Used by get-merchant-feed for batch-efficient open status (RED-01, RED-06).';


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    type text DEFAULT 'general'::text NOT NULL,
    title_ar text NOT NULL,
    title_en text NOT NULL,
    body_ar text NOT NULL,
    body_en text NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    is_read boolean DEFAULT false NOT NULL,
    read_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    reference_id uuid,
    CONSTRAINT notifications_type_check CHECK ((type = ANY (ARRAY['order_status'::text, 'order_assigned'::text, 'order_delivered'::text, 'order_cancelled'::text, 'promo'::text, 'driver_verified'::text, 'driver_rejected'::text, 'driver_deactivated'::text, 'driver_request'::text, 'review_request'::text, 'wallet'::text, 'general'::text])))
);


--
-- Name: TABLE notifications; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.notifications IS 'In-app notifications. Inserted by Edge Functions via service role. Push notifications sent separately via Expo Push API.';


--
-- Name: COLUMN notifications.type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.notifications.type IS 'Notification type for icon selection and deep linking in the app.';


--
-- Name: COLUMN notifications.data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.notifications.data IS 'JSONB payload for deep linking. E.g., {"order_id": "...", "screen": "order_tracking"}.';


--
-- Name: COLUMN notifications.is_read; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.notifications.is_read IS 'False=unread (shown with dot/badge), True=read.';


--
-- Name: COLUMN notifications.reference_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.notifications.reference_id IS 'UUID of the related entity (order, driver, user). Used for deep-link navigation on notification tap.';


--
-- Name: order_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.order_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid NOT NULL,
    item_id uuid NOT NULL,
    item_name_ar text NOT NULL,
    item_name_en text NOT NULL,
    item_price numeric(10,2) NOT NULL,
    quantity integer NOT NULL,
    selected_options jsonb DEFAULT '[]'::jsonb NOT NULL,
    total_price numeric(10,2) NOT NULL,
    special_instructions text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT order_items_item_price_check CHECK ((item_price >= (0)::numeric)),
    CONSTRAINT order_items_quantity_check CHECK ((quantity > 0)),
    CONSTRAINT order_items_total_price_check CHECK ((total_price >= (0)::numeric))
);


--
-- Name: TABLE order_items; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.order_items IS 'Items in an order with PRICE SNAPSHOTS at order time. Critical: item names and prices are frozen, never updated after insert. This prevents price mismatch disputes.';


--
-- Name: COLUMN order_items.item_name_ar; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.order_items.item_name_ar IS 'SNAPSHOT of item Arabic name at order time. Never updated after insert.';


--
-- Name: COLUMN order_items.item_name_en; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.order_items.item_name_en IS 'SNAPSHOT of item English name at order time. Never updated after insert.';


--
-- Name: COLUMN order_items.item_price; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.order_items.item_price IS 'SNAPSHOT of item price at order time. Never updated after insert. In EGP.';


--
-- Name: COLUMN order_items.selected_options; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.order_items.selected_options IS 'JSONB array of selected option choices at order time. Each entry: {option_name_ar, option_name_en, choice_name_ar, choice_name_en, price_modifier}.';


--
-- Name: COLUMN order_items.total_price; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.order_items.total_price IS '(item_price + sum of option modifiers) * quantity. In EGP.';


--
-- Name: order_number_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.order_number_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: order_status_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.order_status_history (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid NOT NULL,
    status text NOT NULL,
    changed_by uuid,
    changed_by_role text,
    note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT order_status_history_changed_by_role_check CHECK (((changed_by_role IS NULL) OR (changed_by_role = ANY (ARRAY['customer'::text, 'driver'::text, 'admin'::text, 'system'::text])))),
    CONSTRAINT order_status_history_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'confirmed'::text, 'preparing'::text, 'ready'::text, 'picked_up'::text, 'on_the_way'::text, 'delivered'::text, 'cancelled'::text])))
);


--
-- Name: TABLE order_status_history; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.order_status_history IS 'Audit trail for every order status change. Every transition is logged with who changed it and why.';


--
-- Name: orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.orders (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_number text,
    customer_id uuid NOT NULL,
    merchant_id uuid NOT NULL,
    driver_id uuid,
    status text DEFAULT 'pending'::text NOT NULL,
    delivery_address jsonb NOT NULL,
    customer_phone text,
    subtotal numeric(10,2) NOT NULL,
    delivery_fee numeric(10,2) DEFAULT 0 NOT NULL,
    platform_fee numeric(10,2) DEFAULT 0 NOT NULL,
    discount_amount numeric(10,2) DEFAULT 0 NOT NULL,
    total numeric(10,2) NOT NULL,
    payment_method text DEFAULT 'cash'::text NOT NULL,
    payment_status text DEFAULT 'pending'::text NOT NULL,
    paymob_order_id text,
    paymob_transaction_id text,
    promo_code_id uuid,
    promo_code text,
    distance_km numeric(6,2),
    estimated_delivery_minutes integer,
    cancelled_by uuid,
    cancellation_reason text,
    cancellation_fee numeric(10,2) DEFAULT 0,
    cancelled_at timestamp with time zone,
    refund_amount numeric(10,2),
    refunded_at timestamp with time zone,
    refund_id text,
    refund_status text,
    admin_notes text,
    idempotency_key text,
    merchant_commission_pct numeric(5,2),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    confirmed_at timestamp with time zone,
    delivered_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    notes text,
    scheduled_time timestamp with time zone,
    promo_funded_by text,
    promo_merchant_share_pct numeric(5,2),
    merchant_payout numeric(10,2) DEFAULT 0.00 NOT NULL,
    payout_recomputed_at timestamp with time zone,
    paid_at timestamp with time zone,
    CONSTRAINT chk_merchant_payout_non_negative CHECK ((merchant_payout >= (0)::numeric)),
    CONSTRAINT orders_cancellation_fee_check CHECK ((cancellation_fee >= (0)::numeric)),
    CONSTRAINT orders_check CHECK (((scheduled_time IS NULL) OR (scheduled_time > created_at))),
    CONSTRAINT orders_delivery_fee_check CHECK ((delivery_fee >= (0)::numeric)),
    CONSTRAINT orders_discount_amount_check CHECK ((discount_amount >= (0)::numeric)),
    CONSTRAINT orders_payment_method_check CHECK ((payment_method = ANY (ARRAY['cash'::text, 'card'::text, 'vodafone_cash'::text, 'instapay'::text, 'orange_cash'::text, 'wallet'::text]))),
    CONSTRAINT orders_payment_status_check CHECK ((payment_status = ANY (ARRAY['pending'::text, 'pending_cash'::text, 'paid'::text, 'failed'::text, 'refunded'::text, 'pending_refund'::text, 'partial_refund'::text, 'refund_failed'::text]))),
    CONSTRAINT orders_platform_fee_check CHECK ((platform_fee >= (0)::numeric)),
    CONSTRAINT orders_promo_funded_by_check CHECK (((promo_funded_by IS NULL) OR (promo_funded_by = ANY (ARRAY['platform'::text, 'merchant'::text, 'shared'::text])))),
    CONSTRAINT orders_promo_merchant_share_pct_check CHECK (((promo_merchant_share_pct IS NULL) OR ((promo_merchant_share_pct >= (0)::numeric) AND (promo_merchant_share_pct <= (100)::numeric)))),
    CONSTRAINT orders_refund_status_check CHECK (((refund_status IS NULL) OR (refund_status = ANY (ARRAY['pending_refund'::text, 'refunded'::text, 'refund_failed'::text, 'partial_refund'::text])))),
    CONSTRAINT orders_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'confirmed'::text, 'preparing'::text, 'ready'::text, 'picked_up'::text, 'on_the_way'::text, 'delivered'::text, 'cancelled'::text]))),
    CONSTRAINT orders_subtotal_check CHECK ((subtotal >= (0)::numeric)),
    CONSTRAINT orders_total_check CHECK ((total >= (0)::numeric))
);


--
-- Name: TABLE orders; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.orders IS 'S02/S19 fix: No direct client INSERT or UPDATE policies. All order mutations go through cancel_order RPC (migration 033, via cancel-order Edge Function), place_order_with_items RPC (migration 045, via place-order Edge Function), driver-actions Edge Function, or admin API routes (service role).';


--
-- Name: COLUMN orders.order_number; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.orders.order_number IS 'Auto-generated order number in ORD-XXXXXX format. Generated by trigger using a sequence.';


--
-- Name: COLUMN orders.delivery_address; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.orders.delivery_address IS 'JSONB snapshot of delivery address at order time: {address, lat, lng, building, floor, apartment, landmark, city, area}.';


--
-- Name: COLUMN orders.payment_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.orders.payment_status IS 'pending=awaiting payment, pending_cash=cash on delivery, paid=payment confirmed, failed=payment failed, refunded=full refund, pending_refund=refund processing, partial_refund=partial refund issued, refund_failed=refund attempt failed.';


--
-- Name: COLUMN orders.idempotency_key; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.orders.idempotency_key IS 'Client-provided key to prevent duplicate orders on retry. Unique constraint ensures same key cannot create two orders.';


--
-- Name: COLUMN orders.merchant_commission_pct; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.orders.merchant_commission_pct IS 'Commission percentage snapshot at order time. Used to calculate merchant payout.';


--
-- Name: COLUMN orders.notes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.orders.notes IS 'Customer-provided delivery instructions or notes for this order. Visible to driver and merchant. Distinct from admin_notes which is internal-only.';


--
-- Name: COLUMN orders.scheduled_time; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.orders.scheduled_time IS 'Customer-requested delivery time (NULL = ASAP). Must be later than created_at.';


--
-- Name: COLUMN orders.promo_funded_by; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.orders.promo_funded_by IS 'Snapshot of promo_codes.funded_by at order time. NULL if no promo applied. For payout forensic audit.';


--
-- Name: COLUMN orders.promo_merchant_share_pct; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.orders.promo_merchant_share_pct IS 'Snapshot of promo_codes.merchant_share_pct at order time. NULL if no promo applied. For payout forensic audit.';


--
-- Name: COLUMN orders.merchant_payout; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.orders.merchant_payout IS 'Net payout to merchant in EGP. Computed by place_order_with_items RPC using promo funded_by logic (subtotal - merchant discount share) * (1 - commission%). Recomputed by cancel_order RPC on cancellation. NO LONGER A GENERATED COLUMN since migration 079.';


--
-- Name: COLUMN orders.payout_recomputed_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.orders.payout_recomputed_at IS 'Timestamp when merchant_payout was last recomputed by the cancel_order RPC (S2). NULL for non-cancelled orders and for cancellations that occurred before migration 082 deployed. Used by finance to distinguish pre-fix vs post-fix cancellations during the 30-day retrospective.';


--
-- Name: COLUMN orders.paid_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.orders.paid_at IS 'When the digital payment was confirmed (webhook / reconcile / place-order for pre-paid methods). NULL = not yet captured. Never backfilled — historic rows stay NULL.';


--
-- Name: platform_config; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platform_config (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    key text NOT NULL,
    value text NOT NULL,
    description text,
    value_type text DEFAULT 'string'::text NOT NULL,
    is_editable boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT platform_config_value_type_check CHECK ((value_type = ANY (ARRAY['string'::text, 'number'::text, 'boolean'::text, 'json'::text])))
);


--
-- Name: TABLE platform_config; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.platform_config IS 'Runtime configuration key-value store. Editable from admin panel without code deployment. Used by DB functions and edge functions.';


--
-- Name: COLUMN platform_config.key; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.platform_config.key IS 'Unique configuration key. Used by functions to fetch values.';


--
-- Name: COLUMN platform_config.value; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.platform_config.value IS 'Configuration value stored as text. Consuming functions cast to appropriate type.';


--
-- Name: profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profiles (
    id uuid NOT NULL,
    full_name text,
    phone text,
    avatar_url text,
    role text DEFAULT 'customer'::text NOT NULL,
    preferred_language text DEFAULT 'ar'::text NOT NULL,
    wallet_balance numeric(10,2) DEFAULT 0.00 NOT NULL,
    expo_push_token text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    CONSTRAINT profiles_preferred_language_check CHECK ((preferred_language = ANY (ARRAY['ar'::text, 'en'::text]))),
    CONSTRAINT profiles_role_check CHECK ((role = ANY (ARRAY['customer'::text, 'driver'::text, 'admin'::text]))),
    CONSTRAINT profiles_wallet_balance_check CHECK ((wallet_balance >= (0)::numeric))
);


--
-- Name: TABLE profiles; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.profiles IS 'Extends auth.users with app-specific profile data. Auto-created on signup.';


--
-- Name: COLUMN profiles.role; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.profiles.role IS 'customer=self-signup, driver=admin-created only, admin=manual insert. RLS prevents self-assignment to driver.';


--
-- Name: COLUMN profiles.preferred_language; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.profiles.preferred_language IS 'ar=Arabic (default for Egypt), en=English';


--
-- Name: COLUMN profiles.wallet_balance; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.profiles.wallet_balance IS 'Platform wallet for refunds and promotional credits. Not used for payments.';


--
-- Name: COLUMN profiles.is_active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.profiles.is_active IS 'Soft-delete flag. FALSE = user invoked deleteAccount (profile + auth.users row retained for audit). Set to FALSE by auth.service.ts:deleteAccount().';


--
-- Name: promo_code_usage; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.promo_code_usage (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    promo_code_id uuid NOT NULL,
    user_id uuid NOT NULL,
    order_id uuid NOT NULL,
    discount_amount numeric(10,2) NOT NULL,
    used_at timestamp with time zone DEFAULT now() NOT NULL,
    ip_address inet,
    CONSTRAINT promo_code_usage_discount_amount_check CHECK ((discount_amount >= (0)::numeric))
);


--
-- Name: COLUMN promo_code_usage.ip_address; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.promo_code_usage.ip_address IS 'P2-7: IP address the promo was redeemed from. Used by check_promo_fraud RPC to detect multi-account abuse. Nullable for old rows + anonymous redemptions.';


--
-- Name: promo_codes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.promo_codes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    code text NOT NULL,
    discount_type text NOT NULL,
    discount_value numeric(10,2) NOT NULL,
    max_discount_amount numeric(10,2) DEFAULT 100.00 NOT NULL,
    starts_at timestamp with time zone NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    max_usage integer DEFAULT 100 NOT NULL,
    current_usage integer DEFAULT 0 NOT NULL,
    max_usage_per_user integer DEFAULT 1 NOT NULL,
    min_order_amount numeric(10,2) DEFAULT 0 NOT NULL,
    merchant_id uuid,
    category text,
    description_ar text,
    description_en text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    free_delivery boolean DEFAULT false NOT NULL,
    last_broadcast_at timestamp with time zone,
    deleted_at timestamp with time zone,
    city text,
    area text,
    target_segment text DEFAULT 'all'::text NOT NULL,
    stackable boolean DEFAULT false NOT NULL,
    funded_by text DEFAULT 'platform'::text NOT NULL,
    merchant_share_pct numeric(5,2) DEFAULT 50.00 NOT NULL,
    CONSTRAINT promo_codes_current_usage_check CHECK ((current_usage >= 0)),
    CONSTRAINT promo_codes_discount_type_check CHECK ((discount_type = ANY (ARRAY['percentage'::text, 'flat'::text]))),
    CONSTRAINT promo_codes_discount_value_check CHECK ((discount_value > (0)::numeric)),
    CONSTRAINT promo_codes_funded_by_check CHECK ((funded_by = ANY (ARRAY['platform'::text, 'merchant'::text, 'shared'::text]))),
    CONSTRAINT promo_codes_max_discount_amount_check CHECK ((max_discount_amount > (0)::numeric)),
    CONSTRAINT promo_codes_max_usage_check CHECK ((max_usage > 0)),
    CONSTRAINT promo_codes_max_usage_per_user_check CHECK ((max_usage_per_user > 0)),
    CONSTRAINT promo_codes_merchant_share_pct_check CHECK (((merchant_share_pct >= (0)::numeric) AND (merchant_share_pct <= (100)::numeric))),
    CONSTRAINT promo_codes_min_order_amount_check CHECK ((min_order_amount >= (0)::numeric)),
    CONSTRAINT promo_codes_target_segment_check CHECK ((target_segment = ANY (ARRAY['all'::text, 'new_users'::text, 'first_order'::text, 'dormant_30d'::text])))
);


--
-- Name: TABLE promo_codes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.promo_codes IS 'Discount codes. Validated server-side only via validate-promo Edge Function. No direct client read access to prevent code scraping.';


--
-- Name: COLUMN promo_codes.discount_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.promo_codes.discount_type IS 'percentage=X% off subtotal, flat=fixed EGP amount off subtotal.';


--
-- Name: COLUMN promo_codes.max_discount_amount; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.promo_codes.max_discount_amount IS 'Maximum discount cap in EGP. Even if percentage discount exceeds this, the discount is capped.';


--
-- Name: COLUMN promo_codes.max_usage_per_user; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.promo_codes.max_usage_per_user IS 'How many times a single user can apply this promo.';


--
-- Name: COLUMN promo_codes.merchant_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.promo_codes.merchant_id IS 'If set, promo only valid for this merchant. If NULL, valid for all merchants.';


--
-- Name: COLUMN promo_codes.free_delivery; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.promo_codes.free_delivery IS 'If TRUE, this promo code grants free delivery regardless of delivery fee calculation.';


--
-- Name: COLUMN promo_codes.last_broadcast_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.promo_codes.last_broadcast_at IS 'P1-5: Timestamp of the last successful broadcast push. The /push route rejects with 429 if this is less than 1 hour ago.';


--
-- Name: COLUMN promo_codes.deleted_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.promo_codes.deleted_at IS 'P1-4: Soft-delete timestamp. NULL = active row. Set by DELETE /api/promo-codes/[id]. Admin list queries filter WHERE deleted_at IS NULL unless ?include_deleted=true.';


--
-- Name: COLUMN promo_codes.city; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.promo_codes.city IS 'P2-4: If set, the promo is only valid for orders delivered to this city. NULL = all cities. Checked by validatePromoCode against the customer delivery address city.';


--
-- Name: COLUMN promo_codes.area; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.promo_codes.area IS 'P2-4: If set, the promo is only valid for orders delivered to this area. NULL = all areas. More specific than city — e.g. city=Cairo, area=Maadi.';


--
-- Name: COLUMN promo_codes.target_segment; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.promo_codes.target_segment IS 'P2-5: User segment this promo targets. all = everyone, new_users = accounts created within 7 days, first_order = customers with 0 non-cancelled orders, dormant_30d = customers with >=1 order but none in last 30 days. Enforced by validatePromoCode.';


--
-- Name: COLUMN promo_codes.stackable; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.promo_codes.stackable IS 'P2-6: Whether this promo can be stacked with other promos on the same order. Currently informational — orders support only one promo (single promo_code_id column). Reserved for future multi-promo support.';


--
-- Name: COLUMN promo_codes.funded_by; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.promo_codes.funded_by IS 'Who absorbs the discount cost: platform (100% platform), merchant (100% merchant), shared (split by merchant_share_pct). Configurable per-promo from the admin dashboard.';


--
-- Name: COLUMN promo_codes.merchant_share_pct; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.promo_codes.merchant_share_pct IS 'When funded_by=shared, the percentage of the discount amount absorbed by the merchant (0-100). Remainder is absorbed by the platform. Default 50%. Only meaningful when funded_by=shared.';


--
-- Name: promoted_slot_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.promoted_slot_events (
    id bigint NOT NULL,
    slot_id uuid NOT NULL,
    event_type text NOT NULL,
    customer_id uuid,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT promoted_slot_events_event_type_check CHECK ((event_type = ANY (ARRAY['impression'::text, 'click'::text])))
);


--
-- Name: TABLE promoted_slot_events; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.promoted_slot_events IS 'P1-6: Per-event time-series for promoted slot impressions and clicks. RLS on with zero policies — service-role only (EF impression writers + admin analytics routes).';


--
-- Name: promoted_slot_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.promoted_slot_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: promoted_slot_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.promoted_slot_events_id_seq OWNED BY public.promoted_slot_events.id;


--
-- Name: promoted_slots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.promoted_slots (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    merchant_id uuid NOT NULL,
    slot_type text DEFAULT 'feed_top'::text NOT NULL,
    starts_at timestamp with time zone NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    city text DEFAULT 'Cairo'::text NOT NULL,
    category text,
    title_ar text,
    title_en text,
    subtitle_ar text,
    subtitle_en text,
    image_url text,
    is_active boolean DEFAULT true NOT NULL,
    price_paid numeric(10,2) DEFAULT 0 NOT NULL,
    impressions integer DEFAULT 0 NOT NULL,
    clicks integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    last_broadcast_at timestamp with time zone,
    deleted_at timestamp with time zone,
    CONSTRAINT promoted_slots_price_paid_check CHECK ((price_paid >= (0)::numeric)),
    CONSTRAINT promoted_slots_slot_type_check CHECK ((slot_type = ANY (ARRAY['feed_top'::text, 'feed_category'::text, 'search_result'::text, 'banner'::text])))
);


--
-- Name: TABLE promoted_slots; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.promoted_slots IS 'Paid ad placements for merchants in the customer feed. Promoted merchants appear at top of feed, clearly marked as Sponsored.';


--
-- Name: COLUMN promoted_slots.slot_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.promoted_slots.slot_type IS 'feed_top=top of main feed, feed_category=top of category filter, search_result=promoted in search, banner=hero banner.';


--
-- Name: COLUMN promoted_slots.impressions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.promoted_slots.impressions IS 'Number of times this ad was shown to customers. Updated by get-merchant-feed Edge Function.';


--
-- Name: COLUMN promoted_slots.clicks; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.promoted_slots.clicks IS 'Number of times customers tapped on this ad. Updated when customer opens merchant page from promoted slot.';


--
-- Name: COLUMN promoted_slots.last_broadcast_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.promoted_slots.last_broadcast_at IS 'P1-5: Timestamp of the last successful broadcast push. The /push route rejects with 429 if this is less than 1 hour ago.';


--
-- Name: COLUMN promoted_slots.deleted_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.promoted_slots.deleted_at IS 'P1-4: Soft-delete timestamp. NULL = active row. Set by DELETE /api/promoted-ads/[id]. Admin list queries filter WHERE deleted_at IS NULL unless ?include_deleted=true.';


--
-- Name: reviews; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reviews (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    merchant_id uuid NOT NULL,
    driver_id uuid,
    merchant_rating smallint NOT NULL,
    driver_rating smallint,
    merchant_comment text,
    driver_comment text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    is_visible boolean DEFAULT false NOT NULL,
    moderated_by uuid,
    moderated_at timestamp with time zone,
    moderation_note text,
    CONSTRAINT reviews_driver_rating_check CHECK (((driver_rating >= 1) AND (driver_rating <= 5))),
    CONSTRAINT reviews_merchant_rating_check CHECK (((merchant_rating >= 1) AND (merchant_rating <= 5)))
);


--
-- Name: TABLE reviews; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.reviews IS 'Customer ratings for merchants and drivers. One review per order. Triggers update aggregate ratings on merchants and drivers tables.';


--
-- Name: COLUMN reviews.merchant_rating; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reviews.merchant_rating IS 'Required rating 1-5 for the merchant. 1=terrible, 5=excellent.';


--
-- Name: COLUMN reviews.driver_rating; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reviews.driver_rating IS 'Optional rating 1-5 for the driver. NULL if no driver was assigned to the order.';


--
-- Name: COLUMN reviews.merchant_comment; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reviews.merchant_comment IS 'Free-text comment about the merchant. Written in user preferred language.';


--
-- Name: COLUMN reviews.is_visible; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reviews.is_visible IS 'Moderation gate (104): FALSE=new review awaiting Ops, TRUE=approved and public. Aggregates, summary RPC, and public reads all filter on this.';


--
-- Name: search_queries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.search_queries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    query text NOT NULL,
    normalized_query text NOT NULL,
    city text,
    category text,
    merchant_results integer DEFAULT 0 NOT NULL,
    item_results integer DEFAULT 0 NOT NULL,
    has_results boolean GENERATED ALWAYS AS (((merchant_results > 0) OR (item_results > 0))) STORED,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE search_queries; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.search_queries IS 'Search & Discovery MVP (095): per-query analytics log (query, normalized, city, result counts). RLS on with zero policies — service-role only. 180-day retention via prune_search_queries cron.';


--
-- Name: wallet_audit_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wallet_audit_log (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    balance_before numeric(10,2) NOT NULL,
    balance_after numeric(10,2) NOT NULL,
    change_amount numeric(10,2) NOT NULL,
    change_type text NOT NULL,
    reference_type text,
    reference_id uuid,
    changed_by uuid,
    reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT wallet_audit_log_change_type_check CHECK ((change_type = ANY (ARRAY['refund'::text, 'promo_credit'::text, 'admin_adjustment'::text, 'cancellation_fee'::text, 'withdrawal'::text, 'correction'::text]))),
    CONSTRAINT wallet_audit_log_reference_type_check CHECK ((reference_type = ANY (ARRAY['order'::text, 'promo'::text, 'admin'::text, 'withdrawal'::text, 'system'::text])))
);


--
-- Name: messages; Type: TABLE; Schema: realtime; Owner: -
--

CREATE TABLE realtime.messages (
    topic text NOT NULL,
    extension text NOT NULL,
    payload jsonb,
    event text,
    private boolean DEFAULT false,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    inserted_at timestamp without time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    binary_payload bytea,
    skip_broadcast boolean DEFAULT false NOT NULL
)
PARTITION BY RANGE (inserted_at);


--
-- Name: messages_2026_09_29; Type: TABLE; Schema: realtime; Owner: -
--

CREATE TABLE realtime.messages_2026_09_29 (
    topic text NOT NULL,
    extension text NOT NULL,
    payload jsonb,
    event text,
    private boolean DEFAULT false,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    inserted_at timestamp without time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    binary_payload bytea,
    skip_broadcast boolean DEFAULT false NOT NULL,
    CONSTRAINT messages_payload_exclusive CHECK (((payload IS NULL) OR (binary_payload IS NULL)))
);


--
-- Name: messages_2026_09_30; Type: TABLE; Schema: realtime; Owner: -
--

CREATE TABLE realtime.messages_2026_09_30 (
    topic text NOT NULL,
    extension text NOT NULL,
    payload jsonb,
    event text,
    private boolean DEFAULT false,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    inserted_at timestamp without time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    binary_payload bytea,
    skip_broadcast boolean DEFAULT false NOT NULL,
    CONSTRAINT messages_payload_exclusive CHECK (((payload IS NULL) OR (binary_payload IS NULL)))
);


--
-- Name: messages_2026_10_01; Type: TABLE; Schema: realtime; Owner: -
--

CREATE TABLE realtime.messages_2026_10_01 (
    topic text NOT NULL,
    extension text NOT NULL,
    payload jsonb,
    event text,
    private boolean DEFAULT false,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    inserted_at timestamp without time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    binary_payload bytea,
    skip_broadcast boolean DEFAULT false NOT NULL,
    CONSTRAINT messages_payload_exclusive CHECK (((payload IS NULL) OR (binary_payload IS NULL)))
);


--
-- Name: messages_2026_10_02; Type: TABLE; Schema: realtime; Owner: -
--

CREATE TABLE realtime.messages_2026_10_02 (
    topic text NOT NULL,
    extension text NOT NULL,
    payload jsonb,
    event text,
    private boolean DEFAULT false,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    inserted_at timestamp without time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    binary_payload bytea,
    skip_broadcast boolean DEFAULT false NOT NULL,
    CONSTRAINT messages_payload_exclusive CHECK (((payload IS NULL) OR (binary_payload IS NULL)))
);


--
-- Name: messages_2026_10_03; Type: TABLE; Schema: realtime; Owner: -
--

CREATE TABLE realtime.messages_2026_10_03 (
    topic text NOT NULL,
    extension text NOT NULL,
    payload jsonb,
    event text,
    private boolean DEFAULT false,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    inserted_at timestamp without time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    binary_payload bytea,
    skip_broadcast boolean DEFAULT false NOT NULL,
    CONSTRAINT messages_payload_exclusive CHECK (((payload IS NULL) OR (binary_payload IS NULL)))
);


--
-- Name: messages_2026_10_04; Type: TABLE; Schema: realtime; Owner: -
--

CREATE TABLE realtime.messages_2026_10_04 (
    topic text NOT NULL,
    extension text NOT NULL,
    payload jsonb,
    event text,
    private boolean DEFAULT false,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    inserted_at timestamp without time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    binary_payload bytea,
    skip_broadcast boolean DEFAULT false NOT NULL,
    CONSTRAINT messages_payload_exclusive CHECK (((payload IS NULL) OR (binary_payload IS NULL)))
);


--
-- Name: messages_2026_10_05; Type: TABLE; Schema: realtime; Owner: -
--

CREATE TABLE realtime.messages_2026_10_05 (
    topic text NOT NULL,
    extension text NOT NULL,
    payload jsonb,
    event text,
    private boolean DEFAULT false,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    inserted_at timestamp without time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    binary_payload bytea,
    skip_broadcast boolean DEFAULT false NOT NULL,
    CONSTRAINT messages_payload_exclusive CHECK (((payload IS NULL) OR (binary_payload IS NULL)))
);


--
-- Name: schema_migrations; Type: TABLE; Schema: realtime; Owner: -
--

CREATE TABLE realtime.schema_migrations (
    version bigint NOT NULL,
    inserted_at timestamp(0) without time zone
);


--
-- Name: subscription; Type: TABLE; Schema: realtime; Owner: -
--

CREATE TABLE realtime.subscription (
    id bigint NOT NULL,
    subscription_id uuid NOT NULL,
    entity regclass NOT NULL,
    filters realtime.user_defined_filter[] DEFAULT '{}'::realtime.user_defined_filter[] NOT NULL,
    claims jsonb NOT NULL,
    claims_role regrole GENERATED ALWAYS AS (realtime.to_regrole((claims ->> 'role'::text))) STORED NOT NULL,
    created_at timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    action_filter text DEFAULT '*'::text,
    selected_columns text[],
    CONSTRAINT subscription_action_filter_check CHECK ((action_filter = ANY (ARRAY['*'::text, 'INSERT'::text, 'UPDATE'::text, 'DELETE'::text])))
);


--
-- Name: subscription_id_seq; Type: SEQUENCE; Schema: realtime; Owner: -
--

ALTER TABLE realtime.subscription ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME realtime.subscription_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: buckets; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.buckets (
    id text NOT NULL,
    name text NOT NULL,
    owner uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    public boolean DEFAULT false,
    avif_autodetection boolean DEFAULT false,
    file_size_limit bigint,
    allowed_mime_types text[],
    owner_id text,
    type storage.buckettype DEFAULT 'STANDARD'::storage.buckettype NOT NULL,
    versioning_status text DEFAULT 'DISABLED'::text NOT NULL,
    lifecycle_configuration jsonb,
    lifecycle_configuration_generation uuid,
    CONSTRAINT buckets_lifecycle_configuration_pair_check CHECK (((lifecycle_configuration IS NULL) = (lifecycle_configuration_generation IS NULL))),
    CONSTRAINT buckets_lifecycle_configuration_shape_check CHECK (((lifecycle_configuration IS NULL) OR ((jsonb_typeof(lifecycle_configuration) = 'object'::text) AND (lifecycle_configuration ? 'rules'::text) AND
CASE
    WHEN (jsonb_typeof((lifecycle_configuration -> 'rules'::text)) = 'array'::text) THEN ((jsonb_array_length((lifecycle_configuration -> 'rules'::text)) >= 1) AND (jsonb_array_length((lifecycle_configuration -> 'rules'::text)) <= 1000))
    ELSE false
END))),
    CONSTRAINT buckets_lifecycle_configuration_standard_only_check CHECK (((type = 'STANDARD'::storage.buckettype) OR ((lifecycle_configuration IS NULL) AND (lifecycle_configuration_generation IS NULL)))),
    CONSTRAINT buckets_versioning_dark_check CHECK ((versioning_status = 'DISABLED'::text)),
    CONSTRAINT buckets_versioning_standard_only_check CHECK (((type = 'STANDARD'::storage.buckettype) OR (versioning_status = 'DISABLED'::text))),
    CONSTRAINT buckets_versioning_status_check CHECK ((versioning_status = ANY (ARRAY['DISABLED'::text, 'ENABLED'::text, 'SUSPENDED'::text])))
);


--
-- Name: COLUMN buckets.owner; Type: COMMENT; Schema: storage; Owner: -
--

COMMENT ON COLUMN storage.buckets.owner IS 'Field is deprecated, use owner_id instead';


--
-- Name: buckets_analytics; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.buckets_analytics (
    name text NOT NULL,
    type storage.buckettype DEFAULT 'ANALYTICS'::storage.buckettype NOT NULL,
    format text DEFAULT 'ICEBERG'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    deleted_at timestamp with time zone
);


--
-- Name: buckets_vectors; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.buckets_vectors (
    id text NOT NULL,
    type storage.buckettype DEFAULT 'VECTOR'::storage.buckettype NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: migrations; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.migrations (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    hash character varying(40) NOT NULL,
    executed_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: objects; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.objects (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    bucket_id text,
    name text,
    owner uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    last_accessed_at timestamp with time zone DEFAULT now(),
    metadata jsonb,
    path_tokens text[] GENERATED ALWAYS AS (string_to_array(name, '/'::text)) STORED,
    version text,
    owner_id text,
    user_metadata jsonb,
    archived_at timestamp with time zone,
    is_delete_marker boolean DEFAULT false NOT NULL,
    is_versioned boolean DEFAULT false NOT NULL
);


--
-- Name: COLUMN objects.owner; Type: COMMENT; Schema: storage; Owner: -
--

COMMENT ON COLUMN storage.objects.owner IS 'Field is deprecated, use owner_id instead';


--
-- Name: s3_multipart_uploads; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.s3_multipart_uploads (
    id text NOT NULL,
    in_progress_size bigint DEFAULT 0 NOT NULL,
    upload_signature text NOT NULL,
    bucket_id text NOT NULL,
    key text NOT NULL COLLATE pg_catalog."C",
    version text NOT NULL,
    owner_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    user_metadata jsonb,
    metadata jsonb
);


--
-- Name: s3_multipart_uploads_parts; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.s3_multipart_uploads_parts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    upload_id text NOT NULL,
    size bigint DEFAULT 0 NOT NULL,
    part_number integer NOT NULL,
    bucket_id text NOT NULL,
    key text NOT NULL COLLATE pg_catalog."C",
    etag text NOT NULL,
    owner_id text,
    version text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: vector_indexes; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.vector_indexes (
    id text DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL COLLATE pg_catalog."C",
    bucket_id text NOT NULL,
    data_type text NOT NULL,
    dimension integer NOT NULL,
    distance_metric text NOT NULL,
    metadata_configuration jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: schema_migrations; Type: TABLE; Schema: supabase_migrations; Owner: -
--

CREATE TABLE supabase_migrations.schema_migrations (
    version text NOT NULL,
    statements text[],
    name text
);


--
-- Name: messages_2026_09_29; Type: TABLE ATTACH; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.messages ATTACH PARTITION realtime.messages_2026_09_29 FOR VALUES FROM ('2026-09-29 00:00:00') TO ('2026-09-30 00:00:00');


--
-- Name: messages_2026_09_30; Type: TABLE ATTACH; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.messages ATTACH PARTITION realtime.messages_2026_09_30 FOR VALUES FROM ('2026-09-30 00:00:00') TO ('2026-10-01 00:00:00');


--
-- Name: messages_2026_10_01; Type: TABLE ATTACH; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.messages ATTACH PARTITION realtime.messages_2026_10_01 FOR VALUES FROM ('2026-10-01 00:00:00') TO ('2026-10-02 00:00:00');


--
-- Name: messages_2026_10_02; Type: TABLE ATTACH; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.messages ATTACH PARTITION realtime.messages_2026_10_02 FOR VALUES FROM ('2026-10-02 00:00:00') TO ('2026-10-03 00:00:00');


--
-- Name: messages_2026_10_03; Type: TABLE ATTACH; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.messages ATTACH PARTITION realtime.messages_2026_10_03 FOR VALUES FROM ('2026-10-03 00:00:00') TO ('2026-10-04 00:00:00');


--
-- Name: messages_2026_10_04; Type: TABLE ATTACH; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.messages ATTACH PARTITION realtime.messages_2026_10_04 FOR VALUES FROM ('2026-10-04 00:00:00') TO ('2026-10-05 00:00:00');


--
-- Name: messages_2026_10_05; Type: TABLE ATTACH; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.messages ATTACH PARTITION realtime.messages_2026_10_05 FOR VALUES FROM ('2026-10-05 00:00:00') TO ('2026-10-06 00:00:00');


--
-- Name: refresh_tokens id; Type: DEFAULT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.refresh_tokens ALTER COLUMN id SET DEFAULT nextval('auth.refresh_tokens_id_seq'::regclass);


--
-- Name: promoted_slot_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promoted_slot_events ALTER COLUMN id SET DEFAULT nextval('public.promoted_slot_events_id_seq'::regclass);


--
-- Name: mfa_amr_claims amr_id_pk; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_amr_claims
    ADD CONSTRAINT amr_id_pk PRIMARY KEY (id);


--
-- Name: audit_log_entries audit_log_entries_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.audit_log_entries
    ADD CONSTRAINT audit_log_entries_pkey PRIMARY KEY (id);


--
-- Name: custom_oauth_providers custom_oauth_providers_identifier_key; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.custom_oauth_providers
    ADD CONSTRAINT custom_oauth_providers_identifier_key UNIQUE (identifier);


--
-- Name: custom_oauth_providers custom_oauth_providers_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.custom_oauth_providers
    ADD CONSTRAINT custom_oauth_providers_pkey PRIMARY KEY (id);


--
-- Name: flow_state flow_state_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.flow_state
    ADD CONSTRAINT flow_state_pkey PRIMARY KEY (id);


--
-- Name: identities identities_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.identities
    ADD CONSTRAINT identities_pkey PRIMARY KEY (id);


--
-- Name: identities identities_provider_id_provider_unique; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.identities
    ADD CONSTRAINT identities_provider_id_provider_unique UNIQUE (provider_id, provider);


--
-- Name: instances instances_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.instances
    ADD CONSTRAINT instances_pkey PRIMARY KEY (id);


--
-- Name: mfa_amr_claims mfa_amr_claims_session_id_authentication_method_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_amr_claims
    ADD CONSTRAINT mfa_amr_claims_session_id_authentication_method_pkey UNIQUE (session_id, authentication_method);


--
-- Name: mfa_challenges mfa_challenges_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_challenges
    ADD CONSTRAINT mfa_challenges_pkey PRIMARY KEY (id);


--
-- Name: mfa_factors mfa_factors_last_challenged_at_key; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_factors
    ADD CONSTRAINT mfa_factors_last_challenged_at_key UNIQUE (last_challenged_at);


--
-- Name: mfa_factors mfa_factors_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_factors
    ADD CONSTRAINT mfa_factors_pkey PRIMARY KEY (id);


--
-- Name: mfa_recovery_code_sets mfa_recovery_code_sets_mfa_factor_id_key; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_recovery_code_sets
    ADD CONSTRAINT mfa_recovery_code_sets_mfa_factor_id_key UNIQUE (mfa_factor_id);


--
-- Name: mfa_recovery_code_sets mfa_recovery_code_sets_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_recovery_code_sets
    ADD CONSTRAINT mfa_recovery_code_sets_pkey PRIMARY KEY (id);


--
-- Name: mfa_recovery_code_sets mfa_recovery_code_sets_user_id_key; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_recovery_code_sets
    ADD CONSTRAINT mfa_recovery_code_sets_user_id_key UNIQUE (user_id);


--
-- Name: mfa_recovery_codes mfa_recovery_codes_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_recovery_codes
    ADD CONSTRAINT mfa_recovery_codes_pkey PRIMARY KEY (id);


--
-- Name: oauth_authorizations oauth_authorizations_authorization_code_key; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_authorizations
    ADD CONSTRAINT oauth_authorizations_authorization_code_key UNIQUE (authorization_code);


--
-- Name: oauth_authorizations oauth_authorizations_authorization_id_key; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_authorizations
    ADD CONSTRAINT oauth_authorizations_authorization_id_key UNIQUE (authorization_id);


--
-- Name: oauth_authorizations oauth_authorizations_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_authorizations
    ADD CONSTRAINT oauth_authorizations_pkey PRIMARY KEY (id);


--
-- Name: oauth_client_states oauth_client_states_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_client_states
    ADD CONSTRAINT oauth_client_states_pkey PRIMARY KEY (id);


--
-- Name: oauth_clients oauth_clients_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_clients
    ADD CONSTRAINT oauth_clients_pkey PRIMARY KEY (id);


--
-- Name: oauth_consents oauth_consents_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_consents
    ADD CONSTRAINT oauth_consents_pkey PRIMARY KEY (id);


--
-- Name: oauth_consents oauth_consents_user_client_unique; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_consents
    ADD CONSTRAINT oauth_consents_user_client_unique UNIQUE (user_id, client_id);


--
-- Name: one_time_tokens one_time_tokens_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.one_time_tokens
    ADD CONSTRAINT one_time_tokens_pkey PRIMARY KEY (id);


--
-- Name: refresh_tokens refresh_tokens_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.refresh_tokens
    ADD CONSTRAINT refresh_tokens_pkey PRIMARY KEY (id);


--
-- Name: refresh_tokens refresh_tokens_token_unique; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.refresh_tokens
    ADD CONSTRAINT refresh_tokens_token_unique UNIQUE (token);


--
-- Name: saml_providers saml_providers_entity_id_key; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.saml_providers
    ADD CONSTRAINT saml_providers_entity_id_key UNIQUE (entity_id);


--
-- Name: saml_providers saml_providers_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.saml_providers
    ADD CONSTRAINT saml_providers_pkey PRIMARY KEY (id);


--
-- Name: saml_relay_states saml_relay_states_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.saml_relay_states
    ADD CONSTRAINT saml_relay_states_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: scim_tokens scim_tokens_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.scim_tokens
    ADD CONSTRAINT scim_tokens_pkey PRIMARY KEY (id);


--
-- Name: scim_users scim_users_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.scim_users
    ADD CONSTRAINT scim_users_pkey PRIMARY KEY (id);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: sso_domains sso_domains_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.sso_domains
    ADD CONSTRAINT sso_domains_pkey PRIMARY KEY (id);


--
-- Name: sso_providers sso_providers_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.sso_providers
    ADD CONSTRAINT sso_providers_pkey PRIMARY KEY (id);


--
-- Name: users users_phone_key; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.users
    ADD CONSTRAINT users_phone_key UNIQUE (phone);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: webauthn_challenges webauthn_challenges_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.webauthn_challenges
    ADD CONSTRAINT webauthn_challenges_pkey PRIMARY KEY (id);


--
-- Name: webauthn_credentials webauthn_credentials_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.webauthn_credentials
    ADD CONSTRAINT webauthn_credentials_pkey PRIMARY KEY (id);


--
-- Name: addresses addresses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.addresses
    ADD CONSTRAINT addresses_pkey PRIMARY KEY (id);


--
-- Name: admin_kpi_cache admin_kpi_cache_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_kpi_cache
    ADD CONSTRAINT admin_kpi_cache_pkey PRIMARY KEY (key);


--
-- Name: admin_sessions admin_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_sessions
    ADD CONSTRAINT admin_sessions_pkey PRIMARY KEY (id);


--
-- Name: alert_incidents alert_incidents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alert_incidents
    ADD CONSTRAINT alert_incidents_pkey PRIMARY KEY (id);


--
-- Name: alert_rules alert_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alert_rules
    ADD CONSTRAINT alert_rules_pkey PRIMARY KEY (id);


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);


--
-- Name: cancellation_rules cancellation_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cancellation_rules
    ADD CONSTRAINT cancellation_rules_pkey PRIMARY KEY (id);


--
-- Name: categories categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (id);


--
-- Name: data_access_log data_access_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_access_log
    ADD CONSTRAINT data_access_log_pkey PRIMARY KEY (id);


--
-- Name: driver_documents driver_documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.driver_documents
    ADD CONSTRAINT driver_documents_pkey PRIMARY KEY (id);


--
-- Name: driver_earnings driver_earnings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.driver_earnings
    ADD CONSTRAINT driver_earnings_pkey PRIMARY KEY (id);


--
-- Name: driver_order_requests driver_order_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.driver_order_requests
    ADD CONSTRAINT driver_order_requests_pkey PRIMARY KEY (id);


--
-- Name: driver_settlement_earnings driver_settlement_earnings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.driver_settlement_earnings
    ADD CONSTRAINT driver_settlement_earnings_pkey PRIMARY KEY (settlement_id, earning_id);


--
-- Name: driver_settlements driver_settlements_driver_id_period_start_period_end_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.driver_settlements
    ADD CONSTRAINT driver_settlements_driver_id_period_start_period_end_key UNIQUE (driver_id, period_start, period_end);


--
-- Name: driver_settlements driver_settlements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.driver_settlements
    ADD CONSTRAINT driver_settlements_pkey PRIMARY KEY (id);


--
-- Name: driver_status_history driver_status_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.driver_status_history
    ADD CONSTRAINT driver_status_history_pkey PRIMARY KEY (id);


--
-- Name: drivers drivers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drivers
    ADD CONSTRAINT drivers_pkey PRIMARY KEY (id);


--
-- Name: favorite_items favorite_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.favorite_items
    ADD CONSTRAINT favorite_items_pkey PRIMARY KEY (id);


--
-- Name: favorites favorites_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.favorites
    ADD CONSTRAINT favorites_pkey PRIMARY KEY (id);


--
-- Name: item_option_choices item_option_choices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.item_option_choices
    ADD CONSTRAINT item_option_choices_pkey PRIMARY KEY (id);


--
-- Name: item_options item_options_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.item_options
    ADD CONSTRAINT item_options_pkey PRIMARY KEY (id);


--
-- Name: items items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.items
    ADD CONSTRAINT items_pkey PRIMARY KEY (id);


--
-- Name: loyalty_promo_log loyalty_promo_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loyalty_promo_log
    ADD CONSTRAINT loyalty_promo_log_pkey PRIMARY KEY (id);


--
-- Name: merchant_categories merchant_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_categories
    ADD CONSTRAINT merchant_categories_pkey PRIMARY KEY (code);


--
-- Name: merchant_payout_orders merchant_payout_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_payout_orders
    ADD CONSTRAINT merchant_payout_orders_pkey PRIMARY KEY (payout_id, order_id);


--
-- Name: merchant_payouts merchant_payouts_merchant_id_period_start_period_end_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_payouts
    ADD CONSTRAINT merchant_payouts_merchant_id_period_start_period_end_key UNIQUE (merchant_id, period_start, period_end);


--
-- Name: merchant_payouts merchant_payouts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_payouts
    ADD CONSTRAINT merchant_payouts_pkey PRIMARY KEY (id);


--
-- Name: merchants merchants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchants
    ADD CONSTRAINT merchants_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: operating_hours operating_hours_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operating_hours
    ADD CONSTRAINT operating_hours_pkey PRIMARY KEY (id);


--
-- Name: order_items order_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_pkey PRIMARY KEY (id);


--
-- Name: order_status_history order_status_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_status_history
    ADD CONSTRAINT order_status_history_pkey PRIMARY KEY (id);


--
-- Name: orders orders_idempotency_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_idempotency_key_key UNIQUE (idempotency_key);


--
-- Name: orders orders_order_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_order_number_key UNIQUE (order_number);


--
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (id);


--
-- Name: platform_config platform_config_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_config
    ADD CONSTRAINT platform_config_key_key UNIQUE (key);


--
-- Name: platform_config platform_config_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_config
    ADD CONSTRAINT platform_config_pkey PRIMARY KEY (id);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);


--
-- Name: promo_code_usage promo_code_usage_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promo_code_usage
    ADD CONSTRAINT promo_code_usage_pkey PRIMARY KEY (id);


--
-- Name: promo_codes promo_codes_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promo_codes
    ADD CONSTRAINT promo_codes_code_key UNIQUE (code);


--
-- Name: promo_codes promo_codes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promo_codes
    ADD CONSTRAINT promo_codes_pkey PRIMARY KEY (id);


--
-- Name: promoted_slot_events promoted_slot_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promoted_slot_events
    ADD CONSTRAINT promoted_slot_events_pkey PRIMARY KEY (id);


--
-- Name: promoted_slots promoted_slots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promoted_slots
    ADD CONSTRAINT promoted_slots_pkey PRIMARY KEY (id);


--
-- Name: reviews reviews_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT reviews_pkey PRIMARY KEY (id);


--
-- Name: search_queries search_queries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.search_queries
    ADD CONSTRAINT search_queries_pkey PRIMARY KEY (id);


--
-- Name: driver_documents unique_driver_doc_type; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.driver_documents
    ADD CONSTRAINT unique_driver_doc_type UNIQUE (driver_id, document_type);


--
-- Name: drivers unique_national_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drivers
    ADD CONSTRAINT unique_national_id UNIQUE (national_id);


--
-- Name: promo_code_usage unique_promo_order; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promo_code_usage
    ADD CONSTRAINT unique_promo_order UNIQUE (promo_code_id, order_id);


--
-- Name: favorite_items unique_user_item_favorite; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.favorite_items
    ADD CONSTRAINT unique_user_item_favorite UNIQUE (user_id, item_id);


--
-- Name: favorites unique_user_merchant_favorite; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.favorites
    ADD CONSTRAINT unique_user_merchant_favorite UNIQUE (user_id, merchant_id);


--
-- Name: drivers unique_vehicle_plate; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drivers
    ADD CONSTRAINT unique_vehicle_plate UNIQUE (vehicle_plate);


--
-- Name: wallet_audit_log wallet_audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_audit_log
    ADD CONSTRAINT wallet_audit_log_pkey PRIMARY KEY (id);


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (id, inserted_at);


--
-- Name: messages_2026_09_29 messages_2026_09_29_pkey; Type: CONSTRAINT; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.messages_2026_09_29
    ADD CONSTRAINT messages_2026_09_29_pkey PRIMARY KEY (id, inserted_at);


--
-- Name: messages_2026_09_30 messages_2026_09_30_pkey; Type: CONSTRAINT; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.messages_2026_09_30
    ADD CONSTRAINT messages_2026_09_30_pkey PRIMARY KEY (id, inserted_at);


--
-- Name: messages_2026_10_01 messages_2026_10_01_pkey; Type: CONSTRAINT; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.messages_2026_10_01
    ADD CONSTRAINT messages_2026_10_01_pkey PRIMARY KEY (id, inserted_at);


--
-- Name: messages_2026_10_02 messages_2026_10_02_pkey; Type: CONSTRAINT; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.messages_2026_10_02
    ADD CONSTRAINT messages_2026_10_02_pkey PRIMARY KEY (id, inserted_at);


--
-- Name: messages_2026_10_03 messages_2026_10_03_pkey; Type: CONSTRAINT; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.messages_2026_10_03
    ADD CONSTRAINT messages_2026_10_03_pkey PRIMARY KEY (id, inserted_at);


--
-- Name: messages_2026_10_04 messages_2026_10_04_pkey; Type: CONSTRAINT; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.messages_2026_10_04
    ADD CONSTRAINT messages_2026_10_04_pkey PRIMARY KEY (id, inserted_at);


--
-- Name: messages_2026_10_05 messages_2026_10_05_pkey; Type: CONSTRAINT; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.messages_2026_10_05
    ADD CONSTRAINT messages_2026_10_05_pkey PRIMARY KEY (id, inserted_at);


--
-- Name: messages messages_payload_exclusive; Type: CHECK CONSTRAINT; Schema: realtime; Owner: -
--

ALTER TABLE realtime.messages
    ADD CONSTRAINT messages_payload_exclusive CHECK (((payload IS NULL) OR (binary_payload IS NULL))) NOT VALID;


--
-- Name: subscription pk_subscription; Type: CONSTRAINT; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.subscription
    ADD CONSTRAINT pk_subscription PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: buckets_analytics buckets_analytics_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.buckets_analytics
    ADD CONSTRAINT buckets_analytics_pkey PRIMARY KEY (id);


--
-- Name: buckets buckets_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.buckets
    ADD CONSTRAINT buckets_pkey PRIMARY KEY (id);


--
-- Name: buckets_vectors buckets_vectors_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.buckets_vectors
    ADD CONSTRAINT buckets_vectors_pkey PRIMARY KEY (id);


--
-- Name: migrations migrations_name_key; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.migrations
    ADD CONSTRAINT migrations_name_key UNIQUE (name);


--
-- Name: migrations migrations_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.migrations
    ADD CONSTRAINT migrations_pkey PRIMARY KEY (id);


--
-- Name: objects objects_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.objects
    ADD CONSTRAINT objects_pkey PRIMARY KEY (id);


--
-- Name: s3_multipart_uploads_parts s3_multipart_uploads_parts_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.s3_multipart_uploads_parts
    ADD CONSTRAINT s3_multipart_uploads_parts_pkey PRIMARY KEY (id);


--
-- Name: s3_multipart_uploads s3_multipart_uploads_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.s3_multipart_uploads
    ADD CONSTRAINT s3_multipart_uploads_pkey PRIMARY KEY (id);


--
-- Name: vector_indexes vector_indexes_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.vector_indexes
    ADD CONSTRAINT vector_indexes_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: supabase_migrations; Owner: -
--

ALTER TABLE ONLY supabase_migrations.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: audit_logs_instance_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX audit_logs_instance_id_idx ON auth.audit_log_entries USING btree (instance_id);


--
-- Name: confirmation_token_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX confirmation_token_idx ON auth.users USING btree (confirmation_token) WHERE ((confirmation_token)::text !~ '^[0-9 ]*$'::text);


--
-- Name: custom_oauth_providers_created_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX custom_oauth_providers_created_at_idx ON auth.custom_oauth_providers USING btree (created_at);


--
-- Name: custom_oauth_providers_enabled_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX custom_oauth_providers_enabled_idx ON auth.custom_oauth_providers USING btree (enabled);


--
-- Name: custom_oauth_providers_identifier_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX custom_oauth_providers_identifier_idx ON auth.custom_oauth_providers USING btree (identifier);


--
-- Name: custom_oauth_providers_provider_type_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX custom_oauth_providers_provider_type_idx ON auth.custom_oauth_providers USING btree (provider_type);


--
-- Name: email_change_token_current_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX email_change_token_current_idx ON auth.users USING btree (email_change_token_current) WHERE ((email_change_token_current)::text !~ '^[0-9 ]*$'::text);


--
-- Name: email_change_token_new_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX email_change_token_new_idx ON auth.users USING btree (email_change_token_new) WHERE ((email_change_token_new)::text !~ '^[0-9 ]*$'::text);


--
-- Name: factor_id_created_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX factor_id_created_at_idx ON auth.mfa_factors USING btree (user_id, created_at);


--
-- Name: flow_state_created_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX flow_state_created_at_idx ON auth.flow_state USING btree (created_at DESC);


--
-- Name: identities_email_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX identities_email_idx ON auth.identities USING btree (email text_pattern_ops);


--
-- Name: INDEX identities_email_idx; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON INDEX auth.identities_email_idx IS 'Auth: Ensures indexed queries on the email column';


--
-- Name: identities_user_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX identities_user_id_idx ON auth.identities USING btree (user_id);


--
-- Name: idx_auth_code; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX idx_auth_code ON auth.flow_state USING btree (auth_code);


--
-- Name: idx_oauth_client_states_created_at; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX idx_oauth_client_states_created_at ON auth.oauth_client_states USING btree (created_at);


--
-- Name: idx_user_id_auth_method; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX idx_user_id_auth_method ON auth.flow_state USING btree (user_id, authentication_method);


--
-- Name: idx_users_created_at_desc; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX idx_users_created_at_desc ON auth.users USING btree (created_at DESC);


--
-- Name: idx_users_email; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX idx_users_email ON auth.users USING btree (email);


--
-- Name: idx_users_last_sign_in_at_desc; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX idx_users_last_sign_in_at_desc ON auth.users USING btree (last_sign_in_at DESC);


--
-- Name: idx_users_name; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX idx_users_name ON auth.users USING btree (((raw_user_meta_data ->> 'name'::text))) WHERE ((raw_user_meta_data ->> 'name'::text) IS NOT NULL);


--
-- Name: mfa_challenge_created_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX mfa_challenge_created_at_idx ON auth.mfa_challenges USING btree (created_at DESC);


--
-- Name: mfa_factors_user_friendly_name_unique; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX mfa_factors_user_friendly_name_unique ON auth.mfa_factors USING btree (friendly_name, user_id) WHERE (TRIM(BOTH FROM friendly_name) <> ''::text);


--
-- Name: mfa_factors_user_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX mfa_factors_user_id_idx ON auth.mfa_factors USING btree (user_id);


--
-- Name: mfa_recovery_codes_set_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX mfa_recovery_codes_set_id_idx ON auth.mfa_recovery_codes USING btree (mfa_recovery_code_set_id);


--
-- Name: oauth_auth_pending_exp_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX oauth_auth_pending_exp_idx ON auth.oauth_authorizations USING btree (expires_at) WHERE (status = 'pending'::auth.oauth_authorization_status);


--
-- Name: oauth_clients_deleted_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX oauth_clients_deleted_at_idx ON auth.oauth_clients USING btree (deleted_at);


--
-- Name: oauth_consents_active_client_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX oauth_consents_active_client_idx ON auth.oauth_consents USING btree (client_id) WHERE (revoked_at IS NULL);


--
-- Name: oauth_consents_active_user_client_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX oauth_consents_active_user_client_idx ON auth.oauth_consents USING btree (user_id, client_id) WHERE (revoked_at IS NULL);


--
-- Name: oauth_consents_user_order_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX oauth_consents_user_order_idx ON auth.oauth_consents USING btree (user_id, granted_at DESC);


--
-- Name: one_time_tokens_relates_to_hash_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX one_time_tokens_relates_to_hash_idx ON auth.one_time_tokens USING hash (relates_to);


--
-- Name: one_time_tokens_token_hash_hash_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX one_time_tokens_token_hash_hash_idx ON auth.one_time_tokens USING hash (token_hash);


--
-- Name: one_time_tokens_user_id_token_type_key; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX one_time_tokens_user_id_token_type_key ON auth.one_time_tokens USING btree (user_id, token_type);


--
-- Name: reauthentication_token_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX reauthentication_token_idx ON auth.users USING btree (reauthentication_token) WHERE ((reauthentication_token)::text !~ '^[0-9 ]*$'::text);


--
-- Name: recovery_token_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX recovery_token_idx ON auth.users USING btree (recovery_token) WHERE ((recovery_token)::text !~ '^[0-9 ]*$'::text);


--
-- Name: refresh_tokens_instance_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX refresh_tokens_instance_id_idx ON auth.refresh_tokens USING btree (instance_id);


--
-- Name: refresh_tokens_instance_id_user_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX refresh_tokens_instance_id_user_id_idx ON auth.refresh_tokens USING btree (instance_id, user_id);


--
-- Name: refresh_tokens_parent_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX refresh_tokens_parent_idx ON auth.refresh_tokens USING btree (parent);


--
-- Name: refresh_tokens_session_id_revoked_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX refresh_tokens_session_id_revoked_idx ON auth.refresh_tokens USING btree (session_id, revoked);


--
-- Name: refresh_tokens_updated_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX refresh_tokens_updated_at_idx ON auth.refresh_tokens USING btree (updated_at DESC);


--
-- Name: saml_providers_sso_provider_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX saml_providers_sso_provider_id_idx ON auth.saml_providers USING btree (sso_provider_id);


--
-- Name: saml_relay_states_created_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX saml_relay_states_created_at_idx ON auth.saml_relay_states USING btree (created_at DESC);


--
-- Name: saml_relay_states_for_email_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX saml_relay_states_for_email_idx ON auth.saml_relay_states USING btree (for_email);


--
-- Name: saml_relay_states_sso_provider_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX saml_relay_states_sso_provider_id_idx ON auth.saml_relay_states USING btree (sso_provider_id);


--
-- Name: scim_tokens_expires_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX scim_tokens_expires_at_idx ON auth.scim_tokens USING btree (expires_at);


--
-- Name: scim_tokens_revoked_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX scim_tokens_revoked_at_idx ON auth.scim_tokens USING btree (revoked_at);


--
-- Name: scim_tokens_sso_provider_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX scim_tokens_sso_provider_id_idx ON auth.scim_tokens USING btree (sso_provider_id);


--
-- Name: scim_tokens_token_hash_key; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX scim_tokens_token_hash_key ON auth.scim_tokens USING btree (token_hash);


--
-- Name: scim_users_created_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX scim_users_created_at_idx ON auth.scim_users USING btree (sso_provider_id, created_at, id) WHERE (deleted_at IS NULL);


--
-- Name: scim_users_deleted_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX scim_users_deleted_at_idx ON auth.scim_users USING btree (deleted_at);


--
-- Name: scim_users_external_id_key; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX scim_users_external_id_key ON auth.scim_users USING btree (sso_provider_id, external_id) WHERE ((external_id IS NOT NULL) AND (deleted_at IS NULL));


--
-- Name: scim_users_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX scim_users_id_idx ON auth.scim_users USING btree (sso_provider_id, id) WHERE (deleted_at IS NULL);


--
-- Name: scim_users_sso_provider_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX scim_users_sso_provider_id_idx ON auth.scim_users USING btree (sso_provider_id);


--
-- Name: scim_users_updated_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX scim_users_updated_at_idx ON auth.scim_users USING btree (sso_provider_id, updated_at, id) WHERE (deleted_at IS NULL);


--
-- Name: scim_users_user_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX scim_users_user_id_idx ON auth.scim_users USING btree (user_id);


--
-- Name: scim_users_user_name_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX scim_users_user_name_idx ON auth.scim_users USING btree (sso_provider_id, user_name COLLATE "C", id) WHERE (deleted_at IS NULL);


--
-- Name: scim_users_user_name_key; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX scim_users_user_name_key ON auth.scim_users USING btree (sso_provider_id, user_name) WHERE (deleted_at IS NULL);


--
-- Name: sessions_not_after_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX sessions_not_after_idx ON auth.sessions USING btree (not_after DESC);


--
-- Name: sessions_oauth_client_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX sessions_oauth_client_id_idx ON auth.sessions USING btree (oauth_client_id);


--
-- Name: sessions_user_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX sessions_user_id_idx ON auth.sessions USING btree (user_id);


--
-- Name: sso_domains_domain_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX sso_domains_domain_idx ON auth.sso_domains USING btree (lower(domain));


--
-- Name: sso_domains_sso_provider_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX sso_domains_sso_provider_id_idx ON auth.sso_domains USING btree (sso_provider_id);


--
-- Name: sso_providers_resource_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX sso_providers_resource_id_idx ON auth.sso_providers USING btree (lower(resource_id));


--
-- Name: sso_providers_resource_id_pattern_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX sso_providers_resource_id_pattern_idx ON auth.sso_providers USING btree (resource_id text_pattern_ops);


--
-- Name: unique_phone_factor_per_user; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX unique_phone_factor_per_user ON auth.mfa_factors USING btree (user_id, phone);


--
-- Name: user_id_created_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX user_id_created_at_idx ON auth.sessions USING btree (user_id, created_at);


--
-- Name: users_email_partial_key; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX users_email_partial_key ON auth.users USING btree (email) WHERE (is_sso_user = false);


--
-- Name: INDEX users_email_partial_key; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON INDEX auth.users_email_partial_key IS 'Auth: A partial unique index that applies only when is_sso_user is false';


--
-- Name: users_instance_id_email_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX users_instance_id_email_idx ON auth.users USING btree (instance_id, lower((email)::text));


--
-- Name: users_instance_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX users_instance_id_idx ON auth.users USING btree (instance_id);


--
-- Name: users_is_anonymous_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX users_is_anonymous_idx ON auth.users USING btree (is_anonymous);


--
-- Name: webauthn_challenges_expires_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX webauthn_challenges_expires_at_idx ON auth.webauthn_challenges USING btree (expires_at);


--
-- Name: webauthn_challenges_user_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX webauthn_challenges_user_id_idx ON auth.webauthn_challenges USING btree (user_id);


--
-- Name: webauthn_credentials_credential_id_key; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX webauthn_credentials_credential_id_key ON auth.webauthn_credentials USING btree (credential_id);


--
-- Name: webauthn_credentials_user_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX webauthn_credentials_user_id_idx ON auth.webauthn_credentials USING btree (user_id);


--
-- Name: idx_addresses_city_area; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_addresses_city_area ON public.addresses USING btree (city, area) WHERE (city IS NOT NULL);


--
-- Name: idx_addresses_one_default_per_user; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_addresses_one_default_per_user ON public.addresses USING btree (user_id) WHERE (is_default = true);


--
-- Name: idx_addresses_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_addresses_user_id ON public.addresses USING btree (user_id);


--
-- Name: idx_admin_sessions_admin_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_admin_sessions_admin_active ON public.admin_sessions USING btree (admin_id, created_at DESC) WHERE (invalidated_at IS NULL);


--
-- Name: idx_admin_sessions_admin_all; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_admin_sessions_admin_all ON public.admin_sessions USING btree (admin_id, created_at DESC);


--
-- Name: idx_admin_sessions_expired; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_admin_sessions_expired ON public.admin_sessions USING btree (expires_at) WHERE (invalidated_at IS NULL);


--
-- Name: idx_admin_sessions_token; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_admin_sessions_token ON public.admin_sessions USING btree (session_token) WHERE (invalidated_at IS NULL);


--
-- Name: idx_alert_incidents_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_alert_incidents_active ON public.alert_incidents USING btree (status, triggered_at DESC) WHERE (status <> 'resolved'::text);


--
-- Name: idx_alert_rules_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_alert_rules_active ON public.alert_rules USING btree (severity, is_active) WHERE (is_active = true);


--
-- Name: idx_audit_logs_action; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_action ON public.audit_logs USING btree (action, created_at DESC);


--
-- Name: idx_audit_logs_admin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_admin ON public.audit_logs USING btree (admin_id, created_at DESC);


--
-- Name: idx_audit_logs_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_created_at ON public.audit_logs USING btree (created_at DESC);


--
-- Name: idx_audit_logs_resource; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_resource ON public.audit_logs USING btree (resource_type, resource_id);


--
-- Name: idx_cancellation_rules_status_initiator; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_cancellation_rules_status_initiator ON public.cancellation_rules USING btree (order_status, initiator);


--
-- Name: idx_categories_merchant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_categories_merchant ON public.categories USING btree (merchant_id, sort_order);


--
-- Name: idx_data_access_log_admin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_data_access_log_admin ON public.data_access_log USING btree (admin_id, created_at DESC);


--
-- Name: idx_data_access_log_field; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_data_access_log_field ON public.data_access_log USING btree (field_name, created_at DESC) WHERE (field_name = ANY (ARRAY['national_id'::text, 'phone'::text, 'address'::text, 'wallet_balance'::text, 'email'::text]));


--
-- Name: idx_data_access_log_flagged; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_data_access_log_flagged ON public.data_access_log USING btree (created_at DESC) WHERE (is_flagged = true);


--
-- Name: idx_data_access_log_ip; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_data_access_log_ip ON public.data_access_log USING btree (ip_address, created_at DESC) WHERE (ip_address IS NOT NULL);


--
-- Name: idx_data_access_log_resource; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_data_access_log_resource ON public.data_access_log USING btree (resource_type, resource_id, created_at DESC);


--
-- Name: idx_driver_documents_driver; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_driver_documents_driver ON public.driver_documents USING btree (driver_id);


--
-- Name: idx_driver_documents_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_driver_documents_status ON public.driver_documents USING btree (status) WHERE (status = 'pending'::text);


--
-- Name: idx_driver_earnings_driver_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_driver_earnings_driver_created ON public.driver_earnings USING btree (driver_id, created_at DESC);


--
-- Name: idx_driver_earnings_order_driver; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_driver_earnings_order_driver ON public.driver_earnings USING btree (order_id, driver_id);


--
-- Name: idx_driver_earnings_payout_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_driver_earnings_payout_status ON public.driver_earnings USING btree (payout_status) WHERE (payout_status = 'pending'::text);


--
-- Name: idx_driver_order_requests_driver_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_driver_order_requests_driver_status ON public.driver_order_requests USING btree (driver_id, status);


--
-- Name: idx_driver_order_requests_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_driver_order_requests_order ON public.driver_order_requests USING btree (order_id);


--
-- Name: idx_driver_order_requests_status_sent_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_driver_order_requests_status_sent_at ON public.driver_order_requests USING btree (status, sent_at) WHERE (status = 'pending'::text);


--
-- Name: idx_driver_settlement_earnings_earning; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_driver_settlement_earnings_earning ON public.driver_settlement_earnings USING btree (earning_id);


--
-- Name: idx_driver_settlements_driver_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_driver_settlements_driver_status ON public.driver_settlements USING btree (driver_id, status);


--
-- Name: idx_driver_settlements_period; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_driver_settlements_period ON public.driver_settlements USING btree (period_start, period_end);


--
-- Name: idx_driver_settlements_status_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_driver_settlements_status_created ON public.driver_settlements USING btree (status, created_at);


--
-- Name: idx_driver_status_history_driver; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_driver_status_history_driver ON public.driver_status_history USING btree (driver_id, changed_at DESC);


--
-- Name: idx_drivers_last_location; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_drivers_last_location ON public.drivers USING btree (last_location_at DESC) WHERE (is_online = true);


--
-- Name: idx_drivers_location_lat; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_drivers_location_lat ON public.drivers USING btree (current_lat) WHERE (current_lat IS NOT NULL);


--
-- Name: idx_drivers_location_lng; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_drivers_location_lng ON public.drivers USING btree (current_lng) WHERE (current_lng IS NOT NULL);


--
-- Name: idx_drivers_national_id_encrypted; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_drivers_national_id_encrypted ON public.drivers USING btree (national_id_encrypted) WHERE (national_id_encrypted IS NOT NULL);


--
-- Name: idx_drivers_online_verified_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_drivers_online_verified_active ON public.drivers USING btree (is_online, is_verified, is_active) WHERE ((is_online = true) AND (is_verified = true) AND (is_active = true));


--
-- Name: idx_drivers_verification_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_drivers_verification_status ON public.drivers USING btree (verification_status) WHERE (verification_status = ANY (ARRAY['pending'::text, 'under_review'::text]));


--
-- Name: idx_favorite_items_item; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_favorite_items_item ON public.favorite_items USING btree (item_id);


--
-- Name: idx_favorite_items_merchant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_favorite_items_merchant ON public.favorite_items USING btree (merchant_id);


--
-- Name: idx_favorite_items_user_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_favorite_items_user_created ON public.favorite_items USING btree (user_id, created_at DESC);


--
-- Name: idx_favorites_merchant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_favorites_merchant ON public.favorites USING btree (merchant_id);


--
-- Name: idx_favorites_user_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_favorites_user_created ON public.favorites USING btree (user_id, created_at DESC);


--
-- Name: idx_item_option_choices_option; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_item_option_choices_option ON public.item_option_choices USING btree (option_id, sort_order);


--
-- Name: idx_item_options_item; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_item_options_item ON public.item_options USING btree (item_id, sort_order);


--
-- Name: idx_items_desc_ar_norm_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_items_desc_ar_norm_trgm ON public.items USING gin (public.normalize_search_text(description_ar) public.gin_trgm_ops);


--
-- Name: idx_items_desc_en_norm_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_items_desc_en_norm_trgm ON public.items USING gin (public.normalize_search_text(description_en) public.gin_trgm_ops);


--
-- Name: idx_items_description_ar_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_items_description_ar_trgm ON public.items USING gin (description_ar public.gin_trgm_ops) WHERE (description_ar IS NOT NULL);


--
-- Name: idx_items_description_en_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_items_description_en_trgm ON public.items USING gin (description_en public.gin_trgm_ops) WHERE (description_en IS NOT NULL);


--
-- Name: idx_items_merchant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_items_merchant ON public.items USING btree (merchant_id) WHERE (is_available = true);


--
-- Name: idx_items_merchant_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_items_merchant_category ON public.items USING btree (merchant_id, category_id, is_available);


--
-- Name: idx_items_name_ar_norm_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_items_name_ar_norm_trgm ON public.items USING gin (public.normalize_search_text(name_ar) public.gin_trgm_ops);


--
-- Name: idx_items_name_ar_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_items_name_ar_trgm ON public.items USING gin (name_ar public.gin_trgm_ops);


--
-- Name: INDEX idx_items_name_ar_trgm; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_items_name_ar_trgm IS 'P1E-02: GIN trigram index for Arabic item name search. Used by search screen.';


--
-- Name: idx_items_name_en_norm_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_items_name_en_norm_trgm ON public.items USING gin (public.normalize_search_text(name_en) public.gin_trgm_ops);


--
-- Name: idx_items_name_en_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_items_name_en_trgm ON public.items USING gin (name_en public.gin_trgm_ops);


--
-- Name: INDEX idx_items_name_en_trgm; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_items_name_en_trgm IS 'P1E-02: GIN trigram index for English item name search. Used by search screen.';


--
-- Name: idx_loyalty_promo_log_customer_issued; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_loyalty_promo_log_customer_issued ON public.loyalty_promo_log USING btree (customer_id, issued_at DESC);


--
-- Name: idx_loyalty_promo_log_customer_promo; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_loyalty_promo_log_customer_promo ON public.loyalty_promo_log USING btree (customer_id, promo_code_id);


--
-- Name: idx_merchant_payout_orders_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_merchant_payout_orders_order ON public.merchant_payout_orders USING btree (order_id);


--
-- Name: idx_merchant_payouts_merchant_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_merchant_payouts_merchant_status ON public.merchant_payouts USING btree (merchant_id, status);


--
-- Name: idx_merchant_payouts_period; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_merchant_payouts_period ON public.merchant_payouts USING btree (period_start, period_end);


--
-- Name: idx_merchant_payouts_status_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_merchant_payouts_status_created ON public.merchant_payouts USING btree (status, created_at);


--
-- Name: idx_merchants_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_merchants_active ON public.merchants USING btree (is_active) WHERE (is_active = true);


--
-- Name: idx_merchants_category_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_merchants_category_active ON public.merchants USING btree (category) WHERE (is_active = true);


--
-- Name: idx_merchants_city_area; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_merchants_city_area ON public.merchants USING btree (city, area) WHERE (is_active = true);


--
-- Name: idx_merchants_city_category_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_merchants_city_category_active ON public.merchants USING btree (city, category, is_active);


--
-- Name: idx_merchants_location_lat; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_merchants_location_lat ON public.merchants USING btree (lat) WHERE (lat IS NOT NULL);


--
-- Name: INDEX idx_merchants_location_lat; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_merchants_location_lat IS 'Btree index for proximity-based merchant queries. Used with ST_DWithin in get-merchant-feed.';


--
-- Name: idx_merchants_location_lng; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_merchants_location_lng ON public.merchants USING btree (lng) WHERE (lng IS NOT NULL);


--
-- Name: idx_merchants_name_ar_norm_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_merchants_name_ar_norm_trgm ON public.merchants USING gin (public.normalize_search_text(name_ar) public.gin_trgm_ops);


--
-- Name: idx_merchants_name_ar_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_merchants_name_ar_trgm ON public.merchants USING gin (name_ar public.gin_trgm_ops);


--
-- Name: INDEX idx_merchants_name_ar_trgm; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_merchants_name_ar_trgm IS 'P1E-01: GIN trigram index for Arabic merchant name search. Separate from English for optimal query plans. See RED-24.';


--
-- Name: idx_merchants_name_en_norm_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_merchants_name_en_norm_trgm ON public.merchants USING gin (public.normalize_search_text(name_en) public.gin_trgm_ops);


--
-- Name: idx_merchants_name_en_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_merchants_name_en_trgm ON public.merchants USING gin (name_en public.gin_trgm_ops);


--
-- Name: INDEX idx_merchants_name_en_trgm; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_merchants_name_en_trgm IS 'P1E-01: GIN trigram index for English merchant name search. Separate from English for optimal query plans. See RED-24.';


--
-- Name: idx_merchants_open_status_city_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_merchants_open_status_city_category ON public.merchants_with_open_status USING btree (city, category);


--
-- Name: idx_merchants_open_status_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_merchants_open_status_id ON public.merchants_with_open_status USING btree (id);


--
-- Name: idx_merchants_open_status_open; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_merchants_open_status_open ON public.merchants_with_open_status USING btree (is_currently_open) WHERE (is_currently_open = true);


--
-- Name: idx_notifications_reference_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notifications_reference_id ON public.notifications USING btree (reference_id) WHERE (reference_id IS NOT NULL);


--
-- Name: idx_notifications_unread; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notifications_unread ON public.notifications USING btree (user_id) WHERE (is_read = false);


--
-- Name: idx_notifications_user_read_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notifications_user_read_created ON public.notifications USING btree (user_id, is_read, created_at DESC);


--
-- Name: idx_operating_hours_merchant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_operating_hours_merchant ON public.operating_hours USING btree (merchant_id);


--
-- Name: idx_operating_hours_merchant_day; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_operating_hours_merchant_day ON public.operating_hours USING btree (merchant_id, day_of_week);


--
-- Name: idx_order_items_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_order_items_order ON public.order_items USING btree (order_id);


--
-- Name: idx_order_status_history_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_order_status_history_order ON public.order_status_history USING btree (order_id, created_at DESC);


--
-- Name: idx_orders_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_active ON public.orders USING btree (status, created_at DESC) WHERE (status <> ALL (ARRAY['delivered'::text, 'cancelled'::text]));


--
-- Name: idx_orders_customer_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_customer_created ON public.orders USING btree (customer_id, created_at DESC);


--
-- Name: idx_orders_driver_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_driver_created ON public.orders USING btree (driver_id, created_at DESC) WHERE (driver_id IS NOT NULL);


--
-- Name: idx_orders_idempotency; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_idempotency ON public.orders USING btree (idempotency_key) WHERE (idempotency_key IS NOT NULL);


--
-- Name: idx_orders_merchant_status_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_merchant_status_created ON public.orders USING btree (merchant_id, status, created_at DESC);


--
-- Name: idx_orders_payment_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_payment_status ON public.orders USING btree (payment_status) WHERE (payment_status = ANY (ARRAY['pending'::text, 'pending_cash'::text, 'pending_refund'::text, 'refund_failed'::text]));


--
-- Name: idx_orders_paymob_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_orders_paymob_order_id ON public.orders USING btree (paymob_order_id) WHERE (paymob_order_id IS NOT NULL);


--
-- Name: idx_orders_refund_sweep; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_refund_sweep ON public.orders USING btree (refund_status, created_at) WHERE (refund_status = ANY (ARRAY['pending_refund'::text, 'refund_failed'::text]));


--
-- Name: idx_profiles_phone; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_profiles_phone ON public.profiles USING btree (phone) WHERE (phone IS NOT NULL);


--
-- Name: idx_profiles_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_profiles_role ON public.profiles USING btree (role);


--
-- Name: idx_promo_codes_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_promo_codes_active ON public.promo_codes USING btree (code) WHERE (is_active = true);


--
-- Name: idx_promo_codes_city; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_promo_codes_city ON public.promo_codes USING btree (city) WHERE (city IS NOT NULL);


--
-- Name: idx_promo_codes_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_promo_codes_deleted_at ON public.promo_codes USING btree (deleted_at) WHERE (deleted_at IS NULL);


--
-- Name: idx_promo_codes_merchant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_promo_codes_merchant ON public.promo_codes USING btree (merchant_id) WHERE (merchant_id IS NOT NULL);


--
-- Name: idx_promo_usage_code; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_promo_usage_code ON public.promo_code_usage USING btree (promo_code_id, used_at DESC);


--
-- Name: idx_promo_usage_fraud; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_promo_usage_fraud ON public.promo_code_usage USING btree (promo_code_id, ip_address, used_at DESC) WHERE (ip_address IS NOT NULL);


--
-- Name: idx_promo_usage_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_promo_usage_user ON public.promo_code_usage USING btree (user_id, used_at DESC);


--
-- Name: idx_promo_usage_user_code; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_promo_usage_user_code ON public.promo_code_usage USING btree (user_id, promo_code_id);


--
-- Name: idx_promoted_slots_active_city; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_promoted_slots_active_city ON public.promoted_slots USING btree (city, slot_type, is_active) WHERE (is_active = true);


--
-- Name: idx_promoted_slots_category_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_promoted_slots_category_active ON public.promoted_slots USING btree (category) WHERE (is_active = true);


--
-- Name: idx_promoted_slots_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_promoted_slots_deleted_at ON public.promoted_slots USING btree (deleted_at) WHERE (deleted_at IS NULL);


--
-- Name: idx_promoted_slots_merchant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_promoted_slots_merchant ON public.promoted_slots USING btree (merchant_id, created_at DESC);


--
-- Name: idx_reviews_customer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reviews_customer ON public.reviews USING btree (customer_id, created_at DESC);


--
-- Name: idx_reviews_driver_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reviews_driver_created ON public.reviews USING btree (driver_id, created_at DESC) WHERE (driver_id IS NOT NULL);


--
-- Name: idx_reviews_merchant_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reviews_merchant_created ON public.reviews USING btree (merchant_id, created_at DESC);


--
-- Name: idx_reviews_merchant_visible; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reviews_merchant_visible ON public.reviews USING btree (merchant_id, created_at DESC) WHERE (is_visible = true);


--
-- Name: idx_reviews_order; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_reviews_order ON public.reviews USING btree (order_id);


--
-- Name: idx_search_queries_trend; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_search_queries_trend ON public.search_queries USING btree (normalized_query, city, created_at DESC);


--
-- Name: idx_search_queries_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_search_queries_user ON public.search_queries USING btree (user_id, created_at DESC);


--
-- Name: idx_search_queries_zero; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_search_queries_zero ON public.search_queries USING btree (created_at DESC) WHERE (NOT has_results);


--
-- Name: idx_slot_events_occurred_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_slot_events_occurred_at ON public.promoted_slot_events USING btree (occurred_at);


--
-- Name: idx_slot_events_slot_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_slot_events_slot_time ON public.promoted_slot_events USING btree (slot_id, occurred_at DESC);


--
-- Name: idx_slot_events_type_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_slot_events_type_time ON public.promoted_slot_events USING btree (event_type, occurred_at DESC);


--
-- Name: idx_wallet_audit_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wallet_audit_type ON public.wallet_audit_log USING btree (change_type, created_at DESC) WHERE (change_type = ANY (ARRAY['admin_adjustment'::text, 'correction'::text]));


--
-- Name: idx_wallet_audit_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wallet_audit_user ON public.wallet_audit_log USING btree (user_id, created_at DESC);


--
-- Name: ix_realtime_subscription_entity; Type: INDEX; Schema: realtime; Owner: -
--

CREATE INDEX ix_realtime_subscription_entity ON realtime.subscription USING btree (entity);


--
-- Name: messages_inserted_at_topic_index; Type: INDEX; Schema: realtime; Owner: -
--

CREATE INDEX messages_inserted_at_topic_index ON ONLY realtime.messages USING btree (inserted_at DESC, topic) WHERE ((extension = 'broadcast'::text) AND (private IS TRUE));


--
-- Name: messages_2026_09_29_inserted_at_topic_idx; Type: INDEX; Schema: realtime; Owner: -
--

CREATE INDEX messages_2026_09_29_inserted_at_topic_idx ON realtime.messages_2026_09_29 USING btree (inserted_at DESC, topic) WHERE ((extension = 'broadcast'::text) AND (private IS TRUE));


--
-- Name: messages_2026_09_30_inserted_at_topic_idx; Type: INDEX; Schema: realtime; Owner: -
--

CREATE INDEX messages_2026_09_30_inserted_at_topic_idx ON realtime.messages_2026_09_30 USING btree (inserted_at DESC, topic) WHERE ((extension = 'broadcast'::text) AND (private IS TRUE));


--
-- Name: messages_2026_10_01_inserted_at_topic_idx; Type: INDEX; Schema: realtime; Owner: -
--

CREATE INDEX messages_2026_10_01_inserted_at_topic_idx ON realtime.messages_2026_10_01 USING btree (inserted_at DESC, topic) WHERE ((extension = 'broadcast'::text) AND (private IS TRUE));


--
-- Name: messages_2026_10_02_inserted_at_topic_idx; Type: INDEX; Schema: realtime; Owner: -
--

CREATE INDEX messages_2026_10_02_inserted_at_topic_idx ON realtime.messages_2026_10_02 USING btree (inserted_at DESC, topic) WHERE ((extension = 'broadcast'::text) AND (private IS TRUE));


--
-- Name: messages_2026_10_03_inserted_at_topic_idx; Type: INDEX; Schema: realtime; Owner: -
--

CREATE INDEX messages_2026_10_03_inserted_at_topic_idx ON realtime.messages_2026_10_03 USING btree (inserted_at DESC, topic) WHERE ((extension = 'broadcast'::text) AND (private IS TRUE));


--
-- Name: messages_2026_10_04_inserted_at_topic_idx; Type: INDEX; Schema: realtime; Owner: -
--

CREATE INDEX messages_2026_10_04_inserted_at_topic_idx ON realtime.messages_2026_10_04 USING btree (inserted_at DESC, topic) WHERE ((extension = 'broadcast'::text) AND (private IS TRUE));


--
-- Name: messages_2026_10_05_inserted_at_topic_idx; Type: INDEX; Schema: realtime; Owner: -
--

CREATE INDEX messages_2026_10_05_inserted_at_topic_idx ON realtime.messages_2026_10_05 USING btree (inserted_at DESC, topic) WHERE ((extension = 'broadcast'::text) AND (private IS TRUE));


--
-- Name: subscription_subscription_id_entity_filters_action_filter_selec; Type: INDEX; Schema: realtime; Owner: -
--

CREATE UNIQUE INDEX subscription_subscription_id_entity_filters_action_filter_selec ON realtime.subscription USING btree (subscription_id, entity, filters, action_filter, COALESCE(selected_columns, '{}'::text[]));


--
-- Name: bname; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX bname ON storage.buckets USING btree (name);


--
-- Name: buckets_analytics_unique_name_idx; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX buckets_analytics_unique_name_idx ON storage.buckets_analytics USING btree (name) WHERE (deleted_at IS NULL);


--
-- Name: idx_multipart_uploads_list; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX idx_multipart_uploads_list ON storage.s3_multipart_uploads USING btree (bucket_id, key, created_at);


--
-- Name: idx_objects_bucket_id_name; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX idx_objects_bucket_id_name ON storage.objects USING btree (bucket_id, name COLLATE "C");


--
-- Name: idx_objects_bucket_id_name_lower; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX idx_objects_bucket_id_name_lower ON storage.objects USING btree (bucket_id, lower(name) COLLATE "C");


--
-- Name: idx_objects_current_version; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX idx_objects_current_version ON storage.objects USING btree (bucket_id, name COLLATE "C") WHERE (archived_at IS NULL);


--
-- Name: idx_objects_delete_markers; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX idx_objects_delete_markers ON storage.objects USING btree (bucket_id, name COLLATE "C") WHERE is_delete_marker;


--
-- Name: idx_objects_null_version; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX idx_objects_null_version ON storage.objects USING btree (bucket_id, name COLLATE "C") WHERE (NOT is_versioned);


--
-- Name: name_prefix_search; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX name_prefix_search ON storage.objects USING btree (name text_pattern_ops);


--
-- Name: objects_bucket_id_name_version_key; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX objects_bucket_id_name_version_key ON storage.objects USING btree (bucket_id, name COLLATE "C", version) NULLS NOT DISTINCT;


--
-- Name: vector_indexes_name_bucket_id_idx; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX vector_indexes_name_bucket_id_idx ON storage.vector_indexes USING btree (name, bucket_id);


--
-- Name: messages_2026_09_29_inserted_at_topic_idx; Type: INDEX ATTACH; Schema: realtime; Owner: -
--

ALTER INDEX realtime.messages_inserted_at_topic_index ATTACH PARTITION realtime.messages_2026_09_29_inserted_at_topic_idx;


--
-- Name: messages_2026_09_29_pkey; Type: INDEX ATTACH; Schema: realtime; Owner: -
--

ALTER INDEX realtime.messages_pkey ATTACH PARTITION realtime.messages_2026_09_29_pkey;


--
-- Name: messages_2026_09_30_inserted_at_topic_idx; Type: INDEX ATTACH; Schema: realtime; Owner: -
--

ALTER INDEX realtime.messages_inserted_at_topic_index ATTACH PARTITION realtime.messages_2026_09_30_inserted_at_topic_idx;


--
-- Name: messages_2026_09_30_pkey; Type: INDEX ATTACH; Schema: realtime; Owner: -
--

ALTER INDEX realtime.messages_pkey ATTACH PARTITION realtime.messages_2026_09_30_pkey;


--
-- Name: messages_2026_10_01_inserted_at_topic_idx; Type: INDEX ATTACH; Schema: realtime; Owner: -
--

ALTER INDEX realtime.messages_inserted_at_topic_index ATTACH PARTITION realtime.messages_2026_10_01_inserted_at_topic_idx;


--
-- Name: messages_2026_10_01_pkey; Type: INDEX ATTACH; Schema: realtime; Owner: -
--

ALTER INDEX realtime.messages_pkey ATTACH PARTITION realtime.messages_2026_10_01_pkey;


--
-- Name: messages_2026_10_02_inserted_at_topic_idx; Type: INDEX ATTACH; Schema: realtime; Owner: -
--

ALTER INDEX realtime.messages_inserted_at_topic_index ATTACH PARTITION realtime.messages_2026_10_02_inserted_at_topic_idx;


--
-- Name: messages_2026_10_02_pkey; Type: INDEX ATTACH; Schema: realtime; Owner: -
--

ALTER INDEX realtime.messages_pkey ATTACH PARTITION realtime.messages_2026_10_02_pkey;


--
-- Name: messages_2026_10_03_inserted_at_topic_idx; Type: INDEX ATTACH; Schema: realtime; Owner: -
--

ALTER INDEX realtime.messages_inserted_at_topic_index ATTACH PARTITION realtime.messages_2026_10_03_inserted_at_topic_idx;


--
-- Name: messages_2026_10_03_pkey; Type: INDEX ATTACH; Schema: realtime; Owner: -
--

ALTER INDEX realtime.messages_pkey ATTACH PARTITION realtime.messages_2026_10_03_pkey;


--
-- Name: messages_2026_10_04_inserted_at_topic_idx; Type: INDEX ATTACH; Schema: realtime; Owner: -
--

ALTER INDEX realtime.messages_inserted_at_topic_index ATTACH PARTITION realtime.messages_2026_10_04_inserted_at_topic_idx;


--
-- Name: messages_2026_10_04_pkey; Type: INDEX ATTACH; Schema: realtime; Owner: -
--

ALTER INDEX realtime.messages_pkey ATTACH PARTITION realtime.messages_2026_10_04_pkey;


--
-- Name: messages_2026_10_05_inserted_at_topic_idx; Type: INDEX ATTACH; Schema: realtime; Owner: -
--

ALTER INDEX realtime.messages_inserted_at_topic_index ATTACH PARTITION realtime.messages_2026_10_05_inserted_at_topic_idx;


--
-- Name: messages_2026_10_05_pkey; Type: INDEX ATTACH; Schema: realtime; Owner: -
--

ALTER INDEX realtime.messages_pkey ATTACH PARTITION realtime.messages_2026_10_05_pkey;


--
-- Name: users on_auth_user_created; Type: TRIGGER; Schema: auth; Owner: -
--

CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


--
-- Name: addresses on_address_deleted; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER on_address_deleted AFTER DELETE ON public.addresses FOR EACH ROW EXECUTE FUNCTION public.handle_after_address_delete();


--
-- Name: orders on_order_insert_set_number; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER on_order_insert_set_number BEFORE INSERT ON public.orders FOR EACH ROW EXECUTE FUNCTION public.set_order_number();


--
-- Name: orders on_order_status_change; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER on_order_status_change AFTER UPDATE OF status ON public.orders FOR EACH ROW WHEN (((old.status IS DISTINCT FROM new.status) AND (new.status <> ALL (ARRAY['cancelled'::text, 'confirmed'::text, 'delivered'::text])))) EXECUTE FUNCTION public.trigger_log_order_status_change();


--
-- Name: TRIGGER on_order_status_change ON orders; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TRIGGER on_order_status_change ON public.orders IS 'A2-G4/A4-G5 fix: logs status transitions into order_status_history, EXCEPT transitions to cancelled (cancel RPCs own those), confirmed (driver-actions EF and admin route own those), and delivered (driver-actions EF owns those). Fallback audit trail for preparing/ready/picked_up/on_the_way transitions where the EF does not insert an explicit row.';


--
-- Name: profiles on_profile_prevent_driver_escalation; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER on_profile_prevent_driver_escalation BEFORE INSERT OR UPDATE OF role ON public.profiles FOR EACH ROW WHEN ((new.role = 'driver'::text)) EXECUTE FUNCTION public.prevent_driver_role_escalation();


--
-- Name: reviews on_review_change_update_driver_rating; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER on_review_change_update_driver_rating AFTER INSERT OR UPDATE ON public.reviews FOR EACH ROW EXECUTE FUNCTION public.trigger_update_driver_rating();


--
-- Name: reviews on_review_change_update_merchant_rating; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER on_review_change_update_merchant_rating AFTER INSERT OR UPDATE ON public.reviews FOR EACH ROW EXECUTE FUNCTION public.trigger_update_merchant_rating();


--
-- Name: profiles on_wallet_balance_change; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER on_wallet_balance_change AFTER UPDATE OF wallet_balance ON public.profiles FOR EACH ROW WHEN ((old.wallet_balance IS DISTINCT FROM new.wallet_balance)) EXECUTE FUNCTION public.trigger_wallet_balance_audit();


--
-- Name: addresses set_addresses_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_addresses_updated_at BEFORE UPDATE ON public.addresses FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: categories set_categories_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_categories_updated_at BEFORE UPDATE ON public.categories FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: driver_settlements set_driver_settlements_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_driver_settlements_updated_at BEFORE UPDATE ON public.driver_settlements FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: drivers set_drivers_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_drivers_updated_at BEFORE UPDATE ON public.drivers FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: item_option_choices set_item_option_choices_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_item_option_choices_updated_at BEFORE UPDATE ON public.item_option_choices FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: item_options set_item_options_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_item_options_updated_at BEFORE UPDATE ON public.item_options FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: items set_items_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_items_updated_at BEFORE UPDATE ON public.items FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: merchant_payouts set_merchant_payouts_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_merchant_payouts_updated_at BEFORE UPDATE ON public.merchant_payouts FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: merchants set_merchants_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_merchants_updated_at BEFORE UPDATE ON public.merchants FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: operating_hours set_operating_hours_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_operating_hours_updated_at BEFORE UPDATE ON public.operating_hours FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: orders set_orders_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_orders_updated_at BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: platform_config set_platform_config_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_platform_config_updated_at BEFORE UPDATE ON public.platform_config FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: profiles set_profiles_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_profiles_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: promo_codes set_promo_codes_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_promo_codes_updated_at BEFORE UPDATE ON public.promo_codes FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: promoted_slots set_promoted_slots_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_promoted_slots_updated_at BEFORE UPDATE ON public.promoted_slots FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: reviews set_review_fields_from_order; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_review_fields_from_order BEFORE INSERT ON public.reviews FOR EACH ROW EXECUTE FUNCTION public.set_review_fields_from_order();


--
-- Name: TRIGGER set_review_fields_from_order ON reviews; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TRIGGER set_review_fields_from_order ON public.reviews IS 'Automatically populates customer_id, merchant_id, driver_id from the referenced order on INSERT. Allows client to insert review with only order_id and ratings/comments.';


--
-- Name: reviews set_reviews_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_reviews_updated_at BEFORE UPDATE ON public.reviews FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: drivers trg_check_driver_suspension; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_check_driver_suspension BEFORE UPDATE OF is_online ON public.drivers FOR EACH ROW EXECUTE FUNCTION public.check_driver_suspension();


--
-- Name: driver_settlements trg_enforce_driver_settlement_transitions; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_enforce_driver_settlement_transitions BEFORE UPDATE ON public.driver_settlements FOR EACH ROW EXECUTE FUNCTION public.enforce_driver_settlement_transitions();


--
-- Name: merchant_payouts trg_enforce_merchant_payout_transitions; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_enforce_merchant_payout_transitions BEFORE UPDATE ON public.merchant_payouts FOR EACH ROW EXECUTE FUNCTION public.enforce_merchant_payout_transitions();


--
-- Name: audit_logs trg_prevent_audit_log_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_prevent_audit_log_delete BEFORE DELETE ON public.audit_logs FOR EACH ROW EXECUTE FUNCTION public.prevent_audit_log_delete();


--
-- Name: audit_logs trg_prevent_audit_log_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_prevent_audit_log_update BEFORE UPDATE ON public.audit_logs FOR EACH ROW EXECUTE FUNCTION public.prevent_audit_log_update();


--
-- Name: subscription tr_check_filters; Type: TRIGGER; Schema: realtime; Owner: -
--

CREATE TRIGGER tr_check_filters BEFORE INSERT OR UPDATE ON realtime.subscription FOR EACH ROW EXECUTE FUNCTION realtime.subscription_check_filters();


--
-- Name: buckets enforce_bucket_name_length_trigger; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER enforce_bucket_name_length_trigger BEFORE INSERT OR UPDATE OF name ON storage.buckets FOR EACH ROW EXECUTE FUNCTION storage.enforce_bucket_name_length();


--
-- Name: buckets protect_bucket_control_insert; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER protect_bucket_control_insert BEFORE INSERT ON storage.buckets FOR EACH ROW EXECUTE FUNCTION storage.protect_bucket_control_columns('service_role');


--
-- Name: buckets protect_bucket_control_update; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER protect_bucket_control_update BEFORE UPDATE OF lifecycle_configuration, lifecycle_configuration_generation ON storage.buckets FOR EACH ROW EXECUTE FUNCTION storage.protect_bucket_control_columns();


--
-- Name: buckets protect_bucket_control_update_role; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER protect_bucket_control_update_role AFTER UPDATE OF lifecycle_configuration, lifecycle_configuration_generation ON storage.buckets FOR EACH ROW EXECUTE FUNCTION storage.enforce_bucket_lifecycle_service_role('service_role');


--
-- Name: buckets protect_buckets_delete; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER protect_buckets_delete BEFORE DELETE ON storage.buckets FOR EACH STATEMENT EXECUTE FUNCTION storage.protect_delete();


--
-- Name: objects protect_objects_delete; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER protect_objects_delete BEFORE DELETE ON storage.objects FOR EACH STATEMENT EXECUTE FUNCTION storage.protect_delete();


--
-- Name: objects update_objects_updated_at; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER update_objects_updated_at BEFORE UPDATE ON storage.objects FOR EACH ROW EXECUTE FUNCTION storage.update_updated_at_column();


--
-- Name: identities identities_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.identities
    ADD CONSTRAINT identities_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: mfa_amr_claims mfa_amr_claims_session_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_amr_claims
    ADD CONSTRAINT mfa_amr_claims_session_id_fkey FOREIGN KEY (session_id) REFERENCES auth.sessions(id) ON DELETE CASCADE;


--
-- Name: mfa_challenges mfa_challenges_auth_factor_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_challenges
    ADD CONSTRAINT mfa_challenges_auth_factor_id_fkey FOREIGN KEY (factor_id) REFERENCES auth.mfa_factors(id) ON DELETE CASCADE;


--
-- Name: mfa_factors mfa_factors_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_factors
    ADD CONSTRAINT mfa_factors_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: mfa_recovery_code_sets mfa_recovery_code_sets_mfa_factor_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_recovery_code_sets
    ADD CONSTRAINT mfa_recovery_code_sets_mfa_factor_id_fkey FOREIGN KEY (mfa_factor_id) REFERENCES auth.mfa_factors(id) ON DELETE CASCADE;


--
-- Name: mfa_recovery_code_sets mfa_recovery_code_sets_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_recovery_code_sets
    ADD CONSTRAINT mfa_recovery_code_sets_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: mfa_recovery_codes mfa_recovery_codes_mfa_recovery_code_set_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_recovery_codes
    ADD CONSTRAINT mfa_recovery_codes_mfa_recovery_code_set_id_fkey FOREIGN KEY (mfa_recovery_code_set_id) REFERENCES auth.mfa_recovery_code_sets(id) ON DELETE CASCADE;


--
-- Name: oauth_authorizations oauth_authorizations_client_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_authorizations
    ADD CONSTRAINT oauth_authorizations_client_id_fkey FOREIGN KEY (client_id) REFERENCES auth.oauth_clients(id) ON DELETE CASCADE;


--
-- Name: oauth_authorizations oauth_authorizations_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_authorizations
    ADD CONSTRAINT oauth_authorizations_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: oauth_consents oauth_consents_client_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_consents
    ADD CONSTRAINT oauth_consents_client_id_fkey FOREIGN KEY (client_id) REFERENCES auth.oauth_clients(id) ON DELETE CASCADE;


--
-- Name: oauth_consents oauth_consents_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_consents
    ADD CONSTRAINT oauth_consents_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: one_time_tokens one_time_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.one_time_tokens
    ADD CONSTRAINT one_time_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: refresh_tokens refresh_tokens_session_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.refresh_tokens
    ADD CONSTRAINT refresh_tokens_session_id_fkey FOREIGN KEY (session_id) REFERENCES auth.sessions(id) ON DELETE CASCADE;


--
-- Name: saml_providers saml_providers_sso_provider_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.saml_providers
    ADD CONSTRAINT saml_providers_sso_provider_id_fkey FOREIGN KEY (sso_provider_id) REFERENCES auth.sso_providers(id) ON DELETE CASCADE;


--
-- Name: saml_relay_states saml_relay_states_flow_state_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.saml_relay_states
    ADD CONSTRAINT saml_relay_states_flow_state_id_fkey FOREIGN KEY (flow_state_id) REFERENCES auth.flow_state(id) ON DELETE CASCADE;


--
-- Name: saml_relay_states saml_relay_states_sso_provider_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.saml_relay_states
    ADD CONSTRAINT saml_relay_states_sso_provider_id_fkey FOREIGN KEY (sso_provider_id) REFERENCES auth.sso_providers(id) ON DELETE CASCADE;


--
-- Name: scim_tokens scim_tokens_sso_provider_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.scim_tokens
    ADD CONSTRAINT scim_tokens_sso_provider_id_fkey FOREIGN KEY (sso_provider_id) REFERENCES auth.sso_providers(id) ON DELETE CASCADE;


--
-- Name: scim_users scim_users_sso_provider_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.scim_users
    ADD CONSTRAINT scim_users_sso_provider_id_fkey FOREIGN KEY (sso_provider_id) REFERENCES auth.sso_providers(id) ON DELETE CASCADE;


--
-- Name: scim_users scim_users_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.scim_users
    ADD CONSTRAINT scim_users_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: sessions sessions_oauth_client_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.sessions
    ADD CONSTRAINT sessions_oauth_client_id_fkey FOREIGN KEY (oauth_client_id) REFERENCES auth.oauth_clients(id) ON DELETE CASCADE;


--
-- Name: sessions sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.sessions
    ADD CONSTRAINT sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: sso_domains sso_domains_sso_provider_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.sso_domains
    ADD CONSTRAINT sso_domains_sso_provider_id_fkey FOREIGN KEY (sso_provider_id) REFERENCES auth.sso_providers(id) ON DELETE CASCADE;


--
-- Name: webauthn_challenges webauthn_challenges_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.webauthn_challenges
    ADD CONSTRAINT webauthn_challenges_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: webauthn_credentials webauthn_credentials_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.webauthn_credentials
    ADD CONSTRAINT webauthn_credentials_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: addresses addresses_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.addresses
    ADD CONSTRAINT addresses_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: admin_sessions admin_sessions_admin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_sessions
    ADD CONSTRAINT admin_sessions_admin_id_fkey FOREIGN KEY (admin_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: alert_incidents alert_incidents_acknowledged_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alert_incidents
    ADD CONSTRAINT alert_incidents_acknowledged_by_fkey FOREIGN KEY (acknowledged_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: alert_incidents alert_incidents_resolved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alert_incidents
    ADD CONSTRAINT alert_incidents_resolved_by_fkey FOREIGN KEY (resolved_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: alert_incidents alert_incidents_rule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alert_incidents
    ADD CONSTRAINT alert_incidents_rule_id_fkey FOREIGN KEY (rule_id) REFERENCES public.alert_rules(id) ON DELETE CASCADE;


--
-- Name: alert_rules alert_rules_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alert_rules
    ADD CONSTRAINT alert_rules_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id);


--
-- Name: audit_logs audit_logs_admin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_admin_id_fkey FOREIGN KEY (admin_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: cancellation_rules cancellation_rules_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cancellation_rules
    ADD CONSTRAINT cancellation_rules_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.profiles(id);


--
-- Name: categories categories_merchant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES public.merchants(id) ON DELETE CASCADE;


--
-- Name: data_access_log data_access_log_admin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_access_log
    ADD CONSTRAINT data_access_log_admin_id_fkey FOREIGN KEY (admin_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: driver_documents driver_documents_driver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.driver_documents
    ADD CONSTRAINT driver_documents_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.drivers(id) ON DELETE CASCADE;


--
-- Name: driver_documents driver_documents_reviewed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.driver_documents
    ADD CONSTRAINT driver_documents_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES public.profiles(id);


--
-- Name: driver_earnings driver_earnings_driver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.driver_earnings
    ADD CONSTRAINT driver_earnings_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.drivers(id) ON DELETE CASCADE;


--
-- Name: driver_earnings driver_earnings_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.driver_earnings
    ADD CONSTRAINT driver_earnings_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- Name: driver_order_requests driver_order_requests_driver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.driver_order_requests
    ADD CONSTRAINT driver_order_requests_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: driver_order_requests driver_order_requests_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.driver_order_requests
    ADD CONSTRAINT driver_order_requests_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- Name: driver_settlement_earnings driver_settlement_earnings_earning_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.driver_settlement_earnings
    ADD CONSTRAINT driver_settlement_earnings_earning_id_fkey FOREIGN KEY (earning_id) REFERENCES public.driver_earnings(id) ON DELETE RESTRICT;


--
-- Name: driver_settlement_earnings driver_settlement_earnings_settlement_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.driver_settlement_earnings
    ADD CONSTRAINT driver_settlement_earnings_settlement_id_fkey FOREIGN KEY (settlement_id) REFERENCES public.driver_settlements(id) ON DELETE CASCADE;


--
-- Name: driver_settlements driver_settlements_driver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.driver_settlements
    ADD CONSTRAINT driver_settlements_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.drivers(id) ON DELETE RESTRICT;


--
-- Name: driver_status_history driver_status_history_changed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.driver_status_history
    ADD CONSTRAINT driver_status_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.profiles(id);


--
-- Name: driver_status_history driver_status_history_driver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.driver_status_history
    ADD CONSTRAINT driver_status_history_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.drivers(id) ON DELETE CASCADE;


--
-- Name: drivers drivers_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drivers
    ADD CONSTRAINT drivers_id_fkey FOREIGN KEY (id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: favorite_items favorite_items_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.favorite_items
    ADD CONSTRAINT favorite_items_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.items(id) ON DELETE CASCADE;


--
-- Name: favorite_items favorite_items_merchant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.favorite_items
    ADD CONSTRAINT favorite_items_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES public.merchants(id) ON DELETE CASCADE;


--
-- Name: favorite_items favorite_items_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.favorite_items
    ADD CONSTRAINT favorite_items_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: favorites favorites_merchant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.favorites
    ADD CONSTRAINT favorites_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES public.merchants(id) ON DELETE CASCADE;


--
-- Name: favorites favorites_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.favorites
    ADD CONSTRAINT favorites_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: orders fk_orders_promo_code; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT fk_orders_promo_code FOREIGN KEY (promo_code_id) REFERENCES public.promo_codes(id) ON DELETE SET NULL;


--
-- Name: item_option_choices item_option_choices_option_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.item_option_choices
    ADD CONSTRAINT item_option_choices_option_id_fkey FOREIGN KEY (option_id) REFERENCES public.item_options(id) ON DELETE CASCADE;


--
-- Name: item_options item_options_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.item_options
    ADD CONSTRAINT item_options_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.items(id) ON DELETE CASCADE;


--
-- Name: items items_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.items
    ADD CONSTRAINT items_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories(id) ON DELETE CASCADE;


--
-- Name: items items_merchant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.items
    ADD CONSTRAINT items_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES public.merchants(id) ON DELETE CASCADE;


--
-- Name: loyalty_promo_log loyalty_promo_log_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loyalty_promo_log
    ADD CONSTRAINT loyalty_promo_log_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: loyalty_promo_log loyalty_promo_log_promo_code_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loyalty_promo_log
    ADD CONSTRAINT loyalty_promo_log_promo_code_id_fkey FOREIGN KEY (promo_code_id) REFERENCES public.promo_codes(id) ON DELETE CASCADE;


--
-- Name: merchant_payout_orders merchant_payout_orders_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_payout_orders
    ADD CONSTRAINT merchant_payout_orders_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE RESTRICT;


--
-- Name: merchant_payout_orders merchant_payout_orders_payout_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_payout_orders
    ADD CONSTRAINT merchant_payout_orders_payout_id_fkey FOREIGN KEY (payout_id) REFERENCES public.merchant_payouts(id) ON DELETE CASCADE;


--
-- Name: merchant_payouts merchant_payouts_merchant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_payouts
    ADD CONSTRAINT merchant_payouts_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES public.merchants(id) ON DELETE RESTRICT;


--
-- Name: merchants merchants_category_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchants
    ADD CONSTRAINT merchants_category_fk FOREIGN KEY (category) REFERENCES public.merchant_categories(code);


--
-- Name: notifications notifications_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: operating_hours operating_hours_merchant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operating_hours
    ADD CONSTRAINT operating_hours_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES public.merchants(id) ON DELETE CASCADE;


--
-- Name: order_items order_items_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.items(id) ON DELETE CASCADE;


--
-- Name: order_items order_items_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- Name: order_status_history order_status_history_changed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_status_history
    ADD CONSTRAINT order_status_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.profiles(id);


--
-- Name: order_status_history order_status_history_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_status_history
    ADD CONSTRAINT order_status_history_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- Name: orders orders_cancelled_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_cancelled_by_fkey FOREIGN KEY (cancelled_by) REFERENCES public.profiles(id);


--
-- Name: orders orders_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: orders orders_driver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: orders orders_merchant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES public.merchants(id) ON DELETE CASCADE;


--
-- Name: profiles profiles_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: promo_code_usage promo_code_usage_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promo_code_usage
    ADD CONSTRAINT promo_code_usage_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- Name: promo_code_usage promo_code_usage_promo_code_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promo_code_usage
    ADD CONSTRAINT promo_code_usage_promo_code_id_fkey FOREIGN KEY (promo_code_id) REFERENCES public.promo_codes(id) ON DELETE CASCADE;


--
-- Name: promo_code_usage promo_code_usage_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promo_code_usage
    ADD CONSTRAINT promo_code_usage_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: promo_codes promo_codes_category_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promo_codes
    ADD CONSTRAINT promo_codes_category_fk FOREIGN KEY (category) REFERENCES public.merchant_categories(code);


--
-- Name: promo_codes promo_codes_merchant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promo_codes
    ADD CONSTRAINT promo_codes_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES public.merchants(id) ON DELETE CASCADE;


--
-- Name: promoted_slot_events promoted_slot_events_slot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promoted_slot_events
    ADD CONSTRAINT promoted_slot_events_slot_id_fkey FOREIGN KEY (slot_id) REFERENCES public.promoted_slots(id) ON DELETE CASCADE;


--
-- Name: promoted_slots promoted_slots_category_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promoted_slots
    ADD CONSTRAINT promoted_slots_category_fk FOREIGN KEY (category) REFERENCES public.merchant_categories(code);


--
-- Name: promoted_slots promoted_slots_merchant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promoted_slots
    ADD CONSTRAINT promoted_slots_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES public.merchants(id) ON DELETE CASCADE;


--
-- Name: reviews reviews_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT reviews_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: reviews reviews_driver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT reviews_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.drivers(id) ON DELETE SET NULL;


--
-- Name: reviews reviews_merchant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT reviews_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES public.merchants(id) ON DELETE CASCADE;


--
-- Name: reviews reviews_moderated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT reviews_moderated_by_fkey FOREIGN KEY (moderated_by) REFERENCES public.profiles(id);


--
-- Name: reviews reviews_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT reviews_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- Name: search_queries search_queries_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.search_queries
    ADD CONSTRAINT search_queries_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: wallet_audit_log wallet_audit_log_changed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_audit_log
    ADD CONSTRAINT wallet_audit_log_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.profiles(id);


--
-- Name: wallet_audit_log wallet_audit_log_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_audit_log
    ADD CONSTRAINT wallet_audit_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: objects objects_bucketId_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.objects
    ADD CONSTRAINT "objects_bucketId_fkey" FOREIGN KEY (bucket_id) REFERENCES storage.buckets(id);


--
-- Name: s3_multipart_uploads s3_multipart_uploads_bucket_id_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.s3_multipart_uploads
    ADD CONSTRAINT s3_multipart_uploads_bucket_id_fkey FOREIGN KEY (bucket_id) REFERENCES storage.buckets(id);


--
-- Name: s3_multipart_uploads_parts s3_multipart_uploads_parts_bucket_id_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.s3_multipart_uploads_parts
    ADD CONSTRAINT s3_multipart_uploads_parts_bucket_id_fkey FOREIGN KEY (bucket_id) REFERENCES storage.buckets(id);


--
-- Name: s3_multipart_uploads_parts s3_multipart_uploads_parts_upload_id_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.s3_multipart_uploads_parts
    ADD CONSTRAINT s3_multipart_uploads_parts_upload_id_fkey FOREIGN KEY (upload_id) REFERENCES storage.s3_multipart_uploads(id) ON DELETE CASCADE;


--
-- Name: vector_indexes vector_indexes_bucket_id_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.vector_indexes
    ADD CONSTRAINT vector_indexes_bucket_id_fkey FOREIGN KEY (bucket_id) REFERENCES storage.buckets_vectors(id);


--
-- Name: audit_log_entries; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.audit_log_entries ENABLE ROW LEVEL SECURITY;

--
-- Name: flow_state; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.flow_state ENABLE ROW LEVEL SECURITY;

--
-- Name: identities; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.identities ENABLE ROW LEVEL SECURITY;

--
-- Name: instances; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.instances ENABLE ROW LEVEL SECURITY;

--
-- Name: mfa_amr_claims; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.mfa_amr_claims ENABLE ROW LEVEL SECURITY;

--
-- Name: mfa_challenges; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.mfa_challenges ENABLE ROW LEVEL SECURITY;

--
-- Name: mfa_factors; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.mfa_factors ENABLE ROW LEVEL SECURITY;

--
-- Name: one_time_tokens; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.one_time_tokens ENABLE ROW LEVEL SECURITY;

--
-- Name: refresh_tokens; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.refresh_tokens ENABLE ROW LEVEL SECURITY;

--
-- Name: saml_providers; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.saml_providers ENABLE ROW LEVEL SECURITY;

--
-- Name: saml_relay_states; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.saml_relay_states ENABLE ROW LEVEL SECURITY;

--
-- Name: schema_migrations; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.schema_migrations ENABLE ROW LEVEL SECURITY;

--
-- Name: sessions; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.sessions ENABLE ROW LEVEL SECURITY;

--
-- Name: sso_domains; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.sso_domains ENABLE ROW LEVEL SECURITY;

--
-- Name: sso_providers; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.sso_providers ENABLE ROW LEVEL SECURITY;

--
-- Name: users; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.users ENABLE ROW LEVEL SECURITY;

--
-- Name: driver_settlements Admins can manage driver settlements; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can manage driver settlements" ON public.driver_settlements TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.admin_sessions
  WHERE ((admin_sessions.admin_id = auth.uid()) AND (admin_sessions.expires_at > now())))));


--
-- Name: merchant_payouts Admins can manage merchant payouts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can manage merchant payouts" ON public.merchant_payouts TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.admin_sessions
  WHERE ((admin_sessions.admin_id = auth.uid()) AND (admin_sessions.expires_at > now())))));


--
-- Name: merchant_payout_orders Admins can view payout orders; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can view payout orders" ON public.merchant_payout_orders TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.admin_sessions
  WHERE ((admin_sessions.admin_id = auth.uid()) AND (admin_sessions.expires_at > now())))));


--
-- Name: driver_settlement_earnings Admins can view settlement earnings; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can view settlement earnings" ON public.driver_settlement_earnings TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.admin_sessions
  WHERE ((admin_sessions.admin_id = auth.uid()) AND (admin_sessions.expires_at > now())))));


--
-- Name: driver_settlement_earnings Drivers can read own settlement earnings; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Drivers can read own settlement earnings" ON public.driver_settlement_earnings FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.driver_settlements ds
  WHERE ((ds.id = driver_settlement_earnings.settlement_id) AND (ds.driver_id = auth.uid())))));


--
-- Name: driver_settlements Drivers can read own settlements; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Drivers can read own settlements" ON public.driver_settlements FOR SELECT TO authenticated USING ((driver_id = auth.uid()));


--
-- Name: addresses; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.addresses ENABLE ROW LEVEL SECURITY;

--
-- Name: addresses addresses_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY addresses_delete_own ON public.addresses FOR DELETE USING ((auth.uid() = user_id));


--
-- Name: addresses addresses_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY addresses_insert_own ON public.addresses FOR INSERT WITH CHECK ((auth.uid() = user_id));


--
-- Name: addresses addresses_read_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY addresses_read_own ON public.addresses FOR SELECT USING ((auth.uid() = user_id));


--
-- Name: addresses addresses_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY addresses_update_own ON public.addresses FOR UPDATE USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));


--
-- Name: admin_kpi_cache; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.admin_kpi_cache ENABLE ROW LEVEL SECURITY;

--
-- Name: admin_sessions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.admin_sessions ENABLE ROW LEVEL SECURITY;

--
-- Name: alert_incidents; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.alert_incidents ENABLE ROW LEVEL SECURITY;

--
-- Name: alert_rules; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.alert_rules ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_logs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: cancellation_rules; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.cancellation_rules ENABLE ROW LEVEL SECURITY;

--
-- Name: categories; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

--
-- Name: categories categories_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY categories_read ON public.categories FOR SELECT USING (true);


--
-- Name: data_access_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.data_access_log ENABLE ROW LEVEL SECURITY;

--
-- Name: driver_documents; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.driver_documents ENABLE ROW LEVEL SECURITY;

--
-- Name: driver_documents driver_documents_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY driver_documents_insert_own ON public.driver_documents FOR INSERT WITH CHECK ((auth.uid() = driver_id));


--
-- Name: POLICY driver_documents_insert_own ON driver_documents; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON POLICY driver_documents_insert_own ON public.driver_documents IS 'P1F-14: Drivers can upload (insert) their own documents during onboarding. Cannot modify after upload.';


--
-- Name: driver_documents driver_documents_read_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY driver_documents_read_own ON public.driver_documents FOR SELECT USING ((auth.uid() = driver_id));


--
-- Name: POLICY driver_documents_read_own ON driver_documents; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON POLICY driver_documents_read_own ON public.driver_documents IS 'P1F-14: Drivers can read their own documents only.';


--
-- Name: driver_earnings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.driver_earnings ENABLE ROW LEVEL SECURITY;

--
-- Name: driver_earnings driver_earnings_read_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY driver_earnings_read_own ON public.driver_earnings FOR SELECT USING ((auth.uid() = driver_id));


--
-- Name: POLICY driver_earnings_read_own ON driver_earnings; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON POLICY driver_earnings_read_own ON public.driver_earnings IS 'P1F-13: Drivers can read their own earnings only.';


--
-- Name: driver_order_requests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.driver_order_requests ENABLE ROW LEVEL SECURITY;

--
-- Name: driver_order_requests driver_order_requests_read_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY driver_order_requests_read_own ON public.driver_order_requests FOR SELECT USING ((auth.uid() = driver_id));


--
-- Name: driver_settlement_earnings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.driver_settlement_earnings ENABLE ROW LEVEL SECURITY;

--
-- Name: driver_settlements; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.driver_settlements ENABLE ROW LEVEL SECURITY;

--
-- Name: driver_status_history; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.driver_status_history ENABLE ROW LEVEL SECURITY;

--
-- Name: driver_status_history driver_status_history_read_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY driver_status_history_read_own ON public.driver_status_history FOR SELECT USING ((auth.uid() = driver_id));


--
-- Name: POLICY driver_status_history_read_own ON driver_status_history; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON POLICY driver_status_history_read_own ON public.driver_status_history IS 'P1F-15: Drivers can read their own status history. Only service role can insert (admin actions).';


--
-- Name: drivers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.drivers ENABLE ROW LEVEL SECURITY;

--
-- Name: drivers drivers_read_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY drivers_read_own ON public.drivers FOR SELECT USING ((auth.uid() = id));


--
-- Name: POLICY drivers_read_own ON drivers; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON POLICY drivers_read_own ON public.drivers IS 'P1F-08: Drivers can read their own row only.';


--
-- Name: drivers drivers_update_own_location; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY drivers_update_own_location ON public.drivers FOR UPDATE USING (((auth.uid() = id) AND (is_verified = true) AND (is_active = true))) WITH CHECK (((auth.uid() = id) AND (is_verified = true) AND (is_active = true) AND (national_id = ( SELECT drivers_1.national_id
   FROM public.drivers drivers_1
  WHERE (drivers_1.id = auth.uid()))) AND (NOT (national_id_encrypted IS DISTINCT FROM ( SELECT drivers_1.national_id_encrypted
   FROM public.drivers drivers_1
  WHERE (drivers_1.id = auth.uid())))) AND (NOT (national_id_image_url IS DISTINCT FROM ( SELECT drivers_1.national_id_image_url
   FROM public.drivers drivers_1
  WHERE (drivers_1.id = auth.uid())))) AND (NOT (driving_license_number IS DISTINCT FROM ( SELECT drivers_1.driving_license_number
   FROM public.drivers drivers_1
  WHERE (drivers_1.id = auth.uid())))) AND (NOT (driving_license_image_url IS DISTINCT FROM ( SELECT drivers_1.driving_license_image_url
   FROM public.drivers drivers_1
  WHERE (drivers_1.id = auth.uid())))) AND (NOT (vehicle_registration_image_url IS DISTINCT FROM ( SELECT drivers_1.vehicle_registration_image_url
   FROM public.drivers drivers_1
  WHERE (drivers_1.id = auth.uid())))) AND (vehicle_plate = ( SELECT drivers_1.vehicle_plate
   FROM public.drivers drivers_1
  WHERE (drivers_1.id = auth.uid()))) AND (vehicle_type = ( SELECT drivers_1.vehicle_type
   FROM public.drivers drivers_1
  WHERE (drivers_1.id = auth.uid()))) AND (NOT (vehicle_color IS DISTINCT FROM ( SELECT drivers_1.vehicle_color
   FROM public.drivers drivers_1
  WHERE (drivers_1.id = auth.uid())))) AND (NOT (vehicle_model IS DISTINCT FROM ( SELECT drivers_1.vehicle_model
   FROM public.drivers drivers_1
  WHERE (drivers_1.id = auth.uid())))) AND (NOT (rating IS DISTINCT FROM ( SELECT drivers_1.rating
   FROM public.drivers drivers_1
  WHERE (drivers_1.id = auth.uid())))) AND (NOT (rating_count IS DISTINCT FROM ( SELECT drivers_1.rating_count
   FROM public.drivers drivers_1
  WHERE (drivers_1.id = auth.uid())))) AND (NOT (total_deliveries IS DISTINCT FROM ( SELECT drivers_1.total_deliveries
   FROM public.drivers drivers_1
  WHERE (drivers_1.id = auth.uid())))) AND (NOT (total_earnings IS DISTINCT FROM ( SELECT drivers_1.total_earnings
   FROM public.drivers drivers_1
  WHERE (drivers_1.id = auth.uid())))) AND (verification_status = ( SELECT drivers_1.verification_status
   FROM public.drivers drivers_1
  WHERE (drivers_1.id = auth.uid()))) AND (NOT (verified_at IS DISTINCT FROM ( SELECT drivers_1.verified_at
   FROM public.drivers drivers_1
  WHERE (drivers_1.id = auth.uid())))) AND (NOT (deactivated_at IS DISTINCT FROM ( SELECT drivers_1.deactivated_at
   FROM public.drivers drivers_1
  WHERE (drivers_1.id = auth.uid()))))));


--
-- Name: POLICY drivers_update_own_location ON drivers; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON POLICY drivers_update_own_location ON public.drivers IS 'P1F-08: Drivers can update ONLY their own row, ONLY location + online status, and ONLY if verified and active. All other columns are write-protected.';


--
-- Name: favorite_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.favorite_items ENABLE ROW LEVEL SECURITY;

--
-- Name: favorite_items favorite_items_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY favorite_items_delete_own ON public.favorite_items FOR DELETE USING ((auth.uid() = user_id));


--
-- Name: POLICY favorite_items_delete_own ON favorite_items; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON POLICY favorite_items_delete_own ON public.favorite_items IS 'Users can remove their own favorite items only.';


--
-- Name: favorite_items favorite_items_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY favorite_items_insert_own ON public.favorite_items FOR INSERT WITH CHECK ((auth.uid() = user_id));


--
-- Name: POLICY favorite_items_insert_own ON favorite_items; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON POLICY favorite_items_insert_own ON public.favorite_items IS 'Users can add their own favorite items only.';


--
-- Name: favorite_items favorite_items_read_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY favorite_items_read_own ON public.favorite_items FOR SELECT USING ((auth.uid() = user_id));


--
-- Name: POLICY favorite_items_read_own ON favorite_items; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON POLICY favorite_items_read_own ON public.favorite_items IS 'Users can read their own favorite items only.';


--
-- Name: favorites; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.favorites ENABLE ROW LEVEL SECURITY;

--
-- Name: favorites favorites_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY favorites_delete_own ON public.favorites FOR DELETE USING ((auth.uid() = user_id));


--
-- Name: favorites favorites_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY favorites_insert_own ON public.favorites FOR INSERT WITH CHECK ((auth.uid() = user_id));


--
-- Name: favorites favorites_read_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY favorites_read_own ON public.favorites FOR SELECT USING ((auth.uid() = user_id));


--
-- Name: POLICY favorites_read_own ON favorites; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON POLICY favorites_read_own ON public.favorites IS 'P1F-11: Users can read their own favorites only.';


--
-- Name: item_option_choices; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.item_option_choices ENABLE ROW LEVEL SECURITY;

--
-- Name: item_option_choices item_option_choices_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY item_option_choices_read ON public.item_option_choices FOR SELECT USING (true);


--
-- Name: item_options; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.item_options ENABLE ROW LEVEL SECURITY;

--
-- Name: item_options item_options_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY item_options_read ON public.item_options FOR SELECT USING (true);


--
-- Name: items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.items ENABLE ROW LEVEL SECURITY;

--
-- Name: items items_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY items_read ON public.items FOR SELECT USING (true);


--
-- Name: loyalty_promo_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.loyalty_promo_log ENABLE ROW LEVEL SECURITY;

--
-- Name: merchant_categories; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.merchant_categories ENABLE ROW LEVEL SECURITY;

--
-- Name: merchant_categories merchant_categories_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY merchant_categories_read ON public.merchant_categories FOR SELECT TO authenticated, anon USING ((is_active = true));


--
-- Name: merchant_payout_orders; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.merchant_payout_orders ENABLE ROW LEVEL SECURITY;

--
-- Name: merchant_payouts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.merchant_payouts ENABLE ROW LEVEL SECURITY;

--
-- Name: merchants; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.merchants ENABLE ROW LEVEL SECURITY;

--
-- Name: merchants merchants_read_active; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY merchants_read_active ON public.merchants FOR SELECT USING ((is_active = true));


--
-- Name: POLICY merchants_read_active ON merchants; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON POLICY merchants_read_active ON public.merchants IS 'P1F-04: Anyone can read active merchants. Inactive merchants hidden.';


--
-- Name: notifications; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

--
-- Name: notifications notifications_read_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notifications_read_own ON public.notifications FOR SELECT USING ((auth.uid() = user_id));


--
-- Name: notifications notifications_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notifications_update_own ON public.notifications FOR UPDATE USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));


--
-- Name: POLICY notifications_update_own ON notifications; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON POLICY notifications_update_own ON public.notifications IS 'P1F-10: Users can mark their own notifications as read.';


--
-- Name: operating_hours; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.operating_hours ENABLE ROW LEVEL SECURITY;

--
-- Name: operating_hours operating_hours_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY operating_hours_read ON public.operating_hours FOR SELECT USING (true);


--
-- Name: order_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;

--
-- Name: order_items order_items_read_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY order_items_read_own ON public.order_items FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.orders o
  WHERE ((o.id = order_items.order_id) AND ((o.customer_id = auth.uid()) OR (o.driver_id = auth.uid()))))));


--
-- Name: order_status_history; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.order_status_history ENABLE ROW LEVEL SECURITY;

--
-- Name: order_status_history order_status_history_read_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY order_status_history_read_own ON public.order_status_history FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.orders o
  WHERE ((o.id = order_status_history.order_id) AND ((o.customer_id = auth.uid()) OR (o.driver_id = auth.uid()))))));


--
-- Name: orders; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

--
-- Name: orders orders_read_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY orders_read_own ON public.orders FOR SELECT USING (((customer_id = auth.uid()) OR (driver_id = auth.uid())));


--
-- Name: platform_config; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.platform_config ENABLE ROW LEVEL SECURITY;

--
-- Name: platform_config platform_config_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY platform_config_read ON public.platform_config FOR SELECT USING (true);


--
-- Name: profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles profiles_read_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY profiles_read_own ON public.profiles FOR SELECT USING ((auth.uid() = id));


--
-- Name: POLICY profiles_read_own ON profiles; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON POLICY profiles_read_own ON public.profiles IS 'P1F-02: Users can read their own profile only.';


--
-- Name: profiles profiles_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY profiles_update_own ON public.profiles FOR UPDATE USING ((auth.uid() = id)) WITH CHECK (((auth.uid() = id) AND (NOT (wallet_balance IS DISTINCT FROM ( SELECT profiles_1.wallet_balance
   FROM public.profiles profiles_1
  WHERE (profiles_1.id = auth.uid())))) AND (NOT (role IS DISTINCT FROM ( SELECT profiles_1.role
   FROM public.profiles profiles_1
  WHERE (profiles_1.id = auth.uid())))) AND (NOT (is_active IS DISTINCT FROM false))));


--
-- Name: POLICY profiles_update_own ON profiles; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON POLICY profiles_update_own ON public.profiles IS 'S01/S14/D05 fix: Users can update own profile EXCEPT wallet_balance, role, and is_active reactivation. wallet_balance: must go through adjust_wallet_balance RPC. role: admin-only. is_active: user may set FALSE (deleteAccount), may NOT set TRUE (no self-reactivation).';


--
-- Name: promo_code_usage; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.promo_code_usage ENABLE ROW LEVEL SECURITY;

--
-- Name: promo_codes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.promo_codes ENABLE ROW LEVEL SECURITY;

--
-- Name: promoted_slot_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.promoted_slot_events ENABLE ROW LEVEL SECURITY;

--
-- Name: promoted_slots; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.promoted_slots ENABLE ROW LEVEL SECURITY;

--
-- Name: promoted_slots promoted_slots_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY promoted_slots_read ON public.promoted_slots FOR SELECT USING (true);


--
-- Name: reviews; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;

--
-- Name: reviews reviews_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY reviews_insert_own ON public.reviews FOR INSERT WITH CHECK (((auth.uid() = customer_id) AND (auth.role() = 'authenticated'::text)));


--
-- Name: POLICY reviews_insert_own ON reviews; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON POLICY reviews_insert_own ON public.reviews IS 'P1F-09: Authenticated users can create reviews for their own orders only.';


--
-- Name: reviews reviews_read_visible; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY reviews_read_visible ON public.reviews FOR SELECT USING (((is_visible = true) OR (customer_id = auth.uid())));


--
-- Name: search_queries; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.search_queries ENABLE ROW LEVEL SECURITY;

--
-- Name: wallet_audit_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.wallet_audit_log ENABLE ROW LEVEL SECURITY;

--
-- Name: messages; Type: ROW SECURITY; Schema: realtime; Owner: -
--

ALTER TABLE realtime.messages ENABLE ROW LEVEL SECURITY;

--
-- Name: objects ad_creatives_delete; Type: POLICY; Schema: storage; Owner: -
--

CREATE POLICY ad_creatives_delete ON storage.objects FOR DELETE USING (((bucket_id = 'ad-creatives'::text) AND (auth.role() = 'service_role'::text)));


--
-- Name: objects ad_creatives_read; Type: POLICY; Schema: storage; Owner: -
--

CREATE POLICY ad_creatives_read ON storage.objects FOR SELECT USING ((bucket_id = 'ad-creatives'::text));


--
-- Name: objects ad_creatives_update; Type: POLICY; Schema: storage; Owner: -
--

CREATE POLICY ad_creatives_update ON storage.objects FOR UPDATE USING (((bucket_id = 'ad-creatives'::text) AND (auth.role() = 'service_role'::text))) WITH CHECK (((bucket_id = 'ad-creatives'::text) AND (auth.role() = 'service_role'::text)));


--
-- Name: objects ad_creatives_write; Type: POLICY; Schema: storage; Owner: -
--

CREATE POLICY ad_creatives_write ON storage.objects FOR INSERT WITH CHECK (((bucket_id = 'ad-creatives'::text) AND (auth.role() = 'service_role'::text)));


--
-- Name: buckets; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.buckets ENABLE ROW LEVEL SECURITY;

--
-- Name: buckets_analytics; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.buckets_analytics ENABLE ROW LEVEL SECURITY;

--
-- Name: buckets_vectors; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.buckets_vectors ENABLE ROW LEVEL SECURITY;

--
-- Name: objects driver_documents_insert_own; Type: POLICY; Schema: storage; Owner: -
--

CREATE POLICY driver_documents_insert_own ON storage.objects FOR INSERT WITH CHECK (((bucket_id = 'driver-documents'::text) AND ((auth.uid())::text = (storage.foldername(name))[1]) AND (auth.role() = 'authenticated'::text)));


--
-- Name: objects driver_documents_read_own; Type: POLICY; Schema: storage; Owner: -
--

CREATE POLICY driver_documents_read_own ON storage.objects FOR SELECT USING (((bucket_id = 'driver-documents'::text) AND ((auth.uid())::text = (storage.foldername(name))[1])));


--
-- Name: objects item_images_delete; Type: POLICY; Schema: storage; Owner: -
--

CREATE POLICY item_images_delete ON storage.objects FOR DELETE USING (((bucket_id = 'item-images'::text) AND (auth.role() = 'service_role'::text)));


--
-- Name: objects item_images_read; Type: POLICY; Schema: storage; Owner: -
--

CREATE POLICY item_images_read ON storage.objects FOR SELECT USING ((bucket_id = 'item-images'::text));


--
-- Name: objects item_images_update; Type: POLICY; Schema: storage; Owner: -
--

CREATE POLICY item_images_update ON storage.objects FOR UPDATE USING (((bucket_id = 'item-images'::text) AND (auth.role() = 'service_role'::text))) WITH CHECK (((bucket_id = 'item-images'::text) AND (auth.role() = 'service_role'::text)));


--
-- Name: objects item_images_write; Type: POLICY; Schema: storage; Owner: -
--

CREATE POLICY item_images_write ON storage.objects FOR INSERT WITH CHECK (((bucket_id = 'item-images'::text) AND (auth.role() = 'service_role'::text)));


--
-- Name: objects merchant_assets_delete; Type: POLICY; Schema: storage; Owner: -
--

CREATE POLICY merchant_assets_delete ON storage.objects FOR DELETE USING (((bucket_id = 'merchant-assets'::text) AND (auth.role() = 'service_role'::text)));


--
-- Name: objects merchant_assets_read; Type: POLICY; Schema: storage; Owner: -
--

CREATE POLICY merchant_assets_read ON storage.objects FOR SELECT USING ((bucket_id = 'merchant-assets'::text));


--
-- Name: objects merchant_assets_update; Type: POLICY; Schema: storage; Owner: -
--

CREATE POLICY merchant_assets_update ON storage.objects FOR UPDATE USING (((bucket_id = 'merchant-assets'::text) AND (auth.role() = 'service_role'::text))) WITH CHECK (((bucket_id = 'merchant-assets'::text) AND (auth.role() = 'service_role'::text)));


--
-- Name: objects merchant_assets_write; Type: POLICY; Schema: storage; Owner: -
--

CREATE POLICY merchant_assets_write ON storage.objects FOR INSERT WITH CHECK (((bucket_id = 'merchant-assets'::text) AND (auth.role() = 'service_role'::text)));


--
-- Name: migrations; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.migrations ENABLE ROW LEVEL SECURITY;

--
-- Name: objects; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

--
-- Name: s3_multipart_uploads; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.s3_multipart_uploads ENABLE ROW LEVEL SECURITY;

--
-- Name: s3_multipart_uploads_parts; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.s3_multipart_uploads_parts ENABLE ROW LEVEL SECURITY;

--
-- Name: objects user_avatars_delete_own; Type: POLICY; Schema: storage; Owner: -
--

CREATE POLICY user_avatars_delete_own ON storage.objects FOR DELETE USING (((bucket_id = 'user-avatars'::text) AND ((auth.uid())::text = (storage.foldername(name))[1])));


--
-- Name: objects user_avatars_insert_own; Type: POLICY; Schema: storage; Owner: -
--

CREATE POLICY user_avatars_insert_own ON storage.objects FOR INSERT WITH CHECK (((bucket_id = 'user-avatars'::text) AND ((auth.uid())::text = (storage.foldername(name))[1]) AND (auth.role() = 'authenticated'::text)));


--
-- Name: objects user_avatars_read; Type: POLICY; Schema: storage; Owner: -
--

CREATE POLICY user_avatars_read ON storage.objects FOR SELECT USING ((bucket_id = 'user-avatars'::text));


--
-- Name: objects user_avatars_update_own; Type: POLICY; Schema: storage; Owner: -
--

CREATE POLICY user_avatars_update_own ON storage.objects FOR UPDATE USING (((bucket_id = 'user-avatars'::text) AND ((auth.uid())::text = (storage.foldername(name))[1]))) WITH CHECK (((bucket_id = 'user-avatars'::text) AND ((auth.uid())::text = (storage.foldername(name))[1])));


--
-- Name: vector_indexes; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.vector_indexes ENABLE ROW LEVEL SECURITY;

--
-- Name: supabase_realtime; Type: PUBLICATION; Schema: -; Owner: -
--

CREATE PUBLICATION supabase_realtime WITH (publish = 'insert, update, delete');


--
-- Name: PUBLICATION supabase_realtime; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON PUBLICATION supabase_realtime IS 'Supabase Realtime publication — includes all admin-dashboard-tracked tables for postgres_changes events. Migration 092 added favorite_items.';


--
-- Name: supabase_realtime_messages_publication; Type: PUBLICATION; Schema: -; Owner: -
--

CREATE PUBLICATION supabase_realtime_messages_publication WITH (publish = 'insert, update, delete, truncate');


--
-- Name: supabase_realtime addresses; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.addresses;


--
-- Name: supabase_realtime alert_incidents; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.alert_incidents;


--
-- Name: supabase_realtime alert_rules; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.alert_rules;


--
-- Name: supabase_realtime audit_logs; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.audit_logs;


--
-- Name: supabase_realtime cancellation_rules; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.cancellation_rules;


--
-- Name: supabase_realtime categories; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.categories;


--
-- Name: supabase_realtime data_access_log; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.data_access_log;


--
-- Name: supabase_realtime driver_documents; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.driver_documents;


--
-- Name: supabase_realtime driver_earnings; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.driver_earnings;


--
-- Name: supabase_realtime driver_order_requests; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.driver_order_requests;


--
-- Name: supabase_realtime driver_status_history; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.driver_status_history;


--
-- Name: supabase_realtime drivers; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.drivers;


--
-- Name: supabase_realtime favorite_items; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.favorite_items;


--
-- Name: supabase_realtime favorites; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.favorites;


--
-- Name: supabase_realtime item_option_choices; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.item_option_choices;


--
-- Name: supabase_realtime item_options; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.item_options;


--
-- Name: supabase_realtime items; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.items;


--
-- Name: supabase_realtime merchants; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.merchants;


--
-- Name: supabase_realtime notifications; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.notifications;


--
-- Name: supabase_realtime operating_hours; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.operating_hours;


--
-- Name: supabase_realtime order_items; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.order_items;


--
-- Name: supabase_realtime order_status_history; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.order_status_history;


--
-- Name: supabase_realtime orders; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.orders;


--
-- Name: supabase_realtime platform_config; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.platform_config;


--
-- Name: supabase_realtime profiles; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.profiles;


--
-- Name: supabase_realtime promo_code_usage; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.promo_code_usage;


--
-- Name: supabase_realtime promo_codes; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.promo_codes;


--
-- Name: supabase_realtime promoted_slots; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.promoted_slots;


--
-- Name: supabase_realtime reviews; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.reviews;


--
-- Name: supabase_realtime wallet_audit_log; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.wallet_audit_log;


--
-- Name: supabase_realtime_messages_publication messages; Type: PUBLICATION TABLE; Schema: realtime; Owner: -
--

ALTER PUBLICATION supabase_realtime_messages_publication ADD TABLE ONLY realtime.messages;


--
-- Name: ensure_rls; Type: EVENT TRIGGER; Schema: -; Owner: -
--

CREATE EVENT TRIGGER ensure_rls ON ddl_command_end
         WHEN TAG IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
   EXECUTE FUNCTION public.rls_auto_enable();


--
-- Name: issue_graphql_placeholder; Type: EVENT TRIGGER; Schema: -; Owner: -
--

CREATE EVENT TRIGGER issue_graphql_placeholder ON sql_drop
         WHEN TAG IN ('DROP EXTENSION')
   EXECUTE FUNCTION extensions.set_graphql_placeholder();


--
-- Name: issue_pg_cron_access; Type: EVENT TRIGGER; Schema: -; Owner: -
--

CREATE EVENT TRIGGER issue_pg_cron_access ON ddl_command_end
         WHEN TAG IN ('CREATE EXTENSION')
   EXECUTE FUNCTION extensions.grant_pg_cron_access();


--
-- Name: issue_pg_graphql_access; Type: EVENT TRIGGER; Schema: -; Owner: -
--

CREATE EVENT TRIGGER issue_pg_graphql_access ON ddl_command_end
         WHEN TAG IN ('CREATE EXTENSION')
   EXECUTE FUNCTION extensions.grant_pg_graphql_access();


--
-- Name: issue_pg_net_access; Type: EVENT TRIGGER; Schema: -; Owner: -
--

CREATE EVENT TRIGGER issue_pg_net_access ON ddl_command_end
         WHEN TAG IN ('CREATE EXTENSION')
   EXECUTE FUNCTION extensions.grant_pg_net_access();


--
-- Name: pgrst_ddl_watch; Type: EVENT TRIGGER; Schema: -; Owner: -
--

CREATE EVENT TRIGGER pgrst_ddl_watch ON ddl_command_end
   EXECUTE FUNCTION extensions.pgrst_ddl_watch();


--
-- Name: pgrst_drop_watch; Type: EVENT TRIGGER; Schema: -; Owner: -
--

CREATE EVENT TRIGGER pgrst_drop_watch ON sql_drop
   EXECUTE FUNCTION extensions.pgrst_drop_watch();


--
-- PostgreSQL database dump complete
--

\unrestrict kGbA4KLccIsatfnwC5VFMps2oq8UKw9W1PrCtlBbdfaxRiIOJGYzkZxlaHVn48V

