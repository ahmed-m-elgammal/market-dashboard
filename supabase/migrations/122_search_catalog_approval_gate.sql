-- Migration 122: gate search_catalog on approval_status (BUG-13 follow-up)
--
-- THE BUG
--   Migration 109 fixed the `merchants_read_active` RLS policy to require
--   `is_active AND approval_status = 'approved'`. That policy protects the
--   `anon` and `authenticated` roles.
--
--   It does NOT protect search_catalog, because search_catalog is
--   SECURITY DEFINER. A SECURITY DEFINER function runs as its owner, which
--   bypasses RLS entirely. All six merchant filters inside it checked
--   `m.is_active` alone, so a merchant with approval_status = 'pending' was
--   returned by search to any signed-in customer even though the RLS policy
--   correctly hid it from a direct table read. The policy and the function
--   disagreed, and the function won because it bypassed the policy.
--
-- COMPANION EDGE-FUNCTION FIXES (same bug, different transport)
--   - get-merchant-feed      filtered is_active only
--   - place-order            checked is_active, not approval_status
--   - get-order-fee-preview  checked is_active, not approval_status
--
--   All three run on the service_role client, which also bypasses RLS. This
--   migration is the durable fix: one rule every catalog reader goes through,
--   rather than relying on each caller to remember.
--
-- WHY BOTH COLUMNS
--   approval_status is the onboarding judgement (has a human reviewed this
--   vendor). is_active is the runtime kill-switch for an approved vendor. Both
--   must pass: is_active alone is what caused the leak, and approval alone
--   would resurface a suspended vendor.
--
-- HOW THIS FILE WAS BUILT
--   The function body below is the LIVE definition extracted verbatim from
--   dashborad/schema-final.sql and patched by appending the approval condition
--   to each of the six merchant filters. Nothing was rewritten by hand.
--
--   That is deliberate. A hand-written replacement for this function called
--   public.trigram_similarity() and public.count_searchable_merchants() --
--   neither exists in this schema -- and restructured the fuzzy passes. It
--   would have failed to compile and broken search for everyone. A patch of six
--   added conditions has no room for that class of mistake.
--
--   Regenerate with: node scripts/build-migration-122.mjs
--
-- DATA IMPACT
--   Narrowing only. Any merchant currently pending+active stops appearing in
--   search immediately, which is the intended behaviour. Check before applying:
--
--     SELECT approval_status, is_active, count(*)
--     FROM public.merchants
--     WHERE is_active AND approval_status <> 'approved'
--     GROUP BY 1, 2;
--
-- NOTE ON MIGRATION 121
--   121 declares a different-arity overload of search_catalog whose body
--   raises 'Migration 121 placeholder - replaced below'. It does not replace
--   the live 12-argument definition this migration targets. That placeholder is
--   a separate pre-existing problem, deliberately left alone here.
--
-- Rollback: drop the six `AND m.approval_status = 'approved'` conditions.
--           Safe at any time -- relaxing a read filter cannot orphan data.

CREATE OR REPLACE FUNCTION public.search_catalog(p_query text, p_city text DEFAULT NULL::text, p_category text DEFAULT NULL::text, p_lat numeric DEFAULT NULL::numeric, p_lng numeric DEFAULT NULL::numeric, p_limit_merchants integer DEFAULT 20, p_limit_items integer DEFAULT 10, p_include_items boolean DEFAULT true, p_fuzzy_threshold numeric DEFAULT 0.30, p_merchant_id uuid DEFAULT NULL::uuid, p_include_suggestions boolean DEFAULT true, p_suggestion_max integer DEFAULT 8) RETURNS json
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
DECLARE
  v_norm TEXT;
  v_like TEXT;     -- escaped, bounded by %..%  (exact pass)
  v_prefix TEXT;   -- escaped, trailing wildcard (suggestions)
  v_bbox BOOLEAN := p_lat IS NOT NULL AND p_lng IS NOT NULL;
  v_merchants JSON := '[]'::json;
  v_items JSON := '[]'::json;
  v_suggestions JSON := '[]'::json;
  v_fuzzy_used BOOLEAN := FALSE;
  v_fuzzy_top TEXT := NULL;
BEGIN
  -- ── Guards (mirror validateSearchRequest; the EF validates first) ──
  IF p_query IS NULL OR length(trim(p_query)) < 2 OR length(trim(p_query)) > 80 THEN
    RAISE EXCEPTION 'INVALID_QUERY';
  END IF;
  v_norm := public.normalize_search_text(p_query);
  IF v_norm IS NULL OR v_norm = '' THEN
    RAISE EXCEPTION 'INVALID_QUERY';
  END IF;

  -- LIKE wildcard escaping: the query is user-controlled text; % and _ must
  -- match literally (the feed escapes PostgREST filter syntax for the same
  -- reason). Bound parameters prevent injection; this prevents wildcard
  -- blowout (e.g. "a%b" matching every name containing a…b).
  v_like := '%' || replace(replace(replace(v_norm, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  v_prefix := replace(replace(replace(v_norm, '\', '\\'), '%', '\%'), '_', '\_') || '%';

  -- ── Clamp arguments to plan hard limits ──
  p_limit_merchants := LEAST(GREATEST(COALESCE(p_limit_merchants, 20), 1), 30);
  p_limit_items := LEAST(GREATEST(COALESCE(p_limit_items, 0), 0), 20);
  p_suggestion_max := LEAST(GREATEST(COALESCE(p_suggestion_max, 0), 0), 20);
  p_category := NULLIF(p_category, 'all');

  -- ── Merchant exact pass ──
  SELECT COALESCE(json_agg(x ORDER BY x.created_at DESC), '[]'::json)
    INTO v_merchants
    FROM (
      SELECT b.id, b.name_ar, b.name_en, b.category, b.logo_url, b.cover_url,
             b.description_ar, b.description_en, b.address, b.lat, b.lng,
             b.city, b.area, b.phone, b.is_active, b.rating, b.rating_count,
             b.min_order_amount, b.estimated_delivery_minutes,
             b.delivery_fee_override, b.commission_pct, b.delivery_radius_km,
             b.estimated_prep_time_minutes, b.created_at, b.updated_at,
             'exact'::text AS match_tier
        FROM (
          SELECT m.*
            FROM public.merchants m
           WHERE m.is_active AND m.approval_status = 'approved'
             AND (
               (v_bbox AND m.lat BETWEEN p_lat - 0.45 AND p_lat + 0.45
                                   AND m.lng BETWEEN p_lng - 0.52 AND p_lng + 0.52)
               OR (NOT v_bbox AND p_city IS NOT NULL AND m.city ILIKE p_city)
               OR (NOT v_bbox AND p_city IS NULL)
             )
              AND (p_category IS NULL OR m.category = p_category)
              AND (p_merchant_id IS NULL OR m.id = p_merchant_id)
              -- Word-AND over combined normalized names: every query word must
              -- appear somewhere (name_ar or name_en). Plain substring cannot
              -- match description-style queries; combined word-AND can.
              AND NOT EXISTS (
                SELECT 1 FROM unnest(string_to_array(v_norm, ' ')) AS w
                 WHERE w <> ''
                   AND (COALESCE(public.normalize_search_text(m.name_en), '') || ' ' ||
                        COALESCE(public.normalize_search_text(m.name_ar), ''))
                       NOT ILIKE '%' || REPLACE(REPLACE(REPLACE(w, '\', '\\'), '%', '\%'), '_', '\_') || '%' ESCAPE '\'
              )
            ORDER BY m.created_at DESC
            LIMIT p_limit_merchants
         ) b
     ) x;

  -- ── Item exact pass (inherits geo/category gates from parent merchant) ──
  IF p_include_items AND p_limit_items > 0 THEN
    SELECT COALESCE(json_agg(x ORDER BY x.popularity_score DESC, x.created_at DESC), '[]'::json)
      INTO v_items
      FROM (
        SELECT b.id, b.merchant_id, b.name_ar, b.name_en, b.price, b.image_url,
               b.popularity_score, b.created_at, 'exact'::text AS match_tier,
               b.merchant_name_ar, b.merchant_name_en,
               b.merchant_lat, b.merchant_lng,
               b.merchant_delivery_radius_km, b.merchant_city
          FROM (
            SELECT i.id, i.merchant_id, i.name_ar, i.name_en, i.price,
                   i.image_url, i.popularity_score, i.created_at,
                   m.name_ar AS merchant_name_ar, m.name_en AS merchant_name_en,
                   m.lat AS merchant_lat, m.lng AS merchant_lng,
                   m.delivery_radius_km AS merchant_delivery_radius_km,
                   m.city AS merchant_city
              FROM public.items i
              JOIN public.merchants m ON m.id = i.merchant_id AND m.is_active AND m.approval_status = 'approved'
             WHERE i.is_available
               AND (
                 (v_bbox AND m.lat BETWEEN p_lat - 0.45 AND p_lat + 0.45
                                     AND m.lng BETWEEN p_lng - 0.52 AND p_lng + 0.52)
                 OR (NOT v_bbox AND p_city IS NOT NULL AND m.city ILIKE p_city)
                 OR (NOT v_bbox AND p_city IS NULL)
               )
                AND (p_category IS NULL OR m.category = p_category)
                AND (p_merchant_id IS NULL OR m.id = p_merchant_id)
                -- Word-AND over combined normalized name+description: every
                -- query word must appear somewhere (names or descriptions).
                -- Lets description-only queries match (name carries the
                -- marker word, description carries the dish word).
                AND NOT EXISTS (
                  SELECT 1 FROM unnest(string_to_array(v_norm, ' ')) AS w
                   WHERE w <> ''
                     AND (COALESCE(public.normalize_search_text(i.name_en), '') || ' ' ||
                          COALESCE(public.normalize_search_text(i.name_ar), '') || ' ' ||
                          COALESCE(public.normalize_search_text(COALESCE(i.description_en, '')), '') || ' ' ||
                          COALESCE(public.normalize_search_text(COALESCE(i.description_ar, '')), ''))
                         NOT ILIKE '%' || REPLACE(REPLACE(REPLACE(w, '\', '\\'), '%', '\%'), '_', '\_') || '%' ESCAPE '\'
                )
              ORDER BY i.popularity_score DESC, i.created_at DESC
              LIMIT p_limit_items
           ) b
       ) x;
   END IF;

  -- ── Fuzzy pass: ONLY on zero exact rows, ONLY when enabled ──
  IF json_array_length(v_merchants) = 0 AND json_array_length(v_items) = 0
     AND COALESCE(p_fuzzy_threshold, 0) > 0 THEN

    -- Fuzzy merchants, best similarity first.
    SELECT COALESCE(json_agg(x ORDER BY x.sim DESC, x.rating_count DESC), '[]'::json)
      INTO v_merchants
      FROM (
        SELECT b.id, b.name_ar, b.name_en, b.category, b.logo_url, b.cover_url,
               b.description_ar, b.description_en, b.address, b.lat, b.lng,
               b.city, b.area, b.phone, b.is_active, b.rating, b.rating_count,
               b.min_order_amount, b.estimated_delivery_minutes,
               b.delivery_fee_override, b.commission_pct, b.delivery_radius_km,
               b.estimated_prep_time_minutes, b.created_at, b.updated_at,
               'fuzzy'::text AS match_tier, b.sim
          FROM (
            SELECT m.*,
                   GREATEST(
                     similarity(public.normalize_search_text(m.name_en), v_norm),
                     similarity(public.normalize_search_text(m.name_ar), v_norm)
                   ) AS sim
              FROM public.merchants m
             WHERE m.is_active AND m.approval_status = 'approved'
               AND (
                 (v_bbox AND m.lat BETWEEN p_lat - 0.45 AND p_lat + 0.45
                                     AND m.lng BETWEEN p_lng - 0.52 AND p_lng + 0.52)
                 OR (NOT v_bbox AND p_city IS NOT NULL AND m.city ILIKE p_city)
                 OR (NOT v_bbox AND p_city IS NULL)
               )
               AND (p_category IS NULL OR m.category = p_category)
               AND (p_merchant_id IS NULL OR m.id = p_merchant_id)
               AND GREATEST(
                     similarity(public.normalize_search_text(m.name_en), v_norm),
                     similarity(public.normalize_search_text(m.name_ar), v_norm)
                   ) >= p_fuzzy_threshold
             ORDER BY sim DESC
             LIMIT p_limit_merchants
          ) b
      ) x;

    IF json_array_length(v_merchants) > 0 THEN
      v_fuzzy_used := TRUE;
      -- did-you-mean = display name of the best fuzzy merchant.
      SELECT (v_merchants -> 0 ->> 'name_en') INTO v_fuzzy_top;
    ELSE
      -- Fuzzy items (same structure; name OR description similarity).
      SELECT COALESCE(json_agg(x ORDER BY x.sim DESC, x.popularity_score DESC), '[]'::json)
        INTO v_items
        FROM (
          SELECT b.id, b.merchant_id, b.name_ar, b.name_en, b.price, b.image_url,
                 b.popularity_score, b.created_at, 'fuzzy'::text AS match_tier,
                 b.merchant_name_ar, b.merchant_name_en,
                 b.merchant_lat, b.merchant_lng,
                 b.merchant_delivery_radius_km, b.merchant_city, b.sim
            FROM (
              SELECT i.id, i.merchant_id, i.name_ar, i.name_en, i.price,
                     i.image_url, i.popularity_score, i.created_at,
                     m.name_ar AS merchant_name_ar, m.name_en AS merchant_name_en,
                     m.lat AS merchant_lat, m.lng AS merchant_lng,
                     m.delivery_radius_km AS merchant_delivery_radius_km,
                     m.city AS merchant_city,
                     GREATEST(
                       similarity(public.normalize_search_text(i.name_en), v_norm),
                       similarity(public.normalize_search_text(i.name_ar), v_norm),
                       similarity(public.normalize_search_text(COALESCE(i.description_en, '')), v_norm),
                       similarity(public.normalize_search_text(COALESCE(i.description_ar, '')), v_norm)
                     ) AS sim
                FROM public.items i
                JOIN public.merchants m ON m.id = i.merchant_id AND m.is_active AND m.approval_status = 'approved'
               WHERE i.is_available
                 AND (
                   (v_bbox AND m.lat BETWEEN p_lat - 0.45 AND p_lat + 0.45
                                       AND m.lng BETWEEN p_lng - 0.52 AND p_lng + 0.52)
                   OR (NOT v_bbox AND p_city IS NOT NULL AND m.city ILIKE p_city)
                   OR (NOT v_bbox AND p_city IS NULL)
                 )
                 AND (p_category IS NULL OR m.category = p_category)
                 AND (p_merchant_id IS NULL OR m.id = p_merchant_id)
                 AND GREATEST(
                       similarity(public.normalize_search_text(i.name_en), v_norm),
                       similarity(public.normalize_search_text(i.name_ar), v_norm),
                       similarity(public.normalize_search_text(COALESCE(i.description_en, '')), v_norm),
                       similarity(public.normalize_search_text(COALESCE(i.description_ar, '')), v_norm)
                     ) >= p_fuzzy_threshold
               ORDER BY sim DESC
               LIMIT p_limit_items
            ) b
        ) x;

      IF json_array_length(v_items) > 0 THEN
        v_fuzzy_used := TRUE;
        -- did-you-mean = merchant name behind the best fuzzy item.
        SELECT (v_items -> 0 ->> 'merchant_name_en') INTO v_fuzzy_top;
      END IF;
    END IF;
  END IF;

  -- ── Suggestions (trending + merchant-name prefixes, normalized dedupe) ──
  IF COALESCE(p_include_suggestions, FALSE) AND p_suggestion_max > 0 THEN
    SELECT COALESCE(json_agg(s.query ORDER BY s.c DESC, s.query ASC), '[]'::json)
      INTO v_suggestions
      FROM (
        SELECT DISTINCT ON (public.normalize_search_text(u.query))
               u.query, u.c
          FROM (
            SELECT sq.query, COUNT(*)::int AS c
              FROM public.search_queries sq
             WHERE sq.created_at >= now() - interval '30 days'
               AND sq.has_results
               AND (p_city IS NULL OR sq.city = p_city)
               AND public.normalize_search_text(sq.query) LIKE v_prefix
               AND public.normalize_search_text(sq.query) <> v_norm
             GROUP BY sq.query
             UNION ALL
             SELECT m.name_en, 0::int
               FROM public.merchants m
              WHERE m.is_active AND m.approval_status = 'approved'
                AND public.normalize_search_text(m.name_en) LIKE v_prefix
                AND public.normalize_search_text(m.name_en) <> v_norm
             UNION ALL
             SELECT m.name_ar, 0::int
               FROM public.merchants m
              WHERE m.is_active AND m.approval_status = 'approved'
                AND public.normalize_search_text(m.name_ar) LIKE v_prefix
                AND public.normalize_search_text(m.name_ar) <> v_norm
          ) u
         ORDER BY public.normalize_search_text(u.query), u.c DESC, u.query ASC
       ) s;
  END IF;

  RETURN json_build_object(
    'match_mode',
      CASE WHEN v_fuzzy_used THEN 'fuzzy'
           WHEN json_array_length(v_merchants) > 0 OR json_array_length(v_items) > 0 THEN 'exact'
           ELSE 'none' END,
    'merchants', v_merchants,
    'items', v_items,
    'fuzzy_top', v_fuzzy_top,
    'suggestions', v_suggestions,
    -- surfaced so the Edge Function can log it into search_queries.normalized_query
    -- (single source of truth for normalization — no JS reimplementation)
    'normalized_query', v_norm
  );
END;
$$;
COMMENT ON FUNCTION public.search_catalog(TEXT, TEXT, TEXT, NUMERIC, NUMERIC, INT, INT, BOOLEAN, NUMERIC, UUID, BOOLEAN, INT) IS
  'BUG-13 follow-up (migration 122): SECURITY DEFINER bypasses the merchants_read_active RLS policy, so search_catalog must gate merchants on approval_status itself. Six merchant filters previously checked is_active only and returned pending vendors to signed-in customers.';
