-- ReqIQ-ANN migration 0023 — Briefing K4b (SRS v1.4 FR-BRF, D-39, D-40)
-- Adds the per-page briefing record and the minimum display time parameter.
-- Forward-only (NFR-MNT-003). Run in Supabase SQL Editor after 0022, then verify.
-- Export sheet "Briefing" (FR-BRF-009) and an admin read of briefing_views are NOT part of this migration.

BEGIN;

-- 1. Parameter: minimum visible time of a briefing page before "Sonraki" is enabled (FR-BRF-004)
ALTER TABLE app_config
  ADD COLUMN IF NOT EXISTS briefing_min_seconds INT NOT NULL DEFAULT 10
  CHECK (briefing_min_seconds BETWEEN 0 AND 300);

-- 2. Briefing progress per session, batch and metric (FR-BRF-006)
CREATE TABLE IF NOT EXISTS briefing_views (
  view_id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  session_id      TEXT NOT NULL REFERENCES sessions(session_id),
  batch_id        TEXT NOT NULL REFERENCES batches(batch_id) ON DELETE CASCADE,
  metric_id       TEXT NOT NULL CHECK (metric_id IN ('M_IND_01','M_IND_02','M_IND_03','M_IND_04','M_IND_05','M_IND_06')),
  language_shown  TEXT NOT NULL CHECK (language_shown IN ('EN','TR','BOTH')),
  visible_seconds REAL NOT NULL DEFAULT 0 CHECK (visible_seconds >= 0 AND visible_seconds <= 3600),
  completed_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (session_id, batch_id, metric_id)
);

ALTER TABLE briefing_views ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON briefing_views FROM anon, authenticated;

-- 3. Save one page visit (called when the annotator leaves an unlocked page forward).
-- Visible seconds keep the largest value; completed_at keeps the first completion.
CREATE OR REPLACE FUNCTION save_briefing_view(
  p_session_id TEXT, p_batch_id TEXT, p_metric_id TEXT,
  p_language TEXT, p_visible_seconds REAL, p_completed BOOLEAN
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_sec REAL := LEAST(GREATEST(COALESCE(p_visible_seconds, 0), 0), 3600);
BEGIN
  IF NOT EXISTS (SELECT 1 FROM sessions WHERE session_id = p_session_id AND ended_at IS NULL AND withdrawn_at IS NULL) THEN
    RAISE EXCEPTION 'session ended or unknown';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM batches WHERE batch_id = p_batch_id AND session_id = p_session_id) THEN
    RAISE EXCEPTION 'unknown batch';
  END IF;
  INSERT INTO briefing_views (session_id, batch_id, metric_id, language_shown, visible_seconds, completed_at)
  VALUES (p_session_id, p_batch_id, p_metric_id, p_language, v_sec,
          CASE WHEN p_completed THEN now() END)
  ON CONFLICT (session_id, batch_id, metric_id) DO UPDATE SET
    visible_seconds = GREATEST(briefing_views.visible_seconds, EXCLUDED.visible_seconds),
    language_shown  = EXCLUDED.language_shown,
    completed_at    = COALESCE(briefing_views.completed_at, EXCLUDED.completed_at);
END;
$$;

-- 4. Read the completed metric pages of one batch (resume after reload, FR-BRF-006)
CREATE OR REPLACE FUNCTION get_briefing_progress(p_session_id TEXT, p_batch_id TEXT)
RETURNS TEXT[] LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN COALESCE((
    SELECT array_agg(metric_id ORDER BY metric_id)
    FROM briefing_views
    WHERE session_id = p_session_id AND batch_id = p_batch_id AND completed_at IS NOT NULL
  ), '{}');
END;
$$;

REVOKE ALL ON FUNCTION save_briefing_view(TEXT, TEXT, TEXT, TEXT, REAL, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION get_briefing_progress(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION save_briefing_view(TEXT, TEXT, TEXT, TEXT, REAL, BOOLEAN) TO anon;
GRANT EXECUTE ON FUNCTION get_briefing_progress(TEXT, TEXT) TO anon;

COMMIT;

-- Verify (expect: briefing_min_seconds column, the table, and two functions with security_definer = true)
SELECT column_name, column_default FROM information_schema.columns
WHERE table_name = 'app_config' AND column_name = 'briefing_min_seconds';
SELECT to_regclass('public.briefing_views') AS briefing_views_table;
SELECT proname, prosecdef AS security_definer FROM pg_proc
WHERE proname IN ('save_briefing_view', 'get_briefing_progress') ORDER BY proname;
