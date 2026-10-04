"""BUG-13 follow-up: search_catalog leaks unreviewed merchants.

test_06_rls.py already covers the RLS policy, and that test passes because
migration 109 fixed the policy. It does NOT cover search_catalog, which is the
hole that remains:

    search_catalog is SECURITY DEFINER. A SECURITY DEFINER function executes as
    its owner, which bypasses RLS entirely. Every merchant filter inside it
    checked `m.is_active` alone, so the correct RLS policy protected nothing
    there.

Migration 122 is the fix. These tests are written to FAIL before it and pass
after, and they fail with the specific merchant name rather than a count, so a
regression says which vendor leaked.

Run:
    cd dashborad/test
    uv run pytest test_12_search_approval_gate.py -v

Requires migration 122 applied (local/reset_db.py replays all migrations).
"""

from __future__ import annotations

import json

import pytest

import aliases as A


def _make_merchant(conn, suffix: str, *, approval: str, active: bool, name: str):
    """One merchant, aliased so cleanup-by-pattern can find it."""
    conn.execute(
        """
        INSERT INTO public.merchants
            (id, name_ar, name_en, category, address, city, phone,
             lat, lng, approval_status, is_active, rating, rating_count,
             min_order_amount, estimated_delivery_minutes, delivery_radius_km)
        VALUES
            (%s, %s, %s, 'restaurant', %s, 'Cairo', '01000000000',
             30.0444, 31.2357, %s, %s, 0, 0, 0, 30, 10)
        """,
        (
            A.uid(f"search-gate-{suffix}"),
            name,
            name,
            f"{A.ALIAS_PREFIX} search {suffix}",
            approval,
            active,
        ),
    )


def _add_item(conn, suffix: str, merchant_id, name: str):
    """One item under the merchant's own category.

    Two schema details this has to respect, both verified against the live
    database rather than assumed:
      - items has no rating column; popularity_score is what exists
      - items.category_id references `categories`, not `merchant_categories`,
        and `categories` carries the merchant_id the item must belong to
    """
    conn.execute(
        """
        INSERT INTO public.categories (id, merchant_id, name_ar, name_en, sort_order)
        VALUES (%s, %s, %s, %s, 0)
        ON CONFLICT (id) DO NOTHING
        """,
        (A.uid(f"search-gate-cat-{suffix}"), merchant_id, name, name),
    )
    conn.execute(
        """
        INSERT INTO public.items
            (id, merchant_id, category_id, name_ar, name_en, price, is_available)
        VALUES (%s, %s, %s, %s, %s, 100, true)
        """,
        (
            A.uid(f"search-gate-item-{suffix}"),
            merchant_id,
            A.uid(f"search-gate-cat-{suffix}"),
            name,
            name,
        ),
    )


def _scalar(conn, sql: str, params: tuple = ()):
    """First column of the first row.

    The suite's connections return plain tuples, not dict rows -- confirmed
    rather than assumed, because indexing with a string key fails at runtime
    with 'tuple indices must be integers'.
    """
    return conn.execute(sql, params).fetchone()[0]


def _search(conn, query: str) -> dict:
    """Call the real SECURITY DEFINER function as a normal caller would.

    The 12-argument overload is named explicitly. Migration 121 added a
    9-argument overload with a different parameter order, so an untyped
    single-argument call is genuinely ambiguous -- Postgres says so:
        function public.search_catalog(unknown) is not unique

    Passing all twelve positionally, with casts, is how search-catalog's edge
    function resolves it, so this mirrors production rather than working around
    the ambiguity in the test.
    """
    row = conn.execute(
        """
        SELECT public.search_catalog(
            %s::text, NULL::text, NULL::text, NULL::numeric, NULL::numeric,
            20::int, 10::int, true, 0.30::numeric, NULL::uuid, true, 8::int
        ) AS result
        """,
        (query,),
    ).fetchone()
    payload = row[0]
    return payload if isinstance(payload, dict) else json.loads(payload)


def _names(blob: dict) -> set[str]:
    out: set[str] = set()
    for key in ("merchants", "items"):
        for row in blob.get(key) or []:
            for field in ("name_en", "name"):
                if row.get(field):
                    out.add(str(row[field]))
    return out


# ---------------------------------------------------------------------------
# The four states that must be distinguishable
# ---------------------------------------------------------------------------
@pytest.fixture
def four_states(conn):
    """approved+active, pending+active, approved+inactive, rejected+active."""
    ids = {
        "ok": A.uid("search-gate-ok"),
        "pending": A.uid("search-gate-pending"),
        "inactive": A.uid("search-gate-inactive"),
        "rejected": A.uid("search-gate-rejected"),
    }
    _make_merchant(conn, "ok", approval="approved", active=True, name="Zgate Approved Open")
    _make_merchant(conn, "pending", approval="pending", active=True, name="Zgate Pending Open")
    _make_merchant(conn, "inactive", approval="approved", active=False, name="Zgate Approved Shut")
    _make_merchant(conn, "rejected", approval="rejected", active=True, name="Zgate Rejected Open")

    for key in ids:
        _add_item(conn, key, ids[key], f"Zgate Item {key}")

    yield ids
    for key, mid in ids.items():
        conn.execute("DELETE FROM public.items WHERE id = %s", (A.uid(f"search-gate-item-{key}"),))
        conn.execute("DELETE FROM public.categories WHERE id = %s", (A.uid(f"search-gate-cat-{key}"),))
        conn.execute("DELETE FROM public.merchants WHERE id = %s", (mid,))


# ---------------------------------------------------------------------------
# THE TESTS
# ---------------------------------------------------------------------------
def test_search_hides_pending_but_active_merchant(conn, four_states):
    """The bug itself.

    A pending+active merchant is exactly the state merchant.create produces for
    an unreviewed vendor whose is_active was later flipped by some other path.
    It must not be searchable.
    """
    found = _names(_search(conn, "Zgate"))

    assert "Zgate Approved Open" in found, "approved+active must remain searchable"
    assert "Zgate Pending Open" not in found, (
        "BUG-13 LEAK: a pending merchant was returned by search_catalog. "
        "The SECURITY DEFINER function bypasses the merchants_read_active RLS "
        "policy and filters m.is_active only. Migration 122 adds "
        "AND m.approval_status = 'approved'."
    )


def test_search_hides_rejected_but_active_merchant(conn, four_states):
    """Rejection is a judgement too, and is_active alone does not capture it."""
    found = _names(_search(conn, "Zgate"))

    assert "Zgate Rejected Open" not in found, (
        "BUG-13 LEAK: a rejected merchant was returned by search_catalog."
    )


def test_search_hides_inactive_approved_merchant(conn, four_states):
    """The kill-switch still works. Guards against over-correcting the fix."""
    found = _names(_search(conn, "Zgate"))

    assert "Zgate Approved Shut" not in found, (
        "an approved but is_active=false merchant must stay hidden -- "
        "is_active is the runtime kill-switch and migration 122 must not remove it"
    )


def test_search_hides_items_of_pending_merchant(conn, four_states):
    """Item search joins merchants. The join needs the gate, not just the WHERE.

    A pending merchant's menu leaking into search is the same bug wearing a
    different hat, and it is the more damaging one: items carry prices.
    """
    found = _names(_search(conn, "Zgate Item"))

    assert "Zgate Item ok" in found, "approved merchant's items must be searchable"
    for key in ("pending", "rejected", "inactive"):
        assert f"Zgate Item {key}" not in found, (
            f"BUG-13 LEAK: items of a {key} merchant were returned by "
            f"search_catalog. The JOIN on merchants needs "
            f"AND m.approval_status = 'approved', not only the merchants WHERE."
        )


def test_suggestions_exclude_pending_merchant(conn, four_states):
    """Autocomplete is a customer-visible surface too."""
    blob = _search(conn, "Zgate Pending")
    suggestions = {str(s) for s in (blob.get("suggestions") or [])}

    assert "Zgate Pending Open" not in suggestions, (
        "BUG-13 LEAK: a pending merchant appeared in search suggestions."
    )


def test_rls_policy_alone_does_not_protect_search(conn, four_states):
    """Documents WHY this file exists.

    A direct table read is correctly gated by RLS. Proving that here is what
    makes the search_catalog hole visible: the policy is right, the function
    bypasses it, so testing only the policy gives false confidence.
    """
    # Direct read as the anon role: correctly hidden by migration 109.
    # SET ROLE is issued on its own because psycopg's multi-statement execute
    # returns the result of the LAST statement, and it must not be left as a
    # prepared statement.
    conn.execute("SET LOCAL ROLE anon")
    try:
        leaked_direct = _scalar(
            conn,
            "SELECT count(*) FROM public.merchants "
            "WHERE name_en = 'Zgate Pending Open'",
        )
    finally:
        conn.execute("RESET ROLE")

    assert leaked_direct == 0, (
        "the RLS policy itself regressed -- migration 109 should hide this"
    )

    # Same merchant through search_catalog: the hole migration 122 closes.
    assert "Zgate Pending Open" not in _names(_search(conn, "Zgate")), (
        "search_catalog still leaks what RLS correctly hides"
    )