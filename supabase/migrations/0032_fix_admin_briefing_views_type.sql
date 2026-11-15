-- ReqIQ-ANN migration 0032 — fixes the admin export error
-- "structure of query does not match function result type" (Dışa aktar, sheet Briefing).
-- Cause: admin_briefing_views (0026) declared config_id INT, but batches.config_id is BIGINT (0018).
-- Fix: declare config_id BIGINT and recreate the function (the return type changes, so DROP first).
-- Re-run safe. Run in Supabase SQL Editor AFTER 0031.

BEGIN;

DROP FUNCTION IF EXISTS admin_briefing_views();

CREATE FUNCTION admin_briefing_views()
RETURNS TABLE (
  session_id      TEXT,
  batch_id        TEXT,
  metric_id       TEXT,
  language_shown  TEXT,
  visible_seconds REAL,
  completed_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ,
  config_id       BIGINT
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

-- Verify (expect: config_id column type bigint; one row for admin_briefing_views)
SELECT proname, prosecdef AS security_definer FROM pg_proc WHERE proname = 'admin_briefing_views';
