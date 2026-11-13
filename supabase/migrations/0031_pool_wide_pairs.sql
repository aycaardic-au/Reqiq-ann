-- ReqIQ-ANN migration 0031 — BOTH sessions use the same pool-wide allocation as EN/TR (ADD-01 §5, FR-ASN-012;
-- ToDO section J; user decision 13 Nov 2026).
-- Replaces pick_pairs from 0024. assign_batch (0025) is unchanged: it calls pick_pairs(p_session_id, n, used_reqs)
-- and keeps the TR-then-EN order inside each pair.
-- Unit = one base_id (EN and TR version together). Pre-scores are stored per base_id, so both versions of a base
-- share the same allocation score. The pair's score count is LEAST(EN count, TR count).
-- 1. Order: lowest pair score count first; the next count is used only when the current group runs out (as in 0030).
-- 2. Allocation score (same as 0030): SCORE-STRAT average over the pre-score deficits; fallback = sentence-bin
--    deficit of the EN version; DIST uses sentence_bin only; the ProjectID cap (25 %, pass 1 strict, pass 2 relaxed)
--    stays for all strategies.
-- Activation is unchanged (app_config.sampling_strategy). Re-run safe.
-- Run in Supabase SQL Editor AFTER 0030.

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
    LEFT JOIN (
      SELECT s.req_id, count(DISTINCT s.session_id) AS n
      FROM scores s
      JOIN batch_items bi ON bi.batch_item_id = s.batch_item_id AND NOT bi.is_attention_check
      JOIN sessions se ON se.session_id = s.session_id AND NOT se.excluded
      GROUP BY s.req_id) ce ON ce.req_id = en.req_id
    LEFT JOIN (
      SELECT s.req_id, count(DISTINCT s.session_id) AS n
      FROM scores s
      JOIN batch_items bi ON bi.batch_item_id = s.batch_item_id AND NOT bi.is_attention_check
      JOIN sessions se ON se.session_id = s.session_id AND NOT se.excluded
      GROUP BY s.req_id) ct ON ct.req_id = tr.req_id
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
REVOKE ALL ON FUNCTION pick_pairs(TEXT, INT, TEXT[]) FROM PUBLIC, anon;

-- Verify (expect prosecdef = true)
SELECT proname, prosecdef FROM pg_proc WHERE proname = 'pick_pairs';
