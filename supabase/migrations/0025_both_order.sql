-- ReqIQ-ANN migration 0025 — BOTH pair order is fixed: Turkish version first, then English version.
-- Replaces assign_batch from 0024 only (pick_pairs from 0024 stays in use).
-- Run in Supabase SQL Editor AFTER 0024. Re-run safe.

BEGIN;

-- assign_batch (0025): units = single requirements (EN/TR sessions), BOTH pairs "TR_x|EN_x" (fixed order),
-- attention checks "AC:req". Units are shuffled; attention checks are inserted between units at least 3 units
-- after their original; each unit is written as consecutive batch items.
CREATE OR REPLACE FUNCTION assign_batch(p_session_id TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  cfg app_config%ROWTYPE;
  ses sessions%ROWTYPE;
  open_batch TEXT;
  n_unique INT;
  used_bases TEXT[];
  used_reqs TEXT[];
  extra TEXT[];
  units TEXT[] := '{}';
  ord TEXT[];
  ac_n INT;
  ac_src INT;
  ins INT;
  i INT;
  pos INT := 0;
  v_batch TEXT := gen_random_uuid()::TEXT;
  v_req TEXT;
  is_ac BOOLEAN;
  ac_pos TEXT[] := '{}';
  b_bases TEXT[];
  b TEXT;
  en_req TEXT;
  tr_req TEXT;
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

  -- Requirements already shown to this session (EN/TR sessions: base-level rule, FR-ASN-009)
  SELECT COALESCE(array_agg(DISTINCT COALESCE(r.base_id, r.req_id)), '{}') INTO used_bases
  FROM batches b JOIN batch_items bi ON bi.batch_id = b.batch_id JOIN requirements r ON r.req_id = bi.req_id
  WHERE b.session_id = p_session_id;
  SELECT COALESCE(array_agg(DISTINCT bi.req_id), '{}') INTO used_reqs
  FROM batches b JOIN batch_items bi ON bi.batch_id = b.batch_id
  WHERE b.session_id = p_session_id;

  IF ses.language_pref = 'BOTH' THEN
    -- D-14 / D-30 / 12 Nov 2026: n_unique/2 pairs; each pair is TR and EN of one base_id, shown together
    b_bases := pick_pairs(p_session_id, n_unique / 2, used_reqs);
    FOREACH b IN ARRAY b_bases LOOP
      SELECT req_id INTO en_req FROM requirements WHERE base_id = b AND language_tag = 'EN' AND eligible LIMIT 1;
      SELECT req_id INTO tr_req FROM requirements WHERE base_id = b AND language_tag = 'TR' AND eligible LIMIT 1;
      IF en_req IS NULL OR tr_req IS NULL THEN CONTINUE; END IF;
      used_reqs := used_reqs || en_req || tr_req;
      -- 0025 (14 Nov 2026, user decision): fixed order inside a pair, Turkish first, then English
      units := units || (tr_req || '|' || en_req);
    END LOOP;
    -- Odd number of unique items (e.g. 25 with batch size 27): one single requirement in a random language
    -- The single comes from the language with more unused requirements, so a leftover version is not lost.
    IF n_unique % 2 = 1 THEN
      extra := pick_requirements(p_session_id,
        CASE WHEN (SELECT count(*) FROM requirements WHERE eligible AND language_tag = 'EN' AND NOT (req_id = ANY (used_reqs)))
               >= (SELECT count(*) FROM requirements WHERE eligible AND language_tag = 'TR' AND NOT (req_id = ANY (used_reqs)))
             THEN 'EN' ELSE 'TR' END,
        1, used_reqs, FALSE);
      units := units || extra;
    END IF;
  ELSE
    units := pick_requirements(p_session_id, ses.language_pref, n_unique, used_bases, TRUE);
  END IF;

  IF cardinality(units) = 0 THEN
    RETURN jsonb_build_object('status', 'exhausted');          -- FR-BTH-004
  END IF;

  -- Random order of the units (a pair stays together)
  SELECT array_agg(x ORDER BY random()) INTO ord FROM unnest(units) AS x;

  -- Attention checks (FR-ASN-005): duplicate of a unit's first item, placed at least 3 units after the original
  ac_n := CASE WHEN cardinality(ord) >= 8 THEN cfg.attention_check_count ELSE 0 END;
  FOR i IN 1..ac_n LOOP
    ac_src := 1 + floor(random() * (cardinality(ord) - 4))::INT;
    WHILE ord[ac_src] = ANY (ac_pos) OR ord[ac_src] LIKE 'AC:%' LOOP
      ac_src := 1 + floor(random() * (cardinality(ord) - 4))::INT;
    END LOOP;
    ins := ac_src + 3 + floor(random() * (cardinality(ord) - ac_src - 2))::INT;
    ac_pos := ac_pos || ord[ac_src];
    ord := ord[1:ins - 1] || ('AC:' || split_part(ord[ac_src], '|', 1)) || ord[ins:cardinality(ord)];
  END LOOP;

  INSERT INTO batches (batch_id, session_id, config_id)
  VALUES (v_batch, p_session_id, (SELECT config_id FROM rubric_config WHERE is_active LIMIT 1));   -- FR-CFG-VER-002

  FOR i IN 1..cardinality(ord) LOOP
    is_ac := ord[i] LIKE 'AC:%';
    FOR v_req IN
      SELECT x FROM unnest(string_to_array(CASE WHEN is_ac THEN substr(ord[i], 4) ELSE ord[i] END, '|')) AS x
    LOOP
      pos := pos + 1;
      INSERT INTO batch_items (batch_id, req_id, position, is_attention_check, attention_check_original_req_id, round)
      VALUES (v_batch, v_req, pos, is_ac, CASE WHEN is_ac THEN v_req END, 1 + req_score_sessions(v_req, p_session_id));   -- D-07
    END LOOP;
  END LOOP;

  UPDATE sessions SET last_active_at = now() WHERE session_id = p_session_id;
  RETURN batch_payload(p_session_id, v_batch);
END;
$$;
REVOKE ALL ON FUNCTION assign_batch(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION assign_batch(TEXT) TO anon;

COMMIT;

-- Verify (expect 3 rows; assign_batch is SECURITY DEFINER)
SELECT proname, prosecdef FROM pg_proc WHERE proname IN ('pick_pairs', 'assign_batch', 'pick_requirements') ORDER BY proname;
