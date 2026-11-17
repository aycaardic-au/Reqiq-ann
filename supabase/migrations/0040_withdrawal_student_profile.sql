-- ReqIQ-ANN migration 0040 (DRAFT, not applied) — full deletion on withdrawal, student profile, admin delete rule
-- Decisions of 17 Nov 2026:
--   A. Withdrawal ("Oturumu sonlandır ve yanıtlarımı sil", SRS FR-SES-009(c)): everything attached to the
--      session is deleted (scores, items, batches, briefing_views, client_errors) and the session's own
--      answers are cleared. The row stays as a minimal record: session_id, rater_code, consent_version,
--      created_at, last_active_at, ended_at, withdrawn_at, excluded = TRUE.
--   B. set_background and log_client_error refuse / ignore a withdrawn session.
--   C. Admin deletion (FR-ADM-014): only a session without scores whose last activity is at least 60 minutes old.
--   D. Student profile (advisor's request): study_level = bachelor / masters / phd / other / prefer_not_to_say;
--      study_year 1-4 only for bachelor; school_dept free text (max 100) for bachelor, masters and phd.
--      The earlier groups bachelor_1_2 and bachelor_3_4 become 'bachelor' (year unknown).
--   E. The 'researcher' type is no longer accepted by set_background. The CHECK on annotator_type keeps it,
--      so old rows and the admin participant import stay valid.
-- set_background keeps ONE definition (no overload: an eight-parameter twin would make named calls ambiguous, see 0038).
-- The two new parameters default to NULL, so a not-yet-deployed old front end keeps working; it may still send
-- the old level groups, which are mapped to 'bachelor'.
--   F. admin_dashboard: language_pref is cleared on withdrawal, so by_language must not use a NULL key
--      (jsonb_object_agg fails on NULL); NULL is reported as 'none'.
-- Run in Supabase SQL Editor AFTER 0039, BEFORE importing ui_texts 2.32. Re-run safe. Not applied by the assistant.

BEGIN;

-- D1. columns and constraints
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS study_year SMALLINT;
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS school_dept TEXT;
COMMENT ON COLUMN sessions.study_year IS 'K3, bachelor students only: class year 1-4 (0040).';
COMMENT ON COLUMN sessions.school_dept IS 'K3, bachelor / master / PhD students: free text school and department, max 100 (0040).';

ALTER TABLE sessions DROP CONSTRAINT IF EXISTS sessions_study_level_chk;
UPDATE sessions SET study_level = 'bachelor' WHERE study_level IN ('bachelor_1_2','bachelor_3_4');
ALTER TABLE sessions ADD CONSTRAINT sessions_study_level_chk CHECK (study_level IN (
  'bachelor','masters','phd','other','prefer_not_to_say'));
ALTER TABLE sessions DROP CONSTRAINT IF EXISTS sessions_study_year_chk;
ALTER TABLE sessions ADD CONSTRAINT sessions_study_year_chk CHECK (study_year BETWEEN 1 AND 4);
ALTER TABLE sessions DROP CONSTRAINT IF EXISTS sessions_school_dept_chk;
ALTER TABLE sessions ADD CONSTRAINT sessions_school_dept_chk CHECK (char_length(school_dept) <= 100);

-- A. withdrawal: delete everything attached to the session, keep the minimal record
CREATE OR REPLACE FUNCTION withdraw_session(p_session_id TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM 1 FROM sessions WHERE session_id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'unknown session'; END IF;
  DELETE FROM scores WHERE session_id = p_session_id;
  DELETE FROM briefing_views WHERE session_id = p_session_id;
  DELETE FROM batch_items WHERE batch_id IN (SELECT batch_id FROM batches WHERE session_id = p_session_id);
  DELETE FROM batches WHERE session_id = p_session_id;
  DELETE FROM client_errors WHERE session_id = p_session_id;
  UPDATE sessions SET
    withdrawn_at = COALESCE(withdrawn_at, now()), ended_at = COALESCE(ended_at, now()), excluded = TRUE,
    annotator_type = NULL, annotator_type_other = NULL, language_pref = NULL,
    role_category = NULL, role_other = NULL, experience_band = NULL,
    study_level = NULL, study_level_other = NULL, study_year = NULL, school_dept = NULL,
    comment = NULL, flag_consistency = FALSE, flag_speed = FALSE,
    batches_completed = 0, last_active_at = now()
  WHERE session_id = p_session_id;
END;
$$;
REVOKE ALL ON FUNCTION withdraw_session(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION withdraw_session(TEXT) TO anon;

-- B + D + E. set_background: ten parameters, withdrawn guard, new student rules
DROP FUNCTION IF EXISTS set_background(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION set_background(
  p_session_id        TEXT,
  p_type              TEXT,
  p_other             TEXT,
  p_role              TEXT DEFAULT NULL,
  p_role_other        TEXT DEFAULT NULL,
  p_experience        TEXT DEFAULT NULL,
  p_study_level       TEXT DEFAULT NULL,
  p_study_level_other TEXT DEFAULT NULL,
  p_study_year        SMALLINT DEFAULT NULL,
  p_school            TEXT DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_other       TEXT := NULLIF(btrim(p_other), '');
  v_role        TEXT := NULLIF(btrim(p_role), '');
  v_role_other  TEXT := NULLIF(btrim(p_role_other), '');
  v_exp         TEXT := NULLIF(btrim(p_experience), '');
  v_level       TEXT := NULLIF(btrim(p_study_level), '');
  v_level_other TEXT := NULLIF(btrim(p_study_level_other), '');
  v_year        SMALLINT := p_study_year;
  v_school      TEXT := NULLIF(btrim(p_school), '');
BEGIN
  -- a withdrawn session must not receive background answers again (NFR-REL-006)
  IF EXISTS (SELECT 1 FROM sessions WHERE session_id = p_session_id AND withdrawn_at IS NOT NULL) THEN
    RAISE EXCEPTION 'session ended';
  END IF;
  IF p_type IS NULL OR p_type NOT IN ('student','industry','other') THEN
    RAISE EXCEPTION 'invalid annotator_type';
  END IF;
  -- legacy level groups sent by an old front end
  IF v_level IN ('bachelor_1_2','bachelor_3_4') THEN v_level := 'bachelor'; END IF;

  IF p_type <> 'other' THEN v_other := NULL; END IF;
  IF p_type <> 'industry' THEN v_role := NULL; v_exp := NULL; END IF;
  IF p_type <> 'student' THEN v_level := NULL; END IF;
  IF v_role IS DISTINCT FROM 'other' THEN v_role_other := NULL; END IF;
  IF v_level IS DISTINCT FROM 'other' THEN v_level_other := NULL; END IF;
  IF v_level IS DISTINCT FROM 'bachelor' THEN v_year := NULL; END IF;
  IF v_level IS NULL OR v_level NOT IN ('bachelor','masters','phd') THEN v_school := NULL; END IF;

  IF v_role IS NOT NULL AND v_role NOT IN ('requirements_engineer','systems_engineer','test_engineer',
       'project_manager','software_developer','other','prefer_not_to_say') THEN
    RAISE EXCEPTION 'invalid role_category';
  END IF;
  IF v_exp IS NOT NULL AND v_exp NOT IN ('0-2','3-5','6-10','11-20','20+','prefer_not_to_say') THEN
    RAISE EXCEPTION 'invalid experience_band';
  END IF;
  IF v_level IS NOT NULL AND v_level NOT IN ('bachelor','masters','phd','other','prefer_not_to_say') THEN
    RAISE EXCEPTION 'invalid study_level';
  END IF;
  IF v_year IS NOT NULL AND v_year NOT BETWEEN 1 AND 4 THEN
    RAISE EXCEPTION 'invalid study_year';
  END IF;
  IF char_length(v_other) > 50 THEN
    RAISE EXCEPTION 'annotator_type_other longer than 50 characters';
  END IF;
  IF char_length(v_role_other) > 50 THEN
    RAISE EXCEPTION 'role_other longer than 50 characters';
  END IF;
  IF char_length(v_level_other) > 50 THEN
    RAISE EXCEPTION 'study_level_other longer than 50 characters';
  END IF;
  IF char_length(v_school) > 100 THEN
    RAISE EXCEPTION 'school_dept longer than 100 characters';
  END IF;

  UPDATE sessions
  SET annotator_type = p_type, annotator_type_other = v_other,
      role_category = v_role, role_other = v_role_other, experience_band = v_exp,
      study_level = v_level, study_level_other = v_level_other,
      study_year = v_year, school_dept = v_school,
      last_active_at = now()
  WHERE session_id = p_session_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'unknown session';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION set_background(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, SMALLINT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION set_background(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, SMALLINT, TEXT) TO anon;

-- B. log_client_error stores nothing for a withdrawn session
CREATE OR REPLACE FUNCTION log_client_error(p_session_id TEXT, p_location TEXT, p_message TEXT, p_user_agent TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM sessions WHERE session_id = left(p_session_id, 64) AND withdrawn_at IS NOT NULL) THEN RETURN; END IF;
  -- simple flood guard: at most 200 entries per hour in total
  IF (SELECT count(*) FROM client_errors WHERE created_at > now() - interval '1 hour') >= 200 THEN RETURN; END IF;
  INSERT INTO client_errors (session_id, location, message, user_agent)
  VALUES (left(p_session_id, 64), left(p_location, 200), left(p_message, 2000), left(p_user_agent, 300));
END;
$$;

-- C. admin deletion: only sessions without scores and idle for at least 60 minutes
CREATE OR REPLACE FUNCTION admin_delete_session(p_session_id TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_code TEXT;
  v_last TIMESTAMPTZ;
  v_batches INT;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not an admin'; END IF;
  SELECT rater_code, last_active_at INTO v_code, v_last FROM sessions WHERE session_id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'unknown session'; END IF;
  IF EXISTS (SELECT 1 FROM scores WHERE session_id = p_session_id) THEN
    RAISE EXCEPTION 'session % has scores and cannot be deleted', v_code;
  END IF;
  IF v_last > now() - interval '60 minutes' THEN
    RAISE EXCEPTION 'session % was active less than 60 minutes ago and cannot be deleted yet', v_code;
  END IF;
  SELECT count(*) INTO v_batches FROM batches WHERE session_id = p_session_id;
  DELETE FROM briefing_views WHERE session_id = p_session_id;
  DELETE FROM batch_items WHERE batch_id IN (SELECT batch_id FROM batches WHERE session_id = p_session_id);
  DELETE FROM batches WHERE session_id = p_session_id;
  DELETE FROM client_errors WHERE session_id = p_session_id;
  DELETE FROM sessions WHERE session_id = p_session_id;
  RETURN jsonb_build_object('deleted', v_code, 'batches', v_batches);
END;
$$;
REVOKE ALL ON FUNCTION admin_delete_session(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_delete_session(TEXT) TO authenticated;

-- F. dashboard counts: NULL language (withdrawn sessions) becomes 'none'
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
    'by_language', (SELECT COALESCE(jsonb_object_agg(COALESCE(language_pref, 'none'), n), '{}') FROM (SELECT language_pref, count(*) n FROM sessions GROUP BY 1) x),
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

COMMIT;

NOTIFY pgrst, 'reload schema';

-- Verify after a UI test withdrawal (paste the withdrawn session_id): every count must be 0 and the row minimal.
SELECT 'scores' AS tbl, count(*) FROM scores WHERE session_id = 'PASTE_SESSION_ID'
UNION ALL SELECT 'batches', count(*) FROM batches WHERE session_id = 'PASTE_SESSION_ID'
UNION ALL SELECT 'batch_items', count(*) FROM batch_items WHERE batch_id IN (SELECT batch_id FROM batches WHERE session_id = 'PASTE_SESSION_ID')
UNION ALL SELECT 'briefing_views', count(*) FROM briefing_views WHERE session_id = 'PASTE_SESSION_ID'
UNION ALL SELECT 'client_errors', count(*) FROM client_errors WHERE session_id = 'PASTE_SESSION_ID';
SELECT * FROM sessions WHERE session_id = 'PASTE_SESSION_ID';
-- Student profile check: no old level groups and no researcher in new rows
SELECT study_level, study_year, count(*) FROM sessions GROUP BY 1, 2 ORDER BY 1, 2;
