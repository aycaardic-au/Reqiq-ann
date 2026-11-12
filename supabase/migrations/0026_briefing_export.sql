-- ReqIQ-ANN migration 0026 — Briefing export and admin read (SRS v1.7 FR-BRF-009, FR-ADM-007, OI-33 closed)
-- Adds one admin-only function that reads briefing_views (the table has no policies and no grants
-- for anon/authenticated, see 0023). The admin export gets the sheet "Briefing".
-- Forward-only (NFR-MNT-003). Run in Supabase SQL Editor after 0025, then verify.

BEGIN;

CREATE OR REPLACE FUNCTION admin_briefing_views()
RETURNS TABLE (
  session_id      TEXT,
  batch_id        TEXT,
  metric_id       TEXT,
  language_shown  TEXT,
  visible_seconds REAL,
  completed_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ,
  config_id       INT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not an admin'; END IF;
  RETURN QUERY
    SELECT bv.session_id, bv.batch_id, bv.metric_id, bv.language_shown, bv.visible_seconds,
           bv.completed_at, bv.created_at, b.config_id
    FROM briefing_views bv
    LEFT JOIN batches b ON b.batch_id = bv.batch_id
    ORDER BY bv.session_id, bv.batch_id, bv.metric_id;
END;
$$;

REVOKE ALL ON FUNCTION admin_briefing_views() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_briefing_views() TO authenticated;

COMMIT;

-- Verify (expect: one row, security_definer = true, and the grant for authenticated only)
SELECT proname, prosecdef AS security_definer FROM pg_proc WHERE proname = 'admin_briefing_views';
SELECT grantee, privilege_type FROM information_schema.routine_privileges
WHERE routine_name = 'admin_briefing_views' AND grantee IN ('anon', 'authenticated') ORDER BY grantee;
