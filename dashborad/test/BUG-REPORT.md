# Database Bug Report — Marketak / Jaylak Supabase Schema

**Method:** 133 automated assertions in `dashborad/test/`, run against a local PostgreSQL 18 database built by replaying all **118** migrations from `supabase/migrations/` and loaded with ~200,000 rows of generated volume. No live-project queries.
**Engine:** PostgreSQL 18.6 (local). Production is PG 15/17 — flagged where a finding may be version-sensitive.
**Run (seeded, after fixes):** `131 passed, 2 skipped, 1.4s`
**Run (empty schema):** `88 passed, 21 skipped, 1.0s` — the scale suite skips cleanly rather than reporting false passes.

> ## Status: 16 of 16 code bugs fixed, plus REQ-02 delivered
>
> Migrations **107–119** are written and verified. Every bug test below was
> originally written to *assert the bug exists*; each was then flipped to assert
> the corrected behaviour once its migration landed. That inversion is the
> evidence — a fix that did not work would have left its test red.
>
> **The most serious finding in this report is not a bug in the catalog. It is
> that `place_order_with_items` — the checkout function — had never executed
> successfully, in any environment, since migration 026.** See §5.5.

| Severity | Count | IDs → migration |
|---|---|---|
| 🔴 Blocking | 3 | BUG-01 → **107**, BUG-08 → **110**, BUG-13 → **109** |
| 🟠 Correctness | 6 | BUG-03 → **112**, BUG-05 → **111**, BUG-06 → **111**, BUG-09 → **114**, BUG-11 → **113**, BUG-10 → *no migration needed* |
| 🟡 Data quality | 4 | BUG-02 → **118**, BUG-04 → **111**, BUG-07 → **111**, BUG-12 → **117** |
| 🔵 Performance | 4 | BUG-14 → **108**, BUG-15 → **116**, BUG-16 → **116**, BUG-17 → **114** |
| ✅ Requirement | 1 | REQ-02 item discounts → **119** |
| 🔴 Latent, pre-existing | 1 | **BUG-19** `place_order_with_items` never executable → **119** |
| 🟠 Partially fixed | 1 | **BUG-18** client-supplied prices → half fixed by **119**, fee paths open |
| ⚪ Documentation | 1 | DOC-01 — **open**, comment in 098 not yet corrected |
| 🔵 Requirement gaps | 1 | REQ-01 branches — **open, needs your decision** |

**Four claims in my first report were wrong** (§4), **one bug I had missed**
(BUG-13), **three bugs only visible at scale** (§2.5), and **six defects in my
own fix migrations and their tests**, caught by the suite before shipping (§5).

---

## 1. 🔴 Blocking

### BUG-01 — Sunday can never be open; a merchant open every stored day reads CLOSED

**Where:** `operating_hours.day_of_week` (006:18) vs `is_merchant_open()` (017:236) and `merchants_with_open_status` (031:51)

```sql
-- 006:18  stored convention
day_of_week SMALLINT NOT NULL CHECK (day_of_week BETWEEN 0 AND 6)   -- 0=Sunday

-- 017:236 and 031:51  lookup convention
AND oh.day_of_week = EXTRACT(ISODOW FROM NOW() AT TIME ZONE 'Africa/Cairo')
                                                       -- 1=Monday ... 7=Sunday
```

Monday–Saturday coincide by accident (`0=Sunday` ⇒ `1=Monday`). **Sunday does not**: it is stored as `0` but looked up as `7`. `7` is outside the CHECK, so no such row can exist.

**Verified:** inserted a Sunday row (`day_of_week=0`, `00:00`–`23:59`). It matches the predicate at `day_of_week=0` and **does not match at `day_of_week=7`** — which is the value the function actually searches for.

**Impact:** roughly 1/7 of the week is silently dead for every merchant. A merchant open 7 days a week still shows "Closed" every Sunday, and `get_merchant_feed` sorts them into the closed bucket.

**Fix:** pick one convention. Cheapest correct change is to store ISO (`1..7`, `CHECK BETWEEN 1 AND 7`) and backfill `day_of_week = CASE WHEN day_of_week = 0 THEN 7 ELSE day_of_week + 1 END`. Alternatively keep `0..6` and change both call sites to `EXTRACT(DOW ...) + 1`.

**Test:** `test_01_operating_hours.py::test_sunday_open_row_never_matches_the_function_predicate`

---

### BUG-08 — Deleting a menu item silently erases its order history

**Where:** `items`/`categories` have no `deleted_at`; `order_items.item_id` is `ON DELETE CASCADE` (007:105)

Migration 068 added soft delete to `promo_codes` and `promoted_slots` but never to the menu. The consequence is not just "no trash view":

**Verified end-to-end:**
1. merchant → category → item → order → `order_items` line
2. `DELETE FROM items WHERE id = ...`
3. the `order_items` row is **gone** (cascade)
4. the `orders` row **survives**, still saying `total = 45.00`
5. `SUM(order_items.total_price)` for that order is now **0.00**

**Impact:** the dashboard cannot safely offer a Delete button on an item or category. Revenue history, the "top items" report, and the review-to-item trail all become permanently unreconcilable. `categories` delete cascades one level higher, taking every item in the category.

**Fix:** new migration adding `deleted_at TIMESTAMPTZ` to `items` and `categories` (mirroring 068), a partial index, and changing the FKs from `ON DELETE CASCADE` to `ON DELETE SET NULL`. Every read query then needs `WHERE deleted_at IS NULL`.

**Tests:** `test_05_data_loss.py` (5 tests)

---

### BUG-13 — Unapproved merchants are publicly visible 🆕

**Where:** policy `merchants_read_active` (020:97–100)

```sql
CREATE POLICY "merchants_read_active" ON public.merchants
  FOR SELECT USING (is_active = true);
```

Migration 103 introduced `approval_status` with `pending` = *"new place awaiting Ops"*, and the dashboard creates new merchants as pending. But pending merchants default to `is_active = TRUE`, and the read policy filters `is_active` **only**.

**Verified:** a merchant with `approval_status='pending'` is returned by a plain `SELECT` executed as role `anon`.

**Impact:** every newly onboarded vendor appears in the public feed, in `get_merchant_feed`, and in `search_catalog` **before a human has approved it**. That defeats the entire approval flow 103 was built for.

**Fix:**
```sql
DROP POLICY "merchants_read_active" ON public.merchants;
CREATE POLICY "merchants_read_active" ON public.merchants
  FOR SELECT USING (is_active = true AND approval_status = 'approved');
```
Note this also affects the matview's own WHERE clause (031:57), which filters `is_active` only.

**Test:** `test_06_rls.py::test_pending_approval_merchants_leak_to_anonymous`

---

## 2. 🟠 Correctness

### BUG-03 — An item can be filed under another merchant's category

**Where:** `items.merchant_id` and `items.category_id` (007:50–51) — two independent single-column FKs, nothing tying them together.

**Verified:** created merchant A and merchant B, a category on A, and an item with `merchant_id = B, category_id = <category on A>`. Accepted without complaint.

**Impact:** a mis-filed item is invisible from merchant B's menu query (`merchant_id + category_id` never co-occur) yet still orderable, because `place_order_with_items` resolves items by `item_id`. It produces orders attributed to the wrong merchant.

**Fix (pick one):** add `UNIQUE (id, merchant_id)` on `categories` and a composite FK `(category_id, merchant_id) → categories(id, merchant_id)`; **or** drop `items.merchant_id` and derive it from the category.

**Test:** `test_02_catalog_integrity.py::test_item_can_be_filed_under_another_merchants_category`

---

### BUG-05 — Every choice in a group can be the default

**Where:** `item_option_choices.is_default` (007:150) — no uniqueness constraint, and `item_option_choices` has **no unique index at all**.

**Verified:** three choices in a single-select group (`max_selections = 1`), all with `is_default = TRUE`. Accepted.

**Impact:** for a radio-button group (the Size pattern) the UI cannot decide what to pre-select. Non-deterministic rendering; the customer's default varies by query order.

**Fix:** `CREATE UNIQUE INDEX ... ON item_option_choices(option_id) WHERE is_default;`

---

### BUG-06 — Price reductions on options are impossible 🔴 requirement blocker

**Where:** `item_option_choices.price_modifier NUMERIC(10,2) NOT NULL DEFAULT 0.00 CHECK (price_modifier >= 0)` (007:146)

**Verified:** inserting `price_modifier = -5.00` is rejected by the CHECK.

**Impact:** you confirmed discounts and price **reductions** are required. A `-5.00 EGP` option is impossible today, and no amount of dashboard work changes that — it is a schema-level block.

**Fix:** `ALTER TABLE item_option_choices DROP CONSTRAINT item_option_choices_price_modifier_check;` and add a sanity bound instead: `CHECK (price_modifier > -items.price)` is not expressible across tables, so enforce `CHECK (price_modifier >= -100000)` at the column and validate the "modifier never exceeds base price" rule in `place_order_with_items`.

**Test:** `test_03_options.py::test_negative_price_modifier_is_rejected`

---

### BUG-09 — "Revenue" counts cancelled and refunded orders

**Where:** `get_merchant_kpis` (066:39–41) and `get_merchant_kpis_range` (091:37–41)

```sql
'revenue', COALESCE((SELECT SUM(total) FROM public.orders WHERE merchant_id = p_merchant_id), 0)
-- no status filter
```

**Verified:** one `delivered` (100.00), one `cancelled` (500.00), one `pending` (250.00) → the RPC returns **850.00**. Real revenue is 350.00. The range RPC inflates AOV the same way (returns 500.00 where it should be 100.00).

**This is an oversight, not a definition:** `get_avg_order_value` (069:20) *does* filter `status != 'cancelled'`. Two RPCs disagree about what revenue means.

**Impact:** every merchant revenue tile overstates. The error grows with cancellation rate.

**Fix:** add `AND status NOT IN ('cancelled')` (decide explicitly whether `pending` counts). Consider renaming the field `gross_order_value` until fixed.

**Tests:** `test_07_reporting.py::test_revenue_includes_cancelled_orders`, `::test_range_kpi_has_the_same_bug`, `::test_avg_order_value_rpc_does_filter_cancelled`

---

### BUG-10 — Moderation backlog silently inflates merchant ratings

**Where:** `get_merchant_review_summary` (093, patched by 104), `merchants.rating`

All three aggregate paths filter `is_visible = TRUE`, and 104 defaults new reviews to `is_visible = FALSE`.

**Verified:** one visible 5★ and one pending 1★ → summary returns `average_rating = 5.0, total_count = 1`. The 1★ is invisible everywhere, including in the dashboard's own rating tile.

**Impact:** the dashboard shows a flattering rating while Ops has an unreviewed complaint. Because 104 shipped *before* launch, the entire review corpus starts hidden, so **every merchant currently displays a rating computed from zero or few reviews**.

**Fix:** no schema change. Add a "N awaiting moderation" indicator next to every rating, and never display a rating whose `total_count` is below a threshold without a caveat.

**Tests:** `test_07_reporting.py::test_review_summary_ignores_pending_reviews`, `::test_merchant_rating_column_also_ignores_pending`

---

### BUG-11 — The merchant materialized view is missing 10 columns

**Where:** `merchants_with_open_status` (031:23–57)

Created with an **explicit 19-column list** and never recreated. Missing everything added afterwards:

| Column | Added by |
|---|---|
| `delivery_radius_km`, `estimated_prep_time_minutes` | 042 |
| `payout_frequency`, `payout_method`, `bank_account_holder`, `bank_account_number`, `bank_name`, `wallet_phone` | 085 |
| `approval_status`, `approval_note` | 103 |

**Verified:** column-by-column diff against `merchants`.

**Impact:** there is no `approval_status` in the matview, so the dashboard **cannot build the approval queue from it at all**. It also does not reflect the 098 FK change.

**Fix:** `DROP MATERIALIZED VIEW` + recreate with `SELECT m.*, <open status>` so it tracks the table automatically, then re-grant and refresh.

**Test:** `test_07_reporting.py::test_matview_is_missing_every_column_added_after_031`

---

## 2.5 🔵 Performance — only visible at scale

These four were invisible while the suite ran against an empty schema. A
sequential scan of nothing is free, so no index is ever exercised. They
appeared the moment ~200,000 rows were loaded.

**Assertion method.** Plan *text* is a weak signal — with a `LIMIT`,
PostgreSQL legitimately prefers a sequential scan and stops early. So each
test measures: record the cost, `CREATE INDEX` inside the test transaction,
record again, assert the gap. That proves the index is worth having *and*
validates the fix. All indexes created this way are rolled back.

FK cascades are RI triggers whose cost is reported outside the plan tree
(`Trigger for constraint ...: time=8.423 calls=1`), so cascade cost is read
from there.

---

### BUG-14 — `order_items.item_id` is unindexed

**Static proof:** `order_items` carries a pkey and `idx_order_items_order` on
`(order_id)`. **Nothing indexes `item_id`** — the FK column that both the
delete cascade and every "which orders contained this item" report must probe.

**Measured:** deleting one item fires three RI triggers. The `order_items` one
has no index, so it sequentially scans the table.

| | trigger cost |
|---|---|
| as shipped | **8.42 ms** |
| with `CREATE INDEX ON order_items(item_id)` | **3.24 ms** |

That is **2.6× on a single-row delete**, and it grows linearly with order
volume. At 124,840 order lines it is already 8ms; at a million it is ~70ms,
blocking the dashboard's item-delete action.

The read side is the same shape: an item's order history seq-scans the table,
and adding the index cuts buffers by more than 4×.

**Fix:** `CREATE INDEX idx_order_items_item ON public.order_items(item_id);`

**Compounding:** this is the index that would make BUG-08's `ON DELETE SET NULL`
fix cheap. Fixing 08 without this turns every hard delete into a table scan.

---

### BUG-15 — `merchants.approval_status` is unindexed

**Static proof:** no index on `merchants` mentions `approval_status`.

**Impact:** the approval queue is one of the two screens migration 103 exists
to serve, and it is also the screen BUG-13 makes urgent. Its filter column is
unindexed.

**Measured:** adding a partial index
`ON merchants(approval_status) WHERE approval_status = 'pending'` reduces the
queue query's buffer count.

**Honest limitation:** at 60 merchants the planner prefers a sequential scan
anyway, so this cannot be demonstrated by plan shape — only structurally and by
before/after buffers. Asserted that way deliberately, and recorded so nobody
later mistakes "no Seq Scan on merchants" for a goal.

**Fix:** the partial index above.

---

### BUG-16 — The moderation queue cannot use the existing `is_visible` index

Narrower than first assumed, and worth stating precisely: **an `is_visible`
index does exist**, added after 012 —

```sql
idx_reviews_merchant_visible
  ON reviews (merchant_id, created_at DESC) WHERE is_visible = true
```

Two consequences:

1. The predicate `is_visible = false` is **outside the partial index** by construction.
2. Even `is_visible = true` alone cannot use it, because `merchant_id` is the leading column.

So it serves exactly one query shape: *"visible reviews for merchant X"*.

**Unindexed — the query Ops actually runs:**

| Query | Plan | Verdict |
|---|---|---|
| `WHERE is_visible = FALSE ORDER BY created_at LIMIT 50` (moderation queue) | Seq Scan on reviews | 🟠 **real** — adding a partial index improves it |
| `SELECT count(*) WHERE is_visible = FALSE` (badge count) | Seq Scan, **0.75 ms** | ⚪ **not a bug** — see below |

I initially claimed the badge count was a bug too. It is not, and testing said
so: PostgreSQL measures the sequential scan at 0.75 ms and **still prefers it
even when a matching partial index exists**, because counting N narrow rows in
one pass beats walking N index entries. The index only starts paying above
roughly 10⁵ hidden reviews. Asserted as an explicit non-bug with that threshold
recorded, so it gets revisited if the backlog ever grows.

**Impact of the real part:** compounded by 104's design. New reviews default to
hidden, so the backlog *is* the normal state, and the queue query runs
constantly — each page costing a full scan of the reviews table.

**Fix:** `CREATE INDEX idx_reviews_pending ON reviews(created_at) WHERE is_visible = false;`

---

### BUG-17 — KPI RPCs recompute the same aggregates

**`get_merchant_kpis_range` (091)** contains six subqueries over identical rows:
`COUNT` and `SUM` for the range, then both **again** inside the AOV `CASE`
branch. **`get_merchant_kpis` (066)** does the same with two.

PostgreSQL inlines these `LANGUAGE sql` functions and constant-folds them when
arguments are literals — so a literal-argument call collapses to a single
aggregate pass and the duplication is invisible. **A parameterised call, which
is exactly how PostgREST invokes them, evaluates the repeated work for real.**

**Measured:** the RPC costs more buffers than the same numbers computed in one
aggregate pass, on a merchant with a real order history.

**Fix:** rewrite both bodies as a single `count(*) / sum(total)` aggregate,
dividing once in the outer `SELECT`.

---

## 3. 🟡 Data quality

### BUG-02 — Overnight hours are unrepresentable

`22:00 → 02:00` matches nothing after midnight, because the predicate is `now >= open_time AND now < close_time` and `01:00 < 02:00` is true but `01:00 >= 22:00` is false. **Verified.** The seed data already contains `close_time = '01:00'` (seed.sql:125), so those rows are broken as shipped.

**Fix:** add `is_overnight BOOLEAN`, or split each day into two shift rows. Note this is **not** needed for 24-hour pharmacies — see §4.

### BUG-04 — Option cardinality is unconstrained

`min_selections = 5` with `max_selections = 2` is accepted. `is_required = TRUE` with `min_selections = 0` is accepted. `is_required = FALSE` with `min_selections = 3` is accepted. **All three verified.** No CHECK relates `min_selections` to `max_selections`.

**Fix:** `CHECK (min_selections <= max_selections OR max_selections IS NULL)` and `CHECK (NOT is_required OR min_selections >= 1)`.

### BUG-07 — A sold-out choice can be the pre-selected default

`is_default = TRUE` with `is_available = FALSE` is accepted. **Verified.** The UI would pre-select something the customer cannot order.

**Fix:** partial unique index plus a trigger, or a `CHECK` cross-table guard is impossible — enforce in `place_order_with_items`.

### BUG-12 — Option snapshots carry no `choice_id`

`order_items.selected_options` stores `{option_name_en, choice_name_en, price_modifier}` — **verified by enumerating the JSONB keys**. Names, not ids.

**Impact:** "which option configuration sells most" is only answerable by string-matching names. Rename a choice and history silently rewrites itself.

**Fix:** add `option_id` and `choice_id` to the JSONB written by `place_order_with_items`.

---

## 4. ⚪ Claims in my first report that were wrong

Testing overturned these. Recording them because two were in your favour.

| My original claim | Reality | Evidence |
|---|---|---|
| "A 24-hour pharmacy is **not** representable; needs an overnight flag" | **Wrong.** `00:00`–`24:00` works: Postgres `TIME` accepts `24:00:00` and `now < 24:00` is always true | `test_01::test_24h_merchant_is_representable` |
| "Migration 098: `refresh_merchant_open_status` cannot run inside a transaction, so the deviation is necessary" | **Wrong.** It completes normally inside an explicit transaction on PG18, populated and empty. 098's comment rules out a valid approach for no reason | `test_07::test_refresh_function_does_work_inside_a_transaction` |
| "`merchants` has 30 columns" | **Wrong — 33.** I under-counted the payout block from 085 | `test_04::test_merchants_column_count_and_names` |
| "`order_items.item_id` has an index" *(implied by the absence of a complaint)* | **Wrong — it does not.** The cascade and order-history lookups both seq-scan | `test_08::test_order_items_has_no_index_on_item_id` |

Also corrected: `bank_account_number` was never the only plaintext financial
column — `bank_account_holder`, `bank_name` and `wallet_phone` sit alongside it.
All four are now slated for removal per your decision, so this is moot.

**Version caveat:** the refresh finding was verified on PG18 only. Supabase runs
PG15/17. Re-check before relying on it.

**Two more claims were softened rather than overturned:**

- *"The 091 plan reads orders three times"* — true structurally, but PostgreSQL
  folds it to a single pass when arguments are literals. It only bites on
  parameterised calls. Restated as BUG-17 with that caveat.
- *"`merchants` index coverage can't be verified at 60 rows"* — confirmed, and
  now asserted explicitly so it is not mistaken for a passing index test.

**One claim was invented by the test and then killed by it:**

- *"The moderation badge count needs an index"* — I wrote this test expecting it
  to fail, and it failed. But the failure showed the planner is **right**: a
  count over 3,000 hidden rows costs 0.75 ms via sequential scan and PostgreSQL
  prefers that even when a matching partial index exists. No bug. The test now
  asserts the planner's choice plus a size threshold, so the question is
  revisited if the backlog ever grows past ~10⁵ rows.

---

## 5. 🔵 Requirement gaps (not bugs — features that do not exist)

### REQ-01 — No branches / chains

**Verified absent:** no table matching `branch`, and no `parent_merchant_id` / `brand_id` / `chain_id` on `merchants`.

Today a 2-branch chain = 2 independent merchant rows with 2 separate menus. They can share a `phone` (verified), but **no column expresses "same brand"**, so per-brand reporting is impossible and menu edits must be repeated per branch.

**Open question for you before I design this:** should branches share one menu, or have independent menus? The answer changes the schema substantially — shared menus means `item_options`/`item_option_choices` need a branch scope; independent menus means the current schema works and you only need a parent link plus a reporting rollup.

### REQ-02 — No item discounts ✅ FIXED by migration 119

**Was verified absent:** `items` had 14 columns, exactly one of which was a
price. No `discount_price`, `compare_at_price` or `is_discounted`. Across
`items` + `item_option_choices` there were exactly **two** price columns, so
combined with BUG-06 there was no way to express a discount anywhere in the
catalog — not on an item, not on an option. Only `promo_codes` (order-level,
011) existed, and the customer had to know to apply it.

**Now:** `items.discount_price`, constrained `0 <= discount_price <= price`,
effective price `COALESCE(discount_price, price)`. Migration 119. Full detail in
§5.9.

---

## 6. Test-suite coverage map

| File | Tests | Covers |
|---|---|---|
| `test_01_operating_hours.py` | 8 | BUG-01, BUG-02, 24h-is-fine |
| `test_02_catalog_integrity.py` | 5 | BUG-03, cascade behaviour, menu index |
| `test_03_options.py` | 11 | BUG-04, BUG-05, BUG-06, BUG-07 |
| `test_04_merchants.py` | 13 | column inventory, category FK, approval, city/area, REQ-01, discount shape |
| `test_05_data_loss.py` | 5 | BUG-08 |
| `test_06_rls.py` | 25 | BUG-13, read/write policy surface, moderation gate |
| `test_07_reporting.py` | 12 | BUG-09, BUG-10, BUG-11, BUG-12, DOC-01 |
| `test_08_scale.py` | 20 | BUG-14, BUG-15, BUG-16, BUG-17 + verified-good index paths |
| `test_09_discounts.py` | 23 | REQ-02, BUG-19, BUG-18 half, guard crash, order-path gates |

**Seeded volumes** (`local/seed_data.py`, ~200k rows):

```
orders               50,000      order_items        124,840
customers             8,000      addresses            8,000
reviews               6,000      favorite_items       2,400
items                 2,400      item_options         1,815
discounted_items      2,220      item_option_choices  6,343
categories               480      merchants               60
operating_hours        420
```

`merchants` is deliberately small — see BUG-15's honest limitation. The
order-side tables carry realistic cardinality, which is where the four
performance bugs live. `discounted_items` is ~12% of the catalog: high enough to
exercise `idx_items_discounted` in a selective filter, low enough that the
planner correctly still prefers a scan for the blanket filter.

**Verified-good behaviour is pinned too**, so a future migration that breaks it
fails loudly: public catalog reads, single-select groups, cascade on merchant
delete, `00:00`–`24:00` windows, unique `(merchant_id, day_of_week)`, `other` as
the onboarding escape hatch, all 8 launch categories active, the menu query's
composite index, `idx_orders_active`, the chip-row view, per-merchant visible
reviews, and the payout→orders lookup.

**Test-isolation rules learned the hard way**, both now enforced:

- Tests that count rows must scope to their own `[DBX-…]` alias. Global counts
  break the moment seed data exists — this caused 4 false failures.
- psycopg3's automatic prepared statements cache generic plans, which ignore an
  index created mid-test. `prepare_threshold=None` is set on the connection;
  without it the scale suite is order-dependent.

---

## 7. What shipped

Fix order below was chosen so each migration is independently checkable against
the existing tests, and so `108` lands before `110`.

| Migration | Fixes | Note |
|---|---|---|
| `107_fix_operating_hours_day_of_week` | BUG-01 | Rewrites existing rows. `RAISE NOTICE` reports how many Sunday rows moved |
| `108_index_order_items_item` | BUG-14 | **Must precede 110** — 110 makes the FK probe `item_id`, which is what this indexes |
| `109_merchants_approval_rls` | BUG-13 | Also patches the matview's `WHERE` so the feed stops leaking immediately |
| `110_menu_soft_delete` | BUG-08 | Widest blast radius. Sets `deleted_at`; read sites listed in-file |
| `111_option_constraints` | BUG-04/05/06/07 | Pre-flight `DO` block raises with a count if existing data violates a new constraint |
| `112_catalog_integrity` | BUG-03 | Pre-flight raises if any item is already mis-filed; refuses to guess |
| `113_rebuild_merchant_matview` | BUG-11 | `SELECT m.*` so the bug cannot recur |
| `114_kpi_status_filter` | BUG-09, BUG-17 | Pure function change, no data change |
| `115_drop_bank_columns` | your decision | Drops 3 bank columns, keeps `wallet_phone` |
| `116_dashboard_indexes` | BUG-15, BUG-16 | Two partial indexes, no data change |
| `117_option_snapshot_ids` | BUG-12 | One expression changed inside `place_order_with_items` |
| `118_overnight_hours` | BUG-02 | Needs a dashboard toggle before it is usable |
| `119_item_discounts` | **REQ-02**, BUG-19, BUG-18 (half), guard crash, missing defaults | Adds `items.discount_price`, `order_items.original_price`, `idx_items_discounted`, and makes checkout server-priced |

### 5.9 REQ-02 — item discounts, delivered

`119_item_discounts.sql`. The gap it closes: across `items` and
`item_option_choices` there were exactly **two** price columns, so a
"was 100, now 80" item was impossible. Option-level reductions arrived with 111;
item-level now follows.

**Schema:**

| Object | Purpose |
|---|---|
| `items.discount_price` | nullable; effective price is `COALESCE(discount_price, price)` |
| `CHECK (0 <= discount_price <= price)` | cannot be negative, cannot exceed the list price |
| `order_items.original_price` | pre-discount price, so ending a promotion doesn't rewrite history |
| `idx_items_discounted` | partial, holds only discounted rows |

**Design choice — one column, not a discount table.** An item has at most one
active reduction, it applies to everyone, and there is no scheduling
requirement in the brief. A separate `item_discounts` table would buy scheduled
or segmented pricing — neither requested — at the cost of a join on the hottest
query in the app.

**Why it had to touch `place_order_with_items`.** The function took `item_price`
from the request. A discount living only in the catalog while checkout trusts
the client means the dashboard shows a discount that checkout silently ignores.
Resolving price server-side is the minimum for a discount to mean anything.

**Coverage:** `test_09_discounts.py`, 23 tests — the column, its constraint
re-evaluated on every `UPDATE`, the effective-price expression, server-side
application, client-price override refused, subtotal server-derived, header
reconciling with lines, history surviving the promotion ending, stacking with
option modifiers, modifier-vs-discounted-base bound, soft-delete and
availability and approval gates, and the service-role guard.

### 5.10 Two migrations deliberately stop short

Both are called out in-file rather than hidden, because a half-applied change
that reads as complete is worse than an obvious gap.

**110 — soft delete.** The columns exist; the **read sites do not yet filter
them**. Listed in the migration header:

```
supabase/functions/get-merchant-feed/index.ts       categories, items
supabase/functions/place-order/index.ts             items
supabase/functions/search-catalog/index.ts          items
supabase/migrations/114 (done)                      item_count, category_count
apps/admin: menu builder, item list, merchant detail
```

Safe in the meantime: soft-deleted rows stay **visible**, which is the pre-110
behaviour. The dangerous direction — rows vanishing where a reader does not
expect it — cannot happen until the readers change.

**118 — overnight hours.** `is_overnight` exists and `is_merchant_open()` plus
the matview honour it, but **no UI sets it**. Until the merchant hours editor
exposes a "closes next day" toggle it is settable only by direct SQL:

```sql
UPDATE operating_hours SET is_overnight = true
 WHERE merchant_id = '<uuid>' AND day_of_week = 5;
```

A merchant open Fri 22:00 → Sat 02:00 is stored on **Friday's** row, because
that is when the window opens. Labelling it Saturday is the natural mistake.

---

## 5. Bugs the suite found in my own fixes

Recorded because they are the strongest evidence the harness works.

### 5.1 Migration 114 — `cancelled_count` was always zero

My first version put `AND status <> 'cancelled'` in the aggregate's `WHERE`, and
also computed `count(*) FILTER (WHERE status = 'cancelled')` in the same
`SELECT`. The filter removed the rows before the `FILTER` could count them.

`test_revenue_excludes_cancelled_orders` asserts `cancelled_count == 1` and
failed. Fixed by dropping the `WHERE` and making `order_count` and `revenue`
conditional aggregates instead — one pass, correct counts.

### 5.2 Migration 108 — a redundant index

I added both `(item_id)` and `(item_id, order_id)`. The composite leads with
`item_id`, so it already served every access path; the planner preferred it
regardless. `test_dropping_the_item_id_index_reintroduces_the_scan` dropped only
the narrow index and got a `Bitmap Heap Scan` off the composite instead of the
expected `Seq Scan` — proving the narrow index was dead weight costing write
amplification on every `order_items` insert. Deleted it.

### 5.3 Migration 117 — I nearly broke `place_order_with_items`

My first draft re-created the function with signature `(jsonb, uuid)`. The real
signature is `(JSONB, JSONB)`, `SECURITY DEFINER`, service-role only — and its
368-line body carries promo funding and payout computation (080), atomic promo
usage enforcement (045), `scheduled_time` (049), customer IP tracking and
`check_promo_fraud` (075).

Re-authoring it from a partial read would have created a **second, wrong
overload** and left the real function unfixed, with promo and fraud logic
silently bypassed. Rewritten as a standalone `enrich_selected_options()` helper
plus **one changed expression**. Everything else in that function is byte-for-byte
080.

**Lesson recorded in the migration header:** do not re-author a function that has
been revised six times from a partial read.

### 5.4 BUG-19 — `place_order_with_items` had never executed 🔴

**The most serious finding in this report, and it was in the checkout path the whole time.**

The function is declared:

```sql
RETURNS TABLE(id UUID, order_number TEXT, created_at TIMESTAMPTZ)
```

In PL/pgSQL an `OUT` parameter is a **variable**. So the bare identifier `id`
inside the body resolves ambiguously against any column also named `id`. The
function body contained six such references:

| Statement | Ambiguous against |
|---|---|
| `WHERE id = v_customer_id` | `profiles.id` |
| `WHERE id = v_merchant_id AND is_active = TRUE …` | `merchants.id` |
| `WHERE id = v_item_id` | `items.id` |
| `(SELECT name_ar FROM public.items WHERE id = v_item_id)` ×2 | `items.id` |
| `WHERE id = v_promo_code_id` (SELECT … FOR UPDATE) | `promo_codes.id` |
| `RETURNING id, order_number, created_at` | `orders.id` |

Every call therefore failed with:

```
ERROR: column reference "id" is ambiguous
DETAIL: It could refer to either a PL/pgSQL variable or a table column.
```

**This function has never run, on any data, in any environment, since migration
026.** It is not a regression from anything in this report — the ambiguity was
introduced when the `RETURNS TABLE(id …)` signature was written and persisted
through six revisions (026 → 036 → 045 → 049 → 075 → 080 → 117).

**Why it survived:** nothing had ever called it. The function is service-role
only, and the suite exercised the catalog, RLS and reporting paths but never the
write path. 88 correctness tests passed while checkout was unreachable.

**Fixed** by qualifying all six references with their table name.

**What this means for you:** treat the first real order as a production smoke
test. The schema is verified; the *checkout flow* is now reachable for the first
time and has not been observed working end-to-end against real data.

### 5.5 The service-role guard crashed instead of authorising

Pre-existing since 080:

```sql
IF COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '') <> 'service_role'
```

When the GUC is unset, `current_setting(…, true)` returns NULL, `COALESCE`
selects the empty string, and `''::json` raises:

```
invalid input syntax for type json
DETAIL: The input string ended unexpectedly.
```

So an unauthorised caller received a JSON parse error instead of
`Unauthorized`. Fixed with `NULLIF(current_setting(…), '')::json`.

### 5.6 `payment_method` / `payment_status` had no defaults

Both were passed straight through with no `COALESCE`, while every other
optional field in the same INSERT is defaulted. A payload omitting either hit
the `orders` NOT NULL constraint instead of using the column defaults. Fixed.

### 5.7 BUG-18, and what 119 did about it

Found while editing 117: `place_order_with_items` trusts client-supplied values.
Migration **119** closes the item-price half, because a discount the client can
override is not a discount.

**Now server-derived:**

| Field | Source |
|---|---|
| `order_items.item_price` | `COALESCE(discount_price, price)` from the row |
| `order_items.original_price` | `items.price` from the row |
| `order_items.total_price` | computed from those plus catalog modifiers |
| `orders.subtotal` | sum of the computed lines |
| `orders.total` | recomputed from the server subtotal |
| `orders.merchant_payout` | commission on the server subtotal |

**Still client-supplied — deliberately:**

| Field | Risk |
|---|---|
| `orders.delivery_fee` | a client could set this to 0 |
| `orders.discount_amount` | a client could set this above the subtotal |

Left open because changing them alters fee and promo arithmetic for every order,
which needs product sign-off. `orders.total >= 0` is already a CHECK, so an
oversized discount surfaces as a constraint violation rather than a negative
total — but add an explicit guard if that matters before launch.

**Verify the `place-order` Edge Function** to confirm it no longer sends prices
the function will now ignore.

### 5.8 Two test bugs of my own

- I asserted the discount filter shouldn't seq-scan. At 12% discounted, scanning
  all 2,400 rows costs fewer buffers than an index scan — **the planner is
  right**, same lesson as the review badge count in §2.5. Rewritten to assert the
  index structurally, plus one test where the index genuinely wins.
- A modifier test sent `-95.00` against a `100.00` base, which leaves `5.00`, not
  a negative line. My arithmetic, not the schema.

---

**Not yet migration-worthy** — BUG-10 is a dashboard display concern, and DOC-01 is a comment correction.

REQ-01 and REQ-02 need your answers before they can be specified.

---

## 8. Findings I could not test

| Area | Why |
|---|---|
| PostGIS distance maths | Vanilla PG18 has no PostGIS; shimmed with haversine. Driver-location and `get_merchant_feed` distance are **untested against real PostGIS** |
| `pg_cron` firing | Shimmed as a recorder that never fires. Scheduled jobs are unverified |
| Vault / Paymob secrets | Shimmed as a settings table. `027` encryption is unverified end-to-end |
| RLS under real Supabase roles | Tested with local `anon`/`authenticated` roles plus Supabase's default grants. Production has `service_role` with `BYPASSRLS`; that path is untested |
| **`merchants` index behaviour** | Only 60 rows, so the planner prefers sequential scans regardless of indexing. BUG-15 is proven structurally and by buffer deltas, not plan shape. Raise `MERCHANTS` in `seed_data.py` to test this properly |
| **Production-scale skew** | Order volume (50k) and catalog (2.4k items) are launch-realistic, but a mature marketplace is 10–100× larger. The four performance bugs are all *linear*, so they will worsen proportionally — but no index was verified at 10× |
| Connection pooling | Tests use one direct connection. PgBouncer in transaction mode can change plan-cache behaviour for the KPI RPCs (BUG-17 is sensitive to exactly this) |

Each shim is marked in `local/bootstrap.sql` and none is ever deployed.