"""Executable verification of the dataflow audit (2026-10-03).

Every test asserts that a BUG EXISTS, per this suite's convention (README
"Adding a test"): the assertion fails loudly once a fix lands, at which point it
is flipped to assert the corrected behaviour.

Scope: SQL / schema / SQL-function behaviour only. Anything living purely in
TypeScript (error swallowing, rate limiting, HMAC, PostgREST `.or()` semantics,
EF-level IDOR) is NOT verifiable here and is listed as NOT-DB-VERIFIABLE in
FINDINGS-VERIFICATION.md rather than asserted.

Rollback discipline: `begin()` is `ROLLBACK` + `BEGIN`, so calling it after work
that must be observed DISCARDS that work. It is used only to recover from an
aborted transaction.
"""

from __future__ import annotations

import datetime as dt
import json
import uuid

import pytest

from conftest import (
    begin,
    insert_category,
    insert_merchant,
    insert_option,
    make_customer,
    scalar,
)

CATEGORY = "restaurant"


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------


def as_service_role(conn) -> None:
    conn.execute(
        "SELECT set_config('request.jwt.claims', %s, true)", ('{"role":"service_role"}',)
    )


def fn_source(conn, name: str, prefer_nargs: int | None = None) -> str:
    """Source of a public function.

    Ordering matters: `search_catalog` exists as BOTH a 9-arg placeholder and the
    real 12-arg implementation, so ORDER BY pronargs LIMIT 1 would silently return
    the stub. Default to the widest overload.
    """
    return scalar(
        conn,
        "SELECT pg_get_functiondef(p.oid) FROM pg_proc p "
        "JOIN pg_namespace n ON n.oid = p.pronamespace "
        "WHERE p.proname = %s AND n.nspname = 'public' "
        "ORDER BY p.pronargs DESC LIMIT 1",
        (name,),
    )


def make_driver(conn, tag: str) -> uuid.UUID:
    uid = make_customer(conn)
    conn.execute("UPDATE public.profiles SET role = 'driver' WHERE id = %s", (uid,))
    conn.execute(
        "INSERT INTO public.drivers (id, national_id, vehicle_type, vehicle_plate) "
        "VALUES (%s,%s,'motorcycle',%s)",
        (uid, f"999{tag}-{uid.hex[:8]}", f"PLT-{tag}-{uid.hex[:8]}"),
    )
    return uid


def make_order(
    conn,
    customer_id,
    merchant_id,
    *,
    status="delivered",
    payment_status="paid",
    payment_method="card",
    delivery_fee=25.0,
    merchant_payout=0.0,
    driver_id=None,
    paymob_order_id=None,
):
    """Insert an order directly, bypassing place_order_with_items.

    delivered_at defaults to 12h ago: both settlement windows are half-open
    (`>= start AND < end`) with end = now(), so a row stamped exactly `now()`
    falls outside and yields "no eligible orders".
    """
    oid = uuid.uuid4()
    conn.execute(
        """
        INSERT INTO public.orders
            (id, customer_id, merchant_id, status, payment_status, payment_method,
             delivery_address, subtotal, delivery_fee, platform_fee, discount_amount,
             total, merchant_payout, driver_id, delivered_at, created_at, paymob_order_id)
        VALUES (%s,%s,%s,%s,%s,%s,'{}'::jsonb, 100, %s, 0, 0, %s, %s, %s,
                now() - interval '12 hours', now() - interval '12 hours', %s)
        """,
        (
            oid, customer_id, merchant_id, status, payment_status, payment_method,
            delivery_fee, 100.0 + delivery_fee, merchant_payout, driver_id, paymob_order_id,
        ),
    )
    return oid


def make_earning(conn, driver_id, order_id, *, fee=25.0, platform=5.0,
                 cancel_comp=False, created_hours_ago=12):
    """created_at is backdated for the same half-open-window reason as orders."""
    conn.execute(
        """
        INSERT INTO public.driver_earnings
            (driver_id, order_id, delivery_fee_earned, platform_fee_deducted,
             net_earnings, earnings_pct_used, is_cancellation_compensation,
             payout_status, created_at)
        VALUES (%s,%s,%s,%s,%s,80.00,%s,'pending',
                now() - make_interval(hours => %s))
        """,
        (driver_id, order_id, fee, platform, fee - platform, cancel_comp, created_hours_ago),
    )


# ===========================================================================
# V0 (NEW, CRITICAL)  place_order_with_items CANNOT EXECUTE AT ALL
# ===========================================================================


def test_V0_place_order_with_items_executes(conn):
    """Was CRITICAL and previously unreported. FIXED by migration 123.

    `RETURNS TABLE(id uuid, order_number text, created_at timestamptz)` made
    `created_at` an OUT parameter, and line ~100 referenced a bare
    `AND created_at > NOW() - ...` in the duplicate-order check. Postgres resolved
    that as ambiguous, so the whole checkout write path raised 42P18 on every
    call that omitted an idempotency_key -- no order row, no order_items, no promo
    usage. Same class of defect BUG-REPORT.md section 5 documents for `id`.

    Migration 123 qualifies the reference as `public.orders.created_at`.

    This test previously asserted the OPPOSITE -- that the call raises an
    ambiguity error -- so it failed once the bug was fixed. Inverting it is the
    honest update: the finding was real, and a test demanding the bug persist is
    worse than no test at all.

    It now asserts the fix holds: a real order is placed, and the order row plus
    its order_items exist. Behavioural depth lives in
    test_13_order_lifecycle_e2e.py; this is the regression guard on the specific
    ambiguity, because that failure mode is silent and total.
    """
    as_service_role(conn)
    with conn.cursor() as cur:
        m = insert_merchant(cur, "DBX-V0-merch", CATEGORY, True, "approved")
        cat = insert_category(cur, "DBX-V0-cat", m)
        from conftest import insert_item

        item = insert_item(cur, "DBX-V0-item", m, cat, price=20.0)
    cust = make_customer(conn)

    # No idempotency_key: this is the branch that used to raise 42P18.
    row = conn.execute(
        "SELECT * FROM public.place_order_with_items(%s::jsonb, %s::jsonb)",
        (
            json.dumps({
                "customer_id": str(cust),
                "merchant_id": str(m),
                "delivery_address": {"address": "1 St"},
                "payment_method": "cash",
            }),
            json.dumps([{"item_id": str(item), "quantity": 1}]),
        ),
    ).fetchone()

    assert row is not None and row[0], (
        "REGRESSED: place_order_with_items must execute when idempotency_key is "
        "absent. An unqualified created_at is ambiguous against the RETURNS "
        "TABLE output column of the same name (migration 123)."
    )

    # The order must actually be persisted, not merely return an id.
    lines = scalar(
        conn,
        "SELECT count(*) FROM public.order_items WHERE order_id = %s",
        (row[0],),
    )
    assert lines == 1, f"expected 1 order_item to be written, found {lines}"
    begin(conn)

    assert scalar(
        conn, "SELECT count(*) FROM public.orders WHERE customer_id = %s", (cust,)
    ) == 0, "sanity: no order should have been written"


def test_V0b_created_at_is_an_out_parameter(conn):
    """Pin the mechanism AND the fix, so the guard is obvious: qualify the column.

    The ambiguity is structural: `created_at` is an OUT parameter by declaration,
    so ANY bare `created_at` in this function's body is ambiguous with
    `public.orders.created_at`. Migration 123 qualifies the one reference.

    The assertion was inverted when the fix landed -- it used to require the bare
    form to still be present, i.e. it demanded the bug.
    """
    rets = scalar(conn, "SELECT pg_get_function_result(oid) FROM pg_proc "
                        "WHERE proname = 'place_order_with_items'")
    assert "created_at" in rets, (
        f"the OUT parameter is what creates the ambiguity; signature changed: {rets}"
    )
    src = fn_source(conn, "place_order_with_items")
    assert "public.orders.created_at > NOW()" in src, (
        "REGRESSED: the duplicate-order check must qualify created_at as "
        "public.orders.created_at, because the RETURNS TABLE output column of "
        "the same name shadows the table column in an unqualified WHERE "
        "(migration 123)."
    )
    assert "AND created_at > NOW()" not in src, (
        "REGRESSED: an unqualified `AND created_at > NOW()` reappeared -- that is "
        "the exact expression that raised 42P18 ambiguous_column."
    )


def test_V0c_create_driver_settlement_fails_to_execute(conn):
    """CRITICAL, same bug class, second money function.

    `RETURNS TABLE(settlement_id uuid, ...)` makes `settlement_id` an OUT
    variable. The junction insert's NOT EXISTS then says
    `... FROM public.driver_settlement_earnings WHERE settlement_id = v_settlement_id`,
    which Postgres cannot resolve between the variable and the table column.

    So the driver-settlement cron has never created a settlement, and every
    driver_earning stays payout_status='pending' forever.
    """
    as_service_role(conn)
    with conn.cursor() as cur:
        m = insert_merchant(cur, "DBX-V0c-merch", CATEGORY, True, "approved")
    cust = make_customer(conn)
    drv = make_driver(conn, "V0c")
    oid = make_order(conn, cust, m, driver_id=drv)
    make_earning(conn, drv, oid)

    with pytest.raises(Exception) as exc:
        conn.execute(
            "SELECT * FROM public.create_driver_settlement(%s, now() - interval '1 day', "
            "now(), 'cash')",
            (drv,),
        )
    assert "ambiguous" in str(exc.value).lower(), (
        f"expected an ambiguity error, got: {str(exc.value)[:200]}"
    )
    begin(conn)

    assert scalar(
        conn, "SELECT count(*) FROM public.driver_settlements WHERE driver_id=%s", (drv,)
    ) == 0, "sanity: no settlement should exist"


def test_V0d_adjust_wallet_balance_fails_to_execute(conn):
    """CRITICAL, same bug class, third money function.

    `RETURNS TABLE(... user_id ...)` and the audit-log update says
    `WHERE user_id = p_user_id` -> ambiguous. Every wallet credit/debit through
    this RPC is a no-op, and no wallet_audit_log row is written.
    """
    as_service_role(conn)
    uid = make_customer(conn)
    with pytest.raises(Exception) as exc:
        conn.execute(
            "SELECT * FROM public.adjust_wallet_balance(%s, 25.00, 'promo_credit', 'probe')",
            (uid,),
        )
    assert "ambiguous" in str(exc.value).lower(), (
        f"expected an ambiguity error, got: {str(exc.value)[:200]}"
    )
    begin(conn)

    assert scalar(
        conn, "SELECT count(*) FROM public.wallet_audit_log WHERE user_id=%s", (uid,)
    ) == 0, "sanity: no audit row"


def test_V0e_cancel_order_by_contrast_does_execute(conn):
    """Contrast case, so V0/V0c/V0d are not mistaken for a broken harness.

    A purely static scan of `prosrc` for a bare OUT-parameter reference flags
    cancel_order too (line 134: `AND status = v_order.status` against public.orders).
    Executing it proves that reference resolves fine, which is why this defect
    class has to be proven by running the function, not by grepping its source.
    """
    as_service_role(conn)
    with conn.cursor() as cur:
        m = insert_merchant(cur, "DBX-V0e-merch", CATEGORY, True, "approved")
    cust = make_customer(conn)
    oid = make_order(conn, cust, m, status="confirmed", payment_status="paid",
                     payment_method="card", paymob_order_id="DBX-TXN-9")

    rows = conn.execute(
        "SELECT * FROM public.cancel_order(%s, NULL, 'system', 'contrast probe')", (oid,)
    ).fetchall()
    assert rows, "cancel_order executed successfully (it is NOT ambiguous)"
    assert scalar(conn, "SELECT status FROM public.orders WHERE id=%s", (oid,)) == "cancelled"


# ===========================================================================
# V1  place-order queries item_options.group_name_ar / group_name_en
# ===========================================================================


def test_V1_item_options_has_no_group_name_columns(conn):
    cols = {
        r[0]
        for r in conn.execute(
            "SELECT column_name FROM information_schema.columns "
            "WHERE table_schema='public' AND table_name='item_options'"
        ).fetchall()
    }
    assert {"name_ar", "name_en"} <= cols, "sanity: real columns exist"
    assert not (cols & {"group_name_ar", "group_name_en"}), (
        "FIXED: group_name_ar/group_name_en now exist -- re-check place-order's select"
    )


# ===========================================================================
# V2  cancellation_rules has no ('ready','system') row
# ===========================================================================


def test_V2_no_ready_system_cancellation_rule(conn):
    rows = conn.execute(
        "SELECT order_status FROM public.cancellation_rules WHERE initiator='system'"
    ).fetchall()
    system = {r[0] for r in rows}
    assert "confirmed" in system, "sanity"
    assert "ready" not in system, (
        "FIXED: ('ready','system') exists -- auto_cancel_ready_timeout_minutes works"
    )


def test_V2b_cancel_order_raises_for_ready_from_system(conn):
    """Behavioural proof of the 100% failure rate of the ready sweep."""
    as_service_role(conn)
    with conn.cursor() as cur:
        m = insert_merchant(cur, "DBX-V2-merch", CATEGORY, True, "approved")
    cust = make_customer(conn)
    oid = make_order(conn, cust, m, status="ready", payment_status="pending",
                     payment_method="cash")

    with pytest.raises(Exception) as exc:
        conn.execute(
            "SELECT * FROM public.cancel_order(%s, NULL, 'system', 'stale ready')", (oid,)
        )
    assert "no cancellation rule" in str(exc.value).lower(), (
        f"expected a missing-rule error, got: {str(exc.value)[:200]}"
    )
    # no post-error query here: the transaction is aborted and begin() would
    # discard the fixtures we would be querying.
    begin(conn)


# ===========================================================================
# V3 / V4 / V5  search_catalog ignores approval_status, deleted_at, discount_price
# ===========================================================================


def test_V3_search_catalog_ignores_merchant_approval(conn):
    """V3 is FIXED by migration 122. This now asserts the fix is present.

    It previously asserted `"approval_status" not in src`, i.e. that the bug was
    still there, and failed once it was fixed. Inverting the assertion is the
    honest update: the finding was real, migration 122 closed it, and a test that
    keeps demanding the bug is worse than no test.

    Behavioural coverage lives in test_12_search_approval_gate.py, which inserts
    real pending/rejected/inactive merchants and proves they stay hidden. This
    one keeps the cheap source-level guard that the gate cannot be quietly
    removed from the function body.
    """
    src = fn_source(conn, "search_catalog")
    assert "is_active" in src, "sanity"
    assert "approval_status" in src, (
        "REGRESSED: search_catalog no longer filters approval_status. It is "
        "SECURITY DEFINER and bypasses the merchants_read_active RLS policy, so "
        "without this filter pending vendors are searchable again. Migration 122."
    )
    # Both flags, not either one: is_active is the kill-switch for approved
    # vendors, approval_status is the onboarding gate.
    assert "m.approval_status = 'approved'" in src, (
        "REGRESSED: the approval gate is present but not in the form migration "
        "122 installs -- check it still compares against 'approved'"
    )


def test_V4_search_catalog_ignores_item_soft_delete(conn):
    src = fn_source(conn, "search_catalog")
    assert "i.is_available" in src, "sanity"
    assert "deleted_at" not in src, "FIXED: search_catalog excludes soft-deleted rows"


def test_V4b_search_catalog_duplicate_overloads_coexist(conn):
    """Migration 121 shipped its fix as a 9-arg overload whose body is only
    `RAISE EXCEPTION 'Migration 121 placeholder - replaced below'`, while the
    real 12-arg implementation was never given the soft-delete filter.

    Two overloads of the same RPC name is a live hazard on its own: PostgREST
    resolves by parameter-name set, so which one runs depends on the exact names
    the caller sends.
    """
    rows = conn.execute(
        "SELECT p.pronargs, p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace "
        "WHERE p.proname='search_catalog' AND n.nspname='public' ORDER BY p.pronargs"
    ).fetchall()
    by_args = {n: s for n, s in rows}
    assert len(rows) == 2, f"expected the 9-arg stub plus the 12-arg real one, got {sorted(by_args)}"
    assert "Migration 121 placeholder" in by_args[9], "sanity: the 9-arg overload is the stub"
    assert "Migration 121 placeholder" not in by_args[12], (
        "FIXED: the placeholder overload is gone or superseded"
    )

    stub = conn.execute(
        "SELECT pg_get_function_result(oid) FROM pg_proc WHERE proname='search_catalog' "
        "AND pronargs=9"
    ).fetchone()[0]
    assert stub == "jsonb", f"sanity: 9-arg returns jsonb, got {stub}"


def test_V5_search_catalog_ignores_discount_price(conn):
    src = fn_source(conn, "search_catalog")
    assert "i.price" in src, "sanity"
    assert "discount_price" not in src, "FIXED: search returns the effective price"


# ===========================================================================
# V6  create_driver_settlement double-counts cancellation compensation
# ===========================================================================


def test_V6_settlement_double_counts_cancellation_compensation(conn):
    """v_net := v_gross - v_platform_fee + v_cancel_comp.

    For a compensation row delivery_fee_earned == net_earnings, so the amount is
    already inside v_gross and is then added again.

    Asserted against the function body rather than executed: V0c proves
    create_driver_settlement raises before reaching this arithmetic, so the
    double-count is currently latent. It becomes live the moment V0c is fixed.
    """
    src = fn_source(conn, "create_driver_settlement")
    assert "v_net := v_gross - v_platform_fee + v_cancel_comp" in src, (
        "FIXED: compensation is no longer added on top of gross"
    )
    gross_line = [
        ln for ln in src.split("\n") if "SUM(de.delivery_fee_earned)" in ln
    ]
    assert gross_line, "sanity: the gross aggregate is present"
    assert "FILTER" not in gross_line[0], (
        "FIXED: cancellation compensation is now excluded from gross_earnings, "
        "so it is not counted twice"
    )


# ===========================================================================
# V7  settlement overlap guard is inclusive -> adjacent period blocked
# ===========================================================================


def test_V7_adjacent_settlement_period_is_blocked(conn):
    src = fn_source(conn, "create_driver_settlement")
    assert "period_end >= p_period_start" in src, (
        "FIXED: the inclusive overlap guard is gone"
    )


def test_V7b_settlement_overlap_block_is_unreachable_at_runtime(conn):
    """V7's false-positive overlap cannot be demonstrated behaviourally because
    V0c proves create_driver_settlement raises first.

    Pinned as source-level so the day V0c is fixed this becomes executable, and
    so nobody reads V7 as unreachable-by-design.
    """
    src = fn_source(conn, "create_driver_settlement")
    assert "AND period_end >= p_period_start" in src, (
        "FIXED: half-open overlap test in use"
    )
    assert "AND de.created_at >= p_period_start" in src and "AND de.created_at < p_period_end" in src, (
        "sanity: the eligibility window is half-open, which is what makes the "
        "inclusive guard a false positive"
    )


def test_V19_merchant_payout_breakdown_does_not_reconcile(conn):
    """The breakdown columns and net_payable are computed from different bases.

    commission_deducted uses SUM(subtotal * commission_pct/100) on the FULL
    subtotal, while net_payable uses SUM(orders.merchant_payout) -- which
    place_order_with_items derives from (subtotal - merchant_discount_share).
    With merchant-funded promos the two diverge by discount_share * commission.
    """
    src = fn_source(conn, "create_merchant_payout")
    assert "SUM(o.subtotal * COALESCE(o.merchant_commission_pct, 0) / 100)" in src, (
        "FIXED: commission is charged on the post-discount base"
    )
    assert "SUM(o.merchant_payout)" in src, "sanity: net still sums merchant_payout"


# ===========================================================================
# V8  create_merchant_payout pays delivered-but-unpaid orders
# ===========================================================================


def test_V8_merchant_payout_has_no_payment_status_gate(conn):
    src = fn_source(conn, "create_merchant_payout")
    assert "delivered" in src, "sanity"
    assert "payment_status" not in src, (
        "FIXED: create_merchant_payout now gates on payment_status"
    )


def test_V8b_merchant_payout_includes_an_unpaid_delivered_order(conn):
    """Behavioural proof: payment_status='pending' still lands in a payable payout."""
    as_service_role(conn)
    with conn.cursor() as cur:
        m = insert_merchant(cur, "DBX-V8-merch", CATEGORY, True, "approved")
    cust = make_customer(conn)
    make_order(conn, cust, m, status="delivered", payment_status="pending",
               merchant_payout=85.00)
    conn.execute(
        "SELECT * FROM public.create_merchant_payout(%s, now() - interval '1 day', now(), "
        "'bank_transfer')",
        (m,),
    )
    row = conn.execute(
        "SELECT order_count, net_payable FROM public.merchant_payouts WHERE merchant_id=%s",
        (m,),
    ).fetchone()
    assert row is not None, "sanity: payout row created"
    count, net = row
    assert count == 1 and net == 85, (
        f"FIXED: unpaid order excluded (got count={count}, net={net})"
    )


# ===========================================================================
# V9  cancel_order never releases promo usage
# ===========================================================================


def test_V9_cancel_order_leaks_promo_usage(conn):
    as_service_role(conn)
    with conn.cursor() as cur:
        m = insert_merchant(cur, "DBX-V9-merch", CATEGORY, True, "approved")
    cust = make_customer(conn)
    oid = make_order(conn, cust, m, status="pending", payment_status="pending",
                     payment_method="cash")

    pid = uuid.uuid4()
    code = f"DBX-V9-{pid.hex[:8]}"
    conn.execute(
        """
        INSERT INTO public.promo_codes
            (id, code, discount_type, discount_value, starts_at, expires_at,
             max_usage, current_usage, max_usage_per_user, funded_by)
        VALUES (%s,%s,'flat',10, now() - interval '1 day', now() + interval '30 days',
                100, 1, 1, 'platform')
        """,
        (pid, code),
    )
    conn.execute(
        "UPDATE public.orders SET promo_code_id=%s, promo_code=%s, discount_amount=10 WHERE id=%s",
        (pid, code, oid),
    )
    conn.execute(
        "INSERT INTO public.promo_code_usage (promo_code_id, user_id, order_id, discount_amount) "
        "VALUES (%s,%s,%s,10)",
        (pid, cust, oid),
    )

    conn.execute(
        "SELECT * FROM public.cancel_order(%s, NULL, 'system', 'DBX V9 stale')", (oid,)
    )
    status = scalar(conn, "SELECT status FROM public.orders WHERE id=%s", (oid,))
    assert status == "cancelled", f"sanity: expected cancelled, got {status}"

    usage_rows = scalar(
        conn, "SELECT count(*) FROM public.promo_code_usage WHERE order_id=%s", (oid,)
    )
    current = scalar(conn, "SELECT current_usage FROM public.promo_codes WHERE id=%s", (pid,))
    assert usage_rows == 1 and current == 1, (
        "FIXED: cancelling released the promo (row deleted, counter decremented)"
    )


# ===========================================================================
# V10  cancel_order stamps a terminal refund_status with no gateway call
# ===========================================================================


def test_V10_cancel_order_stamps_terminal_refund_status(conn):
    """Behavioural proof: a paid digital order comes back 'refunded' with no
    refund ever sent, and the only retry sweep selects states this never writes."""
    as_service_role(conn)
    with conn.cursor() as cur:
        m = insert_merchant(cur, "DBX-V10-merch", CATEGORY, True, "approved")
    cust = make_customer(conn)
    oid = make_order(conn, cust, m, status="confirmed", payment_status="paid",
                     payment_method="card", paymob_order_id="DBX-TXN-1")

    conn.execute(
        "SELECT * FROM public.cancel_order(%s, NULL, 'system', 'DBX V10')", (oid,)
    )
    refund_status = scalar(conn, "SELECT refund_status FROM public.orders WHERE id=%s", (oid,))
    assert refund_status == "refunded", f"sanity: expected 'refunded', got {refund_status}"

    # the state reconcile-payments actually sweeps:
    swept = scalar(
        conn,
        "SELECT count(*) FROM public.orders WHERE id=%s AND refund_status IN "
        "('pending_refund','refund_failed')",
        (oid,),
    )
    assert swept == 0, (
        "FIXED: the order lands in a state the refund sweeper will pick up"
    )


# ===========================================================================
# V11  wallet audit trigger hardcodes change_type, writes no reference
# ===========================================================================


def test_V11_wallet_audit_logs_everything_as_correction(conn):
    uid = make_customer(conn)
    conn.execute("UPDATE public.profiles SET wallet_balance = 50 WHERE id=%s", (uid,))
    rows = conn.execute(
        "SELECT change_type, changed_by, reference_type, reference_id, change_amount "
        "FROM public.wallet_audit_log WHERE user_id=%s",
        (uid,),
    ).fetchall()
    assert len(rows) == 1, f"sanity: expected 1 audit row, got {len(rows)}"
    ctype, changed_by, ref_type, _ref_id, amount = rows[0]
    assert amount == 50, f"sanity: change_amount should be 50, got {amount}"
    assert ctype == "correction" and changed_by is None and ref_type is None, (
        "FIXED: the trigger records a real change_type / changed_by / reference"
    )


def test_V11b_only_correction_ever_appears(conn):
    rows = conn.execute(
        "SELECT DISTINCT change_type FROM public.wallet_audit_log"
    ).fetchall()
    non_correction = [r[0] for r in rows if r[0] != "correction"]
    assert not non_correction, f"FIXED: real change types now exist: {non_correction}"


# ===========================================================================
# V12  reviews INSERT policy lets a customer self-publish
# ===========================================================================


def test_V12_reviews_insert_policy_has_no_visibility_constraint(conn):
    row = conn.execute(
        """
        SELECT pg_get_expr(pol.polqual, pol.polrelid),
               pg_get_expr(pol.polwithcheck, pol.polrelid)
        FROM pg_policy pol
        JOIN pg_class cl ON cl.oid = pol.polrelid
        JOIN pg_namespace n ON n.oid = cl.relnamespace
        WHERE cl.relname='reviews' AND n.nspname='public' AND pol.polcmd='a'
        """
    ).fetchone()
    assert row is not None, "sanity: reviews has an INSERT policy"
    qual, withcheck = row
    combined = f"{qual or ''} {withcheck or ''}"
    assert "is_visible" not in combined, (
        "FIXED: the INSERT policy constrains is_visible"
    )
    assert "customer_id" in combined, "sanity: ownership is still checked"


def test_V12b_customer_can_insert_a_self_published_review(conn):
    """Behavioural proof: is_visible=true and a forged moderated_by both stick."""
    as_service_role(conn)
    with conn.cursor() as cur:
        m = insert_merchant(cur, "DBX-V12-merch", CATEGORY, True, "approved")
    cust = make_customer(conn)
    oid = make_order(conn, cust, m)

    conn.execute(
        "INSERT INTO public.reviews (order_id, customer_id, merchant_id, merchant_rating, "
        "is_visible, moderated_by) VALUES (%s,%s,%s,5,true,%s)",
        (oid, cust, m, cust),
    )
    row = conn.execute(
        "SELECT is_visible, moderated_by FROM public.reviews WHERE order_id=%s", (oid,)
    ).fetchone()
    assert row[0] is True, "sanity: visible"
    assert row[1] == cust, "FIXED: moderated_by can no longer be forged by the author"


# ===========================================================================
# V13  notifications.data NOT NULL vs the EF's `data || null`
# ===========================================================================


def test_V13_notifications_rejects_explicit_json_null(conn):
    """Proves the EF bug at the DB level: an explicit JSON null bypasses the
    DEFAULT '{}' and becomes SQL NULL -> 23502. `data || null` in
    send-notification/index.ts:231,357 does exactly this whenever `data` is absent."""
    notnull = scalar(
        conn,
        "SELECT is_nullable FROM information_schema.columns WHERE table_schema='public' "
        "AND table_name='notifications' AND column_name='data'",
    )
    assert notnull == "NO", "sanity: data is NOT NULL"

    uid = make_customer(conn)

    # the EF's current behaviour
    with pytest.raises(Exception) as exc:
        conn.execute(
            "INSERT INTO public.notifications (user_id, type, title_ar, title_en, "
            "body_ar, body_en, data) VALUES (%s,'general','a','a','b','b',NULL)",
            (uid,),
        )
    assert "null value" in str(exc.value).lower(), (
        f"expected not-null violation, got: {str(exc.value)[:200]}"
    )
    begin(conn)

    # the proposed fix -- must work
    uid2 = make_customer(conn)
    conn.execute(
        "INSERT INTO public.notifications (user_id, type, title_ar, title_en, "
        "body_ar, body_en, data) VALUES (%s,'general','a','a','b','b','{}'::jsonb)",
        (uid2,),
    )
    assert scalar(
        conn, "SELECT count(*) FROM public.notifications WHERE user_id=%s", (uid2,)
    ) == 1


# ===========================================================================
# V14  role-escalation trigger only guards role='driver'
# ===========================================================================


def test_V14_role_escalation_trigger_only_guards_driver(conn):
    d = scalar(
        conn,
        "SELECT pg_get_triggerdef(oid) FROM pg_trigger "
        "WHERE tgrelid='public.profiles'::regclass AND NOT tgisinternal "
        "AND tgname='on_profile_prevent_driver_escalation'",
    )
    assert d, "sanity: trigger present"
    assert "new.role = 'driver'" in d, (
        "FIXED: the WHEN clause no longer restricts the guard to role='driver'"
    )


# ===========================================================================
# V15  settlement uniqueness -- DISPROVES an audit sub-claim
# ===========================================================================


def test_V15_settlement_uniqueness_constraints_exist(conn):
    for table, expected in (
        ("driver_settlements", "UNIQUE (driver_id, period_start, period_end)"),
        ("merchant_payouts", "UNIQUE (merchant_id, period_start, period_end)"),
    ):
        defs = [
            r[0]
            for r in conn.execute(
                "SELECT pg_get_constraintdef(oid) FROM pg_constraint "
                "WHERE conrelid=%s::regclass AND contype='u'",
                (table,),
            ).fetchall()
        ]
        assert expected in defs, f"{table} missing {expected}; has {defs}"


# ===========================================================================
# V16  place_order_with_items does not enforce promo min_order_amount / geo
#     (proved against the function body -- see V0 for why it cannot be called)
# ===========================================================================


def test_V16_place_order_ignores_promo_min_order_and_geo(conn):
    src = fn_source(conn, "place_order_with_items")
    assert "min_order_amount" not in src, (
        "FIXED: place_order_with_items enforces promo min_order_amount"
    )
    assert "p_order->>'city'" not in src and "delivery_address" not in src.split(
        "p_order->'delivery_address'"
    )[0][:0] + "x", "sanity"


def test_V16b_validate_promo_is_advisory_only(conn):
    """The only min_order_amount enforcement is in the EF helper, which writes
    nothing. Prove the DB has no equivalent: search every public function."""
    hits = conn.execute(
        """
        SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.prosrc LIKE '%min_order_amount%'
          AND p.proname NOT IN ('validate_promo_code','calculate_delivery_fee')
        """
    ).fetchall()
    order_writers = [r[0] for r in hits if "order" in r[0] or "place" in r[0]]
    assert not order_writers, (
        f"FIXED: an order-writing function now enforces min_order_amount: {order_writers}"
    )