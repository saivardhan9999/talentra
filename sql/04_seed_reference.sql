-- =============================================================================
-- Talentra :: 04_seed_reference.sql
-- Reference values every environment needs (not the 1M-profile synthetic seed,
-- which is Phase 5). Seeded rows take ids 1..n (< 1000 = system range), so the
-- ids used by CHECK constraints are stable: salary_disclosure_status 1/2/3 and
-- job_category 1 = gig.
-- =============================================================================
SET app.current_user_id = '1';

-- language needs a ui_label_key, so its labels are created first.
CREATE OR REPLACE PROCEDURE seed_label(p_label_key text, p_module text, INOUT p_id bigint DEFAULT NULL)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO ui_label_key (label_key, module_code) VALUES (p_label_key, p_module)
    ON CONFLICT (label_key) DO NOTHING;
    SELECT id INTO p_id FROM ui_label_key WHERE label_key = p_label_key;
END $$;

CREATE OR REPLACE PROCEDURE seed_translation(p_label_key text, p_language_code text, p_text text)
LANGUAGE sql AS $$
    INSERT INTO ui_label_translation (ui_label_key_id, language_id, label_text)
    SELECT k.id, l.id, p_text FROM ui_label_key k, language l
    WHERE k.label_key = p_label_key AND l.code = p_language_code
    ON CONFLICT (ui_label_key_id, language_id) DO UPDATE SET label_text = EXCLUDED.label_text;
$$;

-- Items are 'code|English label'; ids are assigned 1..n in array order.
CREATE OR REPLACE PROCEDURE seed_lookups(p_table text, p_items text[])
LANGUAGE plpgsql AS $$
DECLARE
    i int;
    v_code text;
    v_label text;
    v_key text;
    v_key_id bigint;
BEGIN
    FOR i IN 1 .. array_length(p_items, 1) LOOP
        v_code  := split_part(p_items[i], '|', 1);
        v_label := split_part(p_items[i], '|', 2);
        v_key   := 'lookup.' || p_table || '.' || v_code;
        CALL seed_label(v_key, 'master_data', v_key_id);
        CALL seed_translation(v_key, 'en', v_label);
        EXECUTE format('INSERT INTO %I (id, code, ui_label_key_id, sort_order) VALUES ($1, $2, $3, $4)', p_table)
            USING i, v_code, v_key_id, i * 10;
    END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- Languages (en is the default/fallback UI language)
-- -----------------------------------------------------------------------------
DO $$
DECLARE r record; k bigint; n int := 0;
BEGIN
    FOR r IN SELECT * FROM (VALUES
        ('en', 'English',  true,  true),
        ('hi', 'हिन्दी',     true,  false),
        ('ta', 'தமிழ்',     true,  false),
        ('te', 'తెలుగు',    false, false),
        ('kn', 'ಕನ್ನಡ',     false, false),
        ('ml', 'മലയാളം',   false, false),
        ('mr', 'मराठी',     false, false),
        ('bn', 'বাংলা',     false, false),
        ('ar', 'العربية',   false, false),
        ('zh-Hans', '简体中文', false, false)) AS v(code, native_name, is_ui, is_default)
    LOOP
        n := n + 1;
        CALL seed_label('lookup.language.' || replace(lower(r.code), '-', '_'), 'master_data', k);
        INSERT INTO language (id, code, native_name, ui_label_key_id, is_ui_supported, is_default, sort_order)
        VALUES (n, r.code, r.native_name, k, r.is_ui, r.is_default, n * 10);
    END LOOP;
END $$;
CALL seed_translation('lookup.language.en', 'en', 'English');
CALL seed_translation('lookup.language.hi', 'en', 'Hindi');
CALL seed_translation('lookup.language.ta', 'en', 'Tamil');
CALL seed_translation('lookup.language.te', 'en', 'Telugu');
CALL seed_translation('lookup.language.kn', 'en', 'Kannada');
CALL seed_translation('lookup.language.ml', 'en', 'Malayalam');
CALL seed_translation('lookup.language.mr', 'en', 'Marathi');
CALL seed_translation('lookup.language.bn', 'en', 'Bengali');
CALL seed_translation('lookup.language.ar', 'en', 'Arabic');
CALL seed_translation('lookup.language.zh_hans', 'en', 'Chinese (Simplified)');

-- -----------------------------------------------------------------------------
-- Enumerations
-- -----------------------------------------------------------------------------
CALL seed_lookups('coordinate_source', ARRAY['mapping_provider|Mapping provider','user_device|User device','manual|Entered manually','legacy_import|Legacy import']);
CALL seed_lookups('phone_type', ARRAY['mobile|Mobile','landline|Landline','whatsapp|WhatsApp']);
CALL seed_lookups('address_type', ARRAY['current|Current address','permanent|Permanent address','correspondence|Correspondence address']);
CALL seed_lookups('social_link_type', ARRAY['linkedin|LinkedIn','github|GitHub','portfolio|Portfolio','other|Other']);
CALL seed_lookups('gender', ARRAY['female|Female','male|Male','non_binary|Non-binary','other|Other','prefer_not_to_say|Prefer not to say']);
CALL seed_lookups('marital_status', ARRAY['single|Single','married|Married','other|Other','prefer_not_to_say|Prefer not to say']);
CALL seed_lookups('salary_disclosure_status', ARRAY['disclosed|Disclosed','not_disclosed|Not disclosed','not_applicable|Not applicable']);
CALL seed_lookups('salary_period', ARRAY['annual|Per year','monthly|Per month','daily|Per day','hourly|Per hour']);
CALL seed_lookups('notice_period', ARRAY['immediate|Immediate','days_15|15 days','days_30|30 days','days_60|60 days','days_90|90 days','more_than_90_days|More than 90 days']);
CALL seed_lookups('profile_visibility', ARRAY['public|Visible to all employers','employers_only|Visible to verified employers','hidden|Hidden']);
CALL seed_lookups('skill_category', ARRAY['technical|Technical','functional|Functional','soft|Soft skill','trade|Trade / vocational','tool|Tool / software']);
CALL seed_lookups('proficiency_level', ARRAY['beginner|Beginner','intermediate|Intermediate','advanced|Advanced','expert|Expert']);
CALL seed_lookups('language_proficiency_level', ARRAY['elementary|Elementary','limited_working|Limited working','professional|Professional working','full_professional|Full professional','native|Native or bilingual']);
CALL seed_lookups('qualification_level', ARRAY['below_10th|Below 10th','class_10|10th','class_12|12th','iti|ITI','diploma|Diploma','graduate|Graduate','post_graduate|Post graduate','doctorate|Doctorate','certificate|Certificate']);
CALL seed_lookups('education_mode', ARRAY['full_time|Full time','part_time|Part time','distance|Distance','online|Online']);
CALL seed_lookups('grade_scale', ARRAY['percentage|Percentage','cgpa_10|CGPA (10)','cgpa_4|GPA (4)','letter|Letter grade','pass_fail|Pass / fail']);
CALL seed_lookups('employment_type', ARRAY['full_time|Full time','part_time|Part time','contract|Contract','temporary|Temporary','apprentice|Apprenticeship','internship|Internship','freelance|Freelance']);
CALL seed_lookups('work_mode', ARRAY['onsite|On-site','remote|Remote','hybrid|Hybrid']);
CALL seed_lookups('job_category', ARRAY['gig|Gig / project work','general_staffing|General staffing','professional_staffing|Professional staffing','permanent|Permanent full-time','apprentice|Apprentice hiring','campus|Campus / fresher hiring','consultant_marketplace|Consultant marketplace','managed_remote|Managed remote workforce']);
CALL seed_lookups('functional_area', ARRAY['engineering|Engineering','it_software|IT / software','sales|Sales','operations|Operations','finance|Finance','human_resources|Human resources','customer_service|Customer service','logistics|Logistics','manufacturing|Manufacturing','healthcare|Healthcare']);
CALL seed_lookups('project_kind', ARRAY['candidate_project|Project','gig_project|Gig project']);
CALL seed_lookups('assessment_type', ARRAY['self_assessment|Self-assessment','skill_test|Skill test','psychometric|Psychometric','language_test|Language test']);
CALL seed_lookups('enrolment_status', ARRAY['enrolled|Enrolled','in_progress|In progress','completed|Completed','dropped|Dropped']);
CALL seed_lookups('profile_section', ARRAY['personal|Personal details','contact|Contact details','education|Education','experience|Work experience','skills|Skills','languages|Languages','resume|Resume','projects|Projects','preferences|Career preferences']);
CALL seed_lookups('activity_type', ARRAY['login|Logged in','logout|Logged out','profile_update|Updated profile','resume_upload|Uploaded resume','resume_download|Downloaded resume','application_submit|Applied to a job','password_change|Changed password','privacy_change|Changed privacy settings']);
CALL seed_lookups('view_context', ARRAY['search_result|Search result','application|Application review','sourcing|Sourcing','talent_list|Talent list','direct_link|Direct link']);
CALL seed_lookups('legacy_source_system', ARRAY['legacy_ats|Legacy ATS','legacy_jobboard|Legacy job board','legacy_staffing|Legacy staffing system']);
CALL seed_lookups('job_requirement_status', ARRAY['draft|Draft','pending_approval|Pending approval','open|Open','on_hold|On hold','closed|Closed','filled|Filled','cancelled|Cancelled']);
CALL seed_lookups('publish_state', ARRAY['unpublished|Unpublished','scheduled|Scheduled','published|Published','expired|Expired','withdrawn|Withdrawn']);
CALL seed_lookups('job_position_status', ARRAY['open|Open','filled|Filled','cancelled|Cancelled']);
CALL seed_lookups('application_status', ARRAY['applied|Applied','screening|Screening','shortlisted|Shortlisted','interview_scheduled|Interview scheduled','interviewed|Interviewed','offered|Offered','offer_accepted|Offer accepted','joined|Joined','rejected|Rejected','withdrawn|Withdrawn','offer_declined|Offer declined','on_hold|On hold']);
CALL seed_lookups('application_source', ARRAY['direct|Direct application','sourced|Sourced by recruiter','consultant|Consultant submission','referral|Referral','campus_drive|Campus drive','bulk_outreach|Bulk outreach response','legacy_import|Legacy import']);
CALL seed_lookups('rejection_reason', ARRAY['skills_mismatch|Skills mismatch','experience_mismatch|Experience mismatch','salary_mismatch|Salary mismatch','location_mismatch|Location mismatch','position_filled|Position filled','no_show|No show','failed_interview|Did not clear interview','other|Other']);
CALL seed_lookups('question_type', ARRAY['single_choice|Single choice','multi_choice|Multiple choice','short_text|Short text','long_text|Long text','number|Number','yes_no|Yes / no']);
CALL seed_lookups('interview_round_type', ARRAY['screening|Screening','technical|Technical','managerial|Managerial','hr|HR','assignment|Assignment']);
CALL seed_lookups('interview_mode', ARRAY['in_person|In person','video|Video','phone|Phone']);
CALL seed_lookups('interview_outcome', ARRAY['selected|Selected','rejected|Rejected','on_hold|On hold','no_show|No show','rescheduled|Rescheduled']);
CALL seed_lookups('offer_status', ARRAY['extended|Extended','accepted|Accepted','declined|Declined','revoked|Revoked','expired|Expired']);
CALL seed_lookups('talent_list_type', ARRAY['shortlist|Shortlist','bookmark|Bookmark']);
CALL seed_lookups('referral_status', ARRAY['invited|Invited','registered|Registered','applied|Applied','hired|Hired','expired|Expired']);

UPDATE profile_section SET weight_pct = v.w
FROM (VALUES ('personal',15),('contact',10),('education',15),('experience',20),('skills',15),
             ('languages',5),('resume',10),('projects',5),('preferences',5)) AS v(code, w)
WHERE profile_section.code = v.code;

UPDATE application_status SET is_initial = true WHERE code = 'applied';
UPDATE application_status SET is_terminal = true WHERE code IN ('joined','rejected','withdrawn','offer_declined');
UPDATE activity_type SET is_sensitive = true WHERE code IN ('resume_download','password_change','privacy_change');

-- Pipeline: applied -> screening -> shortlisted -> interview_scheduled -> interviewed -> offered
--           -> offer_accepted -> joined; reject/withdraw/hold from any open stage.
INSERT INTO application_status_transition (from_application_status_id, to_application_status_id)
SELECT f.id, t.id
FROM (VALUES
    ('applied','screening'), ('applied','shortlisted'),
    ('screening','shortlisted'),
    ('shortlisted','interview_scheduled'),
    ('interview_scheduled','interviewed'),
    ('interviewed','interview_scheduled'), ('interviewed','offered'),
    ('offered','offer_accepted'), ('offered','offer_declined'),
    ('offer_accepted','joined'),
    ('on_hold','screening'), ('on_hold','shortlisted'), ('on_hold','interview_scheduled')
) AS v(f, t)
JOIN application_status f ON f.code = v.f
JOIN application_status t ON t.code = v.t
UNION ALL
SELECT s.id, t.id
FROM application_status s
CROSS JOIN application_status t
WHERE NOT s.is_terminal
  AND t.code IN ('rejected', 'withdrawn', 'on_hold')
  AND s.id <> t.id
  AND NOT (s.code = 'offer_accepted' AND t.code = 'on_hold');

-- Sample translations proving the fallback chain (others fall back to en).
CALL seed_translation('lookup.application_status.applied',     'hi', 'आवेदन किया');
CALL seed_translation('lookup.application_status.shortlisted', 'hi', 'शॉर्टलिस्ट किया गया');
CALL seed_translation('lookup.application_status.rejected',    'hi', 'अस्वीकृत');
CALL seed_translation('lookup.application_status.joined',      'hi', 'कार्यभार ग्रहण किया');
CALL seed_translation('lookup.application_status.applied',     'ta', 'விண்ணப்பிக்கப்பட்டது');
CALL seed_translation('lookup.application_status.shortlisted', 'ta', 'பட்டியலிடப்பட்டது');
CALL seed_translation('lookup.application_status.rejected',    'ta', 'நிராகரிக்கப்பட்டது');
CALL seed_translation('lookup.salary_disclosure_status.not_disclosed', 'hi', 'प्रकट नहीं किया गया');
CALL seed_translation('lookup.salary_disclosure_status.not_disclosed', 'ta', 'வெளியிடப்படவில்லை');

-- -----------------------------------------------------------------------------
-- Currency, countries (sample; full ISO lists are loaded by the Phase 5 generator)
-- -----------------------------------------------------------------------------
DO $$
DECLARE r record; k bigint; n int := 0;
BEGIN
    FOR r IN SELECT * FROM (VALUES ('INR','Indian Rupee',2),('USD','US Dollar',2),('EUR','Euro',2),
                                   ('GBP','Pound Sterling',2),('AED','UAE Dirham',2),('SGD','Singapore Dollar',2)) AS v(code, name, mu)
    LOOP
        n := n + 1;
        CALL seed_label('lookup.currency.' || lower(r.code), 'master_data', k);
        CALL seed_translation('lookup.currency.' || lower(r.code), 'en', r.name);
        INSERT INTO currency (id, code, name, minor_unit, ui_label_key_id, sort_order) VALUES (n, r.code, r.name, r.mu, k, n * 10);
    END LOOP;
    n := 0;
    FOR r IN SELECT * FROM (VALUES ('IN','IND','India','91','INR'),('US','USA','United States','1','USD'),
                                   ('GB','GBR','United Kingdom','44','GBP'),('AE','ARE','United Arab Emirates','971','AED'),
                                   ('SG','SGP','Singapore','65','SGD'),('DE','DEU','Germany','49','EUR')) AS v(a2, a3, name, cc, cur)
    LOOP
        n := n + 1;
        CALL seed_label('lookup.country.' || lower(r.a2), 'master_data', k);
        CALL seed_translation('lookup.country.' || lower(r.a2), 'en', r.name);
        INSERT INTO country (id, iso_alpha2, iso_alpha3, name, phone_country_code, currency_id, ui_label_key_id, sort_order)
        SELECT n, r.a2, r.a3, r.name, r.cc, c.id, k, n * 10 FROM currency c WHERE c.code = r.cur;
    END LOOP;
END $$;
CALL seed_translation('lookup.country.in', 'hi', 'भारत');
CALL seed_translation('lookup.country.in', 'ta', 'இந்தியா');

INSERT INTO state (id, country_id, code, name)
SELECT v.id, c.id, v.code, v.name FROM (VALUES
    (1,'TN','Tamil Nadu'),(2,'KA','Karnataka'),(3,'MH','Maharashtra'),(4,'DL','Delhi'),(5,'TG','Telangana')) AS v(id, code, name)
CROSS JOIN country c WHERE c.iso_alpha2 = 'IN';

INSERT INTO city (id, country_id, state_id, name, latitude, longitude, coordinate_source_id)
SELECT v.id, c.id, s.id, v.name, v.lat, v.lon, 1
FROM (VALUES (1,'TN','Chennai',13.082700,80.270700),(2,'TN','Coimbatore',11.016800,76.955800),
             (3,'KA','Bengaluru',12.971600,77.594600),(4,'MH','Mumbai',19.076000,72.877700),
             (5,'MH','Pune',18.520400,73.856700),(6,'DL','New Delhi',28.613900,77.209000),
             (7,'TG','Hyderabad',17.385000,78.486700)) AS v(id, st, name, lat, lon)
JOIN country c ON c.iso_alpha2 = 'IN'
JOIN state s ON s.country_id = c.id AND s.code = v.st;
INSERT INTO city (id, country_id, state_id, name) SELECT 8, id, NULL, 'Singapore' FROM country WHERE iso_alpha2 = 'SG';

RESET app.current_user_id;
