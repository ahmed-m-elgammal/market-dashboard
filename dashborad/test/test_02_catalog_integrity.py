"""Test 02 -- catalog referential integrity between merchants, categories, items.

BUG-03  items carries BOTH merchant_id and category_id with no constraint tying
        them together (migration 007:50-51). An item can be filed under a
        category that belongs to a different merchant.
"""

from __future__ import annotations

import pytest

from conftest import begin, foreign_keys, insert_category, insert_item, insert_merchant, scalar


def test_item_cannot_be_filed_under_another_merchants_category(conn):
    """BUG-03 reproduced: cross-merchant category wiring is accepted."""
    cur = conn.cursor()
    merchant_a = insert_merchant(cur, "DBX-mA", "restaurant", True, "approved")
    merchant_b = insert_merchant(cur, "DBX-mB", "grocery", True, "approved")

    cat_of_a = insert_category(cur, "DBX-cat-of-A", merchant_a)
    with pytest.raises(Exception) as exc:
        insert_item(cur, "DBX-item-on-B", merchant_b, cat_of_a, 99.00)
    begin(conn)
    assert "items_category_merchant_fk" in str(exc.value), (
        "expected the composite FK from migration 112 to reject this"
    )

    # Nothing was written.
    row = conn.execute(
        """
        SELECT count(*) FROM public.items i
        JOIN public.categories c ON c.id = i.category_id
        WHERE i.merchant_id IS DISTINCT FROM c.merchant_id
        """
    ).fetchone()
    assert row == (0,), "no mis-filed item should exist after migration 112"


def test_no_constraint_enforces_item_category_ownership(conn):
    """Static proof: the only FK on items is the two independent single-column
    ones. Nothing is composite over (category_id, merchant_id)."""
    fks = foreign_keys(conn)
    item_fks = [(child, cols, parent) for child, _name, cols, parent in fks if child == "items"]
    assert item_fks, "expected at least the merchant_id and category_id FKs on items"

    col_sets = {frozenset(c.split(",")) for _c, c, _p in item_fks}
    assert frozenset({"merchant_id"}) in col_sets
    assert frozenset({"category_id"}) in col_sets
    assert (
        frozenset({"category_id", "merchant_id"}) in col_sets
    ), "migration 112 must add a composite FK tying item to its category's merchant"


def test_merchant_id_is_denormalised_on_items(conn):
    """items.merchant_id duplicates data derivable from category_id. The two
    can drift, which is exactly BUG-03. Any drift already present?"""
    drifted = scalar(
        conn,
        """
        SELECT count(*) FROM public.items i
        JOIN public.categories c ON c.id = i.category_id
        WHERE i.merchant_id IS DISTINCT FROM c.merchant_id
        """,
    )
    assert drifted == 0, (
        f"{drifted} existing item(s) already have merchant_id disagreeing with "
        "their category's merchant_id"
    )


def test_categories_cascade_delete_with_merchant(conn):
    """Deleting a merchant removes its categories (ON DELETE CASCADE)."""
    cur = conn.cursor()
    m = insert_merchant(cur, "DBX-cascade", "restaurant", True, "approved")
    c = insert_category(cur, "DBX-cat-cascade", m)
    i = insert_item(cur, "DBX-item-cascade", m, c)

    cur.execute("DELETE FROM public.merchants WHERE id = %s", (m,))

    assert scalar(conn, "SELECT count(*) FROM public.categories WHERE id = %s", (c,)) == 0
    assert scalar(conn, "SELECT count(*) FROM public.items WHERE id = %s", (i,)) == 0


def test_menu_query_index_serves_the_main_read(conn):
    """The dashboard menu query is merchant + category + availability.
    A matching index must exist or every menu load is a sequential scan."""
    idx = scalar(
        conn,
        """
        SELECT indexdef FROM pg_indexes
        WHERE schemaname='public' AND tablename='items'
          AND strpos(indexdef,'merchant_id') > 0
          AND strpos(indexdef,'category_id') > 0
          AND strpos(indexdef,'is_available') > 0
        """,
    )
    assert idx, "expected an index covering (merchant_id, category_id, is_available)"
