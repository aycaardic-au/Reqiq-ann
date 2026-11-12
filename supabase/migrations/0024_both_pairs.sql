-- ReqIQ-ANN migration 0024 — BOTH sessions see EN and TR versions of the same requirement as an adjacent pair.
-- Decision 12 Nov 2026 (user): a BOTH batch shows, for each selected base_id, the TR and EN version one after the
-- other (order within the pair random). The last batch of a BOTH session shows all remaining pairs (no sampling
-- when fewer remain than the batch needs). Attention checks are placed between pairs, never inside a pair.
-- Replaces assign_batch (0018). pick_requirements (0018) stays in use for EN and TR sessions.
-- Run in Supabase SQL Editor AFTER 0023. Re-run safe.

BEGIN;

-- BOTH: pick up to p_n base_ids that have an eligible EN and an eligible TR version (tiers, random, ProjectID cap).
CREATE OR REPLACE FUNCTION pick_pairs(p_session_id TEXT, p_n INT, p_exclude TEXT[])
RETURNS TEXT[] LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  cfg app_config%ROWTYPE;
  picked TEXT[] := '{}';
  used TEXT[] := COALESCE(p_exclude, '{}');     -- req_ids already shown to this session
  per_project JSONB := '{}';
  cap INT;
  rec RECORD;
  pass INT;
BEGIN
  SELECT * INTO cfg FROM app_config WHERE id = 1;
  IF p_n <= 0 THEN RETURN picked; END IF;
  cap := GREATEST(1, floor(cfg.project_id_cap_pct * p_n)::INT);
  FOR pass IN 1..2 LOOP            -- pass 2 relaxes the ProjectID cap (ADD-01 §5 step 5)
    FOR rec IN
      SELECT en.base_id, en.req_id AS en_req, tr.req_id AS tr_req, en.project_id,
             GREATEST(
               CASE WHEN req_score_sessions(en.req_id) = 0 THEN 0
                    WHEN req_score_sessions(en.req_id) < cfg.coverage_target THEN 1 ELSE 2 END,
               CASE WHEN req_score_sessions(tr.req_id) = 0 THEN 0
                    WHEN req_score_sessions(tr.req_id) < cfg.coverage_target THEN 1 ELSE 2 END
             ) AS tier
      FROM requirements en
      JOIN requirements tr ON tr.base_id = en.base_id AND tr.language_tag = 'TR' AND tr.eligible
      WHERE en.language_tag = 'EN' AND en.eligible AND en.base_id IS NOT NULL
      ORDER BY tier, random()
    LOOP
      EXIT WHEN cardinality(picked) >= p_n;
      CONTINUE WHEN rec.en_req = ANY (used) OR rec.tr_req = ANY (used) OR rec.base_id = ANY (picked);
      IF pass = 1 AND COALESCE((per_project ->> rec.project_id)::INT, 0) >= cap THEN CONTINUE; END IF;
      picked := picked || rec.base_id;
      used := used || rec.en_req || rec.tr_req;
      per_project := per_project || jsonb_build_object(rec.project_id, COALESCE((per_project ->> rec.project_id)::INT, 0) + 1);
    END LOOP;
    EXIT WHEN cardinality(picked) >= p_n;
  END LOOP;
  RETURN picked;
END;
$$;
REVOKE ALL ON FUNCTION pick_pairs(TEXT, INT, TEXT[]) FROM PUBLIC, anon;

-- assign_batch (0024): units = single requirements (EN/TR sessions), BOTH pairs "EN_x|TR_x" or "TR_x|EN_x",
-- attention checks "AC:req". Units are shuffled; attention checks are inserted between units at least 3 units
-- after their original; each unit is written as consecutive batch items.
CREATE OR REPLACE FUNCTION assign_batch(p_session_id TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  cfg app_config%ROWTYPE;
  ses sessions%ROWTYPE;
  open_batch TEXT;
  n_unique INT;
  used_bases TEXT[];
  used_reqs TEXT[];
  extra TEXT[];
  units TEXT[] := '{}';
  ord TEXT[];
  ac_n INT;
  ac_src INT;
  ins INT;
  i INT;
  pos INT := 0;
  v_batch TEXT := gen_random_uuid()::TEXT;
  v_req TEXT;
  is_ac BOOLEAN;
  ac_pos TEXT[] := '{}';
  b_bases TEXT[];
  b TEXT;
  en_req TEXT;
  tr_req TEXT;
BEGIN
  SELECT * INTO ses FROM sessions WHERE session_id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'unknown session'; END IF;
  IF ses.annotator_type IS NULL THEN RAISE EXCEPTION 'background form not completed'; END IF;
  IF ses.ended_at IS NOT NULL THEN RETURN jsonb_build_object('status', 'ended'); END IF;
  SELECT * INTO cfg FROM app_config WHERE id = 1;

  SELECT batch_id INTO open_batch FROM batches
  WHERE session_id = p_session_id AND completed_at IS NULL ORDER BY created_at DESC LIMIT 1;
  IF open_batch IS NOT NULL THEN
    RETURN batch_payload(p_session_id, open_batch);
  END IF;

  IF ses.batches_completed >= cfg.max_batches_per_session THEN
    RETURN jsonb_build_object('status', 'max_reached');
  END IF;

  -- Serialise assignment so concurrent sessions see consistent coverage counts
  PERFORM pg_advisory_xact_lock(hashtext('reqiq_assign'));

  n_unique := cfg.batch_size - cfg.attention_check_count;

  -- Requirements already shown to this session (EN/TR sessions: base-level rule, FR-ASN-009)
  SELECT COALESCE(array_agg(DISTINCT COALESCE(r.base_id, r.req_id)), '{}') INTO used_bases
  FROM batches b JOIN batch_items bi ON bi.batch_id = b.batch_id JOIN requirements r ON r.req_id = bi.req_id
  WHERE b.session_id = p_session_id;
  SELECT COALESCE(array_agg(DISTINCT bi.req_id), '{}') INTO used_reqs
  FROM batches b JOIN batch_items bi ON bi.batch_id = b.batch_id
  WHERE b.session_id = p_session_id;

  IF ses.language_pref = 'BOTH' THEN
    -- D-14 / D-30 / 12 Nov 2026: n_unique/2 pairs; each pair is TR and EN of one base_id, shown together
    b_bases := pick_pairs(p_session_id, n_unique / 2, used_reqs);
    FOREACH b IN ARRAY b_bases LOOP
      SELECT req_id INTO en_req FROM requirements WHERE base_id = b AND language_tag = 'EN' AND eligible LIMIT 1;
      SELECT req_id INTO tr_req FROM requirements WHERE base_id = b AND language_tag = 'TR' AND eligible LIMIT 1;
      IF en_req IS NULL OR tr_req IS NULL THEN CONTINUE; END IF;
      used_reqs := used_reqs || en_req || tr_req;
      IF random() < 0.5 THEN
        units := units || (en_req || '|' || tr_req);
      ELSE
        units := units || (tr_req || '|' || en_req);
      END IF;
    END LOOP;
    -- Odd number of unique items (e.g. 25 with batch size 27): one single requirement in a random language
    -- The single comes from the language with more unused requirements, so a leftover version is not lost.
    IF n_unique % 2 = 1 THEN
      extra := pick_requirements(p_session_id,
        CASE WHEN (SELECT count(*) FROM requirements WHERE eligible AND language_tag = 'EN' AND NOT (req_id = ANY (used_reqs)))
               >= (SELECT count(*) FROM requirements WHERE eligible AND language_tag = 'TR' AND NOT (req_id = ANY (used_reqs)))
             THEN 'EN' ELSE 'TR' END,
        1, used_reqs, FALSE);
      units := units || extra;
    END IF;
  ELSE
    units := pick_requirements(p_session_id, ses.language_pref, n_unique, used_bases, TRUE);
  END IF;

  IF cardinality(units) = 0 THEN
    RETURN jsonb_build_object('status', 'exhausted');          -- FR-BTH-004
  END IF;

  -- Random order of the units (a pair stays together)
  SELECT array_agg(x ORDER BY random()) INTO ord FROM unnest(units) AS x;

  -- Attention checks (FR-ASN-005): duplicate of a unit's first item, placed at least 3 units after the original
  ac_n := CASE WHEN cardinality(ord) >= 8 THEN cfg.attention_check_count ELSE 0 END;
  FOR i IN 1..ac_n LOOP
    ac_src := 1 + floor(random() * (cardinality(ord) - 4))::INT;
    WHILE ord[ac_src] = ANY (ac_pos) OR ord[ac_src] LIKE 'AC:%' LOOP
      ac_src := 1 + floor(random() * (cardinality(ord) - 4))::INT;
    END LOOP;
    ins := ac_src + 3 + floor(random() * (cardinality(ord) - ac_src - 2))::INT;
    ac_pos := ac_pos || ord[ac_src];
    ord := ord[1:ins - 1] || ('AC:' || split_part(ord[ac_src], '|', 1)) || ord[ins:cardinality(ord)];
  END LOOP;

  INSERT INTO batches (batch_id, session_id, config_id)
  VALUES (v_batch, p_session_id, (SELECT config_id FROM rubric_config WHERE is_active LIMIT 1));   -- FR-CFG-VER-002

  FOR i IN 1..cardinality(ord) LOOP
    is_ac := ord[i] LIKE 'AC:%';
    FOR v_req IN
      SELECT x FROM unnest(string_to_array(CASE WHEN is_ac THEN substr(ord[i], 4) ELSE ord[i] END, '|')) AS x
    LOOP
      pos := pos + 1;
      INSERT INTO batch_items (batch_id, req_id, position, is_attention_check, attention_check_original_req_id, round)
      VALUES (v_batch, v_req, pos, is_ac, CASE WHEN is_ac THEN v_req END, 1 + req_score_sessions(v_req, p_session_id));   -- D-07
    END LOOP;
  END LOOP;

  UPDATE sessions SET last_active_at = now() WHERE session_id = p_session_id;
  RETURN batch_payload(p_session_id, v_batch);
END;
$$;
REVOKE ALL ON FUNCTION assign_batch(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION assign_batch(TEXT) TO anon;

COMMIT;

-- Verify (expect 3 rows; assign_batch is SECURITY DEFINER)
SELECT proname, prosecdef FROM pg_proc WHERE proname IN ('pick_pairs', 'assign_batch', 'pick_requirements') ORDER BY proname;
