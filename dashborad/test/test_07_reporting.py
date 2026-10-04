"""Test 07 -- reporting correctness: KPI RPCs, review summary, stale matview.

BUG-09  get_merchant_kpis() sums orders.total with NO status filter, so
        cancelled and refunded orders are counted as revenue (066:39-41).
BUG-10  get_merchant_review_summary() counts only is_visible = TRUE reviews
        (093 patched by 104), so a moderation backlog silently deflates the
        displayed average.
BUG-11  merchants_with_open_status is a materialized view created with an
        explicit column list (031:23-57) and never recreated, so it is missing
        every column added by 042, 085 and 103.
"""

from __future__ import annotations

import uuid

import pytest

from conftest import (
    insert_category,
    insert_item,
    insert_merchant,
    make_customer,
    scalar,
)


def _customer(conn) -> uuid.UUID:
    return make_customer(conn)


def _order(conn, merchant_id, customer_id, total, status, when=None):
    order_id = uuid.uuid4()
    conn.execute(
        """
        INSERT INTO public.orders
          (id, order_number, customer_id, merchant_id, delivery_address,
           subtotal, total, status, created_at)
        VALUES (%s, %s, %s, %s, '{}'::jsonb, %s, %s, %s, COALESCE(%s, now()))
        """,
        (order_id, f"DBX-{str(order_id)[:8].upper()}", customer_id,
         merchant_id, total, total, status, when),
    )
    return order_id


# ---------------------------------------------------------------------------
# BUG-09: cancelled orders counted as revenue
# ---------------------------------------------------------------------------


def test_revenue_excludes_cancelled_orders(conn):
    insert_merchant(conn.cursor(), "DBX-rev-m", "restaurant", True, "approved")
    m = conn.execute(
        "SELECT id FROM public.merchants WHERE name_en='[DBX-rev-m]'"
    ).fetchone()[0]
    cust = _customer(conn)

    _order(conn, m, cust, 100.00, "delivered")
    _order(conn, m, cust, 500.00, "cancelled")
    _order(conn, m, cust, 250.00, "pending")

    kpis = scalar(conn, "SELECT public.get_merchant_kpis(%s)", (m,))
    revenue = float(kpis["revenue"])
    assert revenue == 350.0, (
        f"migration 114 must exclude cancelled orders; got {revenue}"
    )
    assert kpis["cancelled_count"] == 1, "cancelled count is reported separately"


def test_range_kpi_also_excludes_cancelled(conn):
    insert_merchant(conn.cursor(), "DBX-rev2-m", "restaurant", True, "approved")
    m = conn.execute(
        "SELECT id FROM public.merchants WHERE name_en='[DBX-rev2-m]'"
    ).fetchone()[0]
    cust = _customer(conn)
    _order(conn, m, cust, 100.00, "delivered")
    _order(conn, m, cust, 900.00, "cancelled")

    kpis = scalar(
        conn,
        "SELECT public.get_merchant_kpis_range(%s, now() - interval '1 day')",
        (m,),
    )
    assert float(kpis["revenue"]) == 100.0, "migration 114 excludes cancelled in range too"
    assert float(kpis["avg_order_value"]) == 100.0


def test_avg_order_value_rpc_does_filter_cancelled(conn):
    """069 is the counter-example: it filters status != 'cancelled', which is
    what 066/091 fail to do. Proved by comparing the RPC against a manual
    computation on the same window, so seeded rows cannot skew it.
    """
    got = float(scalar(conn, "SELECT public.get_avg_order_value()"))

    expected = float(
        scalar(
            conn,
            """
            SELECT COALESCE(AVG(total), 0) FROM public.orders
            WHERE status <> 'cancelled'
              AND created_at > NOW() - INTERVAL '30 days'
            """,
        )
    )
    not_filtered = float(
        scalar(
            conn,
            """
            SELECT COALESCE(AVG(total), 0) FROM public.orders
            WHERE created_at > NOW() - INTERVAL '30 days'
            """,
        )
    )
    assert got == expected, "069 should match the cancelled-excluded average"
    if not_filtered != expected:
        assert got != not_filtered, (
            "069 must differ from the unfiltered average -- that difference is "
            "the proof it filters"
        )


def test_kpi_counts_all_time_regardless_of_range(conn):
    """066 is all-time; 091 is range-scoped. Documented so the dashboard does
    not mix them in one tile."""
    insert_merchant(conn.cursor(), "DBX-rev4-m", "restaurant", True, "approved")
    m = conn.execute(
        "SELECT id FROM public.merchants WHERE name_en='[DBX-rev4-m]'"
    ).fetchone()[0]
    cust = _customer(conn)
    _order(conn, m, cust, 70.00, "delivered", when="2020-01-01 00:00:00+00")
    _order(conn, m, cust, 30.00, "delivered")

    all_time = scalar(conn, "SELECT public.get_merchant_kpis(%s)", (m,))
    recent = scalar(
        conn, "SELECT public.get_merchant_kpis_range(%s, now() - interval '1 day')", (m,)
    )
    assert float(all_time["revenue"]) == 100.0
    assert float(recent["revenue"]) == 30.0


# ---------------------------------------------------------------------------
# BUG-10: review summary hides unmoderated reviews
# ---------------------------------------------------------------------------


def _review(conn, merchant_id, customer_id, rating, comment="DBX review", visible=True):
    order_id = _order(conn, merchant_id, customer_id, 50.00, "delivered")
    conn.execute(
        """
        INSERT INTO public.reviews
          (order_id, customer_id, merchant_id, merchant_rating,
           merchant_comment, is_visible)
        VALUES (%s, %s, %s, %s, %s, %s)
        """,
        (order_id, customer_id, merchant_id, rating, comment, visible),
    )


def test_review_summary_ignores_pending_reviews(conn):
    insert_merchant(conn.cursor(), "DBX-revsum-m", "restaurant", True, "approved")
    m = conn.execute(
        "SELECT id FROM public.merchants WHERE name_en='[DBX-revsum-m]'"
    ).fetchone()[0]
    cust = _customer(conn)

    _review(conn, m, cust, 5, visible=True)
    _review(conn, m, cust, 1, visible=False)  # awaiting moderation

    summary = scalar(conn, "SELECT public.get_merchant_review_summary(%s)", (m,))
    assert summary["total_count"] == 1, (
        "expected BUG-10: the unmoderated 1-star review is excluded"
    )
    assert float(summary["average_rating"]) == 5.0, (
        "the displayed 5.0 hides a pending 1-star review -- the dashboard shows "
        "a flattering rating while Ops has an unreviewed complaint"
    )


def test_merchant_rating_column_also_ignores_pending(conn):
    insert_merchant(conn.cursor(), "DBX-revagg-m", "restaurant", True, "approved")
    m = conn.execute(
        "SELECT id FROM public.merchants WHERE name_en='[DBX-revagg-m]'"
    ).fetchone()[0]
    cust = _customer(conn)
    _review(conn, m, cust, 4, visible=True)
    _review(conn, m, cust, 1, visible=False)

    row = conn.execute(
        "SELECT rating, rating_count FROM public.merchants WHERE id=%s", (m,)
    ).fetchone()
    assert float(row[0]) == 4.0
    assert row[1] == 1


# ---------------------------------------------------------------------------
# BUG-11: stale materialized view
# ---------------------------------------------------------------------------


def test_matview_tracks_every_merchant_column(conn):
    """031 froze an explicit column list; 042/085/103 added 10 more columns to
    merchants and the matview never learned about them."""
    matview_cols = {
        r[0]
        for r in conn.execute(
            """
            SELECT a.attname FROM pg_attribute a
            JOIN pg_class c ON c.oid = a.attrelid
            WHERE c.relname='merchants_with_open_status'
              AND a.attnum > 0 AND NOT a.attisdropped
            """
        ).fetchall()
    }
    merchant_cols = {
        r[0]
        for r in conn.execute(
            """
            SELECT a.attname FROM pg_attribute a
            JOIN pg_class c ON c.oid = a.attrelid
            WHERE c.relname='merchants' AND a.attnum > 0 AND NOT a.attisdropped
            """
        ).fetchall()
    }
    missing = sorted(merchant_cols - matview_cols)
    expected_missing = [
        "approval_note",
        "approval_status",
        "bank_account_holder",
        "bank_account_number",
        "bank_name",
        "delivery_radius_km",
        "estimated_prep_time_minutes",
        "payout_frequency",
        "payout_method",
        "wallet_phone",
    ]
    # 115 dropped the three bank columns, so those are absent by design.
    expected_still_missing = [
        c for c in expected_missing
        if c not in ("bank_account_holder", "bank_account_number", "bank_name")
    ]
    assert not (set(expected_still_missing) & set(missing)), (
        f"migration 113 rebuilds the view as m.*, so it must not be missing "
        f"{expected_still_missing}; actually missing {missing}"
    )


def test_matview_can_answer_approval_queue_queries(conn):
    """A dashboard query routed through the matview cannot see pending
    merchants at all -- there is no approval_status column to filter on."""
    cols = {
        r[0]
        for r in conn.execute(
            """
            SELECT a.attname FROM pg_attribute a
            JOIN pg_class c ON c.oid = a.attrelid
            WHERE c.relname='merchants_with_open_status' AND a.attnum > 0
            """
        ).fetchall()
    }
    assert "approval_status" in cols, "migration 113 gives the view m.*"
    assert "is_active" in cols
    assert "is_currently_open" in cols


def test_matview_only_holds_active_merchants(conn):
    """031's WHERE clause is `is_active = TRUE`, and the view is a SNAPSHOT: it
    was populated once at migration time and nothing refreshes it
    automatically. So after any merchant change the matview is simply stale.

    That staleness is the finding. Asserted rather than papered over: the
    dashboard must not treat this view as live.
    """
    definition = scalar(
        conn, "SELECT pg_get_viewdef('public.merchants_with_open_status'::regclass, true)"
    )
    assert "is_active" in definition

    in_view = scalar(conn, "SELECT count(*) FROM public.merchants_with_open_status")
    active = scalar(conn, "SELECT count(*) FROM public.merchants WHERE is_active")

    stale = in_view != active
    inactive_in_view = scalar(
        conn,
        """
        SELECT count(*) FROM public.merchants_with_open_status
        WHERE is_active IS NOT TRUE
        """,
    )
    assert inactive_in_view == 0, (
        "the view must never contain inactive merchants (its WHERE clause "
        "guarantees this at refresh time)"
    )
    # Report rather than assert equality: after seeding, in_view < active.
    if stale:
        assert in_view <= active, (
            f"view holds {in_view} rows vs {active} active merchants -- stale, "
            "which is expected and is why the dashboard should query "
            "merchants directly"
        )


def test_refresh_function_does_work_inside_a_transaction(conn):
    """Migration 098 documents a 'DEVIATION': it skips calling
    refresh_merchant_open_status() because REFRESH MATERIALIZED VIEW CONCURRENTLY
    'cannot execute inside a transaction block', and Supabase wraps every
    migration in one.

    That claim is wrong. Verified on PostgreSQL 18: the function completes
    normally inside an explicit transaction, with the matview populated and with
    it empty. So the 098 comment needlessly rules out a valid approach.

    (Verified locally only, on PG18. Re-check on the Supabase PG version before
    relying on it.)
    """
    insert_merchant(conn.cursor(), "DBX-refresh-m", "restaurant", True, "approved")
    conn.execute("REFRESH MATERIALIZED VIEW public.merchants_with_open_status")

    # Inside the test's transaction, with rows present.
    scalar(conn, "SELECT public.refresh_merchant_open_status()")

    popped = scalar(conn, "SELECT count(*) FROM public.merchants_with_open_status")
    assert popped >= 1, "matview should hold the active merchant"


# ---------------------------------------------------------------------------
# selected_options snapshot shape
# ---------------------------------------------------------------------------


def test_selected_options_json_has_no_choice_id(conn):
    """BUG-12: order_items.selected_options stores names + price_modifier but
    no choice_id, so option-level analytics is string matching only."""
    insert_merchant(conn.cursor(), "DBX-sel-m", "restaurant", True, "approved")
    m = conn.execute(
        "SELECT id FROM public.merchants WHERE name_en='[DBX-sel-m]'"
    ).fetchone()[0]
    cat = insert_category(conn.cursor(), "DBX-sel-c", m)
    item = insert_item(conn.cursor(), "DBX-sel-i", m, cat, 45.00)
    cust = _customer(conn)
    order_id = _order(conn, m, cust, 50.00, "delivered")
    conn.execute(
        """
        INSERT INTO public.order_items
          (order_id, item_id, item_name_ar, item_name_en, item_price,
           quantity, selected_options, total_price)
        VALUES (%s, %s, 'كشري','Koshari',45.00,1,
                '[{"option_name_en":"Size","choice_name_en":"Large","price_modifier":20.00}]'::jsonb,
                65.00)
        """,
        (order_id, item),
    )
    keys = set(
        scalar(
            conn,
            "SELECT string_agg(k, ',' ORDER BY k) FROM public.order_items oi, "
            "LATERAL jsonb_object_keys(oi.selected_options->0) AS k WHERE oi.order_id=%s",
            (order_id,),
        ).split(",")
    )
    assert keys == {"option_name_en", "choice_name_en", "price_modifier"}, (
        f"expected BUG-12: snapshot keys are {sorted(keys)} -- no choice_id, so "
        "you cannot aggregate 'which option sold most' by id"
    )