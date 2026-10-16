-- Milestone 7 (B24-B26): Administration, Organisation and account, and Gig marketplace entities exist.
-- The orphan-table check in m2 covers these modules too (shared expected_entity.sql).
\set ON_ERROR_STOP on
\ir expected_entity.sql

DO $$
DECLARE bad text; n int;
BEGIN
    SELECT string_agg(table_name, ', ') INTO bad FROM expected_entity e
    WHERE e.phase = 2 AND to_regclass(e.table_name) IS NULL;
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL expected entity missing: %', bad; END IF;

    FOR bad, n IN SELECT module, count(*) FROM expected_entity WHERE phase = 2 GROUP BY module ORDER BY module LOOP
        RAISE NOTICE 'PASS % : % entities present', rpad(bad, 22), n;
    END LOOP;

    -- Every docket §3 actor is a role
    SELECT string_agg(a, ', ') INTO bad FROM unnest(ARRAY['super_admin','admin','account_admin','guest','candidate',
        'employer','recruiter','consultant','placement_officer']) a
    WHERE NOT EXISTS (SELECT 1 FROM role r WHERE r.code = a);
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL actor without a role: %', bad; END IF;
    RAISE NOTICE 'PASS all 9 actors from docket §3 exist as roles';

    -- Gig is a separate subsystem: gig tables never reference the core job/application tables (D3)
    SELECT string_agg(k.conrelid::regclass || ' -> ' || k.confrelid::regclass, ', ') INTO bad FROM pg_constraint k
    WHERE k.contype = 'f' AND k.conrelid::regclass::text LIKE 'gig\_%'
      AND k.confrelid::regclass::text IN (SELECT table_name FROM expected_entity WHERE module = 'jobs_applications');
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL gig tables reference the core pipeline: %', bad; END IF;
    RAISE NOTICE 'PASS gig subsystem shares master data, identity and organisation only (D3)';
END $$;
