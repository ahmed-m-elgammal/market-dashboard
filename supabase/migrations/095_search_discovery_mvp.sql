-- Migration 095: Search & Discovery MVP
-- Implements docs/plans/search-discovery-implementation-plan.md §6 (Workstream A).
--
-- What this adds (all additive — nothing existing is modified):
--   1. f_unaccent + normalize_search_text: bilingual (ar/en) search normalization
--      (alef/hamza variants, taa marbuta, alef maqsura, harakat, tatweel,
--      superscript alef, Latin accents, lowercasing) — IMMUTABLE, index-safe.
--   2. 6 GIN trigram expression indexes on merchants/items normalized names
--      (+ item descriptions). Companion to the 016 raw-name indexes, which had
--      zero callers: search previously matched merchant names only (ILIKE).
--   3. search_catalog(p_query, ...): single-round-trip search RPC —
--      exact/prefix pass → fuzzy pass (pg_trgm similarity, only on zero exact
--      rows) → suggestions (trending + merchant-name prefixes). Geo = bbox
--      pre-filter (same ±0.45°/±0.52° constants as get-merchant-feed) or city
--      ILIKE. LIKE wildcards in the user query are escaped (feed's PostgREST
--      escaping has no SQL equivalent — must be done here explicitly).
--   4. search_queries analytics table (RLS on, zero policies → service-role
--      only) + 180-day retention cron.
--   5. get_search_analytics_summary(p_days): aggregate-only ops endpoint data
--      (top queries, top zero-result queries, suggestion candidates).
--   6. 6 platform_config kill switches (F4 degradation ladder in the plan).
--   7. EMBEDDED TEST SUITE: normalization fixtures, metadata/ACL checks, and
--      RPC behavioral tests on marker-prefixed seed data. Marker scoping means
--      prod data can never collide with assertions; any failure RAISEs so the
--      migration aborts loudly and rolls back as a whole (074/075 philosophy).
--
-- Both search functions pin `search_path = public, extensions` because
-- pg_trgm/unaccent objects live in the extensions schema on Supabase, and
-- similarity()/unaccent() must resolve at RPC runtime.

-- =============================================================================
-- 1. NORMALIZATION FUNCTIONS
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS unaccent;

-- unaccent() itself is STABLE (dictionary-dependent), which cannot be used in
-- expression indexes. This wrapper is the standard IMMUTABLE workaround: the
-- 'unaccent' dictionary is resolved via the function's pinned search_path
-- (extensions schema on Supabase) and is static content in practice.
CREATE OR REPLACE FUNCTION public.f_unaccent(p_input TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
STRICT
SET search_path = public, extensions
AS $$
  SELECT unaccent('unaccent', $1)
$$;

-- Bilingual search normalization (ar/en):
--   lower()                        — Latin case folding
--   f_unaccent()                   — Latin accents (café → cafe)
--   translate(أإآٱةى → ااااهي)     — alef/hamza variants fold to bare alef,
--                                    taa marbuta → ha, alef maqsura → ya
--   strip: harakat U+064B-U+0652, tatweel U+0640, superscript alef U+0670
--
-- ⚠️ The strip class is an EXPLICIT character list, NOT a codepoint range:
--    a naive range \u0640-\u0652 would also delete the letters ف ق ك ل م
--    (U+0641-U+0645). Regression-tested in the embedded suite.
CREATE OR REPLACE FUNCTION public.normalize_search_text(p_input TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
STRICT
SET search_path = public, extensions
AS $$
  SELECT trim(
    regexp_replace(
      translate(
        public.f_unaccent(lower(p_input)),
        'أإآٱةى',
        'ااااهي'
      ),
      '[ًٌٍَُِّْـٰ]',  -- U+064B-0652 harakat, U+0640 tatweel, U+0670 sup alef
      '',
      'g'
    )
  )
$$;

-- =============================================================================
-- 2. NORMALIZED EXPRESSION INDEXES (6 GIN trigram)
-- Companion to 016's raw-name indexes. Expression form means the planner uses
-- these only for predicates that call normalize_search_text() exactly — which
-- is what search_catalog does.
-- =============================================================================
CREATE INDEX idx_merchants_name_ar_norm_trgm
  ON public.merchants USING gin (public.normalize_search_text(name_ar) gin_trgm_ops);
CREATE INDEX idx_merchants_name_en_norm_trgm
  ON public.merchants USING gin (public.normalize_search_text(name_en) gin_trgm_ops);
CREATE INDEX idx_items_name_ar_norm_trgm
  ON public.items USING gin (public.normalize_search_text(name_ar) gin_trgm_ops);
CREATE INDEX idx_items_name_en_norm_trgm
  ON public.items USING gin (public.normalize_search_text(name_en) gin_trgm_ops);
CREATE INDEX idx_items_desc_ar_norm_trgm
  ON public.items USING gin (public.normalize_search_text(description_ar) gin_trgm_ops);
CREATE INDEX idx_items_desc_en_norm_trgm
  ON public.items USING gin (public.normalize_search_text(description_en) gin_trgm_ops);

-- =============================================================================
-- 3. search_catalog RPC — the single round-trip search
--
-- Contract (docs/plans/search-discovery-implementation-plan.md §6.3):
--   returns { match_mode, merchants[], items[], fuzzy_top, suggestions[] }
--   - exact pass first (normalized substring on names, descriptions for items)
--   - fuzzy pass ONLY when both exact passes return 0 rows and threshold > 0
--   - suggestions: trending queries (30d, city-scoped, has_results only) +
--     merchant-name prefixes; deduped on normalized form; own query excluded
--   - p_fuzzy_threshold <= 0 disables fuzzy entirely
--
-- Geo (pre-filter only — authoritative delivery-radius exclusion stays in the
-- search-catalog Edge Function via haversine, same as get-merchant-feed):
--   - p_lat + p_lng given → bounding box ±0.45° lat / ±0.52° lng
--   - else p_city given   → city ILIKE
--   - else                → no geo filter
-- =============================================================================
CREATE OR REPLACE FUNCTION public.search_catalog(
  p_query TEXT,
  p_city TEXT DEFAULT NULL,
  p_category TEXT DEFAULT NULL,
  p_lat NUMERIC DEFAULT NULL,
  p_lng NUMERIC DEFAULT NULL,
  p_limit_merchants INT DEFAULT 20,
  p_limit_items INT DEFAULT 10,
  p_include_items BOOLEAN DEFAULT TRUE,
  p_fuzzy_threshold NUMERIC DEFAULT 0.30,
  p_merchant_id UUID DEFAULT NULL,
  p_include_suggestions BOOLEAN DEFAULT TRUE,
  p_suggestion_max INT DEFAULT 8
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
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
           WHERE m.is_active
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
              JOIN public.merchants m ON m.id = i.merchant_id AND m.is_active
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
             WHERE m.is_active
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
                JOIN public.merchants m ON m.id = i.merchant_id AND m.is_active
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
              WHERE m.is_active
                AND public.normalize_search_text(m.name_en) LIKE v_prefix
                AND public.normalize_search_text(m.name_en) <> v_norm
             UNION ALL
             SELECT m.name_ar, 0::int
               FROM public.merchants m
              WHERE m.is_active
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

-- =============================================================================
-- 4. search_queries — search analytics log (DOD-7)
-- RLS enabled with ZERO policies: anon/authenticated can neither read nor
-- write; only the service role (Edge Function writes, admin service client
-- reads) has access. user_id is nullable + ON DELETE SET NULL so analytics
-- survive account deletion (EC-15).
-- =============================================================================
CREATE TABLE public.search_queries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Customer who searched (nullable — auth optional, deletion-tolerant)
  user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,

  -- Raw query as typed (PII note: 180d retention + aggregate-only exposure)
  query TEXT NOT NULL,

  -- Normalized form (normalize_search_text) — groups spelling variants
  normalized_query TEXT NOT NULL,

  -- Context
  city TEXT,
  category TEXT,

  -- Result counts at serve time
  merchant_results INT NOT NULL DEFAULT 0,
  item_results INT NOT NULL DEFAULT 0,

  -- Generated: fast zero-result filtering without per-row arithmetic
  has_results BOOLEAN GENERATED ALWAYS AS (merchant_results > 0 OR item_results > 0) STORED,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_search_queries_trend
  ON public.search_queries(normalized_query, city, created_at DESC);
CREATE INDEX idx_search_queries_zero
  ON public.search_queries(created_at DESC) WHERE NOT has_results;
CREATE INDEX idx_search_queries_user
  ON public.search_queries(user_id, created_at DESC);

ALTER TABLE public.search_queries ENABLE ROW LEVEL SECURITY;

-- =============================================================================
-- 5. Retention: prune rows older than 180 days, daily at 03:15 UTC
-- =============================================================================
CREATE OR REPLACE FUNCTION public.prune_search_queries()
RETURNS BIGINT
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deleted BIGINT;
BEGIN
  DELETE FROM public.search_queries
   WHERE created_at < now() - interval '180 days';
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

SELECT cron.schedule('search-queries-retention', '15 3 * * *',
  $$SELECT public.prune_search_queries()$$);

-- =============================================================================
-- 6. get_search_analytics_summary(p_days) — admin endpoint aggregation
-- Aggregate-only output: never returns raw rows or user ids (§10 security).
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_search_analytics_summary(p_days INT DEFAULT 7)
RETURNS JSON
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_from TIMESTAMPTZ;
  v_volume BIGINT := 0;
  v_top JSON := '[]'::json;
  v_zero JSON := '[]'::json;
  v_suggest JSON := '[]'::json;
BEGIN
  IF p_days IS NULL OR p_days < 1 OR p_days > 90 THEN
    RAISE EXCEPTION 'INVALID_DAYS';
  END IF;
  v_from := now() - (p_days::text || ' days')::interval;

  SELECT COUNT(*) INTO v_volume
    FROM public.search_queries
   WHERE created_at >= v_from;

  -- Top successful queries (exact spelling as typed, spelling variants differ)
  SELECT COALESCE(json_agg(t ORDER BY t.c DESC, t.query ASC), '[]'::json) INTO v_top
    FROM (
      SELECT sq.query, COUNT(*)::int AS c,
             ROUND(AVG(sq.merchant_results)::numeric, 1) AS avg_merchant_results,
             ROUND(AVG(sq.item_results)::numeric, 1) AS avg_item_results
        FROM public.search_queries sq
       WHERE sq.created_at >= v_from AND sq.has_results
       GROUP BY sq.query
       ORDER BY c DESC, sq.query ASC
       LIMIT 20
    ) t;

  -- Top zero-result queries (catalog/merchandising signal)
  SELECT COALESCE(json_agg(t ORDER BY t.c DESC, t.query ASC), '[]'::json) INTO v_zero
    FROM (
      SELECT sq.query, COUNT(*)::int AS c
        FROM public.search_queries sq
       WHERE sq.created_at >= v_from AND NOT sq.has_results
       GROUP BY sq.query
       ORDER BY c DESC, sq.query ASC
       LIMIT 20
    ) t;

  -- Suggestion candidates: successful queries deduped on normalized form
  SELECT COALESCE(json_agg(t ORDER BY t.c DESC, t.query ASC), '[]'::json) INTO v_suggest
    FROM (
      SELECT MIN(sq.query) AS query, SUM(sq.c)::int AS c
        FROM (
          SELECT sq.normalized_query, sq.query, COUNT(*)::int AS c
            FROM public.search_queries sq
           WHERE sq.created_at >= v_from AND sq.has_results
           GROUP BY sq.normalized_query, sq.query
        ) sq
       GROUP BY sq.normalized_query
       ORDER BY c DESC
       LIMIT 20
    ) t;

  RETURN json_build_object(
    'days', p_days,
    'volume', v_volume,
    'top_queries', v_top,
    'top_zero_result_queries', v_zero,
    'suggestion_candidates', v_suggest
  );
END;
$$;

-- =============================================================================
-- 7. platform_config kill switches (F4 degradation ladder; 094 seed pattern)
-- =============================================================================
INSERT INTO public.platform_config (key, value, description, value_type, is_editable)
VALUES
  ('search_items_enabled', 'true',
   'When true, search matches menu items (dishes/products) in addition to merchants. When false, search degrades to merchants-only.',
   'boolean', TRUE),
  ('search_fuzzy_enabled', 'true',
   'When true, zero-result searches fall back to trigram-similarity fuzzy matching with a did-you-mean suggestion.',
   'boolean', TRUE),
  ('search_fuzzy_threshold', '0.30',
   'Minimum pg_trgm similarity (0-1) for the fuzzy fallback to accept a candidate. 0 disables fuzzy matching regardless of search_fuzzy_enabled.',
   'number', TRUE),
  ('search_suggestions_enabled', 'true',
   'When true, the search response includes trending-query and merchant-name prefix suggestions.',
   'boolean', TRUE),
  ('search_suggestions_max', '8',
   'Maximum number of suggestions returned per search (0-20).',
   'number', TRUE),
  ('search_query_logging_enabled', 'true',
   'When true, every search is logged to search_queries for analytics (privacy brake: flip to false to stop all logging).',
   'boolean', TRUE)
ON CONFLICT (key) DO NOTHING;

-- =============================================================================
-- 8. ACLs (094 belt-and-braces pattern)
-- NOTE (095-fix): Supabase default privileges auto-grant EXECUTE ON new
-- functions to anon+authenticated, so REVOKE FROM PUBLIC alone leaves them
-- with access. Explicit per-role REVOKEs below (verified live 2026-09-30).
-- =============================================================================
REVOKE ALL ON FUNCTION public.search_catalog(TEXT, TEXT, TEXT, NUMERIC, NUMERIC, INT, INT, BOOLEAN, NUMERIC, UUID, BOOLEAN, INT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.search_catalog(TEXT, TEXT, TEXT, NUMERIC, NUMERIC, INT, INT, BOOLEAN, NUMERIC, UUID, BOOLEAN, INT) TO service_role;

REVOKE ALL ON FUNCTION public.get_search_analytics_summary(INT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_search_analytics_summary(INT) TO service_role;

REVOKE ALL ON FUNCTION public.prune_search_queries() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prune_search_queries() TO service_role;

REVOKE ALL ON public.search_queries FROM anon, authenticated;
GRANT SELECT, INSERT ON public.search_queries TO service_role;

-- =============================================================================
-- 9. Comments
-- =============================================================================
COMMENT ON FUNCTION public.normalize_search_text(TEXT) IS 'Search & Discovery MVP (095): bilingual ar/en normalization — alef/hamza fold, taa marbuta, maqsura, harakat/tatweel/sup-alef strip, Latin accents, lowercase. IMMUTABLE for expression indexes.';
COMMENT ON FUNCTION public.search_catalog(TEXT, TEXT, TEXT, NUMERIC, NUMERIC, INT, INT, BOOLEAN, NUMERIC, UUID, BOOLEAN, INT) IS 'Search & Discovery MVP (095): single-round-trip catalog search — exact/prefix → fuzzy fallback → suggestions. Geo pre-filter (bbox/city); delivery-radius exclusion stays in the search-catalog Edge Function. service_role only.';
COMMENT ON TABLE public.search_queries IS 'Search & Discovery MVP (095): per-query analytics log (query, normalized, city, result counts). RLS on with zero policies — service-role only. 180-day retention via prune_search_queries cron.';
COMMENT ON FUNCTION public.get_search_analytics_summary(INT) IS 'Search & Discovery MVP (095): aggregate search analytics (top queries, top zero-result, suggestion candidates) over p_days. Aggregate-only output; service_role only.';
COMMENT ON FUNCTION public.prune_search_queries() IS 'Search & Discovery MVP (095): deletes search_queries rows older than 180 days. Scheduled daily 03:15 UTC as search-queries-retention.';

-- =============================================================================
-- 10. EMBEDDED TEST SUITE
-- Marker-prefixed seed data (m95t…) so production rows can never collide with
-- assertions. Every failure is collected and reported; any failure RAISEs,
-- aborting the whole migration transaction (loud, atomic).
-- =============================================================================
DO $test$
DECLARE
  v_failures TEXT[] := '{}';
  v_norm TEXT;
  v_res JSON;
  v_merchants JSON;
  v_items JSON;
  v_arr JSON;
  v_top JSON;
  v_m1 UUID; v_m2 UUID; v_m3 UUID; v_m4 UUID; v_m5 UUID; v_m6 UUID;
  v_c1 UUID; v_c2 UUID;
  v_count INT;
  v_ok BOOLEAN;
  v_sim_a DOUBLE PRECISION;
  v_sim_b DOUBLE PRECISION;
  v_vol BIGINT;
  v_json TEXT;
BEGIN
  -- (plpgsql has no nested functions — result-membership checks below use
  --  inline EXISTS over json_array_elements.)
  -- ═══════════════ SECTION A: normalization fixtures (plan §6.1) ═══════════

  -- A01-A04: alef/hamza variants fold to bare alef
  IF public.normalize_search_text('أحمد') <> 'احمد' THEN v_failures := array_append(v_failures, 'A01 alef-hamza'); END IF;
  IF public.normalize_search_text('إبراهيم') <> 'ابراهيم' THEN v_failures := array_append(v_failures, 'A02 alef-hamza-below'); END IF;
  IF public.normalize_search_text('آمنة') <> 'امنه' THEN v_failures := array_append(v_failures, 'A03 alef-madda+taa'); END IF;
  IF public.normalize_search_text('ٱلله') <> 'الله' THEN v_failures := array_append(v_failures, 'A04 alef-wasla'); END IF;

  -- A05: taa marbuta → ha
  IF public.normalize_search_text('مطعمه') <> 'مطعمه' THEN v_failures := array_append(v_failures, 'A05 taa-marbuta'); END IF;
  -- (literal check: م with fatha ط ع م ة → م ط ع م ه)
  v_norm := public.normalize_search_text('مدرسة');
  IF v_norm <> 'مدرسه' THEN v_failures := array_append(v_failures, 'A05b taa-marbuta-school'); END IF;

  -- A06: alef maqsura → ya
  IF public.normalize_search_text('مستشفى') <> 'مستشفي' THEN v_failures := array_append(v_failures, 'A06 maqsura'); END IF;

  -- A07: harakat stripped
  IF public.normalize_search_text('مَطْعَم') <> 'مطعم' THEN v_failures := array_append(v_failures, 'A07 harakat'); END IF;

  -- A08: tatweel stripped
  IF public.normalize_search_text('مطـــعم') <> 'مطعم' THEN v_failures := array_append(v_failures, 'A08 tatweel'); END IF;

  -- A09: superscript alef stripped
  IF public.normalize_search_text('علىٰ') <> 'علي' THEN v_failures := array_append(v_failures, 'A09 superscript-alef'); END IF;

  -- A10 (REGRESSION): letters ف ق ك ل م (U+0641-U+0645) must SURVIVE — a naive
  -- strip range starting at U+0640 would delete them.
  v_norm := public.normalize_search_text('فقه قلم مك');
  IF v_norm <> 'فقه قلم مك' THEN v_failures := array_append(v_failures, 'A10 fil-qaf-kaf-lam-mim-survive: got ' || v_norm); END IF;

  -- A11: Latin lowercasing
  IF public.normalize_search_text('Koshari') <> 'koshari' THEN v_failures := array_append(v_failures, 'A11 lowercase'); END IF;

  -- A12: Latin accents folded
  IF public.normalize_search_text('Café') <> 'cafe' THEN v_failures := array_append(v_failures, 'A12 latin-accent'); END IF;

  -- A13: mixed script safe
  IF public.normalize_search_text('مطعم ABC') <> 'مطعم abc' THEN v_failures := array_append(v_failures, 'A13 mixed-script'); END IF;

  -- A14: trim
  IF public.normalize_search_text('  koshari  ') <> 'koshari' THEN v_failures := array_append(v_failures, 'A14 trim'); END IF;

  -- A15: empty string → empty
  IF public.normalize_search_text('') <> '' THEN v_failures := array_append(v_failures, 'A15 empty'); END IF;

  -- A16: digits preserved
  IF public.normalize_search_text('Panadol Extra 500mg') <> 'panadol extra 500mg' THEN v_failures := array_append(v_failures, 'A16 digits'); END IF;

  -- A17: emoji preserved (must not error nor be mangled)
  IF public.normalize_search_text('🍕 Pizza') <> '🍕 pizza' THEN v_failures := array_append(v_failures, 'A17 emoji'); END IF;

  -- A18: STRICT — NULL in, NULL out
  IF public.normalize_search_text(NULL) IS NOT NULL THEN v_failures := array_append(v_failures, 'A18 strict-null'); END IF;

  -- A19 (EXTREME): 10,000-char input does not error
  v_norm := public.normalize_search_text(repeat('koshari ', 1250));
  IF length(v_norm) <> 9999 THEN v_failures := array_append(v_failures, 'A19 long-input'); END IF;

  -- A20 (EXTREME): input that is ONLY harakat/tatweel normalizes to empty
  IF public.normalize_search_text('َُِّْـ') <> '' THEN v_failures := array_append(v_failures, 'A20 diacritics-only'); END IF;

  -- ═══════════════ SECTION B: metadata, indexes, ACL, config ═══════════════

  -- B01-B02: functions are IMMUTABLE (expression-index requirement)
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'normalize_search_text' AND provolatile <> 'i')
    THEN v_failures := array_append(v_failures, 'B01 normalize-not-immutable'); END IF;
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'f_unaccent' AND provolatile <> 'i')
    THEN v_failures := array_append(v_failures, 'B02 funaccent-not-immutable'); END IF;

  -- B03: all 6 normalized expression indexes exist and are valid
  FOR v_norm IN
    SELECT unnest(ARRAY[
      'idx_merchants_name_ar_norm_trgm', 'idx_merchants_name_en_norm_trgm',
      'idx_items_name_ar_norm_trgm', 'idx_items_name_en_norm_trgm',
      'idx_items_desc_ar_norm_trgm', 'idx_items_desc_en_norm_trgm'])
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_index i
        JOIN pg_class c ON c.oid = i.indexrelid
       WHERE c.relname = v_norm AND i.indisvalid
    ) THEN
      v_failures := array_append(v_failures, 'B03 missing-index:' || v_norm);
    END IF;
  END LOOP;

  -- B04: search_catalog is SECURITY DEFINER + pinned search_path
  SELECT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE p.proname = 'search_catalog'
       AND p.prosecdef
       AND p.proconfig IS NOT NULL
       AND p.proconfig::text LIKE '%search_path%'
  ) INTO v_ok;
  IF NOT v_ok THEN v_failures := array_append(v_failures, 'B04 search-catalog-definer-or-path'); END IF;

  -- B05: anon/authenticated CANNOT execute search_catalog; service_role CAN
  IF has_function_privilege('anon', 'public.search_catalog(TEXT,TEXT,TEXT,NUMERIC,NUMERIC,INT,INT,BOOLEAN,NUMERIC,UUID,BOOLEAN,INT)', 'EXECUTE')
    THEN v_failures := array_append(v_failures, 'B05 anon-has-execute'); END IF;
  IF NOT has_function_privilege('service_role', 'public.search_catalog(TEXT,TEXT,TEXT,NUMERIC,NUMERIC,INT,INT,BOOLEAN,NUMERIC,UUID,BOOLEAN,INT)', 'EXECUTE')
    THEN v_failures := array_append(v_failures, 'B05b service-role-no-execute'); END IF;

  -- B06: anon CANNOT execute get_search_analytics_summary; service_role CAN
  IF has_function_privilege('anon', 'public.get_search_analytics_summary(INT)', 'EXECUTE')
    THEN v_failures := array_append(v_failures, 'B06 anon-has-execute-analytics'); END IF;
  IF NOT has_function_privilege('service_role', 'public.get_search_analytics_summary(INT)', 'EXECUTE')
    THEN v_failures := array_append(v_failures, 'B06b service-role-no-execute-analytics'); END IF;

  -- B07: RLS enabled on search_queries
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname = 'search_queries' AND relrowsecurity)
    THEN v_failures := array_append(v_failures, 'B07 rls-not-enabled'); END IF;

  -- B08: ZERO policies on search_queries (service-role only by design)
  SELECT COUNT(*) INTO v_count FROM pg_policies WHERE tablename = 'search_queries';
  IF v_count <> 0 THEN v_failures := array_append(v_failures, 'B08 unexpected-policies:' || v_count::text); END IF;

  -- B09: generated column behaves (0/0 → false, 1/0 → true) — asserted via
  -- seeded rows in Section C (T-AN-01/02) rather than direct inserts here.

  -- B10: 6 config seeds present with exact values
  FOR v_norm, v_json IN
    SELECT k, v FROM (VALUES
      ('search_items_enabled', 'true'),
      ('search_fuzzy_enabled', 'true'),
      ('search_fuzzy_threshold', '0.30'),
      ('search_suggestions_enabled', 'true'),
      ('search_suggestions_max', '8'),
      ('search_query_logging_enabled', 'true')
    ) AS seeds(k, v)
  LOOP
    IF NOT EXISTS (SELECT 1 FROM public.platform_config WHERE key = v_norm AND value = v_json)
      THEN v_failures := array_append(v_failures, 'B10 config:' || v_norm); END IF;
  END LOOP;

  -- B11: retention cron scheduled
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'search-queries-retention')
    THEN v_failures := array_append(v_failures, 'B11 cron-missing'); END IF;

  -- B12: prune function runs without error (seeds are fresh → deletes nothing)
  PERFORM public.prune_search_queries();

  -- ═══════════════ SECTION C: RPC behavioral tests on seed data ═════════════

  -- ── Seed (marker prefix m95t guarantees zero prod collisions) ──
  v_m1 := gen_random_uuid(); v_m2 := gen_random_uuid(); v_m3 := gen_random_uuid();
  v_m4 := gen_random_uuid(); v_m5 := gen_random_uuid(); v_m6 := gen_random_uuid();
  v_c1 := gen_random_uuid(); v_c2 := gen_random_uuid();
  INSERT INTO public.merchants (id, name_ar, name_en, category, address, lat, lng, city, phone, rating, rating_count, is_active)
  VALUES
    (v_m1, 'm95t كشري أحمد', 'm95t Ahmed Koshari', 'restaurant', 'addr', 30.0444, 31.2357, 'cairo', '01000000001', 4.5, 100, TRUE),
    (v_m2, 'm95t أحمد الدهب', 'm95t Ahmed El Dehab', 'restaurant', 'addr', 30.0500, 31.2400, 'cairo', '01000000002', 4.0, 10, TRUE),
    (v_m3, 'm95t صيدلية بلس', 'm95t Pharma Plus', 'pharmacy', 'addr', 29.9800, 31.2000, 'giza', '01000000003', 4.2, 40, TRUE),
    (v_m4, 'm95t مطعم مخفي', 'm95t Zzz Hidden Restaurant', 'restaurant', 'addr', 30.0450, 31.2360, 'cairo', '01000000004', 3.0, 1, FALSE),
    (v_m5, 'm95t كشري التحرير', 'm95t Koshari Tahrir', 'restaurant', 'addr', 30.0460, 31.2370, 'cairo', '01000000005', 3.8, 25, TRUE),
    (v_m6, 'm95t عصائر 100%', 'm95t 100% Juice Bar', 'restaurant', 'addr', 30.0470, 31.2380, 'cairo', '01000000006', 4.1, 15, TRUE);

  INSERT INTO public.categories (id, merchant_id, name_ar, name_en)
  VALUES
    (v_c1, v_m1, 'm95t رئيسي', 'm95t Main'),
    (v_c2, v_m3, 'm95t أدوية', 'm95t Medicine');

  INSERT INTO public.items (id, merchant_id, category_id, name_ar, name_en, price, is_available, popularity_score, description_ar, description_en)
  VALUES
    (gen_random_uuid(), v_m1, v_c1, 'm95t كشري أبو طارق', 'm95t Koshari Abou Tariqa', 45.00, TRUE, 90, 'طبق مصري من العدس والأرز', 'Egyptian lentil rice pasta dish'),
    (gen_random_uuid(), v_m1, v_c1, 'm95t أرز بلبن', 'm95t Rice Pudding', 20.00, TRUE, 50, NULL, 'Sweet milk rice dessert'),
    (gen_random_uuid(), v_m1, v_c1, 'm95t طبق مخفي', 'm95t Hidden Dish', 10.00, FALSE, 10, NULL, NULL),
    (gen_random_uuid(), v_m3, v_c2, 'm95t بنادول اكسترا', 'm95t Panadol Extra', 30.00, TRUE, 80, NULL, 'Pain relief tablets');

  -- T-C01: exact merchant match on name_en (lowercase query)
  v_res := public.search_catalog('m95t ahmed koshari', 'cairo', NULL, NULL, NULL, 30, 10, TRUE, 0, NULL, FALSE, 0);
  IF NOT EXISTS (SELECT 1 FROM json_array_elements(v_res->'merchants') e WHERE e->>'name_en' = 'm95t Ahmed Koshari')
    THEN v_failures := array_append(v_failures, 'T-C01 exact-en'); END IF;

  -- T-C02: Arabic hamza-insensitivity — plain alef query matches hamza name
  v_res := public.search_catalog('m95t احمد الدهب', 'cairo', NULL, NULL, NULL, 30, 10, TRUE, 0, NULL, FALSE, 0);
  IF NOT EXISTS (SELECT 1 FROM json_array_elements(v_res->'merchants') e WHERE e->>'name_en' = 'm95t Ahmed El Dehab')
    THEN v_failures := array_append(v_failures, 'T-C02 hamza-fold'); END IF;

  -- T-C03: Arabic diacritics in query match undiacritized name
  v_res := public.search_catalog('m95t كُشري أحمد', 'cairo', NULL, NULL, NULL, 30, 10, TRUE, 0, NULL, FALSE, 0);
  IF NOT EXISTS (SELECT 1 FROM json_array_elements(v_res->'merchants') e WHERE e->>'name_en' = 'm95t Ahmed Koshari')
    THEN v_failures := array_append(v_failures, 'T-C03 diacritics'); END IF;

  -- T-C04: dish search returns items (the headline MVP capability)
  v_res := public.search_catalog('m95t panadol', 'giza', NULL, NULL, NULL, 30, 10, TRUE, 0, NULL, FALSE, 0);
  IF NOT EXISTS (SELECT 1 FROM json_array_elements(v_res->'items') e WHERE e->>'name_en' = 'm95t Panadol Extra')
    THEN v_failures := array_append(v_failures, 'T-C04 item-match'); END IF;

  -- T-C05: description-only match ('lentil' appears only in the description)
  v_res := public.search_catalog('m95t lentil', 'cairo', NULL, NULL, NULL, 30, 10, TRUE, 0, NULL, FALSE, 0);
  IF NOT EXISTS (SELECT 1 FROM json_array_elements(v_res->'items') e WHERE e->>'name_en' = 'm95t Koshari Abou Tariqa')
    THEN v_failures := array_append(v_failures, 'T-C05 description-match'); END IF;

  -- T-C06: Arabic description-only match
  v_res := public.search_catalog('m95t العدس', 'cairo', NULL, NULL, NULL, 30, 10, TRUE, 0, NULL, FALSE, 0);
  IF NOT EXISTS (SELECT 1 FROM json_array_elements(v_res->'items') e WHERE e->>'name_en' = 'm95t Koshari Abou Tariqa')
    THEN v_failures := array_append(v_failures, 'T-C06 ar-description'); END IF;

  -- T-C07: match_tier exact + match_mode exact
  IF v_res->>'match_mode' <> 'exact' THEN v_failures := array_append(v_failures, 'T-C07a match-mode'); END IF;
  v_arr := v_res->'items'->0;
  IF v_arr->>'match_tier' <> 'exact' THEN v_failures := array_append(v_failures, 'T-C07b match-tier'); END IF;

  -- T-C08: fuzzy fallback fires on typo (threshold lowered for determinism)
  v_res := public.search_catalog('m95t koshry', 'cairo', NULL, NULL, NULL, 30, 10, TRUE, 0.2, NULL, FALSE, 0);
  IF v_res->>'match_mode' <> 'fuzzy' THEN v_failures := array_append(v_failures, 'T-C08a fuzzy-mode: got ' || COALESCE(v_res->>'match_mode','NULL')); END IF;
  IF NOT EXISTS (SELECT 1 FROM json_array_elements(v_res->'merchants') e WHERE e->>'name_en' = 'm95t Ahmed Koshari')
    THEN v_failures := array_append(v_failures, 'T-C08b fuzzy-merchant'); END IF;
  IF COALESCE(v_res->>'fuzzy_top', '') NOT LIKE 'm95t%' THEN v_failures := array_append(v_failures, 'T-C08c fuzzy-top'); END IF;

  -- T-C09: fuzzy similarity is better against the right target (ordering sanity)
  v_sim_a := similarity(public.normalize_search_text('m95t koshry'), public.normalize_search_text('m95t koshari'));
  v_sim_b := similarity(public.normalize_search_text('m95t koshry'), public.normalize_search_text('m95t panadol extra'));
  IF NOT (v_sim_a > v_sim_b) THEN v_failures := array_append(v_failures, 'T-C09 similarity-ordering'); END IF;

  -- T-C10: fuzzy disabled (threshold 0) → honest zero
  v_res := public.search_catalog('m95t koshry', 'cairo', NULL, NULL, NULL, 30, 10, TRUE, 0, NULL, FALSE, 0);
  IF v_res->>'match_mode' <> 'none' OR json_array_length(v_res->'merchants') <> 0
    THEN v_failures := array_append(v_failures, 'T-C10 fuzzy-disabled'); END IF;

  -- T-C11: high threshold blocks fuzzy false positives
  v_res := public.search_catalog('m95t koshry', 'cairo', NULL, NULL, NULL, 30, 10, TRUE, 0.99, NULL, FALSE, 0);
  IF v_res->>'match_mode' <> 'none' THEN v_failures := array_append(v_failures, 'T-C11 high-threshold'); END IF;

  -- T-C12: zero-result query, no fuzzy candidate → none + empty everything
  v_res := public.search_catalog('m95t zzqqxx wvvv', 'cairo', NULL, NULL, NULL, 30, 10, TRUE, 0.2, NULL, FALSE, 0);
  IF v_res->>'match_mode' <> 'none' OR json_array_length(v_res->'merchants') <> 0
     OR json_array_length(v_res->'items') <> 0 OR v_res->>'fuzzy_top' IS NOT NULL
    THEN v_failures := array_append(v_failures, 'T-C12 none-shape'); END IF;

  -- T-C13: city filter — giza query cannot see cairo merchants/items
  v_res := public.search_catalog('m95t koshari', 'giza', NULL, NULL, NULL, 30, 10, TRUE, 0, NULL, FALSE, 0);
  IF v_res->>'match_mode' <> 'none' THEN v_failures := array_append(v_failures, 'T-C13 city-filter'); END IF;

  -- T-C14: no city + no coords → no geo filter (giza item reachable)
  v_res := public.search_catalog('m95t panadol', NULL, NULL, NULL, NULL, 30, 10, TRUE, 0, NULL, FALSE, 0);
  IF NOT EXISTS (SELECT 1 FROM json_array_elements(v_res->'items') e WHERE e->>'name_en' = 'm95t Panadol Extra')
    THEN v_failures := array_append(v_failures, 'T-C14 no-geo'); END IF;

  -- T-C15: bbox pre-filter — merchant C (29.98) outside bbox centered at 31.8
  v_res := public.search_catalog('m95t panadol', NULL, NULL, 31.8000, 31.0000, 30, 10, TRUE, 0, NULL, FALSE, 0);
  IF json_array_length(v_res->'items') <> 0 THEN v_failures := array_append(v_failures, 'T-C15a bbox-exclude'); END IF;
  -- and inside bbox centered at giza → included
  v_res := public.search_catalog('m95t panadol', NULL, NULL, 29.9800, 31.2000, 30, 10, TRUE, 0, NULL, FALSE, 0);
  IF NOT EXISTS (SELECT 1 FROM json_array_elements(v_res->'items') e WHERE e->>'name_en' = 'm95t Panadol Extra')
    THEN v_failures := array_append(v_failures, 'T-C15b bbox-include'); END IF;

  -- T-C16: category filter — pharmacy query cannot return restaurant matches
  v_res := public.search_catalog('m95t koshari', 'cairo', 'pharmacy', NULL, NULL, 30, 10, TRUE, 0, NULL, FALSE, 0);
  IF v_res->>'match_mode' <> 'none' THEN v_failures := array_append(v_failures, 'T-C16 category'); END IF;

  -- T-C17: category 'all' treated as no filter
  v_res := public.search_catalog('m95t panadol', 'giza', 'all', NULL, NULL, 30, 10, TRUE, 0, NULL, FALSE, 0);
  IF NOT EXISTS (SELECT 1 FROM json_array_elements(v_res->'items') e WHERE e->>'name_en' = 'm95t Panadol Extra')
    THEN v_failures := array_append(v_failures, 'T-C17 all-category'); END IF;

  -- T-C18: unavailable item never returned
  v_res := public.search_catalog('m95t hidden dish', 'cairo', NULL, NULL, NULL, 30, 10, TRUE, 0, NULL, FALSE, 0);
  IF json_array_length(v_res->'items') <> 0 THEN v_failures := array_append(v_failures, 'T-C18 unavailable-item'); END IF;

  -- T-C19: inactive merchant never returned
  v_res := public.search_catalog('m95t zzz hidden', 'cairo', NULL, NULL, NULL, 30, 10, TRUE, 0, NULL, FALSE, 0);
  IF json_array_length(v_res->'merchants') <> 0 THEN v_failures := array_append(v_failures, 'T-C19 inactive-merchant'); END IF;

  -- T-C20 (REGRESSION): LIKE wildcards in query must be literal — "a%b"
  -- unescaped would match "…dehab" (a…b substring); escaped it matches nothing.
  v_res := public.search_catalog('m95t a%b', 'cairo', NULL, NULL, NULL, 30, 10, TRUE, 0, NULL, FALSE, 0);
  IF v_res->>'match_mode' <> 'none' THEN v_failures := array_append(v_failures, 'T-C20 like-escape'); END IF;

  -- T-C21: literal % in a NAME matches a query containing % (100% Juice Bar)
  v_res := public.search_catalog('m95t 100% juice', 'cairo', NULL, NULL, NULL, 30, 10, TRUE, 0, NULL, FALSE, 0);
  IF NOT EXISTS (SELECT 1 FROM json_array_elements(v_res->'merchants') e WHERE e->>'name_en' = 'm95t 100% Juice Bar')
    THEN v_failures := array_append(v_failures, 'T-C21 literal-percent'); END IF;

  -- T-C22: underscore wildcard escaped (m95t_a… would otherwise match m95tXa…)
  v_res := public.search_catalog('m95t_koshari', 'cairo', NULL, NULL, NULL, 30, 10, TRUE, 0, NULL, FALSE, 0);
  IF v_res->>'match_mode' <> 'none' THEN v_failures := array_append(v_failures, 'T-C22 underscore-escape'); END IF;

  -- T-C23: argument clamps — absurd limits must not error
  v_res := public.search_catalog('m95t koshari', 'cairo', NULL, NULL, NULL, 100000, -5, TRUE, 7.5, NULL, TRUE, 999);
  IF v_res IS NULL THEN v_failures := array_append(v_failures, 'T-C23 clamps-crash'); END IF;

  -- T-C24: p_limit_items = 0 → items suppressed even when matches exist
  v_res := public.search_catalog('m95t panadol', 'giza', NULL, NULL, NULL, 30, 0, TRUE, 0, NULL, FALSE, 0);
  IF json_array_length(v_res->'items') <> 0 THEN v_failures := array_append(v_failures, 'T-C24 zero-item-limit'); END IF;

  -- T-C25: include_items=false → merchants-only
  v_res := public.search_catalog('m95t panadol', 'giza', NULL, NULL, NULL, 30, 10, FALSE, 0, NULL, FALSE, 0);
  IF json_array_length(v_res->'items') <> 0 THEN v_failures := array_append(v_failures, 'T-C25 items-off'); END IF;

  -- T-C26: search guard — short/long/empty queries raise INVALID_QUERY
  BEGIN
    PERFORM public.search_catalog('a', NULL, NULL, NULL, NULL, 30, 10, TRUE, 0, NULL, FALSE, 0);
    v_failures := array_append(v_failures, 'T-C26a short-query-no-raise');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%INVALID_QUERY%' THEN v_failures := array_append(v_failures, 'T-C26a wrong-error: ' || SQLERRM); END IF;
  END;
  BEGIN
    PERFORM public.search_catalog(repeat('x', 81), NULL, NULL, NULL, NULL, 30, 10, TRUE, 0, NULL, FALSE, 0);
    v_failures := array_append(v_failures, 'T-C26b long-query-no-raise');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%INVALID_QUERY%' THEN v_failures := array_append(v_failures, 'T-C26b wrong-error: ' || SQLERRM); END IF;
  END;
  BEGIN
    PERFORM public.search_catalog(NULL, NULL, NULL, NULL, NULL, 30, 10, TRUE, 0, NULL, FALSE, 0);
    v_failures := array_append(v_failures, 'T-C26c null-query-no-raise');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%INVALID_QUERY%' THEN v_failures := array_append(v_failures, 'T-C26c wrong-error: ' || SQLERRM); END IF;
  END;

  -- T-C27: exactly-80-char query is accepted (boundary)
  v_res := public.search_catalog('m95t ' || repeat('k', 75), 'cairo', NULL, NULL, NULL, 30, 10, TRUE, 0, NULL, FALSE, 0);
  IF v_res IS NULL THEN v_failures := array_append(v_failures, 'T-C27 boundary-80'); END IF;

  -- T-C28: merchant_id scoping — search restricted to one merchant
  v_res := public.search_catalog('m95t koshari', 'cairo', NULL, NULL, NULL, 30, 10, TRUE, 0, v_m5, FALSE, 0);
  v_merchants := v_res->'merchants';
  IF json_array_length(v_merchants) <> 1
     OR (v_merchants -> 0 ->> 'name_en') <> 'm95t Koshari Tahrir'
    THEN v_failures := array_append(v_failures, 'T-C28 merchant-scope'); END IF;

  -- T-C29: suggestions — trending + merchant prefix, own query excluded, dedupe
  INSERT INTO public.search_queries (user_id, query, normalized_query, city, category, merchant_results, item_results)
  VALUES
    (NULL, 'm95t koshary tahrir menu', 'm95t koshary tahrir menu', 'cairo', 'restaurant', 1, 0),
    (NULL, 'm95t koshary tahrir menu', 'm95t koshary tahrir menu', 'cairo', 'restaurant', 1, 0),
    (NULL, 'm95t KOSHARY TAHRIR MENU', 'm95t koshary tahrir menu', 'cairo', 'restaurant', 1, 0),
    (NULL, 'm95t koshary tahrir hours', 'm95t koshary tahrir hours', 'cairo', 'restaurant', 1, 0);
  v_res := public.search_catalog('m95t koshary tahr', 'cairo', NULL, NULL, NULL, 30, 10, TRUE, 0, NULL, TRUE, 8);
  v_arr := v_res->'suggestions';
  IF json_array_length(v_arr) = 0 THEN
    v_failures := array_append(v_failures, 'T-C29a suggestions-empty');
  ELSE
    IF NOT EXISTS (SELECT 1 FROM json_array_elements_text(v_arr) s
                    WHERE s = 'm95t koshary tahrir menu')
      THEN v_failures := array_append(v_failures, 'T-C29b trending-missing'); END IF;
    IF EXISTS (SELECT 1 FROM json_array_elements_text(v_arr) s WHERE s = 'm95t koshary tahr')
      THEN v_failures := array_append(v_failures, 'T-C29c own-query-leaked'); END IF;
    IF EXISTS (
      SELECT 1 FROM json_array_elements_text(v_arr) s
       GROUP BY lower(regexp_replace(s, '\s+', ' ', 'g')) HAVING COUNT(*) > 1
    ) THEN v_failures := array_append(v_failures, 'T-C29d duplicate-suggestions'); END IF;
  END IF;

  -- T-C30: suggestions city-scoped — same query logged under giza stays hidden
  INSERT INTO public.search_queries (user_id, query, normalized_query, city, category, merchant_results, item_results)
  VALUES (NULL, 'm95t koshary tahrir giza-only', 'm95t koshary tahrir giza-only', 'giza', 'restaurant', 1, 0);
  v_res := public.search_catalog('m95t koshary tahr', 'cairo', NULL, NULL, NULL, 30, 10, TRUE, 0, NULL, TRUE, 8);
  IF EXISTS (SELECT 1 FROM json_array_elements_text(v_res->'suggestions') s
              WHERE s = 'm95t koshary tahrir giza-only')
    THEN v_failures := array_append(v_failures, 'T-C30 suggestions-city-scope'); END IF;

  -- T-C31: zero-result queries never become suggestions
  INSERT INTO public.search_queries (user_id, query, normalized_query, city, category, merchant_results, item_results)
  VALUES (NULL, 'm95t koshary tahrir zero-hits', 'm95t koshary tahrir zero-hits', 'cairo', 'restaurant', 0, 0);
  v_res := public.search_catalog('m95t koshary tahr', 'cairo', NULL, NULL, NULL, 30, 10, TRUE, 0, NULL, TRUE, 8);
  IF EXISTS (SELECT 1 FROM json_array_elements_text(v_res->'suggestions') s
              WHERE s LIKE '%zero-hits%')
    THEN v_failures := array_append(v_failures, 'T-C31 zero-result-suggestion'); END IF;

  -- T-C32: suggestions disabled → empty array, zero extra work
  v_res := public.search_catalog('m95t koshary tahr', 'cairo', NULL, NULL, NULL, 30, 10, TRUE, 0, NULL, FALSE, 8);
  IF json_array_length(v_res->'suggestions') <> 0 THEN v_failures := array_append(v_failures, 'T-C32 suggestions-off'); END IF;

  -- T-C33: stale trending ignored — 31-day-old queries are out of the window
  INSERT INTO public.search_queries (user_id, query, normalized_query, city, category, merchant_results, item_results, created_at)
  VALUES (NULL, 'm95t koshary tahrir ancient', 'm95t koshary tahrir ancient', 'cairo', 'restaurant', 1, 0, now() - interval '31 days');
  v_res := public.search_catalog('m95t koshary tahr', 'cairo', NULL, NULL, NULL, 30, 10, TRUE, 0, NULL, TRUE, 8);
  IF EXISTS (SELECT 1 FROM json_array_elements_text(v_res->'suggestions') s
              WHERE s LIKE '%ancient%')
    THEN v_failures := array_append(v_failures, 'T-C33 stale-trending'); END IF;

  -- T-C34: analytics summary — volume, top, zero, candidates from seeds
  v_res := public.get_search_analytics_summary(7);
  v_vol := (v_res->>'volume')::bigint;
  -- 6 in-window seed rows (T29×4 + T30 + T31); the RPC itself never logs.
  IF v_vol < 6 THEN v_failures := array_append(v_failures, 'T-C34a volume:' || v_vol::text); END IF;
  v_top := v_res->'top_queries';
  IF NOT EXISTS (SELECT 1 FROM json_array_elements(v_top) e
                  WHERE e->>'query' = 'm95t koshary tahrir menu' AND (e->>'c')::int = 2)
    THEN v_failures := array_append(v_failures, 'T-C34b top-queries'); END IF;
  IF NOT EXISTS (SELECT 1 FROM json_array_elements(v_res->'top_zero_result_queries') e
                  WHERE e->>'query' LIKE '%zero-hits%' AND (e->>'c')::int = 1)
    THEN v_failures := array_append(v_failures, 'T-C34c zero-queries'); END IF;
  IF NOT EXISTS (SELECT 1 FROM json_array_elements(v_res->'suggestion_candidates') e
                  WHERE e->>'query' = 'm95t koshary tahrir menu' AND (e->>'c')::int = 3)
    THEN v_failures := array_append(v_failures, 'T-C34d candidates-dedupe'); END IF;

  -- T-C35: analytics days guard
  BEGIN
    PERFORM public.get_search_analytics_summary(0);
    v_failures := array_append(v_failures, 'T-C35a days-0-no-raise');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%INVALID_DAYS%' THEN v_failures := array_append(v_failures, 'T-C35a wrong-error: ' || SQLERRM); END IF;
  END;
  BEGIN
    PERFORM public.get_search_analytics_summary(91);
    v_failures := array_append(v_failures, 'T-C35b days-91-no-raise');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%INVALID_DAYS%' THEN v_failures := array_append(v_failures, 'T-C35b wrong-error: ' || SQLERRM); END IF;
  END;
  BEGIN
    PERFORM public.get_search_analytics_summary(NULL);
    v_failures := array_append(v_failures, 'T-C35c days-null-no-raise');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%INVALID_DAYS%' THEN v_failures := array_append(v_failures, 'T-C35c wrong-error: ' || SQLERRM); END IF;
  END;
  v_res := public.get_search_analytics_summary(90);
  IF (v_res->>'days')::int <> 90 THEN v_failures := array_append(v_failures, 'T-C35d days-90'); END IF;

  -- T-C36: has_results generated column — zero rows land in the zero index
  SELECT COUNT(*) INTO v_count FROM public.search_queries WHERE NOT has_results;
  IF v_count < 1 THEN v_failures := array_append(v_failures, 'T-C36 generated-column'); END IF;

  -- ═══════════════ VERDICT ═══════════════
  IF array_length(v_failures, 1) > 0 THEN
    RAISE EXCEPTION 'MIGRATION 095 TEST SUITE FAILED (% failures): %',
      array_length(v_failures, 1), array_to_string(v_failures, ' | ');
  END IF;
END;
$test$;

-- Self-cleaning guarantee: seed merchants cascade-delete categories/items; the
-- search_queries seeds are deleted here so the migration leaves zero residue
-- when it passes. (On failure everything rolls back anyway.)
DELETE FROM public.search_queries WHERE query LIKE 'm95t %';
DELETE FROM public.merchants WHERE name_en LIKE 'm95t %' OR name_ar LIKE 'm95t %';
