-- ReqIQ-ANN migration 0007 — reference label model name (D-17)
-- Replaces the placeholder from migration 0004 with the confirmed model name.
-- Run in Supabase SQL Editor AFTER 0006. Re-run safe.

BEGIN;

UPDATE reference_labels
SET llm_model = 'chatgpt sol 5.6'
WHERE llm_model = 'reference-excel-unspecified';

-- Verify: expect one row, 'chatgpt sol 5.6', 150
SELECT llm_model, count(*) FROM reference_labels GROUP BY llm_model;

COMMIT;
