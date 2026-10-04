"""Test 03 -- option groups and choices: cardinality, defaults, price modifiers.

BUG-04  min_selections can exceed max_selections; is_required can contradict
        min_selections. No CHECK covers either (migration 007:110-115).
BUG-05  item_option_choices.is_default has no uniqueness constraint, so every
        choice in a single-select group can be is_default = TRUE (007:150).
BUG-06  price_modifier has CHECK (price_modifier >= 0) (007:146), so a price
        REDUCTION on an option is impossible. Product decision: reductions are
        required.
BUG-07  is_default = TRUE combined with is_available = FALSE is accepted
        (007:150-153), i.e. a sold-out choice can be pre-selected.
"""

from __future__ import annotations

import pytest

from conftest import (
    begin,
    check_constraints,
    insert_category,
    insert_choice,
    insert_item,
    insert_merchant,
    insert_option,
    scalar,
)


def _menu(conn, alias="DBX-menu"):
    """Build merchant -> category -> item and return their ids."""
    cur = conn.cursor()
    m = insert_merchant(cur, f"{alias}-m", "restaurant", True, "approved")
    c = insert_category(cur, f"{alias}-c", m)
    i = insert_item(cur, f"{alias}-i", m, c, 45.00)
    return cur, m, c, i


# ---------------------------------------------------------------------------
# BUG-04: cardinality
# ---------------------------------------------------------------------------


def test_min_greater_than_max_is_now_rejected(conn):
    """BUG-04: min=5, max=2 satisfies every CHECK and is unsatisfiable."""
    cur, _m, _c, item = _menu(conn, "DBX-bug04")
    with pytest.raises(Exception) as exc:
        insert_option(cur, "DBX-opt-bad-range", item, True, 5, 2)
    begin(conn)
    assert "item_options_selection_bounds_check" in str(exc.value)

    # Two CHECKs now mention max_selections: the 007 floor (>= 1) and 111's
    # cross-column bound. Select 111's by name -- fetchone would otherwise
    # return whichever came first.
    definition = scalar(
        conn,
        """
        SELECT pg_get_constraintdef(oid) FROM pg_constraint
        WHERE conrelid='public.item_options'::regclass
          AND conname='item_options_selection_bounds_check'
        """,
    )
    assert definition, "migration 111 must add item_options_selection_bounds_check"
    assert "min_selections" in definition, (
        "migration 111 must relate min_selections to max_selections"
    )


def test_required_with_zero_min_is_now_rejected(conn):
    """BUG-04b: is_required = TRUE with min_selections = 0 is contradictory."""
    cur, _m, _c, item = _menu(conn, "DBX-bug04b")
    with pytest.raises(Exception) as exc:
        insert_option(cur, "DBX-opt-required-zero", item, True, 0, 1)
    begin(conn)
    assert "item_options_required_min_check" in str(exc.value)


def test_optional_with_positive_min_is_still_allowed(conn):
    """BUG-04c: is_required = FALSE with min_selections = 3 -- the UI must
    enforce 3 picks but the field says optional."""
    # Deliberately NOT constrained: is_required = FALSE with min_selections > 0
    # is odd but harmless, and 111 only guards the required case.
    cur, _m, _c, item = _menu(conn, "DBX-bug04c")
    opt = insert_option(cur, "DBX-opt-optional-three", item, False, 3, 5)
    row = conn.execute(
        "SELECT is_required, min_selections FROM public.item_options WHERE id=%s", (opt,)
    ).fetchone()
    assert row == (False, 3)


# ---------------------------------------------------------------------------
# BUG-05: is_default uniqueness
# ---------------------------------------------------------------------------


def test_only_one_choice_can_be_default(conn):
    """BUG-05, fixed by migration 111's partial unique index."""
    cur, _m, _c, item = _menu(conn, "DBX-bug05")
    opt = insert_option(cur, "DBX-opt-size", item, True, 1, 1)
    insert_choice(cur, "DBX-ch-small", opt, 0.00, is_default=True)
    with pytest.raises(Exception) as exc:
        insert_choice(cur, "DBX-ch-medium", opt, 0.00, is_default=True)
    begin(conn)
    assert "one_default" in str(exc.value)

    # begin(conn) rolled back the whole transaction, including the item, so
    # rebuild the menu before asserting on what survived.
    cur, _m, _c, item = _menu(conn, "DBX-bug05")
    opt = insert_option(cur, "DBX-opt-size", item, True, 1, 1)
    insert_choice(cur, "DBX-ch-small", opt, 0.00, is_default=True)
    insert_choice(cur, "DBX-ch-large", opt, 20.00)  # non-default is fine

    defaults = scalar(
        conn,
        "SELECT count(*) FROM public.item_option_choices WHERE option_id=%s AND is_default",
        (opt,),
    )
    assert defaults == 1, "migration 111 must allow exactly one default per group"


def test_unique_index_on_option_default_exists(conn):
    """Static proof: nothing enforces at most one default choice per group.
    (The primary key on id is of course unique; that is not what we mean.)"""
    covering = scalar(
        conn,
        """
        SELECT count(*) FROM pg_index i
        JOIN pg_class c ON c.oid = i.indexrelid
        WHERE i.indisunique AND strpos(c.relname, 'item_option_choice') > 0
AND strpos(pg_get_indexdef(i.indexrelid), 'is_default') > 0
        """,
    )
    assert covering == 1, (
        "migration 111 must add a unique index covering is_default"
    )


# ---------------------------------------------------------------------------
# BUG-06: negative price modifiers
# ---------------------------------------------------------------------------


def test_negative_price_modifier_is_now_accepted(conn):
    """BUG-06 reproduced: a price reduction of -5 EGP is refused by CHECK."""
    cur, _m, _c, item = _menu(conn, "DBX-bug06")
    opt = insert_option(cur, "DBX-opt-extras", item, False, 0, None)

    ch = insert_choice(cur, "DBX-ch-discount", opt, price_modifier=-5.00)
    got = conn.execute(
        "SELECT price_modifier FROM public.item_option_choices WHERE id=%s", (ch,)
    ).fetchone()[0]
    assert float(got) == -5.00, "migration 111 must permit a price reduction"


def test_price_modifier_check_allows_negative(conn):
    """Static proof of BUG-06."""
    found = [
        d
        for _t, _n, d in check_constraints(conn)
        if "price_modifier" in d
    ]
    assert found, "expected a CHECK mentioning price_modifier"
    # Postgres renders the literal as (0)::numeric.
    # Postgres renders the literal as ('-1000000'::integer)::numeric.
    assert any("1000000" in d and ">=" in d for d in found), (
        f"migration 111 must lower the floor to allow reductions -> {found}"
    )


# ---------------------------------------------------------------------------
# BUG-07: default + unavailable
# ---------------------------------------------------------------------------


def test_sold_out_choice_cannot_be_default(conn):
    """BUG-07: is_default AND is_available = FALSE is accepted, so the UI would
    pre-select something the customer cannot order."""
    cur, _m, _c, item = _menu(conn, "DBX-bug07")
    opt = insert_option(cur, "DBX-opt-extras", item, False, 0, None)
    with pytest.raises(Exception) as exc:
        insert_choice(cur, "DBX-ch-soldout", opt, 0.00, is_default=True, is_available=False)
    assert "sold-out choice" in str(exc.value)


# ---------------------------------------------------------------------------
# Verified-good behaviour (regression guards)
# ---------------------------------------------------------------------------


def test_max_selections_null_means_unlimited(conn):
    cur, _m, _c, item = _menu(conn, "DBX-good-unlimited")
    opt = insert_option(cur, "DBX-opt-unlimited", item, False, 0, None)
    row = conn.execute("SELECT max_selections FROM public.item_options WHERE id=%s", (opt,)).fetchone()
    assert row == (None,)


def test_single_select_group_enforced_by_app_only(conn):
    """max_selections = 1 is the 'Size' radio pattern. Nothing at the DB level
    stops two choices being picked; that is application logic. Recorded here
    so the dashboard contract is explicit."""
    cur, _m, _c, item = _menu(conn, "DBX-good-radio")
    opt = insert_option(cur, "DBX-opt-size", item, True, 1, 1)
    insert_choice(cur, "DBX-ch-small", opt, 0.00, is_default=True)
    insert_choice(cur, "DBX-ch-large", opt, 20.00)
    count = scalar(conn, "SELECT count(*) FROM public.item_option_choices WHERE option_id=%s", (opt,))
    assert count == 2


def test_option_choices_cascade_with_their_item(conn):
    cur, _m, _c, item = _menu(conn, "DBX-good-cascade")
    opt = insert_option(cur, "DBX-opt-size", item, True, 1, 1)
    ch = insert_choice(cur, "DBX-ch-small", opt)
    cur.execute("DELETE FROM public.items WHERE id=%s", (item,))
    assert scalar(conn, "SELECT count(*) FROM public.item_options WHERE id=%s", (opt,)) == 0
    assert scalar(conn, "SELECT count(*) FROM public.item_option_choices WHERE id=%s", (ch,)) == 0
