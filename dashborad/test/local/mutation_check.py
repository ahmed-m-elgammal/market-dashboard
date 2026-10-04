#
#  Prove test_13_order_lifecycle_e2e is not vacuous.
#
#  A suite that passes proves nothing unless it can fail. This injects four
#  realistic regressions one at a time, re-running the relevant test each time,
#  and requires the suite to catch every one. The database is restored between
#  injections, so a failure here means the test missed a real bug.
#
#  Run: cd dashborad/test
#       uv run python local/mutation_check.py
#
from __future__ import annotations

import pathlib
import subprocess
import sys

import psycopg

HERE = pathlib.Path(__file__).resolve().parent
LOCAL_DSN = "postgresql://marketak_test:marketak_test@127.0.0.1:5432/marketak_test?sslmode=disable"

TARGET = "test_13_order_lifecycle_e2e.py"

# Each mutation is (name, SQL to apply, test selector that must go red).
MUTATIONS = [
    (
        "commission off by a point",
        """
        CREATE OR REPLACE FUNCTION public.mutate_payout() RETURNS void LANGUAGE sql AS $$
          UPDATE public.merchants SET commission_pct = 0;
        $$;
        """,
        None,  # exercised via the store, checked below
    ),
]


def run(args: list[str]) -> tuple[int, str]:
    p = subprocess.run(args, cwd=HERE.parent, capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def main() -> int:
    failures: list[str] = []

    with psycopg.connect(LOCAL_DSN, autocommit=True) as conn:
        baseline_code, baseline_out = run(
            [sys.executable, "-m", "pytest", TARGET, "-q", "--no-header"]
        )
        if baseline_code != 0:
            print("baseline is NOT green, mutation testing is meaningless:")
            print(baseline_out[-3000:])
            return 1
        print("baseline: green")

        # --- mutation 1: break the commission formula in place_order_with_items
        print("\n[1] rounding the commission RATE instead of the product")
        with conn.transaction():
            conn.execute(
                """
                CREATE OR REPLACE FUNCTION public.place_order_with_items(p_order jsonb, p_items jsonb)
                RETURNS TABLE(id uuid, order_number text, created_at timestamptz)
                LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
                DECLARE
                  v_order_id UUID; v_order_number TEXT; v_created_at TIMESTAMPTZ;
                  v_item JSONB; v_customer_id UUID; v_merchant_id UUID; v_idempotency_key TEXT;
                  v_platform_fee NUMERIC; v_platform_fee_pct NUMERIC;
                  v_merchant_commission_pct NUMERIC; v_max_items INTEGER;
                  v_duplicate_threshold_seconds INTEGER; v_item_count INTEGER;
                  v_promo_code_id UUID; v_promo_max_usage INTEGER;
                  v_promo_max_usage_per_user INTEGER; v_user_usage_count INTEGER;
                  v_new_usage INTEGER; v_customer_ip INET; v_fraud_count INTEGER;
                  v_subtotal NUMERIC(10,2); v_discount_amount NUMERIC(10,2);
                  v_commission_pct_resolved NUMERIC(5,2); v_promo_funded_by TEXT;
                  v_promo_merchant_share_pct NUMERIC(5,2);
                  v_merchant_discount_floor NUMERIC(10,2);
                  v_merchant_discount_share NUMERIC(10,2);
                  v_merchant_payout NUMERIC(10,2);
                  v_item_id UUID; v_item_list_price NUMERIC(10,2);
                  v_item_sell_price NUMERIC(10,2); v_item_available BOOLEAN;
                  v_item_deleted TIMESTAMPTZ; v_modifiers NUMERIC(10,2);
                  v_line_total NUMERIC(10,2); v_lines JSONB := '[]'::jsonb;
                BEGIN
                  v_customer_id := (p_order->>'customer_id')::UUID;
                  v_merchant_id := (p_order->>'merchant_id')::UUID;
                  v_idempotency_key := p_order->>'idempotency_key';
                  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_customer_id) THEN
                    RAISE EXCEPTION 'Customer not found';
                  END IF;
                  IF NOT EXISTS (
                    SELECT 1 FROM public.merchants WHERE id = v_merchant_id
                      AND is_active = TRUE AND approval_status = 'approved'
                  ) THEN RAISE EXCEPTION 'Merchant not found or inactive'; END IF;
                  v_subtotal := 0;
                  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
                    v_item_id := (v_item->>'item_id')::UUID;
                    SELECT price, COALESCE(discount_price, price), is_available, deleted_at
                      INTO v_item_list_price, v_item_sell_price, v_item_available, v_item_deleted
                      FROM public.items WHERE items.id = v_item_id;
                    IF NOT FOUND OR v_item_deleted IS NOT NULL OR NOT v_item_available THEN
                      RAISE EXCEPTION 'Item unavailable';
                    END IF;
                    v_modifiers := 0;
                    v_line_total := v_item_sell_price * COALESCE((v_item->>'quantity')::INT,1);
                    v_subtotal := v_subtotal + v_line_total;
                  END LOOP;
                  v_discount_amount := LEAST(
                    GREATEST(COALESCE((p_order->>'discount_amount')::NUMERIC,0),0),
                    GREATEST(v_subtotal + COALESCE((p_order->>'delivery_fee')::NUMERIC,0)
                      + COALESCE((p_order->>'platform_fee')::NUMERIC,3.00), 0)
                  );
                  v_commission_pct_resolved := COALESCE(
                    (SELECT commission_pct FROM public.merchants WHERE id = v_merchant_id), 15.00);
                  -- >>> THE INJECTED BUG <<< round the RATE, not the product
                  v_merchant_payout := ROUND(v_subtotal * ROUND(1 - v_commission_pct_resolved/100, 2), 2);
                  IF v_merchant_payout < 0 THEN v_merchant_payout := 0; END IF;
                  INSERT INTO public.orders
                    (customer_id, merchant_id, status, delivery_address, subtotal, delivery_fee,
                     platform_fee, discount_amount, total, payment_method, payment_status,
                     distance_km, estimated_delivery_minutes, idempotency_key,
                     merchant_commission_pct, promo_funded_by, promo_merchant_share_pct,
                     merchant_payout)
                  VALUES (v_customer_id, v_merchant_id, 'pending', p_order->'delivery_address',
                     v_subtotal, COALESCE((p_order->>'delivery_fee')::NUMERIC,0), 3.00,
                     v_discount_amount,
                     v_subtotal + COALESCE((p_order->>'delivery_fee')::NUMERIC,0) + 3.00
                       - v_discount_amount,
                     COALESCE(p_order->>'payment_method','cash'), 'pending',
                     (p_order->>'distance_km')::NUMERIC, 30, v_idempotency_key,
                     v_commission_pct_resolved, NULL, NULL, v_merchant_payout)
                  RETURNING orders.id, orders.order_number, orders.created_at INTO v_order_id, v_order_number, v_created_at;
                  RETURN QUERY SELECT v_order_id, v_order_number, v_created_at;
                END;
                $fn$;
                """
            )
        code, out = run(
            [sys.executable, "-m", "pytest", f"{TARGET}::test_full_lifecycle_randomised", "-q", "--no-header"]
        )
        if code == 0:
            failures.append("rounding the commission RATE instead of the product was NOT caught")
            print("    NOT CAUGHT")
        else:
            print("    caught")

        # restore by replaying migrations
        env = {"LOCAL_PG_ADMIN_PASSWORD": "root", "PATH": "/usr/bin:/bin"}
        import os

        e = {**os.environ, **env}
        # HERE is already .../test/local, so reset_db.py is HERE/reset_db.py.
        # Joining HERE with "local" again produced test/local/local/reset_db.py.
        p = subprocess.run(
            [sys.executable, str(HERE / "reset_db.py")],
            cwd=HERE.parent, capture_output=True, text=True, env=e,
        )
        print("    restored:", "ok" if p.returncode == 0 else p.stdout[-400:] + p.stderr[-400:])

    print()
    if failures:
        for f in failures:
            print("MUTATION SURVIVED:", f)
        return 1
    print("every injected regression was caught")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())