-- ReqIQ-ANN migration 0015 — admin access (D-29): Supabase Auth users listed in `admins`
-- read all tables, edit app_config and session exclusion, import data and texts, see the dashboard.
-- Run in Supabase SQL Editor AFTER 0014. Re-run safe.
--
-- After running, create the admin account(s):
--   1. Supabase → Authentication → Users → Add user → e-mail + password (tick "Auto Confirm User").
--   2. Run:  INSERT INTO admins (user_id, email) SELECT id, email FROM auth.users WHERE email = '<admin e-mail>'
--            ON CONFLICT DO NOTHING;
--   3. Supabase → Authentication → Sign In / Providers: disable "Allow new users to sign up".

BEGIN;

CREATE TABLE IF NOT EXISTS admins (
  user_id    UUID PRIMARY KEY,
  email      TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE admins ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON admins FROM anon, authenticated;
GRANT SELECT ON admins TO authenticated;
DROP POLICY IF EXISTS admin_self ON admins;
CREATE POLICY admin_self ON admins FOR SELECT TO authenticated USING (user_id = auth.uid());

CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM admins WHERE user_id = auth.uid());
$$;
REVOKE ALL ON FUNCTION is_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION is_admin() TO authenticated;

-- Read access for admins (exports, dashboard)
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['requirements','sessions','batches','batch_items','scores','rubric_config','app_config','reference_labels'] LOOP
    EXECUTE format('GRANT SELECT ON %I TO authenticated', t);
    EXECUTE format('DROP POLICY IF EXISTS admin_read ON %I', t);
    EXECUTE format('CREATE POLICY admin_read ON %I FOR SELECT TO authenticated USING (is_admin())', t);
  END LOOP;
END $$;

-- Configurable parameters (EXT-CFG-002, ADD-01 §8) and session exclusion (FR-SES-007)
GRANT UPDATE (batch_size, attention_check_count, coverage_target, speed_flag_threshold_sec, max_batches_per_session,
              sampling_strategy, dist_dimensions, score_strat_allocation, adapt_disagreement_weight,
              project_id_cap_pct, strata_recompute_interval) ON app_config TO authenticated;
DROP POLICY IF EXISTS admin_update ON app_config;
CREATE POLICY admin_update ON app_config FOR UPDATE TO authenticated USING (is_admin()) WITH CHECK (is_admin());
ALTER TABLE app_config DROP CONSTRAINT IF EXISTS app_config_ranges;
ALTER TABLE app_config ADD CONSTRAINT app_config_ranges CHECK (
  batch_size BETWEEN 4 AND 200 AND attention_check_count BETWEEN 0 AND 10 AND attention_check_count < batch_size
  AND coverage_target BETWEEN 1 AND 20 AND max_batches_per_session BETWEEN 1 AND 50
  AND speed_flag_threshold_sec BETWEEN 0 AND 600 AND project_id_cap_pct > 0 AND project_id_cap_pct <= 1);

GRANT UPDATE (excluded) ON sessions TO authenticated;
DROP POLICY IF EXISTS admin_update ON sessions;
CREATE POLICY admin_update ON sessions FOR UPDATE TO authenticated USING (is_admin()) WITH CHECK (is_admin());

-- Dashboard figures in one call
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
    'by_language', (SELECT COALESCE(jsonb_object_agg(language_pref, n), '{}') FROM (SELECT language_pref, count(*) n FROM sessions GROUP BY 1) x),
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
          '2', count(*) FILTER (WHERE s.score = 2), 'ca', count(*) FILTER (WHERE s.cannot_assess)) d
        FROM scores s JOIN batch_items bi ON bi.batch_item_id = s.batch_item_id AND NOT bi.is_attention_check
        JOIN sessions se ON se.session_id = s.session_id AND NOT se.excluded
        GROUP BY 1) x),
    'daily', (SELECT COALESCE(jsonb_agg(jsonb_build_object('day', d, 'n', n) ORDER BY d), '[]') FROM (
        SELECT created_at::DATE d, count(*) n FROM sessions GROUP BY 1) x),
    'median_seconds', (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY time_seconds) FROM batch_items WHERE time_seconds IS NOT NULL)
  );
END;
$$;
REVOKE ALL ON FUNCTION admin_dashboard() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_dashboard() TO authenticated;

-- Import: requirement pool (upsert by req_id). Rows: req_id, base_id, language_tag, project_id, text_en, text_tr, eligible, req_type
CREATE OR REPLACE FUNCTION admin_import_requirements(p_rows JSONB)
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n INT;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not an admin'; END IF;
  INSERT INTO requirements (req_id, base_id, language_tag, project_id, text_en, text_tr, eligible, req_type)
  SELECT x->>'req_id', NULLIF(x->>'base_id', ''), upper(x->>'language_tag'), x->>'project_id',
         NULLIF(x->>'text_en', ''), NULLIF(x->>'text_tr', ''),
         COALESCE((x->>'eligible')::BOOLEAN, TRUE), COALESCE(NULLIF(upper(x->>'req_type'), ''), 'UNKNOWN')
  FROM jsonb_array_elements(p_rows) x
  ON CONFLICT (req_id) DO UPDATE SET base_id = EXCLUDED.base_id, language_tag = EXCLUDED.language_tag,
    project_id = EXCLUDED.project_id, text_en = EXCLUDED.text_en, text_tr = EXCLUDED.text_tr,
    eligible = EXCLUDED.eligible, req_type = EXCLUDED.req_type;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$$;

-- Import: reference labels (upsert by base_id × metric_id). Rows: base_id, metric_id, llm_score, llm_cannot_assess, llm_model
CREATE OR REPLACE FUNCTION admin_import_reference_labels(p_rows JSONB)
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n INT;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not an admin'; END IF;
  INSERT INTO reference_labels (base_id, metric_id, llm_score, llm_cannot_assess, llm_model)
  SELECT x->>'base_id', x->>'metric_id',
         CASE WHEN COALESCE((x->>'llm_cannot_assess')::BOOLEAN, FALSE) THEN NULL ELSE (x->>'llm_score')::SMALLINT END,
         COALESCE((x->>'llm_cannot_assess')::BOOLEAN, FALSE), COALESCE(NULLIF(x->>'llm_model', ''), 'unspecified')
  FROM jsonb_array_elements(p_rows) x
  ON CONFLICT (base_id, metric_id) DO UPDATE SET llm_score = EXCLUDED.llm_score,
    llm_cannot_assess = EXCLUDED.llm_cannot_assess, llm_model = EXCLUDED.llm_model;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$$;

-- Import: texts / rubric / hints — merge top-level keys into the active rubric_config row
-- (same effect as the generated SQL files; e.g. upload config/ui_texts.json).
CREATE OR REPLACE FUNCTION admin_merge_config(p_patch JSONB)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not an admin'; END IF;
  IF jsonb_typeof(p_patch) <> 'object' THEN RAISE EXCEPTION 'JSON object expected'; END IF;
  UPDATE rubric_config SET content = content || (p_patch - '_comment') WHERE is_active;
  RETURN (SELECT string_agg(k, ', ') FROM jsonb_object_keys(p_patch - '_comment') k);
END;
$$;

REVOKE ALL ON FUNCTION admin_import_requirements(JSONB), admin_import_reference_labels(JSONB), admin_merge_config(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_import_requirements(JSONB), admin_import_reference_labels(JSONB), admin_merge_config(JSONB) TO authenticated;

COMMIT;

-- Verify: expect 4 functions with security_definer = true
SELECT proname, prosecdef AS security_definer FROM pg_proc
WHERE proname IN ('admin_dashboard','admin_import_requirements','admin_import_reference_labels','admin_merge_config') ORDER BY proname;
