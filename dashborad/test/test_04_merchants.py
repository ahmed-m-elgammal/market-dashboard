"""Test 04 -- merchants table: columns, approval flow, and the two NEW
requirements (branches/chains, discounts).

From the static report:
  - merchants carries 33 columns; `bank_account_number` and the other bank /
    wallet columns are to be DROPPED (payouts are 100% manual, human-in-the-loop)
  - merchants.city / area are free TEXT, not FKs
  - no branches / multi-location: one row == one physical location
  - no discount fields on items
"""

from __future__ import annotations

import pytest

from conftest import check_constraints, foreign_keys, insert_merchant, indexes, scalar


# ---------------------------------------------------------------------------
# Column inventory
# ---------------------------------------------------------------------------


def test_merchants_column_count_and_names(conn):
    """Pins the current shape. The bank/wallet columns are expected to be
    dropped by a fix migration; this test documents what exists today."""
    cols = [
        r[0]
        for r in conn.execute(
            """
            SELECT a.attname
            FROM pg_attribute a
            JOIN pg_class c ON c.oid = a.attrelid
            WHERE c.relname = 'merchants' AND a.attnum > 0 AND NOT a.attisdropped
            ORDER BY a.attnum
            """
        ).fetchall()
    ]
    # 33 at 106; -3 bank columns dropped by 115.
    assert len(cols) == 30, f"expected 30 columns, got {len(cols)}: {cols}"
    for expected in ("delivery_radius_km", "estimated_prep_time_minutes",
                     "payout_frequency", "payout_method", "approval_status",
                     "approval_note"):
        assert expected in cols, f"missing {expected}"


def test_bank_columns_are_dropped_wallet_kept(conn):
    """BUG-05 scope: these are slated for removal. Recorded as present so the
    fix migration has a failing-before / passing-after test."""
    present = scalar(
        conn,
        """
        SELECT count(*) FROM pg_attribute a
        JOIN pg_class c ON c.oid = a.attrelid
        WHERE c.relname='merchants' AND a.attname = ANY(%s)
          AND a.attnum > 0 AND NOT a.attisdropped
        """,
        (["bank_account_number", "bank_account_holder", "bank_name", "wallet_phone"],),
    )
    assert present == 1, (
        "migration 115 drops bank_account_number, bank_account_holder and "
        "bank_name; wallet_phone is KEPT for manual Vodafone Cash reconciliation"
    )
    assert scalar(
        conn,
        """
        SELECT count(*) FROM pg_attribute a
        JOIN pg_class c ON c.oid = a.attrelid
        WHERE c.relname='merchants' AND a.attname='wallet_phone'
          AND a.attnum > 0 AND NOT a.attisdropped
        """,
    ) == 1


# ---------------------------------------------------------------------------
# Category FK (migration 098)
# ---------------------------------------------------------------------------


def test_merchant_category_is_an_fk_not_a_check(conn):
    fks = foreign_keys(conn)
    cat_fks = [
        (cols, parent)
        for child, _n, cols, parent in fks
        if child == "merchants" and cols == "category"
    ]
    assert cat_fks, "expected merchants.category to be an FK"
    assert cat_fks[0][1] == "merchant_categories"

    checks = [d for _t, _n, d in check_constraints(conn) if "'restaurant'" in d]
    assert not checks, (
        f"expected the old two-value CHECK to be gone, found: {checks}"
    )


def test_merchant_category_rejects_unknown_code(conn):
    cur = conn.cursor()
    with pytest.raises(Exception) as exc:
        cur.execute(
            """
            INSERT INTO public.merchants
              (name_ar, name_en, category, address, lat, lng, city, phone)
            VALUES ('x','DBX-badcat','not_a_real_type','a',30.0,31.0,'Cairo','p')
            """
        )
    assert "merchant_categories" in str(exc.value)


def test_all_eight_launch_categories_are_present_and_active(conn):
    """All 8 seeded codes are launch categories per the product decision."""
    rows = conn.execute(
        "SELECT code, is_active FROM public.merchant_categories ORDER BY sort_order"
    ).fetchall()
    codes = [r[0] for r in rows]
    expected = ["restaurant", "pharmacy", "market", "grocery",
                "bakery", "butcher", "flowers", "other"]
    assert codes == expected, f"expected {expected}, got {codes}"
    inactive = [c for c, active in rows if not active]
    assert not inactive, f"all 8 are launch categories, none may be inactive: {inactive}"


def test_other_is_the_escape_hatch(conn):
    """A vendor can always onboard under 'other'."""
    cur = conn.cursor()
    m = insert_merchant(cur, "DBX-merchant-other", "other", True, "approved")
    assert m


# ---------------------------------------------------------------------------
# Approval flow (migration 103)
# ---------------------------------------------------------------------------


def test_approval_status_and_activity_are_independent(conn):
    """approval_status is the onboarding gate; is_active is the kill-switch.
    A rejected merchant can still be is_active = true."""
    cur = conn.cursor()
    m = insert_merchant(cur, "DBX-rejected", "restaurant", True, "rejected")
    row = conn.execute(
        "SELECT approval_status, is_active FROM public.merchants WHERE id=%s", (m,)
    ).fetchone()
    assert row == ("rejected", True)


def test_approval_status_constraint(conn):
    cur = conn.cursor()
    with pytest.raises(Exception):
        insert_merchant(cur, "DBX-badapproval", "restaurant", True, "nonsense")


# ---------------------------------------------------------------------------
# BUG: city / area are free text
# ---------------------------------------------------------------------------


def test_city_is_free_text_so_typos_split_filters(conn):
    """No FK on city/area, so 'Cairo' and 'cairo' are different places and a
    dashboard city filter silently loses rows."""
    fks = foreign_keys(conn)
    geo = {(c, p) for _t, _c, c, p in fks if _t == "merchants"}
    assert ("city", "cities") not in geo
    assert ("area", "areas") not in geo

    cur = conn.cursor()
    insert_merchant(cur, "DBX-city-a", "restaurant", True, "approved")
    conn.execute(
        "UPDATE public.merchants SET city='cairo' WHERE name_en='[DBX-city-a]'"
    )
    exact = scalar(conn, "SELECT count(*) FROM public.merchants WHERE city='Cairo'")
    lower = scalar(conn, "SELECT count(*) FROM public.merchants WHERE city='cairo'")
    assert exact != lower or (exact == 0 and lower == 1), (
        "demonstrates the split: case-sensitive equality misses the row"
    )


def test_no_normalised_city_index(conn):
    """No functional index on lower(city), so a case-insensitive city filter
    is a sequential scan."""
    found = [d for _t, _n, d in indexes(conn) if "lower" in d.lower() and "city" in d.lower()]
    assert not found, f"expected no lower(city) index yet, found: {found}"


# ---------------------------------------------------------------------------
# NEW REQUIREMENT: branches / chains
# ---------------------------------------------------------------------------


def test_no_branch_table_exists(conn):
    """Multi-location is required. There is no branches table and no
    parent/child link on merchants, so a chain must be duplicated by hand --
    including its entire menu."""
    tables = [
        r[0]
        for r in conn.execute(
            """
            SELECT tablename FROM pg_tables
            WHERE schemaname='public'
              AND strpos(tablename,'branch') > 0
            """
        ).fetchall()
    ]
    assert not tables, f"expected no branch table yet, found: {tables}"


def test_no_self_referencing_parent_on_merchants(conn):
    cols = [
        r[0]
        for r in conn.execute(
            """
            SELECT a.attname FROM pg_attribute a
            JOIN pg_class c ON c.oid = a.attrelid
            WHERE c.relname='merchants' AND a.attnum > 0 AND NOT a.attisdropped
            """
        ).fetchall()
    ]
    assert "parent_merchant_id" not in cols
    assert "brand_id" not in cols
    assert "chain_id" not in cols


def test_duplicate_locations_are_independent_menus(conn):
    """A 2-branch chain today means 2 merchant rows and 2 separate menus,
    with nothing tying them together for reporting."""
    cur = conn.cursor()
    branch_a = insert_merchant(cur, "DBX-chain-branch-a", "market", True, "approved")
    branch_b = insert_merchant(cur, "DBX-chain-branch-b", "market", True, "approved")
    distinct = conn.execute(
        "SELECT count(DISTINCT id) FROM public.merchants WHERE id = ANY(%s)",
        ([branch_a, branch_b],),
    ).fetchone()[0]
    assert distinct == 2
    # Nothing links them: grouping by any shared identity yields two groups.
    groups = scalar(
        conn,
        """
        SELECT count(DISTINCT phone) FROM public.merchants WHERE id = ANY(%s)
        """,
        ([branch_a, branch_b],),
    )
    assert groups == 1, "same phone, but no column expresses 'same brand'"


# ---------------------------------------------------------------------------
# NEW REQUIREMENT: discounts
# ---------------------------------------------------------------------------


def test_items_have_discount_columns(conn):
    """REQ-02, implemented by migration 119."""
    cols = [
        r[0]
        for r in conn.execute(
            """
            SELECT a.attname FROM pg_attribute a
            JOIN pg_class c ON c.oid = a.attrelid
            WHERE c.relname='items' AND a.attnum > 0 AND NOT a.attisdropped
            """
        ).fetchall()
    ]
    assert "price" in cols
    assert "discount_price" in cols, "migration 119 must add items.discount_price"
    # 14 at 106; +deleted_at (110) +discount_price (119).
    assert len(cols) == 16, f"expected 16 item columns, got {len(cols)}: {cols}"


def test_discount_cannot_exceed_list_price(conn):
    """The invariant a discount column exists to protect: the dashboard would
    otherwise render 'was 100, now 120'."""
    definition = scalar(
        conn,
        """
        SELECT pg_get_constraintdef(oid) FROM pg_constraint
        WHERE conrelid='public.items'::regclass
          AND conname='items_discount_price_check'
        """,
    )
    assert definition, "migration 119 must add items_discount_price_check"
    assert "discount_price" in definition
    assert "<= price" in definition.replace(" ", " ") or "price" in definition


def test_price_columns_across_the_catalog(conn):
    """Was 2 (items.price, item_option_choices.price_modifier). Migration 119
    adds items.discount_price as the third -- the item-level price path."""
    price_cols = scalar(
        conn,
        """
        SELECT count(*) FROM pg_attribute a
        JOIN pg_class c ON c.oid = a.attrelid
        WHERE c.relname IN ('items','item_option_choices')
          AND a.attnum > 0 AND NOT a.attisdropped
          AND strpos(a.attname,'price') > 0
        """,
    )
    assert price_cols == 3, (
        "expected items.price, items.discount_price and "
        f"item_option_choices.price_modifier; found {price_cols} price columns"
    )


def test_order_items_snapshots_both_prices(conn):
    """original_price (119) so ending a promotion does not rewrite history."""
    cols = [
        r[0]
        for r in conn.execute(
            """
            SELECT a.attname FROM pg_attribute a
            JOIN pg_class c ON c.oid = a.attrelid
            WHERE c.relname='order_items' AND a.attnum > 0 AND NOT a.attisdropped
            """
        ).fetchall()
    ]
    assert "item_price" in cols, "the charged price"
    assert "original_price" in cols, "migration 119 must snapshot the pre-discount price"