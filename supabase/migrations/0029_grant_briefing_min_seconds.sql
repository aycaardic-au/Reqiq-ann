-- ReqIQ-ANN migration 0029 (FR-BRF-004, admin parameter save fix, 13 Nov 2026)
-- Migration 0023 added app_config.briefing_min_seconds but did not grant UPDATE on it.
-- The Parametreler screen saves all parameter fields in one UPDATE, so every save failed with
-- "permission denied for table app_config". Run once in Supabase SQL Editor. Safe to re-run.

GRANT UPDATE (briefing_min_seconds) ON app_config TO authenticated;

-- Verify (expect one row with privilege 'UPDATE' and column 'briefing_min_seconds'):
SELECT column_name, privilege_type
FROM information_schema.column_privileges
WHERE table_name = 'app_config' AND grantee = 'authenticated' AND column_name = 'briefing_min_seconds';
