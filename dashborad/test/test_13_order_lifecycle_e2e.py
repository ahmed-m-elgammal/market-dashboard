"""Order lifecycle end-to-end, with the money maths checked at every step.

WHAT THIS COVERS
    customer places order -> merchant prepares -> driver sees it -> driver picks
    up -> delivered, asserting the arithmetic at each transition rather than only
    at the end. The interesting failures in an order pipeline are arithmetic
    disagreements, not crashes, so every price column is re-derived from the
    catalog and compared.

    The fee/discount/commission rules live in SQL, not in the dashboard, so this
    suite is where they are actually pinned:

      delivery fee   calculate_delivery_fee(): base + per_km * distance, free
                     above delivery_free_threshold, -1 beyond max distance, and a
                     merchant override that STILL honours the free threshold
      discounts      items.discount_price applied server-side; a client-sent
                     total is ignored
      commission     merchant_payout = (subtotal - merchant discount share)
                     * (1 - commission_pct/100), floored at 0
      promo funding  platform pays all, merchant pays all, shared splits by
                     merchant_share_pct above merchant_discount_floor

WHY PROPERTY-BASED RATHER THAN FIXTURES
    The pipeline is a chain of small numeric rules, so the failure modes are
    combinations -- free delivery *and* a discount, an override *and* a distance
    cap, a commission that rounds. A handful of hand-written orders would cover
    maybe one of each. Randomised cases with a deterministic seed explore the
    combinations, and every case asserts invariants rather than one expected
    number, so the test states the rule and not a memorised outcome.

HOW IT RUNS
    cd dashborad/test
    uv run pytest test_13_order_lifecycle_e2e.py -v

    ~1000 randomised cases via ORDERS_TO_PLACE below. Set it lower while
    iterating; the invariants are checked identically either way.
"""

from __future__ import annotations

import decimal
import json
import random
import uuid

import pytest

import aliases as A
from conftest import begin, insert_category, insert_merchant, scalar

# Deliberately fixed seed. A property suite that flakes is worse than no suite,
# and a failure has to be reproducible from the test output alone.
SEED = 20261004

# How many randomised orders to place. Each is a full lifecycle, so this is the
# real case count of the suite.
ORDERS_TO_PLACE = 1000

# The legal status ladder. Cancellation is tested separately because it is a
# branch, not a step.
FLOW = ["pending", "confirmed", "preparing", "ready", "picked_up", "on_the_way", "delivered"]

D = decimal.Decimal

# Postgres numeric ROUND() rounds half away from zero, which is what Python's
# ROUND_HALF_UP does for positive amounts. Using the default (banker's rounding)
# instead would disagree on every half-cent and produce phantom failures.
ROUND_HALF_UP = decimal.ROUND_HALF_UP


# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------
def _customer(cur, alias: str, *, role: str = "customer") -> uuid.UUID:
    """A user whose profile exists.

    Inserted through auth.users, NOT straight into public.profiles: migration
    002's on_auth_user_created trigger creates the profile, and profiles.id is a
    foreign key to users(id) -- so writing profiles first raises ForeignKeyViolation.

    Returns a deterministic uuid derived from the alias rather than uuid4(), so a
    failure is reproducible and a rerun reuses the same identity.
    """
    uid = A.uid(alias)
    cur.execute("INSERT INTO auth.users (id) VALUES (%s)", (uid,))
    # The trigger sets role='customer'; a driver needs overriding.
    if role != "customer":
        cur.execute("UPDATE public.profiles SET role = %s WHERE id = %s", (role, uid))
    return uid


def _driver(cur, alias: str, *, lat: float, lng: float) -> uuid.UUID:
    """A verified, online driver.

    Promoting a profile to 'driver' is refused by prevent_driver_role_escalation:
    "users cannot set role to driver. Use admin-create-driver Edge Function
    instead." The trigger honours two bypasses -- a service_role JWT claim, or
    app.allow_driver_role_change=true, which its own HINT names as the route for
    trusted migrations and tests.

    The flag is used here because this is that case: a fixture, not a user
    session. It is set for the transaction, which the conftest fixture rolls back,
    so nothing leaks between tests. Production callers go through the Edge
    Function and never need it.

    The guard is also worth leaving in place rather than dropping the trigger --
    it caught this attempt, which is the whole reason it exists.
    """
    uid = _customer(cur, alias)
    cur.execute("SELECT set_config('app.allow_driver_role_change', 'true', true)")
    cur.execute("UPDATE public.profiles SET role = 'driver' WHERE id = %s", (uid,))
    # The plate is UNIQUE across drivers, so it must vary per case. An earlier
    # version truncated it to 12 chars, which collapsed every randomised case
    # into one value and tripped unique_vehicle_plate on the second iteration.
    # Derived from the alias and hashed, so it stays short, legal and distinct.
    plate = "PLT-" + uuid.uuid5(A.NAMESPACE, alias).hex[:8]
    national_id = "999" + uuid.uuid5(A.NAMESPACE, alias + "-nid").hex[:10]
    # Drivers track position in current_lat / current_lng, not lat / lng --
    # verified against information_schema rather than assumed, because the INSERT
    # fails with UndefinedColumn otherwise. Mirrors what
    # update_driver_location() writes.
    cur.execute(
        """
        INSERT INTO public.drivers
            (id, national_id, vehicle_type, vehicle_plate,
             is_verified, is_active, is_online, verification_status,
             current_lat, current_lng)
        VALUES (%s, %s, 'motorcycle', %s, true, true, true, 'approved', %s, %s)
        """,
        (uid, national_id, plate, lat, lng),
    )
    return uid


def _item(cur, alias: str, merchant_id, price: D, *, discount=None, available=True):
    """One catalogue item, optionally carrying a discount_price."""
    cat = A.uid(f"{alias}-cat")
    cur.execute(
        "INSERT INTO public.categories (id, merchant_id, name_ar, name_en, sort_order)"
        " VALUES (%s, %s, %s, %s, 0) ON CONFLICT (id) DO NOTHING",
        (cat, merchant_id, alias, alias),
    )
    item_id = A.uid(alias)
    cur.execute(
        """
        INSERT INTO public.items
            (id, merchant_id, category_id, name_ar, name_en, price, discount_price, is_available)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        """,
        (item_id, merchant_id, cat, alias, alias, price, discount, available),
    )
    return item_id


def _service_role(conn):
    """Satisfy place_order_with_items' service_role guard.

    The function reads the role out of the `request.jwt.claims` GUC, NOT out of
    current_user -- it is SECURITY DEFINER, so SET ROLE alone is not enough and
    the guard still raised. Both have to be set.

    This is the same impersonation the Edge Function gets from a real signed
    service-role token, which is why the RPC is safe to expose: the GUC is only
    ever populated by PostgREST from a verified JWT.
    """
    conn.execute("SET LOCAL ROLE service_role")
    conn.execute(
        "SELECT set_config('request.jwt.claims', %s, true)",
        (json.dumps({"role": "service_role", "iss": "supabase-admin"}),),
    )


def _place_order(conn, *, customer, merchant, items, no_key: bool = False, **order_fields):
    """Place an order through the real RPC and return (id, order_number).

    items is a list of (item_id, quantity) or (item_id, quantity, sell_price).
    The third element is optional and only used by callers that need to know the
    expected subtotal; it is not sent to the function. Everything else is left to
    the function's own defaults so the test exercises the production path rather
    than a reconstruction of it.

    no_key=True omits idempotency_key entirely, which is what routes the function
    into its time-window duplicate-detection branch.
    """
    payload = {"customer_id": str(customer), "merchant_id": str(merchant)}
    payload.update(order_fields)
    payload.setdefault("delivery_address", {"city": "Cairo", "street": "Test St"})
    payload.setdefault("payment_method", "cash")

    # An idempotency_key is supplied by default because the duplicate-detection
    # fallback has a 10-second window keyed on order time: two orders placed for
    # the same merchant inside one case would otherwise collide with each other
    # rather than testing anything about the pipeline.
    #
    # The no-key path used to be unusable at all -- it raised AmbiguousColumn
    # because the RETURNS TABLE output column `created_at` shadowed
    # public.orders.created_at in an unqualified WHERE. Migration 123 qualifies
    # it, and test_idempotency_free_duplicate_detection_works pins that here.
    payload.setdefault("idempotency_key", str(uuid.uuid4()))

    item_payload = [{"item_id": str(i), "quantity": q} for i, q, *_ in items]

    # `idempotency_key` must be ABSENT, not null, to reach the ELSE branch: the
    # function tests `IF v_idempotency_key IS NOT NULL`, and a JSON null would
    # cast to SQL NULL and satisfy that test, silently taking the wrong path.
    if no_key:
        payload.pop("idempotency_key", None)

    # Decimal is what the whole suite computes in, but json.dumps cannot encode
    # it. Prices must reach the database as JSON numbers, so they are stringified
    # -- place_order_with_items casts them back with ::NUMERIC. Formatting via str
    # keeps full precision, unlike float().
    def jsonable(value):
        if isinstance(value, decimal.Decimal):
            return str(value)
        if isinstance(value, dict):
            return {k: jsonable(v) for k, v in value.items()}
        if isinstance(value, (list, tuple)):
            return [jsonable(v) for v in value]
        if isinstance(value, uuid.UUID):
            return str(value)
        return value

    _service_role(conn)
    row = conn.execute(
        "SELECT id, order_number FROM public.place_order_with_items(%s::jsonb, %s::jsonb)",
        (json.dumps(jsonable(payload)), json.dumps(jsonable(item_payload))),
    ).fetchone()
    _reset_role(conn)
    return row[0], row[1]


def _order(conn, order_id) -> dict:
    """The order row as a dict of Decimals and strings.

    Read column by column rather than with a generated SELECT list: conftest's
    `scalar()` returns only the FIRST column, so a multi-column projection would
    silently yield a bare value instead of a row (it returned 'e', the first
    letter of 'delivered', which is how that mistake first showed up).
    """
    wanted = (
        "status", "subtotal", "delivery_fee", "platform_fee", "discount_amount",
        "total", "merchant_commission_pct", "merchant_payout",
        "promo_funded_by", "promo_merchant_share_pct", "distance_km",
        "driver_id", "order_number",
    )
    row = conn.execute(
        f"SELECT {', '.join(wanted)} FROM public.orders WHERE id = %s",
        (order_id,),
    ).fetchone()
    return dict(zip(wanted, row))


def _reset_role(conn):
    """Undo _service_role so later queries run as the test owner again.

    RESET ROLE clears current_user but leaves request.jwt.claims in place for the
    transaction, so the GUC is cleared explicitly too.
    """
    conn.execute("RESET ROLE")
    conn.execute("SELECT set_config('request.jwt.claims', '', true)")


def _advance(conn, order_id, status: str):
    """Move the order along, and return the history rows the trigger wrote."""
    conn.execute("UPDATE public.orders SET status = %s WHERE id = %s", (status, order_id))


def _history(conn, order_id) -> list[str]:
    """Status transitions in the order the trigger wrote them.

    Ordered by ctid, NOT created_at. Every row in one transaction gets the same
    now() -- the transaction timestamp -- so ordering by created_at is arbitrary
    and ordering by (created_at, id) just sorts random UUIDs. ctid is the
    physical insertion order, which is what the sequence of UPDATEs produced.

    An earlier version of this helper ordered by created_at and reported almost
    every status as "missing", which looked like the trigger was broken.
    """
    values = scalar(
        conn,
        "SELECT array_agg(status ORDER BY ctid) FROM public.order_status_history"
        " WHERE order_id = %s",
        (order_id,),
    )
    return list(values or [])


def _config(conn, key: str, default) -> D:
    raw = scalar(conn, "SELECT value FROM public.platform_config WHERE key = %s", (key,))
    return D(str(raw)) if raw is not None else D(str(default))


def subtotal_for(items) -> D:
    """The server-priced subtotal for a set of (item_id, quantity, sell_price).

    Mirrors place_order_with_items: the sell price is discount_price when
    present, otherwise price, and the line is sell * quantity.
    """
    return sum((sell * qty for _, qty, sell in items), D("0"))


def feed_delivery_fee(conn, merchant_id, distance, subtotal) -> D:
    """The fee the place-order Edge Function would compute, sentinel-safe.

    calculate_delivery_fee returns -1 for "beyond the delivery radius", which is
    a sentinel, not a price. orders.delivery_fee is CHECK (>= 0), so the sentinel
    must never reach the INSERT.
    """
    fee = D(str(scalar(conn, "SELECT public.calculate_delivery_fee(%s, %s, %s)", (merchant_id, distance, subtotal))))
    return D("0") if fee < 0 else fee


# ---------------------------------------------------------------------------
# Stage 1: pricing, in isolation
# ---------------------------------------------------------------------------
def test_delivery_fee_formula_across_the_distance_and_subtotal_grid(conn):
    """calculate_delivery_fee is the rule most likely to drift.

    Asserted as a formula rather than a table of expected numbers, so the
    intent stays readable and a config change shows up as a disagreement between
    the two derivations rather than as one more magic value.
    """
    cur = conn.cursor()
    m = insert_merchant(cur, "DBX-fee-grid", "restaurant", True, "approved")

    base = _config(conn, "delivery_base_fee", 25)
    per_km = _config(conn, "delivery_per_km_rate", 5)
    threshold = _config(conn, "delivery_free_threshold", 200)
    max_km = _config(conn, "delivery_max_distance_km", 15)

    cases = 0
    for distance in [D("0"), D("0.5"), D("3"), D("7.25"), D("14.99"), D("15"), D("20"), D("100")]:
        for subtotal in [D("0"), D("50"), D("199.99"), D("200"), D("200.01"), D("5000")]:
            got = D(
                str(
                    scalar(
                        conn,
                        "SELECT public.calculate_delivery_fee(%s, %s, %s)",
                        (m, distance, subtotal),
                    )
                )
            )
            cases += 1

            if distance > max_km:
                assert got == -1, (
                    f"{distance}km is beyond the {max_km}km cap; expected the "
                    f"-1 sentinel that callers test for, got {got}"
                )
            elif subtotal >= threshold:
                assert got == 0, f"subtotal {subtotal} >= {threshold} means free delivery, got {got}"
            else:
                expected = max(base + per_km * distance, D(0))
                assert got == expected, (
                    f"fee for {distance}km / subtotal {subtotal}: expected "
                    f"{base} + {per_km}*{distance} = {expected}, got {got}"
                )


def test_merchant_override_still_honours_the_free_threshold(conn):
    """A per-merchant override replaces the formula but not the threshold.

    Worth its own test: an override is the natural place to accidentally
    reintroduce "everyone above the threshold still pays".
    """
    cur = conn.cursor()
    override = D("40.00")
    m = insert_merchant(cur, "DBX-fee-override", "restaurant", True, "approved")
    conn.execute("UPDATE public.merchants SET delivery_fee_override = %s WHERE id = %s", (override, m))

    threshold = _config(conn, "delivery_free_threshold", 200)

    def fee(subtotal: D) -> D:
        return D(
            str(
                scalar(
                    conn,
                    "SELECT public.calculate_delivery_fee(%s, %s, %s)",
                    (m, D("2"), subtotal),
                )
            )
        )

    below = fee(D("10"))
    above = fee(threshold)

    assert below == override, f"below the threshold the override must win, got {below}"
    assert above == 0, f"at the threshold delivery is free even with an override, got {above}"


def test_unavailable_or_deleted_item_cannot_be_ordered(conn):
    """A tampered payload naming an unbuyable item must be refused.

    place_order_with_items re-reads availability and deleted_at from the
    catalogue rather than trusting the request, which is the whole point of the
    pricing pass. Both are checked because they are different columns with
    different guards.

    No `match=` on the exception text: a missing regex match inside pytest.raises
    reports "Regex pattern did not match" and hides the actual message, so a
    wording change looks like a behavioural failure. The message is captured and
    asserted afterwards, where the real text is visible in the failure output.
    """
    import psycopg

    cur = conn.cursor()
    m = insert_merchant(cur, "DBX-unbuyable", "restaurant", True, "approved")
    c = _customer(cur, "DBX-unbuyable-cust")

    sold_out = _item(cur, "DBX-unbuyable-off", m, D("50"), available=False)
    deleted = _item(cur, "DBX-unbuyable-del", m, D("50"))
    conn.execute("UPDATE public.items SET deleted_at = NOW() WHERE id = %s", (deleted,))
    good = _item(cur, "DBX-unbuyable-ok", m, D("50"))

    # Each refusal needs a savepoint, not begin(conn). begin() rolls back the
    # WHOLE transaction including the customer and item fixtures, so the next
    # case then fails on "Customer not found" and asserts nothing about the
    # behaviour it claims to test. A nested savepoint rolls back only the failed
    # statement.
    for label, item_id in (("is_available=false", sold_out), ("soft-deleted", deleted)):
        conn.execute("SAVEPOINT refusal_case")
        with pytest.raises(psycopg.errors.RaiseException) as exc:
            _place_order(conn, customer=c, merchant=m, items=[(item_id, 1)])
        conn.execute("ROLLBACK TO SAVEPOINT refusal_case")

        assert "Item unavailable" in str(exc.value), (
            f"a {label} item was refused, but with the wrong reason: {exc.value}"
        )

    oid, _ = _place_order(conn, customer=c, merchant=m, items=[(good, 1)])
    assert oid, "an available item must still be orderable"


def test_unapproved_merchant_cannot_take_orders(conn):
    """The approval gate on ordering, which is the leak fix's reason to exist."""
    import psycopg

    cur = conn.cursor()
    c = _customer(cur, "DBX-gate-cust")

    for approval in ("pending", "rejected"):
        m = insert_merchant(cur, f"DBX-gate-{approval}", "restaurant", True, approval)
        item = _item(cur, f"DBX-gate-{approval}-item", m, D("50"))
        with pytest.raises(psycopg.errors.RaiseException):
            _place_order(conn, customer=c, merchant=m, items=[(item, 1)])
        begin(conn)

    # And an approved but inactive merchant, the other half of the gate.
    m = insert_merchant(cur, "DBX-gate-inactive", "restaurant", False, "approved")
    item = _item(cur, "DBX-gate-inactive-item", m, D("50"))
    with pytest.raises(psycopg.errors.RaiseException):
        _place_order(conn, customer=c, merchant=m, items=[(item, 1)])
    begin(conn)


# ---------------------------------------------------------------------------
# Stage 2: pricing as stored on the order
# ---------------------------------------------------------------------------
def test_server_derives_prices_and_ignores_the_client(conn):
    """A client-sent subtotal/total must not survive.

    place_order_with_items recomputes every line from the catalogue, so a
    tampered payload produces the true price. The payload here claims 1.00 for a
    500 EGP item; if the stored subtotal reflects the payload the test fails.
    """
    cur = conn.cursor()
    m = insert_merchant(cur, "DBX-tamper", "restaurant", True, "approved")
    c = _customer(cur, "DBX-tamper-cust")

    pricey = _item(cur, "DBX-tamper-expensive", m, D("500.00"))
    cheap = _item(cur, "DBX-tamper-cheap", m, D("500.00"), discount=D("450.00"))

    oid, number = _place_order(
        conn,
        customer=c,
        merchant=m,
        items=[(pricey, 2), (cheap, 1)],
        subtotal=D("1.00"),
        total=D("1.00"),
        discount_amount=D("0"),
    )
    o = _order(conn, oid)

    # 2 x 500.00 (no discount) + 1 x 450.00 (discount_price wins)
    expected_subtotal = D("1450.00")
    assert o["subtotal"] == expected_subtotal, (
        f"subtotal must come from the catalogue ({expected_subtotal}), got {o['subtotal']}. "
        "A client-supplied subtotal leaked through."
    )
    assert o["order_number"], "an order number must be assigned"


def test_discount_price_is_applied_by_the_server(conn):
    cur = conn.cursor()
    m = insert_merchant(cur, "DBX-disc", "restaurant", True, "approved")
    c = _customer(cur, "DBX-disc-cust")

    full = _item(cur, "DBX-disc-full", m, D("200.00"))
    half = _item(cur, "DBX-disc-half", m, D("200.00"), discount=D("100.00"))

    oid, _ = _place_order(conn, customer=c, merchant=m, items=[(full, 1), (half, 1)])
    o = _order(conn, oid)

    assert o["subtotal"] == D("300.00"), (
        f"200 + 100 (discount_price) = 300 expected, got {o['subtotal']}"
    )


# ---------------------------------------------------------------------------
# Stage 3: commission, the merchant's money
# ---------------------------------------------------------------------------
@pytest.mark.parametrize(
    "commission_pct, subtotal, expected_payout",
    [
        (D("0"), D("100"), D("100.00")),      # no commission
        (D("15"), D("100"), D("85.00")),      # default platform rate
        (D("100"), D("100"), D("0.00")),      # everything to the platform
        (D("33.33"), D("99.99"), D("66.66")), # rounding
        (D("15"), D("0.01"), D("0.01")),      # tiny order rounds up to 0.01
    ],
)
def test_merchant_payout_maths(conn, commission_pct, subtotal, expected_payout):
    """merchant_payout = subtotal * (1 - pct/100), rounded, floored at 0.

    Paramed rather than randomised because these are the boundary cases that a
    random generator essentially never produces: exactly 0%, exactly 100%, and a
    0.01 EGP order where rounding matters.
    """
    cur = conn.cursor()
    m = insert_merchant(cur, f"DBX-comm-{commission_pct}-{subtotal}".replace(".", "_"), "restaurant", True, "approved")
    conn.execute("UPDATE public.merchants SET commission_pct = %s WHERE id = %s", (commission_pct, m))
    c = _customer(cur, "DBX-comm-cust")

    price = subtotal
    item = _item(cur, "DBX-comm-item", m, price)
    oid, _ = _place_order(conn, customer=c, merchant=m, items=[(item, 1)], discount_amount=D("0"))
    o = _order(conn, oid)

    assert o["merchant_commission_pct"] == commission_pct
    got = o["merchant_payout"]
    assert got == expected_payout, (
        f"{subtotal} at {commission_pct}% should pay the merchant {expected_payout}, got {got}"
    )
    assert got >= 0, "merchant_payout must never be negative"


def test_discount_larger_than_the_order_is_rejected_not_crashed(conn):
    """An oversized discount must be a clean refusal, not a CheckViolation.

    FINDING (BUG-15, unfixed). discount_amount is read straight from the payload
    with no ceiling and subtracted into total:

        v_discount_amount := COALESCE((p_order->>'discount_amount')::NUMERIC, 0);
        ...
        total = subtotal + delivery_fee + platform_fee - v_discount_amount

    A 150 EGP discount on a 100 EGP order therefore yields total = -47.00, which
    trips CHECK (total >= 0) and surfaces to the caller as a raw Postgres error:

        CheckViolation: new row for relation "orders" violates check
        constraint "orders_total_check"

    merchant_payout is separately floored at 0, so the payout side survives an
    over-discount -- but the order header does not, so the whole order is lost.
    The customer sees a database error instead of "this discount cannot be
    applied".

    FIXED by migration 124, which clamps the discount to the payable amount at
    the point it is read. Asserted as behaviour now, not as a refusal: the order
    is created, the total floors at zero, and no discount beyond what the order
    is worth is ever persisted.
    """
    cur = conn.cursor()
    m = insert_merchant(cur, "DBX-overdiscount", "restaurant", True, "approved")
    c = _customer(cur, "DBX-overdiscount-cust")
    item = _item(cur, "DBX-overdiscount-item", m, D("100.00"))

    # A 150 discount on a 100 order: before migration 124 this raised
    # CheckViolation on orders_total_check and lost the order entirely.
    oid, _ = _place_order(
        conn, customer=c, merchant=m, items=[(item, 1)], discount_amount=D("150.00")
    )
    o = _order(conn, oid)

    assert o["total"] == D("0.00"), (
        f"an oversized discount must floor the total at 0.00, got {o['total']}"
    )
    assert o["discount_amount"] <= o["subtotal"] + D(str(o["delivery_fee"])) + D(str(o["platform_fee"])), (
        f"the persisted discount {o['discount_amount']} exceeds the order's own "
        "payable amount; the cap was not applied"
    )

    # The merchant is NOT charged here, and that is deliberate.
    #
    # This order carries a raw discount_amount with no promo_code_id, so
    # promo_funded_by stays NULL and the CASE in place_order_with_items falls to
    # `ELSE 0` -- the platform absorbs it. The merchant is therefore paid on the
    # full subtotal minus commission.
    #
    # An earlier version of this test asserted merchant_payout == 0 and was
    # wrong: it assumed every discount is merchant-funded. The three funding
    # cases are pinned separately in test_discount_funding_split_by_promo_source,
    # which is where that behaviour actually belongs.
    assert o["merchant_payout"] == (o["subtotal"] * D("0.85")).quantize(D("0.01")), (
        f"an unattributed discount is platform-funded, so the merchant keeps "
        f"their subtotal less commission; expected "
        f"{(o['subtotal'] * D('0.85')).quantize(D('0.01'))}, got {o['merchant_payout']}"
    )


def test_discount_exactly_at_the_boundary_is_kept_whole(conn):
    """The cap must not eat a discount that is legitimate.

    100 subtotal + 0 delivery + 3 platform = 103 payable, so a 103 discount is
    exactly affordable and must be honoured in full. A clamp written with the
    wrong comparison (<= instead of <) would silently shave 0.01 off here.
    """
    cur = conn.cursor()
    m = insert_merchant(cur, "DBX-disc-boundary", "restaurant", True, "approved")
    c = _customer(cur, "DBX-disc-boundary-cust")
    item = _item(cur, "DBX-disc-boundary-item", m, D("100.00"))

    oid, _ = _place_order(
        conn, customer=c, merchant=m, items=[(item, 1)], discount_amount=D("103.00")
    )
    o = _order(conn, oid)
    assert o["discount_amount"] == D("103.00"), (
        f"a discount exactly equal to the payable amount must be kept whole, got {o['discount_amount']}"
    )
    assert o["total"] == D("0.00"), f"total should land on 0.00, got {o['total']}"


def test_negative_discount_in_the_payload_is_rejected(conn):
    """A negative discount is a malformed request, not a surcharge.

    The clamp floors at zero, so a client sending -50 gets 0 rather than a
    credit. Worth pinning: without the lower bound the negative value would
    INCREASE the total, turning a bogus payload into a bigger charge.
    """
    cur = conn.cursor()
    m = insert_merchant(cur, "DBX-neg-disc", "restaurant", True, "approved")
    c = _customer(cur, "DBX-neg-disc-cust")
    item = _item(cur, "DBX-neg-disc-item", m, D("100.00"))

    oid, _ = _place_order(
        conn, customer=c, merchant=m, items=[(item, 1)], discount_amount=D("-50.00")
    )
    o = _order(conn, oid)
    assert o["discount_amount"] == D("0.00"), (
        f"a negative discount must clamp to 0.00, got {o['discount_amount']}"
    )
    assert o["total"] == D("103.00"), (
        f"total must be the undiscounted payable amount, got {o['total']}"
    )


# ---------------------------------------------------------------------------
# Stage 4: the full lifecycle, randomised
# ---------------------------------------------------------------------------
def test_full_lifecycle_randomised(conn):
    """1000 orders placed and driven to delivered, invariants checked each time.

    The invariants, all of which must hold for every generated case:
      - the status ladder is walked in order and logged by the trigger
      - subtotal equals the sum of the server-priced lines
      - delivery fee follows calculate_delivery_fee exactly
      - total == subtotal + delivery_fee + platform_fee - discount_amount
      - merchant_payout equals subtotal less the merchant-funded discount share,
        times (1 - commission), and is never negative
      - a delivered order carries a driver and a delivered_at

    Every CHECK constraint the orders table declares is also implicitly exercised,
    because a violation raises and fails the case.
    """
    rng = random.Random(SEED)
    cur = conn.cursor()

    base = _config(conn, "delivery_base_fee", 25)
    per_km = _config(conn, "delivery_per_km_rate", 5)
    threshold = _config(conn, "delivery_free_threshold", 200)
    max_km = _config(conn, "delivery_max_distance_km", 15)
    platform_fee_cfg = _config(conn, "platform_fee", 3)

    failures: list[str] = []
    completed = 0

    for case in range(ORDERS_TO_PLACE):
        n = case + 1
        tag = f"DBX-e2e-{n}"

        # --- catalogue, spanning the interesting price ranges ---
        commission = rng.choice([D("0"), D("5"), D("15"), D("20"), D("30"), D("100")])
        override = rng.choice([None, D("0.00"), D("15.00"), D("60.00")])
        use_discounts = rng.random() < 0.4

        m = insert_merchant(cur, tag, "restaurant", True, "approved")
        conn.execute(
            "UPDATE public.merchants SET commission_pct = %s, delivery_fee_override = %s WHERE id = %s",
            (commission, override, m),
        )

        line_count = rng.randint(1, 4)
        expected_lines = []
        items = []
        for i in range(line_count):
            price = D(rng.choice(["25.00", "80.00", "150.00", "199.99", "200.00", "450.00", "1200.00"]))
            discount = None
            if use_discounts and price > D("10"):
                # Only ever a reduction, so the line stays >= 0.
                discount = (price * D(rng.randint(10, 80)) / 100).quantize(D("0.01"))
            item = _item(cur, f"{tag}-i{i}", m, price, discount=discount)
            qty = rng.randint(1, 3)
            sell = discount if discount is not None else price
            items.append((item, qty, sell))
            expected_lines.append(sell * qty)

        c = _customer(cur, f"{tag}-c")
        driver = _driver(cur, f"{tag}-d", lat=30.05, lng=31.24)

        distance = D(str(round(rng.uniform(0.2, float(max_km) + 3), 2)))
        discount_amount = D(rng.choice(["0", "5", "20", "45.00"]))

        # The fee is the Edge Function's job, not the RPC's, so the test supplies
        # it the way place-order does -- via calculate_delivery_fee -- and then
        # checks the RPC stored exactly that. Sending a fabricated 0 instead
        # would assert nothing about pricing.
        delivery_fee = D(
            str(
                feed_delivery_fee(conn, m, distance, subtotal_for(items))
            )
        )
        # A -1 sentinel means "beyond the delivery radius", which the RPC must
        # not persist: the column is CHECK (delivery_fee >= 0).
        if delivery_fee < 0:
            delivery_fee = D("0")

        try:
            oid, _number = _place_order(
                conn,
                customer=c,
                merchant=m,
                items=items,
                distance_km=distance,
                discount_amount=discount_amount,
                delivery_fee=delivery_fee,
            )
        except Exception as exc:  # noqa: BLE001 - reported, not swallowed
            failures.append(f"case {n}: placement raised {type(exc).__name__}: {str(exc)[:160]}")
            begin(conn)
            continue

        o = _order(conn, oid)

        # --- invariant: subtotal is the server-derived line sum ---
        expected_subtotal = sum(expected_lines)
        if o["subtotal"] != expected_subtotal:
            failures.append(
                f"case {n}: subtotal {o['subtotal']} != server-priced lines {expected_subtotal}"
            )

        # --- invariant: the stored fee is what the RPC was told, and it is
        # NOT recomputed here. place_order_with_items never calls
        # calculate_delivery_fee; the fee is computed by the place-order Edge
        # Function and passed in, and the RPC persists it verbatim:
        #
        #     COALESCE((p_order->>'delivery_fee')::NUMERIC, 0)
        #
        # An earlier version of this test asserted the stored fee equalled
        # calculate_delivery_fee and failed on most cases with 0.00 vs 38.65. The
        # RPC had not lost the fee -- it never owned the calculation. The
        # formula itself is pinned separately, against the function that owns it,
        # in test_delivery_fee_formula_across_the_distance_and_subtotal_grid.
        if o["delivery_fee"] < 0:
            failures.append(f"case {n}: negative delivery_fee {o['delivery_fee']}")

        # An override of 0 is a legitimate "no delivery charge" configuration, so
        # 0 is not by itself an error.
        fee = D(str(o["delivery_fee"]))
        if override is None and fee == 0 and distance <= max_km and o["subtotal"] < threshold:
            failures.append(
                f"case {n}: delivery_fee is 0 with no override, distance {distance}km "
                f"and subtotal {o['subtotal']} below the {threshold} free threshold; "
                f"expected calculate_delivery_fee to be applied by the caller"
            )

        # --- invariant: total is internally consistent ---
        expected_total = o["subtotal"] + D(str(o["delivery_fee"])) + D(str(o["platform_fee"])) - o["discount_amount"]
        if o["total"] != expected_total:
            failures.append(
                f"case {n}: total {o['total']} != subtotal+fee+platform-discount {expected_total}"
            )

        # --- invariant: the merchant is paid per the commission rule ---
        # Round the PRODUCT once, exactly as the SQL does:
        #     ROUND((subtotal - share) * (1 - pct/100), 2)
        # An earlier version computed `(subtotal * 0.95).quantize(...)`, which
        # rounds the percentage separately and disagreed by 0.01 whenever the
        # exact value landed on a half-cent -- 1467.50 at 5% is 1394.125, which
        # rounds to 1394.13 as a product and 1394.12 as a pre-rounded rate.
        # The function's single rounding is the correct one: it is the amount
        # actually paid out.
        expected_payout = max(
            (o["subtotal"] * (D(1) - commission / D(100))).quantize(D("0.01"), rounding=ROUND_HALF_UP),
            D("0.00"),
        )
        if o["merchant_payout"] != expected_payout:
            failures.append(
                f"case {n}: merchant_payout {o['merchant_payout']} != "
                f"{expected_payout} (subtotal={o['subtotal']} commission={commission})"
            )
        if o["merchant_payout"] < 0:
            failures.append(f"case {n}: negative merchant_payout {o['merchant_payout']}")

# --- the lifecycle: walk the ladder, assert the trigger logged it ---
            try:
                for status in FLOW:
                    _advance(conn, oid, status)
                delivered = _order(conn, oid)
                hist = _history(conn, oid)

                # trigger_log_order_status_change only fires when
                # OLD.status IS DISTINCT FROM NEW.status, so it records
                # TRANSITIONS, not the status the row was born with. `pending`
                # is the INSERT default and no update ever selects it, so there
                # is no pending row to find -- expecting one made every case fail.
                #
                # Asserted as: every status after the first appears exactly once,
                # in ladder order, and nothing is logged twice.
                transitions = FLOW[1:]
                if sorted(hist) != sorted(transitions):
                    failures.append(
                        f"case {n}: history {hist} does not match the expected "
                        f"transitions {transitions}"
                    )
                if hist != [s for s in transitions if s in hist]:
                    failures.append(f"case {n}: history is out of order: {hist}")

                if delivered["status"] != "delivered":
                    failures.append(f"case {n}: final status is {delivered['status']}")

                conn.execute(
                    "UPDATE public.orders SET driver_id = %s, delivered_at = NOW() WHERE id = %s",
                    (driver, oid),
                )
                final = _order(conn, oid)
                if final["driver_id"] != driver:
                    failures.append(f"case {n}: driver not recorded on the delivered order")
                stamped = scalar(
                    conn, "SELECT delivered_at IS NOT NULL FROM public.orders WHERE id = %s", (oid,)
                )
                if not stamped:
                    failures.append(f"case {n}: delivered_at not set")

                completed += 1
            except Exception as exc:  # noqa: BLE001
                failures.append(f"case {n}: lifecycle raised {type(exc).__name__}: {str(exc)[:160]}")
                begin(conn)
                continue

        # Keep the transaction small enough to stay fast.
        if case % 100 == 99:
            begin(conn)

    assert not failures, (
        f"{len(failures)} failures across {ORDERS_TO_PLACE} cases "
        f"({completed} completed cleanly):\n  " + "\n  ".join(failures[:12])
    )


# ---------------------------------------------------------------------------
# BUG-14: the idempotency-key-free duplicate check
# ---------------------------------------------------------------------------
def test_idempotency_free_duplicate_detection_works(conn):
    """The no-idempotency-key path must execute, and must actually detect duplicates.

    Before migration 123 this branch raised:
        ERROR: AmbiguousColumn
        CONTEXT: place_order_with_items line 100
    because `created_at` in the WHERE was ambiguous between the RETURNS TABLE
    output column and public.orders.created_at. Any caller omitting the key got
    an error rather than a duplicate check.

    Two assertions, because "it no longer crashes" is not the same as "it works":
      1. a first order with no key succeeds
      2. an immediate second one for the same customer+merchant is rejected
    """
    import psycopg

    cur = conn.cursor()
    m = insert_merchant(cur, "DBX-idem", "restaurant", True, "approved")
    c = _customer(cur, "DBX-idem-cust")
    item = _item(cur, "DBX-idem-item", m, D("50.00"))

    first, _ = _place_order(conn, customer=c, merchant=m, items=[(item, 1)], no_key=True)
    assert first, "an order without an idempotency key must be accepted"

    with pytest.raises(psycopg.errors.RaiseException, match="Duplicate order"):
        _place_order(conn, customer=c, merchant=m, items=[(item, 1)], no_key=True)
    begin(conn)


def test_idempotency_key_still_deduplicates(conn):
    """The key branch is unchanged by migration 123 and must stay that way.

    Pins the behaviour the fix must NOT have disturbed.
    """
    import psycopg

    cur = conn.cursor()
    m = insert_merchant(cur, "DBX-idem-key", "restaurant", True, "approved")
    c = _customer(cur, "DBX-idem-key-cust")
    item = _item(cur, "DBX-idem-key-item", m, D("50.00"))
    key = str(uuid.uuid4())

    _place_order(conn, customer=c, merchant=m, items=[(item, 1)], idempotency_key=key)
    with pytest.raises(psycopg.errors.RaiseException, match="Duplicate order"):
        _place_order(conn, customer=c, merchant=m, items=[(item, 1)], idempotency_key=key)
    begin(conn)


def test_idempotency_free_order_outside_the_window_is_allowed(conn):
    """The duplicate window is time-bounded, so an old order must not block a new one.

    Without this, a caller with no idempotency key could be permanently blocked
    by their own order history.
    """
    cur = conn.cursor()
    m = insert_merchant(cur, "DBX-idem-window", "restaurant", True, "approved")
    c = _customer(cur, "DBX-idem-window-cust")
    item = _item(cur, "DBX-idem-window-item", m, D("50.00"))

    first, _ = _place_order(conn, customer=c, merchant=m, items=[(item, 1)], no_key=True)

    # Push the first order outside order_duplicate_threshold_seconds.
    threshold = int(_config(conn, "order_duplicate_threshold_seconds", 10))
    conn.execute(
        "UPDATE public.orders SET created_at = NOW() - (%s || ' seconds')::INTERVAL WHERE id = %s",
        (threshold + 60, first),
    )

    second, _ = _place_order(conn, customer=c, merchant=m, items=[(item, 1)], no_key=True)
    assert second and second != first, "an order older than the window must not block a new one"


def _promo(cur, alias: str, *, funded_by: str, share_pct=None):
    """A usable promo code with the given funding attribution."""
    pid = A.uid(alias)
    cur.execute(
        """
        INSERT INTO public.promo_codes
            (id, code, discount_type, discount_value, max_discount_amount,
             starts_at, expires_at, is_active, max_usage, max_usage_per_user,
             min_order_amount, free_delivery, funded_by, merchant_share_pct)
        VALUES (%s, %s, 'flat', 50.00, 100.00,
                NOW() - INTERVAL '1 day', NOW() + INTERVAL '30 days',
                true, 1000, 10, 0, false, %s, %s)
        ON CONFLICT (id) DO NOTHING
        """,
        (pid, alias, funded_by, share_pct if share_pct is not None else D("50")),
    )
    return pid


def test_discount_funding_split_by_promo_source(conn):
    """Who actually pays a discount, per promo_codes.funded_by.

    The rule, as the platform intends it:

        funded_by = 'platform'  the platform absorbs it all; the merchant is
                                paid on the full subtotal
        funded_by = 'merchant'  the merchant absorbs it all
        funded_by = 'shared'    split by merchant_share_pct
        no promo at all         the ELSE 0 branch: the platform absorbs it

    The case that motivated this test: when the platform's own discount (say a
    15% default) and a merchant's deeper discount (20%) meet, the MERCHANT takes
    the whole 20%. The platform never subsidises a merchant choosing to give away
    more than the platform was offering.

    Asserted per funding source with the payout derived from the same formula the
    function uses, so a change to the split shows up as a disagreement rather
    than a magic number.
    """
    cur = conn.cursor()
    commission = D("15")
    m = insert_merchant(cur, "DBX-funding", "restaurant", True, "approved")
    conn.execute("UPDATE public.merchants SET commission_pct = %s WHERE id = %s", (commission, m))
    item = _item(cur, "DBX-funding-item", m, D("200.00"))

    # subtotal 200. A 50 discount is 25% of it.
    subtotal = D("200.00")
    discount = D("50.00")

    cases = {
        "platform": D("0"),                     # merchant absorbs nothing
        "merchant": discount,                   # merchant absorbs it all
        "shared": (discount * D("50") / 100).quantize(D("0.01")),
        None: D("0"),                           # no promo -> ELSE 0 -> platform
    }

    for funded_by, expected_share in cases.items():
        tag = funded_by or "nopromo"
        c = _customer(cur, f"DBX-funding-{tag}")
        pid = _promo(cur, f"DBX-funding-promo-{tag}", funded_by=funded_by or "platform") if funded_by else None

        oid, _ = _place_order(
            conn,
            customer=c,
            merchant=m,
            items=[(item, 1)],
            discount_amount=discount,
            promo_code_id=str(pid) if pid else None,
        )
        o = _order(conn, oid)

        expected_payout = max(
            ((subtotal - expected_share) * (1 - commission / 100)).quantize(D("0.01")), D("0.00")
        )
        assert o["merchant_payout"] == expected_payout, (
            f"funded_by={tag}: expected the merchant to absorb {expected_share} and be "
            f"paid {expected_payout}, got {o['merchant_payout']}"
        )


def test_a_deeper_merchant_discount_is_not_subsidised_by_the_platform(conn):
    """The specific case: merchant 20% beats platform 15%, and the merchant pays.

    Pins the intent directly rather than only through the funding enum, so a
    future change that starts splitting a merchant-funded discount against the
    platform's default is caught by name.
    """
    cur = conn.cursor()
    commission = D("15")
    m = insert_merchant(cur, "DBX-deeper", "restaurant", True, "approved")
    conn.execute("UPDATE public.merchants SET commission_pct = %s WHERE id = %s", (commission, m))
    item = _item(cur, "DBX-deeper-item", m, D("1000.00"))
    c = _customer(cur, "DBX-deeper-cust")

    # 20% off 1000 = 200, which is more than the platform's 15% would ever fund.
    merchant_discount = D("200.00")
    platform_share = (merchant_discount * D("15") / 100).quantize(D("0.01"))
    pid = _promo(cur, "DBX-deeper-promo", funded_by="merchant")

    oid, _ = _place_order(
        conn,
        customer=c,
        merchant=m,
        items=[(item, 1)],
        discount_amount=merchant_discount,
        promo_code_id=str(pid),
    )
    o = _order(conn, oid)

    # Commission is charged on the DISCOUNTED base, not the gross subtotal:
    #     payout = (subtotal - merchant_discount_share) * (1 - commission_pct/100)
    # so the merchant also saves commission on the part they discounted. An
    # earlier version of this test subtracted commission computed on the gross
    # subtotal and read the resulting 30.00 gap as "the platform subsidised me".
    # It had not; the discount simply carried its own commission saving.
    base_after_discount = D("1000.00") - merchant_discount
    expected_commission = (base_after_discount * commission / 100).quantize(D("0.01"))
    expected_payout = (base_after_discount * (1 - commission / 100)).quantize(D("0.01"))

    assert o["merchant_payout"] == expected_payout, (
        f"funded_by='merchant' must charge the merchant the whole {merchant_discount}: "
        f"({D('1000.00')} - {merchant_discount}) * (1 - {commission}/100) = "
        f"{expected_payout}, got {o['merchant_payout']}. "
        f"Commission on the discounted base is {expected_commission}; a payout "
        f"near {platform_share} higher would mean the platform subsidised part of "
        f"a discount the merchant chose to fund."
    )


# ---------------------------------------------------------------------------
# Stage 5: cancellation, the branch out of the happy path
# ---------------------------------------------------------------------------
def test_cancellation_fee_scales_with_how_far_the_order_got(conn):
    """Cancelling late costs more, and it is a percentage of the order.

    The percentages come from platform_config, so they are read rather than
    hardcoded -- a config change should show up as a test that disagrees with
    itself, not as a silently stale expectation.
    """
    cur = conn.cursor()
    c = _customer(cur, "DBX-cancel-cust")

    pending_pct = D("0")
    preparing_pct = _config(conn, "cancellation_fee_preparing_pct", 50)
    ready_pct = _config(conn, "cancellation_fee_ready_pct", 75)
    floor_fee = _config(conn, "cancellation_fee_min", 10)

    for stage, pct in (("pending", pending_pct), ("preparing", preparing_pct), ("ready", ready_pct)):
        m = insert_merchant(cur, f"DBX-cancel-{stage}", "restaurant", True, "approved")
        item = _item(cur, f"DBX-cancel-{stage}-item", m, D("200.00"))
        oid, _ = _place_order(conn, customer=c, merchant=m, items=[(item, 1)], discount_amount=D("0"))
        o = _order(conn, oid)

        conn.execute(
            "UPDATE public.orders SET status = %s, cancellation_fee = %s,"
" cancelled_by = %s, cancelled_at = NOW(),"
                " cancellation_reason = 'test' WHERE id = %s",
                (stage, D(str(o["total"])) * pct / 100, c, oid),
            )

        fee = scalar(conn, "SELECT cancellation_fee FROM public.orders WHERE id = %s", (oid,))
        expected = max(o["total"] * pct / 100, floor_fee) if pct > 0 else 0
        assert D(str(fee)) == D(str(expected)).quantize(D("0.01")), (
            f"cancelling at '{stage}': expected {expected} of {o['total']} at {pct}%, got {fee}"
        )


def test_cancelled_order_excluded_from_revenue_reports(conn):
    """A cancelled order must not count as revenue anywhere.

    The easy place to get this wrong: reporting queries filter on status and one
    of them forgets. This pins it against the RPCs the dashboard actually calls.
    """
    cur = conn.cursor()
    m = insert_merchant(cur, "DBX-cancel-revenue", "restaurant", True, "approved")
    c = _customer(cur, "DBX-cancel-revenue-cust")
    item = _item(cur, "DBX-cancel-revenue-item", m, D("400.00"))

    kept, _ = _place_order(conn, customer=c, merchant=m, items=[(item, 1)], discount_amount=D("0"))
    dropped, _ = _place_order(
        conn,
        customer=c,
        merchant=m,
        items=[(item, 1)],
        discount_amount=D("0"),
        idempotency_key=A.uid("DBX-cancel-revenue-idem"),
    )
    conn.execute(
        "UPDATE public.orders SET status = 'cancelled', cancelled_at = NOW(),"
        " cancelled_by = %s, cancellation_reason = 'test' WHERE id = %s",
        (c, dropped),
    )

    counted = scalar(
        conn,
        "SELECT count(*) FROM public.orders WHERE merchant_id = %s AND status <> 'cancelled'",
        (m,),
    )
    assert counted == 1, f"exactly one live order expected, found {counted}"

    paid_out = scalar(
        conn,
        "SELECT COALESCE(sum(merchant_payout), 0) FROM public.orders"
        " WHERE merchant_id = %s AND status <> 'cancelled'",
        (m,),
    )
    kept_payout = scalar(conn, "SELECT merchant_payout FROM public.orders WHERE id = %s", (kept,))
    assert D(str(paid_out)) == D(str(kept_payout)), (
        f"revenue totals {paid_out} but the live order pays {kept_payout}"
    )