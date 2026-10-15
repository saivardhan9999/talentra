-- Milestone 1 (B1-B3): DB provider fixed, UTF-8 end to end, required extensions present.
\set ON_ERROR_STOP on
DO $$
DECLARE v int;
BEGIN
    v := current_setting('server_version_num')::int;
    IF v < 160000 THEN RAISE EXCEPTION 'FAIL PostgreSQL 16+ required, found %', current_setting('server_version'); END IF;
    RAISE NOTICE 'PASS engine is PostgreSQL %', current_setting('server_version');

    IF pg_encoding_to_char((SELECT encoding FROM pg_database WHERE datname = current_database())) <> 'UTF8' THEN
        RAISE EXCEPTION 'FAIL database encoding is not UTF8';
    END IF;
    IF current_setting('client_encoding') <> 'UTF8' THEN RAISE EXCEPTION 'FAIL client encoding is not UTF8'; END IF;
    RAISE NOTICE 'PASS database and client encoding are UTF8';

    IF (SELECT count(*) FROM pg_extension WHERE extname IN ('pg_trgm', 'btree_gist')) <> 2 THEN
        RAISE EXCEPTION 'FAIL extensions pg_trgm and btree_gist must be installed';
    END IF;
    RAISE NOTICE 'PASS extensions pg_trgm (search) and btree_gist (exclusion constraints) installed';

    IF current_setting('TimeZone') NOT IN ('UTC', 'Etc/UTC') THEN
        RAISE NOTICE 'INFO server TimeZone is % (timestamptz stores UTC regardless)', current_setting('TimeZone');
    END IF;
END $$;
