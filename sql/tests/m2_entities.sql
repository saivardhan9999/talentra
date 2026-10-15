-- Milestone 2 (B4-B7): every agreed entity exists, and every table in the schema is owned by a module.
\set ON_ERROR_STOP on
CREATE TEMP TABLE expected_entity (module text, table_name text);
INSERT INTO expected_entity VALUES
 -- Foundation shells (owned by Phase 2 modules)
 ('administration','user_account'), ('organisation','organisation'),
 -- Master data
 ('master_data','language'), ('master_data','ui_label_key'), ('master_data','ui_label_translation'),
 ('master_data','currency'), ('master_data','country'), ('master_data','state'), ('master_data','city'),
 ('master_data','industry'), ('master_data','job_role'), ('master_data','skill'), ('master_data','skill_alias'),
 ('master_data','qualification'), ('master_data','field_of_study'), ('master_data','institution'),
 -- Profile
 ('profile','candidate_profile'), ('profile','candidate_email'), ('profile','candidate_phone'),
 ('profile','candidate_address'), ('profile','candidate_social_link'), ('profile','candidate_education'),
 ('profile','candidate_work_experience'), ('profile','candidate_skill'), ('profile','candidate_language'),
 ('profile','candidate_certification'), ('profile','candidate_preferred_location'),
 ('profile','candidate_preferred_job_role'), ('profile','resume_template'), ('profile','resume'),
 ('profile','resume_version'), ('profile','profile_project'), ('profile','profile_project_skill'),
 ('profile','assessment'), ('profile','candidate_assessment_result'), ('profile','course'),
 ('profile','course_enrolment'), ('profile','candidate_profile_section_score'),
 ('profile','profile_view_event'), ('profile','candidate_activity_log'),
 ('profile','talent_list'), ('profile','talent_list_entry'), ('profile','referral'),
 -- Jobs and Applications
 ('jobs_applications','job_requirement'), ('jobs_applications','job_requirement_location'),
 ('jobs_applications','job_requirement_skill'), ('jobs_applications','job_requirement_qualification'),
 ('jobs_applications','job_position'), ('jobs_applications','questionnaire'),
 ('jobs_applications','questionnaire_question'), ('jobs_applications','questionnaire_question_option'),
 ('jobs_applications','job_requirement_questionnaire'), ('jobs_applications','application_status_transition'),
 ('jobs_applications','application'), ('jobs_applications','application_status_history'),
 ('jobs_applications','application_answer'), ('jobs_applications','interview'), ('jobs_applications','offer'),
 ('jobs_applications','placement'), ('jobs_applications','saved_job'), ('jobs_applications','job_search_event');

-- Lookup tables are owned by Master data.
INSERT INTO expected_entity
SELECT 'master_data (lookup)', c.relname FROM pg_class c
JOIN pg_description d ON d.objoid = c.oid AND d.objsubid = 0 AND d.description LIKE 'lookup;%';

DO $$
DECLARE bad text; n int;
BEGIN
    SELECT string_agg(table_name, ', ') INTO bad FROM expected_entity e
    WHERE to_regclass(e.table_name) IS NULL;
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL expected entity missing: %', bad; END IF;

    SELECT string_agg(c.relname, ', ') INTO bad FROM pg_class c JOIN pg_namespace s ON s.oid = c.relnamespace
    WHERE s.nspname = 'public' AND c.relkind IN ('r','p') AND NOT c.relispartition
      AND c.relname NOT IN (SELECT table_name FROM expected_entity);
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL table without an owning module: %', bad; END IF;

    FOR bad, n IN SELECT module, count(*) FROM expected_entity GROUP BY module ORDER BY module LOOP
        RAISE NOTICE 'PASS % : % entities present', rpad(bad, 22), n;
    END LOOP;
    -- Gig entities must NOT be in the core model (decision D3)
    IF to_regclass('gig_request') IS NOT NULL THEN RAISE EXCEPTION 'FAIL gig tables found in Phase 1'; END IF;
    RAISE NOTICE 'PASS no orphan tables; gig entities kept out of the core model (D3)';
END $$;
