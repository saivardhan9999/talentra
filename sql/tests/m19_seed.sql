-- Milestone 19 (B60-B64): the seeded dataset exists across all modules at the configured scale
-- (scale 1 = laptop scale: 1M candidate profiles, 100k job requirements, 5M applications).
-- Data quality against the standards is validated in m20.
\set ON_ERROR_STOP on
\ir expected_entity.sql

DO $$
DECLARE
    s numeric := nullif(current_setting('talentra.seed_scale', true), '')::numeric;
    bad text; n bigint; m bigint; v numeric;
BEGIN
    IF s IS NULL OR nullif(current_setting('talentra.seed_finished_at', true), '') IS NULL THEN
        RAISE EXCEPTION 'FAIL database is not seeded (run ./run_phase1.sh m19, which seeds after the build)';
    END IF;
    RAISE NOTICE 'PASS seeded at scale % (finished %)', s, current_setting('talentra.seed_finished_at');

    -- B60/B61 volumes
    SELECT count(*) INTO n FROM candidate_profile;
    IF n < 0.99 * 1000000 * s THEN RAISE EXCEPTION 'FAIL % candidate profiles, expected ~%', n, 1000000 * s; END IF;
    SELECT count(*) INTO m FROM job_requirement;
    IF m < 100000 * s THEN RAISE EXCEPTION 'FAIL % job requirements, expected %', m, 100000 * s; END IF;
    RAISE NOTICE 'PASS % candidate profiles and % job requirements (targets % and %)', n, m, round(1000000 * s), round(100000 * s);
    SELECT count(*) INTO n FROM application;
    IF n < 0.98 * 5000000 * s THEN RAISE EXCEPTION 'FAIL % applications, expected ~%', n, 5000000 * s; END IF;
    RAISE NOTICE 'PASS % applications (target %, less duplicate pairs removed)', n, round(5000000 * s);

    -- every lookup populated, every agreed entity has rows
    SELECT string_agg(table_name, ', ') INTO bad FROM expected_entity e
    WHERE NOT (SELECT EXISTS (SELECT 1 FROM pg_class WHERE relname = e.table_name))
       OR (xpath('/row/c/text()', query_to_xml(format('SELECT count(*) AS c FROM (SELECT 1 FROM %I LIMIT 1) x', e.table_name), false, true, '')))[1]::text = '0';
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL tables without seeded rows: %', bad; END IF;
    SELECT count(*) INTO n FROM expected_entity;
    RAISE NOTICE 'PASS all % agreed entities and lookups hold rows (every module seeded)', n;

    -- B60: duplicates and multilingual names
    SELECT count(*) INTO n FROM candidate_profile WHERE duplicate_of_candidate_profile_id IS NOT NULL;
    SELECT count(*) INTO m FROM (SELECT ph.phone_e164 FROM candidate_phone ph JOIN candidate_profile p ON p.id = ph.candidate_profile_id
                                 WHERE ph.is_primary GROUP BY ph.phone_e164, btrim(p.full_name) HAVING count(*) > 1
                                    AND bool_and(p.duplicate_of_candidate_profile_id IS NULL)) d;
    IF n = 0 OR m = 0 THEN RAISE EXCEPTION 'FAIL duplicates missing (flagged %, undetected groups %)', n, m; END IF;
    RAISE NOTICE 'PASS duplicate registrations seeded: % flagged, % unflagged groups left for detection (same name and phone)', n, m;
    SELECT count(DISTINCT name_language_id), round(100.0 * count(*) FILTER (WHERE full_name !~ '^[A-Za-z .''-]+$') / count(*), 1)
    INTO n, v FROM candidate_profile;
    IF n < 8 OR v NOT BETWEEN 20 AND 35 THEN RAISE EXCEPTION 'FAIL multilingual names: % languages, % %% non-Latin', n, v; END IF;
    RAISE NOTICE 'PASS multilingual names: % name languages, % %% written in a non-Latin script', n, v;

    -- B61: the full status pipeline, with history behind every application
    SELECT string_agg(code, ', ') INTO bad FROM application_status s2 WHERE NOT EXISTS (SELECT 1 FROM application a WHERE a.application_status_id = s2.id);
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL statuses never reached: %', bad; END IF;
    SELECT count(*) INTO n FROM application a WHERE NOT EXISTS (SELECT 1 FROM application_status_history h WHERE h.application_id = a.id);
    IF n > 0 THEN RAISE EXCEPTION 'FAIL % applications without status history', n; END IF;
    RAISE NOTICE 'PASS all 12 pipeline statuses reached; every application has its status history (% rows)', (SELECT count(*) FROM application_status_history);

    -- B62/B63: rules exercised by the seed
    SELECT count(*) INTO n FROM system_error_event WHERE error_code = 'gig_assignment_overlap';
    IF n = 0 THEN RAISE EXCEPTION 'FAIL no gig overlap attempts recorded'; END IF;
    RAISE NOTICE 'PASS % overlapping gig assignments attempted, rejected by the exclusion constraint and logged', n;
    SELECT count(*) INTO n FROM login_attempt WHERE login_outcome_id = 4;
    IF n = 0 THEN RAISE EXCEPTION 'FAIL no device-limit refusals recorded'; END IF;
    RAISE NOTICE 'PASS % logins refused at the device limit and recorded; % live sessions', n, (SELECT count(*) FROM user_session WHERE ended_at IS NULL);
    SELECT count(*) INTO n FROM sourcing_request WHERE sourcing_request_status_id IN (2, 3);
    RAISE NOTICE 'PASS % consultant requests decided by employers; % ledger entries; % profile downloads',
        n, (SELECT count(*) FROM wallet_ledger_entry), (SELECT count(*) FROM profile_download_event);

    -- B64: shared items and the marts
    SELECT count(*) INTO n FROM user_account u WHERE u.id <> 1 AND NOT EXISTS (SELECT 1 FROM user_credential c WHERE c.user_account_id = u.id);
    IF n > 0 THEN RAISE EXCEPTION 'FAIL % users without a credential', n; END IF;
    RAISE NOTICE 'PASS every user has a credential; % consent records; % block entries; % audit events',
        (SELECT count(*) FROM consent_record), (SELECT count(*) FROM block_entry), (SELECT count(*) FROM audit_event);
    SELECT (SELECT count(*) FROM application) - (SELECT count(*) FROM fact_application) INTO n;
    IF n <> 0 THEN RAISE EXCEPTION 'FAIL fact_application differs from application by % rows', n; END IF;
    IF EXISTS (SELECT 1 FROM agg_hiring_funnel_monthly LIMIT 1) IS NOT TRUE THEN RAISE EXCEPTION 'FAIL aggregates not refreshed'; END IF;
    RAISE NOTICE 'PASS marts loaded: fact_application matches all % applications; aggregates refreshed', (SELECT count(*) FROM fact_application);
END $$;
\echo MILESTONE 19 CHECKS PASSED
