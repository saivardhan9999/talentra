-- Milestone 3 (B8-B11): key relationships exist with the stated cardinality and delete rule,
-- and no FK relies on an implicit (unstated) update/delete rule.
\set ON_ERROR_STOP on
CREATE TEMP TABLE expected_fk (child text, cols text, parent text, on_delete char, one_to_one boolean);
-- on_delete: r = RESTRICT, c = CASCADE, n = SET NULL
INSERT INTO expected_fk VALUES
 ('candidate_profile','user_account_id','user_account','r', true),
 ('candidate_email','candidate_profile_id','candidate_profile','c', false),
 ('candidate_phone','candidate_profile_id','candidate_profile','c', false),
 ('candidate_address','candidate_profile_id','candidate_profile','c', false),
 ('candidate_education','candidate_profile_id','candidate_profile','c', false),
 ('candidate_work_experience','candidate_profile_id','candidate_profile','c', false),
 ('candidate_skill','candidate_profile_id','candidate_profile','c', false),
 ('candidate_skill','skill_id','skill','r', false),
 ('candidate_language','candidate_profile_id','candidate_profile','c', false),
 ('resume','candidate_profile_id','candidate_profile','c', false),
 ('resume_version','resume_id','resume','c', false),
 ('profile_project','candidate_profile_id','candidate_profile','c', false),
 ('candidate_assessment_result','candidate_profile_id','candidate_profile','c', false),
 ('course_enrolment','candidate_profile_id','candidate_profile','c', false),
 ('profile_view_event','candidate_profile_id','candidate_profile','r', false),
 ('candidate_activity_log','candidate_profile_id','candidate_profile','r', false),
 ('job_requirement','organisation_id','organisation','r', false),
 ('job_requirement_location','job_requirement_id','job_requirement','c', false),
 ('job_requirement_skill','job_requirement_id','job_requirement','c', false),
 ('job_position','job_requirement_id','job_requirement','c', false),
 ('questionnaire_question','questionnaire_id','questionnaire','c', false),
 ('application','job_requirement_id','job_requirement','r', false),
 ('application','candidate_profile_id','candidate_profile','r', false),
 ('application','resume_version_id','resume_version','r', false),
 ('application_status_history','application_id','application','r', false),
 ('application_answer','application_id','application','c', false),
 ('interview','application_id','application','r', false),
 ('offer','application_id','application','r', false),
 ('placement','application_id,job_requirement_id','application','r', true),
 ('placement','job_position_id,job_requirement_id','job_position','r', true),
 ('talent_list','job_requirement_id,organisation_id','job_requirement','r', false),
 ('talent_list_entry','talent_list_id','talent_list','r', false),
 ('talent_list_entry','candidate_profile_id','candidate_profile','r', false);

\ir check_expected_fk.sql
