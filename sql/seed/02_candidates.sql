-- =============================================================================
-- Talentra seed :: 02_candidates.sql  (B60: 1M candidate profiles, duplicates, multilingual names)
-- Distributions (stated, checked in M20):
--   name script   72% Latin, 6% Devanagari (hi), 6% Tamil, 4% Telugu, 3% each Kannada, Malayalam,
--                 Marathi (Devanagari), Bengali; name_language_id records it
--   name style    80% "Given Family", 10% "Given F" (initial), 10% single name (no family name)
--   duplicates    2% are second registrations of an earlier person: same name and phone, plus-addressed
--                 email; half are flagged (duplicate_of_candidate_profile_id), half left for detection
--   city          skewed towards the metros (seed.skew over population rank)
--   experience    20% freshers (0 months); others 6..306 months, skewed low
--   salary        40% disclose current salary (INR, annual); 30% disclose expected salary
--   visibility    85% public, 12% employers only, 3% hidden; 0.5% soft-deleted; 10% legacy imports
--   children      2-6 skills, 1-2 education rows, 0-3 jobs, 1-3 languages, 1-2 preferred cities,
--                 70% have a resume with 1-2 uploaded versions
-- Profiles are created by the system actor (migration path allowed by the self-registration rule).
-- =============================================================================
\set ON_ERROR_STOP on
SET app.current_user_id = '1';
SET synchronous_commit = off;

-- cum = cumulative share (documents the distribution; the CASE below applies it)
CREATE TABLE seed.name_pool (lang text PRIMARY KEY, cum numeric, latin boolean, given text[], family text[]);
INSERT INTO seed.name_pool VALUES
 ('en', 0.72, true,
  ARRAY['Aarav','Aditi','Akash','Ananya','Arjun','Bhavna','Deepak','Divya','Farhan','Gayathri','Harish','Ishita','Jaya','Karthik','Kavya',
        'Lakshmi','Manoj','Meera','Mohammed','Nandini','Naveen','Neha','Pooja','Pradeep','Priya','Rahul','Ramesh','Rekha','Rohit','Sanjay',
        'Sangeetha','Saranya','Senthil','Shreya','Siddharth','Sneha','Suresh','Tanvi','Uday','Vandana','Venkatesh','Vidya','Vikram','Yamini',
        'Zoya','Abdul','Fathima','Joseph','Mary','Gurpreet','Harpreet','Imran','Ayesha','Nikhil','Swati','Anil','Sunita','Kiran','Ravi','Asha'],
  ARRAY['Sharma','Verma','Iyer','Nair','Reddy','Rao','Patel','Shah','Gupta','Singh','Kumar','Krishnan','Menon','Pillai','Das','Banerjee',
        'Chatterjee','Mukherjee','Joshi','Kulkarni','Deshpande','Naidu','Choudhary','Yadav','Khan','Ansari','Fernandes','D''Souza','Gill',
        'Bhat','Hegde','Shetty','Mishra','Tiwari','Pandey','Agarwal','Jain','Mehta','Thomas','Varghese','Subramanian','Ramachandran']),
 ('hi', 0.78, false, ARRAY['राहुल','प्रिया','अमित','सुनीता','विकास','अंजलि','संजय','पूजा','रोहित','नेहा','अजय','कविता'],
                     ARRAY['शर्मा','वर्मा','गुप्ता','सिंह','यादव','मिश्रा','तिवारी','पांडेय']),
 ('ta', 0.84, false, ARRAY['கார்த்திக்','பிரியா','செந்தில்','லட்சுமி','முருகன்','கவிதா','அருண்','தமிழ்செல்வி','ராஜேஷ்','சரண்யா','விஜய்','மீனா'],
                     ARRAY['குமார்','ராஜா','சுப்பிரமணியம்','வேலு','கிருஷ்ணன்','சுந்தரம்']),
 ('te', 0.88, false, ARRAY['శ్రీనివాస్','లక్ష్మి','రవి','సుజాత','వెంకట్','పద్మ','కిరణ్','అనూష'], ARRAY['రెడ్డి','రావు','నాయుడు','శర్మ']),
 ('kn', 0.91, false, ARRAY['ಮಂಜುನಾಥ್','ಕಾವ್ಯ','ಸುರೇಶ್','ದೀಪಾ','ಪ್ರಕಾಶ್','ಶ್ವೇತಾ'], ARRAY['ಗೌಡ','ಹೆಗ್ಡೆ','ಶೆಟ್ಟಿ','ರಾವ್']),
 ('ml', 0.94, false, ARRAY['അനീഷ്','ദിവ്യ','രാജേഷ്','ലക്ഷ്മി','സുനിൽ','അഞ്ജു'], ARRAY['നായർ','മേനോൻ','പിള്ള','വർഗീസ്']),
 ('mr', 0.97, false, ARRAY['गणेश','स्नेहा','महेश','प्राजक्ता','सचिन','अश्विनी'], ARRAY['पाटील','जोशी','कुलकर्णी','देशमुख']),
 ('bn', 1.00, false, ARRAY['সৌরভ','প্রিয়াঙ্কা','অর্জুন','মৌমিতা','সুমন','রিয়া'], ARRAY['দাস','ব্যানার্জি','চ্যাটার্জি','সেন']);

-- rank tables: join on a computed rank instead of a per-row subquery
CREATE TABLE seed.role_rank AS SELECT row_number() OVER (ORDER BY id) AS rank, id, name FROM job_role;
CREATE TABLE seed.industry_rank AS SELECT row_number() OVER (ORDER BY id) AS rank, id FROM industry;
CREATE TABLE seed.qual_rank AS SELECT row_number() OVER (ORDER BY id) AS rank, id FROM qualification WHERE code NOT IN ('below_10th','ssc_10th','hsc_science','hsc_commerce','hsc_arts');
CREATE TABLE seed.fos_rank AS SELECT row_number() OVER (ORDER BY id) AS rank, id FROM field_of_study;
CREATE TABLE seed.inst_rank AS SELECT row_number() OVER (ORDER BY id) AS rank, id FROM institution;

-- Staging: one row per person-to-be (g = row number).
CREATE TABLE seed.cand AS
SELECT s.g, p.lang, p.latin,
       seed.pick(p.given, s.g, 2) AS given,
       CASE WHEN seed.r(s.g, 4) < 0.90 THEN seed.pick(p.family, s.g, 3) END AS family,
       seed.r(s.g, 4) AS style,
       seed.pick(ARRAY['gmail.com','gmail.com','gmail.com','yahoo.co.in','outlook.com','rediffmail.com','hotmail.com'], s.g, 5) AS domain,
       '+91' || (6 + floor(seed.r(s.g, 7) * 4))::int || lpad(floor(seed.r(s.g, 8) * 999999999)::bigint::text, 9, '0') AS phone,
       CASE WHEN s.g > 1000 AND seed.r(s.g, 9) < 0.02 THEN s.g - 1 - floor(seed.r(s.g, 10) * 900)::bigint END AS dup_of_g,
       seed.ts(s.g, 11) - interval '2 days' AS registered_at   -- leaves room for an application after registration
FROM generate_series(1, seed.n(1000000)) s(g)
JOIN seed.name_pool p ON p.lang = CASE WHEN seed.r(s.g, 1) < 0.72 THEN 'en' WHEN seed.r(s.g, 1) < 0.78 THEN 'hi' WHEN seed.r(s.g, 1) < 0.84 THEN 'ta'
                                       WHEN seed.r(s.g, 1) < 0.88 THEN 'te' WHEN seed.r(s.g, 1) < 0.91 THEN 'kn' WHEN seed.r(s.g, 1) < 0.94 THEN 'ml'
                                       WHEN seed.r(s.g, 1) < 0.97 THEN 'mr' ELSE 'bn' END;
ALTER TABLE seed.cand ADD PRIMARY KEY (g);
-- a duplicate copies its source person (name, script, phone)
UPDATE seed.cand d SET lang = s.lang, latin = s.latin, given = s.given, family = s.family, style = s.style, phone = s.phone
FROM seed.cand s WHERE d.dup_of_g = s.g;
ALTER TABLE seed.cand ADD COLUMN full_name text, ADD COLUMN email text;
UPDATE seed.cand SET
    full_name = CASE WHEN family IS NULL THEN given
                     WHEN style < 0.80 THEN given || ' ' || family
                     ELSE given || ' ' || left(family, 1) END,
    email = CASE WHEN latin THEN lower(regexp_replace(given, '[^A-Za-z]', '', 'g')) || '.'
                                 || lower(regexp_replace(coalesce(family, 'in'), '[^A-Za-z]', '', 'g')) || g
                 ELSE 'user' || g END || '@' || domain;
-- duplicate registrations use plus-addressing on the source mailbox (same inbox, different account)
UPDATE seed.cand d SET email = split_part(s.email, '@', 1) || '+' || d.g || '@' || split_part(s.email, '@', 2)
FROM seed.cand s WHERE d.dup_of_g = s.g;

INSERT INTO user_account (email, created_at, updated_at)
SELECT email, registered_at, registered_at FROM seed.cand ORDER BY g;
CREATE TABLE seed.cand_user AS SELECT c.g, u.id AS user_id FROM seed.cand c JOIN user_account u ON u.email = c.email;
ALTER TABLE seed.cand_user ADD PRIMARY KEY (g);

INSERT INTO candidate_profile (
    user_account_id, full_name, given_name, family_name, name_language_id, date_of_birth, gender_id, nationality_country_id, headline,
    current_city_id, total_experience_months, is_fresher, current_job_role_id, current_industry_id,
    current_salary_disclosure_status_id, current_salary_amount, current_salary_currency_id, current_salary_period_id,
    expected_salary_disclosure_status_id, expected_salary_amount, expected_salary_currency_id, expected_salary_period_id,
    notice_period_id, is_open_to_relocation, is_actively_looking, profile_visibility_id, profile_completion_pct, last_active_at,
    legacy_source_system_id, legacy_record_ref, deleted_at, created_at, updated_at)
SELECT u.user_id,
       -- 1 in 300 duplicates carries stray whitespace, a typical import defect
       CASE WHEN c.dup_of_g IS NOT NULL AND c.g % 3 = 0 THEN c.full_name || '  ' ELSE c.full_name END,
       c.given, c.family, l.id,
       DATE '1970-01-01' + floor(seed.r(c.g, 12) * 13000)::int,
       CASE WHEN seed.r(c.g, 13) < 0.48 THEN 1 WHEN seed.r(c.g, 13) < 0.96 THEN 2 WHEN seed.r(c.g, 13) < 0.97 THEN 3 ELSE 5 END,
       (SELECT id FROM country WHERE iso_alpha2 = 'IN'),
       CASE WHEN x.fresher THEN 'Fresher looking for a ' || lower(jr.name) || ' role'
            ELSE jr.name || ' with ' || (x.exp / 12) || ' years of experience' END,
       cr.city_id, x.exp, x.fresher, jr.id, ir.id,
       CASE WHEN x.sal THEN 1 ELSE 2 END,
       CASE WHEN x.sal THEN round(180000 + x.exp * 2500 * (0.6 + seed.r(c.g, 16)), -3) END,
       CASE WHEN x.sal THEN 1 END, CASE WHEN x.sal THEN 1 END,
       CASE WHEN x.exp_sal THEN 1 ELSE 2 END,
       CASE WHEN x.exp_sal THEN round((180000 + x.exp * 2500 * (0.6 + seed.r(c.g, 16))) * 1.25, -3) END,
       CASE WHEN x.exp_sal THEN 1 END, CASE WHEN x.exp_sal THEN 1 END,
       1 + floor(seed.r(c.g, 17) * 6)::int,
       seed.r(c.g, 18) < 0.30, seed.r(c.g, 19) < 0.60,
       CASE WHEN seed.r(c.g, 20) < 0.85 THEN 1 WHEN seed.r(c.g, 20) < 0.97 THEN 2 ELSE 3 END,
       round(30 + seed.r(c.g, 21) * 70, 2),
       now() - interval '120 days' * seed.r(c.g, 22),
       CASE WHEN seed.r(c.g, 23) < 0.10 THEN 1 + floor(seed.r(c.g, 24) * 3)::int END,
       CASE WHEN seed.r(c.g, 23) < 0.10 THEN 'LEG-' || lpad(c.g::text, 9, '0') END,
       CASE WHEN seed.r(c.g, 25) < 0.005 THEN now() - interval '30 days' * seed.r(c.g, 26) END,
       c.registered_at, c.registered_at
FROM seed.cand c
JOIN seed.cand_user u USING (g)
JOIN language l ON l.code = c.lang
JOIN seed.city_rank cr ON cr.rank = seed.skew((SELECT count(*) FROM seed.city_rank), c.g, 14)
CROSS JOIN LATERAL (SELECT seed.r(c.g, 30) < 0.20 AS fresher,
                           CASE WHEN seed.r(c.g, 30) < 0.20 THEN 0 ELSE 6 + floor(300 * power(seed.r(c.g, 31), 1.7))::int END AS exp,
                           seed.r(c.g, 32) < 0.40 AS sal, seed.r(c.g, 33) < 0.30 AS exp_sal) x
JOIN seed.role_rank jr ON jr.rank = 1 + floor(seed.r(c.g, 34) * (SELECT count(*) FROM seed.role_rank))
JOIN seed.industry_rank ir ON ir.rank = 1 + floor(seed.r(c.g, 15) * (SELECT count(*) FROM seed.industry_rank));

CREATE TABLE seed.cand_p AS
SELECT c.g, p.id AS profile_id, u.user_id, p.is_fresher, coalesce(p.total_experience_months, 0) AS exp, p.current_city_id AS city_id,
       c.lang, c.email, c.phone, c.dup_of_g, p.date_of_birth, p.deleted_at IS NULL AS live, c.registered_at
FROM seed.cand c JOIN seed.cand_user u USING (g) JOIN candidate_profile p ON p.user_account_id = u.user_id;
ALTER TABLE seed.cand_p ADD PRIMARY KEY (g);
CREATE INDEX ON seed.cand_p (profile_id);

-- half of the duplicates were caught by the dedupe job at registration time
UPDATE candidate_profile p SET duplicate_of_candidate_profile_id = s.profile_id
FROM seed.cand_p d JOIN seed.cand_p s ON s.g = d.dup_of_g
WHERE p.id = d.profile_id AND d.dup_of_g IS NOT NULL AND d.g % 2 = 0;

INSERT INTO candidate_email (candidate_profile_id, email, is_primary, verified_at)
SELECT profile_id, email, true, CASE WHEN seed.r(g, 40) < 0.70 THEN now() - interval '200 days' * seed.r(g, 41) END FROM seed.cand_p;
INSERT INTO candidate_email (candidate_profile_id, email, is_primary)
SELECT profile_id, 'alt.' || split_part(email, '@', 1) || '@outlook.com', false FROM seed.cand_p WHERE seed.r(g, 42) < 0.10;
INSERT INTO candidate_phone (candidate_profile_id, phone_e164, country_id, phone_type_id, is_primary, verified_at)
SELECT profile_id, phone, (SELECT id FROM country WHERE iso_alpha2 = 'IN'), 1, true,
       CASE WHEN seed.r(g, 43) < 0.60 THEN now() - interval '200 days' * seed.r(g, 44) END
FROM seed.cand_p;

-- 2-6 distinct skills per person: a popular base skill plus coprime steps
INSERT INTO candidate_skill (candidate_profile_id, skill_id, proficiency_level_id, experience_months, last_used_year, is_primary)
SELECT p.profile_id, sr.skill_id, 1 + floor(seed.r(p.g * 7 + k, 45) * 4)::int,
       least(p.exp, floor(seed.r(p.g * 7 + k, 46) * (p.exp + 1))::int), 2020 + floor(seed.r(p.g * 7 + k, 47) * 7)::int, k = 1
FROM seed.cand_p p
CROSS JOIN generate_series(1, 6) k
JOIN seed.skill_rank sr ON sr.rank = 1 + ((seed.skew(90, p.g, 48) - 1 + (k - 1) * 17) % 90)
WHERE k <= 2 + floor(seed.r(p.g, 49) * 5);

-- highest qualification (+ class 12 for 40%)
INSERT INTO candidate_education (candidate_profile_id, qualification_id, field_of_study_id, institution_id, education_mode_id,
                                 start_date, end_date, is_ongoing, grade_scale_id, grade_value, is_highest)
SELECT p.profile_id, q.id, fs.id, i.id, 1,
       (p.date_of_birth + interval '18 years')::date,
       CASE WHEN p.is_fresher AND seed.r(p.g, 50) < 0.15 THEN NULL ELSE (p.date_of_birth + interval '21 years')::date END,
       p.is_fresher AND seed.r(p.g, 50) < 0.15,
       1, round(55 + seed.r(p.g, 51) * 40, 2), true
FROM seed.cand_p p
JOIN seed.qual_rank q ON q.rank = 1 + floor(seed.r(p.g, 52) * (SELECT count(*) FROM seed.qual_rank))
JOIN seed.fos_rank fs ON fs.rank = 1 + floor(seed.r(p.g, 53) * (SELECT count(*) FROM seed.fos_rank))
JOIN seed.inst_rank i ON i.rank = 1 + floor(seed.r(p.g, 54) * (SELECT count(*) FROM seed.inst_rank));
INSERT INTO candidate_education (candidate_profile_id, qualification_id, institution_name, start_date, end_date, is_highest)
SELECT p.profile_id, (SELECT id FROM qualification WHERE code = 'hsc_science'), 'Government Higher Secondary School',
       (p.date_of_birth + interval '16 years')::date, (p.date_of_birth + interval '18 years')::date, false
FROM seed.cand_p p WHERE seed.r(p.g, 55) < 0.40;

-- 1-3 jobs for experienced people, newest first, contiguous back from today
INSERT INTO candidate_work_experience (candidate_profile_id, employer_name, job_title, job_role_id, employment_type_id, city_id,
                                       start_date, end_date, is_current)
SELECT p.profile_id,
       seed.pick(ARRAY['Infosys','TCS','Wipro','HCLTech','Tech Mahindra','Reliance Retail','HDFC Bank','ICICI Bank','Flipkart','Amazon India',
                       'Swiggy','Zomato','Larsen & Toubro','Tata Motors','Mahindra Logistics','Apollo Hospitals','Big Bazaar','DMart','Blue Dart',
                       'Delhivery','Asian Paints','Bajaj Auto','Sundaram Clayton','Ashok Leyland','Local proprietorship firm'], p.g * 3 + j, 56),
       jr.name, jr.id, 1, p.city_id,
       (now() - interval '1 month' * least(p.exp, (p.exp * j) / n.jobs))::date,
       CASE WHEN j = 1 AND seed.r(p.g, 57) < 0.7 THEN NULL
            ELSE (now() - interval '1 month' * ((p.exp * (j - 1)) / n.jobs) - interval '1 day')::date END,
       j = 1 AND seed.r(p.g, 57) < 0.7
FROM seed.cand_p p
CROSS JOIN LATERAL (SELECT 1 + floor(seed.r(p.g, 58) * 3)::int AS jobs) n
CROSS JOIN generate_series(1, 3) j
JOIN seed.role_rank jr ON jr.rank = 1 + floor(seed.r(p.g * 3 + j, 59) * (SELECT count(*) FROM seed.role_rank))
WHERE NOT p.is_fresher AND p.exp >= 3 AND j <= n.jobs;

INSERT INTO candidate_language (candidate_profile_id, language_id, language_proficiency_level_id, can_read, can_write, can_speak)
SELECT p.profile_id, (SELECT id FROM language WHERE code = 'en'), 2 + floor(seed.r(p.g, 60) * 3)::int, true, true, true FROM seed.cand_p p;
INSERT INTO candidate_language (candidate_profile_id, language_id, language_proficiency_level_id, can_read, can_write, can_speak)
SELECT p.profile_id, l.id, 5, true, true, true FROM seed.cand_p p JOIN language l ON l.code = p.lang WHERE p.lang <> 'en';
INSERT INTO candidate_language (candidate_profile_id, language_id, language_proficiency_level_id, can_read, can_write, can_speak)
SELECT p.profile_id, (SELECT id FROM language WHERE code = 'hi'), 3, seed.r(p.g, 61) < 0.8, seed.r(p.g, 61) < 0.6, true
FROM seed.cand_p p WHERE p.lang NOT IN ('hi', 'mr') AND seed.r(p.g, 62) < 0.40;

INSERT INTO candidate_preferred_location (candidate_profile_id, city_id, sort_order)
SELECT profile_id, city_id, 1 FROM seed.cand_p;
INSERT INTO candidate_preferred_location (candidate_profile_id, city_id, sort_order)
SELECT p.profile_id, cr.city_id, 2 FROM seed.cand_p p JOIN seed.city_rank cr ON cr.rank = seed.skew(20, p.g, 63)
WHERE seed.r(p.g, 64) < 0.50 AND cr.city_id <> p.city_id;

INSERT INTO resume (candidate_profile_id, title, is_default)
SELECT profile_id, 'My resume', true FROM seed.cand_p WHERE seed.r(g, 65) < 0.70;
INSERT INTO resume_version (resume_id, version_number, storage_uri, file_name, mime_type, file_size_bytes, content_sha256)
SELECT r.id, v, 's3://talentra-resumes/' || r.candidate_profile_id || '/v' || v || '.pdf', 'resume_v' || v || '.pdf', 'application/pdf',
       40000 + floor(seed.r(r.id * 2 + v, 66) * 400000)::int, md5(r.id || ':' || v) || md5(v || ':' || r.id)
FROM resume r CROSS JOIN generate_series(1, 2) v
WHERE v = 1 OR seed.r(r.id, 67) < 0.35;

DO $$
BEGIN
    PERFORM seed.done('profile: user accounts', (SELECT count(*) FROM seed.cand_user));
    PERFORM seed.done('profile: candidate profiles', (SELECT count(*) FROM candidate_profile));
    PERFORM seed.done('profile: duplicates (flagged + unflagged)', (SELECT count(*) FROM seed.cand WHERE dup_of_g IS NOT NULL));
    PERFORM seed.done('profile: emails + phones', (SELECT count(*) FROM candidate_email) + (SELECT count(*) FROM candidate_phone));
    PERFORM seed.done('profile: skills', (SELECT count(*) FROM candidate_skill));
    PERFORM seed.done('profile: education + work', (SELECT count(*) FROM candidate_education) + (SELECT count(*) FROM candidate_work_experience));
    PERFORM seed.done('profile: languages + locations', (SELECT count(*) FROM candidate_language) + (SELECT count(*) FROM candidate_preferred_location));
    PERFORM seed.done('profile: resumes + versions', (SELECT count(*) FROM resume) + (SELECT count(*) FROM resume_version));
END $$;
