-- ReqIQ-ANN migration 0039 — stable rater codes, deletion of sessions without scores,
-- grouped study levels (decisions 17 Nov 2026)
--   1. sessions.rater_code: assigned once when the session row is created and never renumbered.
--      Existing sessions get the code shown today in the admin session list (all sessions,
--      ordered by created_at). Before 0039 the export renumbered sessions after filtering, so a
--      code could change with the filter or after a deletion.
--   2. admin_delete_session: an admin may delete a session only if it has no scores. Its
--      batches, items, briefing views and client errors are deleted with it. The code is not reused.
--   3. study_level: year_1..year_4 replaced by bachelor_1_2 and bachelor_3_4 (no stored row used
--      year_1..year_4 on 17 Nov 2026; the migration stops if one does).
--   4. admin_reset_study also restarts the code numbering (R001), as the computed codes did.
-- Allocation is not changed. Run in Supabase SQL Editor AFTER 0038. Re-run safe.

BEGIN;

-- 0. Guard for step 3
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM sessions WHERE study_level IN ('year_1','year_2','year_3','year_4')) THEN
    RAISE EXCEPTION '0039 stopped: sessions with study_level year_1..year_4 exist; decide how to map them first';
  END IF;
END $$;

-- 1. Stable rater code
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS rater_code TEXT;
COMMENT ON COLUMN sessions.rater_code IS 'Rater code R001, R002, ... assigned at creation, never reused (0039).';

CREATE SEQUENCE IF NOT EXISTS sessions_rater_seq AS INTEGER START 1 MINVALUE 1;

-- Backfill: same order as the admin list before 0039 (created_at; session_id breaks ties)
WITH numbered AS (
  SELECT session_id,
         (SELECT COALESCE(max(substring(rater_code FROM 2)::INT), 0) FROM sessions WHERE rater_code ~ '^R[0-9]+$')
         + row_number() OVER (ORDER BY created_at, session_id) AS n
  FROM sessions WHERE rater_code IS NULL
)
UPDATE sessions s SET rater_code = 'R' || lpad(numbered.n::TEXT, 3, '0')
FROM numbered WHERE s.session_id = numbered.session_id;

SELECT setval('sessions_rater_seq',
  GREATEST(1, COALESCE((SELECT max(substring(rater_code FROM 2)::INT) FROM sessions WHERE rater_code ~ '^R[0-9]+$'), 0)),
  EXISTS (SELECT 1 FROM sessions WHERE rater_code IS NOT NULL));

CREATE OR REPLACE FUNCTION sessions_set_rater_code()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.rater_code IS NULL THEN
    NEW.rater_code := 'R' || lpad(nextval('sessions_rater_seq')::TEXT, 3, '0');
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION sessions_set_rater_code() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS sessions_rater_code_trg ON sessions;
CREATE TRIGGER sessions_rater_code_trg BEFORE INSERT ON sessions
  FOR EACH ROW EXECUTE FUNCTION sessions_set_rater_code();

ALTER TABLE sessions ALTER COLUMN rater_code SET NOT NULL;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'sessions_rater_code_key') THEN
    ALTER TABLE sessions ADD CONSTRAINT sessions_rater_code_key UNIQUE (rater_code);
  END IF;
END $$;

-- 2. Delete a session without scores (admin only)
CREATE OR REPLACE FUNCTION admin_delete_session(p_session_id TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_code TEXT;
  v_batches INT;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not an admin'; END IF;
  SELECT rater_code INTO v_code FROM sessions WHERE session_id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'unknown session'; END IF;
  IF EXISTS (SELECT 1 FROM scores WHERE session_id = p_session_id) THEN
    RAISE EXCEPTION 'session % has scores and cannot be deleted', v_code;
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

-- 3. Grouped study levels
ALTER TABLE sessions DROP CONSTRAINT IF EXISTS sessions_study_level_chk;
ALTER TABLE sessions ADD CONSTRAINT sessions_study_level_chk CHECK (study_level IN (
  'bachelor_1_2','bachelor_3_4','masters','phd','other','prefer_not_to_say'));

-- set_background (replaces 0038; only the study level list changes)
CREATE OR REPLACE FUNCTION set_background(
  p_session_id        TEXT,
  p_type              TEXT,
  p_other             TEXT,
  p_role              TEXT DEFAULT NULL,
  p_role_other        TEXT DEFAULT NULL,
  p_experience        TEXT DEFAULT NULL,
  p_study_level       TEXT DEFAULT NULL,
  p_study_level_other TEXT DEFAULT NULL)
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
BEGIN
  IF p_type IS NULL OR p_type NOT IN ('student','industry','researcher','other') THEN
    RAISE EXCEPTION 'invalid annotator_type';
  END IF;

  IF p_type <> 'other' THEN v_other := NULL; END IF;
  IF p_type <> 'industry' THEN v_role := NULL; END IF;
  IF p_type NOT IN ('industry','researcher') THEN v_exp := NULL; END IF;
  IF p_type <> 'student' THEN v_level := NULL; END IF;
  IF v_role IS DISTINCT FROM 'other' THEN v_role_other := NULL; END IF;
  IF v_level IS DISTINCT FROM 'other' THEN v_level_other := NULL; END IF;

  IF v_role IS NOT NULL AND v_role NOT IN ('requirements_engineer','systems_engineer','test_engineer',
       'project_manager','software_developer','other','prefer_not_to_say') THEN
    RAISE EXCEPTION 'invalid role_category';
  END IF;
  IF v_exp IS NOT NULL AND v_exp NOT IN ('0-2','3-5','6-10','11-20','20+','prefer_not_to_say') THEN
    RAISE EXCEPTION 'invalid experience_band';
  END IF;
  IF v_level IS NOT NULL AND v_level NOT IN ('bachelor_1_2','bachelor_3_4','masters','phd',
       'other','prefer_not_to_say') THEN
    RAISE EXCEPTION 'invalid study_level';
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

  UPDATE sessions
  SET annotator_type = p_type, annotator_type_other = v_other,
      role_category = v_role, role_other = v_role_other, experience_band = v_exp,
      study_level = v_level, study_level_other = v_level_other,
      last_active_at = now()
  WHERE session_id = p_session_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'unknown session';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION set_background(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION set_background(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO anon;

-- 4. Study reset (replaces 0022): also restarts the rater code numbering
CREATE OR REPLACE FUNCTION admin_reset_study(p_confirm TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n_s INT;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not an admin'; END IF;
  IF p_confirm IS DISTINCT FROM 'SIFIRLA' THEN RAISE EXCEPTION 'confirmation text must be SIFIRLA'; END IF;
  SELECT count(*) INTO n_s FROM sessions;
  DELETE FROM scores WHERE TRUE;
  DELETE FROM batch_items WHERE TRUE;
  DELETE FROM batches WHERE TRUE;
  DELETE FROM sessions WHERE TRUE;
  DELETE FROM client_errors WHERE TRUE;
  PERFORM setval('sessions_rater_seq', 1, FALSE);
  RETURN jsonb_build_object('sessions_deleted', n_s);
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- Verify 1 (expect: sessions_without_code = 0, duplicate_codes = 0)
SELECT count(*) FILTER (WHERE rater_code IS NULL) AS sessions_without_code,
       count(*) - count(DISTINCT rater_code) AS duplicate_codes
FROM sessions;

-- Verify 2 (expect the same codes as the admin session list before 0039)
SELECT rater_code, created_at, annotator_type, language_pref FROM sessions ORDER BY created_at, session_id;

-- Verify 3 (expect 3 rows: admin_delete_session, admin_reset_study, set_background; all security_definer = true)
SELECT proname, pronargs, prosecdef AS security_definer FROM pg_proc
WHERE proname IN ('admin_delete_session','admin_reset_study','set_background') ORDER BY proname;

-- Verify 4 (expect anon_delete = false, admin_delete = true)
SELECT has_function_privilege('anon', 'admin_delete_session(text)', 'EXECUTE') AS anon_delete,
       has_function_privilege('authenticated', 'admin_delete_session(text)', 'EXECUTE') AS admin_delete;
