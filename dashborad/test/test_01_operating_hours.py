"""Test 01 -- operating_hours: day-of-week semantics and overnight windows.

Derived from static analysis of migrations 006 / 017 / 031, then run against the
live database.

BUG-01  day_of_week is documented and constrained as 0=Sunday..6=Saturday
        (Egyptian week, migration 006:18) but both is_merchant_open() (017:236)
        and merchants_with_open_status (031:51) compare it against
        EXTRACT(ISODOW ...), which is 1=Monday..7=Sunday. 7 is outside
        CHECK (day_of_week BETWEEN 0 AND 6) so Sunday can never match.

BUG-02  The open window is `now >= open_time AND now < close_time`, which
        cannot represent a window crossing midnight (22:00 -> 02:00).

NOT A BUG (verified, correcting the static analysis)
        A 24-hour merchant IS expressible as open_time 00:00 / close_time
        24:00 -- Postgres TIME accepts 24:00:00 and `now < 24:00` is always
        true. No overnight flag is needed for the "24-hour pharmacy" case.
"""

from __future__ import annotations

import pytest

from conftest import begin, insert_merchant, scalar

SUNDAY_EGYPTIAN = 0  # documented convention, migration 006:18
ISODOW_SUNDAY = 7  # what EXTRACT(ISODOW) actually returns


def _insert_hours(cur, merchant_id, dow, open_t, close_t, is_closed=False):
    cur.execute(
        """
        INSERT INTO public.operating_hours
            (merchant_id, day_of_week, open_time, close_time, is_closed)
        VALUES (%s, %s, %s, %s, %s)
        """,
        (merchant_id, dow, open_t, close_t, is_closed),
    )


# ---------------------------------------------------------------------------
# BUG-01: day-of-week mismatch
# ---------------------------------------------------------------------------


def test_day_of_week_check_range_is_one_to_seven(conn):
    """Precondition for BUG-01: the CHECK admits only 0..6."""
    definition = scalar(
        conn,
        """
        SELECT pg_get_constraintdef(oid)
        FROM pg_constraint
        WHERE conrelid = 'public.operating_hours'::regclass
          AND contype = 'c'
          AND strpos(pg_get_constraintdef(oid), 'day_of_week') > 0
        """,
    )
    assert definition, "no CHECK constraint mentions day_of_week"
    # Postgres normalises BETWEEN 0 AND 6 into two comparisons.
    assert "day_of_week >= 1" in definition
    assert "day_of_week <= 7" in definition


def test_isodow_sunday_is_now_storable(conn):
    """The value EXTRACT(ISODOW) returns for Sunday cannot be stored."""
    cur = conn.cursor()
    m = insert_merchant(cur, "DBX-oh-iso", "restaurant", True, "approved")
    _insert_hours(cur, m, ISODOW_SUNDAY, "09:00", "23:00")  # must NOT raise
    stored = conn.execute(
        "SELECT day_of_week FROM public.operating_hours"
        " WHERE merchant_id=%s AND day_of_week=%s",
        (m, ISODOW_SUNDAY),
    ).fetchone()
    assert stored == (7,), "migration 107 stores Sunday as ISO 7"


def test_sunday_open_row_matches_the_function_predicate(conn):
    """BUG-01, deterministic (no need to wait for Sunday).

    Stored convention  0=Sunday .. 6=Saturday   (006:18)
    ISODOW convention  1=Monday .. 7=Sunday   (017:236, 031:51)

    Monday..Saturday agree by coincidence. Sunday does not: it is stored as 0
    but looked up as 7. This inserts a Sunday-open row and evaluates the exact
    predicate the function uses, at ISODOW=7.
    """
    cur = conn.cursor()
    m = insert_merchant(cur, "DBX-oh-sunday", "restaurant", True, "approved")
    # Migration 107: Sunday is ISO 7.
    _insert_hours(cur, m, ISODOW_SUNDAY, "00:00", "23:59")  # Sunday, wide open

    # Before migration 107 this query used day_of_week = 0 (the 006 convention)
    # and matched nothing, while the function looked up 7. Both are now 7.
    at_isodow_7 = scalar(
        conn,
        """
        SELECT EXISTS (
            SELECT 1 FROM public.operating_hours oh
            WHERE oh.merchant_id = %s
              AND oh.day_of_week = 7
              AND oh.is_closed = FALSE
              AND TIME '12:00' >= oh.open_time
              AND TIME '12:00' <  oh.close_time
        )
        """,
        (m,),
    )
    assert at_isodow_7 is True, (
        "expected migration 107 to align Sunday: the row is stored as "
        "day_of_week=7 and is_merchant_open() looks up EXTRACT(ISODOW)=7"
    )

    # And the old 0-based value is now rejected outright, so the two conventions
    # cannot drift apart again.
    with pytest.raises(Exception) as exc:
        _insert_hours(cur, m, 0, "09:00", "23:00")
    begin(conn)
    assert "day_of_week" in str(exc.value).lower()


def test_sunday_is_open_end_to_end_when_it_is_sunday(conn):
    """The same path, run only on a real Sunday.

    The bug this covers is fixed by migration 107, which realigned the stored
    day_of_week with ISODOW (0=Sunday became 7=Sunday) and widened the CHECK to
    1..7. The test previously asserted the merchant reads CLOSED, i.e. it
    demanded the bug still be present, and it wrote rows using the old 0-based
    convention -- day_of_week=0 is now outside the CHECK, so on a Sunday it
    raised CheckViolation instead of asserting anything.

    Both halves are corrected here:
      - rows are written 1..7, the convention the column now holds
      - the assertion is that Sunday reads OPEN, which is the fixed behaviour

    Still Sunday-only, because is_merchant_open() reads NOW(). A Sunday row on a
    Tuesday is not observable through this function; the ISO convention itself is
    covered by the non-skipped tests above.
    """
    isodow_today = int(
        scalar(conn, "SELECT EXTRACT(ISODOW FROM NOW() AT TIME ZONE 'Africa/Cairo')")
    )
    if isodow_today != ISODOW_SUNDAY:
        pytest.skip(f"today is ISODOW {isodow_today}; BUG-01 only observable on Sunday")

    cur = conn.cursor()
    m = insert_merchant(cur, "DBX-oh-sunday-live", "restaurant", True, "approved")
    # ISO 1..7. Writing 0 would violate operating_hours_day_of_week_check.
    for dow in range(1, 8):
        _insert_hours(cur, m, dow, "00:00", "23:59")

    assert (
        scalar(conn, "SELECT public.is_merchant_open(%s)", (m,)) is True
    ), "expected the merchant to read OPEN on Sunday: migration 107 moved Sunday to ISODOW 7"


def test_sunday_row_is_representable_under_the_current_check(conn):
    """Regression guard for the CHECK itself, runnable any day.

    This is the part of the old test that failed on a Sunday for the wrong
    reason: inserting day_of_week=0 raises CheckViolation. Asserting the
    constraint accepts every ISO value 1..7 and rejects 0 means a future
    migration cannot silently narrow it back without a test going red.
    """
    definition = scalar(
        conn,
        """
        SELECT pg_get_constraintdef(oid)
        FROM pg_constraint
        WHERE conrelid = 'public.operating_hours'::regclass
          AND contype = 'c'
          AND strpos(pg_get_constraintdef(oid), 'day_of_week') > 0
        """,
    )
    assert "7" in str(definition), (
        f"day_of_week CHECK no longer admits ISO Sunday (7): {definition}"
    )

    cur = conn.cursor()
    m = insert_merchant(cur, "DBX-oh-isodow-range", "restaurant", True, "approved")
    for dow in range(1, 8):
        _insert_hours(cur, m, dow, "09:00", "21:00")  # must all be accepted

    import psycopg

    with pytest.raises(psycopg.errors.CheckViolation):
        _insert_hours(cur, m, 0, "09:00", "21:00")  # the old convention must be rejected


def test_matview_uses_isodow_against_zero_based_column(conn):
    """The materialized view has the same mismatch, baked into its definition."""
    definition = scalar(
        conn,
        """
        SELECT pg_get_viewdef('public.merchants_with_open_status'::regclass, true)
        """,
    )
    assert definition, "expected merchants_with_open_status to exist"
    assert "ISODOW" in definition.upper(), "expected ISODOW in the view definition"
    # The column is constrained 0..6 but compared against ISODOW 1..7.
    assert "oh.day_of_week" in definition


# ---------------------------------------------------------------------------
# BUG-02: overnight windows
# ---------------------------------------------------------------------------


def test_overnight_window_never_matches(conn):
    """BUG-02 reproduced: a 22:00 -> 02:00 window matches nothing after midnight."""
    dow_today = int(
        scalar(conn, "SELECT EXTRACT(ISODOW FROM NOW() AT TIME ZONE 'Africa/Cairo')")
    )
    cur = conn.cursor()
    m = insert_merchant(cur, "DBX-oh-night", "restaurant", True, "approved")
    _insert_hours(cur, m, dow_today, "22:00", "02:00")

    at_0100 = scalar(
        conn,
        """
        SELECT EXISTS (
            SELECT 1 FROM public.operating_hours oh
            WHERE oh.merchant_id = %s AND oh.day_of_week = %s
              AND oh.is_closed = FALSE
              AND TIME '01:00' >= oh.open_time
              AND TIME '01:00' <  oh.close_time
        )
        """,
        (m, dow_today),
    )
    assert at_0100 is False, "expected BUG-02: 01:00 does not match 22:00-02:00"

    at_2300 = scalar(
        conn,
        """
        SELECT EXISTS (
            SELECT 1 FROM public.operating_hours oh
            WHERE oh.merchant_id = %s AND oh.day_of_week = %s
              AND oh.is_closed = FALSE
              AND TIME '23:00' >= oh.open_time
              AND TIME '23:00' <  oh.close_time
        )
        """,
        (m, dow_today),
    )
    assert at_2300 is False, "expected BUG-02: 23:00 also fails, 23:00 < 02:00 is false"


# ---------------------------------------------------------------------------
# Verified NOT a bug
# ---------------------------------------------------------------------------


def test_24h_merchant_is_representable(conn):
    """A 24-hour pharmacy works: 00:00 -> 24:00, because Postgres TIME allows
    24:00:00. This corrects the static-analysis claim that 24h is impossible."""
    dow_today = int(
        scalar(conn, "SELECT EXTRACT(ISODOW FROM NOW() AT TIME ZONE 'Africa/Cairo')")
    )
    cur = conn.cursor()
    m = insert_merchant(cur, "DBX-oh-24h", "pharmacy", True, "approved")
    _insert_hours(cur, m, dow_today, "00:00", "24:00")  # must NOT raise

    at_noon = scalar(
        conn,
        """
        SELECT EXISTS (
            SELECT 1 FROM public.operating_hours oh
            WHERE oh.merchant_id = %s AND oh.day_of_week = %s
              AND oh.is_closed = FALSE
              AND TIME '12:00' >= oh.open_time
              AND TIME '12:00' <  oh.close_time
        )
        """,
        (m, dow_today),
    )
    assert at_noon is True


def test_unique_one_row_per_day(conn):
    """One row per (merchant, day) -- the upsert key the dashboard form needs."""
    dupes = scalar(
        conn,
        """
        SELECT count(*) FROM (
            SELECT merchant_id, day_of_week
            FROM public.operating_hours
            GROUP BY 1, 2 HAVING count(*) > 1
        ) x
        """,
    )
    assert dupes == 0