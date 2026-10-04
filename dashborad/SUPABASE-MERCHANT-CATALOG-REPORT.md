# Supabase Report — Merchants, Categories, Items & Dashboard Readiness

**Scope:** `supabase/` only (106 migrations, `seed.sql`, 18 Edge Functions, storage, RLS).
**Question answered:** *How do merchants work, and what does merchant → categories → items → item data (price, size, etc.) actually look like in the database?*
**Date:** 2026-10-03

> ### ⚠️ Read this first — the findings in this report are superseded
>
> Every claim below was checked against a real database by **133 automated
> assertions** running on local PostgreSQL 18 with ~200,000 rows of generated
> volume.
>
> **Fix migrations 107–119 are written and verified.** All 118 migrations replay
> cleanly; the suite is green at **131 passed, 2 skipped**.
>
> **Four findings in this report were wrong** (column count, 24-hour pharmacies,
> `refresh_merchant_open_status` inside a transaction, and an implied claim that
> `order_items.item_id` was indexed), **one serious bug was missed** (unapproved
> merchants are publicly visible), **four bugs only appear at scale**, and
> **the checkout function `place_order_with_items` had never successfully
> executed in any environment since migration 026.**
>
> See **`dashborad/test/BUG-REPORT.md`** for the verified truth,
> **§16 Product decisions** for what was decided, and **§16.5** for what shipped.
>
> This document remains the structural reference — the catalog hierarchy,
> RLS model, and RPC catalogue are accurate. §13 is superseded by the bug report.

---

## 0. TL;DR — Answers to your questions

| Your assumption | Reality in this DB |
|---|---|
| merchant → categories → items | ✅ Correct. Exactly that hierarchy. |
| items hold price, size, etc. | ⚠️ **Half correct.** `items` holds **price** only. **Size is NOT on `items`** — size lives in a *separate option-group chain*: `items → item_options → item_option_choices`. |
| admins manage merchants | ✅ Correct — and **only** admins do. There is **no merchant login at all** in the database. |

**The single most important structural fact:**

```
merchant (1) ──< category (1) ──< item (1) ──< item_option (N) ──< item_option_choice (N)
   30 cols          8 cols            14 cols          8 cols              11 cols
```

An item's "size" (Small / Medium / Large) is **not a column on `items`** — it is an `item_options` row named "Size" with three `item_option_choices` children carrying `price_modifier` 0.00 / 10.00 / 20.00. This is the classic restaurant-menu modelling pattern and it is correctly implemented.

---

## 1. The Catalog Hierarchy — Full Reference

### 1.1 Relationship diagram

```
                    ┌──────────────────────────────┐
                    │       merchants              │  (005 + 042 + 085 + 103)
                    │  30 columns                  │
                    └───────────────┬──────────────┘
                                    │ merchant_id (FK, ON DELETE CASCADE)
             ┌──────────────────────┼──────────────────────┬────────────────────┐
             ▼                      ▼                      ▼                    ▼
    ┌─────────────────┐   ┌──────────────────┐   ┌───────────────┐   ┌────────────────────┐
    │  categories     │   │ operating_hours  │   │    orders     │   │ merchant_payouts   │
    │  menu sections  │   │  7 rows/merchant │   │  + snapshots  │   │  finance           │
    │  (007)          │   │  (006)           │   │  (008)        │   │  (085)             │
    └────────┬────────┘   └──────────────────┘   └───────┬───────┘   └────────────────────┘
             │ category_id (FK, CASCADE)                  │ order_id
             ▼                                           ▼
    ┌─────────────────┐                          ┌──────────────────┐
    │      items      │                          │   order_items    │
    │  (007)          │──────────────────────────│  PRICE SNAPSHOT  │
    │  price, image,  │  item_id (FK, CASCADE)   │  names frozen    │
    │  availability   │                          │  (008)           │
    └────────┬────────┘                          └──────────────────┘
             │ item_id (FK, ON DELETE CASCADE)
             ▼
    ┌──────────────────────┐
    │    item_options      │   ← the "SIZE" lives here (a group)
    │  is_required         │
    │  min/max_selections  │
    └──────────┬───────────┘
               │ option_id (FK, ON DELETE CASCADE)
               ▼
    ┌────────────────────────────┐
    │   item_option_choices      │  ← "Small +0.00", "Large +20.00"
    │  price_modifier, calories  │
    └────────────────────────────┘
```

### 1.2 The "size" answer, concretely

From `supabase/seed.sql:161-173` — real seeded data:

```sql
INSERT INTO public.item_options (id, item_id, name_ar, name_en, is_required, max_selections, min_selections, sort_order) VALUES
  ('...0001', 'd...0001', 'الحجم',  'Size',   TRUE,  1,    1,    1),   -- REQUIRED, single-select
  ('...0002', 'd...0001', 'إضافات', 'Extras', FALSE, NULL, 0,    2);   -- OPTIONAL, unlimited

INSERT INTO public.item_option_choices (option_id, name_ar, name_en, price_modifier, is_default, sort_order) VALUES
  ('...0001', 'صغير',  'Small',        0.00, TRUE,  1),   -- pre-selected
  ('...0001', 'وسط',   'Medium',      10.00, FALSE, 2),
  ('...0001', 'كبير',  'Large',       20.00, FALSE, 3),
  ('...0002', 'صلصة إضافية', 'Extra Sauce',    5.00, FALSE, 1),
  ('...0002', 'بصل مقرمش',   'Crispy Onions', 5.00, FALSE, 2),
  ('...0002', 'دقة',         'Dakka',          3.00, FALSE, 3);
```

**Pricing rule** (baked into `order_items.total_price`): `(items.price + Σ price_modifier) × quantity`.

---

## 2. `merchants` — Effective Schema (30 columns)

Built across **4 migrations**. This is the post-replay truth, not just `005`.

### 2.1 Identity & content

| Column | Type | Null | Default | Source | Notes |
|---|---|---|---|---|---|
| `id` | UUID | NO | `gen_random_uuid()` | 005 | PK |
| `name_ar` | TEXT | NO | — | 005 | Arabic name |
| `name_en` | TEXT | NO | — | 005 | English name |
| `category` | TEXT | NO | — | 005 → **098** | **Was** `CHECK IN ('restaurant','pharmacy')`. **Now** `FK → merchant_categories(code)` |
| `logo_url` | TEXT | YES | — | 005 | → storage bucket `merchant-assets` |
| `cover_url` | TEXT | YES | — | 005 | → storage bucket `merchant-assets` |
| `description_ar` | TEXT | YES | — | 005 | |
| `description_en` | TEXT | YES | — | 005 | |

### 2.2 Location

| Column | Type | Null | Default | Source | Notes |
|---|---|---|---|---|---|
| `address` | TEXT | NO | — | 005 | Free text, bilingual not split |
| `lat` | NUMERIC(9,6) | NO | — | 005 | |
| `lng` | NUMERIC(9,6) | NO | — | 005 | |
| `city` | TEXT | NO | — | 005 | e.g. `'Cairo'` — English, not an FK |
| `area` | TEXT | YES | — | 005 | e.g. `'Dokki'` — free text, not an FK |

### 2.3 Status & lifecycle

| Column | Type | Null | Default | Source | Notes |
|---|---|---|---|---|---|
| `is_active` | BOOLEAN | NO | `TRUE` | 005 | **Runtime kill-switch.** Hides merchant from feed |
| `approval_status` | TEXT | NO | `'approved'` | **103** | `CHECK IN ('pending','approved','rejected')` |
| `approval_note` | TEXT | YES | — | **103** | Ops rejection reason |
| `phone` | TEXT | NO | — | 005 | ⚠️ No email column anywhere |

> **Two independent state axes.** `approval_status` = onboarding gate (new place → Ops reviews). `is_active` = runtime kill-switch (suspend for abuse). A rejected merchant can still be `is_active = true`. Your dashboard UI must show **both** as separate controls.

### 2.4 Ratings (trigger-maintained — do not write)

| Column | Type | Null | Default | Source | Notes |
|---|---|---|---|---|---|
| `rating` | NUMERIC(2,1) | NO | `0.0` | 005 | `CHECK 0..5`. Maintained by `trigger_update_merchant_rating()` |
| `rating_count` | INTEGER | NO | `0` | 005 | Same trigger |

### 2.5 Ordering & delivery config

| Column | Type | Null | Default | Source | Notes |
|---|---|---|---|---|---|
| `min_order_amount` | NUMERIC(10,2) | NO | `0.00` | 005 | |
| `estimated_delivery_minutes` | INTEGER | NO | `30` | 005 | **Total** ETA incl. transit |
| `estimated_prep_time_minutes` | INTEGER | NO | `30` | **042** | **Kitchen-only** prep time |
| `delivery_fee_override` | NUMERIC(10,2) | YES | `NULL` | 005 | NULL → use `platform_config` calc |
| `delivery_radius_km` | NUMERIC(5,2) | NO | `10.00` | **042** | `CHECK > 0`. Orders beyond rejected |
| `commission_pct` | NUMERIC(5,2) | YES | `NULL` | 005 | NULL → `platform_config.default_commission_pct` (15.00) |

> ⚠️ **Two overlapping ETA columns** (`estimated_delivery_minutes` vs `estimated_prep_time_minutes`) with no documented invariant on their relationship. Dashboard form should enforce `prep ≤ delivery`.

### 2.6 Payout config (added by 085)

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| `payout_frequency` | TEXT | NO | `'weekly'` | `CHECK IN ('daily','weekly','monthly')` |
| `payout_method` | TEXT | NO | `'bank_transfer'` | `CHECK IN ('bank_transfer','wallet','cash','instapay')` |
| `bank_account_holder` | TEXT | YES | — | |
| `bank_account_number` | TEXT | YES | — | 🔴 **PLAINTEXT.** Migration comment says "TODO: encrypt at rest" |
| `bank_name` | TEXT | YES | — | |
| `wallet_phone` | TEXT | YES | — | |

> 🔴 **Security finding.** `merchants.bank_account_number` is stored unencrypted. The repo already has a working encryption pattern — `027_add_national_id_encryption.sql` (`encrypt_national_id` / `decrypt_national_id` / `mask_national_id`). Apply it here.

### 2.7 Timestamps

`created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`, `updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()` (auto via `set_merchants_updated_at` trigger).

### 2.8 What `merchants` does NOT have

| Missing | Impact on dashboard |
|---|---|
| **Merchant owner / user link** | 🔴 See §6 — no merchant login exists |
| Email contact | Onboarding/verification by email impossible |
| Branches / multi-location | One row = one physical location. Chain = N rows |
| Commercial registry / tax ID | No legal-entity tracking |
| `ordering_enabled` | Cannot pause ordering while staying visible |
| Manual open/close override | Only `operating_hours` + `is_active` control visibility |
| Item/category counts | No denormalized counter — must aggregate (§7.2) |

---

## 3. `categories` — 8 columns (007)

Menu sections per merchant. **NOT** the same thing as `merchants.category`.

```sql
CREATE TABLE categories (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id   UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  name_ar       TEXT NOT NULL,
  name_en       TEXT NOT NULL,
  sort_order    INTEGER NOT NULL DEFAULT 0,   -- lower = appears first
  icon          TEXT,                          -- optional emoji / icon key
  is_available  BOOLEAN NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_categories_merchant ON categories(merchant_id, sort_order);
```

> ⚠️ **Naming collision — the single biggest readability trap in this schema.** `merchants.category` = *what kind of business* (restaurant/pharmacy/grocery…). `categories` = *a section of that merchant's menu* (Burgers/Sides/Drinks). Same word, two meanings. In dashboard code, always name variables `merchant_category_code` vs `menu_category`.

### 🔴 Data-integrity gap

`items` has **both** `merchant_id` and `category_id`, with **no constraint tying them together**. Nothing stops this:

```sql
-- category belongs to merchant A, item claims merchant B
INSERT INTO items (merchant_id, category_id, ...) VALUES ('merchant-B', 'category-of-A', ...);
```

`idx_items_merchant_category` is a plain index, not a composite FK. **Dashboard must validate this in application code** on every item create/update: `category.merchant_id === item.merchant_id`. Candidate fix for a future migration: drop `items.merchant_id` and derive it, or add a composite FK `(category_id, merchant_id) → categories(id, merchant_id)` behind a `UNIQUE(id, merchant_id)`.

---

## 4. `items` — 14 columns (007)

```sql
CREATE TABLE items (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id      UUID NOT NULL REFERENCES merchants(id)    ON DELETE CASCADE,
  category_id      UUID NOT NULL REFERENCES categories(id)    ON DELETE CASCADE,

  name_ar          TEXT NOT NULL,
  name_en          TEXT NOT NULL,
  description_ar   TEXT,                     -- optional
  description_en   TEXT,                     -- optional

  price            NUMERIC(10,2) NOT NULL CHECK (price >= 0),   -- EGP, base price
  image_url        TEXT,

  is_available     BOOLEAN NOT NULL DEFAULT TRUE,  -- the "86'd / sold out" flag
  sort_order       INTEGER NOT NULL DEFAULT 0,
  popularity_score INTEGER NOT NULL DEFAULT 0,     -- for recommendations

  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### Indexes

| Index | Definition | Serves |
|---|---|---|
| `idx_items_merchant_category` | `(merchant_id, category_id, is_available)` | **Main menu query** |
| `idx_items_merchant` | `(merchant_id) WHERE is_available = TRUE` | Merchant-wide search |
| `idx_items_name_ar_trgm` | GIN `normalize_search_text(name_ar) gin_trgm_ops` | Fuzzy search (095) |
| `idx_items_name_en_trgm` | GIN `normalize_search_text(name_en) gin_trgm_ops` | Fuzzy search |
| `idx_items_desc_ar_trgm` | GIN on `description_ar` | Description search |
| `idx_items_desc_en_trgm` | GIN on `description_en` | Description search |

### 🔴 No stock, no discount, no dietary/tag metadata

`items` has **no** `stock_quantity`, `discount_price`, `compare_at_price`, `is_featured`, `is_spicy`, `is_vegetarian`, `calories`, `prep_minutes`, `allergens`. If the dashboard needs any of these, that's a migration, not a form field.

> ⚠️ **`calories` exists on `item_option_choices` but NOT on `items`.** Asymmetric — you can log calories for "Large Koshari" but not for the base item. Likely an oversight in 007.

---

## 5. `item_options` & `item_option_choices` — The Size/Modifier Engine

### 5.1 `item_options` (8 cols) — an option *group*

```sql
CREATE TABLE item_options (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id         UUID NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  name_ar         TEXT NOT NULL,
  name_en         TEXT NOT NULL,
  is_required     BOOLEAN NOT NULL DEFAULT FALSE,
  max_selections  INTEGER CHECK (max_selections IS NULL OR max_selections >= 1),
  min_selections  INTEGER NOT NULL DEFAULT 0 CHECK (min_selections >= 0),
  sort_order      INTEGER NOT NULL DEFAULT 0,
  created_at / updated_at TIMESTAMPTZ
);
CREATE INDEX idx_item_options_item ON item_options(item_id, sort_order);
```

**Selection semantics:**

| `max_selections` | Meaning |
|---|---|
| `1` | **Single-select** (radio) — the Size pattern |
| `> 1` | Multi-select with a cap |
| `NULL` | **Unlimited** multi-select — the Extras pattern |

**Validation rules the dashboard must enforce:**
1. `min_selections <= max_selections` — ❌ **not enforced by any CHECK constraint.**
2. `is_required = TRUE` with `min_selections = 0` — contradictory, allowed.
3. `is_required = FALSE` with `min_selections > 0` — contradictory, allowed.
4. A required group with **zero** available choices → the item is unorderable. Dashboard should warn.
5. `max_selections` greater than the number of choices — harmless but sloppy.

### 5.2 `item_option_choices` (11 cols) — an option *value*

```sql
CREATE TABLE item_option_choices (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  option_id      UUID NOT NULL REFERENCES item_options(id) ON DELETE CASCADE,
  name_ar        TEXT NOT NULL,
  name_en        TEXT NOT NULL,
  price_modifier NUMERIC(10,2) NOT NULL DEFAULT 0.00 CHECK (price_modifier >= 0),
  is_default     BOOLEAN NOT NULL DEFAULT FALSE,
  is_available   BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order     INTEGER NOT NULL DEFAULT 0,
  calories       INTEGER,          -- nullable, no CHECK (negatives allowed)
  created_at / updated_at TIMESTAMPTZ
);
CREATE INDEX idx_item_option_choices_option ON item_option_choices(option_id, sort_order);
```

> 🔴 **`price_modifier` has `CHECK (price_modifier >= 0)` — discounts on options are impossible.** A "−15 EGP" option (e.g. a promo size) will be rejected by Postgres. To support price *reductions* you must drop that CHECK.

> ⚠️ **`is_default` has no uniqueness constraint.** Nothing stops every choice in a group being `is_default = TRUE`. For a single-select group the UI can't decide what to pre-select. Dashboard should force exactly-one-default for `max_selections = 1` groups.

> ⚠️ **`is_default = TRUE` on an `is_available = FALSE` choice** is possible. Pre-selecting a sold-out option is a real bug class here.

### 5.3 Full option matrix (what the dashboard form must render)

| Concept | Column | Values |
|---|---|---|
| Group name | `item_options.name_ar/en` | "Size", "Extras", "Spice Level" |
| Mandatory? | `item_options.is_required` | bool |
| Pick how many | `min_selections` / `max_selections` | int / int-NULL |
| Choice label | `item_option_choices.name_ar/en` | "Large" |
| Price delta | `item_option_choices.price_modifier` | ≥ 0 EGP |
| Pre-selected | `item_option_choices.is_default` | bool |
| In stock | `item_option_choices.is_available` | bool |
| Calories | `item_option_choices.calories` | nullable int |

---

## 6. 🔴 CRITICAL FINDING — There Is No Merchant User System

I grepped the entire `supabase/` tree for `merchant_users`, `merchant_members`, `merchant_staff`, `owner_id`, and any `profiles → merchants` link. **Zero matches.**

**Consequences:**

1. **No merchant can ever log in.** The only role system is `profiles.role TEXT CHECK IN ('customer','driver','admin')` (002). There is no `merchant` role.
2. **Every menu change must be made by a platform admin** through the dashboard using the `service_role` key. No self-service, no merchant portal, no delegation.
3. **`customers` (seed 3), `drivers` (seed 7), `admins` — all seeded. Merchants are the only actor with no account.**

**Decision you must make before building merchant-facing screens:**

| Option | What it costs |
|---|---|
| **A. Admin-only (status quo)** | Zero migration. Merchants call/whatsapp an admin to change their menu. Does not scale past ~50 vendors. |
| **B. Add `merchant_users` join table** | New table `merchant_users(user_id → profiles, merchant_id → merchants, role, created_at)` + `profiles.role` gains `'merchant'` + new RLS policies so a merchant can CRUD only their own `categories`/`items`/`item_options`/`item_option_choices`. ~1 migration, plus rewriting the 4 menu RLS policies (currently `USING (TRUE)`). |
| **C. Add `'merchant'` role + `profiles.merchant_id`** | Simpler RLS (`merchant_id = auth.uid()`-style check) but one merchant = one profile. Blocks staff accounts. |

> **Recommendation: Option B.** It's the only one that supports a real vendor panel, and the RLS work is bounded — exactly 4 tables need policy replacement (`categories_read`, `items_read`, `item_options_read`, `item_option_choices_read`, all currently `USING (TRUE)`).

---

## 7. Merchant-Adjacent Tables

### 7.1 `merchant_categories` (097) — the business-type lookup

```sql
CREATE TABLE public.merchant_categories (
  code       TEXT PRIMARY KEY CHECK (code ~ '^[a-z][a-z0-9_]*$'),
  name_ar    TEXT NOT NULL,
  name_en    TEXT NOT NULL,
  icon       TEXT,                          -- emoji for chip grid
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_active  BOOLEAN NOT NULL DEFAULT TRUE, -- hide without deleting
  created_at / updated_at TIMESTAMPTZ
);
```

**8 seeded codes:**

| code | name_ar | name_en | icon | order |
|---|---|---|---|---|
| `restaurant` | مطاعم | Restaurants | 🍔 | 1 |
| `pharmacy` | صيدليات | Pharmacies | 💊 | 2 |
| `market` | أسواق | Markets | 🛒 | 3 |
| `grocery` | بقالة | Grocery | 🧺 | 4 |
| `bakery` | مخبوزات | Bakery | 🥖 | 5 |
| `butcher` | جزارة | Butcher | 🥩 | 6 |
| `flowers` | زهور | Flowers | 💐 | 7 |
| `other` | أخرى | Other | 🛍️ | 8 |

**Migration 098** replaced three inline `CHECK IN ('restaurant','pharmacy')` constraints with FKs to `merchant_categories(code)`:

| Table | Column | Nullable after 098 |
|---|---|---|
| `merchants` | `category` | NO |
| `promoted_slots` | `category` | YES (stays nullable) |
| `promo_codes` | `category` | YES (stays nullable) |

**Dashboard implication:** business type is now **data-driven, not code-driven**. The dashboard's merchant-type dropdown must read `merchant_categories` (where `is_active = TRUE`) — never a hardcoded array. Adding a 9th vendor type = one INSERT, no deploy.

**View `active_merchant_categories` (099)** — `WITH (security_invoker = true)`, returns only categories with ≥1 active merchant, plus `active_merchants COUNT(*)`. This is the chip-row source and makes "a chip with no backing vendor" structurally impossible. Use it for the dashboard's category filter dropdown so you never offer a filter that returns zero rows.

### 7.2 `operating_hours` (006) — exactly 7 rows per merchant

```sql
CREATE TABLE operating_hours (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  day_of_week SMALLINT NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
  open_time   TIME NOT NULL,
  close_time  TIME NOT NULL,
  is_closed   BOOLEAN NOT NULL DEFAULT FALSE,
  created_at / updated_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX idx_operating_hours_merchant_day ON operating_hours(merchant_id, day_of_week);
```

> ⚠️ **`day_of_week` semantics are inconsistent across the codebase.** The column comment says `0=Sunday … 6=Saturday` (Egyptian week), and `CHECK BETWEEN 0 AND 6` allows it — but both `is_merchant_open()` (017:236) **and** the materialized view (031:51) use `EXTRACT(ISODOW FROM ...)` which returns **1=Monday … 7=Sunday**. 7 is outside the CHECK constraint, so **Sunday never matches** — Sunday merchants always read as closed.

> 🔴 **Overnight hours don't work.** The predicate is `current_time >= open_time AND current_time < close_time`. A merchant open `22:00 → 02:00` is closed at 01:00 because `01:00 < 22:00` is false. The seed data does this (`close_time = '01:00'` for Thu/Fri, seed.sql:125) — so those seeded hours are **already broken**.

> ⚠️ **No overnight flag.** Requires a schema change (`is_overnight BOOLEAN` or split shifts) to support late-night vendors — highly relevant if `pharmacy` ("24-hour pharmacy" is literally in seed.sql:105) is a launch category.

### 7.3 `reviews` (012 + 104 + 105 + 106)

| Column | Type | Notes |
|---|---|---|
| `order_id` | UUID | **UNIQUE** — one review per order |
| `customer_id` | UUID | Auto-filled from order by trigger |
| `merchant_id` | UUID | Auto-filled from order by trigger |
| `merchant_rating` | SMALLINT | `CHECK 1..5`, NOT NULL |
| `merchant_comment` | TEXT | free text |
| `driver_rating` | SMALLINT | nullable |
| `is_visible` | BOOLEAN | **104: `DEFAULT FALSE`** — moderation gate |
| `moderated_by` / `moderated_at` / `moderation_note` | | Ops moderation trail |

- **Read policy (106):** `USING (is_visible = TRUE OR customer_id = auth.uid())` — authors see their own pending review.
- **Aggregates filter `is_visible = TRUE`** — so `merchants.rating` excludes pending reviews.
- **105 fixed the re-aggregation bug:** flipping `is_visible` now re-runs `update_merchant_rating` / `update_driver_rating` via `IS DISTINCT FROM` check. Approving a review updates the merchant's rating immediately.

**Dashboard implication:** you need a **moderation queue** — `SELECT * FROM reviews WHERE is_visible = FALSE`. And `get_merchant_review_summary` (093, patched by 104) returns `{average_rating, total_count, distribution[5]}` — but **counts only visible reviews**, so a moderation backlog silently deflates the displayed average.

### 7.4 `favorite_items` (092) & `favorites` (015)

| Table | Grain | Unique |
|---|---|---|
| `favorites` | user ↔ **merchant** | `(user_id, merchant_id)` |
| `favorite_items` | user ↔ **item** | `(user_id, item_id)` |

`favorite_items` denormalizes `merchant_id` for query speed. Dashboard use: *"top favorited items"* and *"which merchants get saved"* — a real demand signal no other table provides.

### 7.5 `merchant_payouts` (085) — merchant finance

- `merchant_payouts` — one row per settlement period. States enforced by `enforce_merchant_payout_transitions()`.
- `merchant_payout_orders` — junction (payout ↔ order), snapshots `merchant_payout_at_settlement` per order.
- `create_merchant_payout(merchant, period_start, period_end)` — aggregates that merchant's delivered, not-yet-paid orders. **Idempotent**: raises if a pending/approved payout already overlaps the period.
- Formula: `net_payable = Σ orders.merchant_payout`; `commission_deducted = Σ (subtotal × COALESCE(merchant_commission_pct,0) / 100)`.
- RLS: only admins with a live `admin_sessions` row can read.

### 7.6 `orders` / `order_items` — the snapshot model (008)

**`order_items` freezes everything at checkout.** This is the most important thing to understand for reporting:

| Column | Snapshot? |
|---|---|
| `item_name_ar` / `item_name_en` | 🔒 **FROZEN** copy of `items.name_*` |
| `item_price` | 🔒 **FROZEN** copy of `items.price` |
| `selected_options` | 🔒 JSONB array: `{option_name_ar, option_name_en, choice_name_ar, choice_name_en, price_modifier}` |
| `total_price` | `(item_price + Σ modifiers) × quantity` |
| `item_id` | live FK, `ON DELETE CASCADE` ⚠️ |
| `special_instructions` | customer text |

`orders` also snapshots:
- `merchant_commission_pct` — commission frozen at order time
- `merchant_payout` — `GENERATED ALWAYS AS (subtotal - subtotal × pct/100) STORED`
- `delivery_address` JSONB — frozen address
- `idempotency_key` UNIQUE — duplicate-order guard

> 🔴 **The `item_id` `ON DELETE CASCADE` is a data-loss trap.** Deleting an `items` row **hard-deletes every `order_items` row referencing it**, destroying order history. `068_add_soft_delete.sql` solved exactly this for `promo_codes` and `promoted_slots` — but **`items` and `categories` were never given a `deleted_at` column.** For a dashboard, this means **no hard DELETE on items/categories**, or a `107_add_menu_soft_delete.sql` migration first.

> 💡 Also note: `selected_options` JSONB holds names but **no `choice_id`** — you cannot post-hoc analyze "which option configuration sold most" by ID, only by string-matching names.

### 7.7 `promo_codes` (011 + 042 + 068 + 071-078)

Merchant-scoped promos: `merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE` (NULL = all merchants), plus `category` FK → `merchant_categories`. Has `deleted_at` soft-delete (068), city/area targeting (071), segment targeting (072), stackable flag (073), fraud detection (074), and `funded_by` (078). Guarded by atomic usage RPCs (044/045).

### 7.8 `promoted_slots` (014 + 068 + 070)

Ad injection into the merchant feed, scoped to `merchant_id` + `city` + `category`. Has `deleted_at` (068) and a per-impression/click event log in `promoted_slot_events` (070, service-role only).

---

## 8. RLS — What the Dashboard Can and Cannot Do

### 8.1 Current menu policies (020) — all wide open

```sql
CREATE POLICY "categories_read"         ON public.categories          FOR SELECT USING (TRUE);
CREATE POLICY "items_read"             ON public.items              FOR SELECT USING (TRUE);
CREATE POLICY "item_options_read"      ON public.item_options       FOR SELECT USING (TRUE);
CREATE POLICY "item_option_choices_read" ON public.item_option_choices FOR SELECT USING (TRUE);
CREATE POLICY "merchants_read_active"  ON public.merchants           FOR SELECT USING (is_active = TRUE);
CREATE POLICY "operating_hours_read"   ON public.operating_hours     FOR SELECT USING (TRUE);
```

**Reads are public.** **Writes are denied to everyone except `service_role`** — no INSERT/UPDATE/DELETE policy exists on any of these tables, so RLS blocks anon and authenticated by default.

> **This is the dashboard's entire write model.** Every create/edit/delete the dashboard performs must go through a `service_role` client. The dashboard's `anon`/`authenticated` key can read the catalog but cannot write a single row.

### 8.2 Implication for the dashboard

| Concern | Status |
|---|---|
| Read inactive merchants | ❌ **Blocked** by `merchants_read_active`. Must use `service_role` |
| Read pending-approval merchants | ❌ **Blocked** for the same reason |
| Read hidden (`is_visible=false`) reviews | ❌ **Blocked** by `reviews_read_visible` — moderation queue needs `service_role` |
| Read pending payouts | ❌ Needs `service_role` **and** a live `admin_sessions` row |
| Read `audit_logs` | ❌ Service-role only, **zero policies** |
| Write anything in the catalog | ❌ Needs `service_role` |

**Conclusion:** an admin session in `admin_sessions` is *not* sufficient for a PostgREST client. The dashboard's server layer needs a `service_role` client for essentially every admin operation, gated by its own application-level session check. The DB gives you no admin-scoped read path.

### 8.3 RLS coverage

- `019_enable_rls.sql` — initial sweep
- `096_enable_rls_missing_tables.sql` — closed 2 CI gaps (`promoted_slot_events`, `loyalty_promo_log`) with **RLS-on + zero policies = deny-all**
- CI enforces this: `scripts/check-rls-coverage.js` requires `ENABLE ROW LEVEL SECURITY` after every `CREATE TABLE`
- `092` added `favorite_items` to the `supabase_realtime` publication

---

## 9. Admin Auth & Roles

### 9.1 Role model

```sql
-- profiles (002)
role TEXT NOT NULL DEFAULT 'customer' CHECK (role IN ('customer', 'driver', 'admin'))
```

- `handle_new_user()` (002, `SECURITY DEFINER`) auto-creates a `profiles` row with `role='customer'` on every `auth.users` insert — the anti-escalation anchor.
- `prevent_driver_role_escalation()` (024, hardened 052) blocks self-promotion to driver/admin.
- **`admin` is a manual insert only.** There is no "invite admin" flow in the schema.
- `idx_profiles_role` supports role listing.

### 9.2 `admin_sessions` (028)

| Column | Notes |
|---|---|
| `admin_id` | → `profiles(id)` |
| `session_token` | **hashed**, not plaintext |
| `ip_address` INET / `user_agent` / `country` / `city` | anomaly detection |
| `created_at` / `last_accessed_at` / `expires_at` | `CHECK (expires_at > created_at)` |
| `invalidated_at` / `invalidation_reason` | `logout\|new_login\|admin_force\|timeout\|security_alert` |
| `device_fingerprint` | "logout everywhere" |

- **Zero RLS policies** → service-role only. Admins never query it directly.
- `create_admin_session()` invalidates **all** prior sessions on login (one active session per admin), default 8h.
- `invalidate_all_admin_sessions()` / `cleanup_expired_admin_sessions()`.
- Many admin policies (e.g. `merchant_payout_orders`) gate on `EXISTS (SELECT 1 FROM admin_sessions WHERE admin_id = auth.uid() AND expires_at > NOW())`.

### 9.3 Audit trail — two tables, different jobs

| Table | Scope | Immutability |
|---|---|---|
| `audit_logs` (039) | **All** admin actions. `action` = `resource.verb`. `resource_type` CHECK includes `'merchant'`, `'menu_item'`, `'category'`. `details` JSONB snapshot | 🔒 `prevent_audit_log_update` + `prevent_audit_log_delete` triggers **raise an exception** |
| `data_access_log` (029) | **PII access** specifically. `log_data_access()` + `get_admin_access_summary()` | — |

For the dashboard: when an admin edits a menu item, write an `audit_logs` row with `resource_type='menu_item'`, `resource_id=<item uuid>`, `details={before, after}`. The CHECK constraint already whitelists `menu_item` and `category`.

---

## 10. RPCs & Functions the Dashboard Can Use

### 10.1 Merchant-specific

| Function | Signature | Returns |
|---|---|---|
| `get_merchant_kpis` (066) | `(p_merchant_id uuid)` | `{order_count, revenue, item_count}` — **all-time, all statuses** |
| `get_merchant_kpis_range` (091) | `(p_merchant_id uuid, p_from timestamptz)` | `{order_count, revenue, avg_order_value}` — **range-scoped** |
| `get_merchant_review_summary` (093→104) | `(p_merchant_id uuid)` | `{average_rating, total_count, distribution[5]}` — **visible reviews only** |
| `get_merchant_feed` (031) | `(city, category, lat, lng, limit, offset)` | 21 cols incl. `is_currently_open`, `distance_meters`, `is_promoted`, `promoted_position` |
| `is_merchant_open` (017) | `(p_merchant_id uuid)` | bool. ⚠️ Comment warns: **single lookups only**, never per-row |
| `refresh_merchant_open_status` (031) | `()` | `REFRESH MATERIALIZED VIEW CONCURRENTLY`. **Cannot run inside a transaction** — Supabase wraps each migration in one, so never call from a migration |
| `search_catalog` (095) | 12 params incl. `p_query`, `p_city`, `p_category`, lat/lng, limits, fuzzy threshold | JSON `{merchants[], items[], suggestions[]}`. Guards: query length 2–80 |

### 10.2 Platform-wide

| Function | Migration | Purpose |
|---|---|---|
| `get_analytics_summary` | 054 | Platform KPIs incl. user-role breakdown |
| `compute_admin_kpis` / `get_admin_kpi(key)` | 035 → 058 → 052 | **Materialized KPI cache** — read from cache, don't recompute |
| `get_admin_access_summary` | 029 | PII-access audit |
| `get_unique_audit_actions` | 057 | Filter dropdown for the audit log UI |
| `get_avg_order_value()` | 069 | 30-day AOV. `REVOKE`d from PUBLIC, `service_role` only |
| `get_platform_config(key)` | 017 | Read a `platform_config` value |
| `calculate_delivery_fee(merchant, km)` | 017 | Honors `delivery_fee_override` |
| `admin_create_driver` / `admin_review_driver` / `admin_deactivate_driver` | 030 → 052 | Driver admin RPCs — **the pattern to copy for merchant RPCs** |
| `create_merchant_payout` / `mark_merchant_payout_paid` | 085 | Payout lifecycle |
| `cancel_order` / `admin_cancel_order` | 033→059→081→082→086→088 | Order cancellation, 6 hardening rounds |
| `place_order_with_items` | 026→036→045→049→075→080 | 6 revisions |
| `check_and_trigger_alerts` | 040→058→094 | Alert engine |

### 🔴 The `get_merchant_kpis` revenue number is misleading

```sql
'subtotal', ...
'revenue', COALESCE((SELECT SUM(total) FROM public.orders WHERE merchant_id = p_merchant_id), 0)
```

**No status filter.** Cancelled and refunded orders are counted as revenue. The migration comment even admits it: *"sum of orders.total (all statuses)"*. Compare with `get_avg_order_value` (069) which *does* filter `status != 'cancelled'`.

**Dashboard rule: do not label `get_merchant_kpis().revenue` as "Revenue".** Either label it "Gross order value (incl. cancelled)" or build a new status-filtered RPC.

---

## 11. Storage Buckets (025)

| Bucket | Public | Limit | MIME | Path convention |
|---|---|---|---|---|
| `merchant-assets` | ✅ | 5 MB | jpeg/png/webp | `merchant-assets/{merchant_id}/logo.{ext}`, `.../cover.{ext}` |
| `item-images` | ✅ | 5 MB | jpeg/png/webp | `item-images/{merchant_id}/{item_id}.{ext}` |
| `driver-documents` | 🔒 **private** | 5 MB | jpeg/png/webp | — |
| `user-avatars` | ✅ | 5 MB | jpeg/png/webp | — |
| `ad-creatives` | ✅ | 5 MB | jpeg/png/webp | — |

All have read/write/update/delete policies. Note `logo_url` / `cover_url` / `image_url` are **TEXT columns holding paths**, not enforced by FK to `storage.objects` — nothing stops a dashboard upload writing a URL that points at a deleted object. Orphaned media is invisible to the DB.

---

## 12. `platform_config` (004) — Runtime Config

Key-value store, `value TEXT` cast by consumers, `value_type ∈ (string, number, boolean, json)`, `is_editable` flag for the admin UI. **Editable from the dashboard with no deploy.**

**17 seeded keys** — the ones that affect merchants:

| Key | Default | Effect |
|---|---|---|
| `delivery_base_fee` | `25.00` | EGP |
| `delivery_per_km_rate` | `5.00` | EGP/km |
| `delivery_free_threshold` | `200.00` | free delivery above this |
| `delivery_max_distance_km` | `15` | hard cap (vs per-merchant `delivery_radius_km` default 10) |
| `platform_fee` | `3.00` | per order |
| `platform_fee_percentage` | `0` | 0 = fixed fee |
| **`default_commission_pct`** | `15.00` | fallback when `merchants.commission_pct IS NULL` |
| `driver_earnings_pct` | `80.00` | |
| `order_auto_cancel_minutes` | `30` | |
| `max_items_per_order` | `50` | |
| `promo_max_discount_amount` | `100.00` | |

---

## 13. 🔴 Findings Summary — Ranked

### Blocking / architectural

| # | Finding | Where | Action |
|---|---|---|---|
| 1 | **No merchant user system.** No `merchant_users`, no `merchant` role. Vendors cannot self-serve. | — | Decide A/B/C (§6). B recommended |
| 2 | **Sunday never open.** `operating_hours.day_of_week CHECK 0..6` vs `EXTRACT(ISODOW)` returning 1..7 | 006:18 vs 017:236, 031:51 | Align semantics; pick one convention |
| 3 | **Overnight hours impossible.** `time >= open AND time < close` breaks for `22:00→02:00` | 017:245-249, 031:53-54 | Add `is_overnight` or split shifts |
| 4 | **Hard DELETE on items/categories destroys order history** via `order_items.item_id ON DELETE CASCADE` | 007:105 | Migration `107`: add `deleted_at` to `items` + `categories` |
| 5 | **`merchants.bank_account_number` is plaintext** | 085:162 | Apply the 027 encryption pattern |

### Data integrity

| # | Finding | Where | Action |
|---|---|---|---|
| 6 | `items.merchant_id` and `items.category_id` are **unconstrained against each other** | 007:50-51 | Composite FK, or validate in app code |
| 7 | `item_options.min_selections` can exceed `max_selections`; no CHECK | 007:110-115 | App validation, or a migration CHECK |
| 8 | `item_options.is_required` can contradict `min_selections` | 007:106-115 | App validation |
| 9 | `item_option_choices.is_default` has **no uniqueness** — all choices can be default | 007:150 | Force one default for single-select groups |
| 10 | `is_default = TRUE` on an `is_available = FALSE` choice | 007:150-153 | Block in app |
| 11 | `price_modifier CHECK (>= 0)` — **discount options impossible** | 007:146-147 | Drop CHECK if discounts needed |
| 12 | `calories` on choices but **not on items**; no `CHECK >= 0` | 007:158 | Add to `items`; add CHECK |

### Reporting / correctness

| # | Finding | Where | Action |
|---|---|---|---|
| 13 | `get_merchant_kpis().revenue` **includes cancelled orders** | 066:39-41 | Never label as "Revenue"; add status-filtered RPC |
| 14 | `get_merchant_review_summary` counts **visible only** → moderation backlog deflates averages | 093→104 | Show "N pending moderation" next to the rating |
| 15 | 🔴 **Migration `031` materialized view is stale by design.** `merchants_with_open_status` was created with an **explicit 19-column list** and **never recreated**. It is missing everything added later: `delivery_radius_km`, `estimated_prep_time_minutes`, `approval_status`, `approval_note`, and all 6 payout columns. It also does not pick up the 098 FK change. | 031:23-57 vs 042, 085, 103 | Dashboard must query `merchants` directly for full records. Only use the matview for feed-grade open/closed display |
| 16 | `merchants.city` / `area` are free text, not FKs | 005:34-35 | Typo risk in filters; consider a `cities` lookup |
| 17 | No item/category counts on `merchants` | — | Aggregate per request, or add a counter + trigger |
| 18 | `selected_options` JSONB stores names, no `choice_id` | 008:117 | Option analytics limited to string matching |

---

## 14. Recommended Dashboard Data-Access Pattern

```
┌─────────────────────────────────────────────────────────┐
│  Dashboard UI (React)                                   │
└───────────────────────┬─────────────────────────────────┘
                        │ HTTP (cookie session)
┌───────────────────────▼─────────────────────────────────┐
│  Dashboard API routes (Node)                            │
│  • verify admin_sessions row (app-level authz)          │
│  • requireAdmin() guard                                 │
└───────────────────────┬─────────────────────────────────┘
                        │
        ┌───────────────┴────────────────┐
        │                                │
┌───────▼─────────────────┐   ┌──────────▼──────────────────┐
│ service_role client     │   │ anon/authenticated client   │
│ (ALL writes + admin     │   │ (public catalog reads only)  │
│  reads: inactive        │   │ • merchants is_active=TRUE   │
│  merchants, moderation │   │ • categories/items/options   │
│  queue, payouts, audit) │   │   USING (TRUE)               │
└─────────────────────────┘   └─────────────────────────────┘
```

**Concrete rules:**

1. **Never** give the browser a `service_role` key. All `service_role` calls live server-side.
2. Catalog **writes** (`categories`, `items`, `item_options`, `item_option_choices`) → `service_role`, no RLS policy permits anything else.
3. Merchant list/detail → `service_role` (you must see `is_active=false` and `approval_status='pending'`).
4. Write an `audit_logs` row for every menu mutation (`resource_type` = `'menu_item'` or `'category'`, `action` = `'merchant.create'` / `'menu_item.update'` / `'category.delete'`).
5. **No hard DELETE on items/categories** until finding #4 is fixed.
6. Read `merchant_categories` (not a hardcoded array) for the business-type dropdown; read `active_merchant_categories` for any filter that must not return empty.
7. Use `get_merchant_kpis_range` (091) for date-scoped KPIs; use `get_merchant_kpis` (066) only for all-time, and label its `revenue` field honestly.
8. Use the `admin_kpi_cache` (035) for dashboard home tiles — do not re-aggregate raw tables per page load.

---

## 15. Open Questions for You

1. **Will vendors ever log in?** Determines whether finding #1 blocks the build. (§6)
2. **Do you need branches/chains?** Currently 1 row = 1 location. A "Al Ezaby Pharmacy" chain with 5 branches = 5 unrelated rows with 5× the menu data. Multi-location is a significant redesign.
3. **Do you need discounts or price *reductions* on items/options?** `price_modifier >= 0` blocks them today. (§11)
4. **Is `pharmacy` a launch category?** It's in the seed data and called "24-hour", but the hours model can't do 24/7. (§7.2)
5. **What is your item-import story?** For a pharmacy with hundreds of SKUs, per-row dashboard forms will not scale. `search_catalog` exists; a bulk CSV/RPC import does not.
6. **Do you need dietary/allergen metadata?** Not present on `items`. Relevant for a pharmacy + food hybrid.

---

## Appendix A — Migration index (106 files, merchant-relevant)

| # | File | Merchant relevance |
|---|---|---|
| 002 | `create_profiles` | `role` CHECK — no `merchant` value |
| 004 | `create_platform_config` | 17 config keys |
| **005** | **`create_merchants`** | **base table, 22 cols** |
| **006** | **`create_operating_hours`** | **7 rows/merchant; day_of_week semantics** |
| **007** | **`create_menu_structure`** | **categories, items, item_options, item_option_choices** |
| 008 | `create_orders` | `order_items` price snapshots |
| 011 | `create_promo_codes` | merchant-scoped promos |
| 012 | `create_reviews` | merchant ratings |
| 014 | `create_promoted_slots` | ad injection |
| 015 | `create_favorites` | user ↔ merchant |
| 016 | `create_indexes` | trigram indexes |
| 017 | `create_functions` | `is_merchant_open`, `calculate_delivery_fee`, `get_platform_config` |
| 019 | `enable_rls` | RLS on the 5 catalog tables |
| 020 | `create_rls_policies` | all 4 menu policies `USING (TRUE)` |
| 025 | `create_storage_buckets` | `merchant-assets`, `item-images` |
| 028 | `create_admin_sessions` | admin session model |
| 029 | `create_data_access_log` | PII audit |
| 031 | `add_merchant_open_batch_view` | 🔴 **stale matview + `get_merchant_feed`** |
| 039 | `create_audit_logs` | immutable admin trail |
| 042 | `add_missing_ef_columns` | **+2 merchant cols** |
| 066 | `merchant_kpi_rpc` | `get_merchant_kpis` |
| 068 | `add_soft_delete` | ⚠️ promos + ads only, **not menu** |
| 069 | `get_avg_order_value_rpc` | status-filtered AOV |
| 085 | `merchant_payouts` | **+6 merchant cols**, plaintext bank number |
| 091 | `merchant_kpi_range_rpc` | range KPIs |
| 092 | `add_favorite_items` | user ↔ item |
| 093 | `get_merchant_review_summary_rpc` | rating distribution |
| **095** | **`search_discovery_mvp`** | **`search_catalog`, normalize_search_text, search_queries** |
| 096 | `enable_rls_missing_tables` | CI coverage fix |
| **097** | **`create_merchant_categories`** | **8-code lookup** |
| **098** | **`widen_category_constraints`** | **CHECK → FK on 3 tables** |
| **099** | **`create_active_merchant_categories_view`** | **`security_invoker` view** |
| 103 | `merchant_approval_status` | **+2 merchant cols** |
| 104 | `review_moderation` | `is_visible` gate |
| 105 | `review_visibility_reaggregate` | re-aggregate on visibility flip |
| 106 | `review_author_visibility` | authors see own pending |

## Appendix B — All 40 tables

<details>
<summary>Click to expand</summary>

| Table | Migration | RLS | Purpose |
|---|---|---|---|
| `profiles` | 002 | ✅ | Extends `auth.users`; `role`, wallet, language |
| `addresses` | 003 | ✅ | Saved delivery addresses |
| `platform_config` | 004 | ✅ | Runtime KV config |
| **`merchants`** | **005** | ✅ | **Vendors** |
| `operating_hours` | 006 | ✅ | 7 rows/merchant |
| **`categories`** | **007** | ✅ | **Menu sections** |
| **`items`** | **007** | ✅ | **Menu items** |
| **`item_options`** | **007** | ✅ | **Option groups (Size)** |
| **`item_option_choices`** | **007** | ✅ | **Option values (Large)** |
| `orders` | 008 | ✅ | Core order |
| `order_items` | 008 | ✅ | Price snapshots |
| `order_status_history` | 008 | ✅ | Status audit trail |
| `drivers` | 009 | ✅ | Driver profiles |
| `driver_earnings` | 010 | ✅ | Per-delivery earnings |
| `promo_codes` | 011 | ✅ | Discount codes |
| `reviews` | 012 | ✅ | Ratings + moderation |
| `notifications` | 013 | ✅ | Push/in-app |
| `promoted_slots` | 014 | ✅ | Ads in feed |
| `favorites` | 015 | ✅ | user ↔ merchant |
| `driver_documents` | 021 | ✅ | Verification docs |
| `driver_status_history` | 022 | ✅ | Online/offline log |
| `cancellation_rules` | 023 | ✅ | Cancellation policy |
| `admin_sessions` | 028 | ✅ zero policies | Admin sessions |
| `data_access_log` | 029 | ✅ | PII access audit |
| `wallet_audit_log` | 034 | ✅ | Wallet changes |
| `promo_code_usage` | 034 | ✅ | Redemption log |
| `admin_kpi_cache` | 035 | ✅ | KPI cache |
| `audit_logs` | 039 | ✅ zero policies + immutable | All admin actions |
| `alert_rules` | 040 | ✅ | Alert config |
| `alert_incidents` | 058 | ✅ | Alert firings |
| `driver_order_requests` | 060 | ✅ | Driver offer fan-out |
| `promoted_slot_events` | 070 | ✅ zero policies | Ad impressions/clicks |
| `loyalty_promo_log` | 076 | ✅ zero policies | Loyalty issuance |
| `driver_settlements` | 083 | ✅ | Driver payout batches |
| `driver_settlement_earnings` | 083 | ✅ | Earnings junction |
| `merchant_payouts` | 085 | ✅ admin session | Merchant payout batches |
| `merchant_payout_orders` | 085 | ✅ admin session | Payout junction |
| `favorite_items` | 092 | ✅ | user ↔ item |
| `search_queries` | 095 | ✅ | Search analytics |
| **`merchant_categories`** | **097** | ✅ read `is_active` | **Business-type lookup** |

**Non-table database objects:**

| Object | Type | Migration |
|---|---|---|
| `merchants_with_open_status` | 🔴 **materialized view (STALE)** | 031 |
| `active_merchant_categories` | view (`security_invoker`) | 099 |

</details>

---

*Report generated from `supabase/` only: migrations 001–106, `seed.sql`, `config.toml`. 40 tables, 2 views, 5 storage buckets, ~100 functions.*

---

## 16. Product decisions

Confirmed 2026-10-03. Recorded here so future work does not re-litigate them.

### 16.1 Deferred — no work now

| Item | Decision |
|---|---|
| Merchant user system / merchant self-service | **DEFERRED.** No `merchant_users`, no `merchant` role. Vendors cannot log in; platform admins do 100% of catalog work through the dashboard using `service_role`. Revisit when vendor count makes phone-based menu changes unscalable |

### 16.2 Dropped — remove entirely

| Item | Decision |
|---|---|
| `merchants.bank_account_number` | **DROP the column.** Also drop `bank_account_holder`, `bank_name`, `wallet_phone` — they exist only to support automated payouts |
| Merchant payout automation | **HUMAN-IN-THE-LOOP ONLY, NO AUTOMATION.** Cash handed over directly, or money sent by Vodafone Cash directly, both performed manually by a person. Nothing automated |
| `calories` asymmetry (on choices, not items) + missing `CHECK >= 0` | **DROPPED.** Not worth a migration |
| Dietary / allergen metadata | **DROPPED.** Not adding it to `items` |

**Consequence of dropping the bank columns:** `merchant_payouts` (085) and
`merchant_payout_orders` still exist and `auto-generate-merchant-payouts` is
still a scheduled Edge Function. `merchants.payout_frequency` and
`payout_method` also remain. Decide whether to remove the whole settlement
subsystem or keep it as a **manual record** — a paper ledger typed into the
dashboard, where `payout_method = 'cash'` and a human does the handover. That is
a cleaner fit than deleting the tables, because you still need to know what a
merchant is owed and has been paid.

### 16.3 Confirmed launch scope

| Item | Decision |
|---|---|
| Pharmacy | **LAUNCH CATEGORY.** Along with all 8 seeded codes: `restaurant`, `pharmacy`, `market`, `grocery`, `bakery`, `butcher`, `flowers`, `other`. Verified all 8 are `is_active = TRUE`; none may be deactivated at launch. Adding a 9th type = one INSERT into `merchant_categories`, no deploy |
| 24-hour pharmacy | **Works today** — `00:00`–`24:00` is valid (`test_01::test_24h_merchant_is_representable`). My earlier claim that it was impossible was wrong |

### 16.4 New work — queued for migrations

| Requirement | Status | Notes |
|---|---|---|
| **Branches / chains** | Design not started | No `branches` table, no `parent_merchant_id`/`brand_id`/`chain_id` on `merchants` (verified). **Blocking question: do branches share one menu or have independent menus?** Shared menus means `item_options`/`item_option_choices` need a branch scope; independent menus means the current schema survives and you only need a parent link plus a reporting rollup |
| **Discounts on items** | ✅ **Shipped, migration 119** | `items.discount_price`, `CHECK (0 <= discount_price <= price)`, effective price `COALESCE(discount_price, price)` |
| **Price reductions on options** | ✅ **Shipped, migration 111** | `price_modifier` floor lowered to −1,000,000; the "modifier must not exceed base price" guard lives in `place_order_with_items` where the base price is in hand |

### 16.5 Fixes — SHIPPED as migrations 107–119

All 118 migrations replay cleanly on local PostgreSQL 18 and the suite is green:
**131 passed, 2 skipped, 1.4s.** Full evidence in `dashborad/test/BUG-REPORT.md`.

| Migration | Fixes |
|---|---|
| `107_fix_operating_hours_day_of_week` | Sunday never opens (`0=Sunday` vs `ISODOW=7`) — backfill 0→7, CHECK now 1..7 |
| `108_index_order_items_item` | `order_items.item_id` unindexed. **Must precede 110** |
| `109_merchants_approval_rls` | Unapproved merchants were publicly visible |
| `110_menu_soft_delete` | Deleting an item erased its order history |
| `111_option_constraints` | Selection cardinality, multiple defaults, negative modifiers, sold-out default |
| `112_catalog_integrity` | Item filed under another merchant's category |
| `113_rebuild_merchant_matview` | Matview missing 10 columns, rebuilt as `SELECT m.*` |
| `114_kpi_status_filter` | "Revenue" included cancelled orders + the duplicate subqueries |
| `115_drop_bank_columns` | Your decision — 3 bank columns dropped, `wallet_phone` kept |
| `116_dashboard_indexes` | Approval queue and moderation queue both seq-scanned |
| `117_option_snapshot_ids` | `selected_options` had no `choice_id` |
| `118_overnight_hours` | `22:00 → 02:00` unrepresentable |
| `119_item_discounts` | **REQ-02 delivered**, plus BUG-19 and half of BUG-18 |

### 16.7 Item discounts (REQ-02) — shipped in 119

Before: two price columns across the whole catalog, so a "was 100, now 80" item
was impossible.

| Object | Purpose |
|---|---|
| `items.discount_price` | nullable; effective price is `COALESCE(discount_price, price)` |
| `CHECK (0 <= discount_price <= price)` | cannot be negative, cannot exceed the list price |
| `order_items.original_price` | pre-discount price, so ending a promotion doesn't rewrite history |
| `idx_items_discounted` | partial — holds only discounted rows |

**One column, not a discount table:** an item has at most one active reduction,
it applies to everyone, and nothing in the brief asks for scheduling or
segmenting. A table would add a join to the hottest query in the app.

**`place_order_with_items` now resolves price server-side.** It previously took
`item_price` from the request, which would have meant the dashboard displayed a
discount that checkout silently ignored. This also fixes the item-price half of
BUG-18.

### 16.8 🔴 Checkout was never reachable — BUG-19

`place_order_with_items` declares `RETURNS TABLE(id UUID, …)`. An OUT parameter
is a PL/pgSQL **variable**, so every bare `WHERE id = …` in the body was
ambiguous against `profiles.id`, `merchants.id`, `items.id`, `promo_codes.id` and
`orders.id`. Six sites. **Every call raised `column reference "id" is
ambiguous`** — the function had never run, in any environment, since migration
026.

It survived because nothing had called it: the suite covered catalog, RLS and
reporting, never the write path.

**Treat the first real order as a production smoke test.** Fixed in 119, but the
checkout *flow* is now reachable for the first time.

**Still open after 119:**
- `orders.delivery_fee` and `orders.discount_amount` remain client-supplied. A hostile payload can zero the delivery fee. Needs product sign-off.
- Verify the `place-order` Edge Function no longer sends prices the function now ignores.

**Not fixed by a migration:**

- **BUG-10** (ratings ignore the moderation backlog) — a dashboard display concern, no schema change needed. Show "N awaiting moderation" next to every rating.
- **DOC-01** — the incorrect `refresh_merchant_open_status` comment in migration 098.
- **REQ-01 branches** — needs your decision first.

### 16.9 Two migrations deliberately stop short

Called out in-file rather than hidden, because a half-applied change that reads
as complete is worse than an obvious gap.

**110 — soft delete.** `deleted_at` exists on `items` and `categories`, but the
**read sites do not yet filter it**. The affected files are listed in the
migration header. Safe meanwhile: soft-deleted rows stay **visible**, which is
the pre-110 behaviour.

**118 — overnight hours.** `is_overnight` exists and both readers honour it, but
**no UI sets it** yet. Until the merchant hours editor gains a "closes next day"
toggle it is settable only by direct SQL:

```sql
UPDATE operating_hours SET is_overnight = true
 WHERE merchant_id = '<uuid>' AND day_of_week = 5;
```

Note a merchant open Fri 22:00 → Sat 02:00 is stored on **Friday's** row.

### 16.6 Corrections to this document

| §  | Claim | Reality |
|---|---|---|
| 2 | "`merchants` has 30 columns" | **33.** I under-counted the 085 payout block |
| 7.2 | "A 24-hour pharmacy is not expressible" | **Wrong.** `00:00`–`24:00` works |
| 7.2 | "098's deviation is needed, `REFRESH ... CONCURRENTLY` cannot run in a transaction" | **Wrong** on PG18 — verified working inside an explicit transaction. 098's comment rules out a valid approach for no reason. Re-check on the Supabase PG version |
| 2.6 | "`bank_account_number` is the plaintext risk" | Moot — dropping all four bank/wallet columns. But `bank_account_holder` and `bank_name` are also plaintext, so the original framing understated it |
| 13 | *(no complaint made about)* `order_items.item_id` indexing | **Also unindexed.** A fourth correction: the delete cascade and every "which orders contained this item" query seq-scan the whole table. Measured at 2.6× on cascade time with 124,840 rows |

### 16.7 Testing setup

`dashborad/test/` runs the real 105 migrations against local PostgreSQL 18 with
Supabase stubs (`local/bootstrap.sql`), so no Supabase quota is consumed. Two
modes:

- **Empty schema** — 88 passed, 17 skipped. Fast correctness pass.
- **Seeded, ~200k rows** — 103 passed, 2 skipped. Adds index and plan
  verification, which is where BUG-14 to BUG-17 were found.

Seeding is not optional if you care about performance: against an empty schema a
sequential scan of nothing is free and no index is ever exercised.

---