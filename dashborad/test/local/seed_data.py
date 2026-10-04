"""Fill marketak_test with realistic volumes so index behaviour is real.

    uv run python local/seed_data.py            # seed
    uv run python local/seed_data.py --analyze  # seed + ANALYZE

Why this exists: every other test in this suite runs against an empty schema,
where PostgreSQL happily uses a sequential scan because a sequential scan of
nothing is free. Bugs that only appear at cardinality -- a missing index, a
quadratic plan, an unindexed moderation filter -- are invisible until there are
rows.

Volumes are aimed at a launch marketplace, roughly what 6-12 months of a
Cairo/Giza/ Alexandria marketplace would hold:

    8       merchant categories
    60      merchants
    420     operating_hours rows (7 per merchant)
    480     menu categories (8 per merchant)
    2,400   items (40 per merchant)
    ~3,500  item_options
    ~12,000 item_option_choices
    8,000   customers
    50,000  orders
    ~120,000 order_items
    6,000   reviews (half unmoderated)
    5,000   favorite_items
    12,000  addresses

Row counts are printed at the end so a test can assert the scale it assumes.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import random
import sys
import uuid
from datetime import datetime, timedelta, timezone

import psycopg

HERE = pathlib.Path(__file__).resolve().parent

MERCHANTS = 60
CATEGORIES_PER_MERCHANT = 8
ITEMS_PER_CATEGORY = 5  # 8 * 5 * 60 = 2,400
OPTIONS_PER_ITEM = 1.5  # probabilistic
CHOICES_PER_OPTION = 4
CUSTOMERS = 8_000
ORDERS = 50_000
LINES_PER_ORDER = (1, 4)
REVIEWS = 6_000
FAVORITES = 5_000
ADDRESSES = 12_000

CITIES = ["Cairo", "Giza", "Alexandria"]
AREAS = ["Dokki", "Maadi", "Nasr City", "Mohandessin", "Heliopolis", "Zamalek"]

ORDER_STATUSES = [
    ("delivered", 62),
    ("cancelled", 8),
    ("pending", 6),
    ("confirmed", 5),
    ("preparing", 5),
    ("ready", 4),
    ("picked_up", 3),
    ("on_the_way", 7),
]

CAT_WORDS_EN = ["Grills", "Sides", "Drinks", "Desserts", "Breakfast", "Sauces",
                "Sandwiches", "Salads", "Pasta", "Rice", "Soups", "Coffee"]
CAT_WORDS_AR = ["مشاوي", "أطباق جانبية", "مشروبات", "حلويات", "فطار", "صلصات",
                "ساندوتشات", "سلطات", "باستا", "رز", "شوربات", "قهوة"]

ITEM_WORDS_EN = ["Koshari", "Ful Medames", "Shawarma", "Burger", "Pizza", "Salad",
                 "Soup", "Rice Bowl", "Sandwich", "Grilled Cheese", "Pasta",
                 "Steak", "Falafel", "Eggplant", "Chicken", "Fish", "Fries"]
ITEM_WORDS_AR = ["كشري", "فول مدمس", "شاورما", "برجر", "بيتزا", "سلطة",
                 "شوربة", "رز", "ساندوتش", "جبن مشوي", "باستا", "ستيك",
                 "فلافل", "باذنجان", "فراخ", "سمك", "بطاطس"]

SIZE_CHOICES = [("صغير", "Small", 0.00), ("وسط", "Medium", 10.00), ("كبير", "Large", 20.00)]
EXTRA_CHOICES = [
    ("صلصة إضافية", "Extra Sauce", 5.00),
    ("بصل مقرمش", "Crispy Onions", 5.00),
    ("دقة", "Dakka", 3.00),
    ("جبنextra", "Extra Cheese", 8.00),
]


def dsn() -> str:
    import os

    host = os.environ.get("LOCAL_PG_HOST", "127.0.0.1")
    port = os.environ.get("LOCAL_PG_PORT", "5432")
    return (
        f"postgresql://marketak_test:marketak_test@{host}:{port}/marketak_test"
        "?sslmode=disable"
    )


def uid(n: int) -> str:
    return str(uuid.UUID(int=n))


def build(conn) -> dict[str, int]:
    rnd = random.Random(20261003)  # fixed seed: reproducible volumes
    counts: dict[str, int] = {}

    with conn.cursor() as cur:
        # -- merchant categories: the 8 launch codes already exist (097) -----
        cur.execute("SELECT code FROM public.merchant_categories ORDER BY sort_order")
        codes = [r[0] for r in cur.fetchall()]

        # -- auth users + profiles -------------------------------------------
        # profiles are created by the on_auth_user_created trigger (002), so
        # only auth.users is inserted here.
        customer_ids: list[str] = []
        batch = 2_000
        for start in range(0, CUSTOMERS, batch):
            n = min(batch, CUSTOMERS - start)
            cur.executemany(
                "INSERT INTO auth.users (id, email) VALUES (%s, %s)",
                [(uid(10_000_000 + start + i), f"c{start + i}@seed.test")
                 for i in range(n)],
            )
        cur.execute(
            "SELECT id FROM public.profiles WHERE id >= %s ORDER BY id",
            (uid(10_000_000),),
        )
        customer_ids = [r[0] for r in cur.fetchall()]
        counts["customers"] = len(customer_ids)

        # -- merchants --------------------------------------------------------
        merchant_rows = []
        for i in range(MERCHANTS):
            m = 20_000_000 + i
            merchant_rows.append((
                uid(m), f"مطعم {i}", f"Seed Merchant {i}",
                codes[i % len(codes)], f"{i} شارع {i}", 30.0 + i * 0.001,
                31.0 + i * 0.001, CITIES[i % len(CITIES)], AREAS[i % len(AREAS)],
                f"+2010{i:07d}",
                # 80% active, 10% inactive, 10% pending approval
                i % 10 != 8, "pending" if i % 10 == 9 else "approved",
                30.0 + (i % 5) * 20.0, 20 + (i % 4) * 10,
            ))
        cur.executemany(
            """
            INSERT INTO public.merchants
              (id, name_ar, name_en, category, address, lat, lng, city, area,
               phone, is_active, approval_status, min_order_amount,
               estimated_delivery_minutes)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
            """,
            merchant_rows,
        )
        merchant_ids = [r[0] for r in merchant_rows]
        counts["merchants"] = len(merchant_ids)

        # -- operating hours: 7 rows per merchant, ISO dow 1..7 (migration 107) --
        cur.executemany(
            """
            INSERT INTO public.operating_hours
              (merchant_id, day_of_week, open_time, close_time, is_closed)
            VALUES (%s, %s, %s, %s, FALSE)
            """,
            [
                (mid, dow, "09:00" if dow != 6 else "10:00",
                 "23:00" if dow not in (5, 6) else "01:00")
                for mid in merchant_ids
                for dow in range(1, 8)  # ISO 1=Mon .. 7=Sun
            ],
        )
        counts["operating_hours"] = len(merchant_ids) * 7

        # -- menu categories --------------------------------------------------
        cat_rows = []
        n = 30_000_000
        for mid in merchant_ids:
            for j in range(CATEGORIES_PER_MERCHANT):
                cat_rows.append((
                    uid(n), mid, CAT_WORDS_AR[j % len(CAT_WORDS_AR)],
                    f"{CAT_WORDS_EN[j % len(CAT_WORDS_EN)]} {mid[-4:]}-{j}",
                    j + 1,
                ))
                n += 1
        cur.executemany(
            "INSERT INTO public.categories (id, merchant_id, name_ar, name_en, sort_order)"
            " VALUES (%s,%s,%s,%s,%s)",
            cat_rows,
        )
        counts["categories"] = len(cat_rows)
        categories_by_merchant: dict[str, list[str]] = {}
        for cid, mid, *_ in cat_rows:
            categories_by_merchant.setdefault(mid, []).append(cid)

        # -- items ------------------------------------------------------------
        item_rows = []
        n = 40_000_000
        items_by_category: dict[str, list[str]] = {}
        for cid, mid, *_ in cat_rows:
            for k in range(ITEMS_PER_CATEGORY):
                word = ITEM_WORDS_EN[(n % len(ITEM_WORDS_EN))]
                word_ar = ITEM_WORDS_AR[(n % len(ITEM_WORDS_AR))]
                item_rows.append((
                    uid(n), mid, cid, word_ar, f"{word} {n % 1000}",
                    15.0 + (n % 40) * 5.0,
                    True if n % 17 else False,  # ~6% unavailable
                    k + 1, n % 1000,
                ))
                items_by_category.setdefault(cid, []).append(uid(n))
                n += 1
        # -- item discounts (migration 119) ---------------------------------
        # ~12% of items on promotion, so idx_items_discounted and the
        # "top discounted items" report are exercised at realistic cardinality.
        item_rows = [list(r) for r in item_rows]
        for row in item_rows:
            list_price = row[5]
            # A discount is set only when there is room for it to read as one;
            # an 80% off 15 EGP item is noise, not a promotion.
            row.append(
                round(list_price * 0.8, 2)
                if list_price >= 30.0 and int(row[0][:2], 16) % 8 == 0
                else None
            )
        cur.executemany(
            """
            INSERT INTO public.items
              (id, merchant_id, category_id, name_ar, name_en, price,
               is_available, sort_order, popularity_score, discount_price)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
            """,
            item_rows,
        )
        counts["items"] = len(item_rows)
        counts["discounted_items"] = sum(1 for r in item_rows if r[9] is not None)

        # -- item options + choices ------------------------------------------
        opt_rows = []
        n = 50_000_000
        for iid, *_ in item_rows:
            if rnd.random() > OPTIONS_PER_ITEM / 2:
                continue
            required = rnd.random() < 0.5
            opt_rows.append((
                uid(n), iid, "الحجم" if required else "إضافات",
                "Size" if required else "Extras", required,
                1 if required else None, 1 if required else 0,
                len(opt_rows) % 3 + 1,
            ))
            n += 1
        cur.executemany(
            """
            INSERT INTO public.item_options
              (id, item_id, name_ar, name_en, is_required, max_selections,
               min_selections, sort_order)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s)
            """,
            opt_rows,
        )
        counts["item_options"] = len(opt_rows)

        choice_rows = []
        n = 60_000_000
        for oid, iid, _ar, en, required, *_ in opt_rows:
            pool = SIZE_CHOICES if en == "Size" else EXTRA_CHOICES
            for idx, (ar, en_c, mod) in enumerate(pool):
                choice_rows.append((
                    uid(n), oid, ar, f"{en_c} {idx}", mod, idx == 0, True, idx + 1,
                    (40 if en == "Size" else 120) + idx * 30,
                ))
                n += 1
        cur.executemany(
            """
            INSERT INTO public.item_option_choices
              (id, option_id, name_ar, name_en, price_modifier, is_default,
               is_available, sort_order, calories)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)
            """,
            choice_rows,
        )
        counts["item_option_choices"] = len(choice_rows)

        # -- addresses --------------------------------------------------------
        cur.executemany(
            """
            INSERT INTO public.addresses
              (user_id, label, title_ar, title_en, address, building_number,
               city, area, lat, lng, is_default)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """,
            [
                (cid, "home", "المنزل", "Home", f"{i} Test St", str(i % 90 + 1),
                 CITIES[i % 3], AREAS[i % 6], 30.0, 31.0, True)
                for i, cid in enumerate(customer_ids[:ADDRESSES])
            ],
        )
        counts["addresses"] = min(len(customer_ids), ADDRESSES)

        # -- orders + order_items --------------------------------------------
        statuses, weights = zip(*ORDER_STATUSES)
        order_rows = []
        n = 70_000_000
        for i in range(ORDERS):
            status = rnd.choices(statuses, weights=weights)[0]
            cust = rnd.choice(customer_ids)
            merch = rnd.choice(merchant_ids)
            subtotal = 40.0 + (i % 60) * 12.5
            fee = 0.0 if subtotal > 200 else 25.0
            order_rows.append([
                uid(n), f"ORD-SEED{i:07d}", cust, merch, status,
                json.dumps({"address": f"{i} St", "city": CITIES[i % 3]}),
                round(subtotal, 2), fee, 3.0, 0.0, round(subtotal + fee + 3.0, 2),
                "cash" if i % 4 else "card",
                "paid" if status == "delivered" else "pending",
                round(0.5 + (i % 60) * 0.25, 2), 20 + (i % 30),
            ])
            n += 1

        # Spread created_at over ~18 months, with a mild upward trend so the
        # daily-series graph has a shape rather than a flat line.
        #
        # This matters for more than realism: with every order stamped NOW(), no
        # date window is ever selective, so the planner correctly prefers a
        # sequential scan everywhere and the orders(created_at) index can never
        # be shown to earn its keep.
        span_days = 540
        # Spread created_at over ~18 months, with a mild upward trend so the
        # daily-series graph has a shape rather than a flat line.
        #
        # This matters for more than realism: with every order stamped NOW(), no
        # date window is ever selective, so the planner correctly prefers a
        # sequential scan everywhere and the orders(created_at) index can never
        # be shown to earn its keep.
        #
        # Computed in Python rather than as a SQL expression so the values bind
        # as real timestamptz in a single executemany, instead of one round trip
        # per distinct expression.
        span_days = 540
        now = datetime.now(timezone.utc)
        for i, row in enumerate(order_rows):
            age_days = span_days * (1.0 - ((i / ORDERS) ** 0.85))
            row.append(
                now - timedelta(
                    days=age_days,
                    minutes=rnd.randint(0, 1439),
                    seconds=rnd.randint(0, 59),
                )
            )

        cur.executemany(
            """
            INSERT INTO public.orders
              (id, order_number, customer_id, merchant_id, status,
               delivery_address, subtotal, delivery_fee, platform_fee,
               discount_amount, total, payment_method, payment_status,
               distance_km, estimated_delivery_minutes, created_at)
            VALUES (%s,%s,%s,%s,%s,%s::jsonb,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
            """,
            order_rows,
        )
        counts["orders"] = len(order_rows)

        all_items = [(r[0], r[1]) for r in item_rows]  # (item_id, merchant_id)
        lines = []
        n = 80_000_000
        for oid, _num, _cust, merch, status, *_ in order_rows:
            for _ in range(rnd.randint(*LINES_PER_ORDER)):
                # bias toward items belonging to the order's merchant
                iid, imerch = (
                    rnd.choice(all_items)
                    if rnd.random() < 0.8
                    else (lambda p: (p[0], p[1]))(rnd.choice(all_items))
                )
                price = 15.0 + (int(iid.split("-")[0], 16) % 40) * 5.0
                qty = rnd.randint(1, 3)
                opts = (
                    '[{"option_name_en":"Size","choice_name_en":"Large 2",'
                    '"price_modifier":20.00}]'
                    if rnd.random() < 0.4 else "[]"
                )
                lines.append((
                    uid(n), oid, iid, "صنف", f"Seeded Item {n % 500}",
                    price, qty, opts, round(price * qty, 2), None,
                ))
                n += 1
        cur.executemany(
            """
            INSERT INTO public.order_items
              (id, order_id, item_id, item_name_ar, item_name_en, item_price,
               quantity, selected_options, total_price, special_instructions)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s::jsonb,%s,%s)
            """,
            lines,
        )
        counts["order_items"] = len(lines)

        # -- reviews: half unmoderated (104 default) --------------------------
        rev_rows = []
        n = 90_000_000
        for i in range(REVIEWS):
            o = order_rows[i]
            rev_rows.append((
                uid(n), o[0], o[2], o[3], 1 + (i % 5),
                f"Seed review {i}", i % 2 == 0,  # half visible
            ))
            n += 1
        # reviews has a UNIQUE index on order_id, so use distinct orders
        seen: set[str] = set()
        deduped = []
        for r in rev_rows:
            oid = r[1]
            if oid in seen:
                continue
            seen.add(oid)
            deduped.append(r)
        cur.executemany(
            """
            INSERT INTO public.reviews
              (id, order_id, customer_id, merchant_id, merchant_rating,
               merchant_comment, is_visible)
            VALUES (%s,%s,%s,%s,%s,%s,%s)
            """,
            deduped,
        )
        counts["reviews"] = len(deduped)

        # -- favorites --------------------------------------------------------
        cur.executemany(
            "INSERT INTO public.favorite_items (user_id, item_id, merchant_id)"
            " VALUES (%s,%s,%s)",
            [
                (customer_ids[i % len(customer_ids)], r[0], r[1])
                for i, r in enumerate(all_items[:FAVORITES])
            ],
        )
        counts["favorite_items"] = min(len(all_items), FAVORITES)

    conn.commit()
    return counts


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--analyze", action="store_true", help="run ANALYZE after seeding")
    args = ap.parse_args()

    print(f"seeding {dsn()}")
    with psycopg.connect(dsn(), autocommit=False) as conn:
        existing = conn.execute("SELECT count(*) FROM public.merchants").fetchone()[0]
        if existing:
            print(
                f"  database already has {existing} merchants -- reset first "
                "(uv run python local/reset_db.py)"
            )
            return 1
        counts = build(conn)

    if args.analyze:
        with psycopg.connect(dsn(), autocommit=True) as conn:
            conn.execute("ANALYZE")
        print("  ANALYZE complete")

    print("\nrow counts:")
    for table, n in sorted(counts.items()):
        print(f"  {table:24} {n:>9,}")
    return 0


if __name__ == "__main__":
    sys.exit(main())