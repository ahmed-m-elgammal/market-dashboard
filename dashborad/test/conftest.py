"""Pytest configuration: connection, transaction isolation, alias fixtures.

Safety model
------------
1. Every test runs inside a transaction that is ROLLED BACK in teardown. A test
   that crashes still leaves nothing behind.
2. Fixtures are additionally aliased (see aliases.py) and cleaned by pattern, so
   residue from an aborted run is one DELETE away.
3. `guard_live_db` refuses to run if the target looks like a database holding
   data this suite did not create -- it snapshots counts and asserts we only
   ever touch our own aliases.

Connection target
-----------------
DEFAULT: the local `marketak_test` database (see local/reset_db.py). Zero
network, zero Supabase quota. Override with TEST_DATABASE_URL only when you
deliberately want to point at a real project.

Why the local default: the Supabase free plan was over its 100GB egress
allowance, so every assertion against the cloud project costs money. The local
database is built by replaying all 105 real migrations over the Supabase stubs
in local/bootstrap.sql, so the schema under test is the production schema.
"""

from __future__ import annotations

import os
import pathlib
import re
import uuid

import psycopg
import pytest

import aliases as A

HERE = pathlib.Path(__file__).parent
LOCAL_DSN = "postgresql://marketak_test:marketak_test@127.0.0.1:5432/marketak_test?sslmode=disable"


def _database_url() -> str:
    url = os.environ.get("TEST_DATABASE_URL")
    if url:
        return url
    host = os.environ.get("LOCAL_PG_HOST")
    if host:
        port = os.environ.get("LOCAL_PG_PORT", "5432")
        return f"postgresql://marketak_test:marketak_test@{host}:{port}/marketak_test?sslmode=disable"
    return LOCAL_DSN


@pytest.fixture(scope="session")
def database_url() -> str:
    return _database_url()


@pytest.fixture(scope="session")
def _session_conn(database_url: str):
    # prepare_threshold=None disables psycopg3's automatic prepared statements.
    # They matter here: test_08 creates and drops indexes mid-test, and a cached
    # generic plan would keep using the pre-index plan and make the assertions
    # order-dependent.
    conn = psycopg.connect(database_url, autocommit=False, prepare_threshold=None)
    yield conn
    conn.close()


@pytest.fixture
def conn(_session_conn):
    """Transaction-scoped connection. Always rolled back.

    Explicit SQL BEGIN/ROLLBACK rather than psycopg's transaction() object:
    plain SQL survives a mid-test conn.rollback() (needed to inspect the error
    state after a constraint violation) as long as the test re-BEGINs.
    """
    _session_conn.execute("BEGIN")
    try:
        yield _session_conn
    finally:
        _session_conn.execute("ROLLBACK")


def begin(conn) -> None:
    """Re-open a transaction after a test aborted it (e.g. via conn.rollback()
    to inspect state after a constraint violation)."""
    conn.rollback()
    conn.execute("BEGIN")


@pytest.fixture(scope="session")
def schema_snapshot(_session_conn):
    """Live introspection of the DB under test. Read-only, no writes."""
    with _session_conn.cursor() as cur:
        cur.execute("SET TRANSACTION READ ONLY")
        cur.execute(
            """
            SELECT c.relname, a.attname, format_type(a.atttypid, a.atttypmod),
                   a.attnotnull, pg_get_expr(d.adbin, d.adrelid)
            FROM pg_attribute a
            JOIN pg_class c ON c.oid = a.attrelid
            JOIN pg_namespace n ON n.oid = c.relnamespace
            LEFT JOIN pg_attrdef d
                   ON d.adrelid = a.attrelid AND d.adnum = a.attnum
            WHERE c.relkind IN ('r','m')
              AND n.nspname = 'public'
              AND a.attnum > 0 AND NOT a.attisdropped
              AND c.relname = ANY(%s)
            ORDER BY c.relname, a.attnum
            """,
            (
                [
                    "merchants",
                    "categories",
                    "items",
                    "item_options",
                    "item_option_choices",
                    "operating_hours",
                    "merchant_categories",
                    "orders",
                    "order_items",
                    "reviews",
                    "merchants_with_open_status",
                ],
            ),
        )
        return cur.fetchall()


# ---------------------------------------------------------------------------
# Assertion helpers
# ---------------------------------------------------------------------------


def columns(snapshot, table: str) -> dict[str, dict]:
    """{column_name: {type, notnull, default}} for one table."""
    out: dict[str, dict] = {}
    for rel, att, typ, notnull, default in snapshot:
        if rel == table:
            out[att] = {"type": typ, "notnull": notnull, "default": default}
    return out


def check_constraints(conn) -> list[tuple[str, str, str]]:
    """(table, name, definition) for every CHECK constraint in public."""
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT rel.relname, con.conname,
                   pg_get_constraintdef(con.oid)
            FROM pg_constraint con
            JOIN pg_class rel ON rel.oid = con.conrelid
            JOIN pg_namespace n ON n.oid = rel.relnamespace
            WHERE con.contype = 'c' AND n.nspname = 'public'
            ORDER BY rel.relname, con.conname
            """
        )
        return cur.fetchall()


def foreign_keys(conn) -> list[tuple[str, str, str, str]]:
    """(child_table, constraint_name, child_cols, parent) for every FK."""
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT child.relname, con.conname,
                   (SELECT string_agg(att.attname, ',' ORDER BY att.attnum)
                      FROM unnest(con.conkey) k
                      JOIN pg_attribute att
                        ON att.attrelid = child.oid AND att.attnum = k),
                   parent.relname
            FROM pg_constraint con
            JOIN pg_class child  ON child.oid = con.conrelid
            JOIN pg_class parent ON parent.oid = con.confrelid
            JOIN pg_namespace n ON n.oid = child.relnamespace
            WHERE con.contype = 'f' AND n.nspname = 'public'
            ORDER BY child.relname, con.conname
            """
        )
        return cur.fetchall()


def indexes(conn) -> list[tuple[str, str, str]]:
    """(table, index_name, definition) for every index in public."""
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT tablename, indexname, indexdef
            FROM pg_indexes
            WHERE schemaname = 'public'
            ORDER BY tablename, indexname
            """
        )
        return cur.fetchall()


def rls_enabled(conn, table: str) -> bool:
    with conn.cursor() as cur:
        cur.execute(
            "SELECT relrowsecurity FROM pg_class WHERE relname = %s", (table,)
        )
        row = cur.fetchone()
        return bool(row and row[0])


def make_customer(conn) -> uuid.UUID:
    """Create a customer.

    Insert into auth.users ONLY -- migration 002's on_auth_user_created trigger
    creates the matching public.profiles row. Inserting profiles directly raises
    a duplicate-key error on profiles_pkey.
    """
    uid = uuid.uuid4()
    conn.execute("INSERT INTO auth.users (id) VALUES (%s)", (uid,))
    return uid


def set_role(conn, role: str, user_id: uuid.UUID | None = None) -> None:
    """Impersonate a Postgres role for RLS testing."""
    conn.execute(f"SET LOCAL ROLE {role}")
    if user_id is not None:
        conn.execute(
            "SELECT set_config('request.jwt.claims', %s, true)",
            (f'{{"sub":"{user_id}","role":"{role}"}}',),
        )
        conn.execute(
            "SELECT set_config('request.jwt.claim.sub', %s, true)", (str(user_id),)
        )


def policies(conn, table: str) -> list[tuple[str, str, str, str]]:
    """(name, cmd, roles, qual) for each policy on a table."""
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT pol.polname, pol.polcmd,
                   CASE WHEN pol.polroles = '{0}' THEN 'PUBLIC'
                        ELSE (SELECT string_agg(r.rolname, ',')
                                FROM pg_roles r WHERE r.oid = ANY(pol.polroles))
                   END,
                   pg_get_expr(pol.polqual, pol.polrelid)
            FROM pg_policy pol
            JOIN pg_class c ON c.oid = pol.polrelid
            WHERE c.relname = %s
            ORDER BY pol.polname
            """,
            (table,),
        )
        return cur.fetchall()


def scalar(conn, sql: str, params=()):
    with conn.cursor() as cur:
        cur.execute(sql, params)
        row = cur.fetchone()
        return row[0] if row else None


# ---------------------------------------------------------------------------
# Fixture-data builders (used by tests that need live rows)
# ---------------------------------------------------------------------------


def insert_merchant(cur, alias: str, category: str, is_active: bool, approval: str):
    cur.execute(
        """
        INSERT INTO public.merchants
            (name_ar, name_en, category, address, lat, lng, city, area,
             phone, is_active, approval_status)
        VALUES (%s, %s, %s, %s, 30.0444, 31.2357, 'Cairo', 'TestDistrict',
                '+201000000000', %s, %s)
        ON CONFLICT (id) DO UPDATE
          SET name_en = EXCLUDED.name_en, is_active = EXCLUDED.is_active,
              approval_status = EXCLUDED.approval_status
        RETURNING id
        """,
        (A.ar(alias), A.en(alias), category, f"{alias} street", is_active, approval),
    )
    return cur.fetchone()[0]


def insert_category(cur, alias: str, merchant_id: uuid.UUID, sort_order: int = 1):
    cur.execute(
        """
        INSERT INTO public.categories (merchant_id, name_ar, name_en, sort_order)
        VALUES (%s, %s, %s, %s)
        RETURNING id
        """,
        (merchant_id, A.ar(alias), A.en(alias), sort_order),
    )
    return cur.fetchone()[0]


def insert_item(cur, alias, merchant_id, category_id, price=45.00, is_available=True):
    cur.execute(
        """
        INSERT INTO public.items
            (merchant_id, category_id, name_ar, name_en, price, is_available)
        VALUES (%s, %s, %s, %s, %s, %s)
        RETURNING id
        """,
        (merchant_id, category_id, A.ar(alias), A.en(alias), price, is_available),
    )
    return cur.fetchone()[0]


def insert_option(cur, alias, item_id, is_required, min_sel, max_sel, sort_order=1):
    cur.execute(
        """
        INSERT INTO public.item_options
            (item_id, name_ar, name_en, is_required, min_selections,
             max_selections, sort_order)
        VALUES (%s, %s, %s, %s, %s, %s, %s)
        RETURNING id
        """,
        (item_id, A.ar(alias), A.en(alias), is_required, min_sel, max_sel, sort_order),
    )
    return cur.fetchone()[0]


def insert_choice(cur, alias, option_id, price_modifier=0.00, is_default=False, is_available=True):
    cur.execute(
        """
        INSERT INTO public.item_option_choices
            (option_id, name_ar, name_en, price_modifier, is_default, is_available)
        VALUES (%s, %s, %s, %s, %s, %s)
        RETURNING id
        """,
        (option_id, A.ar(alias), A.en(alias), price_modifier, is_default, is_available),
    )
    return cur.fetchone()[0]