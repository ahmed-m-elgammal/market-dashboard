# Dataflow Findings — verified against the local lab

**Date:** 2026-10-03
**Lab:** `dashborad/test` — PostgreSQL 18.6, `marketak_test`, 120 migrations replayed, ~200k seeded rows
**Verification suite:** `test_11_verify_findings.py` — 29 tests, all passing
**Method:** every DB-verifiable claim is proven by *executing* the function or introspecting the live catalog, not by reading source. Each test asserts the bug **exists**, so it fails loudly once fixed (suite convention, see README).

```
190 passed, 2 skipped in 1.77s      # full suite incl. 29 new verification tests
```

---

## Headline: the audit's priority order was wrong

Three money-critical RPCs **cannot execute at all**. This was not in the original audit — it was found by running the functions rather than reading them.

| RPC | Fails with | Consequence |
|---|---|---|
| `place_order_with_items` | `42P18 column reference "created_at" is ambiguous` | **Checkout is 100% dead.** No order, no order_items, no promo usage. |
| `create_driver_settlement` | `42P18 column reference "settlement_id" is ambiguous` | **Driver settlements have never run.** Every `driver_earnings` row stays `pending` forever. |
| `adjust_wallet_balance` | `42P18 column reference "user_id" is ambiguous` | **Every wallet credit/debit is a silent no-op.** No `wallet_audit_log` row. |

**Cause.** All three use `RETURNS TABLE(...)`, which makes the output column names PL/pgSQL *variables*. A later bare column reference is then unresolvable:

```
place_order_with_items      RETURNS TABLE(id uuid, order_number text, created_at timestamptz)
  line ~100:  AND created_at > NOW() - interval    -- ambiguous: variable vs orders.created_at

create_driver_settlement    RETURNS TABLE(settlement_id uuid, net_payable numeric, delivery_count integer)
  NOT EXISTS (... FROM driver_settlement_earnings WHERE settlement_id = v_settlement_id)

adjust_wallet_balance       RETURNS TABLE(... user_id ...)
  UPDATE wallet_audit_log ... WHERE user_id = p_user_id
```

This is the same defect class as BUG-REPORT.md §5 (where `id` was ambiguous until migration 119). Migration 119 fixed `id`; `created_at` was missed, and the same class exists in two further functions. `test_V0e` proves the detection method is sound: `cancel_order` has an identically-shaped bare reference (`AND status = v_order.status`, line 134) and **executes fine** — so this must be proven by running, never by grepping.

**Fix:** qualify every column reference (`o.created_at`, `dse.settlement_id`, `walu.user_id`), or rename the OUT params (`v_created_at`). Then run `test_11` — V6/V7/V21 are latent behind this and go live the moment it is fixed.

---

## Verified true — behavioural proof (executed)

| ID | Finding | Proof |
|---|---|---|
| **V0** | `place_order_with_items` raises `ambiguous` on every call | called it; `23514`/`42P18`; 0 orders written |
| **V0c** | `create_driver_settlement` raises `ambiguous` | called it; 0 settlements written |
| **V0d** | `adjust_wallet_balance` raises `ambiguous` | called it; balance stayed `0.00`, 0 audit rows |
| **V8b** | `create_merchant_payout` pays **unpaid** delivered orders | `payment_status='pending'`, `merchant_payout=85` → payout row `order_count=1, net_payable=85.00` |
| **V9** | `cancel_order` never releases promo usage | after cancel: `promo_code_usage` row still present, `current_usage` still `1` |
| **V10** | `cancel_order` stamps a terminal refund status no sweeper reads | paid card order → `refund_status='refunded'`; sweep predicate `IN ('pending_refund','refund_failed')` matches **0 rows** |
| **V12b** | Customer can self-publish a review and forge `moderated_by` | inserted `is_visible=true, moderated_by=<self>` as the author; both stuck |
| **V13** | `notifications.data NOT NULL` rejects the EF's `data \|\| null` | explicit `NULL` → not-null violation; `'{}'::jsonb` succeeds |
| **V2b** | `cancel_order` raises for `('ready','system')` | called with `p_initiator_role='system'` on a `ready` order → `No cancellation rule found` |

## Verified true — catalog/introspection proof

| ID | Finding | Evidence |
|---|---|---|
| **V1** | `item_options` has no `group_name_ar`/`group_name_en` | columns are `name_ar`,`name_en`; 0 `group%` columns. `place-order:576` selects the non-existent pair and swallows the error at `:584` |
| **V2** | No `('ready','system')` row in `cancellation_rules` | `system` rows are only `confirmed`,`pending`. The `ready` sweep rule fails 100% of the time |
| **V3** | `search_catalog` ignores `approval_status` | **0 occurrences** in the live 12-arg body |
| **V4** | `search_catalog` ignores `deleted_at` | **0 occurrences**; items also never join `categories`, so a deleted/unavailable category does not hide its items |
| **V5** | `search_catalog` returns `price`, not `COALESCE(discount_price, price)` | **0 occurrences** of `discount_price` |
| **V6** | Settlement double-counts cancellation compensation | `v_net := v_gross - v_platform_fee + v_cancel_comp` with an unfiltered `SUM(de.delivery_fee_earned)`. *Latent behind V0c* |
| **V7** | Inclusive overlap guard vs half-open window | `AND period_end >= p_period_start` vs `created_at >= start AND created_at < end`. *Latent behind V0c* |
| **V11 / V11b** | Wallet audit hardcodes `change_type='correction'`, `changed_by=NULL`, no `reference_*` | one row written with `change_type='correction'`; `DISTINCT change_type` across the table returns only `correction` |
| **V12** | `reviews` INSERT policy constrains no visibility | `polcmd='a'` policy's qual+with_check mention `customer_id` but not `is_visible` |
| **V14** | Role-escalation trigger guards only `role='driver'` | `WHEN (new.role = 'driver')` — escalation to `admin` is unguarded |
| **V16 / V16b** | No order-writing function enforces promo `min_order_amount`/geo | `min_order_amount` absent from `place_order_with_items`; no order-writing public function references it |
| **V19** | `merchant_payouts` breakdown ≠ `net_payable` | commission uses `SUM(subtotal * pct/100)` on the **full** subtotal; net uses `SUM(merchant_payout)`, which is derived post-discount |

## New finding surfaced during verification

**`search_catalog` has two overloads, and one is a placeholder stub.**

```
search_catalog(9 args)  -> jsonb   body: RAISE EXCEPTION 'Migration 121 placeholder - replaced below'
search_catalog(12 args) -> json    the real implementation
```

Migration 121 shipped the soft-delete fix as a *new 9-arg overload* whose body only raises, without replacing the 12-arg implementation — so the fix does nothing. This answers open question #1 from the original audit. It is also a live hazard on its own: PostgREST resolves RPC by parameter-name set, so which function runs depends on the exact names the caller sends.

---

## Disproven / corrected during verification

| Claim | Verdict |
|---|---|
| "59 FK columns lack an index" (my own first pass) | **FALSE — my script had a variable-shadowing bug.** Verified present: `orders(customer_id, created_at DESC)`, `driver_earnings(driver_id, created_at DESC)`, `order_items(order_id)`, `notifications(user_id, is_read, created_at DESC)`, `promo_code_usage(user_id, promo_code_id)`. Discarded entirely. |
| "`driver_settlements` / `merchant_payouts` may lack the anti-double-payment UNIQUE constraint" (sub-agent) | **FALSE.** Both exist: `UNIQUE (driver_id, period_start, period_end)`, `UNIQUE (merchant_id, period_start, period_end)`. The `CREATE TABLE IF NOT EXISTS` concern is unfounded. |
| "`wallet_audit_log` is never written" (sub-agent) | **FALSE as stated.** A trigger writes it. Corrected to: the trigger *does* write it, but hardcodes `change_type='correction'` with no reference — V11. |
| "59 FK columns unindexed" regex sweep | My detection was unreliable; the corrected per-table check showed indexing is good. |

---

## NOT verifiable by a Postgres lab — unproven, treat as code review only

These live in TypeScript or in PostgREST/gateway behaviour. A Deno test harness or a running EF is required. **Do not treat these as confirmed.**

- Error swallowing on money-critical inserts (`driver_earnings`, `order_status_history`, `driver_order_requests`) — `supabase-js` resolves on DB errors, so an undestructured `error` fails silently. *(V13/V9 show what that hides.)*
- Rate limiting: webhook keying on client-controllable `x-forwarded-for`; `send-notification`'s limiter being unreachable; the 1000-row PostgREST truncation on 5+ unscoped reads.
- `city: "%"` returning every merchant — PostgREST `.ilike()` semantics, not PG.
- Paymob HMAC correctness and timing-safety.
- EF-level IDOR and the `accept` double-claim race (`driver-actions:434-457`).
- National-ID encryption correctness (`admin-driver:249-274`).
- Admin gate gaps: `profiles.is_active` unchecked, `admin_sessions` never read.
- `is_overnight` ignored in JS, hardcoded `cairoOffset = 2` vs Africa/Cairo DST.
- Cron behaviour: window hardcoding, no catch-up, `auto-expiry-promos` irreversibility, loyalty code collision.

---

## Severity, revised

The original ranking put option-pricing (V1) and webhook/refund races at the top. Revised:

1. **V0 / V0c / V0d — three RPCs cannot execute.** Nothing else matters until these are fixed: checkout, driver settlement, and wallet are all non-functional. Fix first; it is a small, mechanical diff.
2. **V8b, V9, V10, V13 — live money loss**, all behaviourally proven. V10 in particular silently loses customer refunds.
3. **V3, V4, V5, V12b — live security/correctness exposure** on customer-facing reads.
4. **V6, V7, V19, V21 — real but latent** behind V0c. Fix them in the same pass, or they activate silently the moment V0c lands.
5. Everything in the NOT-verifiable list needs a Deno harness before it can be actioned.

## Still open

1. **Does the mobile client call `place-order` at all?** If checkout is dead end-to-end, V1/V16 are unreachable in practice — but that is a much larger product problem than any single bug here.
2. **Is there real order data in the cloud project?** If `place_order_with_items` never executed, `orders` should be empty or contain only rows from before migration 026. Worth confirming against production: `SELECT count(*) FROM orders;`
3. **`db-max-rows`** on the hosted project (default 1000) — decides whether the truncation findings are live or latent.
4. **Was any `adjust_wallet_balance` path ever exercised?** If yes, balances may be silently wrong in production with no audit trail.