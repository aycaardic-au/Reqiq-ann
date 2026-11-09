-- ReqIQ-ANN migration 0002 (SRS v0.5, D-10 / D-11)
-- Run once in Supabase SQL Editor AFTER 0001. Safe to run on the 0001 schema.

-- 1. Language preference may now be BOTH (FR-LNG-002, FR-ASN-011)
ALTER TABLE sessions DROP CONSTRAINT IF EXISTS sessions_language_pref_check;
ALTER TABLE sessions ADD CONSTRAINT sessions_language_pref_check
  CHECK (language_pref IN ('EN','TR','BOTH'));

-- 2. Base requirement identifier, shared by EN and TR versions (FR-ASN-009)
ALTER TABLE requirements ADD COLUMN IF NOT EXISTS base_id TEXT;
CREATE INDEX IF NOT EXISTS requirements_base_idx ON requirements (base_id);
