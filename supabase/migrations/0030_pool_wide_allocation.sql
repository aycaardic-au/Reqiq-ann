-- ReqIQ-ANN migration 0030 (ADD-01 §5, FR-ASN-012, OI-23; section J of ToDO.md, 13 Nov 2026)
-- Replaces pick_requirements (0027) with pool-wide allocation:
-- 1. Round order (D-53): a batch takes candidates with the lowest valid score count first.
--    Within a tier, only candidates whose count equals the lowest remaining count are eligible.
--    If that group runs out before the batch is full, the rest is filled from the next count
--    (e.g. 5 leftovers of round 2 are taken first, then 20 items that already have 2 scores,
--    which starts round 3 for the batch). No target number is needed. (Decision 13 Nov 2026.)
-- 2. Tier order (0 = unscored, 1 = below coverage_target, 2 = at/above) is kept inside the gate.
-- 3. One allocation score per candidate, same unit (expected missing picks):
--    SCORE-STRAT: average over the candidate's available metric pre-scores of
--                 (target share of the level x (picks so far + 1) - picks so far at that level);
--    fallback (no pre-score, or DIST strategy): sentence-bin deficit, same formula on sentence_bin.
--    Candidates with no pre-score are therefore not starved (ToDO J, decision approved 13 Nov 2026).
-- 4. DIST uses sentence_bin only (decision B, option 2). project_id is no longer a DIST dimension.
--    The ProjectID cap (25 %, pass 1 strict, pass 2 relaxed) stays for all strategies.
-- 5. Counters: bin counts and level counts are updated for every pick (all strategies), so
--    the deficit always refers to all picks made in the batch.
-- Activation is unchanged (app_config.sampling_strategy). Safe to re-run.
-- Run once in Supabase SQL Editor AFTER 0029.

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
  LEFT JOIN (
    SELECT s.req_id, count(DISTINCT s.session_id) AS n
    FROM scores s
    JOIN batch_items bi ON bi.batch_item_id = s.batch_item_id AND NOT bi.is_attention_check
    JOIN sessions se ON se.session_id = s.session_id AND NOT se.excluded
    GROUP BY s.req_id) c ON c.req_id = r.req_id
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
REVOKE ALL ON FUNCTION pick_requirements(TEXT, TEXT, INT, TEXT[], BOOLEAN) FROM PUBLIC, anon;

-- ---------- verification (expect the values in the comments) ----------
-- SELECT proname, prosecdef FROM pg_proc WHERE proname = 'pick_requirements';   -- prosecdef = true
