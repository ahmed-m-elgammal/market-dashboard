# Mobile Readiness — order, checkout, address lifecycle

**Date:** 2026-10-03
**Scope:** `apps/mobile` (Expo/RN/TS) + the contracts it depends on
**Constraint:** fix to ship. No feature dropped, no redesign.
**Verification:** schema/RPC claims proven by execution in `dashborad/test` (120 migrations, ~200k rows). Mobile/EF claims are static analysis, labelled as such.

---

## Two corrections to my own earlier report

I got two things wrong before. Both are corrected here rather than buried.

### ❌ "Checkout is 100% dead" — WRONG

I reported `place_order_with_items` as unable to execute, blocking all checkout. **It executes fine.** My lab payload omitted `idempotency_key`; the ambiguous `created_at` sits in the `ELSE` arm of the duplicate check, which only runs when no key is supplied. Proven:

```
WITHOUT idempotency_key:  ERR -> column reference "created_at" is ambiguous
WITH    idempotency_key:  OK   -> (UUID('a03600b4-…'), 'ORD-000049', created_at)
```

`usePlaceOrderFlow.ts:59` generates a key per checkout session, always sends it (`place-order/index.ts:139,366`), and the RPC's `IF v_idempotency_key IS NOT NULL` branch is taken. **Mobile is not blocked by this bug.** It is still a real bug — any keyless caller breaks, and `119:243` must still be fixed — but it is not the emergency I called it.

### ❌ "RLS has no SELECT policy on orders/addresses" — WRONG

I asserted this in my briefs; the agents checked and I was wrong. Both tables have `FOR SELECT` policies:
- `orders_read_own`, `order_items_read_own`, `order_status_history_read_own` — `schema-final.sql:16082, 16052, 16067`
- `addresses_read_own` — `schema-final.sql:15598`, from `migrations/020_create_rls_policies.sql:65`

Also refuted: `idx_addresses_one_default_per_user` **does** exist as a partial UNIQUE index (`schema-final.sql:13169`, `migrations/003`), so two defaults are impossible.

What survives from my earlier claim: the **write** surface is genuinely narrow (only 6 tables have INSERT/UPDATE/DELETE policies), so all writes must go through EF/RPC with the service role. That part stands.

---

## Answer: will checkout work?

**Cash: yes, but every option surcharge is silently dropped and the customer is undercharged.**
**Card/wallet: no — for any basket containing a priced option, Paymob captures the money and the webhook then marks the order `failed`.**

That is one root cause. Everything else is degradation.

---

## B1 — CRITICAL — Option surcharges are dropped; digital payment is captured then voided

**Proven in the lab.** Item price 45, option `+25`:

| Payload shape | stored `selected_options` | line total |
|---|---|---|
| What mobile sends: `{option_id, choice_ids}` | `[]` | **45.00** |
| What the EF sends today (option name = `''`) | `[]` | **45.00** |
| Correct names both sides | fully populated | **70.00** ✅ |

Two independent defects stack:

**(a) EF queries a column that does not exist.** `supabase/functions/place-order/index.ts:576`
```ts
supabase.from('item_options').select('id, group_name_ar, group_name_en')
```
`item_options` has `name_ar` / `name_en` (verified: 0 columns matching `group%`). PostgREST 400s and the error is **discarded** at `:584` via `(optionsResult.data || [])`. Every option name becomes `''` at `:594-595`.

**(b) The SQL resolver matches by name, and `''` matches nothing.** `enrich_selected_options` requires `o.name_en = sel->>'option_name_en'`; the inner `JOIN LATERAL` yields no row → `COALESCE(…, '[]')` → `[]`. So `v_modifiers = 0` and the line is priced at base.

**Consequence for digital payments** — this is the money path:
- The EF *does* read the correct `item_option_choices.price_modifier`, so its own total is **70**, and Paymob is initialised for 70 (`index.ts:311`).
- The RPC writes `orders.total = 45`.
- `paymob-webhook/index.ts:263-286` compares `receivedCents !== expectedCents` → sets `payment_status='failed'` on a **captured** payment, then returns without notifying or queueing a refund.

Money taken, order dead, customer never told. `reconcile-payments` only scans `payment_status='pending'`, so it never picks this up.

**Fix (one word, EF side — cheapest correct path):** `index.ts:576` → `select('id, name_ar, name_en, item_id')`; `:594-595` → `opt?.name_ar`. **Then check `.error`** and fail closed. The lab proves the SQL then resolves correctly.

**SQL-only alternative** (if the EF must not change): make `enrich_selected_options` resolve by `option_id`/`choice_ids` with a name fallback. That also fixes defect (b) for any caller. Worth doing regardless — it removes the name fragility permanently.

**Related, currently masked:** `item_option_choices` is fetched with no `.eq('option_id', …)` and no scoping to the item (`:577`, `:592`). The moment (a) is fixed this becomes exploitable — a crafted choice id from another item inflates the EF total while the RPC correctly drops it. Fix in the same pass.

---

## B2 — HIGH — EF and RPC compute `platform_fee` differently

`place-order/index.ts:255,286` uses the flat `platform_fee` config. The RPC (`119:418-431`) *prefers* `platform_fee_percentage`. Seeded `'0'`, so latent — but it is admin-editable, and the moment it is non-zero **every digital payment mismatches**, hitting the identical webhook failure as B1, for baskets with no options at all.

**Fix:** make the EF mirror the RPC's `CASE WHEN pct > 0 THEN round(subtotal*pct/100) ELSE flat END`, or make the RPC honour `p_order->>'platform_fee'`.

---

## B3 — HIGH — Receipt renders `": Large"` instead of `"Size: Large"`

The SQL writes `option_name_ar/en`; the shared type declares `option_group_name_ar/en` and `OrderItemsList.tsx:83` reads `option_group_name`. `getBilingualField` returns `''` for a missing key. Masked by B1; appears the moment B1 is fixed. The existing unit test passes only because its fixture uses the TS names.

**Fix:** rename the two TS fields and the one `getBilingualField` call. Also affects menu/cart via the same `group_name` mismatch (`MenuItemOptionSelector.tsx:119,286`, `CartItemCard.tsx:63`).

---

## B4 — HIGH — Notification centre is permanently empty for order events

`send-notification/index.ts:231,357` sends `data: data || null` into `notifications.data jsonb NOT NULL DEFAULT '{}'`. Explicit JSON null bypasses the default → `23502`. **Proven in the lab.** Every order caller omits `data` (`place-order:455`, `driver-actions:527,922,1035`, `paymob-webhook:458`), and all are fire-and-forget.

Push still arrives (built independently), so deep links work — but no rows are ever written, so `useNotifications` has nothing to read and the badge stays 0.

**Fix:** `data: data ?? {}`. Two characters. Nothing in mobile reads `data`.

---

## B5 — HIGH — Drivers never see incoming requests (realtime event discarded)

`driver-actions:172` selects `id, driver_id, status` — **not** `order_number` — then broadcasts it at `:321` as `undefined`. `useRealtime.ts:23-35` validates all fields and **returns early on the whole payload** if any fails. `order_number` is the only failing field, and the event is thrown away entirely.

**Fix:** add `order_number` to the `.select()`.

---

## B6 — MEDIUM — Orders tab caps at 20 rows; active orders can vanish

`useOrders.ts:56-59` hardcodes `limit: 20`; `orders.tsx:71-73` passes no status filter; the `FlatList` has no `onEndReached`. The 20 most recent orders of *any* status are fetched, then split client-side. A customer with 20+ past orders sees **no active orders section at all** — their live order is invisible. No pagination, no error, history silently ends at #20.

**Fix:** two queries (active + past) as `_layout.tsx:168-172` already does, or add `onEndReached` + `offset`.

---

## B7 — MEDIUM — Order badge lags: query-key prefix mismatch

`QUERY_KEYS.orders.list()` → `['orders','list',undefined]` does **not** prefix-match the status-filtered badge key `['orders','list','pending|confirmed|…']`. Badge does not appear/clear immediately after placing or cancelling. Self-heals via `staleTime` + `refetchOnWindowFocus`.

**Fix:** invalidate `['orders','list']` (three call sites in `useOrders.ts`).

---

## What is genuinely sound — do not "fix" these

| Area | Evidence |
|---|---|
| **Mobile calls the EF only** | Zero direct `place_order_with_items` calls in `apps/mobile`; zero client `INSERT` into `orders`. All EF validation is enforced. Double auth: gateway `verify_jwt` + `requireRole('customer')`. |
| **No lost basket** | `clearCart()`/`resetCheckout()` run **only** inside `onSuccess` (`usePlaceOrderFlow:186,228,282,308`). `onError` only toasts. Double-tap and mid-flight navigation both guarded. |
| **Idempotency correct** | Stable per checkout session; rotated only on material change (`:99-114`) and on success; **reused verbatim on retry** (`:211`). Matches `orders.idempotency_key UNIQUE`; EF replays rather than duplicating. |
| **Payload contract complete** | Every key the RPC requires is sent. `subtotal`/`total`/`platform_fee`/`merchant_commission_pct` are correctly *ignored* server-side and recomputed. No CHECK/NOT NULL violation possible. |
| **No IDOR** | `customer_id` comes from the JWT only (`:87,351`); mobile never sends it. |
| **No client-side money reaches the server** | All JS math (`computeOrderTotal`, cart `unitPrice`) is display-only. EF re-prices from the catalog; RPC re-prices again. |
| **Order reads work** | `orders_read_own` etc. exist; direct PostgREST read + nested embeds is correct. Null-embed (deactivated merchant) degrades gracefully. |
| **Status vocabulary — zero drift** | All 8 statuses match the CHECK exactly. No `onTheWay`/`pickedUp` anywhere. `useRealtime:19-21` validates before forwarding. All 8 i18n keys exist in en+ar. |
| **Money rendering** | `Intl.NumberFormat` with `min=max=2` dp. All 6 render sites pass server values through; **no local recompute**. |
| **Notification types** | All 12 DB types mapped identically on both sides; `default:` fallbacks everywhere. |
| **No stale orders after restart** | `queryClient.ts:74` excludes `orders` from AsyncStorage persistence. 10s polling stops at terminal; realtime on top. |
| **Address lifecycle — no blockers** | SELECT policy exists; one-default-per-user enforced by partial UNIQUE index; auto-promote on delete via trigger; `user_id` sent explicitly (never relies on `DEFAULT auth.uid()`); `label` enum always valid; all NOT NULLs satisfied on both insert paths; sign-out clears query + location + checkout stores; `mutations.retry:false` prevents duplicate writes. |
| **Address → order handoff** | Key names match EF, validator, and every consumer. RPC stores the blob verbatim, so no mismatch is possible. |
| **Checkout with 0 addresses / 0 defaults** | Prompts and falls back to `addresses[0]`. Never crashes. |

---

## Address lifecycle — field risks (no blockers)

- **F1 HIGH — onboarding hard-gates on GPS.** `complete-profile.tsx:157-160` returns early with no location, and the screen has no coordinate input. A user who denies permission **cannot complete registration** (iOS will not re-prompt). The Skip button does work, so this is a conversion risk, not a lockout. *Fix: inline coordinate input as fallback.*
- **F2 HIGH — undo-delete diverges the cache.** `useAddressDeleteWithUndo:64-70` clears pending timeouts on unmount, so leaving within 6 s leaves the row removed from the UI but **still in the database**, with no reconciliation trigger, for up to the 5-min `staleTime`. *Fix: invalidate on unmount, or flush instead of clear.*
- **F3 MEDIUM — delete/set-default failures are silent, and the rollback is a no-op.** `previousAddresses` is captured *after* the undo hook already filtered the row (`useAddresses:111-116`), so `onError` restores an already-filtered list. Neither call site passes an error handler. *Fix: capture before filtering; add `onError` toasts (mirror `handleFormSave`, which is correct).*
- **F4/F5 MEDIUM — map-pan fallback.** `initialRegion` does not fire `onRegionChangeComplete`, so a GPS-denied user must pan the map with no affordance; on web the map is a non-interactive `<View>`, making it **impossible**. The fallback stores the viewport centre at whatever zoom — imprecise enough to mis-price delivery and mis-route drivers. *Fix: optional manual lat/lng inputs; raise the zoom floor.*
- **F6 MEDIUM — double-tap creates duplicate addresses.** No unique constraint, no client guard; `isPending` only flips on the next render. *Fix: one-line in-flight ref guard.*
- **F7 MEDIUM — "zero defaults" is reachable.** Untick "Set as default" on your only default and nothing promotes a replacement (the promotion trigger is `AFTER DELETE` only). Degrades gracefully — both consumers fall back to `addresses[0]`. *Fix: promote in the RPC's update path.*
- **F8–F12 LOW** — zod schema never parsed; query key not user-scoped; RPC errors flattened *and never logged* (will cost the most debugging time); onboarding addresses have `city = NULL` so search assumes Cairo; `getAddresses` fires while signed out (RLS blocks it, so no leak).

---

## Order lifecycle — remaining field risks

- **F8 MEDIUM — reviews:** submission works (`set_review_fields_from_order` fills `customer_id` before the RLS `WITH CHECK`). But `is_visible` defaults false, the reviewer sees their own review publicly while nobody else does, and the `Review` type has no `is_visible` field — so the app cannot show "pending moderation". Aggregation is correct (`get_merchant_review_summary` filters `is_visible`). *Fix: surface the column.*
- **F7 MEDIUM — type drift:** `Order` missing `paid_at`, `payout_recomputed_at`, `promo_funded_by`, `promo_merchant_share_pct`; `OrderItem` missing `original_price` (so no strike-through price can render); `types/supabase.ts:335` `payment_method` omits `'wallet'`; `favorite_items.Relationship` points at a non-existent `menu_items`. Nothing crashes; all additive.
- **F8b LOW** — no `UNIQUE` on `reviews(order_id)`; the TOCTOU `canReview` + `.maybeSingle()` can wedge the Rate button.
- **F11b LOW** — the history trigger omits `confirmed`/`delivered`/`cancelled`, so those rows have no timestamp. `StatusStepper` degrades cleanly (state from current status, timestamps only from history).

---

## Recommended order of work

1. **B1** — EF column name + `.error` check. *(proves out in the lab)*
2. **B1 hardening** — scope the option/choice queries to the item; resolve by id in SQL.
3. **B2** — align `platform_fee` between EF and RPC before anyone edits that config.
4. **B4** — `data ?? {}`. Two characters, unblocks the whole notification centre.
5. **B3** — rename the two `option_group_name_*` fields + the one call site.
6. **B5** — add `order_number` to the select.
7. **B6, B7** — pagination and cache key.
8. **Address F1, F2, F3** — onboarding escape, undo reconciliation, visible failures.
9. `119:243` `created_at` → `orders.created_at` + restore `#variable_conflict use_column`. **Not a mobile blocker** — do it, but it is not why checkout is broken.
10. Type-drift additions (F7/F8) — purely additive, no behaviour change.

---

## Open questions

1. **Is production actually on this schema?** Everything above is derived from `schema-final.sql` + a local 120-migration replay. `SELECT count(*) FROM pg_policies WHERE tablename IN ('orders','addresses')` on the live project would settle it in one query.
2. **Do real merchants have priced options?** One query decides whether B1 is "a silent minority of digital payments fail" or "all of them": `SELECT count(*) FROM item_option_choices WHERE price_modifier <> 0 AND is_available`.
3. **Is `platform_fee_percentage` non-zero anywhere?** Decides whether B2 is live or latent.
4. **Is web a shipping target?** `AddAddressForm.tsx:316` branches on `Platform.OS !== 'web'`; if web ships, address entry is currently impossible there.
5. **How many orders will a returning customer have?** Decides whether B6 matters at launch or at month two.
6. **Does anything set `reviews.is_visible = true`?** If no admin path does, merchant review *lists* stay empty for everyone but the reviewer.

---

## Lab note

`seed_data.py` must be run with `--analyze` **after** `reset_db.py`, in that order. Running it without `--analyze` leaves stale planner statistics and fails two `test_08_scale.py` index-plan tests. Final state after this analysis: **190 passed, 2 skipped.**