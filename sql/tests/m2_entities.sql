-- Milestone 2 (B4-B7): every agreed entity exists, and every table in the schema is owned by a module.
\set ON_ERROR_STOP on
\ir expected_entity.sql

DO $$
DECLARE bad text; n int;
BEGIN
    SELECT string_agg(table_name, ', ') INTO bad FROM expected_entity e
    WHERE e.phase IN (0, 1) AND to_regclass(e.table_name) IS NULL;
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL expected entity missing: %', bad; END IF;

    SELECT string_agg(c.relname, ', ') INTO bad FROM pg_class c JOIN pg_namespace s ON s.oid = c.relnamespace
    WHERE s.nspname = 'public' AND c.relkind IN ('r','p') AND NOT c.relispartition
      AND c.relname NOT IN (SELECT table_name FROM expected_entity);
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL table without an owning module: %', bad; END IF;

    FOR bad, n IN SELECT module, count(*) FROM expected_entity WHERE phase IN (0, 1) GROUP BY module ORDER BY module LOOP
        RAISE NOTICE 'PASS % : % entities present', rpad(bad, 22), n;
    END LOOP;
    -- Gig entities must NOT be in the core pipeline (decision D3)
    SELECT string_agg(k.conrelid::regclass || ' -> ' || k.confrelid::regclass, ', ') INTO bad FROM pg_constraint k
    WHERE k.contype = 'f' AND k.conrelid::regclass::text IN ('job_requirement', 'application')
      AND k.confrelid::regclass::text LIKE 'gig\_%';
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL core pipeline references gig tables: %', bad; END IF;
    RAISE NOTICE 'PASS no orphan tables; gig entities kept out of the core pipeline (D3)';
END $$;
