-- ReqIQ-ANN migration 0027 (ADD-01 §3 B and C, FR-ASN-012, OI-23)
-- 1. Derived sentence columns (ADD-01 §6): computed at import and backfilled now.
-- 2. pick_requirements: strategies DIST (B) and SCORE-STRAT (C) implemented.
--    Strategies choose only inside the priority tier (ADD-01 §5 step 3 first):
--    tier 0 (never shown) is always used before tier 1 (partial), then tier 2.
--    RAND keeps the previous behaviour.
--    SCORE-STRAT uses LLM pre-scores from reference_labels (decision 12 Nov 2026,
--    deviation from ADD-01 which uses human round-1 medians). A requirement without
--    a pre-score is treated as 'unknown' and is not pushed to any stratum (neutral).
-- Run once in Supabase SQL Editor AFTER 0026. Safe to re-run.
-- Activation of SCORE-STRAT is done by migration 0028 (not here).

-- ---------- 1. derived sentence columns ----------
-- Sentence count: sentence-ending . ? ! ; a decimal point between digits (e.g. 0.5 °C) is not a sentence end.
-- A text without punctuation counts as 1 sentence. Bins: SHORT 1, MEDIUM 2-3, LONG 4+.
CREATE OR REPLACE FUNCTION _sentence_count(p_text TEXT)
RETURNS SMALLINT LANGUAGE sql IMMUTABLE AS $$
  SELECT GREATEST(1, length(regexp_replace(regexp_replace(COALESCE(p_text, ''), '[0-9][.][0-9]', '', 'g'), '[^.?!]', '', 'g')))::SMALLINT;
$$;

CREATE OR REPLACE FUNCTION _sentence_bin(p_count SMALLINT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN p_count <= 1 THEN 'SHORT' WHEN p_count <= 3 THEN 'MEDIUM' ELSE 'LONG' END;
$$;

REVOKE ALL ON FUNCTION _sentence_count(TEXT), _sentence_bin(SMALLINT) FROM PUBLIC, anon, authenticated;

-- Backfill existing rows (text_en, else text_tr)
UPDATE requirements
SET sentence_count = _sentence_count(COALESCE(text_en, text_tr))
WHERE sentence_count IS NULL;

UPDATE requirements
SET sentence_bin = _sentence_bin(sentence_count)
WHERE sentence_bin IS NULL AND sentence_count IS NOT NULL;

-- Import computes the same fields for new or re-imported rows
CREATE OR REPLACE FUNCTION admin_import_requirements(p_rows JSONB)
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n INT;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not an admin'; END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_rows) x
             WHERE COALESCE(x->>'req_id', '') = '' OR upper(x->>'language_tag') NOT IN ('EN','TR') OR COALESCE(x->>'project_id', '') = '') THEN
    RAISE EXCEPTION 'every row needs req_id, language_tag (EN/TR) and project_id';
  END IF;
  INSERT INTO requirements (req_id, base_id, language_tag, project_id, text_en, text_tr, eligible, req_type,
                            sentence_count, sentence_bin, source_meta)
  SELECT x->>'req_id', NULLIF(x->>'base_id', ''), upper(x->>'language_tag'), x->>'project_id',
         NULLIF(x->>'text_en', ''), NULLIF(x->>'text_tr', ''),
         COALESCE((x->>'eligible')::BOOLEAN, TRUE), COALESCE(NULLIF(upper(x->>'req_type'), ''), 'UNKNOWN'),
         _sentence_count(COALESCE(NULLIF(x->>'text_en', ''), NULLIF(x->>'text_tr', ''))),
         _sentence_bin(_sentence_count(COALESCE(NULLIF(x->>'text_en', ''), NULLIF(x->>'text_tr', '')))),
         x - ARRAY['req_id','base_id','language_tag','project_id','text_en','text_tr','eligible','req_type']
  FROM jsonb_array_elements(p_rows) x
  ON CONFLICT (req_id) DO UPDATE SET base_id = EXCLUDED.base_id, language_tag = EXCLUDED.language_tag,
    project_id = EXCLUDED.project_id, text_en = EXCLUDED.text_en, text_tr = EXCLUDED.text_tr,
    eligible = EXCLUDED.eligible, req_type = EXCLUDED.req_type,
    sentence_count = EXCLUDED.sentence_count, sentence_bin = EXCLUDED.sentence_bin,
    source_meta = requirements.source_meta || EXCLUDED.source_meta;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$$;
REVOKE ALL ON FUNCTION admin_import_requirements(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_import_requirements(JSONB) TO authenticated;

-- ---------- 2. pick_requirements with DIST and SCORE-STRAT ----------
CREATE OR REPLACE FUNCTION pick_requirements(p_session_id TEXT, p_lang TEXT, p_n INT, p_exclude TEXT[], p_by_base BOOLEAN)
RETURNS TEXT[] LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  cfg app_config%ROWTYPE;
  picked TEXT[] := '{}';
  used TEXT[] := COALESCE(p_exclude, '{}');
  per_project JSONB := '{}';
  cap INT;
  rec RECORD;
  best RECORD;
  found BOOLEAN;
  sc DOUBLE PRECISION;
  best_sc DOUBLE PRECISION;
  pass INT;
  tier_i INT;
  n_now INT;
  dims TEXT[];
  shares JSONB := '{}';                       -- 'dim|value' -> pool share (values with >= 2 pool items only, FR-SMP-B-002)
  dcnt JSONB := '{}';                         -- 'dim|value' -> picked count so far
  sshare DOUBLE PRECISION[] := ARRAY[0,0,0];  -- SCORE-STRAT target share for levels 0,1,2
  scnt INT[] := array_fill(0, ARRAY[18]);     -- (metric-1)*3 + level + 1 -> picked count
  lv INT[];
  m INT;
  idx INT;
  k TEXT;
BEGIN
  SELECT * INTO cfg FROM app_config WHERE id = 1;
  IF p_n <= 0 THEN RETURN picked; END IF;
  cap := GREATEST(1, floor(cfg.project_id_cap_pct * p_n)::INT);
  dims := COALESCE(cfg.dist_dimensions, '{}');

  CREATE TEMP TABLE IF NOT EXISTS _cand (
    req_id TEXT, key TEXT, project_id TEXT, sbin TEXT, tier INT, rnd DOUBLE PRECISION,
    l1 SMALLINT, l2 SMALLINT, l3 SMALLINT, l4 SMALLINT, l5 SMALLINT, l6 SMALLINT
  ) ON COMMIT DROP;
  TRUNCATE _cand;
  INSERT INTO _cand
  SELECT r.req_id,
         CASE WHEN p_by_base THEN COALESCE(r.base_id, r.req_id) ELSE r.req_id END,
         r.project_id,
         r.sentence_bin,
         CASE WHEN COALESCE(c.n, 0) = 0 THEN 0 WHEN c.n < cfg.coverage_target THEN 1 ELSE 2 END,
         random(),
         (SELECT rl.llm_score FROM reference_labels rl WHERE rl.base_id = COALESCE(r.base_id, r.req_id) AND rl.metric_id = 'M_IND_01'),
         (SELECT rl.llm_score FROM reference_labels rl WHERE rl.base_id = COALESCE(r.base_id, r.req_id) AND rl.metric_id = 'M_IND_02'),
         (SELECT rl.llm_score FROM reference_labels rl WHERE rl.base_id = COALESCE(r.base_id, r.req_id) AND rl.metric_id = 'M_IND_03'),
         (SELECT rl.llm_score FROM reference_labels rl WHERE rl.base_id = COALESCE(r.base_id, r.req_id) AND rl.metric_id = 'M_IND_04'),
         (SELECT rl.llm_score FROM reference_labels rl WHERE rl.base_id = COALESCE(r.base_id, r.req_id) AND rl.metric_id = 'M_IND_05'),
         (SELECT rl.llm_score FROM reference_labels rl WHERE rl.base_id = COALESCE(r.base_id, r.req_id) AND rl.metric_id = 'M_IND_06')
  FROM requirements r
  LEFT JOIN (
    SELECT s.req_id, count(DISTINCT s.session_id) AS n
    FROM scores s
    JOIN batch_items bi ON bi.batch_item_id = s.batch_item_id AND NOT bi.is_attention_check
    JOIN sessions se ON se.session_id = s.session_id AND NOT se.excluded
    GROUP BY s.req_id) c ON c.req_id = r.req_id
  WHERE r.eligible AND r.language_tag = p_lang;

  -- DIST targets: pool shares of the active dimensions (whole eligible pool of this language)
  IF cfg.sampling_strategy = 'DIST' THEN
    IF 'project_id' = ANY(dims) THEN
      SELECT shares || COALESCE(jsonb_object_agg('project_id|' || x.project_id, x.cnt::DOUBLE PRECISION / t.total), '{}')
      INTO shares
      FROM (SELECT project_id, count(*) AS cnt FROM _cand GROUP BY project_id HAVING count(*) >= 2) x,
           (SELECT count(*) AS total FROM _cand) t;
    END IF;
    IF 'sentence_bin' = ANY(dims) THEN
      SELECT shares || COALESCE(jsonb_object_agg('sentence_bin|' || x.sbin, x.cnt::DOUBLE PRECISION / t.total), '{}')
      INTO shares
      FROM (SELECT sbin, count(*) AS cnt FROM _cand WHERE sbin IS NOT NULL GROUP BY sbin HAVING count(*) >= 2) x,
           (SELECT count(*) AS total FROM _cand) t;
    END IF;
  END IF;

  -- SCORE-STRAT targets: allocation from app_config (default equal thirds)
  IF cfg.sampling_strategy = 'SCORE-STRAT' THEN
    sshare := ARRAY[
      COALESCE((cfg.score_strat_allocation ->> '0')::DOUBLE PRECISION, 0),
      COALESCE((cfg.score_strat_allocation ->> '1')::DOUBLE PRECISION, 0),
      COALESCE((cfg.score_strat_allocation ->> '2')::DOUBLE PRECISION, 0)];
  END IF;

  FOR pass IN 1..2 LOOP            -- pass 2 relaxes the ProjectID cap (ADD-01 §5 step 5)
    FOR tier_i IN 0..2 LOOP        -- priority tiers always come first (ADD-01 §5 step 3)
      LOOP
        EXIT WHEN cardinality(picked) >= p_n;
        n_now := cardinality(picked);
        found := FALSE;
        best_sc := NULL;
        FOR rec IN SELECT * FROM _cand WHERE tier = tier_i ORDER BY rnd LOOP
          CONTINUE WHEN rec.key = ANY (used) OR rec.req_id = ANY (picked);
          IF pass = 1 AND COALESCE((per_project ->> rec.project_id)::INT, 0) >= cap THEN CONTINUE; END IF;

          sc := 0;
          IF cfg.sampling_strategy = 'DIST' THEN
            IF 'project_id' = ANY(dims) AND shares ? ('project_id|' || rec.project_id) THEN
              k := 'project_id|' || rec.project_id;
              sc := sc + (shares ->> k)::DOUBLE PRECISION * (n_now + 1) - COALESCE((dcnt ->> k)::DOUBLE PRECISION, 0);
            END IF;
            IF 'sentence_bin' = ANY(dims) AND rec.sbin IS NOT NULL AND shares ? ('sentence_bin|' || rec.sbin) THEN
              k := 'sentence_bin|' || rec.sbin;
              sc := sc + (shares ->> k)::DOUBLE PRECISION * (n_now + 1) - COALESCE((dcnt ->> k)::DOUBLE PRECISION, 0);
            END IF;
          ELSIF cfg.sampling_strategy = 'SCORE-STRAT' THEN
            lv := ARRAY[rec.l1, rec.l2, rec.l3, rec.l4, rec.l5, rec.l6]::INT[];
            FOR m IN 1..6 LOOP
              IF lv[m] IS NOT NULL THEN
                idx := (m - 1) * 3 + lv[m] + 1;
                sc := sc + sshare[lv[m] + 1] * (n_now + 1) - scnt[idx];
              END IF;
            END LOOP;
          END IF;

          -- strictly greater keeps the first (random) candidate on ties; RAND scores are always 0
          IF NOT found OR sc > best_sc THEN
            best := rec;
            best_sc := sc;
            found := TRUE;
          END IF;
        END LOOP;

        EXIT WHEN NOT found;

        picked := picked || best.req_id;
        used := used || best.key;
        per_project := per_project || jsonb_build_object(best.project_id, COALESCE((per_project ->> best.project_id)::INT, 0) + 1);

        IF cfg.sampling_strategy = 'DIST' THEN
          IF 'project_id' = ANY(dims) AND shares ? ('project_id|' || best.project_id) THEN
            k := 'project_id|' || best.project_id;
            dcnt := dcnt || jsonb_build_object(k, COALESCE((dcnt ->> k)::INT, 0) + 1);
          END IF;
          IF 'sentence_bin' = ANY(dims) AND best.sbin IS NOT NULL AND shares ? ('sentence_bin|' || best.sbin) THEN
            k := 'sentence_bin|' || best.sbin;
            dcnt := dcnt || jsonb_build_object(k, COALESCE((dcnt ->> k)::INT, 0) + 1);
          END IF;
        ELSIF cfg.sampling_strategy = 'SCORE-STRAT' THEN
          lv := ARRAY[best.l1, best.l2, best.l3, best.l4, best.l5, best.l6]::INT[];
          FOR m IN 1..6 LOOP
            IF lv[m] IS NOT NULL THEN
              idx := (m - 1) * 3 + lv[m] + 1;
              scnt[idx] := scnt[idx] + 1;
            END IF;
          END LOOP;
        END IF;
      END LOOP;
    END LOOP;
    EXIT WHEN cardinality(picked) >= p_n;
  END LOOP;
  RETURN picked;
END;
$$;
REVOKE ALL ON FUNCTION pick_requirements(TEXT, TEXT, INT, TEXT[], BOOLEAN) FROM PUBLIC, anon;

-- ---------- verification (run after the migration; expect the values in the comments) ----------
-- SELECT count(*) FILTER (WHERE sentence_bin IS NULL) AS missing_bin FROM requirements WHERE eligible;   -- expect 0
-- SELECT sentence_bin, count(*) FROM requirements GROUP BY 1;                                            -- SHORT/MEDIUM/LONG only
-- SELECT proname, prosecdef FROM pg_proc WHERE proname IN ('pick_requirements','admin_import_requirements'); -- prosecdef = true
