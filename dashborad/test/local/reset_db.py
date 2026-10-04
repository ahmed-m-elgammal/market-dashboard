"""Rebuild the local `marketak_test` database from the real migrations.

    uv run python local/reset_db.py            # full rebuild
    uv run python local/reset_db.py --keep     # skip teardown, just re-apply

Mirrors `supabase db reset`: drop, recreate, bootstrap Supabase stubs, then
replay supabase/migrations/*.sql in filename order, each in its own transaction.
Any migration that fails is reported with its error; the run then stops before
granting defaults, because a partial schema would make tests lie.

Requires superuser on the local PostgreSQL 18 service. Password comes from
TEST_PG_ADMIN_PASSWORD, else LOCAL_PG_ADMIN_PASSWORD, else 'root'.
"""

from __future__ import annotations

import argparse
import os
import pathlib
import re
import sys

import psycopg

HERE = pathlib.Path(__file__).resolve().parent
MIGRATIONS = HERE.parent.parent.parent / "supabase" / "migrations"
BOOTSTRAP = HERE / "bootstrap.sql"

DB_NAME = "marketak_test"
OWNER = "marketak_test"
OWNER_PASSWORD = "marketak_test"
ROLES = ("anon", "authenticated", "service_role")

# Extensions Supabase provides that a vanilla PostgreSQL 18 install cannot.
# Each is replaced with a comment; bootstrap.sql supplies a shim instead.
# This matters most for `postgis`: migration 001 creates postgis FIRST, so when
# it fails the whole migration rolls back and `pg_trgm` never gets installed,
# which then breaks every trigram index in 016 and 095.
UNAVAILABLE_EXTENSIONS = (
    "postgis",
    "pg_cron",
    "supabase_vault",
    "pg_net",
    "pgmq",
    "pgsodium",
    "pg_graphql",
    "supabase_pgjwt",
)

_CREATE_EXT = re.compile(
    r"^\s*CREATE\s+EXTENSION\s+(IF\s+NOT\s+EXISTS\s+)?"
    r'(?:"(?P<q>[^"]+)"|(?P<u>\w+))\s*;',
    re.IGNORECASE | re.MULTILINE,
)


def sanitize(sql: str) -> str:
    """Neutralise CREATE EXTENSION for extensions unavailable locally."""

    def repl(m: re.Match) -> str:
        name = (m.group("q") or m.group("u") or "").lower()
        if name in UNAVAILABLE_EXTENSIONS:
            return f"-- [local] skipped CREATE EXTENSION {name} (shimmed in bootstrap.sql)"
        return m.group(0)

    return _CREATE_EXT.sub(repl, sql)


def admin_dsn() -> str:
    pw = (
        os.environ.get("TEST_PG_ADMIN_PASSWORD")
        or os.environ.get("LOCAL_PG_ADMIN_PASSWORD")
        or "root"
    )
    host = os.environ.get("LOCAL_PG_HOST", "127.0.0.1")
    port = os.environ.get("LOCAL_PG_PORT", "5432")
    return f"postgresql://postgres:{pw}@{host}:{port}/postgres"


def test_dsn() -> str:
    host = os.environ.get("LOCAL_PG_HOST", "127.0.0.1")
    port = os.environ.get("LOCAL_PG_PORT", "5432")
    return (
        f"postgresql://{OWNER}:{OWNER_PASSWORD}@{host}:{port}/{DB_NAME}"
        "?sslmode=disable"
    )


def ensure_cluster_objects() -> None:
    """Roles are cluster-wide and only superuser may create them, so this runs
    on the admin connection regardless of --keep.

    The GRANT is what lets the test role `SET ROLE anon`; without it every RLS
    test errors with 'permission denied to set role'."""
    with psycopg.connect(admin_dsn(), autocommit=True) as conn:
        with conn.cursor() as cur:
            for role in ROLES:
                if not cur.execute(
                    "SELECT 1 FROM pg_roles WHERE rolname = %s", (role,)
                ).fetchone():
                    cur.execute(f'CREATE ROLE "{role}" NOLOGIN NOINHERIT')
                    print(f"  created role {role}")
            if cur.execute("SELECT 1 FROM pg_roles WHERE rolname = %s", (OWNER,)).fetchone():
                for role in ROLES:
                    cur.execute(f'GRANT "{role}" TO "{OWNER}"')


def drop_and_create() -> None:
    ensure_cluster_objects()
    with psycopg.connect(admin_dsn(), autocommit=True) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT pg_terminate_backend(pid)
                FROM pg_stat_activity
                WHERE datname = %s AND pid <> pg_backend_pid()
                """,
                (DB_NAME,),
            )
            cur.execute(f'DROP DATABASE IF EXISTS "{DB_NAME}"')
            print(f"  dropped database {DB_NAME}")

            if not cur.execute(
                "SELECT 1 FROM pg_roles WHERE rolname = %s", (OWNER,)
            ).fetchone():
                # CREATE ROLE takes no bind parameters; the literal is a fixed
                # throwaway constant for the local test database only.
                cur.execute(f"""CREATE ROLE "{OWNER}" LOGIN PASSWORD '{OWNER_PASSWORD}'""")
                print(f"  created role {OWNER}")

            cur.execute(f'CREATE DATABASE "{DB_NAME}" OWNER "{OWNER}"')
            print(f"  created database {DB_NAME} owned by {OWNER}")


def apply_default_privileges() -> None:
    """Model Supabase's default privileges the way Supabase actually applies
    them: at OBJECT CREATION time.

    This must run BEFORE the migrations, not after. Granting afterwards would
    re-grant EXECUTE on every function, undoing the explicit REVOKEs that
    migrations 069 and 120 rely on -- and the tests for those grants would then
    pass or fail for the wrong reason.

    Supabase grants anon and authenticated broad access by default, which is
    precisely why migrations must revoke explicitly.
    """
    with psycopg.connect(test_dsn(), autocommit=True) as conn:
        with conn.cursor() as cur:
            for role in ROLES:
                cur.execute(
                    f'ALTER DEFAULT PRIVILEGES IN SCHEMA public '
                    f'GRANT ALL ON TABLES TO "{role}"'
                )
                cur.execute(
                    f'ALTER DEFAULT PRIVILEGES IN SCHEMA public '
                    f'GRANT ALL ON SEQUENCES TO "{role}"'
                )
                cur.execute(
                    f'ALTER DEFAULT PRIVILEGES IN SCHEMA public '
                    f'GRANT EXECUTE ON FUNCTIONS TO "{role}"'
                )
                cur.execute(f'GRANT USAGE ON SCHEMA public TO "{role}"')
            print("  applied Supabase default privileges (pre-migration, as Supabase does)")


def grant_table_privileges() -> None:
    """Schema-level USAGE only.

    Table and function privileges now come from the ALTER DEFAULT PRIVILEGES
    set before the replay, matching production. Granting them again here would
    silently override migration 120's REVOKE ... FROM anon, authenticated.
    """
    with psycopg.connect(test_dsn(), autocommit=True) as conn:
        with conn.cursor() as cur:
            for role in ROLES:
                cur.execute(f'GRANT USAGE ON SCHEMA public TO "{role}"')
            print("  applied schema usage grants")


def apply_sql(conn, sql: str) -> None:
    with conn.cursor() as cur:
        cur.execute(sql)


def replay() -> list[str]:
    files = sorted(MIGRATIONS.glob("*.sql"))
    if not files:
        sys.exit(f"no migrations found in {MIGRATIONS}")

    applied: list[str] = []
    failures: list[tuple[str, str]] = []

    with psycopg.connect(test_dsn(), autocommit=False) as conn:
        apply_sql(conn, BOOTSTRAP.read_text(encoding="utf-8"))
        conn.commit()
        print("  bootstrap.sql applied")

    # Defaults BEFORE the replay, so a migration's REVOKE is the last word --
    # exactly the production ordering.
    apply_default_privileges()

    with psycopg.connect(test_dsn(), autocommit=False) as conn:
        for path in files:
            sql = path.read_text(encoding="utf-8", errors="replace")
            try:
                with conn.cursor() as cur:
                    cur.execute(sanitize(sql))
                conn.commit()
                applied.append(path.name)
            except Exception as exc:  # noqa: BLE001 - report every failure
                conn.rollback()
                msg = str(exc).strip().splitlines()[0]
                failures.append((path.name, msg))
                print(f"  FAIL {path.name}: {msg}")

    print(f"\napplied {len(applied)}/{len(files)} migrations")
    if failures:
        print(f"{len(failures)} failed -- NOT granting defaults, schema is partial:")
        for name, msg in failures:
            print(f"  - {name}: {msg}")
        return [n for n, _ in failures]

    grant_table_privileges()
    return []


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--keep",
        action="store_true",
        help="do not drop the database first",
    )
    args = parser.parse_args()

    print(f"target: {test_dsn()}")
    if not args.keep:
        print("teardown:")
        drop_and_create()
    else:
        ensure_cluster_objects()
    print("replay:")
    failures = replay()
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())