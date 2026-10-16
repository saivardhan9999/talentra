-- =============================================================================
-- Talentra seed :: 08_supplementary.sql  (B60-B62: the rest of the profile, jobs and gig tables)
-- Distributions:
--   profile extras  addresses 40%, LinkedIn 15% / GitHub 5%, certifications 10%, preferred roles 50%,
--                   section completion scores for 20%, template-built resume versions for 5% of resumes
--   assessments     20 assessments; 10% of candidates take 1-2 attempts (85% completed, scored)
--   courses         30 courses; 8% of candidates enrolled (40% completed)
--   questionnaires  2% of organisations screen with a 3-question questionnaire on 5% of their open
--                   requirements; every application to those requirements answers all three
--   joins           a qualification on 40% of requirements, skills on gig requests and projects
-- =============================================================================
\set ON_ERROR_STOP on
SET app.current_user_id = '1';
SET synchronous_commit = off;

-- resume templates (label keys translated) and template-built versions
DO $$
DECLARE r record; k bigint;
BEGIN
    FOR r IN SELECT * FROM (VALUES ('classic','Classic'),('modern','Modern'),('fresher','Fresher one-page')) v(code, label) LOOP
        k := NULL;
        CALL seed_label('resume_template.' || r.code, 'profile', k);
        CALL seed_translation('resume_template.' || r.code, 'en', r.label);
        INSERT INTO resume_template (code, ui_label_key_id, layout_definition)
        VALUES (r.code, k, jsonb_build_object('sections', ARRAY['summary','experience','education','skills'], 'columns', CASE WHEN r.code = 'modern' THEN 2 ELSE 1 END));
    END LOOP;
END $$;
INSERT INTO resume_version (resume_id, version_number, resume_template_id, body_text, body_language_id)
SELECT r.id, 3, (SELECT id FROM resume_template ORDER BY id OFFSET (r.id % 3) LIMIT 1),
       p.full_name || E'\n' || coalesce(p.headline, '') || E'\nExperience: ' || coalesce(p.total_experience_months, 0) / 12 || ' years',
       p.name_language_id
FROM resume r JOIN candidate_profile p ON p.id = r.candidate_profile_id WHERE seed.r(r.id, 301) < 0.05;

INSERT INTO candidate_address (candidate_profile_id, address_type_id, address_line_1, city_id, postal_code, latitude, longitude, coordinate_source_id)
SELECT c.profile_id, 1, (1 + c.g % 400) || ', ' || seed.pick(ARRAY['Gandhi Nagar','Anna Nagar','Rajaji Street','Sector 15','Indira Colony','Main Road'], c.g, 302),
       c.city_id, lpad((110001 + floor(seed.r(c.g, 303) * 750000))::int::text, 6, '0'),
       round(ci.latitude + (seed.r(c.g, 304) - 0.5) * 0.1, 6), round(ci.longitude + (seed.r(c.g, 305) - 0.5) * 0.1, 6), 2
FROM seed.cand_p c JOIN city ci ON ci.id = c.city_id WHERE seed.r(c.g, 306) < 0.40 AND ci.latitude IS NOT NULL;
INSERT INTO candidate_social_link (candidate_profile_id, social_link_type_id, url)
SELECT c.profile_id, t, CASE t WHEN 1 THEN 'https://www.linkedin.com/in/' ELSE 'https://github.com/' END || split_part(c.email, '@', 1)
FROM seed.cand_p c CROSS JOIN (VALUES (1), (2)) v(t)
WHERE (t = 1 AND seed.r(c.g, 307) < 0.15) OR (t = 2 AND seed.r(c.g, 308) < 0.05);
INSERT INTO candidate_certification (candidate_profile_id, certification_name, issuing_body, credential_ref, issued_on, expires_on)
SELECT c.profile_id, x.name, x.body, 'CERT-' || c.g, (now() - interval '700 days' * seed.r(c.g, 309))::date,
       CASE WHEN x.expires THEN (now() + interval '400 days' * seed.r(c.g, 310))::date END
FROM seed.cand_p c
CROSS JOIN LATERAL (SELECT * FROM (VALUES ('AWS Certified Cloud Practitioner','Amazon Web Services',true),('Tally Prime Certified','Tally Education',false),
                                          ('Google Digital Marketing','Google',false),('NSDC Electrician (Level 4)','National Skill Development Corporation',false),
                                          ('First Aid and CPR','Indian Red Cross Society',true)) v(name, body, expires)
                    OFFSET floor(seed.r(c.g, 311) * 5)::int LIMIT 1) x
WHERE seed.r(c.g, 312) < 0.10;
INSERT INTO candidate_preferred_job_role (candidate_profile_id, job_role_id, employment_type_id, work_mode_id)
SELECT DISTINCT ON (c.profile_id, jr.id) c.profile_id, jr.id, 1, CASE WHEN seed.r(c.g * 2 + k, 313) < 0.7 THEN 1 ELSE 3 END
FROM seed.cand_p c CROSS JOIN generate_series(1, 2) k
JOIN seed.role_rank jr ON jr.rank = 1 + floor(seed.r(c.g * 2 + k, 314) * (SELECT count(*) FROM seed.role_rank))
WHERE seed.r(c.g, 315) < 0.50 AND (k = 1 OR seed.r(c.g, 316) < 0.5)
ORDER BY c.profile_id, jr.id;
INSERT INTO candidate_profile_section_score (candidate_profile_id, profile_section_id, completion_pct, computed_at)
SELECT c.profile_id, s, round(seed.r(c.g * 9 + s, 317) * 100, 2), now() - interval '7 days' * seed.r(c.g, 318)
FROM seed.cand_p c CROSS JOIN generate_series(1, 9) s WHERE seed.r(c.g, 319) < 0.20;

-- assessments and courses
INSERT INTO assessment (assessment_type_id, skill_id, title, max_score, pass_score, duration_minutes)
SELECT 2, sr.skill_id, s.name || ' skill test', 100, 60, 45 FROM seed.skill_rank sr JOIN skill s ON s.id = sr.skill_id WHERE sr.rank <= 16;
INSERT INTO assessment (assessment_type_id, title, max_score, pass_score, duration_minutes)
VALUES (4, 'Spoken English assessment', 10, 6, 20), (1, 'Career interests self-assessment', 50, NULL, 15), (3, 'Workplace behaviour profile', 40, NULL, 30);
INSERT INTO candidate_assessment_result (candidate_profile_id, assessment_id, attempt_number, started_at, completed_at, score, score_pct, is_passed)
SELECT c.profile_id, a.id, n, x.t, CASE WHEN x.done THEN x.t + interval '40 minutes' END,
       CASE WHEN x.done THEN round(a.max_score * x.pct / 100, 2) END, CASE WHEN x.done THEN x.pct END,
       CASE WHEN x.done AND a.pass_score IS NOT NULL THEN a.max_score * x.pct / 100 >= a.pass_score END
FROM seed.cand_p c CROSS JOIN generate_series(1, 2) n
JOIN (SELECT id, max_score, pass_score, row_number() OVER (ORDER BY id) AS rn FROM assessment) a ON a.rn = 1 + c.g % 19
CROSS JOIN LATERAL (SELECT now() - interval '300 days' * seed.r(c.g, 320) + interval '20 days' * n AS t, seed.r(c.g * 2 + n, 321) < 0.85 AS done,
                           round(30 + seed.r(c.g * 2 + n, 322) * 70, 2) AS pct) x
WHERE seed.r(c.g, 323) < 0.10 AND (n = 1 OR seed.r(c.g, 324) < 0.3);
INSERT INTO course (title, provider_name, course_url, duration_hours)
SELECT t || ' ' || lvl, p, 'https://learn.example.in/' || lower(replace(t, ' ', '-')) || '-' || lower(lvl), 10 + (length(t) % 30)
FROM unnest(ARRAY['Spring Boot','SQL for analysts','Spoken English','GST and Tally','Electrical safety','Retail selling','Customer support','Excel dashboards',
                  'Interview preparation','Digital marketing']) t
CROSS JOIN unnest(ARRAY['Basics','Advanced','Bootcamp']) lvl
CROSS JOIN LATERAL (SELECT (ARRAY['NPTEL','Skill India Digital','Talentra Academy'])[1 + length(t) % 3] AS p) x;
INSERT INTO course_enrolment (candidate_profile_id, course_id, enrolment_status_id, enrolled_on, completed_on, progress_pct)
SELECT c.profile_id, co.id, x.st, x.d, CASE WHEN x.st = 3 THEN x.d + 30 END, CASE x.st WHEN 3 THEN 100 WHEN 1 THEN 0 ELSE round(seed.r(c.g, 325) * 90, 2) END
FROM seed.cand_p c
JOIN (SELECT id, row_number() OVER (ORDER BY id) AS rn FROM course) co ON co.rn = 1 + c.g % 30
CROSS JOIN LATERAL (SELECT CASE WHEN seed.r(c.g, 326) < 0.40 THEN 3 WHEN seed.r(c.g, 326) < 0.70 THEN 2 WHEN seed.r(c.g, 326) < 0.90 THEN 1 ELSE 4 END AS st,
                           (now() - interval '400 days' * seed.r(c.g, 327))::date AS d) x
WHERE seed.r(c.g, 328) < 0.08;

-- screening questionnaires and the answers on applications to the requirements that use them
INSERT INTO questionnaire (organisation_id, title, language_id)
SELECT o.org_id, 'Screening questions', (SELECT id FROM language WHERE code = 'en') FROM seed.org o WHERE seed.r(o.g, 329) < 0.02 OR o.g <= 3;   -- the 3 largest employers always screen
INSERT INTO questionnaire_question (questionnaire_id, question_order, question_text, question_type_id, is_mandatory, is_knockout, min_number_value, max_number_value)
SELECT q.id, n, (ARRAY['Are you willing to work in rotational shifts?','How many years of relevant experience do you have?','What is your notice period?'])[n],
       (ARRAY[6, 5, 1])[n], true, n = 1, CASE WHEN n = 2 THEN 0 END, CASE WHEN n = 2 THEN 40 END
FROM questionnaire q CROSS JOIN generate_series(1, 3) n;
INSERT INTO questionnaire_question_option (questionnaire_question_id, option_order, option_text, is_knockout_pass)
SELECT qq.id, o.n, o.t, qq.is_knockout AND o.n = 1
FROM questionnaire_question qq
JOIN LATERAL (SELECT * FROM unnest(CASE WHEN qq.question_type_id = 6 THEN ARRAY['Yes','No'] ELSE ARRAY['Immediate','15 days','30 days','60 days or more'] END)
              WITH ORDINALITY u(t, n)) o ON true
WHERE qq.question_type_id IN (1, 6);
INSERT INTO job_requirement_questionnaire (job_requirement_id, questionnaire_id, sort_order)
SELECT j.job_id, q.id, 1 FROM seed.job j JOIN questionnaire q ON q.organisation_id = j.org_id
WHERE j.published_at IS NOT NULL
  AND (seed.r(j.g, 330) < 0.05 OR j.g = (SELECT min(j2.g) FROM seed.job j2 WHERE j2.org_id = j.org_id AND j2.published_at IS NOT NULL));
INSERT INTO application_answer (application_id, questionnaire_question_id, questionnaire_question_option_id, answer_number)
SELECT a.id, qq.id,
       CASE WHEN qq.question_type_id IN (1, 6) THEN (SELECT o.id FROM questionnaire_question_option o WHERE o.questionnaire_question_id = qq.id
                                                     ORDER BY o.option_order OFFSET (a.id % CASE WHEN qq.question_type_id = 6 THEN 2 ELSE 4 END) LIMIT 1) END,
       CASE WHEN qq.question_type_id = 5 THEN a.id % 15 END
FROM application a JOIN job_requirement_questionnaire jq ON jq.job_requirement_id = a.job_requirement_id
JOIN questionnaire_question qq ON qq.questionnaire_id = jq.questionnaire_id;

INSERT INTO job_requirement_qualification (job_requirement_id, qualification_id, field_of_study_id, is_mandatory)
SELECT j.job_id, q.id, CASE WHEN seed.r(j.g, 331) < 0.5 THEN fs.id END, seed.r(j.g, 332) < 0.6
FROM seed.job j JOIN seed.qual_rank q ON q.rank = 1 + floor(seed.r(j.g, 333) * (SELECT count(*) FROM seed.qual_rank))
JOIN seed.fos_rank fs ON fs.rank = 1 + floor(seed.r(j.g, 334) * (SELECT count(*) FROM seed.fos_rank))
WHERE seed.r(j.g, 335) < 0.40;
INSERT INTO gig_request_skill (gig_request_id, skill_id) SELECT request_id, skill_id FROM seed.gig_req;
INSERT INTO profile_project_skill (profile_project_id, skill_id)
SELECT DISTINCT ON (p.id, sr.skill_id) p.id, sr.skill_id
FROM profile_project p CROSS JOIN generate_series(1, 2) k JOIN seed.skill_rank sr ON sr.rank = 1 + ((p.id * 7 + k * 13) % 90)
ORDER BY p.id, sr.skill_id;

DO $$
BEGIN
    PERFORM seed.done('profile: addresses / links / certifications',
        (SELECT count(*) FROM candidate_address) + (SELECT count(*) FROM candidate_social_link) + (SELECT count(*) FROM candidate_certification));
    PERFORM seed.done('profile: preferred roles + section scores', (SELECT count(*) FROM candidate_preferred_job_role) + (SELECT count(*) FROM candidate_profile_section_score));
    PERFORM seed.done('profile: templates + template-built versions', (SELECT count(*) FROM resume_template) + (SELECT count(*) FROM resume_version WHERE resume_template_id IS NOT NULL));
    PERFORM seed.done('profile: assessments + results', (SELECT count(*) FROM assessment) + (SELECT count(*) FROM candidate_assessment_result));
    PERFORM seed.done('profile: courses + enrolments', (SELECT count(*) FROM course) + (SELECT count(*) FROM course_enrolment));
    PERFORM seed.done('jobs: questionnaires (q + options)', (SELECT count(*) FROM questionnaire) + (SELECT count(*) FROM questionnaire_question) + (SELECT count(*) FROM questionnaire_question_option));
    PERFORM seed.done('applications: questionnaire answers', (SELECT count(*) FROM application_answer));
    PERFORM seed.done('jobs/gig/projects: qualification + skill links',
        (SELECT count(*) FROM job_requirement_qualification) + (SELECT count(*) FROM gig_request_skill) + (SELECT count(*) FROM profile_project_skill));
END $$;
