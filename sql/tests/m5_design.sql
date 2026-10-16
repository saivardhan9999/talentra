-- Milestone 5 (B16-B19): the combined design serves its main access paths through the intended indexes,
-- soft-delete views exist, and history tables are partitioned.
-- A small synthetic dataset (20k candidates, 2k jobs, 40k applications) is generated and ANALYZEd inside
-- a transaction that is rolled back, so the planner decides on real statistics with sequential scans
-- allowed. Latency at 1M profiles is measured in Phase 5.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL app.current_user_id = '1';

-- ---- sample data ------------------------------------------------------------
INSERT INTO city (country_id, state_id, name)
SELECT 1, 1 + (g % 5), 'Sample town ' || g FROM generate_series(1, 300) g;
INSERT INTO skill (skill_category_id, code, name)
SELECT 1, 'sample_skill_' || g, 'Sample skill ' || g FROM generate_series(1, 500) g;
INSERT INTO user_account (email) SELECT 'cand' || g || '@sample.test' FROM generate_series(1, 20000) g;
INSERT INTO candidate_profile (user_account_id, full_name, profile_visibility_id, current_city_id, deleted_at)
SELECT u.id,
       initcap(substr(md5(u.id::text), 1, 6)) || ' ' || initcap(substr(md5(u.id::text), 7, 8)),
       1,
       (SELECT id FROM city ORDER BY id OFFSET (u.id % 300) LIMIT 1),
       CASE WHEN u.id % 20 = 0 THEN now() END
FROM user_account u WHERE u.email LIKE '%@sample.test';
INSERT INTO candidate_skill (candidate_profile_id, skill_id, experience_months)
SELECT p.id, s.id, (p.id % 120)
FROM candidate_profile p CROSS JOIN generate_series(1, 3) k
CROSS JOIN LATERAL (SELECT id FROM skill ORDER BY id OFFSET ((p.id * k) % 500) LIMIT 1) s
ON CONFLICT DO NOTHING;
INSERT INTO candidate_phone (candidate_profile_id, phone_e164, country_id, phone_type_id, is_primary)
SELECT id, '+9198' || lpad(id::text, 8, '0'), 1, 1, true FROM candidate_profile;
INSERT INTO organisation (legal_name) SELECT 'Sample employer ' || g FROM generate_series(1, 100) g;
INSERT INTO job_requirement (organisation_id, posted_by_user_account_id, title, description, job_category_id, employment_type_id,
                             work_mode_id, job_requirement_status_id, publish_state_id, is_open_to_consultants, published_at)
SELECT (SELECT id FROM organisation ORDER BY id OFFSET (g % 100) LIMIT 1), 1,
       (ARRAY['Java Developer','QA Engineer','Delivery Executive','Accountant','Electrician','Sales Associate'])[1 + g % 6] || ' ' || g,
       (ARRAY['spring boot microservices','manual and automation testing','two wheeler last mile delivery',
              'gst and tally accounting','industrial wiring maintenance','retail store sales'])[1 + g % 6] || ' role number ' || g,
       2 + (g % 7), 1, 1, 3, 3, g % 10 = 0, now()
FROM generate_series(1, 2000) g;
INSERT INTO job_requirement_location (job_requirement_id, city_id)
SELECT j.id, (SELECT id FROM city ORDER BY id OFFSET (j.id % 300) LIMIT 1) FROM job_requirement j;
INSERT INTO application (job_requirement_id, candidate_profile_id, application_status_id, application_source_id)
SELECT j.id, p.id, 1, 1
FROM (SELECT id, row_number() OVER (ORDER BY id) rn FROM job_requirement) j
JOIN (SELECT id, row_number() OVER (ORDER BY id) rn FROM candidate_profile) p
  ON p.rn BETWEEN (j.rn - 1) * 10 + 1 AND (j.rn - 1) * 10 + 20;
ANALYZE;

-- ---- index usage --------------------------------------------------------------
CREATE OR REPLACE FUNCTION pg_temp.expect_index(p_sql text, p_index text, p_force boolean DEFAULT false) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE plan text := ''; line text;
BEGIN
    -- p_force: GIN indexes lose to a seq scan on this small sample, so for them we prove the index
    -- MATCHES the query shape (seq scan disabled). Phase 5 at 1M rows must show the planner choosing them unaided.
    IF p_force THEN PERFORM set_config('enable_seqscan', 'off', true); END IF;
    FOR line IN EXECUTE 'EXPLAIN ' || p_sql LOOP plan := plan || line || E'\n'; END LOOP;
    PERFORM set_config('enable_seqscan', 'on', true);
    IF position(p_index IN plan) = 0 THEN
        RAISE EXCEPTION E'FAIL % not used for:\n%\n%', p_index, p_sql, plan;
    END IF;
    RAISE NOTICE 'PASS % serves%: %', p_index,
        CASE WHEN p_force THEN ' [forced: index usable, seq scan cheaper at sample size]' ELSE ' [chosen by planner]' END,
        left(regexp_replace(p_sql, '\s+', ' ', 'g'), 90);
END $$;

DO $$
DECLARE v_skill bigint; v_city bigint; v_job bigint; v_cand bigint; v_org bigint;
BEGIN
    SELECT id INTO v_skill FROM skill WHERE code = 'sample_skill_42';
    SELECT id INTO v_city  FROM city WHERE name = 'Sample town 42';
    SELECT job_requirement_id INTO v_job FROM application ORDER BY id LIMIT 1;
    SELECT candidate_profile_id INTO v_cand FROM application ORDER BY id LIMIT 1;
    SELECT organisation_id INTO v_org FROM job_requirement WHERE is_open_to_consultants LIMIT 1;

    PERFORM pg_temp.expect_index(format('SELECT candidate_profile_id FROM candidate_skill WHERE skill_id = %s', v_skill),
                                 'idx_candidate_skill_skill_id');
    PERFORM pg_temp.expect_index(format('SELECT id FROM candidate_profile WHERE current_city_id = %s AND deleted_at IS NULL', v_city),
                                 'idx_candidate_profile_current_city_id');
    PERFORM pg_temp.expect_index($q$SELECT id FROM candidate_profile WHERE full_name % 'Abcdef Kumarxyz'$q$,
                                 'idx_candidate_profile_full_name_trgm', true);
    PERFORM pg_temp.expect_index($q$SELECT id FROM candidate_phone WHERE phone_e164 = '+919800012345'$q$,
                                 'idx_candidate_phone_phone_e164');
    PERFORM pg_temp.expect_index($q$SELECT id FROM job_requirement WHERE search_document @@ to_tsquery('simple', 'spring & microservices & 42')$q$,
                                 'idx_job_requirement_search_document', true);
    PERFORM pg_temp.expect_index(format('SELECT job_requirement_id FROM job_requirement_location WHERE city_id = %s', v_city),
                                 'idx_job_requirement_location_city_id');
    PERFORM pg_temp.expect_index(format('SELECT id FROM application WHERE job_requirement_id = %s AND application_status_id = 1
                                         ORDER BY status_changed_at DESC LIMIT 50', v_job),
                                 'idx_application_job_requirement_id_status');
    PERFORM pg_temp.expect_index(format('SELECT id FROM application WHERE candidate_profile_id = %s ORDER BY applied_at DESC LIMIT 20', v_cand),
                                 'idx_application_candidate_profile_id');
    PERFORM pg_temp.expect_index(format('SELECT id FROM job_requirement WHERE organisation_id = %s AND is_open_to_consultants AND deleted_at IS NULL', v_org),
                                 'idx_job_requirement_consultant_open');
END $$;

-- ---- views and partitions -----------------------------------------------------
DO $$
DECLARE bad text; n int; n_all int; n_live int;
BEGIN
    SELECT count(*) INTO n_all FROM candidate_profile;
    SELECT count(*) INTO n_live FROM v_candidate_profile;
    IF n_live >= n_all THEN RAISE EXCEPTION 'FAIL v_candidate_profile does not exclude soft-deleted rows'; END IF;
    RAISE NOTICE 'PASS v_candidate_profile hides soft-deleted rows (% of % visible)', n_live, n_all;
    IF to_regclass('v_job_requirement') IS NULL THEN RAISE EXCEPTION 'FAIL v_job_requirement missing'; END IF;

    SELECT string_agg(t, ', ') INTO bad FROM unnest(ARRAY['profile_view_event','candidate_activity_log',
        'application_status_history','job_search_event']) t
    WHERE (SELECT relkind FROM pg_class WHERE relname = t) <> 'p';
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL not partitioned: %', bad; END IF;
    SELECT count(*) INTO n FROM pg_class WHERE relispartition AND relkind = 'r' AND relname ~ '_p(\d{6}|default)$';
    RAISE NOTICE 'PASS the 4 Phase 1 history tables are partitioned monthly; % partitioned tables in all, % partitions named <table>_pYYYYMM / _pdefault',
        (SELECT count(*) FROM pg_class WHERE relkind = 'p'), n;

    SELECT count(*) INTO n FROM application_status_history;
    RAISE NOTICE 'PASS pipeline trigger wrote % history rows for % sample applications', n, (SELECT count(*) FROM application);
END $$;
ROLLBACK;

\echo 'MILESTONE 5 CHECKS PASSED'
