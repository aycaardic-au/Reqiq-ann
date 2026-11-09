-- ReqIQ-ANN migration 0016 — end session / withdraw answers (D-32)
-- "Oturumu sonlandır" offers: pause (nothing written), end and keep answers, end and delete answers.
-- Run in Supabase SQL Editor AFTER 0015. Re-run safe.

BEGIN;

ALTER TABLE sessions ADD COLUMN IF NOT EXISTS ended_at TIMESTAMPTZ;
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS withdrawn_at TIMESTAMPTZ;

-- End the session, answers kept
CREATE OR REPLACE FUNCTION end_session(p_session_id TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE sessions SET ended_at = COALESCE(ended_at, now()), last_active_at = now() WHERE session_id = p_session_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'unknown session'; END IF;
END;
$$;

-- End the session and delete its answers (withdrawal). The session row stays, without answers,
-- so the number of withdrawals can be reported; it is marked excluded.
CREATE OR REPLACE FUNCTION withdraw_session(p_session_id TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM 1 FROM sessions WHERE session_id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'unknown session'; END IF;
  DELETE FROM scores WHERE session_id = p_session_id;
  DELETE FROM batch_items WHERE batch_id IN (SELECT batch_id FROM batches WHERE session_id = p_session_id);
  DELETE FROM batches WHERE session_id = p_session_id;
  UPDATE sessions SET withdrawn_at = now(), ended_at = COALESCE(ended_at, now()), excluded = TRUE,
    annotator_type_other = NULL, comment = NULL, batches_completed = 0, last_active_at = now()
  WHERE session_id = p_session_id;
END;
$$;

-- Assignment, scoring and comment refuse ended or withdrawn sessions
CREATE OR REPLACE FUNCTION session_is_open(p_session_id TEXT)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM sessions WHERE session_id = p_session_id AND ended_at IS NULL);
$$;

REVOKE ALL ON FUNCTION end_session(TEXT), withdraw_session(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION session_is_open(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION end_session(TEXT), withdraw_session(TEXT) TO anon;

-- Dashboard: add ended / withdrawn counts
CREATE OR REPLACE FUNCTION admin_session_counts()
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not an admin'; END IF;
  RETURN jsonb_build_object(
    'ended', (SELECT count(*) FROM sessions WHERE ended_at IS NOT NULL AND withdrawn_at IS NULL),
    'withdrawn', (SELECT count(*) FROM sessions WHERE withdrawn_at IS NOT NULL));
END;
$$;
REVOKE ALL ON FUNCTION admin_session_counts() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_session_counts() TO authenticated;

-- Refuse ended sessions (replaces the 0014 / 0013 versions)
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
  IF ses.language_pref = 'BOTH' THEN
    -- D-14: equal EN and TR. D-30: EN and TR versions of the same requirement may both be
    -- assigned to a BOTH session; only the same language version is never repeated.
    SELECT COALESCE(array_agg(DISTINCT bi.req_id), '{}') INTO used_bases
    FROM batches b JOIN batch_items bi ON bi.batch_id = b.batch_id WHERE b.session_id = p_session_id;
    uniq := pick_requirements(p_session_id, 'EN', n_unique / 2, used_bases, FALSE)
         || pick_requirements(p_session_id, 'TR', n_unique - n_unique / 2, used_bases, FALSE);
  ELSE
    SELECT COALESCE(array_agg(DISTINCT COALESCE(r.base_id, r.req_id)), '{}') INTO used_bases
    FROM batches b JOIN batch_items bi ON bi.batch_id = b.batch_id JOIN requirements r ON r.req_id = bi.req_id
    WHERE b.session_id = p_session_id;
    uniq := pick_requirements(p_session_id, ses.language_pref, n_unique, used_bases, TRUE);
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
  IF NOT session_is_open(p_session_id) THEN RAISE EXCEPTION 'session ended'; END IF;
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

COMMIT;

-- Verify: expect 3 rows
SELECT proname FROM pg_proc WHERE proname IN ('end_session','withdraw_session','admin_session_counts') ORDER BY 1;
