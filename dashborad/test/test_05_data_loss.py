"""Test 05 -- data loss: deleting catalog rows destroys order history.

BUG-08  items and categories have NO deleted_at column. Migration 068 added
        soft delete to promo_codes and promoted_slots but never to the menu.
        Combined with order_items.item_id ON DELETE CASCADE (007:105), a hard
        DELETE of an item silently erases every order line that referenced it.

        The dashboard therefore cannot offer a Delete button on an item without
        either losing revenue history or needing a fix migration first.
"""

from __future__ import annotations

import uuid

import pytest

from conftest import insert_category, insert_item, insert_merchant, make_customer, scalar


def _auth_user(conn) -> uuid.UUID:
    """A profiles row, created via auth.users so the 002 trigger fires."""
    return make_customer(conn)


def _order_for_item(conn, merchant_id, item_id, customer_id) -> tuple[uuid.UUID, uuid.UUID]:
    order_id = uuid.uuid4()
    line_id = uuid.uuid4()
    conn.execute(
        """
        INSERT INTO public.orders
          (id, order_number, customer_id, merchant_id, delivery_address,
           subtotal, total, status)
        VALUES (%s, %s, %s, %s, '{}'::jsonb, 45.00, 45.00, 'delivered')
        """,
        (order_id, f"DBX-{str(order_id)[:8].upper()}", customer_id, merchant_id),
    )
    conn.execute(
        """
        INSERT INTO public.order_items
          (id, order_id, item_id, item_name_ar, item_name_en, item_price,
           quantity, total_price)
        VALUES (%s, %s, %s, 'كشري', 'Koshari', 45.00, 1, 45.00)
        """,
        (line_id, order_id, item_id),
    )
    return order_id, line_id


def test_menu_tables_have_deleted_at(conn):
    # Only items and categories are user-deletable. item_options and
    # item_option_choices are configuration that cascades with their item.
    for table in ("items", "categories"):
        n = scalar(
            conn,
            """
            SELECT count(*) FROM pg_attribute a
            JOIN pg_class c ON c.oid = a.attrelid
            WHERE c.relname=%s AND a.attname='deleted_at'
              AND a.attnum > 0 AND NOT a.attisdropped
            """,
            (table,),
        )
        assert n == 1, f"migration 110 must add {table}.deleted_at"


def test_promo_and_ad_tables_do_have_soft_delete(conn):
    """The pattern already exists elsewhere, which is why the gap is a bug and
    not a missing feature."""
    for table in ("promo_codes", "promoted_slots"):
        n = scalar(
            conn,
            """
            SELECT count(*) FROM pg_attribute a
            JOIN pg_class c ON c.oid = a.attrelid
            WHERE c.relname=%s AND a.attname='deleted_at'
              AND a.attnum > 0 AND NOT a.attisdropped
            """,
            (table,),
        )
        assert n == 1, f"{table} should already have deleted_at"


def test_hard_deleting_an_item_preserves_order_lines(conn):
    """BUG-08 reproduced end-to-end: the order survives, the line vanishes."""
    cur = conn.cursor()
    customer = _auth_user(conn)
    m = insert_merchant(cur, "DBX-loss-m", "restaurant", True, "approved")
    c = insert_category(cur, "DBX-loss-c", m)
    i = insert_item(cur, "DBX-loss-item", m, c, 45.00)

    order_id, line_id = _order_for_item(conn, m, i, customer)
    assert scalar(conn, "SELECT count(*) FROM public.order_items WHERE id=%s", (line_id,)) == 1

    cur.execute("DELETE FROM public.items WHERE id=%s", (i,))

    assert scalar(conn, "SELECT count(*) FROM public.order_items WHERE id=%s", (line_id,)) == 1, (
        "migration 110 changed item_id to ON DELETE SET NULL, so the order line "
        "must survive a hard delete"
    )
    assert scalar(conn, "SELECT count(*) FROM public.orders WHERE id=%s", (order_id,)) == 1
    assert scalar(
        conn, "SELECT count(*) FROM public.order_items WHERE id=%s AND item_id IS NULL", (line_id,)
    ) == 1, "the pointer is nulled but the frozen snapshot is retained"


def test_order_stays_reconcilable_after_item_deletion(conn):
    """The order total says 45 EGP but sums to 0 across its lines."""
    cur = conn.cursor()
    customer = _auth_user(conn)
    m = insert_merchant(cur, "DBX-loss2-m", "restaurant", True, "approved")
    c = insert_category(cur, "DBX-loss2-c", m)
    i = insert_item(cur, "DBX-loss2-item", m, c, 45.00)

    order_id, _ = _order_for_item(conn, m, i, customer)
    cur.execute("DELETE FROM public.items WHERE id=%s", (i,))

    totals = conn.execute(
        """
        SELECT o.total, COALESCE(SUM(oi.total_price), 0)
        FROM public.orders o
        LEFT JOIN public.order_items oi ON oi.order_id = o.id
        WHERE o.id = %s
        GROUP BY o.total
        """,
        (order_id,),
    ).fetchone()
    assert totals[0] == 45.0
    assert float(totals[1]) == 45.0, (
        "migration 110 keeps the line, so the order still reconciles"
    )


def test_deleting_a_category_cascades_to_its_items(conn):
    """Which then cascades to the order lines, same data loss one level up."""
    cur = conn.cursor()
    customer = _auth_user(conn)
    m = insert_merchant(cur, "DBX-loss3-m", "restaurant", True, "approved")
    c = insert_category(cur, "DBX-loss3-c", m)
    i = insert_item(cur, "DBX-loss3-item", m, c, 45.00)
    order_id, _line = _order_for_item(conn, m, i, customer)

    cur.execute("DELETE FROM public.categories WHERE id=%s", (c,))

    assert scalar(conn, "SELECT count(*) FROM public.items WHERE id=%s", (i,)) == 0
    assert scalar(
        conn,
        "SELECT count(*) FROM public.order_items WHERE order_id=%s",
        (order_id,),
    ) == 1, "the order line survives a category cascade too"


def test_order_item_snapshot_survives_history(conn):
    """order_items stores frozen names and prices, so the DISPLAY survives --
    but only while the row exists. The cascade takes the snapshot with it."""
    cur = conn.cursor()
    customer = _auth_user(conn)
    m = insert_merchant(cur, "DBX-loss4-m", "restaurant", True, "approved")
    c = insert_category(cur, "DBX-loss4-c", m)
    i = insert_item(cur, "DBX-loss4-item", m, c, 45.00)
    _order_for_item(conn, m, i, customer)

    snapshot_before = conn.execute(
        "SELECT item_name_en, item_price FROM public.order_items"
    ).fetchall()
    assert snapshot_before

    cur.execute("DELETE FROM public.items WHERE id=%s", (i,))

    assert scalar(
        conn, "SELECT count(*) FROM public.order_items WHERE item_name_en='Koshari'"
    ) == 1, "the frozen snapshot must outlive the catalog row"