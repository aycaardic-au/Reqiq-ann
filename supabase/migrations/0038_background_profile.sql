-- ReqIQ-ANN migration 0038 — optional background questions on the information form (K3)
-- Decision 17 Nov 2026: new optional questions by annotator type, each with "prefer not to say".
--   industry   : role (closed list + "other" text, max 50) and years in the sector (band)
--   researcher : years of sector / academic experience (same bands)
--   student    : study level (closed list + "other" text, max 50)
--   other      : no new question
-- Additive only: nullable columns, CHECK rules, set_background redefined with optional
-- parameters (the old three-argument call keeps working), withdraw_session also clears the
-- new free texts. Existing rows keep NULL in the new columns. Allocation is not changed.
-- Run in Supabase SQL Editor AFTER 0037. Re-run safe.

BEGIN;

-- 1. Columns (NULL = not asked or skipped; 'prefer_not_to_say' = explicit answer)
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS role_category     TEXT;
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS role_other        TEXT;
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS experience_band   TEXT;
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS study_level       TEXT;
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS study_level_other TEXT;

COMMENT ON COLUMN sessions.role_category     IS 'K3, industry only: role (0038).';
COMMENT ON COLUMN sessions.role_other        IS 'K3, industry only: free text when role_category = other (max 50).';
COMMENT ON COLUMN sessions.experience_band   IS 'K3: industry = years in the sector; researcher = years of sector/academic experience (0038).';
COMMENT ON COLUMN sessions.study_level       IS 'K3, student only: study level (0038).';
COMMENT ON COLUMN sessions.study_level_other IS 'K3, student only: free text when study_level = other (max 50).';

-- 2. CHECK rules
ALTER TABLE sessions DROP CONSTRAINT IF EXISTS sessions_role_category_chk;
ALTER TABLE sessions ADD CONSTRAINT sessions_role_category_chk CHECK (role_category IN (
  'requirements_engineer','systems_engineer','test_engineer','project_manager',
  'software_developer','other','prefer_not_to_say'));
ALTER TABLE sessions DROP CONSTRAINT IF EXISTS sessions_role_other_chk;
ALTER TABLE sessions ADD CONSTRAINT sessions_role_other_chk CHECK (char_length(role_other) <= 50);
ALTER TABLE sessions DROP CONSTRAINT IF EXISTS sessions_experience_band_chk;
ALTER TABLE sessions ADD CONSTRAINT sessions_experience_band_chk CHECK (experience_band IN (
  '0-2','3-5','6-10','11-20','20+','prefer_not_to_say'));
ALTER TABLE sessions DROP CONSTRAINT IF EXISTS sessions_study_level_chk;
ALTER TABLE sessions ADD CONSTRAINT sessions_study_level_chk CHECK (study_level IN (
  'year_1','year_2','year_3','year_4','masters','phd','other','prefer_not_to_say'));
ALTER TABLE sessions DROP CONSTRAINT IF EXISTS sessions_study_level_other_chk;
ALTER TABLE sessions ADD CONSTRAINT sessions_study_level_other_chk CHECK (char_length(study_level_other) <= 50);

-- 3. set_background (replaces the 0008 version). The new parameters default to NULL, so the
-- previous client call {p_session_id, p_type, p_other} still resolves to this function.
-- Answers that do not apply to the chosen type are stored as NULL.
DROP FUNCTION IF EXISTS set_background(TEXT, TEXT, TEXT);

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

  -- Keep only the answers that belong to the chosen type
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
  IF v_level IS NOT NULL AND v_level NOT IN ('year_1','year_2','year_3','year_4','masters','phd',
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

-- 4. withdraw_session (replaces the 0016 version; body unchanged except the two new free
-- texts, which are cleared like annotator_type_other)
CREATE OR REPLACE FUNCTION withdraw_session(p_session_id TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM 1 FROM sessions WHERE session_id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'unknown session'; END IF;
  DELETE FROM scores WHERE session_id = p_session_id;
  DELETE FROM batch_items WHERE batch_id IN (SELECT batch_id FROM batches WHERE session_id = p_session_id);
  DELETE FROM batches WHERE session_id = p_session_id;
  UPDATE sessions SET withdrawn_at = now(), ended_at = COALESCE(ended_at, now()), excluded = TRUE,
    annotator_type_other = NULL, role_other = NULL, study_level_other = NULL,
    comment = NULL, batches_completed = 0, last_active_at = now()
  WHERE session_id = p_session_id;
END;
$$;

REVOKE ALL ON FUNCTION withdraw_session(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION withdraw_session(TEXT) TO anon;

-- No table grant to anon: annotator writes stay inside SECURITY DEFINER functions (D-21, 0008).
-- Admin reads: the table-level SELECT grant to authenticated (0015) covers the new columns.

COMMIT;

-- Ask PostgREST to reload its schema cache (new function signature)
NOTIFY pgrst, 'reload schema';

-- Verify 1 (expect 5 rows, all nullable)
SELECT column_name, data_type, is_nullable FROM information_schema.columns
WHERE table_name = 'sessions'
  AND column_name IN ('role_category','role_other','experience_band','study_level','study_level_other')
ORDER BY column_name;

-- Verify 2 (expect 1 row: 8 arguments, security_definer = true; the 3-argument version is gone)
SELECT proname, pronargs, prosecdef AS security_definer FROM pg_proc WHERE proname = 'set_background';

-- Verify 3 (expect anon_execute = true, anon_table_update = false)
SELECT has_function_privilege('anon', 'set_background(text,text,text,text,text,text,text,text)', 'EXECUTE') AS anon_execute,
       has_table_privilege('anon', 'sessions', 'UPDATE') AS anon_table_update;

-- Verify 4 (expect 0: existing rows have no values in the new columns)
SELECT count(*) AS rows_with_new_values FROM sessions
WHERE COALESCE(role_category, role_other, experience_band, study_level, study_level_other) IS NOT NULL;
