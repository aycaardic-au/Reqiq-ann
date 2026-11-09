-- ReqIQ-ANN schema, migration 0001 (SRS v0.4, ADD-01 v0.3)
-- Run once: Supabase → SQL Editor → New query → paste → Run.

-- 1. Requirement pool (FR-DAT, ADD-01 §6)
CREATE TABLE requirements (
  req_id         TEXT PRIMARY KEY,
  text_en        TEXT,
  text_tr        TEXT,
  language_tag   TEXT NOT NULL CHECK (language_tag IN ('EN','TR')),
  project_id     TEXT NOT NULL,
  eligible       BOOLEAN NOT NULL DEFAULT TRUE,
  sentence_count SMALLINT,
  sentence_bin   TEXT CHECK (sentence_bin IN ('SHORT','MEDIUM','LONG')),
  has_modal      BOOLEAN,
  modal_type     TEXT CHECK (modal_type IN ('SHALL','MUST','SHOULD','WILL','MAY','NONE')),
  req_type       TEXT NOT NULL DEFAULT 'UNKNOWN' CHECK (req_type IN ('FR','NFR','UNKNOWN')),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. Sessions (FR-SES, FR-ONB-003, FR-LNG)
CREATE TABLE sessions (
  session_id           TEXT PRIMARY KEY,
  annotator_type       TEXT CHECK (annotator_type IN ('student','industry','researcher','other')),
  annotator_type_other TEXT CHECK (char_length(annotator_type_other) <= 50),
  language_pref        TEXT CHECK (language_pref IN ('EN','TR')),
  batches_completed    SMALLINT NOT NULL DEFAULT 0,
  comment              TEXT CHECK (char_length(comment) <= 500),
  flag_consistency     BOOLEAN NOT NULL DEFAULT FALSE,
  flag_speed           BOOLEAN NOT NULL DEFAULT FALSE,
  excluded             BOOLEAN NOT NULL DEFAULT FALSE,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_active_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. Batches and items (FR-ASN, FR-DB-001)
CREATE TABLE batches (
  batch_id     TEXT PRIMARY KEY,
  session_id   TEXT NOT NULL REFERENCES sessions(session_id),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ
);
CREATE INDEX batches_session_idx ON batches (session_id, created_at DESC);

CREATE TABLE batch_items (
  batch_item_id                   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  batch_id                        TEXT NOT NULL REFERENCES batches(batch_id) ON DELETE CASCADE,
  req_id                          TEXT NOT NULL REFERENCES requirements(req_id),
  position                        INTEGER NOT NULL,
  is_attention_check              BOOLEAN NOT NULL DEFAULT FALSE,
  attention_check_original_req_id TEXT,
  time_seconds                    REAL,
  UNIQUE (batch_id, position),
  CHECK (
    (is_attention_check = FALSE AND attention_check_original_req_id IS NULL) OR
    (is_attention_check = TRUE  AND attention_check_original_req_id IS NOT NULL)
  )
);

-- 4. Scores (FR-ANN-009, NFR-REL-001 upsert key)
CREATE TABLE scores (
  score_id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  session_id          TEXT NOT NULL REFERENCES sessions(session_id),
  batch_item_id       BIGINT NOT NULL REFERENCES batch_items(batch_item_id),
  req_id              TEXT NOT NULL REFERENCES requirements(req_id),
  metric_id           TEXT NOT NULL CHECK (metric_id IN ('M_IND_01','M_IND_02','M_IND_03','M_IND_04','M_IND_05','M_IND_06')),
  score               SMALLINT CHECK (score IN (0,1,2)),
  cannot_assess       BOOLEAN NOT NULL DEFAULT FALSE,
  note                TEXT CHECK (char_length(note) <= 500),
  annotation_language TEXT NOT NULL CHECK (annotation_language IN ('EN','TR')),
  round               SMALLINT NOT NULL DEFAULT 1,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK ((cannot_assess = TRUE AND score IS NULL) OR (cannot_assess = FALSE AND score IS NOT NULL)),
  UNIQUE (session_id, batch_item_id, metric_id)
);
CREATE INDEX scores_req_idx ON scores (req_id);

-- 5. Rubric configuration (EXT-CFG-001, FR-ADM-009)
CREATE TABLE rubric_config (
  config_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  version_label TEXT NOT NULL,
  content       JSONB NOT NULL,
  uploaded_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  is_active     BOOLEAN NOT NULL DEFAULT FALSE
);
CREATE UNIQUE INDEX rubric_one_active ON rubric_config (is_active) WHERE is_active;

-- 6. Operational parameters, single row (EXT-CFG-002, ADD-01 §8)
CREATE TABLE app_config (
  id                        SMALLINT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  batch_size                INT NOT NULL DEFAULT 30,
  attention_check_count     INT NOT NULL DEFAULT 2,
  coverage_target           INT NOT NULL DEFAULT 3,
  speed_flag_threshold_sec  INT NOT NULL DEFAULT 20,
  max_batches_per_session   INT NOT NULL DEFAULT 5,
  sampling_strategy         TEXT NOT NULL DEFAULT 'DIST' CHECK (sampling_strategy IN ('RAND','DIST','SCORE-STRAT','ADAPT')),
  dist_dimensions           TEXT[] NOT NULL DEFAULT ARRAY['project_id','sentence_bin'],
  score_strat_allocation    JSONB NOT NULL DEFAULT '{"0":0.33,"1":0.34,"2":0.33}',
  adapt_disagreement_weight REAL NOT NULL DEFAULT 0.7,
  project_id_cap_pct        REAL NOT NULL DEFAULT 0.25,
  strata_recompute_interval INT NOT NULL DEFAULT 10
);
INSERT INTO app_config (id) VALUES (1);

-- 7. Score strata for Strategy C/D (ADD-01 §7)
CREATE TABLE requirement_strata (
  req_id       TEXT NOT NULL REFERENCES requirements(req_id),
  metric_id    TEXT NOT NULL CHECK (metric_id IN ('M_IND_01','M_IND_02','M_IND_03','M_IND_04','M_IND_05','M_IND_06')),
  round        SMALLINT NOT NULL,
  score_count  SMALLINT NOT NULL DEFAULT 0,
  score_mean   REAL,
  score_median REAL,
  score_stddev REAL,
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (req_id, metric_id, round)
);

-- ============================================================
-- Row Level Security (EXT-DB-002)
-- The publishable key is public, so every table is locked down
-- and only the minimum needed by annotators is re-opened below.
-- ============================================================
ALTER TABLE requirements        ENABLE ROW LEVEL SECURITY;
ALTER TABLE sessions            ENABLE ROW LEVEL SECURITY;
ALTER TABLE batches             ENABLE ROW LEVEL SECURITY;
ALTER TABLE batch_items         ENABLE ROW LEVEL SECURITY;
ALTER TABLE scores              ENABLE ROW LEVEL SECURITY;
ALTER TABLE rubric_config       ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_config          ENABLE ROW LEVEL SECURITY;
ALTER TABLE requirement_strata  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon, authenticated;

-- Read-only: eligible requirements, active rubric, app config
GRANT SELECT ON requirements, rubric_config, app_config TO anon;
CREATE POLICY anon_read_eligible_requirements ON requirements
  FOR SELECT TO anon USING (eligible = TRUE);
CREATE POLICY anon_read_active_rubric ON rubric_config
  FOR SELECT TO anon USING (is_active = TRUE);
CREATE POLICY anon_read_app_config ON app_config
  FOR SELECT TO anon USING (TRUE);

-- Sessions: create a session, set background answers and comment.
-- Language is set once at insert and cannot be changed later (FR-SES-008).
-- Flags, exclusion and batch counter are NOT writable by annotators (FR-QC-008).
-- No SELECT for anon: annotators must not read other sessions.
GRANT INSERT (session_id, language_pref) ON sessions TO anon;
GRANT UPDATE (annotator_type, annotator_type_other, comment, last_active_at) ON sessions TO anon;
CREATE POLICY anon_insert_session ON sessions
  FOR INSERT TO anon WITH CHECK (TRUE);
CREATE POLICY anon_update_session ON sessions
  FOR UPDATE TO anon USING (TRUE) WITH CHECK (TRUE);

-- batches, batch_items, scores, requirement_strata: no direct anon access.
-- Batch assignment and score saving will go through server-side functions
-- (FR-ASN-010, NFR-REL-001) in later steps.
-- Admin access uses the service-role key inside Edge Functions only (EXT-DB-003).
