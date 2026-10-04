"""Alias registry: every fixture row gets a readable alias and a stable UUID.

Why aliases: fixtures must be trivially clearable. Every row this suite creates
carries an ALIAS in its *_en / *_ar name columns, so cleanup is a single
`DELETE ... WHERE name_en LIKE 'DBX-%'` -- no UUID bookkeeping.

Why stable UUIDs: derived with uuid5 from the alias itself, so re-running the
suite collides on the same rows instead of creating duplicates, and a test that
prints a UUID can be matched back to its alias by eye.
"""

from __future__ import annotations

import uuid

# Fixed namespace. Never change this -- it would change every generated UUID.
NAMESPACE = uuid.UUID("6f1d5b7e-0c4a-4e2f-9a3b-1d2c3e4f5a6b")

# Every alias this suite is allowed to create, in FK-safe insert order.
ALIAS_PREFIX = "DBX"

ALIAS_MERCHANT = f"{ALIAS_PREFIX}-merchant-cafe"
ALIAS_MERCHANT_2 = f"{ALIAS_PREFIX}-market-grocery"
ALIAS_MERCHANT_INACTIVE = f"{ALIAS_PREFIX}-merchant-inactive"
ALIAS_MERCHANT_PENDING = f"{ALIAS_PREFIX}-merchant-pending"
ALIAS_MERCHANT_BRANCH_PARENT = f"{ALIAS_PREFIX}-merchant-chain"

ALIAS_CATEGORY_MAIN = f"{ALIAS_PREFIX}-cat-mains"
ALIAS_CATEGORY_SIDES = f"{ALIAS_PREFIX}-cat-sides"
ALIAS_CATEGORY_OTHER_MERCHANT = f"{ALIAS_PREFIX}-cat-foreign"

ALIAS_ITEM_BASE = f"{ALIAS_PREFIX}-item-koshari"
ALIAS_ITEM_NO_OPTIONS = f"{ALIAS_PREFIX}-item-plainrice"
ALIAS_ITEM_FOREIGN = f"{ALIAS_PREFIX}-item-foreign"

ALIAS_OPTION_SIZE = f"{ALIAS_PREFIX}-opt-size"
ALIAS_OPTION_EXTRAS = f"{ALIAS_PREFIX}-opt-extras"

ALIAS_CHOICE_SMALL = f"{ALIAS_PREFIX}-ch-small"
ALIAS_CHOICE_MEDIUM = f"{ALIAS_PREFIX}-ch-medium"
ALIAS_CHOICE_LARGE = f"{ALIAS_PREFIX}-ch-large"
ALIAS_CHOICE_EXTRA_SAUCE = f"{ALIAS_PREFIX}-ch-sauce"
ALIAS_CHOICE_DISCOUNT = f"{ALIAS_PREFIX}-ch-discount"
ALIAS_CHOICE_SOLD_OUT_DEFAULT = f"{ALIAS_PREFIX}-ch-soldout-default"


def uid(alias: str) -> uuid.UUID:
    """Deterministic UUID for an alias."""
    return uuid.uuid5(NAMESPACE, alias)


def ar(alias: str) -> str:
    """Arabic name carrying the alias, so every fixture row is greppable in ar too."""
    return f"[{alias}]"


def en(alias: str) -> str:
    """English name carrying the alias."""
    return f"[{alias}]"


def alias_pattern() -> str:
    """LIKE pattern matching every row this suite can create."""
    return f"[{ALIAS_PREFIX}-%"


# Merchant fixtures: (alias, category_code, is_active, approval_status)
MERCHANTS = [
    (ALIAS_MERCHANT, "restaurant", True, "approved"),
    (ALIAS_MERCHANT_2, "grocery", True, "approved"),
    (ALIAS_MERCHANT_INACTIVE, "restaurant", False, "approved"),
    (ALIAS_MERCHANT_PENDING, "bakery", True, "pending"),
    (ALIAS_MERCHANT_BRANCH_PARENT, "market", True, "approved"),
]

# Category fixtures: (alias, merchant_alias)
CATEGORIES = [
    (ALIAS_CATEGORY_MAIN, ALIAS_MERCHANT),
    (ALIAS_CATEGORY_SIDES, ALIAS_MERCHANT),
    # Belongs to merchant 2 -- used to prove items can be cross-wired today.
    (ALIAS_CATEGORY_OTHER_MERCHANT, ALIAS_MERCHANT_2),
]

# Item fixtures: (alias, merchant_alias, category_alias, price)
ITEMS = [
    (ALIAS_ITEM_BASE, ALIAS_MERCHANT, ALIAS_CATEGORY_MAIN, 45.00),
    (ALIAS_ITEM_NO_OPTIONS, ALIAS_MERCHANT, ALIAS_CATEGORY_SIDES, 15.00),
    (ALIAS_ITEM_FOREIGN, ALIAS_MERCHANT, ALIAS_CATEGORY_OTHER_MERCHANT, 30.00),
]

# Option-group fixtures: (alias, item_alias, is_required, min_sel, max_sel)
OPTIONS = [
    (ALIAS_OPTION_SIZE, ALIAS_ITEM_BASE, True, 1, 1),
    (ALIAS_OPTION_EXTRAS, ALIAS_ITEM_BASE, False, 0, None),
]

# Choice fixtures: (alias, option_alias, price_modifier, is_default, is_available)
CHOICES = [
    (ALIAS_CHOICE_SMALL, ALIAS_OPTION_SIZE, 0.00, True, True),
    (ALIAS_CHOICE_MEDIUM, ALIAS_OPTION_SIZE, 10.00, False, True),
    (ALIAS_CHOICE_LARGE, ALIAS_OPTION_SIZE, 20.00, False, True),
    (ALIAS_CHOICE_EXTRA_SAUCE, ALIAS_OPTION_EXTRAS, 5.00, False, True),
    # Negative modifier: proves/disproves that price reductions are possible.
    (ALIAS_CHOICE_DISCOUNT, ALIAS_OPTION_EXTRAS, -5.00, False, True),
    # default AND unavailable at once.
    (ALIAS_CHOICE_SOLD_OUT_DEFAULT, ALIAS_OPTION_EXTRAS, 0.00, True, False),
]