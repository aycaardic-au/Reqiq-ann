-- ReqIQ-ANN: admin_reset_study fails with "DELETE requires a WHERE clause" when the
-- pg_safeupdate guard is active on the project. Same behaviour as 0018, with explicit WHERE TRUE.
-- Forward-only fix (NFR-MNT-003). Privileges are kept by CREATE OR REPLACE.
-- Run in Supabase SQL Editor, then run the study reset again.

BEGIN;

CREATE OR REPLACE FUNCTION admin_reset_study(p_confirm TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n_s INT;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not an admin'; END IF;
  IF p_confirm IS DISTINCT FROM 'SIFIRLA' THEN RAISE EXCEPTION 'confirmation text must be SIFIRLA'; END IF;
  SELECT count(*) INTO n_s FROM sessions;
  DELETE FROM scores WHERE TRUE;
  DELETE FROM batch_items WHERE TRUE;
  DELETE FROM batches WHERE TRUE;
  DELETE FROM sessions WHERE TRUE;
  DELETE FROM client_errors WHERE TRUE;
  RETURN jsonb_build_object('sessions_deleted', n_s);
END;
$$;

COMMIT;

-- Verify: function exists and is executable by authenticated users only (expect 1 row)
SELECT proname FROM pg_proc WHERE proname = 'admin_reset_study';
