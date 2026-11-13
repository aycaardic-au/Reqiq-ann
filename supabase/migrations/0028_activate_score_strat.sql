-- ReqIQ-ANN migration 0028 (D-55, 13 Nov 2026): activate SCORE-STRAT for round 1 sampling.
-- Run in Supabase SQL Editor AFTER 0027, in the same session. Forward-only; safe to re-run.
-- Why: 0027 makes DIST and SCORE-STRAT work; the column default is 'DIST', so without this line
-- DIST would become active as soon as 0027 runs. Strategy is an admin parameter (Parametreler tab) and can be changed there.
-- Preconditions (checked by the user before running): reference_labels holds the 50 trial pre-scores (migration 0004).
-- Requirements without a pre-score are treated as 'unknown' (neutral), not excluded.

UPDATE app_config SET sampling_strategy = 'SCORE-STRAT' WHERE id = 1;

-- Verify (expect 'SCORE-STRAT'):
SELECT sampling_strategy, score_strat_allocation, project_id_cap_pct FROM app_config WHERE id = 1;
