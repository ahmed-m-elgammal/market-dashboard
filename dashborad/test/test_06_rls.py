"""Test 06 -- RLS: what the admin dashboard can and cannot read or write.

The dashboard is the only writer of the catalog. These tests pin the exact
access surface so a future migration that tightens or loosens a policy is caught.

Model under test (migrations 019 / 020 / 096 / 097):
  - catalog READ policies are USING (TRUE)      -> public
  - catalog has NO write policy                 -> service_role only
  - merchants_read_active filters is_active     -> inactive rows invisible
  - reviews_read_visible filters is_visible     -> moderation queue invisible
  - audit_logs / admin_sessions have ZERO policies
"""

from __future__ import annotations

import uuid

import pytest

from conftest import (
    insert_merchant,
    make_customer,
    policies,
    rls_enabled,
    scalar,
    set_role,
)

ANON = "anon"
AUTHENTICATED = "authenticated"


@pytest.fixture
def customer(conn) -> uuid.UUID:
    return make_customer(conn)


def _as_role(conn, role: str, user_id: uuid.UUID | None = None):
    set_role(conn, role, user_id)


def select_policy(conn, table: str):
    """The table's SELECT policy. A table can carry several policies, so index
    by command rather than assuming a single row."""
    for row in policies(conn, table):
        if row[1] == "r":
            return row
    raise AssertionError(f"no SELECT policy on {table}: {policies(conn, table)}")


# ---------------------------------------------------------------------------
# RLS is on everywhere
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "table",
    [
        "merchants",
        "categories",
        "items",
        "item_options",
        "item_option_choices",
        "operating_hours",
        "reviews",
        "audit_logs",
        "admin_sessions",
        "merchant_categories",
    ],
)
def test_rls_enabled(conn, table):
    assert rls_enabled(conn, table), f"{table} must have RLS enabled (CI enforces this)"


# ---------------------------------------------------------------------------
# merchants: active-only visibility
# ---------------------------------------------------------------------------


def test_inactive_merchants_are_invisible_to_anonymous(conn):
    insert_merchant(conn.cursor(), "DBX-rls-active", "restaurant", True, "approved")
    insert_merchant(conn.cursor(), "DBX-rls-inactive", "restaurant", False, "approved")

    _as_role(conn, ANON)
    names = [
        r[0]
        for r in conn.execute("SELECT name_en FROM public.merchants").fetchall()
    ]
    assert "[DBX-rls-active]" in names
    assert "[DBX-rls-inactive]" not in names, (
        "expected BUG: the dashboard CANNOT list deactivated merchants without "
        "the service_role client"
    )


def test_pending_approval_merchants_are_hidden_from_anonymous(conn):
    """BUG-13, real and unfixed.

    merchants_read_active is `(is_active = true)` and nothing else. Migration
    103 introduced approval_status with pending = "new place awaiting Ops", and
    the dashboard creates new merchants as pending -- but they default to
    is_active = TRUE, so the public feed and search expose a vendor Ops has not
    approved yet.

    Correct predicate would be:
        USING (is_active = true AND approval_status = 'approved')
    """
    insert_merchant(conn.cursor(), "DBX-rls-pending", "bakery", True, "approved")
    insert_merchant(conn.cursor(), "DBX-rls-pending2", "bakery", True, "pending")
    approved = insert_merchant(
        conn.cursor(), "DBX-rls-approved", "bakery", True, "approved"
    )

    _as_role(conn, ANON)
    assert scalar(
        conn, "SELECT count(*) FROM public.merchants WHERE id=%s", (approved,)
    ) == 1, "an approved active merchant is still publicly visible"
    # Scoped to this test's own fixture so seeded rows cannot skew the count.
    leaked = scalar(
        conn,
        "SELECT count(*) FROM public.merchants WHERE name_en = '[DBX-rls-pending2]'",
    )
    assert leaked == 0, (
        "migration 109 requires is_active AND approval_status='approved', so a "
        "pending merchant must not be publicly readable"
    )


# ---------------------------------------------------------------------------
# catalog: public read, no client writes
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "table", ["categories", "items", "item_options", "item_option_choices"]
)
def test_catalog_read_policy_is_public(conn, table):
    names = [p[0] for p in policies(conn, table)]
    assert len(names) == 1, f"{table} should have exactly one policy, got {names}"
    _name, cmd, roles, qual = policies(conn, table)[0]
    assert cmd == "r", f"{table} policy should be SELECT-only, got {cmd}"
    assert qual == "true", f"{table} policy should be USING (TRUE), got {qual}"


@pytest.mark.parametrize(
    "table", ["categories", "items", "item_options", "item_option_choices", "merchants"]
)
def test_no_client_write_policy_on_catalog(conn, table):
    """No INSERT/UPDATE/DELETE policy => anon and authenticated are denied by
    RLS. The dashboard must therefore use the service_role client for every
    catalog mutation."""
    cmds = {p[1] for p in policies(conn, table)}
    assert not (cmds & {"a", "w", "d"}), (
        f"{table} exposes write policies {cmds}; the dashboard's write path "
        "assumption (service_role only) has changed"
    )


def test_anonymous_cannot_write_the_catalog(conn):
    """No INSERT/UPDATE/DELETE policy exists, so RLS denies the write.

    The target merchant must exist BEFORE the role switch: an INSERT whose
    source SELECT returns no rows inserts nothing and never evaluates the
    policy, which would make this test pass without testing anything.
    """
    insert_merchant(conn.cursor(), "DBX-rls-target", "restaurant", True, "approved")

    _as_role(conn, ANON)
    visible = scalar(conn, "SELECT count(*) FROM public.merchants")
    assert visible >= 1, "sanity: anon can see the active merchant"

    with pytest.raises(Exception) as exc:
        conn.execute(
            """
            INSERT INTO public.categories (merchant_id, name_ar, name_en)
            SELECT id, 'x', 'DBX-rls-write' FROM public.merchants
            """
        )
    assert "row-level security" in str(exc.value).lower()


# ---------------------------------------------------------------------------
# reviews moderation gate
# ---------------------------------------------------------------------------


def test_review_read_policy_gates_on_visibility(conn):
    _name, cmd, roles, qual = select_policy(conn, "reviews")
    assert cmd == "r"
    assert "is_visible" in qual
    assert "customer_id" in qual, (
        "106 lets an author read their own pending review -- expected"
    )


# ---------------------------------------------------------------------------
# service-role-only tables
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("table", ["audit_logs", "admin_sessions"])
def test_internal_tables_have_zero_policies(conn, table):
    assert policies(conn, table) == [], (
        f"{table} must have NO policies (service-role only)"
    )


def test_service_role_bypasses_rls(conn):
    """Sanity: the superuser-ish path sees everything, which is what makes the
    service_role client viable for the dashboard."""
    insert_merchant(conn.cursor(), "DBX-rls-svc", "restaurant", False, "approved")
    n = scalar(
        conn,
        "SELECT count(*) FROM public.merchants WHERE name_en='[DBX-rls-svc]'",
    )
    assert n == 1


# ---------------------------------------------------------------------------
# merchant_categories: read active, write service-role only
# ---------------------------------------------------------------------------


def test_merchant_categories_read_is_active_only(conn):
    _name, cmd, roles, qual = select_policy(conn, "merchant_categories")
    assert cmd == "r"
    assert "is_active" in qual


def test_inactive_merchant_category_is_hidden(conn):
    """Hiding a vendor type must not break existing merchants -- the FK stays
    valid, only the label disappears from client reads."""
    conn.execute(
        "UPDATE public.merchant_categories SET is_active=false WHERE code='butcher'"
    )
    _as_role(conn, ANON)
    codes = [
        r[0] for r in conn.execute("SELECT code FROM public.merchant_categories").fetchall()
    ]
    assert "butcher" not in codes
    assert "restaurant" in codes


def test_merchant_categories_has_no_write_policy(conn):
    cmds = {p[1] for p in policies(conn, "merchant_categories")}
    assert not (cmds & {"a", "w", "d"})
