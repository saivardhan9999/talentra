-- Milestone 6 (B20-B23): keys and constraints enforce the business rules (behavioural tests, rolled back).
\set ON_ERROR_STOP on
CREATE OR REPLACE FUNCTION pg_temp.expect_fail(p_sql text, p_label text) RETURNS void
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

BEGIN;
SET LOCAL app.current_user_id = '1';

DO $$
DECLARE
    v_cand_user bigint; v_recr_user bigint; v_org bigint; v_cand bigint; v_job bigint;
    v_app bigint; v_pos bigint; v_offer bigint; v_n int;
    st_applied bigint; st_short bigint; st_sched bigint; st_int bigint; st_off bigint; st_acc bigint; st_joined bigint;
    v_label text;
BEGIN
    SELECT id INTO st_applied FROM application_status WHERE code = 'applied';
    SELECT id INTO st_short   FROM application_status WHERE code = 'shortlisted';
    SELECT id INTO st_sched   FROM application_status WHERE code = 'interview_scheduled';
    SELECT id INTO st_int     FROM application_status WHERE code = 'interviewed';
    SELECT id INTO st_off     FROM application_status WHERE code = 'offered';
    SELECT id INTO st_acc     FROM application_status WHERE code = 'offer_accepted';
    SELECT id INTO st_joined  FROM application_status WHERE code = 'joined';

    INSERT INTO user_account (email) VALUES ('asha.k@example.com') RETURNING id INTO v_cand_user;
    INSERT INTO user_account (email) VALUES ('recruiter@acme.example') RETURNING id INTO v_recr_user;
    INSERT INTO organisation (legal_name) VALUES ('Acme Staffing Pvt Ltd') RETURNING id INTO v_org;

    PERFORM pg_temp.expect_fail($q$INSERT INTO user_account (email) VALUES ('Mixed@Case.com')$q$, 'uppercase email');

    -- Recruiter tries to register a candidate on the candidate's behalf
    PERFORM set_config('app.current_user_id', v_recr_user::text, true);
    PERFORM pg_temp.expect_fail(format(
        $q$INSERT INTO candidate_profile (user_account_id, full_name, profile_visibility_id) VALUES (%s, 'Asha K', 1)$q$, v_cand_user),
        'recruiter registering a candidate');

    -- Candidate self-registers (multilingual name)
    PERFORM set_config('app.current_user_id', v_cand_user::text, true);
    INSERT INTO candidate_profile (user_account_id, full_name, given_name, family_name, profile_visibility_id)
    VALUES (v_cand_user, 'ஆஷா குமார்', 'ஆஷா', 'குமார்', 1) RETURNING id INTO v_cand;
    RAISE NOTICE 'PASS candidate self-registration with Tamil-script name (id %)', v_cand;

    PERFORM pg_temp.expect_fail(format(
        $q$UPDATE candidate_profile SET current_salary_disclosure_status_id = 1 WHERE id = %s$q$, v_cand),
        'salary marked disclosed without amount');
    PERFORM pg_temp.expect_fail(format(
        $q$UPDATE candidate_profile SET current_salary_amount = 0 WHERE id = %s$q$, v_cand),
        'zero salary used as "not disclosed" sentinel');
    UPDATE candidate_profile SET current_salary_disclosure_status_id = 1, current_salary_amount = 1200000,
           current_salary_currency_id = 1, current_salary_period_id = 1 WHERE id = v_cand;
    RAISE NOTICE 'PASS disclosed salary with currency accepted';

    PERFORM pg_temp.expect_fail(format(
        $q$INSERT INTO candidate_phone (candidate_profile_id, phone_e164, country_id, phone_type_id) VALUES (%s, '98400 12345', 1, 1)$q$, v_cand),
        'phone not in E.164');
    INSERT INTO candidate_phone (candidate_profile_id, phone_e164, country_id, phone_type_id, is_primary) VALUES (v_cand, '+919840012345', 1, 1, true);
    PERFORM pg_temp.expect_fail(format(
        $q$INSERT INTO candidate_phone (candidate_profile_id, phone_e164, country_id, phone_type_id, is_primary) VALUES (%s, '+919840099999', 1, 1, true)$q$, v_cand),
        'second primary phone');
    PERFORM pg_temp.expect_fail(format(
        $q$INSERT INTO candidate_work_experience (candidate_profile_id, employer_name, job_title, employment_type_id, start_date, end_date)
           VALUES (%s, 'Foo', 'Dev', 1, '2024-05-01', '2023-01-01')$q$, v_cand),
        'work experience end before start');
    PERFORM pg_temp.expect_fail(format(
        $q$INSERT INTO candidate_education (candidate_profile_id, qualification_id) VALUES (%s, 1)$q$, v_cand),
        'education without institution (and unknown qualification)');

    -- Job requirement rules
    PERFORM set_config('app.current_user_id', v_recr_user::text, true);
    PERFORM pg_temp.expect_fail(format(
        $q$INSERT INTO job_requirement (organisation_id, posted_by_user_account_id, title, description, job_category_id, employment_type_id,
           work_mode_id, job_requirement_status_id, publish_state_id) VALUES (%s, %s, 'Delivery gig', 'x', 1, 1, 1, 1, 1)$q$, v_org, v_recr_user),
        'gig category in job_requirement');
    PERFORM pg_temp.expect_fail(format(
        $q$INSERT INTO job_requirement (organisation_id, posted_by_user_account_id, title, description, job_category_id, employment_type_id,
           work_mode_id, job_requirement_status_id, publish_state_id, salary_disclosure_status_id, salary_min_amount, salary_max_amount,
           salary_currency_id, salary_period_id) VALUES (%s, %s, 'Java Dev', 'x', 4, 1, 1, 1, 1, 1, 900000, 500000, 1, 1)$q$, v_org, v_recr_user),
        'salary min greater than max');
    PERFORM pg_temp.expect_fail(format(
        $q$INSERT INTO job_requirement (organisation_id, posted_by_user_account_id, title, description, job_category_id, employment_type_id,
           work_mode_id, job_requirement_status_id, publish_state_id, consultant_fee_pct) VALUES (%s, %s, 'Java Dev', 'x', 4, 1, 1, 1, 1, 8.5)$q$, v_org, v_recr_user),
        'consultant fee on a job closed to consultants');
    INSERT INTO job_requirement (organisation_id, posted_by_user_account_id, title, description, job_category_id, employment_type_id,
           work_mode_id, job_requirement_status_id, publish_state_id, number_of_positions, published_at, expires_at)
    VALUES (v_org, v_recr_user, 'Java Developer', 'Spring Boot microservices in Chennai', 4, 1, 3, 3, 3, 1, now(), now() + interval '30 days')
    RETURNING id INTO v_job;
    INSERT INTO job_position (job_requirement_id, position_number, job_position_status_id) VALUES (v_job, 1, 1) RETURNING id INTO v_pos;
    SELECT count(*) INTO v_n FROM job_requirement WHERE search_document @@ to_tsquery('simple', 'spring & chennai');
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL full-text search'; END IF;
    RAISE NOTICE 'PASS job requirement created and found by full-text search';

    -- Application pipeline
    PERFORM set_config('app.current_user_id', v_cand_user::text, true);
    PERFORM pg_temp.expect_fail(format(
        $q$INSERT INTO application (job_requirement_id, candidate_profile_id, application_status_id, application_source_id) VALUES (%s, %s, %s, 1)$q$,
        v_job, v_cand, st_joined), 'application created directly as joined');
    INSERT INTO application (job_requirement_id, candidate_profile_id, application_status_id, application_source_id)
    VALUES (v_job, v_cand, st_applied, 1) RETURNING id INTO v_app;
    PERFORM pg_temp.expect_fail(format(
        $q$INSERT INTO application (job_requirement_id, candidate_profile_id, application_status_id, application_source_id) VALUES (%s, %s, %s, 1)$q$,
        v_job, v_cand, st_applied), 'duplicate application to the same job');

    PERFORM set_config('app.current_user_id', v_recr_user::text, true);
    PERFORM pg_temp.expect_fail(format($q$UPDATE application SET application_status_id = %s WHERE id = %s$q$, st_joined, v_app),
        'skip from applied straight to joined');
    UPDATE application SET application_status_id = st_short WHERE id = v_app;
    UPDATE application SET application_status_id = st_sched WHERE id = v_app;
    UPDATE application SET application_status_id = st_int   WHERE id = v_app;
    UPDATE application SET application_status_id = st_off   WHERE id = v_app;
    INSERT INTO offer (application_id, offer_status_id, salary_amount, salary_currency_id, salary_period_id, proposed_joining_date, valid_until)
    VALUES (v_app, 1, 1500000, 1, 1, current_date + 30, current_date + 7) RETURNING id INTO v_offer;
    UPDATE application SET application_status_id = st_acc    WHERE id = v_app;
    UPDATE application SET application_status_id = st_joined WHERE id = v_app;
    INSERT INTO placement (application_id, job_position_id, job_requirement_id, offer_id, joined_on)
    VALUES (v_app, v_pos, v_job, v_offer, current_date + 30);
    SELECT count(*) INTO v_n FROM application_status_history WHERE application_id = v_app;
    IF v_n <> 7 THEN RAISE EXCEPTION 'FAIL expected 7 history rows, got %', v_n; END IF;
    RAISE NOTICE 'PASS full pipeline applied -> joined, 7 history rows written by trigger';
    PERFORM pg_temp.expect_fail(format($q$UPDATE application SET application_status_id = %s WHERE id = %s$q$, st_short, v_app),
        'move out of terminal status joined');

    -- Append-only
    PERFORM pg_temp.expect_fail('UPDATE application_status_history SET status_note = ''x''', 'update of append-only history');
    PERFORM pg_temp.expect_fail('DELETE FROM application_status_history', 'delete of append-only history');
    INSERT INTO profile_view_event (candidate_profile_id, viewer_user_account_id, viewer_organisation_id, view_context_id, job_requirement_id)
    VALUES (v_cand, v_recr_user, v_org, 2, v_job);
    PERFORM pg_temp.expect_fail('DELETE FROM profile_view_event', 'delete of profile view history');

    -- Talent list must belong to the job's organisation
    INSERT INTO organisation (legal_name) VALUES ('Rival Corp') RETURNING id INTO v_n;
    PERFORM pg_temp.expect_fail(format(
        $q$INSERT INTO talent_list (owner_user_account_id, organisation_id, talent_list_type_id, job_requirement_id, name)
           VALUES (%s, %s, 1, %s, 'cross-org list')$q$, v_recr_user, v_n, v_job),
        'talent list for another organisation''s job');
    INSERT INTO talent_list (owner_user_account_id, organisation_id, talent_list_type_id, job_requirement_id, name)
    VALUES (v_recr_user, v_org, 1, v_job, 'Java shortlist');
    RAISE NOTICE 'PASS talent list for own organisation''s job accepted';

    -- Audit columns
    PERFORM set_config('app.current_user_id', '', true);
    PERFORM pg_temp.expect_fail(format($q$UPDATE job_requirement SET title = 'x' WHERE id = %s$q$, v_job), 'update without actor context');
    PERFORM pg_temp.expect_fail($q$INSERT INTO organisation (legal_name) VALUES ('NoActor Ltd')$q$, 'insert without actor context');

    -- Translation fallback
    SELECT fn_ui_label(s.ui_label_key_id, (SELECT id FROM language WHERE code = 'ta')) INTO v_label FROM application_status s WHERE code = 'joined';
    IF v_label <> 'Joined' THEN RAISE EXCEPTION 'FAIL fallback returned %', v_label; END IF;
    SELECT fn_ui_label(s.ui_label_key_id, (SELECT id FROM language WHERE code = 'ta')) INTO v_label FROM application_status s WHERE code = 'rejected';
    IF v_label <> 'நிராகரிக்கப்பட்டது' THEN RAISE EXCEPTION 'FAIL translation returned %', v_label; END IF;
    RAISE NOTICE 'PASS UI label translation and fallback to default language';

    -- System lookup codes are immutable
    PERFORM set_config('app.current_user_id', '1', true);
    PERFORM pg_temp.expect_fail($q$UPDATE salary_disclosure_status SET code = 'shown' WHERE id = 1$q$, 'renaming a system lookup code');

    -- ---- Constraints listed in the design but not yet exercised above ----
    PERFORM set_config('app.current_user_id', v_cand_user::text, true);
    INSERT INTO candidate_email (candidate_profile_id, email, is_primary) VALUES (v_cand, 'asha.k@example.com', true);
    PERFORM pg_temp.expect_fail(format(
        $q$INSERT INTO candidate_email (candidate_profile_id, email, is_primary) VALUES (%s, 'asha.alt@example.com', true)$q$, v_cand),
        'second primary email');
    PERFORM pg_temp.expect_fail(format(
        $q$UPDATE candidate_profile SET is_fresher = true, total_experience_months = 24 WHERE id = %s$q$, v_cand),
        'fresher with 24 months experience');

    PERFORM set_config('app.current_user_id', v_recr_user::text, true);
    PERFORM pg_temp.expect_fail(format(
        $q$UPDATE job_requirement SET expires_at = published_at - interval '1 day' WHERE id = %s$q$, v_job),
        'publish window expiring before publish');
    PERFORM pg_temp.expect_fail(format(
        $q$UPDATE job_requirement SET min_experience_months = 60, max_experience_months = 24 WHERE id = %s$q$, v_job),
        'experience min greater than max');
    PERFORM pg_temp.expect_fail(format(
        $q$UPDATE job_requirement SET number_of_positions = 0 WHERE id = %s$q$, v_job),
        'zero positions');

    -- Placement must fill a slot of the SAME job: create a second job + slot and try to cross them
    INSERT INTO job_requirement (organisation_id, posted_by_user_account_id, title, description, job_category_id, employment_type_id,
           work_mode_id, job_requirement_status_id, publish_state_id)
    VALUES (v_org, v_recr_user, 'QA Engineer', 'Manual and automation testing', 4, 1, 1, 3, 3) RETURNING id INTO v_n;
    INSERT INTO job_position (job_requirement_id, position_number, job_position_status_id) VALUES (v_n, 1, 1) RETURNING id INTO v_pos;
    -- Uses a fresh candidate's application so only the cross-job rule can fire.
    DECLARE v_u2 bigint; v_c2 bigint; v_a2 bigint; v_o2 bigint;
    BEGIN
        INSERT INTO user_account (email) VALUES ('ravi.s@example.com') RETURNING id INTO v_u2;
        PERFORM set_config('app.current_user_id', v_u2::text, true);
        INSERT INTO candidate_profile (user_account_id, full_name, profile_visibility_id) VALUES (v_u2, 'Ravi S', 1) RETURNING id INTO v_c2;
        INSERT INTO application (job_requirement_id, candidate_profile_id, application_status_id, application_source_id)
        VALUES (v_job, v_c2, st_applied, 1) RETURNING id INTO v_a2;
        PERFORM set_config('app.current_user_id', v_recr_user::text, true);
        INSERT INTO offer (application_id, offer_status_id, salary_amount, salary_currency_id, salary_period_id, proposed_joining_date, valid_until)
        VALUES (v_a2, 1, 1400000, 1, 1, current_date + 30, current_date + 7) RETURNING id INTO v_o2;
        PERFORM pg_temp.expect_fail(format(
            $q$INSERT INTO placement (application_id, job_position_id, job_requirement_id, offer_id, joined_on) VALUES (%s, %s, %s, %s, current_date)$q$,
            v_a2, v_pos, v_job, v_o2), 'placement into a slot of a different job (slot from QA job, application for Java job)');
    END;
    PERFORM pg_temp.expect_fail(format(
        $q$INSERT INTO placement (application_id, job_position_id, job_requirement_id, offer_id, joined_on)
           SELECT %s, id, %s, %s, current_date FROM job_position WHERE job_requirement_id = %s$q$, v_app, v_job, v_offer, v_job),
        'second placement for the same application');

    -- Talent list entries: one active entry per candidate per list, never deleted, removal keeps history
    INSERT INTO talent_list_entry (talent_list_id, candidate_profile_id, added_by_user_account_id)
    SELECT id, v_cand, v_recr_user FROM talent_list WHERE name = 'Java shortlist';
    PERFORM pg_temp.expect_fail(format(
        $q$INSERT INTO talent_list_entry (talent_list_id, candidate_profile_id, added_by_user_account_id)
           SELECT id, %s, %s FROM talent_list WHERE name = 'Java shortlist'$q$, v_cand, v_recr_user),
        'second active entry for the same candidate on a list');
    PERFORM pg_temp.expect_fail('DELETE FROM talent_list_entry', 'delete of a talent list entry');
    UPDATE talent_list_entry SET removed_at = now(), removed_by_user_account_id = v_recr_user WHERE candidate_profile_id = v_cand;
    INSERT INTO talent_list_entry (talent_list_id, candidate_profile_id, added_by_user_account_id)
    SELECT id, v_cand, v_recr_user FROM talent_list WHERE name = 'Java shortlist';
    SELECT count(*) INTO v_n FROM talent_list_entry WHERE candidate_profile_id = v_cand;
    IF v_n <> 2 THEN RAISE EXCEPTION 'FAIL expected 2 entries (history), got %', v_n; END IF;
    RAISE NOTICE 'PASS removed then re-added candidate keeps both entries as shortlist history';

    -- Questionnaire answers: exactly one value per answer row
    INSERT INTO questionnaire (organisation_id, title, language_id) VALUES (v_org, 'Screening', 1) RETURNING id INTO v_n;
    INSERT INTO questionnaire_question (questionnaire_id, question_order, question_text, question_type_id)
    VALUES (v_n, 1, 'Years of Java experience?', 5) RETURNING id INTO v_n;
    PERFORM pg_temp.expect_fail(format(
        $q$INSERT INTO application_answer (application_id, questionnaire_question_id, answer_text, answer_number) VALUES (%s, %s, 'five', 5)$q$,
        v_app, v_n), 'answer with two values');
    PERFORM pg_temp.expect_fail(format(
        $q$INSERT INTO application_answer (application_id, questionnaire_question_id) VALUES (%s, %s)$q$, v_app, v_n),
        'answer with no value');
    INSERT INTO application_answer (application_id, questionnaire_question_id, answer_number) VALUES (v_app, v_n, 5);
    RAISE NOTICE 'PASS answer with exactly one value accepted';

    -- Interview time range and rating
    PERFORM pg_temp.expect_fail(format(
        $q$INSERT INTO interview (application_id, round_number, interview_round_type_id, interview_mode_id, scheduled_start_at,
           scheduled_end_at, display_time_zone) VALUES (%s, 1, 2, 2, now(), now() - interval '1 hour', 'Asia/Kolkata')$q$, v_app),
        'interview ending before it starts');

    -- Master data rules
    PERFORM set_config('app.current_user_id', '1', true);
    PERFORM pg_temp.expect_fail($q$UPDATE language SET is_default = true WHERE code = 'hi'$q$, 'second default UI language');
    PERFORM pg_temp.expect_fail($q$UPDATE city SET latitude = 95 WHERE id = 1$q$, 'latitude out of range');
    PERFORM pg_temp.expect_fail($q$UPDATE city SET latitude = NULL WHERE id = 1$q$, 'half a coordinate pair');
END $$;
ROLLBACK;

\echo 'MILESTONE 6 CHECKS PASSED'
