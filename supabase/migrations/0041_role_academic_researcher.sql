-- ReqIQ-ANN migration 0041 (DRAFT, not applied) - new role option "Akademisyen / Araştırmacı" (academic_researcher)
-- Decision of 18 Nov 2026: the industry (Çalışan) role list gets one more option, placed before "Diğer".
--   1. CHECK sessions_role_category_chk accepts 'academic_researcher'.
--   2. set_background accepts 'academic_researcher' (same ten-parameter definition as 0040, only the role list differs).
-- Nothing else changes: the dashboard, the export and the admin import read role_category as free values.
-- Run in Supabase SQL Editor AFTER 0040, BEFORE importing ui_texts 2.33. Re-run safe. Not applied by the assistant.

ALTER TABLE sessions DROP CONSTRAINT IF EXISTS sessions_role_category_chk;
ALTER TABLE sessions ADD CONSTRAINT sessions_role_category_chk CHECK (role_category IN (
  'requirements_engineer','systems_engineer','test_engineer','project_manager',
  'software_developer','academic_researcher','other','prefer_not_to_say'));

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
       'project_manager','software_developer','academic_researcher','other','prefer_not_to_say') THEN
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
