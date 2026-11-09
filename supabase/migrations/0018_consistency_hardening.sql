-- ReqIQ-ANN migration 0018 — consistency and hardening release (SRS v1.1)
-- Closes the SRS v1.0 audit findings and adds robustness/security items:
--   * rubric/text versioning: every change creates a new rubric_config row (FR-ADM-009, FR-CFG-VER-001..003)
--   * batches.config_id: each batch records the configuration version it was scored with
--   * server-side QC at batch completion: attention-check discrepancies, consistency and speed flags (FR-QC-002..004, 008)
--   * finish_session: thank-you comment also closes the session (ADD-02 §6)
--   * requirements.source_meta: extra import columns kept as metadata (FR-DAT-003)
--   * admin: eligibility toggle (FR-DAT-004), status figures, config history/activation, study reset
--   * client error log (NFR-REL-004), faster assignment query (NFR-PERF-003)
-- Run in Supabase SQL Editor AFTER 0017. Re-run safe.

BEGIN;

-- ---------- schema ----------
ALTER TABLE requirements  ADD COLUMN IF NOT EXISTS source_meta JSONB NOT NULL DEFAULT '{}';
ALTER TABLE rubric_config ADD COLUMN IF NOT EXISTS note TEXT;
ALTER TABLE batches ADD COLUMN IF NOT EXISTS config_id BIGINT REFERENCES rubric_config(config_id);
ALTER TABLE batches ADD COLUMN IF NOT EXISTS ac_pairs SMALLINT;
ALTER TABLE batches ADD COLUMN IF NOT EXISTS ac_mismatches SMALLINT;
ALTER TABLE batches ADD COLUMN IF NOT EXISTS ac_max_diff SMALLINT;
ALTER TABLE batches ADD COLUMN IF NOT EXISTS median_seconds REAL;
UPDATE batches SET config_id = (SELECT config_id FROM rubric_config WHERE is_active LIMIT 1) WHERE config_id IS NULL;

CREATE TABLE IF NOT EXISTS client_errors (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  session_id TEXT,
  location   TEXT,
  message    TEXT,
  user_agent TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE client_errors ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON client_errors FROM anon, authenticated;
GRANT SELECT ON client_errors TO authenticated;
DROP POLICY IF EXISTS admin_read ON client_errors;
CREATE POLICY admin_read ON client_errors FOR SELECT TO authenticated USING (is_admin());

-- ---------- configuration versioning ----------
-- Internal: new active version = active content merged with the patch. Not callable by clients;
-- used by admin_merge_config and by the generated SQL files (run as owner in the SQL Editor).
CREATE OR REPLACE FUNCTION _config_new_version(p_patch JSONB, p_label TEXT, p_note TEXT)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  cur rubric_config%ROWTYPE;
  v_label TEXT;
BEGIN
  IF jsonb_typeof(p_patch) <> 'object' THEN RAISE EXCEPTION 'JSON object expected'; END IF;
  SELECT * INTO cur FROM rubric_config WHERE is_active LIMIT 1 FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'no active rubric_config row'; END IF;
  IF NOT EXISTS (SELECT 1 FROM jsonb_each(p_patch - '_comment') e WHERE cur.content -> e.key IS DISTINCT FROM e.value) THEN
    RETURN cur.version_label || ' (unchanged)';            -- every key already equal: no new version
  END IF;
  v_label := COALESCE(NULLIF(btrim(p_label), ''),
                      split_part(cur.version_label, ' ', 1) || ' ' || to_char(now() AT TIME ZONE 'Europe/Istanbul', 'YYYY-MM-DD HH24:MI'));
  UPDATE rubric_config SET is_active = FALSE WHERE config_id = cur.config_id;
  INSERT INTO rubric_config (version_label, content, is_active, note)
  VALUES (v_label, cur.content || (p_patch - '_comment'), TRUE, left(p_note, 500));
  RETURN v_label;
END;
$$;
REVOKE ALL ON FUNCTION _config_new_version(JSONB, TEXT, TEXT) FROM PUBLIC, anon, authenticated;

DROP FUNCTION IF EXISTS admin_merge_config(JSONB);
CREATE OR REPLACE FUNCTION admin_merge_config(p_patch JSONB, p_label TEXT DEFAULT NULL, p_note TEXT DEFAULT NULL)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not an admin'; END IF;
  RETURN _config_new_version(p_patch, p_label, COALESCE(p_note, 'admin upload: ' || (SELECT string_agg(k, ', ') FROM jsonb_object_keys(p_patch - '_comment') k)));
END;
$$;

CREATE OR REPLACE FUNCTION admin_activate_config(p_config_id BIGINT)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v TEXT;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not an admin'; END IF;
  SELECT version_label INTO v FROM rubric_config WHERE config_id = p_config_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'unknown config'; END IF;
  UPDATE rubric_config SET is_active = FALSE WHERE is_active AND config_id <> p_config_id;
  UPDATE rubric_config SET is_active = TRUE WHERE config_id = p_config_id;
  RETURN v;
END;
$$;
REVOKE ALL ON FUNCTION admin_merge_config(JSONB, TEXT, TEXT), admin_activate_config(BIGINT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_merge_config(JSONB, TEXT, TEXT), admin_activate_config(BIGINT) TO authenticated;

-- ---------- import keeps extra columns as metadata (FR-DAT-003) ----------
CREATE OR REPLACE FUNCTION admin_import_requirements(p_rows JSONB)
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n INT;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not an admin'; END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_rows) x
             WHERE COALESCE(x->>'req_id', '') = '' OR upper(x->>'language_tag') NOT IN ('EN','TR') OR COALESCE(x->>'project_id', '') = '') THEN
    RAISE EXCEPTION 'every row needs req_id, language_tag (EN/TR) and project_id';
  END IF;
  INSERT INTO requirements (req_id, base_id, language_tag, project_id, text_en, text_tr, eligible, req_type, source_meta)
  SELECT x->>'req_id', NULLIF(x->>'base_id', ''), upper(x->>'language_tag'), x->>'project_id',
         NULLIF(x->>'text_en', ''), NULLIF(x->>'text_tr', ''),
         COALESCE((x->>'eligible')::BOOLEAN, TRUE), COALESCE(NULLIF(upper(x->>'req_type'), ''), 'UNKNOWN'),
         x - ARRAY['req_id','base_id','language_tag','project_id','text_en','text_tr','eligible','req_type']
  FROM jsonb_array_elements(p_rows) x
  ON CONFLICT (req_id) DO UPDATE SET base_id = EXCLUDED.base_id, language_tag = EXCLUDED.language_tag,
    project_id = EXCLUDED.project_id, text_en = EXCLUDED.text_en, text_tr = EXCLUDED.text_tr,
    eligible = EXCLUDED.eligible, req_type = EXCLUDED.req_type,
    source_meta = requirements.source_meta || EXCLUDED.source_meta;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$$;

-- Eligibility toggle for admins (FR-DAT-004)
GRANT UPDATE (eligible) ON requirements TO authenticated;
DROP POLICY IF EXISTS admin_update ON requirements;
CREATE POLICY admin_update ON requirements FOR UPDATE TO authenticated USING (is_admin()) WITH CHECK (is_admin());

-- ---------- faster requirement picking (NFR-PERF-003): score counts computed once ----------
CREATE OR REPLACE FUNCTION pick_requirements(p_session_id TEXT, p_lang TEXT, p_n INT, p_exclude TEXT[], p_by_base BOOLEAN)
RETURNS TEXT[] LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  cfg app_config%ROWTYPE;
  picked TEXT[] := '{}';
  used TEXT[] := COALESCE(p_exclude, '{}');
  per_project JSONB := '{}';
  cap INT;
  rec RECORD;
  k TEXT;
  pass INT;
BEGIN
  SELECT * INTO cfg FROM app_config WHERE id = 1;
  IF p_n <= 0 THEN RETURN picked; END IF;
  cap := GREATEST(1, floor(cfg.project_id_cap_pct * p_n)::INT);
  CREATE TEMP TABLE IF NOT EXISTS _cand (req_id TEXT, key TEXT, project_id TEXT, tier INT, rnd DOUBLE PRECISION) ON COMMIT DROP;
  TRUNCATE _cand;
  INSERT INTO _cand
  SELECT r.req_id,
         CASE WHEN p_by_base THEN COALESCE(r.base_id, r.req_id) ELSE r.req_id END,
         r.project_id,
         CASE WHEN COALESCE(c.n, 0) = 0 THEN 0 WHEN c.n < cfg.coverage_target THEN 1 ELSE 2 END,
         random()
  FROM requirements r
  LEFT JOIN (
    SELECT s.req_id, count(DISTINCT s.session_id) AS n
    FROM scores s
    JOIN batch_items bi ON bi.batch_item_id = s.batch_item_id AND NOT bi.is_attention_check
    JOIN sessions se ON se.session_id = s.session_id AND NOT se.excluded
    GROUP BY s.req_id) c ON c.req_id = r.req_id
  WHERE r.eligible AND r.language_tag = p_lang;
  FOR pass IN 1..2 LOOP            -- pass 2 relaxes the ProjectID cap (ADD-01 §5 step 5)
    FOR rec IN SELECT * FROM _cand ORDER BY tier, rnd LOOP
      EXIT WHEN cardinality(picked) >= p_n;
      k := rec.key;
      CONTINUE WHEN k = ANY (used) OR rec.req_id = ANY (picked);
      IF pass = 1 AND COALESCE((per_project ->> rec.project_id)::INT, 0) >= cap THEN CONTINUE; END IF;
      picked := picked || rec.req_id;
      used := used || k;
      per_project := per_project || jsonb_build_object(rec.project_id, COALESCE((per_project ->> rec.project_id)::INT, 0) + 1);
    END LOOP;
    EXIT WHEN cardinality(picked) >= p_n;
  END LOOP;
  RETURN picked;
END;
$$;
REVOKE ALL ON FUNCTION pick_requirements(TEXT, TEXT, INT, TEXT[], BOOLEAN) FROM PUBLIC, anon;

-- assign_batch: records the active configuration version; requires the background form (D-20)
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
  IF ses.annotator_type IS NULL THEN RAISE EXCEPTION 'background form not completed'; END IF;
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

  INSERT INTO batches (batch_id, session_id, config_id)
  VALUES (v_batch, p_session_id, (SELECT config_id FROM rubric_config WHERE is_active LIMIT 1));   -- FR-CFG-VER-002
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

-- ---------- QC at batch completion (FR-QC-002..004, FR-QC-008) ----------
CREATE OR REPLACE FUNCTION complete_batch(p_session_id TEXT, p_batch_id TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  b batches%ROWTYPE;
  missing INT;
  cfg app_config%ROWTYPE;
  ses sessions%ROWTYPE;
  v_pairs INT; v_mis INT; v_max INT; v_med REAL; v_sess_med REAL;
BEGIN
  SELECT * INTO b FROM batches WHERE batch_id = p_batch_id AND session_id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'unknown batch for this session'; END IF;
  SELECT count(*) INTO missing FROM batch_items bi
  WHERE bi.batch_id = p_batch_id
    AND (SELECT count(*) FROM scores s WHERE s.batch_item_id = bi.batch_item_id AND s.session_id = p_session_id) < 6;
  IF missing > 0 THEN RAISE EXCEPTION 'batch has % unscored items', missing; END IF;
  SELECT * INTO cfg FROM app_config WHERE id = 1;

  IF b.completed_at IS NULL THEN
    -- attention checks: compare each duplicate with its original, metric by metric
    SELECT count(*), count(*) FILTER (WHERE a.cannot_assess IS DISTINCT FROM o.cannot_assess OR a.score IS DISTINCT FROM o.score),
           COALESCE(max(abs(a.score - o.score)) FILTER (WHERE NOT a.cannot_assess AND NOT o.cannot_assess), 0)
    INTO v_pairs, v_mis, v_max
    FROM batch_items d
    JOIN batch_items oi ON oi.batch_id = d.batch_id AND oi.req_id = d.req_id AND NOT oi.is_attention_check
    JOIN scores a ON a.batch_item_id = d.batch_item_id AND a.session_id = p_session_id
    JOIN scores o ON o.batch_item_id = oi.batch_item_id AND o.session_id = p_session_id AND o.metric_id = a.metric_id
    WHERE d.batch_id = p_batch_id AND d.is_attention_check;
    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY time_seconds) INTO v_med
    FROM batch_items WHERE batch_id = p_batch_id AND time_seconds IS NOT NULL;

    UPDATE batches SET completed_at = now(), ac_pairs = v_pairs, ac_mismatches = v_mis, ac_max_diff = v_max, median_seconds = v_med
    WHERE batch_id = p_batch_id;

    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY bi.time_seconds) INTO v_sess_med
    FROM batch_items bi JOIN batches bb ON bb.batch_id = bi.batch_id
    WHERE bb.session_id = p_session_id AND bb.completed_at IS NOT NULL AND bi.time_seconds IS NOT NULL;

    UPDATE sessions SET
      batches_completed = batches_completed + 1,
      flag_consistency = flag_consistency OR v_max >= 2,                      -- FR-QC-003: 0↔2 on any metric
      flag_speed = COALESCE(v_sess_med < cfg.speed_flag_threshold_sec, FALSE), -- FR-QC-004: re-evaluated each batch
      last_active_at = now()
    WHERE session_id = p_session_id;
  END IF;

  SELECT * INTO ses FROM sessions WHERE session_id = p_session_id;
  RETURN jsonb_build_object(
    'batch_count', (SELECT count(*) FROM batch_items WHERE batch_id = p_batch_id),
    'batch_number', (SELECT count(*) FROM batches WHERE session_id = p_session_id AND created_at <= b.created_at),
    'total', (SELECT count(*) FROM batch_items bi JOIN batches bb ON bb.batch_id = bi.batch_id
              WHERE bb.session_id = p_session_id AND bb.completed_at IS NOT NULL),
    'batches_completed', ses.batches_completed,
    'can_continue', ses.batches_completed < cfg.max_batches_per_session);
END;
$$;

-- ---------- thank-you: save comment and close the session (ADD-02 §6) ----------
CREATE OR REPLACE FUNCTION finish_session(p_session_id TEXT, p_comment TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v TEXT := NULLIF(btrim(p_comment), '');
BEGIN
  IF char_length(v) > 500 THEN RAISE EXCEPTION 'comment longer than 500 characters'; END IF;
  UPDATE sessions SET comment = COALESCE(v, comment), ended_at = COALESCE(ended_at, now()), last_active_at = now()
  WHERE session_id = p_session_id AND withdrawn_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'unknown session'; END IF;
END;
$$;
REVOKE ALL ON FUNCTION finish_session(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION finish_session(TEXT, TEXT) TO anon;

-- ---------- client error log (NFR-REL-004) ----------
CREATE OR REPLACE FUNCTION log_client_error(p_session_id TEXT, p_location TEXT, p_message TEXT, p_user_agent TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- simple flood guard: at most 200 entries per hour in total
  IF (SELECT count(*) FROM client_errors WHERE created_at > now() - interval '1 hour') >= 200 THEN RETURN; END IF;
  INSERT INTO client_errors (session_id, location, message, user_agent)
  VALUES (left(p_session_id, 64), left(p_location, 200), left(p_message, 2000), left(p_user_agent, 300));
END;
$$;
REVOKE ALL ON FUNCTION log_client_error(TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION log_client_error(TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;

-- ---------- admin status and study reset ----------
CREATE OR REPLACE FUNCTION admin_status()
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not an admin'; END IF;
  RETURN jsonb_build_object(
    'strategy', (SELECT sampling_strategy FROM app_config WHERE id = 1),
    'config_version', (SELECT version_label FROM rubric_config WHERE is_active LIMIT 1),
    'config_versions', (SELECT count(*) FROM rubric_config),
    'flag_consistency', (SELECT count(*) FROM sessions WHERE flag_consistency),
    'flag_speed', (SELECT count(*) FROM sessions WHERE flag_speed),
    'client_errors_24h', (SELECT count(*) FROM client_errors WHERE created_at > now() - interval '24 hours'),
    'ended', (SELECT count(*) FROM sessions WHERE ended_at IS NOT NULL AND withdrawn_at IS NULL),
    'withdrawn', (SELECT count(*) FROM sessions WHERE withdrawn_at IS NOT NULL));
END;
$$;

-- Deletes all participant data (sessions, batches, items, scores, client errors) — e.g. after the pilot.
-- Requirements, reference labels, configuration versions and parameters are kept.
CREATE OR REPLACE FUNCTION admin_reset_study(p_confirm TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n_s INT;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not an admin'; END IF;
  IF p_confirm IS DISTINCT FROM 'SIFIRLA' THEN RAISE EXCEPTION 'confirmation text must be SIFIRLA'; END IF;
  SELECT count(*) INTO n_s FROM sessions;
  DELETE FROM scores; DELETE FROM batch_items; DELETE FROM batches; DELETE FROM sessions; DELETE FROM client_errors;
  RETURN jsonb_build_object('sessions_deleted', n_s);
END;
$$;
REVOKE ALL ON FUNCTION admin_status(), admin_reset_study(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_status(), admin_reset_study(TEXT) TO authenticated;

-- set_comment is replaced by finish_session; kept for older clients
COMMIT;

-- Verify: expect 7 rows
SELECT proname FROM pg_proc WHERE proname IN ('_config_new_version','admin_merge_config','admin_activate_config',
  'finish_session','log_client_error','admin_status','admin_reset_study') ORDER BY 1;
