"""Test 09 -- Item-level discounts (REQ-02, migration 119).

The gap 119 closes: across items and item_option_choices there were exactly two
price columns, so a "was 100, now 80" item was impossible. Option-level
reductions arrived with migration 111; item-level now follows.

Covered here:
  * the column and its CHECK
  * the effective price the menu must show
  * that place_order_with_items applies the discount SERVER-side, so a client
    cannot send an undiscounted price and have it honoured (the reason 119 had to
    touch the function at all)
  * that order_items keeps the pre-discount price, so history survives the
    promotion ending
  * interaction with option modifiers
"""

from __future__ import annotations

import json
import uuid

import pytest

from conftest import begin, insert_category, insert_item, insert_merchant, scalar


@pytest.fixture
def shop(conn):
    """merchant -> category -> one undiscounted item at 100.00"""
    cur = conn.cursor()
    m = insert_merchant(cur, "DBX-disc-m", "restaurant", True, "approved")
    c = insert_category(cur, "DBX-disc-c", m)
    i = insert_item(cur, "DBX-disc-item", m, c, 100.00)
    return m, c, i


def set_discount(conn, item_id, amount):
    """Set or clear an item's discount_price. `amount=None` clears it."""
    conn.execute(
        "UPDATE public.items SET discount_price = %s WHERE id = %s",
        (amount, item_id),
    )


# ---------------------------------------------------------------------------
# 1. The column and its constraint
# ---------------------------------------------------------------------------


def test_discount_price_column_exists(conn):
    cols = {
        r[0]
        for r in conn.execute(
            """
            SELECT a.attname FROM pg_attribute a
            JOIN pg_class c ON c.oid = a.attrelid
            WHERE c.relname='items' AND a.attnum > 0 AND NOT a.attisdropped
            """
        ).fetchall()
    }
    assert "discount_price" in cols, "migration 119 must add items.discount_price"
    assert "price" in cols


def test_discount_price_defaults_to_null_which_means_undiscounted(conn, shop):
    _m, _c, item = shop
    assert scalar(
        conn, "SELECT discount_price FROM public.items WHERE id=%s", (item,)
    ) is None, "NULL must mean not discounted, not zero"


def test_discount_below_list_price_is_accepted(conn, shop):
    _m, _c, item = shop
    set_discount(conn, item, 80.00)
    assert float(
        scalar(conn, "SELECT discount_price FROM public.items WHERE id=%s", (item,))
    ) == 80.00


def test_discount_equal_to_list_price_is_allowed(conn, shop):
    """Not a discount, but harmless -- the CHECK permits it rather than
    pretending to police intent."""
    _m, _c, item = shop
    set_discount(conn, item, 100.00)


def test_discount_above_list_price_is_rejected(conn, shop):
    """A price rise wearing a discount's name. The dashboard would render
    "was 100, now 120"."""
    _m, _c, item = shop
    with pytest.raises(Exception) as exc:
        set_discount(conn, item, 120.00)
    begin(conn)
    assert "items_discount_price_check" in str(exc.value)


def test_negative_discount_is_rejected(conn, shop):
    _m, _c, item = shop
    with pytest.raises(Exception) as exc:
        set_discount(conn, item, -5.00)
    begin(conn)
    assert "items_discount_price_check" in str(exc.value)


def test_constraint_is_reevaluated_on_every_update(conn, shop):
    """Setting discount_price, then lowering price below it, must fail too --
    the CHECK is evaluated on every UPDATE, not only on insert."""
    _m, _c, item = shop
    set_discount(conn, item, 80.00)
    with pytest.raises(Exception) as exc:
        conn.execute("UPDATE public.items SET price = 50.00 WHERE id = %s", (item,))
    begin(conn)
    assert "items_discount_price_check" in str(exc.value)


# ---------------------------------------------------------------------------
# 2. Effective price, the value the menu must show
# ---------------------------------------------------------------------------


def test_effective_price_expression(conn, shop):
    """The single expression every reader must use. Pinned here so a future
    migration cannot quietly change the pricing rule."""
    _m, _c, item = shop
    set_discount(conn, item, 80.00)
    eff = scalar(
        conn,
        "SELECT COALESCE(discount_price, price) FROM public.items WHERE id=%s",
        (item,),
    )
    assert float(eff) == 80.00

    set_discount(conn, item, None)
    assert float(
        scalar(
            conn,
            "SELECT COALESCE(discount_price, price) FROM public.items WHERE id=%s",
            (item,),
        )
    ) == 100.00


def test_discount_survives_a_catalog_read(conn, shop):
    _m, _c, item = shop
    set_discount(conn, item, 75.00)
    row = conn.execute(
        "SELECT price, discount_price FROM public.items WHERE id=%s", (item,)
    ).fetchone()
    assert float(row[0]) == 100.00
    assert float(row[1]) == 75.00


# ---------------------------------------------------------------------------
# 3. place_order applies it server-side
# ---------------------------------------------------------------------------


def _customer(conn) -> uuid.UUID:
    uid = uuid.uuid4()
    conn.execute("INSERT INTO auth.users (id) VALUES (%s)", (uid,))
    return uid


def _place(conn, merchant_id, customer_id, item_id, quantity=1, claimed_price=None,
           selected=None):
    """Call place_order_with_items as service_role.

    `claimed_price` deliberately sends a lie for item_price so the test can
    prove the function ignores it. `selected` carries option selections.
    """
    conn.execute(
        "SELECT set_config('request.jwt.claims', %s, true)",
        ('{"role":"service_role"}',),
    )
    payload_item = {
        "item_id": str(item_id),
        "item_name_ar": "كشري",
        "item_name_en": "Koshari",
        "quantity": quantity,
        "selected_options": selected or [],
        "special_instructions": None,
    }
    if claimed_price is not None:
        payload_item["item_price"] = claimed_price
        payload_item["total_price"] = claimed_price * quantity
    order = {
        "customer_id": str(customer_id),
        "merchant_id": str(merchant_id),
        "status": "pending",
        "delivery_address": {"address": "1 Test St"},
        "subtotal": 999999.00,
        "total": 999999.00,
        "payment_method": "cash",
        "idempotency_key": str(uuid.uuid4()),
    }
    rows = conn.execute(
        "SELECT * FROM public.place_order_with_items(%s::jsonb, %s::jsonb)",
        (json.dumps(order), json.dumps([payload_item])),
    ).fetchall()
    return rows[0][0]



def test_order_uses_the_discounted_price(conn, shop):
    m, _c, item = shop
    set_discount(conn, item, 80.00)
    cust = _customer(conn)
    order_id = _place(conn, m, cust, item, quantity=2)

    line = conn.execute(
        "SELECT item_price, original_price, quantity, total_price"
        " FROM public.order_items WHERE order_id=%s",
        (order_id,),
    ).fetchone()
    assert float(line[0]) == 80.00, "the customer must be charged the discount price"
    assert float(line[1]) == 100.00, "the pre-discount price must be snapshotted"
    assert int(line[2]) == 2
    assert float(line[3]) == 160.00


def test_client_cannot_override_the_price(conn, shop):
    """The reason migration 119 had to touch place_order_with_items at all.

    Before it, item_price came from the request. A client sending the list
    price would have paid full price on a "discounted" item -- or worse, a
    tampered payload set its own price.
    """
    m, _c, item = shop
    set_discount(conn, item, 80.00)
    cust = _customer(conn)
    order_id = _place(conn, m, cust, item, quantity=1, claimed_price=1.00)

    line = conn.execute(
        "SELECT item_price, total_price FROM public.order_items WHERE order_id=%s",
        (order_id,),
    ).fetchone()
    assert float(line[0]) == 80.00, "a client-supplied item_price of 1.00 must be ignored"
    assert float(line[1]) == 80.00


def test_order_subtotal_is_server_derived(conn, shop):
    """The payload claims a subtotal of 999,999. It must be ignored."""
    m, _c, item = shop
    set_discount(conn, item, 80.00)
    cust = _customer(conn)
    order_id = _place(conn, m, cust, item, quantity=3)

    subtotal = scalar(
        conn, "SELECT subtotal FROM public.orders WHERE id=%s", (order_id,)
    )
    assert float(subtotal) == 240.00, (
        f"subtotal must be derived from the priced lines, got {subtotal}"
    )


def test_order_total_reconciles_with_its_lines(conn, shop):
    m, _c, item = shop
    set_discount(conn, item, 80.00)
    cust = _customer(conn)
    order_id = _place(conn, m, cust, item, quantity=2)

    header, lines = conn.execute(
        """
        SELECT o.subtotal,
               COALESCE((SELECT sum(total_price) FROM order_items
                          WHERE order_id = o.id), 0)
          FROM orders o WHERE o.id = %s
        """,
        (order_id,),
    ).fetchone()
    assert float(header) == float(lines) == 160.00


def test_undiscounted_order_is_unchanged(conn, shop):
    """No discount_price means behaviour is identical to migration 117."""
    m, _c, item = shop
    cust = _customer(conn)
    order_id = _place(conn, m, cust, item, quantity=2)

    line = conn.execute(
        "SELECT item_price, original_price, total_price"
        " FROM public.order_items WHERE order_id=%s",
        (order_id,),
    ).fetchone()
    assert float(line[0]) == 100.00
    assert float(line[1]) == 100.00, "original_price equals item_price when not discounted"
    assert float(line[2]) == 200.00


# ---------------------------------------------------------------------------
# 4. History survives the promotion ending
# ---------------------------------------------------------------------------


def test_original_price_records_the_promotion_after_it_ends(conn, shop):
    m, _c, item = shop
    set_discount(conn, item, 70.00)
    cust = _customer(conn)
    during = _place(conn, m, cust, item)

    set_discount(conn, item, None)  # promotion ends

    after = conn.execute(
        "SELECT item_price, original_price FROM public.order_items WHERE order_id=%s",
        (during,),
    ).fetchone()
    assert float(after[0]) == 70.00, "the price charged is frozen"
    assert float(after[1]) == 100.00, (
        "original_price must still show the list price after the discount is "
        "removed, otherwise history silently rewrites itself"
    )

    # And a new order now charges full price.
    cust2 = _customer(conn)
    later = _place(conn, m, cust2, item)
    assert float(
        scalar(
            conn, "SELECT item_price FROM public.order_items WHERE order_id=%s", (later,)
        )
    ) == 100.00


def test_discount_adoption_is_reportable(conn, shop):
    """The reporting query 119 documents actually runs."""
    m, _c, item = shop
    set_discount(conn, item, 60.00)
    cust = _customer(conn)
    _place(conn, m, cust, item)

    discounted, total = conn.execute(
        """
        SELECT count(*) FILTER (WHERE original_price > item_price),
               count(*)
          FROM public.order_items
        """
    ).fetchone()
    assert discounted == 1
    assert total >= 1


# ---------------------------------------------------------------------------
# 5. Interaction with option modifiers
# ---------------------------------------------------------------------------


def test_discount_composes_with_option_modifiers(conn, shop):
    """A discounted base plus an option surcharge must stack."""
    m, _c, item = shop
    cur = conn.cursor()
    opt = conn.execute(
        """
        INSERT INTO public.item_options (item_id, name_ar, name_en, is_required,
                                         max_selections, min_selections)
        VALUES (%s, 'الحجم', 'Size', TRUE, 1, 1)
        RETURNING id
        """,
        (item,),
    ).fetchone()[0]
    conn.execute(
        """
        INSERT INTO public.item_option_choices
          (option_id, name_ar, name_en, price_modifier, is_default)
        VALUES (%s, 'كبير', 'Large', 20.00, TRUE)
        """,
        (opt,),
    )

    set_discount(conn, item, 80.00)
    cust = _customer(conn)
    order_id = _place(
        conn, m, cust, item, quantity=1,
        selected=[{"option_name_en": "Size", "choice_name_en": "Large"}],
    )

    line = conn.execute(
        "SELECT item_price, total_price, selected_options FROM public.order_items"
        " WHERE order_id=%s",
        (order_id,),
    ).fetchone()
    assert float(line[0]) == 80.00, "base is discounted"
    assert float(line[1]) == 100.00, "80.00 discounted base + 20.00 Large modifier"


def test_modifier_cannot_exceed_the_discounted_base(conn, shop):
    """BUG-06 follow-up: with reductions allowed, a modifier must not push the
    line negative. Now enforced against the SELL price, not the list price."""
    m, _c, item = shop
    cur = conn.cursor()
    opt = conn.execute(
        """
        INSERT INTO public.item_options (item_id, name_ar, name_en, is_required,
                                         max_selections, min_selections)
        VALUES (%s, 'إضافات', 'Extras', FALSE, NULL, 0)
        RETURNING id
        """,
        (item,),
    ).fetchone()[0]
    conn.execute(
        """
        INSERT INTO public.item_option_choices
          (option_id, name_ar, name_en, price_modifier, is_default)
        VALUES (%s, 'خصم كبير', 'Big discount', -150.00, TRUE)
        """,
        (opt,),
    )
    set_discount(conn, item, 100.00)
    cust = _customer(conn)

    conn.execute(
        "SELECT set_config('request.jwt.claims', %s, true)", ('{"role":"service_role"}',)
    )
    with pytest.raises(Exception) as exc:
        conn.execute(
            "SELECT public.place_order_with_items(%s::jsonb, %s::jsonb)",
            (
                json.dumps({
                    "customer_id": str(cust),
                    "merchant_id": str(m),
                    "delivery_address": {"address": "1 St"},
                    "idempotency_key": str(uuid.uuid4()),
                }),
                json.dumps([{
                    "item_id": str(item),
                    "quantity": 1,
                    "selected_options": [
                        {"option_name_en": "Extras", "choice_name_en": "Big discount"}
                    ],
                }]),
            ),
        )
    begin(conn)
    assert "exceeds item price" in str(exc.value).lower()


# ---------------------------------------------------------------------------
# 6. Interaction with soft delete and availability
# ---------------------------------------------------------------------------


def test_soft_deleted_item_cannot_be_ordered(conn, shop):
    """119 added an explicit deleted_at check; 110 added the column but left
    the read sites to the application."""
    m, _c, item = shop
    conn.execute("UPDATE public.items SET deleted_at = now() WHERE id=%s", (item,))
    cust = _customer(conn)
    conn.execute(
        "SELECT set_config('request.jwt.claims', %s, true)", ('{"role":"service_role"}',)
    )
    with pytest.raises(Exception) as exc:
        conn.execute(
            "SELECT public.place_order_with_items(%s::jsonb, %s::jsonb)",
            (
                json.dumps({
                    "customer_id": str(cust),
                    "merchant_id": str(m),
                    "delivery_address": {"address": "1 St"},
                    "idempotency_key": str(uuid.uuid4()),
                }),
                json.dumps([{"item_id": str(item), "quantity": 1}]),
            ),
        )
    begin(conn)
    assert "unavailable" in str(exc.value).lower()


def test_unavailable_item_cannot_be_ordered(conn, shop):
    m, _c, item = shop
    conn.execute("UPDATE public.items SET is_available = false WHERE id=%s", (item,))
    cust = _customer(conn)
    conn.execute(
        "SELECT set_config('request.jwt.claims', %s, true)", ('{"role":"service_role"}',)
    )
    with pytest.raises(Exception) as exc:
        conn.execute(
            "SELECT public.place_order_with_items(%s::jsonb, %s::jsonb)",
            (
                json.dumps({
                    "customer_id": str(cust),
                    "merchant_id": str(m),
                    "delivery_address": {"address": "1 St"},
                    "idempotency_key": str(uuid.uuid4()),
                }),
                json.dumps([{"item_id": str(item), "quantity": 1}]),
            ),
        )
    begin(conn)
    assert "unavailable" in str(exc.value).lower()


def test_unapproved_merchant_cannot_take_orders(conn, shop):
    """BUG-13's gate extended to the order path."""
    m, _c, item = shop
    conn.execute(
        "UPDATE public.merchants SET approval_status = 'pending' WHERE id=%s", (m,)
    )
    cust = _customer(conn)
    conn.execute(
        "SELECT set_config('request.jwt.claims', %s, true)", ('{"role":"service_role"}',)
    )
    with pytest.raises(Exception) as exc:
        conn.execute(
            "SELECT public.place_order_with_items(%s::jsonb, %s::jsonb)",
            (
                json.dumps({
                    "customer_id": str(cust),
                    "merchant_id": str(m),
                    "delivery_address": {"address": "1 St"},
                    "idempotency_key": str(uuid.uuid4()),
                }),
                json.dumps([{"item_id": str(item), "quantity": 1}]),
            ),
        )
    begin(conn)
    assert "merchant not found" in str(exc.value).lower()


def test_non_service_role_cannot_place_orders(conn, shop):
    m, _c, item = shop
    cust = _customer(conn)
    with pytest.raises(Exception) as exc:
        conn.execute(
            "SELECT public.place_order_with_items(%s::jsonb, %s::jsonb)",
            (
                json.dumps({
                    "customer_id": str(cust),
                    "merchant_id": str(m),
                    "delivery_address": {"address": "1 St"},
                    "idempotency_key": str(uuid.uuid4()),
                }),
                json.dumps([{"item_id": str(item), "quantity": 1}]),
            ),
        )
    begin(conn)
    assert "service-role only" in str(exc.value).lower()


# ---------------------------------------------------------------------------
# 7. Scale
# ---------------------------------------------------------------------------


def test_discounted_items_filter_has_a_partial_index(conn):
    """REQ-02: the dashboard's "items on promotion" filter needs an index.

    Structural assertion, because the planner is right not to use it at seed
    volumes: ~12% of items are discounted, and scanning all 2,400 rows for 2,220
    matches costs fewer buffers than an index scan. Same lesson as the review
    badge count -- partial indexes only pay once the filtered fraction is small.
    """
    if scalar(conn, "SELECT count(*) FROM public.items") < 2000:
        pytest.skip("needs seed_data.py")

    idx = scalar(
        conn,
        """
        SELECT count(*) FROM pg_indexes
        WHERE schemaname='public' AND tablename='items'
          AND strpos(indexdef, 'discount_price') > 0
        """,
    )
    assert idx == 1, "migration 119 must add idx_items_discounted"


def test_discounted_items_report_is_queryable_at_scale(conn):
    """Runs the documented report end to end at volume.

    Not asserted on plan shape -- with a LEFT JOIN over all order history the
    order_items side genuinely needs a pass. What matters is that it completes
    and returns one row per discounted item.
    """
    if scalar(conn, "SELECT count(*) FROM public.items") < 2000:
        pytest.skip("needs seed_data.py")

    discounted = scalar(
        conn, "SELECT count(*) FROM public.items WHERE discount_price IS NOT NULL"
    )
    assert discounted > 100, "expected a real promotion set in the seed"

    rows = conn.execute(
        """
        SELECT i.id, i.price, i.discount_price, count(oi.id) AS sold
          FROM public.items i
          LEFT JOIN public.order_items oi ON oi.item_id = i.id
         WHERE i.discount_price IS NOT NULL
         GROUP BY 1, 2, 3
         ORDER BY sold DESC
         LIMIT 20
        """
    ).fetchall()
    assert len(rows) == 20
    for _id, was, now, _sold in rows:
        assert float(now) <= float(was), "a discount must never exceed the list price"


def test_selective_discount_filter_uses_the_index(conn):
    """Where the partial index does pay: a specific price value."""
    if scalar(conn, "SELECT count(*) FROM public.items") < 2000:
        pytest.skip("needs seed_data.py")
    price = scalar(
        conn,
        "SELECT discount_price FROM public.items"
        " WHERE discount_price IS NOT NULL LIMIT 1",
    )
    text = "\n".join(
        r[0]
        for r in conn.execute(
            "EXPLAIN (ANALYZE) SELECT id FROM public.items WHERE discount_price = %s",
            (price,),
        ).fetchall()
    )
    assert "idx_items_discounted" in text, (
        f"a selective discount_price filter should use the partial index:\n{text}"
    )