-- ReqIQ-ANN migration 0034 — admin import of a participant's own scores (Excel template).
-- Why: a participant who scores the whole Promise+ subset in several sessions enters the
-- scores in an Excel template (one row per requirement version, six metric scores + rationale)
-- instead of the annotator screen. The import creates one "import session" per rater code.
-- Rules:
--   * Admin only (is_admin()).
--   * All-or-nothing: every row is validated before anything is written. If any row fails,
--     the function returns status = 'error' with the list of problem rows and writes nothing.
--   * Re-upload: the earlier scores of the same rater code are removed and replaced.
--   * Import session: annotator_type and language_pref are given by the admin (no consent row,
--     consent_version stays NULL). comment = 'IMPORT:<rater_code>' marks the session.
--   * time_seconds is NULL for every item, so the session has no speed data and raises no
--     speed flag. The rationale text is stored in scores.note (max 500 characters).
--   * Batches of batch_size items (app_config, default 30), sampling_strategy = 'IMPORT',
--     completed_at set at import time.
--   * Excluded sessions: none (the import counts in the analysis together with other raters).
-- Changes nothing else: no existing function, table or row is modified.
-- Run once in Supabase SQL Editor AFTER 0033. Re-run safe (CREATE OR REPLACE).

BEGIN;

CREATE OR REPLACE FUNCTION admin_import_participant_scores(
  p_rater_code     TEXT,
  p_annotator_type TEXT,
  p_language_pref  TEXT,
  p_rows           JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code     TEXT := upper(btrim(COALESCE(p_rater_code, '')));
  v_marker   TEXT;
  v_session  TEXT;
  v_old_lang TEXT;
  v_cfg      BIGINT;
  v_bs       INT;
  v_errors   TEXT[] := '{}';
  v_mids     TEXT[] := ARRAY['M_IND_01','M_IND_02','M_IND_03','M_IND_04','M_IND_05','M_IND_06'];
  v_row      RECORD;
  q          RECORD;
  v_m        TEXT;
  v_entry    JSONB;
  v_s        TEXT;
  v_note     TEXT;
  v_label    TEXT;
  v_bad      BOOLEAN;
  v_n        INT := 0;
  v_pos      INT;
  v_batch    TEXT;
  v_bi       BIGINT;
  v_round    SMALLINT;
  v_nbatch   INT := 0;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not an admin'; END IF;
  IF v_code !~ '^[A-Z0-9_-]{1,20}$' THEN
    RAISE EXCEPTION 'invalid rater code (A-Z, 0-9, _ or -, max 20 characters)';
  END IF;
  IF p_annotator_type NOT IN ('student','industry','researcher','other') THEN
    RAISE EXCEPTION 'invalid annotator_type';
  END IF;
  IF p_language_pref NOT IN ('EN','TR','BOTH') THEN
    RAISE EXCEPTION 'invalid language';
  END IF;
  IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
    RAISE EXCEPTION 'no rows to import';
  END IF;

  -- 1. Validation. Nothing is written in this block.
  FOR v_row IN SELECT x.value AS j, x.ord FROM jsonb_array_elements(p_rows) WITH ORDINALITY AS x(value, ord) ORDER BY x.ord LOOP
    v_label := 'Satır ' || COALESCE(v_row.j->>'excel_row', v_row.ord::TEXT) || ': ';
    SELECT * INTO q FROM requirements WHERE req_id = v_row.j->>'req_id';
    IF NOT FOUND THEN
      v_errors := array_append(v_errors, v_label || 'req_id sistemde yok (' || COALESCE(v_row.j->>'req_id', '') || ')');
      CONTINUE;
    END IF;
    IF upper(COALESCE(v_row.j->>'language_tag', '')) <> q.language_tag THEN
      v_errors := array_append(v_errors, v_label || 'Dil gereksinimin dili ile uyuşmuyor (' || q.language_tag || ' olmalı)');
    END IF;
    IF COALESCE(v_row.j->>'project_id', '') <> q.project_id THEN
      v_errors := array_append(v_errors, v_label || 'Project_ID uyuşmuyor (sistem: ' || q.project_id || ')');
    END IF;
    IF COALESCE(v_row.j->>'base_id', '') <> COALESCE(q.base_id, '') THEN
      v_errors := array_append(v_errors, v_label || 'Base_ID uyuşmuyor (sistem: ' || COALESCE(q.base_id, '-') || ')');
    END IF;
    IF (SELECT count(*) FROM jsonb_array_elements(p_rows) y WHERE y->>'req_id' = v_row.j->>'req_id') > 1 THEN
      v_errors := array_append(v_errors, v_label || 'aynı req_id birden fazla satırda');
    END IF;
    FOREACH v_m IN ARRAY v_mids LOOP
      v_entry := v_row.j->'scores'->v_m;
      v_s := v_entry->>'score';
      IF v_s IS NULL OR v_s = '' THEN
        v_errors := array_append(v_errors, v_label || v_m || ' puanı boş');
      ELSIF v_s !~ '^[0-2](\.0+)?$' THEN
        v_errors := array_append(v_errors, v_label || v_m || ' puanı 0, 1 veya 2 olmalı (girilen: ' || v_s || ')');
      END IF;
      IF char_length(COALESCE(v_entry->>'note', '')) > 500 THEN
        v_errors := array_append(v_errors, v_label || v_m || ' gerekçesi 500 karakteri aşıyor');
      END IF;
    END LOOP;
  END LOOP;

  IF array_length(v_errors, 1) IS NOT NULL THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'written', false,
      'error_count', array_length(v_errors, 1),
      'errors', to_jsonb(v_errors[1:50])
    );
  END IF;

  -- 2. Import session for this rater code (created once, reused on re-upload).
  v_marker := 'IMPORT:' || v_code;
  SELECT session_id, language_pref INTO v_session, v_old_lang
  FROM sessions WHERE comment = v_marker ORDER BY created_at LIMIT 1;
  IF v_session IS NULL THEN
    v_session := md5(gen_random_uuid()::TEXT) || md5(gen_random_uuid()::TEXT);
    INSERT INTO sessions (session_id, annotator_type, language_pref, comment, excluded, flag_speed, flag_consistency)
    VALUES (v_session, p_annotator_type, p_language_pref, v_marker, FALSE, FALSE, FALSE);
  ELSIF v_old_lang <> p_language_pref THEN
    RAISE EXCEPTION 'rater % was imported with language % — use the same language for a re-upload', v_code, v_old_lang;
  ELSE
    UPDATE sessions SET annotator_type = p_annotator_type, last_active_at = now() WHERE session_id = v_session;
  END IF;

  -- 3. Re-upload: remove this rater's earlier scores and batches (batch_items cascade).
  DELETE FROM scores WHERE session_id = v_session;
  DELETE FROM batches WHERE session_id = v_session;

  -- 4. Write batches of batch_size items.
  SELECT COALESCE(batch_size, 30) INTO v_bs FROM app_config WHERE id = 1;
  v_cfg := (SELECT config_id FROM rubric_config WHERE is_active LIMIT 1);

  FOR v_row IN SELECT x.value AS j, x.ord FROM jsonb_array_elements(p_rows) WITH ORDINALITY AS x(value, ord) ORDER BY x.ord LOOP
    SELECT * INTO q FROM requirements WHERE req_id = v_row.j->>'req_id';
    v_n := v_n + 1;
    v_pos := ((v_n - 1) % v_bs) + 1;
    IF v_pos = 1 THEN
      v_nbatch := v_nbatch + 1;
      v_batch := 'IMP-' || left(v_session, 12) || '-' || lpad(v_nbatch::TEXT, 3, '0');
      INSERT INTO batches (batch_id, session_id, config_id, sampling_strategy, completed_at)
      VALUES (v_batch, v_session, v_cfg, 'IMPORT', now());
    END IF;
    v_round := (1 + req_score_sessions(q.req_id))::SMALLINT;
    INSERT INTO batch_items (batch_id, req_id, position, is_attention_check, round)
    VALUES (v_batch, q.req_id, v_pos, FALSE, v_round)
    RETURNING batch_item_id INTO v_bi;
    FOREACH v_m IN ARRAY v_mids LOOP
      v_entry := v_row.j->'scores'->v_m;
      v_note := NULLIF(btrim(COALESCE(v_entry->>'note', '')), '');
      INSERT INTO scores (session_id, batch_item_id, req_id, metric_id, score, note, annotation_language, round)
      VALUES (v_session, v_bi, q.req_id, v_m, (v_entry->>'score')::NUMERIC::SMALLINT, v_note, q.language_tag, v_round);
    END LOOP;
  END LOOP;

  UPDATE sessions
  SET batches_completed = (SELECT count(*) FROM batches WHERE session_id = v_session), last_active_at = now()
  WHERE session_id = v_session;

  RETURN jsonb_build_object('status', 'ok', 'written', true, 'rows', v_n, 'batches', v_nbatch);
END;
$$;

REVOKE ALL ON FUNCTION admin_import_participant_scores(TEXT, TEXT, TEXT, JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_import_participant_scores(TEXT, TEXT, TEXT, JSONB) TO authenticated;

COMMIT;

-- Verify (expect 1 row, security_definer = true)
SELECT proname, prosecdef AS security_definer FROM pg_proc WHERE proname = 'admin_import_participant_scores';
