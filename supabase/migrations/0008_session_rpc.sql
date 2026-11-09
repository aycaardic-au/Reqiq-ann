-- ReqIQ-ANN migration 0008 — session writes through server-side functions (D-21)
-- Why: in 0001 anon has UPDATE on sessions but no SELECT. PostgreSQL needs SELECT
-- rights to evaluate "WHERE session_id = ...", so background/comment updates fail
-- ("permission denied for table sessions"). Tested on PostgreSQL 16, 9 Nov 2026.
-- Fix: two SECURITY DEFINER functions; direct anon INSERT/UPDATE on sessions removed.
-- Run in Supabase SQL Editor AFTER 0007. Re-run safe.

BEGIN;

-- Text version of the consent notice the annotator agreed to (ethics audit trail)
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS consent_version TEXT;

-- [3] Consent: create the session row (D-20). Language is set once (FR-SES-008):
-- a repeated call for the same session_id changes nothing (idempotent, NFR-REL-001).
CREATE OR REPLACE FUNCTION create_session(p_session_id TEXT, p_language TEXT, p_consent_version TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_session_id IS NULL OR p_session_id !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'invalid session_id';
  END IF;
  IF p_language NOT IN ('EN','TR','BOTH') THEN
    RAISE EXCEPTION 'invalid language';
  END IF;
  INSERT INTO sessions (session_id, language_pref, consent_version)
  VALUES (p_session_id, p_language, left(p_consent_version, 20))
  ON CONFLICT (session_id) DO NOTHING;
END;
$$;

-- [4] Background (FR-ONB-003, FR-BKG-002/003). "Other" text kept only for type 'other'.
CREATE OR REPLACE FUNCTION set_background(p_session_id TEXT, p_type TEXT, p_other TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_other TEXT := NULLIF(btrim(p_other), '');
BEGIN
  IF p_type NOT IN ('student','industry','researcher','other') THEN
    RAISE EXCEPTION 'invalid annotator_type';
  END IF;
  IF p_type <> 'other' THEN
    v_other := NULL;
  END IF;
  IF char_length(v_other) > 50 THEN
    RAISE EXCEPTION 'annotator_type_other longer than 50 characters';
  END IF;
  UPDATE sessions
  SET annotator_type = p_type, annotator_type_other = v_other, last_active_at = now()
  WHERE session_id = p_session_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'unknown session';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION create_session(TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION set_background(TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION create_session(TEXT, TEXT, TEXT) TO anon;
GRANT EXECUTE ON FUNCTION set_background(TEXT, TEXT, TEXT) TO anon;

-- Direct table writes are no longer used by the client.
-- (The thank-you comment will get its own function in a later migration.)
REVOKE INSERT, UPDATE ON sessions FROM anon;
DROP POLICY IF EXISTS anon_insert_session ON sessions;
DROP POLICY IF EXISTS anon_update_session ON sessions;

COMMIT;

-- Verify (expect: 2 rows, both functions, security_definer = true)
SELECT proname, prosecdef AS security_definer
FROM pg_proc WHERE proname IN ('create_session','set_background') ORDER BY proname;
