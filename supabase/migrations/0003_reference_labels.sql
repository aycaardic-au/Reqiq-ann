-- ReqIQ-ANN migration 0003 (ADD-01 §4 Phase 1, OI-SMP-01/03)
-- LLM pre-scores used ONLY by the batch sampling engine to balance
-- score distribution. Never shown to annotators; no public access.
-- Run once in Supabase SQL Editor AFTER 0002.

CREATE TABLE reference_labels (
  base_id            TEXT NOT NULL,
  metric_id          TEXT NOT NULL CHECK (metric_id IN ('M_IND_01','M_IND_02','M_IND_03','M_IND_04','M_IND_05','M_IND_06')),
  llm_score          SMALLINT CHECK (llm_score IN (0,1,2)),
  llm_cannot_assess  BOOLEAN NOT NULL DEFAULT FALSE,
  llm_defect_present BOOLEAN,
  llm_defect_note    TEXT,
  llm_model          TEXT NOT NULL,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (base_id, metric_id),
  CHECK ((llm_cannot_assess = TRUE AND llm_score IS NULL) OR (llm_cannot_assess = FALSE AND llm_score IS NOT NULL))
);

ALTER TABLE reference_labels ENABLE ROW LEVEL SECURITY;

-- Supabase grants anon/authenticated on new tables by default; close that explicitly.
REVOKE ALL ON reference_labels FROM anon, authenticated;
-- No policies: annotators cannot read or write. The sampling function (later step)
-- runs server-side (SECURITY DEFINER); admin reads via Edge Function (service role).
