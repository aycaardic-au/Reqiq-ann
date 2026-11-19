-- ReqIQ-ANN migration 0043 — in-flight assignments count in the allocation (audit finding B3, 18 Nov 2026; decision D-81).
-- Problem: pick_requirements (0030) and pick_pairs (0031) rank candidates by the number of sessions that have SCORED them.
--   Items assigned to an open batch but not yet scored are not counted, so concurrent sessions can receive the same
--   low-count items while other items wait.
-- Change: a new helper alloc_session_counts(p_session_id) counts, per requirement, the distinct sessions that
--   (a) have scored it (same rule as before), or
--   (b) hold it in an open batch (completed_at IS NULL) and were active within the last 120 minutes
--       (not ended, not excluded, not the calling session; attention-check copies are ignored).
--   A session that both holds and has scored an item counts once. The two functions are re-created from 0030 and 0031
--   with ONLY the count source replaced. Round numbers stored with a batch item (batch_items.round, D-07) still use
--   req_score_sessions (scored sessions only) and are unchanged.
-- The 120-minute window is a parameter of the helper (default argument). Abandoned open batches stop counting after it.
-- Run once in Supabase SQL Editor AFTER 0042. Re-run safe (CREATE OR REPLACE).

BEGIN;

CREATE OR REPLACE FUNCTION alloc_session_counts(p_session_id TEXT, p_window_minutes INT DEFAULT 120)
RETURNS TABLE (req_id TEXT, n INT) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT x.req_id, count(DISTINCT x.session_id)::INT
  FROM (
    SELECT s.req_id, s.session_id
    FROM scores s
    JOIN batch_items bi ON bi.batch_item_id = s.batch_item_id AND NOT bi.is_attention_check
    JOIN sessions se ON se.session_id = s.session_id AND NOT se.excluded
    UNION
    SELECT bi.req_id, b.session_id
    FROM batch_items bi
    JOIN batches b ON b.batch_id = bi.batch_id AND b.completed_at IS NULL
    JOIN sessions se ON se.session_id = b.session_id
    WHERE NOT bi.is_attention_check
      AND NOT se.excluded AND se.ended_at IS NULL
      AND se.last_active_at > now() - make_interval(mins => p_window_minutes)
      AND b.session_id <> p_session_id
  ) x
  GROUP BY x.req_id;
$$;
REVOKE ALL ON FUNCTION alloc_session_counts(TEXT, INT) FROM PUBLIC, anon;

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
  best_sc DOUBLE PRECISION;
  best_lv INT[];
  found BOOLEAN;
  sc DOUBLE PRECISION;
  sum_sc DOUBLE PRECISION;
  cnt_sc INT;
  pass INT;
  tier_i INT;
  n_now INT;
  cur_lvl INT;
  shares JSONB := '{}';                       -- 'sentence_bin|X' -> pool share (bins with >= 2 items)
  bcnt JSONB := '{}';                         -- 'sentence_bin|X' -> picks so far in this batch
  sshare DOUBLE PRECISION[] := ARRAY[0,0,0];  -- SCORE-STRAT target share for levels 0,1,2
  scnt INT[] := array_fill(0, ARRAY[18]);     -- (metric-1)*3 + level + 1 -> picks so far
  lv INT[];
  m INT;
  idx INT;
  k TEXT;
BEGIN
  SELECT * INTO cfg FROM app_config WHERE id = 1;
  IF p_n <= 0 THEN RETURN picked; END IF;
  cap := GREATEST(1, floor(cfg.project_id_cap_pct * p_n)::INT);

  CREATE TEMP TABLE IF NOT EXISTS _cand (
    req_id TEXT, key TEXT, project_id TEXT, sbin TEXT, cnt INT, tier INT, rnd DOUBLE PRECISION,
    l1 SMALLINT, l2 SMALLINT, l3 SMALLINT, l4 SMALLINT, l5 SMALLINT, l6 SMALLINT
  ) ON COMMIT DROP;
  TRUNCATE _cand;
  INSERT INTO _cand
  SELECT r.req_id,
         CASE WHEN p_by_base THEN COALESCE(r.base_id, r.req_id) ELSE r.req_id END,
         r.project_id,
         r.sentence_bin,
         COALESCE(c.n, 0),
         CASE WHEN COALESCE(c.n, 0) = 0 THEN 0 WHEN c.n < cfg.coverage_target THEN 1 ELSE 2 END,
         random(),
         (SELECT rl.llm_score FROM reference_labels rl WHERE rl.base_id = COALESCE(r.base_id, r.req_id) AND rl.metric_id = 'M_IND_01'),
         (SELECT rl.llm_score FROM reference_labels rl WHERE rl.base_id = COALESCE(r.base_id, r.req_id) AND rl.metric_id = 'M_IND_02'),
         (SELECT rl.llm_score FROM reference_labels rl WHERE rl.base_id = COALESCE(r.base_id, r.req_id) AND rl.metric_id = 'M_IND_03'),
         (SELECT rl.llm_score FROM reference_labels rl WHERE rl.base_id = COALESCE(r.base_id, r.req_id) AND rl.metric_id = 'M_IND_04'),
         (SELECT rl.llm_score FROM reference_labels rl WHERE rl.base_id = COALESCE(r.base_id, r.req_id) AND rl.metric_id = 'M_IND_05'),
         (SELECT rl.llm_score FROM reference_labels rl WHERE rl.base_id = COALESCE(r.base_id, r.req_id) AND rl.metric_id = 'M_IND_06')
  FROM requirements r
  LEFT JOIN alloc_session_counts(p_session_id) c ON c.req_id = r.req_id   -- 0043: scored + in-flight
  WHERE r.eligible AND r.language_tag = p_lang;

  IF NOT EXISTS (SELECT 1 FROM _cand) THEN RETURN picked; END IF;

  -- Sentence-bin pool shares (fallback balance for every candidate without a pre-score)
  SELECT COALESCE(jsonb_object_agg('sentence_bin|' || x.sbin, x.cnt::DOUBLE PRECISION / t.total), '{}')
  INTO shares
  FROM (SELECT sbin, count(*) AS cnt FROM _cand WHERE sbin IS NOT NULL GROUP BY sbin HAVING count(*) >= 2) x,
       (SELECT count(*) AS total FROM _cand) t;

  -- SCORE-STRAT target shares from app_config (default equal thirds)
  IF cfg.sampling_strategy = 'SCORE-STRAT' THEN
    sshare := ARRAY[
      COALESCE((cfg.score_strat_allocation ->> '0')::DOUBLE PRECISION, 0),
      COALESCE((cfg.score_strat_allocation ->> '1')::DOUBLE PRECISION, 0),
      COALESCE((cfg.score_strat_allocation ->> '2')::DOUBLE PRECISION, 0)];
  END IF;

  FOR pass IN 1..2 LOOP            -- pass 2 relaxes the ProjectID cap (ADD-01 §5 step 5)
    FOR tier_i IN 0..2 LOOP        -- tier order (tiers follow the count, so this is also the count order)
      LOOP
        EXIT WHEN cardinality(picked) >= p_n;
        n_now := cardinality(picked);
        found := FALSE;
        best_sc := NULL;
        -- lowest count still available in this tier (respecting the cap of this pass)
        SELECT min(c.cnt) INTO cur_lvl FROM _cand c
        WHERE c.tier = tier_i AND NOT (c.key = ANY (used)) AND NOT (c.req_id = ANY (picked))
          AND (pass = 2 OR COALESCE((per_project ->> c.project_id)::INT, 0) < cap);
        FOR rec IN SELECT * FROM _cand WHERE tier = tier_i AND cnt = cur_lvl ORDER BY rnd LOOP
          CONTINUE WHEN rec.key = ANY (used) OR rec.req_id = ANY (picked);
          IF pass = 1 AND COALESCE((per_project ->> rec.project_id)::INT, 0) >= cap THEN CONTINUE; END IF;

          sc := 0;
          IF cfg.sampling_strategy IN ('DIST', 'SCORE-STRAT') THEN
            sum_sc := 0;
            cnt_sc := 0;
            IF cfg.sampling_strategy = 'SCORE-STRAT' THEN
              lv := ARRAY[rec.l1, rec.l2, rec.l3, rec.l4, rec.l5, rec.l6]::INT[];
              FOR m IN 1..6 LOOP
                IF lv[m] IS NOT NULL THEN
                  idx := (m - 1) * 3 + lv[m] + 1;
                  sum_sc := sum_sc + sshare[lv[m] + 1] * (n_now + 1) - scnt[idx];
                  cnt_sc := cnt_sc + 1;
                END IF;
              END LOOP;
            END IF;
            -- no pre-score (or DIST strategy): sentence-bin deficit
            IF cnt_sc = 0 AND rec.sbin IS NOT NULL AND shares ? ('sentence_bin|' || rec.sbin) THEN
              k := 'sentence_bin|' || rec.sbin;
              sum_sc := (shares ->> k)::DOUBLE PRECISION * (n_now + 1) - COALESCE((bcnt ->> k)::DOUBLE PRECISION, 0);
              cnt_sc := 1;
            END IF;
            IF cnt_sc > 0 THEN sc := sum_sc / cnt_sc; END IF;
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

        -- counters for all picks (both fallback and level balance refer to all picks of the batch)
        IF best.sbin IS NOT NULL AND shares ? ('sentence_bin|' || best.sbin) THEN
          k := 'sentence_bin|' || best.sbin;
          bcnt := bcnt || jsonb_build_object(k, COALESCE((bcnt ->> k)::INT, 0) + 1);
        END IF;
        lv := ARRAY[best.l1, best.l2, best.l3, best.l4, best.l5, best.l6]::INT[];
        FOR m IN 1..6 LOOP
          IF lv[m] IS NOT NULL THEN
            idx := (m - 1) * 3 + lv[m] + 1;
            scnt[idx] := scnt[idx] + 1;
          END IF;
        END LOOP;
      END LOOP;
    END LOOP;
    EXIT WHEN cardinality(picked) >= p_n;
  END LOOP;
  RETURN picked;
END;
$$;

CREATE OR REPLACE FUNCTION pick_pairs(p_session_id TEXT, p_n INT, p_exclude TEXT[])
RETURNS TEXT[] LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  cfg app_config%ROWTYPE;
  picked TEXT[] := '{}';                      -- base_ids
  used TEXT[] := COALESCE(p_exclude, '{}');   -- req_ids already shown to this session
  per_project JSONB := '{}';
  cap INT;
  rec RECORD;
  best RECORD;
  best_sc DOUBLE PRECISION;
  found BOOLEAN;
  sc DOUBLE PRECISION;
  sum_sc DOUBLE PRECISION;
  cnt_sc INT;
  pass INT;
  tier_i INT;
  n_now INT;
  cur_lvl INT;
  shares JSONB := '{}';
  bcnt JSONB := '{}';
  sshare DOUBLE PRECISION[] := ARRAY[0,0,0];
  scnt INT[] := array_fill(0, ARRAY[18]);
  lv INT[];
  m INT;
  idx INT;
  k TEXT;
BEGIN
  SELECT * INTO cfg FROM app_config WHERE id = 1;
  IF p_n <= 0 THEN RETURN picked; END IF;
  cap := GREATEST(1, floor(cfg.project_id_cap_pct * p_n)::INT);

  CREATE TEMP TABLE IF NOT EXISTS _pair (
    base_id TEXT, en_req TEXT, tr_req TEXT, project_id TEXT, sbin TEXT, cnt INT, tier INT, rnd DOUBLE PRECISION,
    l1 SMALLINT, l2 SMALLINT, l3 SMALLINT, l4 SMALLINT, l5 SMALLINT, l6 SMALLINT
  ) ON COMMIT DROP;
  TRUNCATE _pair;
  INSERT INTO _pair
  SELECT x.base_id, x.en_req, x.tr_req, x.project_id, x.sbin, x.cnt,
         CASE WHEN x.cnt = 0 THEN 0 WHEN x.cnt < cfg.coverage_target THEN 1 ELSE 2 END,
         random(),
         (SELECT rl.llm_score FROM reference_labels rl WHERE rl.base_id = x.base_id AND rl.metric_id = 'M_IND_01'),
         (SELECT rl.llm_score FROM reference_labels rl WHERE rl.base_id = x.base_id AND rl.metric_id = 'M_IND_02'),
         (SELECT rl.llm_score FROM reference_labels rl WHERE rl.base_id = x.base_id AND rl.metric_id = 'M_IND_03'),
         (SELECT rl.llm_score FROM reference_labels rl WHERE rl.base_id = x.base_id AND rl.metric_id = 'M_IND_04'),
         (SELECT rl.llm_score FROM reference_labels rl WHERE rl.base_id = x.base_id AND rl.metric_id = 'M_IND_05'),
         (SELECT rl.llm_score FROM reference_labels rl WHERE rl.base_id = x.base_id AND rl.metric_id = 'M_IND_06')
  FROM (
    SELECT en.base_id, en.req_id AS en_req, tr.req_id AS tr_req, en.project_id, en.sentence_bin AS sbin,
           LEAST(COALESCE(ce.n, 0), COALESCE(ct.n, 0)) AS cnt
    FROM requirements en
    JOIN requirements tr ON tr.base_id = en.base_id AND tr.language_tag = 'TR' AND tr.eligible
    LEFT JOIN alloc_session_counts(p_session_id) ce ON ce.req_id = en.req_id   -- 0043: scored + in-flight
    LEFT JOIN alloc_session_counts(p_session_id) ct ON ct.req_id = tr.req_id   -- 0043: scored + in-flight
    WHERE en.language_tag = 'EN' AND en.eligible AND en.base_id IS NOT NULL
  ) x;

  IF NOT EXISTS (SELECT 1 FROM _pair) THEN RETURN picked; END IF;

  SELECT COALESCE(jsonb_object_agg('sentence_bin|' || y.sbin, y.cnt::DOUBLE PRECISION / t.total), '{}')
  INTO shares
  FROM (SELECT sbin, count(*) AS cnt FROM _pair WHERE sbin IS NOT NULL GROUP BY sbin HAVING count(*) >= 2) y,
       (SELECT count(*) AS total FROM _pair) t;

  IF cfg.sampling_strategy = 'SCORE-STRAT' THEN
    sshare := ARRAY[
      COALESCE((cfg.score_strat_allocation ->> '0')::DOUBLE PRECISION, 0),
      COALESCE((cfg.score_strat_allocation ->> '1')::DOUBLE PRECISION, 0),
      COALESCE((cfg.score_strat_allocation ->> '2')::DOUBLE PRECISION, 0)];
  END IF;

  FOR pass IN 1..2 LOOP
    FOR tier_i IN 0..2 LOOP
      LOOP
        EXIT WHEN cardinality(picked) >= p_n;
        n_now := cardinality(picked);
        found := FALSE;
        best_sc := NULL;
        SELECT min(c.cnt) INTO cur_lvl FROM _pair c
        WHERE c.tier = tier_i AND NOT (c.en_req = ANY (used)) AND NOT (c.tr_req = ANY (used))
          AND NOT (c.base_id = ANY (picked))
          AND (pass = 2 OR COALESCE((per_project ->> c.project_id)::INT, 0) < cap);
        FOR rec IN SELECT * FROM _pair WHERE tier = tier_i AND cnt = cur_lvl ORDER BY rnd LOOP
          CONTINUE WHEN rec.en_req = ANY (used) OR rec.tr_req = ANY (used) OR rec.base_id = ANY (picked);
          IF pass = 1 AND COALESCE((per_project ->> rec.project_id)::INT, 0) >= cap THEN CONTINUE; END IF;

          sc := 0;
          IF cfg.sampling_strategy IN ('DIST', 'SCORE-STRAT') THEN
            sum_sc := 0;
            cnt_sc := 0;
            IF cfg.sampling_strategy = 'SCORE-STRAT' THEN
              lv := ARRAY[rec.l1, rec.l2, rec.l3, rec.l4, rec.l5, rec.l6]::INT[];
              FOR m IN 1..6 LOOP
                IF lv[m] IS NOT NULL THEN
                  idx := (m - 1) * 3 + lv[m] + 1;
                  sum_sc := sum_sc + sshare[lv[m] + 1] * (n_now + 1) - scnt[idx];
                  cnt_sc := cnt_sc + 1;
                END IF;
              END LOOP;
            END IF;
            IF cnt_sc = 0 AND rec.sbin IS NOT NULL AND shares ? ('sentence_bin|' || rec.sbin) THEN
              k := 'sentence_bin|' || rec.sbin;
              sum_sc := (shares ->> k)::DOUBLE PRECISION * (n_now + 1) - COALESCE((bcnt ->> k)::DOUBLE PRECISION, 0);
              cnt_sc := 1;
            END IF;
            IF cnt_sc > 0 THEN sc := sum_sc / cnt_sc; END IF;
          END IF;

          IF NOT found OR sc > best_sc THEN
            best := rec;
            best_sc := sc;
            found := TRUE;
          END IF;
        END LOOP;

        EXIT WHEN NOT found;

        picked := picked || best.base_id;
        used := used || best.en_req || best.tr_req;
        per_project := per_project || jsonb_build_object(best.project_id, COALESCE((per_project ->> best.project_id)::INT, 0) + 1);

        IF best.sbin IS NOT NULL AND shares ? ('sentence_bin|' || best.sbin) THEN
          k := 'sentence_bin|' || best.sbin;
          bcnt := bcnt || jsonb_build_object(k, COALESCE((bcnt ->> k)::INT, 0) + 1);
        END IF;
        lv := ARRAY[best.l1, best.l2, best.l3, best.l4, best.l5, best.l6]::INT[];
        FOR m IN 1..6 LOOP
          IF lv[m] IS NOT NULL THEN
            idx := (m - 1) * 3 + lv[m] + 1;
            scnt[idx] := scnt[idx] + 1;
          END IF;
        END LOOP;
      END LOOP;
    END LOOP;
    EXIT WHEN cardinality(picked) >= p_n;
  END LOOP;
  RETURN picked;
END;
$$;

REVOKE ALL ON FUNCTION pick_requirements(TEXT, TEXT, INT, TEXT[], BOOLEAN) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION pick_pairs(TEXT, INT, TEXT[]) FROM PUBLIC, anon;

COMMIT;
