-- ReqIQ-ANN migration 0013 — batch assignment, score saving, batch completion, comment (K5, K6, Teşekkürler)
-- FR-ASN-001..011, FR-ANN-009/011/012, FR-BTH, NFR-REL-001; D-07, D-08, D-14, D-15, D-21, D-27.
-- Sampling: priority tier (FR-ASN-003) + random within tier + ProjectID cap (FR-ASN-004, relaxed if needed).
-- app_config.sampling_strategy DIST / SCORE-STRAT / ADAPT are NOT implemented yet and behave as RAND (D-27).
-- Run in Supabase SQL Editor AFTER 0012. Re-run safe.

BEGIN;

ALTER TABLE batch_items ADD COLUMN IF NOT EXISTS round SMALLINT NOT NULL DEFAULT 1;

-- Distinct non-excluded sessions that scored a requirement (non-attention-check items)
CREATE OR REPLACE FUNCTION req_score_sessions(p_req_id TEXT, p_except_session TEXT DEFAULT NULL)
RETURNS INT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT count(DISTINCT s.session_id)::INT
  FROM scores s
  JOIN batch_items bi ON bi.batch_item_id = s.batch_item_id AND NOT bi.is_attention_check
  JOIN sessions se ON se.session_id = s.session_id AND NOT se.excluded
  WHERE s.req_id = p_req_id AND (p_except_session IS NULL OR s.session_id <> p_except_session);
$$;

-- Batch contents for the client: never reveals which items are attention checks.
CREATE OR REPLACE FUNCTION batch_payload(p_session_id TEXT, p_batch_id TEXT)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'status', 'ok',
    'batch_id', p_batch_id,
    'batch_number', (SELECT count(*) FROM batches WHERE session_id = p_session_id AND created_at <= b.created_at),
    'items', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'batch_item_id', bi.batch_item_id,
        'position', bi.position,
        'language_tag', r.language_tag,
        'text', CASE WHEN r.language_tag = 'EN' THEN r.text_en ELSE r.text_tr END,
        'scores', COALESCE((
          SELECT jsonb_agg(jsonb_build_object('metric_id', s.metric_id, 'score', s.score,
                                              'cannot_assess', s.cannot_assess, 'note', s.note))
          FROM scores s WHERE s.batch_item_id = bi.batch_item_id AND s.session_id = p_session_id), '[]'::jsonb)
      ) ORDER BY bi.position)
      FROM batch_items bi JOIN requirements r ON r.req_id = bi.req_id
      WHERE bi.batch_id = p_batch_id), '[]'::jsonb))
  FROM batches b WHERE b.batch_id = p_batch_id;
$$;

-- Pick up to p_n requirements of one language for a session (tiers, random, ProjectID cap).
CREATE OR REPLACE FUNCTION pick_requirements(p_session_id TEXT, p_lang TEXT, p_n INT, p_exclude_bases TEXT[])
RETURNS TEXT[] LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  cfg app_config%ROWTYPE;
  picked TEXT[] := '{}';
  bases TEXT[] := COALESCE(p_exclude_bases, '{}');
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
      SELECT r.req_id, r.base_id, r.project_id,
             req_score_sessions(r.req_id) AS n_sc
      FROM requirements r
      WHERE r.eligible AND r.language_tag = p_lang
        AND NOT (COALESCE(r.base_id, r.req_id) = ANY (bases))
        AND NOT (r.req_id = ANY (picked))
      ORDER BY CASE WHEN req_score_sessions(r.req_id) = 0 THEN 0
                    WHEN req_score_sessions(r.req_id) < cfg.coverage_target THEN 1 ELSE 2 END,
               random()
    LOOP
      EXIT WHEN cardinality(picked) >= p_n;
      CONTINUE WHEN COALESCE(rec.base_id, rec.req_id) = ANY (bases);
      IF pass = 1 AND COALESCE((per_project ->> rec.project_id)::INT, 0) >= cap THEN CONTINUE; END IF;
      picked := picked || rec.req_id;
      bases := bases || COALESCE(rec.base_id, rec.req_id);
      per_project := per_project || jsonb_build_object(rec.project_id, COALESCE((per_project ->> rec.project_id)::INT, 0) + 1);
    END LOOP;
    EXIT WHEN cardinality(picked) >= p_n;
  END LOOP;
  RETURN picked;
END;
$$;

-- K5: return the open batch of the session, or assign a new one (FR-ASN-010, FR-SES-006).
CREATE OR REPLACE FUNCTION assign_batch(p_session_id TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  cfg app_config%ROWTYPE;
  ses sessions%ROWTYPE;
  open_batch TEXT;
  n_unique INT;
  used_bases TEXT[];
  uniq TEXT[] := '{}';
  ord TEXT[];
  ac_n INT;
  ac_src INT;
  ins INT;
  i INT;
  v_batch TEXT := gen_random_uuid()::TEXT;
  v_req TEXT;
  is_ac BOOLEAN;
  ac_orig TEXT;
  ac_pos TEXT[] := '{}';
BEGIN
  SELECT * INTO ses FROM sessions WHERE session_id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'unknown session'; END IF;
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
  SELECT COALESCE(array_agg(DISTINCT COALESCE(r.base_id, r.req_id)), '{}') INTO used_bases
  FROM batches b JOIN batch_items bi ON bi.batch_id = b.batch_id JOIN requirements r ON r.req_id = bi.req_id
  WHERE b.session_id = p_session_id;

  IF ses.language_pref = 'BOTH' THEN                          -- D-14: equal EN and TR
    uniq := pick_requirements(p_session_id, 'EN', n_unique / 2, used_bases);
    SELECT used_bases || COALESCE(array_agg(COALESCE(base_id, req_id)), '{}') INTO used_bases
    FROM requirements WHERE req_id = ANY (uniq);
    uniq := uniq || pick_requirements(p_session_id, 'TR', n_unique - n_unique / 2, used_bases);
  ELSE
    uniq := pick_requirements(p_session_id, ses.language_pref, n_unique, used_bases);
  END IF;

  IF cardinality(uniq) = 0 THEN
    RETURN jsonb_build_object('status', 'exhausted');          -- FR-BTH-004
  END IF;

  -- Random order of the unique items
  SELECT array_agg(x ORDER BY random()) INTO ord FROM unnest(uniq) AS x;

  -- Attention checks (FR-ASN-005): duplicate items placed at least 3 positions after the original
  ac_n := CASE WHEN cardinality(ord) >= 8 THEN cfg.attention_check_count ELSE 0 END;
  FOR i IN 1..ac_n LOOP
    ac_src := 1 + floor(random() * (cardinality(ord) - 4))::INT;         -- original in the first part
    WHILE ord[ac_src] = ANY (ac_pos) OR ord[ac_src] LIKE 'AC:%' LOOP ac_src := 1 + floor(random() * (cardinality(ord) - 4))::INT; END LOOP;
    ins := ac_src + 3 + floor(random() * (cardinality(ord) - ac_src - 2))::INT;  -- insert before position ins
    ac_pos := ac_pos || ord[ac_src];
    ord := ord[1:ins - 1] || ('AC:' || ord[ac_src]) || ord[ins:cardinality(ord)];
  END LOOP;

  INSERT INTO batches (batch_id, session_id) VALUES (v_batch, p_session_id);
  FOR i IN 1..cardinality(ord) LOOP
    is_ac := ord[i] LIKE 'AC:%';
    v_req := CASE WHEN is_ac THEN substr(ord[i], 4) ELSE ord[i] END;
    ac_orig := CASE WHEN is_ac THEN v_req END;
    INSERT INTO batch_items (batch_id, req_id, position, is_attention_check, attention_check_original_req_id, round)
    VALUES (v_batch, v_req, i, is_ac, ac_orig, 1 + req_score_sessions(v_req, p_session_id));   -- D-07
  END LOOP;
  UPDATE sessions SET last_active_at = now() WHERE session_id = p_session_id;
  RETURN batch_payload(p_session_id, v_batch);
END;
$$;

-- K5: save the six metric scores of one item (FR-ANN-008/009/011, NFR-REL-001). Re-saving overwrites.
CREATE OR REPLACE FUNCTION save_scores(p_session_id TEXT, p_batch_item_id BIGINT, p_scores JSONB, p_time_seconds REAL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  item RECORD;
  m JSONB;
  v_ca BOOLEAN;
  v_score SMALLINT;
  v_note TEXT;
BEGIN
  SELECT bi.batch_item_id, bi.req_id, bi.round, r.language_tag, b.completed_at
  INTO item
  FROM batch_items bi JOIN batches b ON b.batch_id = bi.batch_id JOIN requirements r ON r.req_id = bi.req_id
  WHERE bi.batch_item_id = p_batch_item_id AND b.session_id = p_session_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'unknown item for this session'; END IF;
  IF item.completed_at IS NOT NULL THEN RAISE EXCEPTION 'batch already completed'; END IF;
  IF jsonb_array_length(p_scores) <> 6
     OR (SELECT count(DISTINCT x->>'metric_id') FROM jsonb_array_elements(p_scores) x
         WHERE x->>'metric_id' IN ('M_IND_01','M_IND_02','M_IND_03','M_IND_04','M_IND_05','M_IND_06')) <> 6 THEN
    RAISE EXCEPTION 'all six metrics are required';
  END IF;

  FOR m IN SELECT * FROM jsonb_array_elements(p_scores) LOOP
    v_ca := COALESCE((m->>'cannot_assess')::BOOLEAN, FALSE);
    v_score := CASE WHEN v_ca THEN NULL ELSE (m->>'score')::SMALLINT END;
    IF NOT v_ca AND (v_score IS NULL OR v_score NOT IN (0,1,2)) THEN RAISE EXCEPTION 'invalid score'; END IF;
    v_note := NULLIF(btrim(m->>'note'), '');
    IF char_length(v_note) > 500 THEN RAISE EXCEPTION 'note longer than 500 characters'; END IF;
    INSERT INTO scores (session_id, batch_item_id, req_id, metric_id, score, cannot_assess, note, annotation_language, round)
    VALUES (p_session_id, p_batch_item_id, item.req_id, m->>'metric_id', v_score, v_ca, v_note, item.language_tag, item.round)
    ON CONFLICT (session_id, batch_item_id, metric_id)
    DO UPDATE SET score = EXCLUDED.score, cannot_assess = EXCLUDED.cannot_assess, note = EXCLUDED.note;
  END LOOP;

  UPDATE batch_items SET time_seconds = COALESCE(time_seconds, 0) + GREATEST(0, LEAST(COALESCE(p_time_seconds, 0), 3600))
  WHERE batch_item_id = p_batch_item_id;
  UPDATE sessions SET last_active_at = now() WHERE session_id = p_session_id;
END;
$$;

-- K6: close the batch once every item has six scores (FR-ANN-012). Idempotent.
CREATE OR REPLACE FUNCTION complete_batch(p_session_id TEXT, p_batch_id TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  b batches%ROWTYPE;
  missing INT;
  cfg app_config%ROWTYPE;
  ses sessions%ROWTYPE;
BEGIN
  SELECT * INTO b FROM batches WHERE batch_id = p_batch_id AND session_id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'unknown batch for this session'; END IF;
  SELECT count(*) INTO missing FROM batch_items bi
  WHERE bi.batch_id = p_batch_id
    AND (SELECT count(*) FROM scores s WHERE s.batch_item_id = bi.batch_item_id AND s.session_id = p_session_id) < 6;
  IF missing > 0 THEN RAISE EXCEPTION 'batch has % unscored items', missing; END IF;
  IF b.completed_at IS NULL THEN
    UPDATE batches SET completed_at = now() WHERE batch_id = p_batch_id;
    UPDATE sessions SET batches_completed = batches_completed + 1, last_active_at = now() WHERE session_id = p_session_id;
  END IF;
  SELECT * INTO cfg FROM app_config WHERE id = 1;
  SELECT * INTO ses FROM sessions WHERE session_id = p_session_id;
  RETURN jsonb_build_object(
    'batch_count', (SELECT count(*) FROM batch_items WHERE batch_id = p_batch_id),
    'total', (SELECT count(*) FROM batch_items bi JOIN batches bb ON bb.batch_id = bi.batch_id
              WHERE bb.session_id = p_session_id AND bb.completed_at IS NOT NULL),
    'batches_completed', ses.batches_completed,
    'can_continue', ses.batches_completed < cfg.max_batches_per_session);
END;
$$;

-- Thank-you comment (ADD-02 §6). Re-saving overwrites.
CREATE OR REPLACE FUNCTION set_comment(p_session_id TEXT, p_comment TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v TEXT := NULLIF(btrim(p_comment), '');
BEGIN
  IF char_length(v) > 500 THEN RAISE EXCEPTION 'comment longer than 500 characters'; END IF;
  UPDATE sessions SET comment = v, last_active_at = now() WHERE session_id = p_session_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'unknown session'; END IF;
END;
$$;

REVOKE ALL ON FUNCTION req_score_sessions(TEXT, TEXT), batch_payload(TEXT, TEXT),
  pick_requirements(TEXT, TEXT, INT, TEXT[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION assign_batch(TEXT), save_scores(TEXT, BIGINT, JSONB, REAL),
  complete_batch(TEXT, TEXT), set_comment(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION assign_batch(TEXT), save_scores(TEXT, BIGINT, JSONB, REAL),
  complete_batch(TEXT, TEXT), set_comment(TEXT, TEXT) TO anon;

COMMIT;

-- Verify: expect 4 rows, all security_definer = true
SELECT proname, prosecdef AS security_definer FROM pg_proc
WHERE proname IN ('assign_batch','save_scores','complete_batch','set_comment') ORDER BY proname;
