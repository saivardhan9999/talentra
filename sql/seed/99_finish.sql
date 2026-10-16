-- =============================================================================
-- Talentra seed :: 99_finish.sql
-- Fresh planner statistics, the finish time on the database (read by M19/M20), the
-- generator's helper schema dropped (the generator itself is the sql/seed files).
-- =============================================================================
\set ON_ERROR_STOP on
ANALYZE;
DO $$ BEGIN
    EXECUTE format('ALTER DATABASE %I SET talentra.seed_finished_at = %L', current_database(), now()::text);
END $$;
SELECT 'database size after seeding: ' || pg_size_pretty(pg_database_size(current_database())) AS summary \gset
\echo :summary
SET client_min_messages = warning;
DROP SCHEMA seed CASCADE;
