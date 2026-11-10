-- ReqIQ-ANN: remove "Cannot assess" (Değerlendirilemiyor) from the data model and RPCs.
-- Every metric now needs a score 0/1/2. Attention-check columns (ac_pairs, ac_mismatches, ac_max_diff,
-- flag_consistency) are NOT touched.
-- Requires: existing scores/reference_labels rows must have a score (no NULL). If the check below fails,
-- run admin_reset_study (Parametreler -> SIFIRLA) first, or remove the rows listed in the error.
-- Run in Supabase SQL Editor inside one transaction (BEGIN ... COMMIT).

BEGIN;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM scores WHERE score IS NULL) THEN
    RAISE EXCEPTION 'scores contains rows without a score (cannot_assess). Reset the study first (admin_reset_study).';
  END IF;
  IF EXISTS (SELECT 1 FROM reference_labels WHERE llm_score IS NULL) THEN
    RAISE EXCEPTION 'reference_labels contains rows without llm_score. Re-import or delete them first.';
  END IF;
END $$;

ALTER TABLE scores DROP COLUMN IF EXISTS cannot_assess;
ALTER TABLE scores ALTER COLUMN score SET NOT NULL;
ALTER TABLE reference_labels DROP COLUMN IF EXISTS llm_cannot_assess;
ALTER TABLE reference_labels ALTER COLUMN llm_score SET NOT NULL;

-- Annotator: save_scores (0016 version without cannot_assess)
CREATE OR REPLACE FUNCTION save_scores(p_session_id TEXT, p_batch_item_id BIGINT, p_scores JSONB, p_time_seconds REAL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  item RECORD;
  m JSONB;
  v_score SMALLINT;
  v_note TEXT;
BEGIN
  SELECT bi.batch_item_id, bi.req_id, bi.round, r.language_tag, b.completed_at
  INTO item
  FROM batch_items bi JOIN batches b ON b.batch_id = bi.batch_id JOIN requirements r ON r.req_id = bi.req_id
  WHERE bi.batch_item_id = p_batch_item_id AND b.session_id = p_session_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'unknown item for this session'; END IF;
  IF item.completed_at IS NOT NULL THEN RAISE EXCEPTION 'batch already completed'; END IF;
  IF NOT session_is_open(p_session_id) THEN RAISE EXCEPTION 'session ended'; END IF;
  IF jsonb_array_length(p_scores) <> 6
     OR (SELECT count(DISTINCT x->>'metric_id') FROM jsonb_array_elements(p_scores) x
         WHERE x->>'metric_id' IN ('M_IND_01','M_IND_02','M_IND_03','M_IND_04','M_IND_05','M_IND_06')) <> 6 THEN
    RAISE EXCEPTION 'all six metrics are required';
  END IF;

  FOR m IN SELECT * FROM jsonb_array_elements(p_scores) LOOP
    v_score := (m->>'score')::SMALLINT;
    IF v_score IS NULL OR v_score NOT IN (0,1,2) THEN RAISE EXCEPTION 'invalid score'; END IF;
    v_note := NULLIF(btrim(m->>'note'), '');
    IF char_length(v_note) > 500 THEN RAISE EXCEPTION 'note longer than 500 characters'; END IF;
    INSERT INTO scores (session_id, batch_item_id, req_id, metric_id, score, note, annotation_language, round)
    VALUES (p_session_id, p_batch_item_id, item.req_id, m->>'metric_id', v_score, v_note, item.language_tag, item.round)
    ON CONFLICT (session_id, batch_item_id, metric_id)
    DO UPDATE SET score = EXCLUDED.score, note = EXCLUDED.note;
  END LOOP;

  UPDATE batch_items SET time_seconds = COALESCE(time_seconds, 0) + GREATEST(0, LEAST(COALESCE(p_time_seconds, 0), 3600))
  WHERE batch_item_id = p_batch_item_id;
  UPDATE sessions SET last_active_at = now() WHERE session_id = p_session_id;
END;
$$;

-- Annotator: batch_payload (0013 version without cannot_assess)
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
          SELECT jsonb_agg(jsonb_build_object('metric_id', s.metric_id, 'score', s.score, 'note', s.note))
          FROM scores s WHERE s.batch_item_id = bi.batch_item_id AND s.session_id = p_session_id), '[]'::jsonb)
      ) ORDER BY bi.position)
      FROM batch_items bi JOIN requirements r ON r.req_id = bi.req_id
      WHERE bi.batch_id = p_batch_id), '[]'::jsonb))
  FROM batches b WHERE b.batch_id = p_batch_id;
$$;

-- Annotator: complete_batch (0018 version; attention-check comparison on score only)
CREATE OR REPLACE FUNCTION complete_batch(p_session_id TEXT, p_batch_id TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  b batches%ROWTYPE;
  missing INT;
  cfg app_config%ROWTYPE;
  ses sessions%ROWTYPE;
  v_pairs INT; v_mis INT; v_max INT; v_med REAL; v_sess_med REAL;
BEGIN
  SELECT * INTO b FROM batches WHERE batch_id = p_batch_id AND session_id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'unknown batch for this session'; END IF;
  SELECT count(*) INTO missing FROM batch_items bi
  WHERE bi.batch_id = p_batch_id
    AND (SELECT count(*) FROM scores s WHERE s.batch_item_id = bi.batch_item_id AND s.session_id = p_session_id) < 6;
  IF missing > 0 THEN RAISE EXCEPTION 'batch has % unscored items', missing; END IF;
  SELECT * INTO cfg FROM app_config WHERE id = 1;

  IF b.completed_at IS NULL THEN
    -- attention checks: compare each duplicate with its original, metric by metric
    SELECT count(*), count(*) FILTER (WHERE a.score IS DISTINCT FROM o.score),
           COALESCE(max(abs(a.score - o.score)), 0)
    INTO v_pairs, v_mis, v_max
    FROM batch_items d
    JOIN batch_items oi ON oi.batch_id = d.batch_id AND oi.req_id = d.req_id AND NOT oi.is_attention_check
    JOIN scores a ON a.batch_item_id = d.batch_item_id AND a.session_id = p_session_id
    JOIN scores o ON o.batch_item_id = oi.batch_item_id AND o.session_id = p_session_id AND o.metric_id = a.metric_id
    WHERE d.batch_id = p_batch_id AND d.is_attention_check;
    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY time_seconds) INTO v_med
    FROM batch_items WHERE batch_id = p_batch_id AND time_seconds IS NOT NULL;

    UPDATE batches SET completed_at = now(), ac_pairs = v_pairs, ac_mismatches = v_mis, ac_max_diff = v_max, median_seconds = v_med
    WHERE batch_id = p_batch_id;

    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY bi.time_seconds) INTO v_sess_med
    FROM batch_items bi JOIN batches bb ON bb.batch_id = bi.batch_id
    WHERE bb.session_id = p_session_id AND bb.completed_at IS NOT NULL AND bi.time_seconds IS NOT NULL;

    UPDATE sessions SET
      batches_completed = batches_completed + 1,
      flag_consistency = flag_consistency OR v_max >= 2,                      -- FR-QC-003: 0↔2 on any metric
      flag_speed = COALESCE(v_sess_med < cfg.speed_flag_threshold_sec, FALSE), -- FR-QC-004: re-evaluated each batch
      last_active_at = now()
    WHERE session_id = p_session_id;
  END IF;

  SELECT * INTO ses FROM sessions WHERE session_id = p_session_id;
  RETURN jsonb_build_object(
    'batch_count', (SELECT count(*) FROM batch_items WHERE batch_id = p_batch_id),
    'batch_number', (SELECT count(*) FROM batches WHERE session_id = p_session_id AND created_at <= b.created_at),
    'total', (SELECT count(*) FROM batch_items bi JOIN batches bb ON bb.batch_id = bi.batch_id
              WHERE bb.session_id = p_session_id AND bb.completed_at IS NOT NULL),
    'batches_completed', ses.batches_completed,
    'can_continue', ses.batches_completed < cfg.max_batches_per_session);
END;
$$;

-- Admin: dashboard (score distribution without 'ca')
CREATE OR REPLACE FUNCTION admin_dashboard()
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE cfg app_config%ROWTYPE;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not an admin'; END IF;
  SELECT * INTO cfg FROM app_config WHERE id = 1;
  RETURN jsonb_build_object(
    'sessions', (SELECT count(*) FROM sessions),
    'sessions_scored', (SELECT count(DISTINCT session_id) FROM scores),
    'sessions_batch_done', (SELECT count(*) FROM sessions WHERE batches_completed > 0),
    'sessions_excluded', (SELECT count(*) FROM sessions WHERE excluded),
    'by_language', (SELECT COALESCE(jsonb_object_agg(language_pref, n), '{}') FROM (SELECT language_pref, count(*) n FROM sessions GROUP BY 1) x),
    'by_type', (SELECT COALESCE(jsonb_object_agg(COALESCE(annotator_type, 'none'), n), '{}') FROM (SELECT annotator_type, count(*) n FROM sessions GROUP BY 1) x),
    'batches', (SELECT count(*) FROM batches),
    'batches_done', (SELECT count(*) FROM batches WHERE completed_at IS NOT NULL),
    'items_scored', (SELECT count(DISTINCT batch_item_id) FROM scores),
    'score_rows', (SELECT count(*) FROM scores),
    'requirements', (SELECT COALESCE(jsonb_object_agg(language_tag, n), '{}') FROM (SELECT language_tag, count(*) n FROM requirements WHERE eligible GROUP BY 1) x),
    'coverage_target', cfg.coverage_target,
    'coverage', (SELECT COALESCE(jsonb_object_agg(k, n), '{}') FROM (
        SELECT CASE WHEN c >= cfg.coverage_target THEN 'target' ELSE c::TEXT END k, count(*) n
        FROM (SELECT r.req_id, req_score_sessions(r.req_id) c FROM requirements r WHERE r.eligible) y GROUP BY 1) x),
    'score_dist', (SELECT COALESCE(jsonb_object_agg(metric_id, d), '{}') FROM (
        SELECT s.metric_id, jsonb_build_object(
          '0', count(*) FILTER (WHERE s.score = 0), '1', count(*) FILTER (WHERE s.score = 1),
          '2', count(*) FILTER (WHERE s.score = 2)) d
        FROM scores s JOIN batch_items bi ON bi.batch_item_id = s.batch_item_id AND NOT bi.is_attention_check
        JOIN sessions se ON se.session_id = s.session_id AND NOT se.excluded
        GROUP BY 1) x),
    'daily', (SELECT COALESCE(jsonb_agg(jsonb_build_object('day', d, 'n', n) ORDER BY d), '[]') FROM (
        SELECT created_at::DATE d, count(*) n FROM sessions GROUP BY 1) x),
    'median_seconds', (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY time_seconds) FROM batch_items WHERE time_seconds IS NOT NULL)
  );
END;
$$;

-- Admin: reference labels import (llm_score required; no CA)
CREATE OR REPLACE FUNCTION admin_import_reference_labels(p_rows JSONB)
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n INT;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not an admin'; END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_rows) x WHERE x->>'llm_score' IS NULL) THEN
    RAISE EXCEPTION 'llm_score is required for every row';
  END IF;
  INSERT INTO reference_labels (base_id, metric_id, llm_score, llm_model)
  SELECT x->>'base_id', x->>'metric_id', (x->>'llm_score')::SMALLINT,
         COALESCE(NULLIF(x->>'llm_model', ''), 'unspecified')
  FROM jsonb_array_elements(p_rows) x
  ON CONFLICT (base_id, metric_id) DO UPDATE SET llm_score = EXCLUDED.llm_score, llm_model = EXCLUDED.llm_model;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$$;

COMMIT;

-- Verify: no cannot_assess column left (expect 0 rows)
SELECT table_name, column_name FROM information_schema.columns
WHERE table_schema = 'public' AND column_name IN ('cannot_assess', 'llm_cannot_assess');
