-- Milestone 10 (B33-B35): keys and constraints for Administration, Organisation and Gig.
-- Behavioural tests; everything (including the helper functions) is rolled back.
-- Row-level security is tested as talentra_app, the role the application connects as.
\set ON_ERROR_STOP on
BEGIN;
CREATE FUNCTION public.t_expect_fail(p_sql text, p_label text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS rejected: % (%)', p_label, SQLERRM;
        RETURN;
    END;
    RAISE EXCEPTION 'FAIL accepted but should be rejected: %', p_label;
END $$;
CREATE FUNCTION public.t_count(p_sql text) RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE n bigint;
BEGIN
    EXECUTE p_sql INTO n;
    RETURN n;
END $$;
CREATE FUNCTION public.t_id(p_name text) RETURNS bigint LANGUAGE sql AS $$ SELECT current_setting('t.' || p_name)::bigint $$;
CREATE FUNCTION public.t_as(p_name text) RETURNS void LANGUAGE sql AS $$ SELECT set_config('app.current_user_id', current_setting('t.' || p_name), true) $$;
SET LOCAL app.current_user_id = '1';

-- ---------------------------------------------------------------------------
-- Setup (as the system actor) + Administration and Organisation rules
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v bigint; v_n bigint; v_detail jsonb;
    u_admin bigint; u_emp bigint; u_reca bigint; u_recb bigint; u_old bigint; u_cand bigint; u_cand2 bigint;
    o_a bigint; o_b bigint; st_applied bigint;
BEGIN
    INSERT INTO user_account (email) VALUES ('admin@talentra.test') RETURNING id INTO u_admin;
    INSERT INTO user_account (email) VALUES ('owner@acme.test') RETURNING id INTO u_emp;
    INSERT INTO user_account (email) VALUES ('rec.a@acme.test') RETURNING id INTO u_reca;
    INSERT INTO user_account (email) VALUES ('rec.b@globex.test') RETURNING id INTO u_recb;
    INSERT INTO user_account (email) VALUES ('former.rec@acme.test') RETURNING id INTO u_old;
    INSERT INTO user_account (email) VALUES ('meera@mail.test') RETURNING id INTO u_cand;
    INSERT INTO user_account (email) VALUES ('arun@mail.test') RETURNING id INTO u_cand2;
    INSERT INTO organisation (legal_name) VALUES ('Acme Staffing Pvt Ltd') RETURNING id INTO o_a;
    INSERT INTO organisation (legal_name) VALUES ('Globex Corp') RETURNING id INTO o_b;
    PERFORM set_config('t.admin', u_admin::text, true); PERFORM set_config('t.emp', u_emp::text, true);
    PERFORM set_config('t.reca', u_reca::text, true);   PERFORM set_config('t.recb', u_recb::text, true);
    PERFORM set_config('t.old', u_old::text, true);     PERFORM set_config('t.cand', u_cand::text, true);
    PERFORM set_config('t.cand2', u_cand2::text, true);
    PERFORM set_config('t.org_a', o_a::text, true);     PERFORM set_config('t.org_b', o_b::text, true);

    -- Roles and the audit trail
    INSERT INTO user_account_role (user_account_id, role_id) VALUES (u_admin, 2) RETURNING id INTO v;
    SELECT count(*) INTO v_n FROM audit_event a JOIN audit_action x ON x.id = a.audit_action_id
    WHERE a.target_table = 'user_account_role' AND a.target_record_id = v AND x.code = 'create' AND a.created_by = 1;
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL role grant not audited'; END IF;
    RAISE NOTICE 'PASS role grant wrote an audit event with the actor';
    PERFORM t_expect_fail(format('INSERT INTO user_account_role (user_account_id, role_id) VALUES (%s, 2)', u_admin), 'second live grant of the same role');
    UPDATE user_account_role SET revoked_at = now() WHERE id = v;
    SELECT a.detail INTO v_detail FROM audit_event a WHERE a.target_table = 'user_account_role' AND a.target_record_id = v
      AND a.detail IS NOT NULL;
    IF NOT v_detail -> 'changed' ? 'revoked_at' THEN RAISE EXCEPTION 'FAIL revoke not audited: %', v_detail; END IF;
    RAISE NOTICE 'PASS role revoke audited with changed columns only: %', v_detail;
    INSERT INTO user_account_role (user_account_id, role_id) VALUES (u_admin, 2);
    RAISE NOTICE 'PASS role can be granted again after revocation';
    PERFORM t_expect_fail('UPDATE audit_event SET target_table = ''tampered''', 'editing the audit trail');
    PERFORM t_expect_fail('DELETE FROM audit_event', 'deleting the audit trail');
    PERFORM set_config('app.current_user_id', '', true);
    PERFORM t_expect_fail(format('INSERT INTO user_account_role (user_account_id, role_id) VALUES (%s, 1)', u_emp), 'role grant without an actor');
    PERFORM set_config('app.current_user_id', '1', true);

    -- Effective-dated organisation mapping
    INSERT INTO organisation_member (organisation_id, user_account_id, role_id) VALUES (o_a, u_emp, 6), (o_a, u_reca, 7), (o_b, u_recb, 7);
    INSERT INTO organisation_member (organisation_id, user_account_id, role_id, valid_from, valid_to)
    VALUES (o_a, u_old, 7, now() - interval '30 days', now() - interval '1 day');
    PERFORM t_expect_fail(format($q$INSERT INTO organisation_member (organisation_id, user_account_id, role_id, valid_from)
        VALUES (%s, %s, 7, now() - interval '1 hour')$q$, o_a, u_reca), 'overlapping recruiter mapping');
    INSERT INTO organisation_member (organisation_id, user_account_id, role_id, valid_from, valid_to)
    VALUES (o_a, u_old, 7, now() - interval '60 days', now() - interval '30 days');
    RAISE NOTICE 'PASS adjacent (non-overlapping) mapping period accepted';
    PERFORM t_expect_fail(format('INSERT INTO organisation_member (organisation_id, user_account_id, role_id) VALUES (%s, %s, 5)', o_a, u_cand),
        'organisation mapping with a non-organisation role (candidate)');
    PERFORM t_expect_fail(format('DELETE FROM organisation_member WHERE user_account_id = %s', u_old), 'deleting mapping history');

    -- Hierarchy
    UPDATE organisation SET parent_organisation_id = o_a WHERE id = o_b;
    RAISE NOTICE 'PASS Globex placed under Acme';
    PERFORM t_expect_fail(format('UPDATE organisation SET parent_organisation_id = %s WHERE id = %s', o_b, o_a), 'hierarchy cycle (Acme under its child)');
    PERFORM t_expect_fail(format('UPDATE organisation SET parent_organisation_id = %s WHERE id = %s', o_a, o_a), 'organisation as its own parent');
    UPDATE organisation SET parent_organisation_id = NULL WHERE id = o_b;

    -- Locations and identifiers
    INSERT INTO organisation_location (organisation_id, city_id, address_line_1, is_headquarters) VALUES (o_a, 1, '12 Anna Salai', true);
    PERFORM t_expect_fail(format($q$INSERT INTO organisation_location (organisation_id, city_id, address_line_1, is_headquarters)
        VALUES (%s, 3, '1 MG Road', true)$q$, o_a), 'second headquarters');
    INSERT INTO organisation_registration_identifier (organisation_id, registration_identifier_type_id, issuing_country_id,
        identifier_token, identifier_hmac, identifier_masked)
    VALUES (o_a, 1, 1, 'vault:tok_001', sha256('33ABCDE1234F1Z5'::bytea), '***********F1Z5');
    PERFORM t_expect_fail(format($q$INSERT INTO organisation_registration_identifier (organisation_id, registration_identifier_type_id,
        issuing_country_id, identifier_token, identifier_hmac, identifier_masked)
        VALUES (%s, 1, 1, 'vault:tok_002', sha256('33ABCDE1234F1Z5'::bytea), '***********F1Z5')$q$, o_b), 'same GSTIN registered twice');
    PERFORM t_expect_fail($q$UPDATE organisation_registration_identifier SET verification_status_id = 2$q$, 'verified without time and reference');
    PERFORM t_expect_fail(format($q$INSERT INTO organisation_registration_identifier (organisation_id, registration_identifier_type_id,
        issuing_country_id, identifier_token, identifier_hmac, identifier_masked) VALUES (%s, 2, 1, 'vault:tok_003', '\x01', '*')$q$, o_b),
        'identifier hash that is not HMAC-SHA256');
    UPDATE organisation SET verification_status_id = 2 WHERE id = o_a;
    SELECT a.detail INTO v_detail FROM audit_event a WHERE a.target_table = 'organisation' AND a.organisation_id = o_a AND a.detail IS NOT NULL
    ORDER BY a.id DESC LIMIT 1;
    IF v_detail -> 'changed' <> '["verification_status_id"]'::jsonb THEN RAISE EXCEPTION 'FAIL verification change not audited: %', v_detail; END IF;
    RAISE NOTICE 'PASS organisation verification change audited: %', v_detail;

    -- Jobs and applications used by the RLS tests: Acme draft + published, Globex draft + published
    INSERT INTO job_requirement (organisation_id, posted_by_user_account_id, title, description, job_category_id, employment_type_id,
        work_mode_id, job_requirement_status_id, publish_state_id, number_of_positions, published_at, expires_at)
    VALUES (o_a, u_emp, 'Acme draft', 'x', 4, 1, 1, 1, 1, 1, NULL, NULL),
           (o_a, u_emp, 'Acme Java Developer', 'x', 4, 1, 1, 3, 3, 1, now(), now() + interval '30 days'),
           (o_b, u_recb, 'Globex draft', 'x', 4, 1, 1, 1, 1, 1, NULL, NULL),
           (o_b, u_recb, 'Globex Data Analyst', 'x', 4, 1, 1, 3, 3, 1, now(), now() + interval '30 days');
    SELECT id INTO st_applied FROM application_status WHERE code = 'applied';
    PERFORM set_config('app.current_user_id', u_cand::text, true);
    INSERT INTO candidate_profile (user_account_id, full_name, profile_visibility_id) VALUES (u_cand, 'Meera', 1) RETURNING id INTO v;
    INSERT INTO application (job_requirement_id, candidate_profile_id, application_status_id, application_source_id)
    SELECT id, v, st_applied, 1 FROM job_requirement WHERE title = 'Acme Java Developer';
    PERFORM set_config('app.current_user_id', u_cand2::text, true);
    INSERT INTO candidate_profile (user_account_id, full_name, profile_visibility_id) VALUES (u_cand2, 'Arun', 1) RETURNING id INTO v;
    INSERT INTO application (job_requirement_id, candidate_profile_id, application_status_id, application_source_id)
    SELECT id, v, st_applied, 1 FROM job_requirement WHERE title = 'Globex Data Analyst';
    PERFORM set_config('app.current_user_id', '1', true);
END $$;

-- ---------------------------------------------------------------------------
-- Row-level security, as the application role
-- ---------------------------------------------------------------------------
SET LOCAL ROLE talentra_app;
DO $$
DECLARE v_n bigint;
    q_jobs text := 'SELECT count(*) FROM job_requirement';
    q_apps text := 'SELECT count(*) FROM application';
    ins_job text := $q$INSERT INTO job_requirement (organisation_id, posted_by_user_account_id, title, description, job_category_id,
        employment_type_id, work_mode_id, job_requirement_status_id, publish_state_id, number_of_positions) VALUES (%s, %s, '%s', 'x', 4, 1, 1, 1, 1, 1)$q$;
BEGIN
    PERFORM t_as('reca');
    v_n := t_count(q_jobs || ' WHERE organisation_id = ' || t_id('org_a'));
    IF v_n <> 2 THEN RAISE EXCEPTION 'FAIL recruiter sees % of own company''s 2 requirements', v_n; END IF;
    v_n := t_count(q_jobs || ' WHERE organisation_id = ' || t_id('org_b'));
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL recruiter sees % requirements of another company', v_n; END IF;
    RAISE NOTICE 'PASS recruiter sees own company''s 2 requirements (incl. draft) and none of another company''s';
    PERFORM t_expect_fail(format(ins_job, t_id('org_a'), t_id('reca'), 'Recruiter post'), 'recruiter posting a requirement (no job_requirement.manage)');
    UPDATE job_requirement SET title = 'renamed' WHERE organisation_id = t_id('org_a');
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL recruiter edited % requirements', v_n; END IF;
    RAISE NOTICE 'PASS recruiter cannot edit requirements (0 rows updated)';
    v_n := t_count(q_apps);
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL recruiter sees % applications, expected 1 (own company''s job)', v_n; END IF;
    RAISE NOTICE 'PASS recruiter sees only the application to own company''s job';

    PERFORM t_as('recb');
    v_n := t_count(q_jobs || ' WHERE organisation_id = ' || t_id('org_a'));
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL Globex recruiter sees % Acme requirements', v_n; END IF;
    RAISE NOTICE 'PASS Globex recruiter sees no Acme requirement, not even the published one';

    PERFORM t_as('old');
    v_n := t_count(q_jobs || ' WHERE title = ''Acme draft''');
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL former recruiter still sees the Acme draft'; END IF;
    RAISE NOTICE 'PASS mapping that ended yesterday gives no access to the company''s drafts';

    PERFORM t_as('emp');
    EXECUTE format(ins_job, t_id('org_a'), t_id('emp'), 'Employer post');
    RAISE NOTICE 'PASS employer posts a requirement for own company';
    PERFORM t_expect_fail(format(ins_job, t_id('org_b'), t_id('emp'), 'Cross post'), 'employer posting for another company');

    PERFORM t_as('cand');
    v_n := t_count(q_jobs);
    IF v_n <> 2 THEN RAISE EXCEPTION 'FAIL candidate sees % requirements, expected the 2 published', v_n; END IF;
    v_n := t_count(q_apps);
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL candidate sees % applications, expected own 1', v_n; END IF;
    RAISE NOTICE 'PASS candidate sees the 2 published requirements (no drafts) and only own application';

    PERFORM t_as('admin');
    v_n := t_count(q_jobs);
    IF v_n <> 5 THEN RAISE EXCEPTION 'FAIL platform admin sees % of 5 requirements', v_n; END IF;
    RAISE NOTICE 'PASS platform admin sees all 5 requirements';

    PERFORM t_expect_fail('UPDATE audit_event SET target_table = ''x''', 'application role updating the audit trail');
    PERFORM t_expect_fail('DELETE FROM application_status_history', 'application role deleting pipeline history');
END $$;
RESET ROLE;

-- ---------------------------------------------------------------------------
-- Gig marketplace rules
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    u_w bigint; u_w2 bigint; w bigint; w2 bigint; w_req bigint; r_open bigint; r_draft bigint; r_overlap bigint;
    a bigint; a2 bigint; s bigint; s2 bigint; v_start timestamptz; v_n bigint;
    ins_req text := $q$INSERT INTO gig_request (requester_user_account_id, requester_organisation_id, title, description, work_mode_id,
        window_start_at, window_end_at, gig_price_type_id, price_amount, price_currency_id, gig_request_status_id)
        VALUES (%s, %s, 'Event photographer', 'Wedding shoot', 1, now() + interval '%s days', now() + interval '%s days', 1, 15000, 1, %s)$q$;
BEGIN
    INSERT INTO user_account (email) VALUES ('ravi.photo@mail.test') RETURNING id INTO u_w;
    INSERT INTO user_account (email) VALUES ('kiran.photo@mail.test') RETURNING id INTO u_w2;

    PERFORM t_as('reca');
    PERFORM t_expect_fail(format($q$INSERT INTO gig_worker_profile (user_account_id, display_name) VALUES (%s, 'Ravi')$q$, u_w),
        'recruiter registering a gig worker');
    PERFORM set_config('app.current_user_id', u_w::text, true);
    INSERT INTO gig_worker_profile (user_account_id, display_name) VALUES (u_w, 'Ravi') RETURNING id INTO w;
    PERFORM set_config('app.current_user_id', u_w2::text, true);
    INSERT INTO gig_worker_profile (user_account_id, display_name) VALUES (u_w2, 'Kiran') RETURNING id INTO w2;
    PERFORM t_as('emp');
    INSERT INTO gig_worker_profile (user_account_id, display_name) VALUES (t_id('emp'), 'Acme owner') RETURNING id INTO w_req;
    RAISE NOTICE 'PASS gig workers register themselves';

    -- Requests
    EXECUTE format(ins_req, t_id('emp'), t_id('org_a'), 10, 11, 2) || ' RETURNING id' INTO r_open;
    EXECUTE format(ins_req, t_id('emp'), 'NULL', 20, 21, 1) || ' RETURNING id' INTO r_draft;
    EXECUTE format(ins_req, t_id('emp'), 'NULL', 10, 12, 2) || ' RETURNING id' INTO r_overlap;
    RAISE NOTICE 'PASS requester posts gigs for own organisation and as an individual';
    PERFORM t_expect_fail(format(ins_req, t_id('emp'), t_id('org_b'), 1, 2, 2), 'gig request for an organisation the requester is not mapped to');
    PERFORM set_config('app.current_user_id', u_w::text, true);
    PERFORM t_expect_fail(format(ins_req, t_id('emp'), 'NULL', 1, 2, 2), 'gig request posted by someone else on the requester''s behalf');
    PERFORM t_expect_fail(format(ins_req, u_w, 'NULL', 5, 4, 2), 'gig window ending before it starts');

    -- Applications
    PERFORM t_as('emp');
    PERFORM t_expect_fail(format('INSERT INTO gig_application (gig_request_id, gig_worker_profile_id) VALUES (%s, %s)', r_open, w),
        'requester creating an application for a worker (bids do not flow both ways)');
    PERFORM t_expect_fail(format('INSERT INTO gig_application (gig_request_id, gig_worker_profile_id) VALUES (%s, %s)', r_open, w_req),
        'requester applying to own gig request');
    INSERT INTO gig_worker_list_entry (owner_user_account_id, gig_worker_profile_id, gig_worker_list_type_id) VALUES (t_id('emp'), w2, 2);
    PERFORM t_expect_fail(format('INSERT INTO gig_worker_list_entry (owner_user_account_id, gig_worker_profile_id, gig_worker_list_type_id) VALUES (%s, %s, 1)', t_id('emp'), w2),
        'worker both blacklisted and favourite for the same requester');
    PERFORM set_config('app.current_user_id', u_w2::text, true);
    PERFORM t_expect_fail(format('INSERT INTO gig_application (gig_request_id, gig_worker_profile_id) VALUES (%s, %s)', r_open, w2),
        'blacklisted worker applying');
    PERFORM set_config('app.current_user_id', u_w::text, true);
    PERFORM t_expect_fail(format('INSERT INTO gig_application (gig_request_id, gig_worker_profile_id) VALUES (%s, %s)', r_draft, w),
        'applying to a draft gig request');
    INSERT INTO gig_application (gig_request_id, gig_worker_profile_id) VALUES (r_open, w) RETURNING id INTO a;
    INSERT INTO gig_application (gig_request_id, gig_worker_profile_id) VALUES (r_overlap, w) RETURNING id INTO a2;
    RAISE NOTICE 'PASS worker applies to two open gigs';
    PERFORM t_expect_fail(format('UPDATE gig_application SET gig_application_status_id = 2 WHERE id = %s', a), 'worker accepting own application');

    -- Assignment needs acceptance; window copied from the request
    PERFORM set_config('app.current_user_id', '1', true);
    PERFORM t_expect_fail(format($q$INSERT INTO gig_assignment (gig_application_id, gig_worker_profile_id, handoff_ref, gig_assignment_status_id)
        VALUES (%s, %s, 'FUL-0', 1)$q$, a, w), 'assignment for an application that is not accepted');
    PERFORM t_as('emp');
    UPDATE gig_application SET gig_application_status_id = 2 WHERE id = a;
    UPDATE gig_application SET gig_application_status_id = 2 WHERE id = a2;
    SELECT count(*) INTO v_n FROM gig_application WHERE id IN (a, a2) AND decided_at IS NOT NULL;
    IF v_n <> 2 THEN RAISE EXCEPTION 'FAIL decided_at not set on acceptance'; END IF;
    RAISE NOTICE 'PASS requester accepts; decided_at recorded';
    PERFORM t_expect_fail(format('UPDATE gig_application SET gig_application_status_id = 3 WHERE id = %s', a), 'changing an already decided application');
    PERFORM t_expect_fail(format($q$INSERT INTO gig_assignment (gig_application_id, gig_worker_profile_id, handoff_ref, gig_assignment_status_id)
        VALUES (%s, %s, 'FUL-X', 1)$q$, a, w2), 'assignment to a worker other than the applicant');
    PERFORM set_config('app.current_user_id', '1', true);
    INSERT INTO gig_assignment (gig_application_id, gig_worker_profile_id, handoff_ref, gig_assignment_status_id)
    VALUES (a, w, 'FUL-1001', 1) RETURNING id, window_start_at INTO s, v_start;
    IF v_start <> (SELECT window_start_at FROM gig_request WHERE id = r_open) THEN RAISE EXCEPTION 'FAIL window not copied'; END IF;
    RAISE NOTICE 'PASS assignment created on handoff with the request''s window copied';
    PERFORM t_expect_fail(format($q$INSERT INTO gig_assignment (gig_application_id, gig_worker_profile_id, handoff_ref, gig_assignment_status_id)
        VALUES (%s, %s, 'FUL-1002', 1)$q$, a2, w), 'overlapping gig windows for the same worker (B35)');
    UPDATE gig_assignment SET gig_assignment_status_id = 4 WHERE id = s;
    INSERT INTO gig_assignment (gig_application_id, gig_worker_profile_id, handoff_ref, gig_assignment_status_id)
    VALUES (a2, w, 'FUL-1002', 1) RETURNING id INTO s2;
    RAISE NOTICE 'PASS overlapping window accepted once the first assignment is cancelled';

    -- Ratings
    PERFORM t_as('emp');
    PERFORM t_expect_fail(format('INSERT INTO gig_rating (gig_assignment_id, rated_by_user_account_id, rating_score) VALUES (%s, %s, 5)', s2, t_id('emp')),
        'rating a gig that is not completed');
    PERFORM set_config('app.current_user_id', '1', true);
    PERFORM t_expect_fail(format('UPDATE gig_assignment SET gig_assignment_status_id = 3 WHERE id = %s', s2), 'completed without completed_at');
    UPDATE gig_assignment SET gig_assignment_status_id = 3, completed_at = now() WHERE id = s2;
    PERFORM set_config('app.current_user_id', u_w::text, true);
    PERFORM t_expect_fail(format('INSERT INTO gig_rating (gig_assignment_id, rated_by_user_account_id, rating_score) VALUES (%s, %s, 5)', s2, u_w),
        'worker rating own gig');
    PERFORM t_as('emp');
    PERFORM t_expect_fail(format('INSERT INTO gig_rating (gig_assignment_id, rated_by_user_account_id, rating_score) VALUES (%s, %s, 6)', s2, t_id('emp')),
        'rating outside 1..5');
    INSERT INTO gig_rating (gig_assignment_id, rated_by_user_account_id, rating_score, review_text) VALUES (s2, t_id('emp'), 5, 'On time, great photos');
    RAISE NOTICE 'PASS requester rates the completed gig';

    -- Earnings are append-only and idempotent
    PERFORM set_config('app.current_user_id', '1', true);
    INSERT INTO gig_earning_snapshot (gig_assignment_id, gig_earning_type_id, earning_amount, earning_currency_id, external_event_ref, reported_at)
    VALUES (s2, 2, 15000, 1, 'FUL-EVT-1', now());
    PERFORM t_expect_fail(format($q$INSERT INTO gig_earning_snapshot (gig_assignment_id, gig_earning_type_id, earning_amount, earning_currency_id,
        external_event_ref, reported_at) VALUES (%s, 2, 15000, 1, 'FUL-EVT-1', now())$q$, s2), 'redelivered earnings event');
    PERFORM t_expect_fail('UPDATE gig_earning_snapshot SET earning_amount = 1', 'editing reported earnings');

    -- Gig project on the profile has exactly one owner
    PERFORM t_expect_fail(format($q$INSERT INTO profile_project (project_kind_id, candidate_profile_id, gig_worker_profile_id, title, role_name, start_date)
        SELECT 2, (SELECT min(id) FROM candidate_profile), %s, 'Shoot', 'Photographer', current_date$q$, w), 'project owned by both a candidate and a gig worker');
    INSERT INTO profile_project (project_kind_id, gig_worker_profile_id, title, role_name, start_date) VALUES (2, w, 'Wedding shoot', 'Photographer', current_date);
    RAISE NOTICE 'PASS gig project recorded on the gig worker profile';
END $$;

DO $$ BEGIN RAISE NOTICE 'MILESTONE 10 CHECKS PASSED'; END $$;
ROLLBACK;
