-- ReqIQ-ANN migration 0014 — BOTH sessions may receive both language versions of a requirement (D-30)
-- Replaces pick_requirements (new signature) and assign_batch from 0013. FR-ASN-009 now applies per
-- language version for BOTH sessions; EN and TR sessions keep the base_id rule (D-15).
-- Run in Supabase SQL Editor AFTER 0013. Re-run safe.

BEGIN;

DROP FUNCTION IF EXISTS pick_requirements(TEXT, TEXT, INT, TEXT[]);

-- Pick up to p_n requirements of one language for a session (tiers, random, ProjectID cap).
CREATE OR REPLACE FUNCTION pick_requirements(p_session_id TEXT, p_lang TEXT, p_n INT, p_exclude TEXT[], p_by_base BOOLEAN)
RETURNS TEXT[] LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  cfg app_config%ROWTYPE;
  picked TEXT[] := '{}';
  bases TEXT[] := COALESCE(p_exclude, '{}');   -- keys already used: base_id (p_by_base) or req_id
  per_project JSONB := '{}';
  cap INT;
  rec RECORD;
  pass INT;
BEGIN
  SELECT * INTO cfg FROM app_config WHERE id = 1;
  IF p_n <= 0 THEN RETURN picked; END IF;
  cap := GREATEST(1, floor(cfg.project_id_cap_pct * p_n)::INT);
  FOR pass IN 1..2 LOOP            -- pass 2 relaxes the ProjectID cap (ADD-01 §5 step 5)
    FOR rec IN
      SELECT r.req_id, r.base_id, r.project_id,
             req_score_sessions(r.req_id) AS n_sc
      FROM requirements r
      WHERE r.eligible AND r.language_tag = p_lang
        AND NOT ((CASE WHEN p_by_base THEN COALESCE(r.base_id, r.req_id) ELSE r.req_id END) = ANY (bases))
        AND NOT (r.req_id = ANY (picked))
      ORDER BY CASE WHEN req_score_sessions(r.req_id) = 0 THEN 0
                    WHEN req_score_sessions(r.req_id) < cfg.coverage_target THEN 1 ELSE 2 END,
               random()
    LOOP
      EXIT WHEN cardinality(picked) >= p_n;
      CONTINUE WHEN (CASE WHEN p_by_base THEN COALESCE(rec.base_id, rec.req_id) ELSE rec.req_id END) = ANY (bases);
      IF pass = 1 AND COALESCE((per_project ->> rec.project_id)::INT, 0) >= cap THEN CONTINUE; END IF;
      picked := picked || rec.req_id;
      bases := bases || (CASE WHEN p_by_base THEN COALESCE(rec.base_id, rec.req_id) ELSE rec.req_id END);
      per_project := per_project || jsonb_build_object(rec.project_id, COALESCE((per_project ->> rec.project_id)::INT, 0) + 1);
    END LOOP;
    EXIT WHEN cardinality(picked) >= p_n;
  END LOOP;
  RETURN picked;
END;
$$;

-- K5: return the open batch of the session, or assign a new one (FR-ASN-010, FR-SES-006).
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

  INSERT INTO batches (batch_id, session_id) VALUES (v_batch, p_session_id);
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


REVOKE ALL ON FUNCTION pick_requirements(TEXT, TEXT, INT, TEXT[], BOOLEAN) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION assign_batch(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION assign_batch(TEXT) TO anon;

COMMIT;
