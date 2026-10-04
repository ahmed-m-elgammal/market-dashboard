"""Test 10 -- Dashboard Overview RPCs (migration 120).

The Overview page needs four queries that did not exist. These tests pin their
semantics, because the definitions make deliberate choices that are easy to
misread in a UI:

  * revenue AND orders_count both exclude cancelled, so the two KPI cards agree.
    cancelled_count and orders_including_cancelled sit beside them for anyone
    who needs the raw numbers.
  * change.* is NULL against an empty previous window, not 0. A dashboard
    rendering 0% would read "flat" when the truth is "no baseline".
  * get_daily_series returns explicit zero rows for days with no activity, via
    generate_series. Without that a chart draws a straight line across the gap
    and reads it as steady.
  * get_trending_items uses the order_items snapshot for revenue, not the live
    catalog price.
  * all four are service_role only.

Everything is asserted as a DELTA or scoped to this test's own rows. The seeded
database holds ~50k orders inside every window, so a platform-wide absolute
value cannot be asserted.
"""

from __future__ import annotations

import uuid

import pytest

from conftest import insert_category, insert_item, insert_merchant, scalar

WINDOW = "NOW() - interval '7 days'"


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------


def kpis(conn):
    return scalar(conn, f"SELECT public.get_platform_kpis({WINDOW})")


def delta(conn, before, key):
    """Change in a KPI caused by this test's fixtures."""
    return float(kpis(conn)[key]) - float(before[key])


def series(conn, days=4):
    """day -> row, for the whole daily series."""
    return {
        r[0]: r
        for r in conn.execute(
            f"SELECT * FROM public.get_daily_series(NOW() - interval '{days} days', NOW())"
        ).fetchall()
    }


def trending_for(conn, item_id):
    """Trending rows for ONE specific item.

    Two problems this has to work around:

      * the seeded database holds thousands of delivered orders, so a global
        count cannot distinguish this test's fixture from the noise
      * get_trending_items clamps its limit to 100, so a low-revenue fixture
        would fall off the ranked list entirely

    Hence BIG: fixture orders are given enough revenue to rank first, which is
    what every trending assertion below relies on.
    """
    return [
        r
        for r in conn.execute(
            f"SELECT * FROM public.get_trending_items({WINDOW}, NOW(), 100)"
        ).fetchall()
        if r[0] == item_id
    ]


# Fixture revenue high enough to rank #1 against the seeded catalogue.
BIG = 7_777.00


def recent_for(conn, match: dict):
    """Recent-order rows matching a predicate on the returned tuple.

    Takes the predicate as a positional dict: **kwargs would require string
    keys, and these are positional column indices.
    """
    rows = conn.execute("SELECT * FROM public.get_recent_orders(100)").fetchall()
    return [r for r in rows if all(r[k] == v for k, v in match.items())]


def _customer(conn) -> uuid.UUID:
    """Insert auth.users only -- the 002 trigger creates the profiles row."""
    uid = uuid.uuid4()
    conn.execute("INSERT INTO auth.users (id) VALUES (%s)", (uid,))
    return uid


def _order(conn, merchant_id, customer_id, total, status, when, quantity=1, item=None):
    """`when` is a SQL expression, inlined rather than bound.

    psycopg sends a str for a timestamptz parameter as text, so
    "(NOW() - interval '1 day')" would arrive as a literal and fail to parse.
    These are test-local expressions with no user input, so inlining is safe.
    """
    order_id = uuid.uuid4()
    conn.execute(
        f"""
        INSERT INTO public.orders
          (id, order_number, customer_id, merchant_id, status, delivery_address,
           subtotal, total, created_at)
        VALUES (%s, %s, %s, %s, %s, '{{}}'::jsonb, %s, %s, {when})
        """,
        (order_id, f"DBX-{str(order_id)[:8].upper()}", customer_id,
         merchant_id, status, total, total),
    )
    if item is not None:
        conn.execute(
            """
            INSERT INTO public.order_items
              (order_id, item_id, item_name_ar, item_name_en, item_price,
               quantity, total_price)
            VALUES (%s, %s, 'صنف', 'Seeded Item', %s, %s, %s)
            """,
            (order_id, item[0], total / quantity, quantity, total),
        )
    return order_id


@pytest.fixture
def world(conn):
    """merchant -> category -> item, plus a customer."""
    cur = conn.cursor()
    m = insert_merchant(cur, "DBX-ov-m", "restaurant", True, "approved")
    c = insert_category(cur, "DBX-ov-c", m)
    i = insert_item(cur, "DBX-ov-item", m, c, 100.00)
    return m, c, i, _customer(conn)


# ---------------------------------------------------------------------------
# Grants: service_role only
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "fn",
    [
        "public.get_platform_kpis(timestamptz)",
        "public.get_daily_series(timestamptz, timestamptz)",
        "public.get_trending_items(timestamptz, timestamptz, integer)",
        "public.get_recent_orders(integer)",
    ],
)
def test_overview_rpcs_are_service_role_only(conn, fn):
    """These expose platform revenue, customer names and customer phone
    numbers. Supabase grants EXECUTE on new functions to anon and authenticated
    by default, so migration 120 must revoke explicitly -- and did."""
    row = conn.execute(
        """
        SELECT has_function_privilege('anon', %s, 'EXECUTE'),
               has_function_privilege('authenticated', %s, 'EXECUTE'),
               has_function_privilege('service_role', %s, 'EXECUTE')
        """,
        (fn, fn, fn),
    ).fetchone()
    assert row[0] is False, f"anon must not execute {fn}"
    assert row[1] is False, f"authenticated must not execute {fn}"
    assert row[2] is True, f"service_role must execute {fn}"


def test_pct_change_helper_is_not_public(conn):
    assert (
        scalar(conn, "SELECT has_function_privilege('anon',"
                      " 'public._pct_change(numeric,numeric)', 'EXECUTE')")
        is False
    )


def test_leaked_merchant_kpi_grant_is_recorded_but_not_fixed(conn):
    """BUG-20, deliberately not fixed in migration 120.

    get_merchant_kpis is granted to anon (066), so an unauthenticated caller can
    read any merchant's revenue and order count by guessing a UUID. Recorded
    rather than fixed: tightening an existing grant can break the mobile app,
    which is outside the dashboard's scope.
    """
    ok = scalar(
        conn,
        "SELECT has_function_privilege('anon',"
        " 'public.get_merchant_kpis(uuid)', 'EXECUTE')",
    )
    assert ok is True, "expected BUG-20: still granted to anon; update when fixed"


# ---------------------------------------------------------------------------
# get_platform_kpis
# ---------------------------------------------------------------------------


def test_revenue_and_order_count_both_exclude_cancelled(conn, world):
    """The two cards must agree. cancelled_count carries the raw number."""
    m, _c, _i, cust = world
    before = kpis(conn)

    _order(conn, m, cust, 100.00, "delivered", "(NOW() - interval '1 day')")
    _order(conn, m, cust, 500.00, "cancelled", "(NOW() - interval '1 day')")
    _order(conn, m, cust, 250.00, "pending", "(NOW() - interval '1 day')")

    assert delta(conn, before, "revenue") == 350.0, (
        "100 delivered + 250 pending; the cancelled 500 must be excluded"
    )
    assert delta(conn, before, "orders_count") == 2, (
        "orders_count excludes cancelled too, so the cards agree"
    )
    assert delta(conn, before, "cancelled_count") == 1, (
        "the cancelled order is not lost, just reported separately"
    )


def test_previous_window_is_the_immediately_preceding_span(conn, world):
    m, _c, _i, cust = world
    before = kpis(conn)

    _order(conn, m, cust, 100.00, "delivered", "(NOW() - interval '1 day')")
    _order(conn, m, cust, 100.00, "delivered", "(NOW() - interval '10 days')")

    after = kpis(conn)
    assert delta(conn, before, "revenue") == 100.0, (
        "only the 1-day-old order is inside the window"
    )
    assert float(after["previous"]["revenue"]) == float(before["previous"]["revenue"]) + 100.0, (
        "the 10-day-old order belongs to the previous window of equal length"
    )


def test_change_is_null_against_an_empty_previous_window(conn):
    """NULL, not 0. Asserted on the helper the RPC uses, because the seeded
    database has activity in every window."""
    row = conn.execute(
        "SELECT public._pct_change(100.00, 0) AS zero, "
        "public._pct_change(0, NULL) AS nullbase, "
        "public._pct_change(150, 100) AS up, "
        "public._pct_change(50, 100) AS down"
    ).fetchone()
    assert row[0] is None, "no baseline means no percentage, not 0%"
    assert row[1] is None
    assert float(row[2]) == 50.0
    assert float(row[3]) == -50.0


def test_window_days_is_echoed_back(conn):
    k = kpis(conn)
    assert k["window_days"] in (6, 7), k["window_days"]
    assert "from" in k and "to" in k


def test_new_customers_counts_only_customer_role(conn):
    """The role-escalation trigger (024/052) blocks promoting a profile to
    driver/admin from a non-service_role session, so the non-customer case is
    asserted against the index predicate rather than by mutating role."""
    before = kpis(conn)
    for _ in range(2):
        c = _customer(conn)
        conn.execute(
            "UPDATE public.profiles SET created_at = NOW() - interval '1 hour' WHERE id=%s",
            (c,),
        )
    after = kpis(conn)
    assert after["new_customers"] - before["new_customers"] == 2

    definition = scalar(
        conn,
        """
        SELECT indexdef FROM pg_indexes
        WHERE schemaname='public' AND tablename='profiles'
          AND strpos(indexdef,'created_at') > 0
        """,
    )
    assert "customer" in definition, (
        f"the index must be partial on role='customer' so admin/driver rows "
        f"never count: {definition}"
    )


# ---------------------------------------------------------------------------
# get_daily_series
# ---------------------------------------------------------------------------


def test_series_returns_every_day_in_range(conn):
    """Contiguity is the point of generate_series: a missing day makes a chart
    draw a straight line across the gap and read it as steady."""
    rows = conn.execute(
        "SELECT * FROM public.get_daily_series(NOW() - interval '6 days', NOW())"
    ).fetchall()
    assert len(rows) == 7, f"expected 7 contiguous days, got {len(rows)}"
    days = [r[0] for r in rows]
    assert days == sorted(days), "must be chronological"
    assert (days[-1] - days[0]).days == 6, "no gaps"


def test_series_yields_zeros_for_a_window_with_no_activity(conn):
    """A future window has no orders at all, so every bucket must be an
    explicit zero rather than absent."""
    rows = conn.execute(
        "SELECT * FROM public.get_daily_series("
        "NOW() + interval '10 days', NOW() + interval '14 days')"
    ).fetchall()
    assert len(rows) == 5, f"expected 5 days, got {len(rows)}"
    for day, revenue, orders, customers, cancelled, raw in rows:
        assert float(revenue) == 0.0, day
        assert orders == 0 and customers == 0 and cancelled == 0 and raw == 0, day


def test_series_aggregates_per_day(conn, world):
    m, _c, _i, cust = world
    before = series(conn)

    _order(conn, m, cust, 100.00, "delivered", "(NOW() - interval '1 day')")
    _order(conn, m, cust, 200.00, "delivered", "(NOW() - interval '1 day')")
    _order(conn, m, cust, 999.00, "cancelled", "(NOW() - interval '1 day')")
    _order(conn, m, cust, 50.00, "delivered", "(NOW() - interval '3 days')")

    after = series(conn)
    # Yesterday, not today -- the fixtures are one day old.
    days = sorted(after)
    yesterday, three_ago = days[-2], days[-4]

    assert float(after[yesterday][1]) - float(before[yesterday][1]) == 300.0, (
        "100 + 200; the cancelled 999 must be excluded"
    )
    assert after[yesterday][2] - before[yesterday][2] == 2, "orders_count excludes cancelled"
    assert after[yesterday][4] - before[yesterday][4] == 1, "cancelled_count reported"
    assert after[yesterday][5] - before[yesterday][5] == 3, "raw count carried alongside"
    assert float(after[three_ago][1]) - float(before[three_ago][1]) == 50.0


def test_series_and_kpis_agree_on_revenue(conn, world):
    """Two code paths computing the same number must not drift."""
    m, _c, _i, cust = world
    _order(conn, m, cust, 100.00, "delivered", "(NOW() - interval '1 day')")
    _order(conn, m, cust, 500.00, "cancelled", "(NOW() - interval '1 day')")

    from_kpis = float(kpis(conn)["revenue"])
    from_series = float(
        scalar(
            conn,
            "SELECT COALESCE(sum(revenue), 0) FROM public.get_daily_series("
            "NOW() - interval '7 days', NOW())",
        )
    )
    assert from_kpis == from_series, (
        f"get_platform_kpis says {from_kpis}, get_daily_series says {from_series}"
    )


def test_series_uses_cairo_day_boundaries(conn, world):
    """A UTC boundary would split a late-evening Cairo order across two days.

    The order is stamped YESTERDAY 23:30 local -- always in the past, unlike
    "today 23:30", which lands in the future when the suite runs before 23:30.
    """
    m, _c, _i, cust = world
    before = series(conn, days=3)
    _order(
        conn, m, cust, 100.00, "delivered",
        "date_trunc('day', NOW()) + interval '23 hours 30 minutes' - interval '1 day'",
    )
    after = series(conn, days=3)
    gained = sum(float(after[d][1]) - float(before[d][1]) for d in after)
    assert gained == 100.0, (
        f"the late order must land in exactly one bucket, got {gained}"
    )


# ---------------------------------------------------------------------------
# get_trending_items
# ---------------------------------------------------------------------------


def test_trending_ranks_by_revenue_and_reports_units(conn, world):
    _m, _c, item, cust = world
    _order(conn, _m, cust, BIG * 3, "delivered", "(NOW() - interval '1 day')",
           quantity=3, item=(item,))
    _order(conn, _m, cust, BIG, "delivered", "(NOW() - interval '1 day')",
           quantity=1, item=(item,))

    rows = trending_for(conn, item)
    assert rows
    top = rows[0]
    assert top[0] == item
    assert top[5] == 4, "units summed across both orders"
    assert float(top[6]) == BIG * 4


def test_trending_excludes_non_delivered_orders(conn, world):
    """A trending list built on pending orders would promote whatever was
    abandoned most recently, and a cancelled order is not demand."""
    m, _c, item, cust = world
    _order(conn, m, cust, BIG * 9, "cancelled", "(NOW() - interval '1 day')", item=(item,))
    _order(conn, m, cust, BIG * 5, "pending", "(NOW() - interval '1 day')", item=(item,))
    _order(conn, m, cust, BIG, "delivered", "(NOW() - interval '1 day')", item=(item,))

    rows = trending_for(conn, item)
    assert len(rows) == 1, f"only the delivered order should count: {rows}"
    assert float(rows[0][6]) == BIG


def test_trending_uses_the_snapshot_not_the_live_price(conn, world):
    """A price edit today must not retroactively change what an old order
    earned."""
    m, _c, item, cust = world
    _order(conn, m, cust, BIG, "delivered", "(NOW() - interval '5 days')", item=(item,))
    conn.execute(
        "UPDATE public.items SET price = %s WHERE id=%s", (BIG * 99, item)
    )

    rows = trending_for(conn, item)
    assert float(rows[0][6]) == BIG, "revenue comes from order_items, not items.price"


def test_trending_reports_the_current_discount(conn, world):
    """The UI shows a promotion badge when this is non-NULL."""
    m, _c, item, cust = world
    _order(conn, m, cust, BIG, "delivered", "(NOW() - interval '1 day')", item=(item,))
    conn.execute("UPDATE public.items SET discount_price = 70.00 WHERE id=%s", (item,))

    rows = trending_for(conn, item)
    assert float(rows[0][7]) == 70.00


def test_trending_excludes_soft_deleted_items(conn, world):
    """A soft-deleted item (migration 110) should not be merchandised, even
    though its order lines still exist and still earned revenue."""
    m, _c, item, cust = world
    _order(conn, m, cust, BIG, "delivered", "(NOW() - interval '1 day')", item=(item,))
    conn.execute("UPDATE public.items SET deleted_at = now() WHERE id=%s", (item,))

    assert not trending_for(conn, item), "soft-deleted items must not be merchandised"


def test_trending_limit_is_clamped(conn):
    """A UI bug sending limit=100000 must not become a 100000-row scan."""
    definition = scalar(
        conn,
        """
        SELECT pg_get_functiondef(p.oid) FROM pg_proc p
        JOIN pg_namespace ns ON ns.oid = p.pronamespace
        WHERE ns.nspname='public' AND p.proname='get_trending_items'
        """,
    )
    assert "LEAST" in definition and "GREATEST" in definition, (
        "the limit must be clamped with LEAST/GREATEST, not trusted"
    )
    n = scalar(
        conn,
        "SELECT count(*) FROM public.get_trending_items("
        "NOW() - interval '3650 days', NOW(), 10000000)",
    )
    assert n <= 100, f"clamp failed: {n} rows"


def test_recent_orders_limit_is_clamped(conn):
    definition = scalar(
        conn,
        """
        SELECT pg_get_functiondef(p.oid) FROM pg_proc p
        JOIN pg_namespace ns ON ns.oid = p.pronamespace
        WHERE ns.nspname='public' AND p.proname='get_recent_orders'
        """,
    )
    assert "LEAST" in definition and "GREATEST" in definition
    n = scalar(conn, "SELECT count(*) FROM public.get_recent_orders(10000000)")
    assert n <= 100, f"clamp failed: {n} rows"


# ---------------------------------------------------------------------------
# get_recent_orders
# ---------------------------------------------------------------------------

# 0 id, 1 order_number, 2 status, 3 total, 4 payment_method, 5 payment_status,
# 6 created_at, 7 customer_id, 8 customer_name, 9 customer_phone,
# 10 merchant_id, 11 merchant_name, 12 merchant_city, 13 item_count


def test_recent_orders_newest_first_with_labels(conn, world):
    m, _c, _i, cust = world
    conn.execute(
        "UPDATE public.profiles SET full_name='DBX Customer', phone='+2012345'"
        " WHERE id=%s",
        (cust,),
    )
    # NOWEST: the seeded database holds 50k orders stamped at seed time, so a
    # fixture dated in the past would fall outside the LIMIT and vanish.
    _order(conn, m, cust, 100.00, "delivered", "(date_trunc('second', NOW()) + interval '10 seconds')")
    _order(conn, m, cust, 200.00, "pending", "(date_trunc('second', NOW()) + interval '20 seconds')")

    ours = sorted(recent_for(conn, {7: cust}), key=lambda r: r[6], reverse=True)
    assert len(ours) == 2
    assert float(ours[0][3]) == 200.00, "the newest order is first"
    assert ours[0][8] == "DBX Customer", "customer name from profiles"
    assert ours[0][9] == "+2012345"
    assert ours[0][10] == m
    assert ours[0][11], "merchant name from merchants"
    assert ours[0][12], "merchant city from merchants"


def test_recent_orders_are_sorted_newest_first(conn):
    rows = conn.execute("SELECT * FROM public.get_recent_orders(50)").fetchall()
    stamps = [r[6] for r in rows]
    assert stamps == sorted(stamps, reverse=True), "must be newest first"


def test_recent_orders_includes_every_status(conn, world):
    """An operator wants to see what just came in, including failures."""
    m, _c, _i, cust = world
    base = "(date_trunc('second', NOW()) + interval '{} seconds')"
    _order(conn, m, cust, 10.00, "delivered", base.format(10))
    _order(conn, m, cust, 20.00, "cancelled", base.format(20))
    _order(conn, m, cust, 30.00, "pending", base.format(30))

    mine = recent_for(conn, {7: cust})
    assert {r[2] for r in mine} == {"delivered", "cancelled", "pending"}


def test_recent_orders_counts_lines(conn, world):
    m, _c, item, cust = world
    order_id = _order(
        conn, m, cust, 100.00, "delivered",
        "(date_trunc('second', NOW()) + interval '10 seconds')",
    )
    # _order(item=None) inserts no lines, so add two explicitly.
    for _ in range(2):
        conn.execute(
            """
            INSERT INTO public.order_items
              (order_id, item_id, item_name_ar, item_name_en, item_price,
               quantity, total_price)
            VALUES (%s, %s, 'صنف', 'Item', 50.00, 1, 50.00)
            """,
            (order_id, item),
        )
    mine = recent_for(conn, {0: order_id})
    assert mine and mine[0][13] == 2, "line count must reflect both lines"


# ---------------------------------------------------------------------------
# Indexes
# ---------------------------------------------------------------------------


def test_order_time_window_index_exists(conn):
    """Every pre-existing orders index leads with a party column or a partial
    predicate, so a platform-wide date range had nothing to use."""
    n = scalar(
        conn,
        """
        SELECT count(*) FROM pg_indexes
        WHERE schemaname='public' AND tablename='orders'
          AND strpos(indexdef,'created_at') > 0
          AND strpos(indexdef,'merchant_id') = 0
          AND strpos(indexdef,'customer_id') = 0
        """,
    )
    assert n >= 1, "migration 120 must add a plain orders(created_at) index"


def test_daily_aggregate_uses_the_new_index_for_a_narrow_window(conn):
    """Where idx_orders_created_at pays: a window that selects a small slice.

    Asserted on the inner aggregate rather than the RPC, because EXPLAIN on the
    function shows only a Function Scan.

    Deliberately a 7-day window, not 90. At seed volumes every order falls
    inside 90 days, so a sequential scan really is cheaper and the planner
    correctly refuses the index. The index is kept anyway because it wins on
    narrow windows now and on any window once the table spans months -- both
    true of the real catalogue.
    """
    if scalar(conn, "SELECT count(*) FROM public.orders") < 40_000:
        pytest.skip("needs seed_data.py")

    narrow = "\n".join(
        r[0]
        for r in conn.execute(
            """
            EXPLAIN (ANALYZE)
            SELECT (created_at AT TIME ZONE 'Africa/Cairo')::date AS day,
                   COALESCE(sum(total) FILTER (WHERE status <> 'cancelled'), 0)
              FROM public.orders
             WHERE created_at >= NOW() - interval '7 days'
             GROUP BY 1
            """
        ).fetchall()
    )
    assert "idx_orders_created_at" in narrow, (
        f"a 7-day daily aggregate should use idx_orders_created_at:\n{narrow}"
    )


def test_ninety_day_aggregate_uses_the_index_once_history_spreads(conn):
    """The 90-day case, after the seed was fixed to spread orders over ~18
    months.

    Previously every seeded order fell inside 90 days, so a sequential scan was
    genuinely cheaper and the planner correctly refused the index. That was
    recorded as a non-bug at the time. With realistic history -- 9,599 of 50,000
    orders inside 90 days -- the index now wins, which is the behaviour the
    dashboard needs as the marketplace ages.
    """
    if scalar(conn, "SELECT count(*) FROM public.orders") < 40_000:
        pytest.skip("needs seed_data.py")
    inside, total = conn.execute(
        "SELECT count(*) FILTER (WHERE created_at >= NOW() - interval '90 days'),"
        "       count(*) FROM public.orders"
    ).fetchone()
    assert inside < total * 0.5, (
        f"expected a selective 90-day window, got {inside}/{total} -- if the seed "
        "stops spreading orders over time this test is meaningless"
    )
    text = "\n".join(
        r[0]
        for r in conn.execute(
            """
            EXPLAIN
            SELECT (created_at AT TIME ZONE 'Africa/Cairo')::date,
                   COALESCE(sum(total) FILTER (WHERE status <> 'cancelled'), 0),
                   count(*) FILTER (WHERE status <> 'cancelled')
              FROM public.orders
             WHERE created_at >= NOW() - interval '90 days'
             GROUP BY 1
            """
        ).fetchall()
    )
    assert "idx_orders_created_at" in text, (
        f"a selective 90-day window should use the index:\n{text}"
    )