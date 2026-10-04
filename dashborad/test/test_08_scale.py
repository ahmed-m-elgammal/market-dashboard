"""Test 08 -- index and plan behaviour at real cardinality.

Every other suite here runs against an empty schema, where a sequential scan of
nothing is free and no index is ever exercised. This file runs against the
volumes loaded by local/seed_data.py:

    8,000 customers   60 merchants     480 categories   2,400 items
    1,815 options     6,343 choices    50,000 orders    124,840 order_items
    6,000 reviews     2,400 favorites  8,000 addresses  420 hours

Assertion style
---------------
Plan TEXT is a weak signal: with a LIMIT, PostgreSQL legitimately prefers a
sequential scan and stops early, so "the plan contains a Seq Scan" is often true
for a perfectly healthy query. So where a missing index is suspected, these
tests measure instead:

    1. record the cost with the current schema
    2. add the index inside the test transaction
    3. record the cost again
    4. assert the gap is material

That proves the index is worth having AND validates the fix, in one test. The
CREATE INDEX is rolled back with everything else, so the suite is repeatable.

FK cascades run as RI triggers, whose time is reported outside the plan tree
("Trigger for constraint ... : time=11.086 calls=1"), so cascade cost is read
from there.
"""

from __future__ import annotations

import re

import pytest

from conftest import indexes, scalar

MIN_ORDER_ITEMS = 100_000
MIN_ORDERS = 40_000
MIN_REVIEWS = 5_000
MIN_ITEMS = 2_000

# PostgreSQL prints "Trigger for constraint <name> on <table>: time=.. calls=.."
# when the triggers span tables, but OMITS the "on <table>" part when they all
# fire on the same relation. Both forms occur, so the table is optional.
TRIGGER_RE = re.compile(
    r"Trigger for constraint (?P<name>\S+)(?: on (?P<table>\S+))?: "
    r"time=(?P<ms>[0-9.]+) calls=(?P<calls>\d+)"
)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------


def explain(conn, sql: str, params=()) -> str:
    with conn.cursor() as cur:
        cur.execute("EXPLAIN (ANALYZE, BUFFERS) " + sql, params)
        return "\n".join(r[0] for r in cur.fetchall())


def shared_blocks(conn, sql: str, params=()) -> int:
    """Buffers read+hit, comparable before/after an index change.

    In FORMAT JSON the buffer counters live inside the "Plan" object, not at
    the top level alongside Planning/Execution Time.
    """
    with conn.cursor() as cur:
        cur.execute("EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) " + sql, params)
        return cur.fetchone()[0][0]["Plan"]["Shared Hit Blocks"]


def trigger_ms(conn, sql: str, params=()) -> dict[str, float]:
    """{constraint_name: milliseconds} from an EXPLAIN ANALYZE."""
    out: dict[str, float] = {}
    for _name, table, ms, _calls in TRIGGER_RE.findall(explain(conn, sql, params)):
        out[_name] = float(ms)
    return out


def table_blocks(conn, table: str) -> int:
    return scalar(
        conn,
        """
        SELECT COALESCE((SELECT relpages FROM pg_class WHERE relname = %s), 0) * 128
        """,
        (table,),
    )


def busiest_item(conn) -> tuple[str, int]:
    row = conn.execute(
        """
        SELECT item_id, count(*) c FROM public.order_items
        GROUP BY item_id ORDER BY c DESC LIMIT 1
        """
    ).fetchone()
    return row[0], row[1]


def busiest_merchant(conn) -> tuple[str, int]:
    """A merchant that actually has orders -- probing a random uuid returns 0
    rows and makes every timing meaningless."""
    row = conn.execute(
        """
        SELECT merchant_id, count(*) c FROM public.orders
        WHERE status <> 'cancelled'
        GROUP BY merchant_id ORDER BY c DESC LIMIT 1
        """
    ).fetchone()
    return row[0], row[1]


def need(conn, table: str, floor: int) -> None:
    n = scalar(conn, f"SELECT count(*) FROM public.{table}")
    if n < floor:
        pytest.skip(f"needs >= {floor} {table}, found {n}. Run local/seed_data.py")


# ---------------------------------------------------------------------------
# Sanity
# ---------------------------------------------------------------------------


def test_volumes_are_present(conn):
    for table, floor in (
        ("orders", MIN_ORDERS),
        ("order_items", MIN_ORDER_ITEMS),
        ("reviews", MIN_REVIEWS),
        ("items", MIN_ITEMS),
    ):
        need(conn, table, floor)


# ---------------------------------------------------------------------------
# BUG-14 -- order_items.item_id is unindexed
# ---------------------------------------------------------------------------


def test_order_items_has_index_on_item_id(conn):
    """Static proof. order_items carries a pkey and idx_order_items_order on
    (order_id). Nothing indexes item_id -- the FK column that both the delete
    cascade and every "which orders contained this item" report must probe."""
    idx = sorted(name for _t, name, _d in indexes(conn) if _t == "order_items")
    # One composite, not two: item_id leads, so it covers the FK probe and both
    # history reads. A narrow (item_id) index alongside it is redundant -- the
    # planner prefers the composite anyway -- and would only cost write
    # amplification.
    assert "idx_order_items_item_order" in idx, (
        f"migration 108 must add idx_order_items_item_order; found {idx}"
    )
    assert "idx_order_items_item" not in idx, (
        f"a narrow item_id index is redundant alongside the composite; found {idx}"
    )


def test_fk_cascade_uses_the_item_id_index(conn):
    """BUG-14, fixed by migration 108.

    Was: the items -> order_items cascade had no index to probe and
    sequentially scanned the table (8.42ms at 124,840 rows). Now the index
    exists, so the probe is a btree lookup.
    """
    need(conn, "order_items", MIN_ORDER_ITEMS)
    item_id, lines = busiest_item(conn)
    assert lines > 10

    conn.execute("CREATE TEMP TABLE _pick (id uuid)")
    conn.execute("INSERT INTO _pick VALUES (%s)", (item_id,))
    conn.execute("SAVEPOINT sp")
    timings = trigger_ms(
        conn, "DELETE FROM public.items WHERE id = (SELECT id FROM _pick)"
    )
    conn.execute("ROLLBACK TO SAVEPOINT sp")
    assert "order_items_item_id_fkey" in timings, (
        f"the order_items cascade trigger must be observable: {timings}"
    )


def test_dropping_the_item_id_index_reintroduces_the_scan(conn):
    """The converse, so the fix cannot silently regress.

    Drops migration 108's index inside the transaction and confirms the same
    query flips to a sequential scan. Asserted on plan shape rather than
    trigger milliseconds: the cascade's cost is reported as a timing, which is
    noisy enough to flake, whereas the plan is deterministic.
    """
    need(conn, "order_items", MIN_ORDER_ITEMS)
    item_id, _ = busiest_item(conn)
    sql = "SELECT order_id FROM public.order_items WHERE item_id = %s"

    assert "Seq Scan on order_items" not in explain(conn, sql, (item_id,)), (
        "with migration 108's index the lookup should not seq-scan"
    )

    conn.execute("DROP INDEX public.idx_order_items_item_order")
    assert "Seq Scan on order_items" in explain(conn, sql, (item_id,)), (
        "expected BUG-14 to return once the index is dropped -- the index is "
        "what prevents the scan"
    )


def test_item_order_history_lookup_is_indexed(conn):
    """BUG-14 from the read side."""
    need(conn, "order_items", MIN_ORDER_ITEMS)
    item_id, _ = busiest_item(conn)
    sql = "SELECT order_id FROM public.order_items WHERE item_id = %s"
    text = explain(conn, sql, (item_id,))
    assert "Seq Scan on order_items" not in text, (
        f"item history should use idx_order_items_item, plan:\n{text}"
    )


# ---------------------------------------------------------------------------
# BUG-15 -- merchants.approval_status is unindexed
# ---------------------------------------------------------------------------


def test_approval_status_is_unindexed(conn):
    """BUG-15, static proof. The approval queue is one of the two screens
    migration 103 exists to serve, and its filter column has no index."""
    found = [d for _t, _n, d in indexes(conn) if "approval_status" in d]
    assert found, "migration 116 must add an index covering approval_status"


def test_approval_queue_cost_drops_when_indexed(conn):
    """BUG-15, measured."""
    if scalar(conn, "SELECT count(*) FROM public.merchants") == 0:
        pytest.skip("needs merchants; run local/seed_data.py")
    sql = """
        SELECT id, name_en FROM public.merchants
        WHERE approval_status = 'pending' AND is_active = TRUE
        ORDER BY created_at DESC LIMIT 50
    """
    before = shared_blocks(conn, sql)

    conn.execute(
        "CREATE INDEX idx_test_m_approval ON public.merchants(approval_status)"
        " WHERE approval_status = 'pending'"
    )
    after = shared_blocks(conn, sql)

    assert after < before, (
        f"BUG-15 should cost something: {before} buffers seq-scanning vs {after} "
        "with a partial index"
    )


def test_merchants_table_is_small_enough_to_hide_missing_indexes(conn):
    """Context, not a bug. At 60 merchants PostgreSQL prefers a sequential scan
    even for indexed columns, so index coverage on `merchants` cannot be proven
    at this scale -- only on orders / order_items / reviews, where the row
    counts are realistic.

    Recorded so nobody later mistakes "no Seq Scan on merchants" for a goal.
    BUG-15 (approval_status) is therefore proven structurally and by
    before/after buffer counts, not by plan shape.
    """
    n = scalar(conn, "SELECT count(*) FROM public.merchants")
    assert n < 500, (
        f"merchants has {n} rows; if this is now large, re-check whether the "
        "index-shape assertions in this file are still meaningful"
    )


# ---------------------------------------------------------------------------
# BUG-16 -- the moderation queue cannot use the existing is_visible index
# ---------------------------------------------------------------------------


def test_is_visible_index_is_merchant_prefixed_and_true_only(conn):
    """BUG-16, static proof -- and narrower than first assumed.

    There IS an is_visible index (added after 012), but it is:
        (merchant_id, created_at DESC) WHERE is_visible = true

    Two consequences:
      * the predicate `is_visible = false` is outside the partial index
      * even `is_visible = true` alone cannot use it, because merchant_id is
        the leading column
    So it serves exactly one query shape: "visible reviews for merchant X".
    """
    defs = {name: d for _t, name, d in indexes(conn) if _t == "reviews"}
    target = "idx_reviews_merchant_visible"
    assert target in defs, f"expected {target}, found {sorted(defs)}"
    definition = defs[target]
    assert "merchant_id" in definition, "leading column must be merchant_id"
    assert "is_visible = true" in definition, (
        f"expected the partial predicate to exclude is_visible = false: {definition}"
    )


def test_moderation_queue_cannot_use_the_partial_index(conn):
    """BUG-16, measured. The Ops queue is `WHERE is_visible = false`, which the
    index excludes by construction."""
    need(conn, "reviews", MIN_REVIEWS)
    hidden = scalar(
        conn, "SELECT count(*) FROM public.reviews WHERE is_visible = FALSE"
    )
    assert hidden > 100, "need a real moderation backlog for this to mean anything"

    sql = """
        SELECT id, order_id, merchant_rating, merchant_comment, created_at
        FROM public.reviews WHERE is_visible = FALSE
        ORDER BY created_at ASC LIMIT 50
    """
    before = shared_blocks(conn, sql)

    conn.execute(
        "CREATE INDEX idx_test_rev_pending ON public.reviews(created_at)"
        " WHERE is_visible = FALSE"
    )
    after = shared_blocks(conn, sql)

    assert after < before, (
        f"BUG-16 should cost something: {before} buffers vs {after} with a "
        "matching partial index"
    )


def test_unmoderated_badge_count_served_by_the_pending_index(conn):
    """BUG-16 follow-up.

    Originally this was recorded as NOT a bug: at 3,000 hidden rows the planner
    preferred a sequential scan (110 buffers) even when a matching partial index
    existed. Migration 116 then added that index for the moderation queue, and
    it turns out the same index also serves the count -- 8 buffers, index-only.

    So the earlier "not a bug" note was right that no SECOND index was needed,
    but wrong to imply the count could not be improved. Corrected here.
    """
    need(conn, "reviews", MIN_REVIEWS)
    sql = "SELECT count(*) FROM public.reviews WHERE is_visible = FALSE"
    text = explain(conn, sql)
    assert "Seq Scan on reviews" not in text, (
        f"migration 116's idx_reviews_pending should serve the badge count, plan:\n{text}"
    )
    hidden = scalar(
        conn, "SELECT count(*) FROM public.reviews WHERE is_visible = FALSE"
    )
    assert hidden > 1000, "need a real backlog for this to be meaningful"


def test_visible_reviews_for_one_merchant_is_already_indexed(conn):
    """Verified-good: the one query shape the 012-era index does serve."""
    need(conn, "reviews", MIN_REVIEWS)
    merchant_id = scalar(conn, "SELECT merchant_id FROM public.reviews LIMIT 1")
    sql = """
        SELECT id FROM public.reviews
        WHERE merchant_id = %s AND is_visible = TRUE
        ORDER BY created_at DESC
    """
    assert "idx_reviews_merchant_visible" in explain(conn, sql, (merchant_id,)), (
        "the per-merchant visible-reviews query should use its partial index"
    )


# ---------------------------------------------------------------------------
# BUG-17 -- get_merchant_kpis_range walks orders three times
# ---------------------------------------------------------------------------


def test_kpis_range_costs_more_than_one_aggregate_pass(conn):
    """BUG-17, measured.

    091's body contains six subqueries over the same rows: COUNT and SUM for
    the range, then both again inside the AOV CASE branch. PostgreSQL
    inlines the SQL function, but only folds the arguments when they are
    constant -- so a parameterised call (which is exactly how PostgREST invokes
    it) evaluates the repeated work for real.

    Compared against the same numbers computed in a single aggregate pass.
    """
    need(conn, "orders", MIN_ORDERS)
    merchant_id, orders = busiest_merchant(conn)
    assert orders > 100, "need a merchant with a real order history"

    rpc = shared_blocks(
        conn,
        "SELECT public.get_merchant_kpis_range(%s, %s)",
        (merchant_id, "2020-01-01T00:00:00Z"),
    )
    single = shared_blocks(
        conn,
        """
        SELECT json_build_object(
            'order_count', count(*),
            'revenue', COALESCE(sum(total), 0),
            'avg_order_value', CASE WHEN count(*) > 0
                THEN round(COALESCE(sum(total),0) / count(*), 2) ELSE 0 END
        )
        FROM public.orders WHERE merchant_id = %s AND created_at >= %s
        """,
        (merchant_id, "2020-01-01T00:00:00Z"),
    )
    assert rpc > single, (
        f"BUG-17 expected: the RPC costs {rpc} buffers vs {single} for one "
        f"aggregate pass over {orders} orders. Equal or lower means PostgreSQL "
        "folded the function and the duplication is harmless -- update this test."
    )


def test_kpis_all_time_costs_more_than_one_aggregate_pass(conn):
    """066 does the same thing with two subqueries instead of one."""
    need(conn, "orders", MIN_ORDERS)
    merchant_id, orders = busiest_merchant(conn)

    rpc = shared_blocks(
        conn, "SELECT public.get_merchant_kpis(%s)", (merchant_id,)
    )
    single = shared_blocks(
        conn,
        "SELECT json_build_object('n', count(*), 'rev', COALESCE(sum(total),0))"
        " FROM public.orders WHERE merchant_id = %s",
        (merchant_id,),
    )
    assert rpc > single, (
        f"BUG-17 expected: {rpc} buffers for the RPC vs {single} for one pass "
        f"over {orders} orders"
    )


# ---------------------------------------------------------------------------
# Verified-good: hot paths that ARE indexed
# ---------------------------------------------------------------------------


def test_menu_query_uses_the_composite_index(conn):
    need(conn, "items", MIN_ITEMS)
    row = conn.execute(
        "SELECT merchant_id, category_id FROM public.items LIMIT 1"
    ).fetchone()
    text = explain(
        conn,
        "SELECT id, name_en, price FROM public.items"
        " WHERE merchant_id = %s AND category_id = %s AND is_available = TRUE"
        " ORDER BY sort_order",
        row,
    )
    assert "idx_items_merchant_category" in text, (
        f"menu query should use idx_items_merchant_category, plan:\n{text}"
    )


def test_active_orders_dashboard_query_is_indexed(conn):
    """The active-orders board: newest-first, non-terminal statuses only.

    Asserts that SOME index on orders is used, not a specific one. Migration
    120's idx_orders_created_at turned out to serve this better than
    idx_orders_active, because ORDER BY created_at DESC LIMIT 100 is answered
    directly by walking that index backwards with no sort step. Pinning
    idx_orders_active here would freeze the planner onto the slower of two valid
    plans.
    """
    need(conn, "orders", MIN_ORDERS)
    text = explain(
        conn,
        "SELECT id, status, created_at FROM public.orders"
        " WHERE status NOT IN ('delivered','cancelled')"
        " ORDER BY created_at DESC LIMIT 100",
    )
    assert "Seq Scan on orders" not in text, (
        f"the active-orders board must not seq-scan orders, plan:\n{text}"
    )


def test_chip_row_view_does_not_scan_merchants(conn):
    if scalar(conn, "SELECT count(*) FROM public.merchants") == 0:
        pytest.skip("needs merchants; run local/seed_data.py")
    text = explain(conn, "SELECT code, name_en FROM public.active_merchant_categories")
    assert "Seq Scan on merchants" not in text, (
        f"the chip view should use the merchants category index, plan:\n{text}"
    )


def test_payout_order_lookup_is_indexed(conn):
    """The merchant payout screen joins payout -> orders."""
    if not scalar(
        conn,
        "SELECT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname='public'"
        " AND tablename='merchant_payout_orders')",
    ):
        pytest.skip("merchant_payout_orders not present")
    payout_id = scalar(conn, "SELECT payout_id FROM public.merchant_payout_orders LIMIT 1")
    if payout_id is None:
        pytest.skip("no payout rows seeded")
    text = explain(
        conn,
        "SELECT order_id FROM public.merchant_payout_orders WHERE payout_id = %s",
        (payout_id,),
    )
    assert "Seq Scan on merchant_payout_orders" not in text, (
        f"payout -> orders lookup should be indexed, plan:\n{text}"
    )


# ---------------------------------------------------------------------------
# Scale context for the correctness bugs
# ---------------------------------------------------------------------------


def test_cancelled_share_quantifies_bug_09(conn):
    need(conn, "orders", MIN_ORDERS)
    total = scalar(conn, "SELECT count(*) FROM public.orders")
    cancelled = scalar(
        conn, "SELECT count(*) FROM public.orders WHERE status = 'cancelled'"
    )
    share = cancelled / total
    assert share > 0.01, (
        f"cancelled share {share:.1%} -- BUG-09 overstates revenue by about "
        "this much, and grows as cancellations grow"
    )


def test_unmoderated_share_quantifies_bug_10(conn):
    need(conn, "reviews", MIN_REVIEWS)
    total = scalar(conn, "SELECT count(*) FROM public.reviews")
    hidden = scalar(
        conn, "SELECT count(*) FROM public.reviews WHERE is_visible = FALSE"
    )
    assert hidden / total > 0.2, (
        f"{hidden}/{total} reviews unmoderated -- every displayed rating rests "
        "on the visible minority"
    )


def test_order_lines_per_order_is_realistic(conn):
    need(conn, "orders", MIN_ORDERS)
    lines = scalar(conn, "SELECT count(*) FROM public.order_items")
    orders = scalar(conn, "SELECT count(*) FROM public.orders")
    per = lines / orders
    assert 1.5 < per < 4.0, (
        f"{per:.2f} lines per order -- outside 1.5-4.0 the order_items index "
        "tests are not representative"
    )