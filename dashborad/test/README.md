# Database Test Suite

133 assertions against the real schema, running entirely on local PostgreSQL.
**No Supabase project is contacted**, so this costs zero egress against your
free-plan allowance.

| Run | Result |
|---|---|
| Seeded (~200k rows) | **131 passed, 2 skipped, 1.4s** |
| Empty schema | **88 passed, 21 skipped, 1.0s** |

The scale tests skip rather than report false passes when the database is empty.

> All **118** migrations replay cleanly — 106 original plus fixes **107–119**.
> Every bug test was first written to assert the bug *exists*, then flipped to
> assert the corrected behaviour once its migration landed. That inversion is the
> evidence a fix actually worked.
>
> The suite found six defects in my own migrations, including that
> **`place_order_with_items` had never successfully executed since migration
> 026** — `RETURNS TABLE(id UUID, …)` made every bare `WHERE id = …` ambiguous.
> See `BUG-REPORT.md` §5.

---

## Run it

```powershell
cd dashborad/test

# 1. build the database from the real migrations (~10s, after any change under
#    supabase/migrations/)
uv run python local\reset_db.py

# 2. optional: load ~200k rows so index behaviour is real
uv run python local\seed_data.py --analyze

# 3. run the tests
uv run pytest -q
```

`reset_db.py` mirrors `supabase db reset`: drop, recreate, apply the Supabase
stubs, then replay all 118 files from `supabase/migrations/` in filename order,
each in its own transaction. **If any migration fails it stops and refuses to
grant defaults** — a partial schema would make the tests lie.

## Why seeding matters

Against an empty schema a sequential scan of nothing is free, so no index is
ever exercised. Four real bugs (BUG-14 to BUG-17) were invisible until the
database held realistic row counts. `seed_data.py` loads:

```
orders               50,000      order_items        124,840
customers             8,000      addresses            8,000
reviews               6,000      favorite_items       2,400
items                 2,400      item_options         1,815
discounted_items      2,220      item_option_choices  6,343
categories               480      merchants               60
operating_hours        420
```

`merchants` is intentionally small — at 60 rows the planner prefers sequential
scans regardless of indexing, which is itself asserted (see `test_08`). Raise
`MERCHANTS` there to test merchant-side indexes properly.

`discounted_items` is ~12% of the catalog. Deliberate: high enough that a
selective `discount_price` filter uses `idx_items_discounted`, low enough that
the planner still correctly prefers a scan for the blanket "everything on
promotion" filter. An assertion that it must not scan fails — the planner is
right.

## Requirements

- Local PostgreSQL (developed against 18.6, service `postgresql-x64-18`)
- Superuser password — from `TEST_PG_ADMIN_PASSWORD`, else `LOCAL_PG_ADMIN_PASSWORD`, else `root`
- `uv` (already installed)

---

## Safety model

1. **Every test runs in a transaction that is rolled back.** A crashing test
   still leaves nothing behind.
2. **Every fixture row is aliased.** Names carry `[DBX-...]` in both `name_en`
   and `name_ar`, so residue from an aborted run is one statement:
   ```sql
   DELETE FROM public.merchants WHERE name_en LIKE '[DBX-%';
   ```
3. **Deterministic UUIDs.** `aliases.uid()` derives a UUIDv5 from the alias, so
   re-runs collide on the same rows instead of duplicating them, and a UUID
   printed in a failure can be matched back to its alias by eye.
4. **Verified.** The live project was queried during early development before
   the local database existed; residue check afterwards returned 0 fixture rows
   across all 9 affected tables and the merchant count was unchanged.

## Pointing at a real project (not recommended)

```powershell
$env:TEST_DATABASE_URL = "postgresql://..."
uv run pytest -q
```

This works but spends quota. Prefer local.

---

## Layout

```
test/
  aliases.py                    alias registry + deterministic UUIDs + fixture shapes
  conftest.py                   connection, BEGIN/ROLLBACK, introspection helpers,
                                row builders
  local/
    bootstrap.sql               Supabase stubs (auth / storage / postgis /
                                pg_cron / vault) + NOLOGIN roles + publication
    reset_db.py                 drop -> create -> bootstrap -> replay migrations
    seed_data.py                ~200k rows of realistic volume, fixed RNG seed
  test_01_operating_hours.py    day-of-week, overnight windows, 24h merchants
  test_02_catalog_integrity.py  item <-> category ownership, cascades, indexes
  test_03_options.py            selection cardinality, defaults, price modifiers
  test_04_merchants.py          columns, approval, city/area, discount shape
  test_05_data_loss.py          delete cascade destroying order history
  test_06_rls.py                the admin dashboard's exact read/write surface
  test_07_reporting.py          KPI RPCs, review summary, stale matview
  test_08_scale.py              index + plan behaviour at real cardinality
  test_09_discounts.py          item discounts, order pricing, checkout guards
  BUG-REPORT.md                 what the tests found
```

## Coverage note: the write path was the gap

For its whole life this suite tested the catalog, RLS and reporting but never
called `place_order_with_items` — which is why a function that could not execute
at all went unnoticed. `test_09_discounts.py` now exercises the order path:
server-side pricing, client-price override refused, subtotal derived,
header reconciling with lines, soft-delete and availability and approval gates,
and the service-role guard.

## How the Supabase shims work

A vanilla PostgreSQL install has none of the Supabase-managed objects, and
`GRANT ... TO anon` is a hard error without the role — so a single missing role
aborts a migration that creates half the schema. `bootstrap.sql` supplies:

| Supabase object | Local stand-in | Used by |
|---|---|---|
| `auth.users`, `auth.uid()`, `auth.jwt()`, `auth.role()` | stub table + SQL functions | 17 migrations |
| `storage.buckets`, `storage.objects`, `storage.foldername()` | stub table + `text[]` function | 025 |
| `postgis` | `ST_MakePoint`, `ST_Distance` (haversine), `geography` domain | 001, 009, 016, 031, 032 |
| `pg_cron` | `cron.job` table + no-op `schedule`/`unschedule` | 077, 089, 094, 095 |
| `vault` | settings table + `create_secret`/`read_secret` | 027, 028, 037 |
| `anon` / `authenticated` / `service_role` | `NOLOGIN` roles | every GRANT |
| `supabase_realtime` | empty publication | 053, 058, 064, 092 |

`reset_db.py` additionally rewrites `CREATE EXTENSION` for unavailable
extensions into a comment. This matters most for **postgis**: migration 001
creates postgis *first*, so when it fails the whole migration rolls back,
`pg_trgm` is never installed, and every trigram index in 016 and 095 then fails
too. One shim unblocks five migrations.

After a clean replay the script applies Supabase's default table grants. Without
them a request as `anon` is rejected with *permission denied for table* before
RLS is ever consulted — and every RLS test would pass for the wrong reason.

**None of this is deployed.** On Supabase these objects already exist and
`bootstrap.sql` is never run. Known blind spots are listed in §8 of
`BUG-REPORT.md`.

## Adding a test

```python
def test_something(conn):
    """State the bug being pinned, then assert the CURRENT (wrong) behaviour.

    A bug test asserts the bug EXISTS, so it fails loudly once the fix lands --
    at which point flip the assertion to the correct behaviour. That inversion
    is the point: it is what makes the fix verifiable.
    """
    cur = conn.cursor()
    m = insert_merchant(cur, "DBX-my-alias", "restaurant", True, "approved")
    ...
    assert some_wrong_thing, "expected BUG-NN: ..."
```

Builders live in `conftest.py`: `insert_merchant`, `insert_category`,
`insert_item`, `insert_option`, `insert_choice`, `make_customer`.

Introspection helpers: `columns`, `check_constraints`, `foreign_keys`,
`indexes`, `policies`, `rls_enabled`, `scalar`.

**One gotcha:** psycopg3 treats a bare `%` in a query as a placeholder and
raises `only '%s', '%b', '%t' are allowed`. Use `strpos(col, 'text') > 0`
instead of `LIKE '%text%'`.

**Second gotcha, already handled for you:** psycopg3 automatically creates
prepared statements after 5 executions of the same query. A cached generic plan
ignores an index created mid-test, which made `test_08` order-dependent. The
connection is opened with `prepare_threshold=None`. Don't remove it.

**Third, the rule that caused the most false failures:** a test that counts rows
must scope to its own `[DBX-…]` alias, never a global count. Seed data exists
precisely so global counts are non-zero.