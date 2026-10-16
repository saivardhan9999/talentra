-- Agreed entity list for every module built so far (included by m2 and m7).
-- A new table must be added here with its owning module, or the orphan check fails.
CREATE TEMP TABLE expected_entity (phase int, module text, table_name text);
INSERT INTO expected_entity VALUES
 -- Foundation shells: created in Phase 1, owned and extended by Phase 2 modules
 (1,'administration','user_account'), (1,'organisation','organisation'),
 -- Master data
 (1,'master_data','language'), (1,'master_data','ui_label_key'), (1,'master_data','ui_label_translation'),
 (1,'master_data','currency'), (1,'master_data','country'), (1,'master_data','state'), (1,'master_data','city'),
 (1,'master_data','industry'), (1,'master_data','job_role'), (1,'master_data','skill'), (1,'master_data','skill_alias'),
 (1,'master_data','qualification'), (1,'master_data','field_of_study'), (1,'master_data','institution'),
 -- Profile
 (1,'profile','candidate_profile'), (1,'profile','candidate_email'), (1,'profile','candidate_phone'),
 (1,'profile','candidate_address'), (1,'profile','candidate_social_link'), (1,'profile','candidate_education'),
 (1,'profile','candidate_work_experience'), (1,'profile','candidate_skill'), (1,'profile','candidate_language'),
 (1,'profile','candidate_certification'), (1,'profile','candidate_preferred_location'),
 (1,'profile','candidate_preferred_job_role'), (1,'profile','resume_template'), (1,'profile','resume'),
 (1,'profile','resume_version'), (1,'profile','profile_project'), (1,'profile','profile_project_skill'),
 (1,'profile','assessment'), (1,'profile','candidate_assessment_result'), (1,'profile','course'),
 (1,'profile','course_enrolment'), (1,'profile','candidate_profile_section_score'),
 (1,'profile','profile_view_event'), (1,'profile','candidate_activity_log'),
 (1,'profile','talent_list'), (1,'profile','talent_list_entry'), (1,'profile','referral'),
 -- Jobs and Applications
 (1,'jobs_applications','job_requirement'), (1,'jobs_applications','job_requirement_location'),
 (1,'jobs_applications','job_requirement_skill'), (1,'jobs_applications','job_requirement_qualification'),
 (1,'jobs_applications','job_position'), (1,'jobs_applications','questionnaire'),
 (1,'jobs_applications','questionnaire_question'), (1,'jobs_applications','questionnaire_question_option'),
 (1,'jobs_applications','job_requirement_questionnaire'), (1,'jobs_applications','application_status_transition'),
 (1,'jobs_applications','application'), (1,'jobs_applications','application_status_history'),
 (1,'jobs_applications','application_answer'), (1,'jobs_applications','interview'), (1,'jobs_applications','offer'),
 (1,'jobs_applications','placement'), (1,'jobs_applications','saved_job'), (1,'jobs_applications','job_search_event'),
 -- Administration (Member A)
 (2,'administration','role'), (2,'administration','permission'),
 (2,'administration','role_permission'), (2,'administration','user_account_role'), (2,'administration','audit_event'),
 -- Organisation and account (Member B)
 (2,'organisation','organisation_location'),
 (2,'organisation','organisation_registration_identifier'), (2,'organisation','organisation_member'),
 -- Gig marketplace (Member C)
 (2,'gig','gig_worker_profile'), (2,'gig','gig_worker_service'), (2,'gig','gig_worker_availability'),
 (2,'gig','gig_request'), (2,'gig','gig_request_skill'), (2,'gig','gig_application'), (2,'gig','gig_assignment'),
 (2,'gig','gig_earning_snapshot'), (2,'gig','gig_rating'), (2,'gig','gig_worker_list_entry');

-- Lookup tables are owned by Master data, whichever phase added them.
INSERT INTO expected_entity
SELECT 0, 'master_data (lookup)', c.relname FROM pg_class c
JOIN pg_description d ON d.objoid = c.oid AND d.objsubid = 0 AND d.description LIKE 'lookup;%';
