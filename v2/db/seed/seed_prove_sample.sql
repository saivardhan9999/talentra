-- Talentra v2 — Phase 3 (Prove · Step 14) Discovery & Golden Sample Dataset ("testing-only data").
-- Purpose: A compact, deterministic, fast-loading dataset (~30 candidate profiles, 6 organisations, 12 job requirements,
-- 36 applications, ~420 business rows total) that exercises 100% of entities, 100% of lookup states, 100% of allowed
-- state transitions, all 9 actor roles, all 6 planted data-quality findings (F-01..F-06), known golden query answers,
-- and a companion negative-test block of 16 deliberate invalid rows proven to be rejected by the database.
--
-- Usage:
--   psql -v ON_ERROR_STOP=1 -f v2/db/seed/seed_prove_sample.sql

SET client_min_messages = warning;
SET app.hmac_key = 'prove-phase-sample-hmac-key';
SELECT setseed(0.314159);

CREATE FUNCTION pg_temp.sha(t text) RETURNS bytea LANGUAGE sql IMMUTABLE AS $$ SELECT sha256(convert_to(t, 'UTF8')) $$;

\set pw '''$argon2id$v=19$m=65536,t=3,p=4$c2VlZHNhbHRzZWVkc2FsdA$c2VlZGhhc2hzZWVkaGFzaHNlZWRoYXNoc2VlZGhhc2g'''

------------------------------------------------------------------------------------------------------------------------
-- 1. Platform staff, consultants, and placement officers (actors 1, 2, 6, 7)
------------------------------------------------------------------------------------------------------------------------
INSERT INTO app_user (email, phone_e164, phone_country_id, preferred_language_id, created_at, last_login_at) VALUES
  ('superadmin@talentra.test', '+919000000001', 1, 1, '2026-01-01 09:00:00+00', '2026-10-25 09:00:00+00'),
  ('admin@talentra.test',      '+919000000002', 1, 1, '2026-01-01 09:05:00+00', '2026-10-25 09:05:00+00'),
  ('consultant1@partner.test', '+919000000003', 1, 1, '2026-01-10 10:00:00+00', '2026-10-24 11:00:00+00'),
  ('consultant2@partner.test', '+919000000004', 1, 2, '2026-01-12 10:00:00+00', '2026-10-20 11:00:00+00'),
  ('tpo1@partner.test',        '+919000000005', 1, 3, '2026-01-15 10:00:00+00', '2026-10-21 11:00:00+00');

INSERT INTO user_credential (app_user_id, password_hash, created_at, created_by)
SELECT id, :pw, created_at, id FROM app_user;

INSERT INTO user_access_role (app_user_id, access_role_id, created_at, created_by)
SELECT id,
       CASE email
         WHEN 'superadmin@talentra.test' THEN 1
         WHEN 'admin@talentra.test'      THEN 2
         WHEN 'consultant1@partner.test' THEN 6
         WHEN 'consultant2@partner.test' THEN 6
         WHEN 'tpo1@partner.test'        THEN 7
       END,
       created_at, id
FROM app_user;

------------------------------------------------------------------------------------------------------------------------
-- 2. Candidate users and profiles (30 candidates: cand1..cand30@mail.test, actor 8)
-- Covers:
--   - Multilingual scripts: Latin, Devanagari ('राहुल शर्मा', 'प्रिया वर्मा'), Tamil ('கார்த்திக் சுப்பிரமணியம்', 'லக்ஷ்மி நாராயணன்'), mononyms ('Murugan', 'Selvi')
--   - All 3 profile_visibility values: public (1), recruiters_only (2), hidden (3)
--   - All 3 salary_disclosure values: disclosed (1), not_disclosed (2), not_provided (3)
--   - All 4 account_status values: active (1), suspended (2 on cand28), deactivated (3 on cand29), erased (4 on cand30 via candidate_erase)
--   - Finding F-01: cand2 shares phone + full_name with cand1 ('Priya Sharma', '+919845011101')
--   - Finding F-02: cand5 and cand6 have current_city_id IS NULL
--   - Finding F-03: cand7 states total_experience_months = 12 but has 36 months of work history
--   - Finding F-06: cand8 and cand9 have is_open_to_work = true but last_active_at > 90 days ago
------------------------------------------------------------------------------------------------------------------------
CREATE TEMP TABLE seed_cand (
    idx int PRIMARY KEY,
    email text,
    phone text,
    lang smallint,
    full_name text,
    headline text,
    city_id int,
    exp_months smallint,
    sal_amount numeric(14,2),
    sal_disc smallint,
    notice smallint,
    open_work boolean,
    vis smallint,
    created_at timestamptz,
    last_active timestamptz
);

INSERT INTO seed_cand VALUES
  (1,  'cand1@mail.test',  '+919845011101', 1, 'Priya Sharma',              'Senior Java & Spring Boot Engineer', 1,  60, 1800000.00, 1, 30, true,  1, '2026-02-01 08:00:00+00', '2026-10-24 14:00:00+00'),
  (2,  'cand2@mail.test',  '+919845011101', 1, 'Priya Sharma',              'Java Backend Developer',             1,  48, 1500000.00, 1, 15, true,  1, '2026-02-02 08:00:00+00', '2026-10-23 14:00:00+00'), -- F-01 duplicate phone+name
  (3,  'cand3@mail.test',  '+919845011103', 2, 'राहुल शर्मा',                 'Python & Data Analyst',              4,  36,  950000.00, 1, 30, true,  1, '2026-02-03 08:00:00+00', '2026-10-22 14:00:00+00'),
  (4,  'cand4@mail.test',  '+919845011104', 3, 'கார்த்திக் சுப்பிரமணியம்',      'React & TypeScript Frontend',        8,  42, 1200000.00, 1,  0, true,  2, '2026-02-04 08:00:00+00', '2026-10-21 14:00:00+00'),
  (5,  'cand5@mail.test',  '+919845011105', 1, 'Arjun Reddy',               'DevOps & Kubernetes Specialist',     NULL,72, 2200000.00, 1, 60, true,  1, '2026-02-05 08:00:00+00', '2026-10-20 14:00:00+00'), -- F-02 NULL city
  (6,  'cand6@mail.test',  '+919845011106', 1, 'Murugan',                   'CNC Machine Operator',               NULL,84, NULL,       2, 15, true,  1, '2026-02-06 08:00:00+00', '2026-10-19 14:00:00+00'), -- F-02 NULL city + mononym
  (7,  'cand7@mail.test',  '+919845011107', 1, 'Ananya Iyer',               'Full Stack Engineer',                12, 12,  800000.00, 1, 30, true,  1, '2026-02-07 08:00:00+00', '2026-10-18 14:00:00+00'), -- F-03 experience mismatch
  (8,  'cand8@mail.test',  '+919845011108', 1, 'Vikram Singh',              'Logistics & Warehouse Supervisor',   14, 96,  600000.00, 1, 30, true,  1, '2026-02-08 08:00:00+00', '2026-05-01 10:00:00+00'), -- F-06 stale open_to_work
  (9,  'cand9@mail.test',  '+919845011109', 2, 'प्रिया वर्मा',                'Staff Nurse (ICU)',                  5,  48,  480000.00, 1, 15, true,  2, '2026-02-09 08:00:00+00', '2026-05-10 10:00:00+00'), -- F-06 stale open_to_work
  (10, 'cand10@mail.test', '+919845011110', 3, 'லக்ஷ்மி நாராயணன்',           'Senior Accountant & GST Specialist', 8,  66, NULL,       2, 45, false, 3, '2026-02-10 08:00:00+00', '2026-10-15 14:00:00+00'), -- hidden profile
  (11, 'cand11@mail.test', '+919845011111', 1, 'Siddharth Menon',           'QA Automation Engineer (Selenium)',  1,  30,  750000.00, 1, 30, true,  1, '2026-02-11 08:00:00+00', '2026-10-16 14:00:00+00'),
  (12, 'cand12@mail.test', '+919845011112', 1, 'Neha Gupta',                'Android & Kotlin Developer',         25, 36, 1100000.00, 1, 15, true,  1, '2026-02-12 08:00:00+00', '2026-10-17 14:00:00+00'),
  (13, 'cand13@mail.test', '+919845011113', 1, 'Mohammed Ansari',           'Last-Mile Delivery Executive',       4,  18, NULL,       3,  0, true,  1, '2026-02-13 08:00:00+00', '2026-10-18 14:00:00+00'),
  (14, 'cand14@mail.test', '+919845011114', 1, 'Selvi',                     'Retail Sales Associate',             8,  12, NULL,       3,  0, true,  1, '2026-02-14 08:00:00+00', '2026-10-19 14:00:00+00'),
  (15, 'cand15@mail.test', '+919845011115', 1, 'Rohan Deshpande',           'Cloud Architect (AWS & GCP)',        5, 108, 3200000.00, 1, 90, false, 2, '2026-02-15 08:00:00+00', '2026-10-20 14:00:00+00'),
  (16, 'cand16@mail.test', '+919845011116', 1, 'Kavya Nair',                'HR Operations & Payroll Specialist', 22, 40,  650000.00, 1, 30, true,  1, '2026-02-16 08:00:00+00', '2026-10-21 14:00:00+00'),
  (17, 'cand17@mail.test', '+919845011117', 1, 'Deepak Kulkarni',           'Mechanical Maintenance Engineer',    5,  54,  720000.00, 1, 30, true,  1, '2026-02-17 08:00:00+00', '2026-10-22 14:00:00+00'),
  (18, 'cand18@mail.test', '+919845011118', 1, 'Fatima Khan',               'Clinical Pharmacist',                12, 24,  420000.00, 1, 15, true,  1, '2026-02-18 08:00:00+00', '2026-10-23 14:00:00+00'),
  (19, 'cand19@mail.test', '+919845011119', 1, 'Harpreet Gill',             'Heavy Vehicle Driver (HMV)',         28, 120, 360000.00, 1,  0, true,  1, '2026-02-19 08:00:00+00', '2026-10-24 14:00:00+00'),
  (20, 'cand20@mail.test', '+919845011120', 1, 'Meera Krishnan',            'Product Manager — FinTech',          1,  84, 2800000.00, 1, 60, false, 3, '2026-02-20 08:00:00+00', '2026-10-24 15:00:00+00'), -- hidden profile
  (21, 'cand21@mail.test', NULL,            1, 'Aditya Verma',              'Graduate Software Intern',           15,  0, NULL,       3,  0, true,  1, '2026-02-21 08:00:00+00', '2026-10-24 16:00:00+00'), -- NULL phone
  (22, 'cand22@mail.test', '+919845011122', 1, 'Pooja Agarwal',             'Digital Marketing Specialist',       4,  36,  700000.00, 1, 30, true,  1, '2026-02-22 08:00:00+00', '2026-10-24 17:00:00+00'),
  (23, 'cand23@mail.test', '+919845011123', 1, 'Suresh Naidu',              'Site Civil Supervisor',              12, 72,  680000.00, 1, 15, true,  1, '2026-02-23 08:00:00+00', '2026-10-24 18:00:00+00'),
  (24, 'cand24@mail.test', '+919845011124', 1, 'Divya Menon',               'Customer Support Lead',              1,  48,  550000.00, 1, 30, true,  1, '2026-02-24 08:00:00+00', '2026-10-24 19:00:00+00'),
  (25, 'cand25@mail.test', '+919845011125', 1, 'Karthik Subramanian',       'Go & PostgreSQL Backend Engineer',   1,  60, 2100000.00, 1, 30, true,  1, '2026-02-25 08:00:00+00', '2026-10-25 08:00:00+00'),
  (26, 'cand26@mail.test', '+919845011126', 1, 'Sneha Banerjee',            'Business Analyst',                   18, 36,  900000.00, 1, 30, true,  2, '2026-02-26 08:00:00+00', '2026-10-25 08:30:00+00'),
  (27, 'cand27@mail.test', '+919845011127', 1, 'Manoj Joshi',               'Electrical Maintenance Technician',  19, 48, NULL,       2, 15, true,  1, '2026-02-27 08:00:00+00', '2026-10-25 09:00:00+00'), -- withdraws purpose 3 consent below
  (28, 'cand28@mail.test', '+919845011128', 1, 'Ramesh Kumar',              'Suspended Account Candidate',        1,  24,  500000.00, 1, 30, false, 1, '2026-02-28 08:00:00+00', '2026-09-01 09:00:00+00'), -- suspended
  (29, 'cand29@mail.test', '+919845011129', 1, 'Sunita Rao',                'Deactivated Account Candidate',      4,  36,  600000.00, 1, 30, false, 1, '2026-03-01 08:00:00+00', '2026-09-15 09:00:00+00'), -- deactivated
  (30, 'cand30@mail.test', '+919845011130', 1, 'Candidate To Be Erased',    'Will exercise DPDP erasure',         1,  24,  700000.00, 1, 15, true,  1, '2026-03-02 08:00:00+00', '2026-10-01 09:00:00+00'); -- erased via candidate_erase()

INSERT INTO app_user (email, phone_e164, phone_country_id, preferred_language_id, created_at, last_login_at)
SELECT email, phone, CASE WHEN phone IS NOT NULL THEN 1 END, lang, created_at, last_active
FROM seed_cand ORDER BY idx;

CREATE TEMP TABLE cand_map AS
SELECT sc.*, u.id AS app_user_id
FROM seed_cand sc JOIN app_user u ON u.email = sc.email;

INSERT INTO user_credential (app_user_id, password_hash, created_at, created_by)
SELECT app_user_id, :pw, created_at, app_user_id FROM cand_map;

-- Lock out cand26's credential via auth_record_login_failure to cover lockout state in sample data
SELECT auth_record_login_failure((SELECT app_user_id FROM cand_map WHERE idx = 26), 2::smallint, interval '30 minutes');
SELECT auth_record_login_failure((SELECT app_user_id FROM cand_map WHERE idx = 26), 2::smallint, interval '30 minutes');

INSERT INTO user_access_role (app_user_id, access_role_id, created_at, created_by)
SELECT app_user_id, 8, created_at, app_user_id FROM cand_map;

-- Consent records: purposes 1 (terms), 2 (privacy), 3 (recruiter visibility) granted by all 30 at sign-up;
-- purpose 4 (marketing_email) granted by idx 1..15; purpose 5 (whatsapp_alerts) granted by idx 1..10.
INSERT INTO consent_record (app_user_id, consent_purpose_id, is_granted, policy_version, recorded_at, ip_address, created_at, created_by)
SELECT app_user_id, p, true, '2026-01', created_at, ('10.0.1.' || idx)::inet, created_at, app_user_id
FROM cand_map CROSS JOIN (VALUES (1), (2), (3)) v(p)
UNION ALL
SELECT app_user_id, 4, idx <= 15, '2026-01', created_at, ('10.0.1.' || idx)::inet, created_at, app_user_id
FROM cand_map
UNION ALL
SELECT app_user_id, 5, idx <= 10, '2026-01', created_at, ('10.0.1.' || idx)::inet, created_at, app_user_id
FROM cand_map;

-- Withdrawals of consent (history): cand3 withdraws marketing (4); cand27 withdraws profile_visible_to_recruiters (3)
INSERT INTO consent_record (app_user_id, consent_purpose_id, is_granted, policy_version, recorded_at, created_at, created_by)
SELECT app_user_id, 4, false, '2026-01', created_at + interval '30 days', created_at + interval '30 days', app_user_id
FROM cand_map WHERE idx = 3
UNION ALL
SELECT app_user_id, 3, false, '2026-01', created_at + interval '30 days', created_at + interval '30 days', app_user_id
FROM cand_map WHERE idx = 27;

INSERT INTO candidate_profile (app_user_id, full_name, headline, summary, profile_language_id, current_city_id,
    total_experience_months, expected_salary_amount, expected_salary_currency_id, salary_disclosure_id,
    notice_period_days, is_open_to_work, profile_visibility_id, last_active_at, created_at, created_by)
SELECT app_user_id, full_name, headline,
       'Experienced professional: ' || headline || '.',
       lang, city_id, exp_months, sal_amount,
       CASE WHEN sal_amount IS NOT NULL THEN 1 END,
       sal_disc, notice, open_work, vis, last_active, created_at, app_user_id
FROM cand_map ORDER BY idx;

ALTER TABLE cand_map ADD COLUMN profile_id bigint;
UPDATE cand_map cm SET profile_id = p.id FROM candidate_profile p WHERE p.app_user_id = cm.app_user_id;

-- Education, experience, skills, languages, resumes
INSERT INTO candidate_education (candidate_profile_id, qualification_id, institution_name, field_of_study, start_date, end_date, created_at, created_by)
SELECT profile_id,
       CASE WHEN idx % 4 = 0 THEN 7 WHEN idx % 5 = 0 THEN 4 ELSE 6 END,
       CASE WHEN idx % 2 = 0 THEN 'Anna University' ELSE 'Visvesvaraya Technological University' END,
       'Computer Science & Engineering',
       date '2016-07-01', date '2020-05-31', created_at, app_user_id
FROM cand_map;

-- Work experience: note idx = 7 (Ananya Iyer) has 36 months of history vs 12 months stated on profile (Finding F-03)
INSERT INTO candidate_experience (candidate_profile_id, company_name, job_title, employment_type_id, start_date, end_date, description, created_at, created_by)
SELECT profile_id,
       CASE WHEN idx % 3 = 0 THEN 'Infosys' WHEN idx % 3 = 1 THEN 'TCS' ELSE 'Wipro' END,
       headline, 1,
       CASE WHEN idx = 7 THEN current_date - interval '38 months' ELSE current_date - make_interval(months => greatest(exp_months, 12)) END::date,
       CASE WHEN idx % 3 = 0 THEN NULL ELSE (current_date - interval '2 months')::date END,
       'Delivered core platform features and maintained SLAs.',
       created_at, app_user_id
FROM cand_map WHERE exp_months > 0;

INSERT INTO candidate_skill (candidate_profile_id, skill_id, proficiency_level_id, experience_months, created_at, created_by)
SELECT profile_id, s_id, 3, greatest(12, exp_months - 6), created_at, app_user_id
FROM cand_map
CROSS JOIN LATERAL (VALUES (1), (5), (6), (11)) v(s_id)
WHERE idx <= 15
UNION ALL
SELECT profile_id, s_id, 4, greatest(6, exp_months), created_at, app_user_id
FROM cand_map
CROSS JOIN LATERAL (VALUES (2), (8), (16), (30)) v(s_id)
WHERE idx > 15;

INSERT INTO candidate_language (candidate_profile_id, language_id, proficiency_level_id, created_at, created_by)
SELECT profile_id, 1, 4, created_at, app_user_id FROM cand_map
UNION ALL
SELECT profile_id, CASE WHEN lang > 1 THEN lang ELSE 2 END, 5, created_at, app_user_id FROM cand_map;

INSERT INTO resume (candidate_profile_id, version_number, storage_key, file_sha256, content_language_id, is_primary, created_at, created_by)
SELECT profile_id, 1,
       'resumes/' || profile_id || '/00000000-0000-4000-8000-' || lpad(idx::text, 12, '0') || '.pdf',
       pg_temp.sha('resume-v1-' || profile_id), 1, true, created_at, app_user_id
FROM cand_map WHERE idx <= 28;

------------------------------------------------------------------------------------------------------------------------
-- 3. Six Organisations across all 3 plans & all 3 verification statuses
--   Org 1: Apex Technologies (Verified, Growth plan — 5 seats, 2 devices/user, 300 credits + 100 recharged)
--   Org 2: Blue River Finserv (Verified, Enterprise plan — 15 seats, 3 devices/user, 2000 credits, parent of Org 3)
--   Org 3: Crescent Logistics (Verified, Starter plan — 2 seats, 1 device/user, 50 credits, child of Org 2, FULL on seats)
--   Org 4: Deccan Healthcare (Pending verification — Finding F-05: has an open job while verification_status_id = 1)
--   Org 5: Everest Manufacturing (Rejected verification — verification_status_id = 3)
--   Org 6: Falcon Retail (Verified, expired subscription — Finding F-04: 2 active members on lapsed subscription -> seat limit 1)
------------------------------------------------------------------------------------------------------------------------
CREATE TEMP TABLE seed_org (
    org_idx int PRIMARY KEY,
    admin_email text,
    legal_name text,
    display_name text,
    industry_id smallint,
    ver_status smallint,
    city_id int,
    gstin text,
    created_at timestamptz
);

INSERT INTO seed_org VALUES
  (1, 'admin@org1.test', 'Apex Technologies Private Limited',     'Apex Technologies',     1, 2, 1,  '29AABCA1111A1Z5', '2026-01-20 09:00:00+00'),
  (2, 'admin@org2.test', 'Blue River Finserv Private Limited',    'Blue River Finserv',    2, 2, 4,  '27AABCB2222B1Z5', '2026-01-22 09:00:00+00'),
  (3, 'admin@org3.test', 'Crescent Logistics Private Limited',    'Crescent Logistics',    7, 2, 12, '36AABCC3333C1Z5', '2026-01-25 09:00:00+00'),
  (4, 'admin@org4.test', 'Deccan Healthcare Private Limited',     'Deccan Healthcare',     3, 1, 8,  '33AABCD4444D1Z5', '2026-01-28 09:00:00+00'),
  (5, 'admin@org5.test', 'Everest Manufacturing Private Limited', 'Everest Manufacturing', 4, 3, 5,  '27AABCE5555E1Z5', '2026-02-01 09:00:00+00'),
  (6, 'admin@org6.test', 'Falcon Retail Private Limited',         'Falcon Retail',         5, 2, 14, '07AABCF6666F1Z5', '2026-01-05 09:00:00+00');

INSERT INTO app_user (email, phone_e164, phone_country_id, created_at)
SELECT admin_email, '+91970000000' || org_idx, 1, created_at FROM seed_org ORDER BY org_idx;

CREATE TEMP TABLE org_map AS
SELECT so.*, u.id AS admin_user_id
FROM seed_org so JOIN app_user u ON u.email = so.admin_email;

INSERT INTO user_credential (app_user_id, password_hash, created_at, created_by)
SELECT admin_user_id, :pw, created_at, admin_user_id FROM org_map;

INSERT INTO user_access_role (app_user_id, access_role_id, created_at, created_by)
SELECT admin_user_id, 3, created_at, admin_user_id FROM org_map;

INSERT INTO organisation (legal_name, display_name, industry_id, country_id, website_url, verification_status_id, verified_at, created_at, created_by)
SELECT legal_name, display_name, industry_id, 1,
       'https://www.' || lower(replace(display_name, ' ', '')) || '.test',
       ver_status, CASE WHEN ver_status = 2 THEN created_at + interval '1 day' END,
       created_at, admin_user_id
FROM org_map ORDER BY org_idx;

ALTER TABLE org_map ADD COLUMN org_id bigint;
UPDATE org_map om SET org_id = o.id FROM organisation o WHERE o.legal_name = om.legal_name;

-- Set Org 3's parent to Org 2 (tests parent_organisation_id hierarchy)
UPDATE organisation SET parent_organisation_id = (SELECT org_id FROM org_map WHERE org_idx = 2)
WHERE id = (SELECT org_id FROM org_map WHERE org_idx = 3);

-- Wallets are automatically created by trg_organisation_ensure_wallet (V013), or we ensure created_at matches
UPDATE wallet w SET created_at = om.created_at, created_by = om.admin_user_id
FROM org_map om WHERE w.organisation_id = om.org_id;

INSERT INTO organisation_location (organisation_id, city_id, address_line, postal_code, latitude, longitude, is_headquarters, created_at, created_by)
SELECT om.org_id, c.id, '100 Corporate Park, ' || c.name, '560001', c.latitude, c.longitude, true, om.created_at, om.admin_user_id
FROM org_map om JOIN city c ON c.id = om.city_id;

INSERT INTO organisation_tax_identifier (organisation_id, country_id, tax_identifier_type_id, identifier_hmac, identifier_last4,
                                         verification_status_id, verified_at, created_at, created_by)
SELECT org_id, 1, 1, pii_hmac(gstin), right(gstin, 4), ver_status,
       CASE WHEN ver_status = 2 THEN created_at + interval '1 day' END, created_at, admin_user_id
FROM org_map;

INSERT INTO organisation_member (organisation_id, app_user_id, access_role_id, valid_from, created_at, created_by)
SELECT org_id, admin_user_id, 3, created_at, created_at, admin_user_id FROM org_map;

------------------------------------------------------------------------------------------------------------------------
-- 4. Subscriptions, payment orders, payment events, wallet recharges, and refunds
-- Covers all 5 payment_status values: created (1), authorised (2), captured (3), failed (4), refunded (5)
-- Covers all 6 ledger_entry_type values: recharge (1), plan_grant (2), job_post_debit (3), profile_download_debit (4),
-- outreach_debit (5), reversal (6)
------------------------------------------------------------------------------------------------------------------------
DO $$
DECLARE
  o1 bigint := (SELECT org_id FROM org_map WHERE org_idx = 1);
  o2 bigint := (SELECT org_id FROM org_map WHERE org_idx = 2);
  o3 bigint := (SELECT org_id FROM org_map WHERE org_idx = 3);
  o4 bigint := (SELECT org_id FROM org_map WHERE org_idx = 4);
  o6 bigint := (SELECT org_id FROM org_map WHERE org_idx = 6);
  ord bigint;
  w1 bigint := (SELECT id FROM wallet WHERE organisation_id = o1);
BEGIN
  -- Org 1: Growth plan (id=2, 24999.00, 3 months, 5 seats, 2 devices, 300 credits) — active now
  INSERT INTO payment_order (organisation_id, payment_purpose_id, amount, currency_id, plan_id, gateway_order_ref, idempotency_key, created_at)
  VALUES (o1, 2, 24999.00, 1, 2, 'order_org1_sub', 'prove-ord-org1-sub', current_date - interval '30 days') RETURNING id INTO ord;
  PERFORM billing_apply_payment_event(ord, 'authorised', 'evt_org1_sub_a', 24999.00, current_date - interval '30 days' + interval '1 minute', pg_temp.sha('evt1a'));
  PERFORM billing_apply_payment_event(ord, 'captured',   'evt_org1_sub_c', 24999.00, current_date - interval '30 days' + interval '2 minutes', pg_temp.sha('evt1c'));

  -- Org 1: Wallet recharge of 100 credits (5000.00) — captured
  INSERT INTO payment_order (organisation_id, payment_purpose_id, amount, currency_id, credits_to_grant, gateway_order_ref, idempotency_key, created_at)
  VALUES (o1, 1, 5000.00, 1, 100, 'order_org1_rec', 'prove-ord-org1-rec', current_date - interval '25 days') RETURNING id INTO ord;
  PERFORM billing_apply_payment_event(ord, 'captured', 'evt_org1_rec_c', 5000.00, current_date - interval '25 days' + interval '1 minute', pg_temp.sha('evt1rc'));

  -- Org 1: Outreach debit (-5 credits) so all 6 ledger_entry_type codes are present in the golden sample
  PERFORM wallet_post(w1, 'outreach_debit', -5, 'prove-outreach-org1-1', p_occurred_at => current_date - interval '20 days');

  -- Org 2: Enterprise plan (id=3, 199999.00, 12 months, 15 seats, 3 devices, 2000 credits) — active now
  INSERT INTO payment_order (organisation_id, payment_purpose_id, amount, currency_id, plan_id, gateway_order_ref, idempotency_key, created_at)
  VALUES (o2, 2, 199999.00, 1, 3, 'order_org2_sub', 'prove-ord-org2-sub', current_date - interval '40 days') RETURNING id INTO ord;
  PERFORM billing_apply_payment_event(ord, 'captured', 'evt_org2_sub_c', 199999.00, current_date - interval '40 days' + interval '1 minute', pg_temp.sha('evt2c'));

  -- Org 2: Recharge that was subsequently refunded (covers payment_status = 5 refunded & ledger_entry_type = 6 reversal)
  INSERT INTO payment_order (organisation_id, payment_purpose_id, amount, currency_id, credits_to_grant, gateway_order_ref, idempotency_key, created_at)
  VALUES (o2, 1, 2500.00, 1, 50, 'order_org2_ref', 'prove-ord-org2-ref', current_date - interval '15 days') RETURNING id INTO ord;
  PERFORM billing_apply_payment_event(ord, 'captured', 'evt_org2_ref_c', 2500.00, current_date - interval '15 days' + interval '1 minute', pg_temp.sha('evt2rc'));
  PERFORM billing_apply_payment_event(ord, 'refunded', 'evt_org2_ref_r', 2500.00, current_date - interval '15 days' + interval '5 minutes', pg_temp.sha('evt2rr'));

  -- Org 3: Starter plan (id=1, 4999.00, 1 month, 2 seats, 1 device, 50 credits) — active now
  INSERT INTO payment_order (organisation_id, payment_purpose_id, amount, currency_id, plan_id, gateway_order_ref, idempotency_key, created_at)
  VALUES (o3, 2, 4999.00, 1, 1, 'order_org3_sub', 'prove-ord-org3-sub', current_date - interval '10 days') RETURNING id INTO ord;
  PERFORM billing_apply_payment_event(ord, 'captured', 'evt_org3_sub_c', 4999.00, current_date - interval '10 days' + interval '1 minute', pg_temp.sha('evt3c'));

  -- Org 4 (pending verification): Wallet recharge of 50 credits so it can publish an open job (Finding F-05)
  INSERT INTO payment_order (organisation_id, payment_purpose_id, amount, currency_id, credits_to_grant, gateway_order_ref, idempotency_key, created_at)
  VALUES (o4, 1, 2500.00, 1, 50, 'order_org4_rec', 'prove-ord-org4-rec', current_date - interval '20 days') RETURNING id INTO ord;
  PERFORM billing_apply_payment_event(ord, 'captured', 'evt_org4_rec_c', 2500.00, current_date - interval '20 days' + interval '1 minute', pg_temp.sha('evt4c'));

  -- Org 6: Historical Starter subscription that lapsed 60 days ago (for Finding F-04: over-seat after lapse)
  INSERT INTO payment_order (organisation_id, payment_purpose_id, amount, currency_id, plan_id, gateway_order_ref, idempotency_key, created_at)
  VALUES (o6, 2, 4999.00, 1, 1, 'order_org6_sub', 'prove-ord-org6-sub', current_date - interval '120 days') RETURNING id INTO ord;
  PERFORM billing_apply_payment_event(ord, 'captured', 'evt_org6_sub_c', 4999.00, current_date - interval '120 days' + interval '1 minute', pg_temp.sha('evt6c'));

  -- Additional payment orders to cover payment_status = 1 (created), 2 (authorised), 4 (failed)
  INSERT INTO payment_order (organisation_id, payment_purpose_id, amount, currency_id, credits_to_grant, gateway_order_ref, idempotency_key, created_at)
  VALUES (o1, 1, 1000.00, 1, 20, 'order_org1_created', 'prove-ord-org1-created', now() - interval '1 hour');

  INSERT INTO payment_order (organisation_id, payment_purpose_id, amount, currency_id, credits_to_grant, gateway_order_ref, idempotency_key, created_at)
  VALUES (o1, 1, 1500.00, 1, 30, 'order_org1_auth', 'prove-ord-org1-auth', now() - interval '2 hours') RETURNING id INTO ord;
  PERFORM billing_apply_payment_event(ord, 'authorised', 'evt_org1_auth_only', 1500.00, now() - interval '110 minutes', pg_temp.sha('evt1ao'));

  INSERT INTO payment_order (organisation_id, payment_purpose_id, amount, currency_id, credits_to_grant, gateway_order_ref, idempotency_key, created_at)
  VALUES (o3, 1, 2000.00, 1, 40, 'order_org3_fail', 'prove-ord-org3-fail', now() - interval '3 hours') RETURNING id INTO ord;
  PERFORM billing_apply_payment_event(ord, 'failed', 'evt_org3_fail_f', 2000.00, now() - interval '175 minutes', pg_temp.sha('evt3ff'));
END $$;

------------------------------------------------------------------------------------------------------------------------
-- 5. Organisation members (employers and recruiters — actors 4 & 5)
--   - Org 1 (max_seats = 5): has admin + 1 employer + 1 active recruiter + 1 past recruiter (valid_to set) = 3 current members (< 5, free_org for t02)
--   - Org 2 (max_seats = 15): has admin + 1 active recruiter = 2 current members
--   - Org 3 (max_seats = 2): has admin + 1 active recruiter = 2 current members (FULL on seats, full_org for t02)
--   - Org 6 (lapsed sub, joined while active): has admin + 1 active recruiter added during the active subscription window (Finding F-04: 2 > 1 unsubscribed seat limit today)
------------------------------------------------------------------------------------------------------------------------
INSERT INTO app_user (email, phone_e164, phone_country_id, created_at) VALUES
  ('emp1@org1.test',      '+919700000101', 1, current_date - interval '28 days'),
  ('rec1@org1.test',      '+919700000102', 1, current_date - interval '28 days'),
  ('rec_past@org1.test',  '+919700000103', 1, current_date - interval '28 days'),
  ('rec1@org2.test',      '+919700000201', 1, current_date - interval '35 days'),
  ('rec1@org3.test',      '+919700000301', 1, current_date - interval '9 days'),
  ('rec1@org6.test',      '+919700000601', 1, current_date - interval '110 days');

INSERT INTO user_credential (app_user_id, password_hash, created_at, created_by)
SELECT id, :pw, created_at, id FROM app_user WHERE email LIKE '%@org%.test' AND email NOT LIKE 'admin@%';

INSERT INTO user_access_role (app_user_id, access_role_id, created_at, created_by)
SELECT id, CASE WHEN email LIKE 'emp%' THEN 4 ELSE 5 END, created_at, id
FROM app_user WHERE email LIKE '%@org%.test' AND email NOT LIKE 'admin@%';

INSERT INTO organisation_member (organisation_id, app_user_id, access_role_id, valid_from, valid_to, created_at, created_by)
SELECT (SELECT org_id FROM org_map WHERE org_idx = 1), id, 4, created_at, NULL::timestamptz, created_at, id FROM app_user WHERE email = 'emp1@org1.test'
UNION ALL
SELECT (SELECT org_id FROM org_map WHERE org_idx = 1), id, 5, created_at, NULL::timestamptz, created_at, id FROM app_user WHERE email = 'rec1@org1.test'
UNION ALL
SELECT (SELECT org_id FROM org_map WHERE org_idx = 1), id, 5, created_at, (current_date - interval '5 days')::timestamptz, created_at, id FROM app_user WHERE email = 'rec_past@org1.test'
UNION ALL
SELECT (SELECT org_id FROM org_map WHERE org_idx = 2), id, 5, created_at, NULL::timestamptz, created_at, id FROM app_user WHERE email = 'rec1@org2.test'
UNION ALL
SELECT (SELECT org_id FROM org_map WHERE org_idx = 3), id, 5, created_at, NULL::timestamptz, created_at, id FROM app_user WHERE email = 'rec1@org3.test'
UNION ALL
SELECT (SELECT org_id FROM org_map WHERE org_idx = 6), id, 5, created_at, NULL::timestamptz, created_at, id FROM app_user WHERE email = 'rec1@org6.test';

------------------------------------------------------------------------------------------------------------------------
-- 6. Twelve Job Requirements across all 5 job_status values (draft=1, open=2, paused=3, closed=4, filled=5)
--   J1  (Org 1): Open, NOT open to consultants, closes_on IS NULL, 3 positions (matches t02 :job_open)
--   J2  (Org 1): Open, open to consultants = true, closes_on in future, 2 positions
--   J3  (Org 1): Open -> will become FILLED (status 5) when 1 application reaches joined (positions_total = 1)
--   J4  (Org 1): Open -> will be PAUSED (status 3) after applications
--   J5  (Org 1): Open -> will be CLOSED (status 4) after applications (matches t02 :job_closed)
--   J6  (Org 1): Draft (status 1, published_at IS NULL, never charged)
--   J7  (Org 2): Open, NOT open to consultants, closes_on IS NULL, 2 positions (matches t03 :job_other)
--   J8  (Org 2): Draft (status 1, matches t03 :draft_other)
--   J9  (Org 2): Open -> CLOSED and soft-deleted (deleted_at IS NOT NULL)
--   J10 (Org 3): Open, open to consultants = true, 2 positions
--   J11 (Org 4 - unverified): Open (Finding F-05: open job from unverified organisation)
--   J12 (Org 6): Open -> PAUSED
------------------------------------------------------------------------------------------------------------------------
CREATE TEMP TABLE seed_job (
    job_idx int PRIMARY KEY,
    org_idx int,
    title text,
    emp_type smallint,
    work_mode smallint,
    industry_id smallint,
    min_exp smallint,
    max_exp smallint,
    sal_min numeric(14,2),
    sal_max numeric(14,2),
    sal_disc smallint,
    pos_total smallint,
    init_status smallint,
    consultants boolean,
    pub_at timestamptz,
    closes_on date,
    city_id int,
    skill_id int
);

INSERT INTO seed_job VALUES
  (1,  1, 'Java Backend Developer',          1, 3, 1, 24, 60, 1200000.00, 1800000.00, 1, 3, 2, false, current_date - interval '20 days' + interval '2 hours', NULL,                              1,  1),
  (2,  1, 'Senior Spring Boot Architect',    1, 2, 1, 60,120, 2000000.00, 3000000.00, 1, 2, 2, true,  current_date - interval '19 days', (current_date + interval '30 days')::date, 1, 11),
  (3,  1, 'DevOps & Kubernetes Engineer',    1, 2, 1, 36, 84, 1500000.00, 2200000.00, 1, 1, 2, false, current_date - interval '18 days', NULL,                              1, 17),
  (4,  1, 'QA Automation Engineer',          3, 1, 1, 12, 48,  600000.00,  900000.00, 1, 2, 2, false, current_date - interval '17 days', NULL,                              1, 33),
  (5,  1, 'Legacy Migration Specialist',     1, 1, 1, 24, 72, NULL,       NULL,       2, 2, 2, false, current_date - interval '16 days', (current_date - interval '2 days')::date,  1,  6),
  (6,  1, 'Draft: Principal Data Engineer',  1, 3, 1, 48, 96, NULL,       NULL,       2, 1, 1, false, NULL,                              NULL,                              1,  2),
  (7,  2, 'FinTech Product Analyst',         1, 3, 2, 12, 60,  900000.00, 1400000.00, 1, 2, 2, false, current_date - interval '15 days' + interval '10 minutes', NULL,                              4, 28),
  (8,  2, 'Draft: Risk Compliance Officer',  1, 1, 2, 36, 84, NULL,       NULL,       2, 1, 1, false, NULL,                              NULL,                              4, 41),
  (9,  2, 'Archived Treasury Associate',     1, 1, 2, 12, 36,  500000.00,  700000.00, 1, 1, 2, false, current_date - interval '14 days', NULL,                              4, 86),
  (10, 3, 'Fleet Operations Supervisor',     1, 1, 7, 24, 72,  450000.00,  650000.00, 1, 2, 2, true,  current_date - interval '8 days',  NULL,                             12, 83),
  (11, 4, 'ICU Staff Nurse (Unverified Org)',1, 1, 3,  0, 60,  360000.00,  500000.00, 1, 4, 2, false, current_date - interval '12 days', NULL,                              8, 70),
  (12, 6, 'Retail Store Manager',            1, 1, 5, 24, 72,  400000.00,  600000.00, 1, 1, 2, false, current_date - interval '115 days',NULL,                             14, 81);

INSERT INTO job_requirement (organisation_id, title, description, description_language_id, employment_type_id, work_mode_id,
    industry_id, min_experience_months, max_experience_months, salary_min_amount, salary_max_amount, salary_currency_id,
    salary_disclosure_id, positions_total, job_status_id, is_open_to_consultants, published_at, closes_on, created_at, created_by)
SELECT om.org_id, sj.title,
       sj.title || ' at ' || om.display_name || '. Full role description covering responsibilities, skills, and benefits.',
       1, sj.emp_type, sj.work_mode, sj.industry_id, sj.min_exp, sj.max_exp, sj.sal_min, sj.sal_max,
       CASE WHEN sj.sal_min IS NOT NULL THEN 1 END, sj.sal_disc, sj.pos_total, sj.init_status, sj.consultants,
       sj.pub_at, sj.closes_on, coalesce(sj.pub_at - interval '2 hours', now() - interval '5 days'), om.admin_user_id
FROM seed_job sj JOIN org_map om ON om.org_idx = sj.org_idx
ORDER BY sj.job_idx;

ALTER TABLE seed_job ADD COLUMN job_id bigint;
UPDATE seed_job sj SET job_id = j.id FROM job_requirement j WHERE j.title = sj.title;

INSERT INTO job_requirement_location (job_requirement_id, city_id, created_at, created_by)
SELECT sj.job_id, sj.city_id, coalesce(sj.pub_at, now()), om.admin_user_id
FROM seed_job sj JOIN org_map om ON om.org_idx = sj.org_idx;

INSERT INTO job_requirement_skill (job_requirement_id, skill_id, is_mandatory, created_at, created_by)
SELECT sj.job_id, sj.skill_id, true, coalesce(sj.pub_at, now()), om.admin_user_id
FROM seed_job sj JOIN org_map om ON om.org_idx = sj.org_idx
UNION ALL
SELECT sj.job_id, 5, false, coalesce(sj.pub_at, now()), om.admin_user_id
FROM seed_job sj JOIN org_map om ON om.org_idx = sj.org_idx WHERE sj.skill_id <> 5;

-- Screening questions on J1, J2, J7, J10 (covers all 3 answer_type values: 1=yes_no, 2=number, 3=short_text)
INSERT INTO screening_question (job_requirement_id, question_text, answer_type_id, is_required, sort_order, created_at, created_by)
SELECT sj.job_id, q.txt, q.typ, q.req, q.ord, sj.pub_at, om.admin_user_id
FROM seed_job sj JOIN org_map om ON om.org_idx = sj.org_idx
CROSS JOIN (VALUES
  ('Are you willing to work in hybrid/onsite mode?', 1, true,  1),
  ('How many years of relevant experience do you have?', 2, true, 2),
  ('What is your current notice period?', 3, false, 3)
) q(txt, typ, req, ord)
WHERE sj.job_idx IN (1, 2, 7, 10);

------------------------------------------------------------------------------------------------------------------------
-- 7. Applications & Pipeline Transitions (36 applications across open jobs)
-- Exercises:
--   - All 5 application_source values: direct(1), recruiter_outreach(2), consultant(3), referral(4), campus(5)
--   - All 7 application_status values: applied(1), shortlisted(2), interviewing(3), offered(4), joined(5), rejected(6), withdrawn(7)
--   - All 12 allowed transitions in application_status_transition:
--       applied -> shortlisted, applied -> rejected, applied -> withdrawn
--       shortlisted -> interviewing, shortlisted -> rejected, shortlisted -> withdrawn
--       interviewing -> offered, interviewing -> rejected, interviewing -> withdrawn
--       offered -> joined, offered -> rejected, offered -> withdrawn
--   - J1 has >= 2 applications resting in 'offered' (status 4) so t02 and t04 concurrency race on J1 work out of the box!
--   - J3 has 1 application reaching 'joined' (status 5) -> automatically transitions J3 to 'filled' (status 5)!
------------------------------------------------------------------------------------------------------------------------
CREATE TEMP TABLE seed_app (
    app_idx int PRIMARY KEY,
    job_idx int,
    cand_idx int,
    src smallint,
    path int[] -- sequence of status_ids after 1 (applied)
);

INSERT INTO seed_app VALUES
  -- Job 1 (Org 1, 3 positions): 10 applications covering every status & multiple offers for t02/t04
  (1,  1,  2, 1, ARRAY[]::int[]),             -- stays applied (1) — matches t03 :cand (public, unblocked, undownloaded)
  (2,  1,  3, 1, ARRAY[2]),                   -- applied -> shortlisted (2)
  (3,  1,  4, 2, ARRAY[2, 3]),                -- applied -> shortlisted -> interviewing (3) (recruiter_outreach)
  (4,  1,  5, 1, ARRAY[2, 3, 4]),             -- applied -> shortlisted -> interviewing -> offered (4) (offer #1 on J1)
  (5,  1,  7, 4, ARRAY[2, 3, 4]),             -- applied -> shortlisted -> interviewing -> offered (4) (offer #2 on J1, referral)
  (6,  1, 11, 5, ARRAY[2, 3, 4, 5]),          -- applied -> shortlisted -> interviewing -> offered -> joined (5) (campus, fills 1 of 3 on J1)
  (7,  1, 12, 1, ARRAY[6]),                   -- applied -> rejected (6)
  (8,  1, 13, 1, ARRAY[7]),                   -- applied -> withdrawn (7)
  (9,  1, 14, 1, ARRAY[2, 6]),                -- applied -> shortlisted -> rejected (6)
  (10, 1, 15, 1, ARRAY[2, 7]),                -- applied -> shortlisted -> withdrawn (7)

  -- Job 2 (Org 1, open to consultants, 2 positions): 6 applications covering consultant source & remaining transitions
  (11, 2, 16, 3, ARRAY[2, 3, 6]),             -- interviewing -> rejected (6) (consultant1)
  (12, 2, 17, 3, ARRAY[2, 3, 7]),             -- interviewing -> withdrawn (7) (consultant2)
  (13, 2, 18, 1, ARRAY[2, 3, 4, 6]),          -- offered -> rejected (6)
  (14, 2, 19, 1, ARRAY[2, 3, 4, 7]),          -- offered -> withdrawn (7)
  (15, 2, 21, 1, ARRAY[2, 3, 4]),             -- stays offered (4)
  (16, 2, 22, 1, ARRAY[]::int[]),             -- stays applied (1)

  -- Job 3 (Org 1, 1 position): 2 applications, one joins and auto-fills Job 3 (job_status_id -> 5 filled)
  (17, 3, 25, 1, ARRAY[2, 3, 4, 5]),          -- joined -> fills J3!
  (18, 3, 26, 1, ARRAY[2]),                   -- shortlisted

  -- Job 4 (Org 1, will be paused): 3 applications
  (19, 4, 11, 1, ARRAY[2]),
  (20, 4, 12, 1, ARRAY[6]),
  (21, 4, 30, 1, ARRAY[2, 3]),                -- cand30 (will be erased, proving applications survive erasure!)

  -- Job 5 (Org 1, will be closed): 2 applications
  (22, 5,  3, 1, ARRAY[6]),
  (23, 5,  4, 1, ARRAY[2, 6]),

  -- Job 7 (Org 2, 2 positions): 6 applications
  (24, 7,  2, 1, ARRAY[2, 3, 4, 5]),          -- joined (1 of 2 positions on J7)
  (25, 7,  3, 2, ARRAY[2, 3, 4]),             -- offered
  (26, 7,  5, 1, ARRAY[2, 3]),                -- interviewing
  (27, 7,  7, 1, ARRAY[2]),                   -- shortlisted
  (28, 7, 11, 1, ARRAY[6]),                   -- rejected
  (29, 7, 16, 1, ARRAY[]::int[]),             -- applied

  -- Job 10 (Org 3, open to consultants, 2 positions): 4 applications
  (30, 10, 6, 3, ARRAY[2, 3, 4]),             -- consultant-sourced, offered
  (31, 10, 8, 1, ARRAY[2]),                   -- shortlisted
  (32, 10,13, 1, ARRAY[]::int[]),             -- applied
  (33, 10,19, 1, ARRAY[6]),                   -- rejected

  -- Job 11 (Org 4 - unverified org): 3 applications
  (34, 11, 9, 1, ARRAY[2]),
  (35, 11,18, 1, ARRAY[2, 3]),
  (36, 11,24, 1, ARRAY[]::int[]);

INSERT INTO application (job_requirement_id, candidate_profile_id, resume_id, application_source_id,
                         sourced_by_app_user_id, applied_at, created_at, created_by)
SELECT sj.job_id, cm.profile_id, r.id, sa.src,
       CASE
         WHEN sa.src = 2 THEN (SELECT m.app_user_id FROM organisation_member m JOIN org_map om ON om.org_id = m.organisation_id WHERE om.org_idx = sj.org_idx AND m.access_role_id = 5 AND m.valid_to IS NULL LIMIT 1)
         WHEN sa.src = 3 THEN (SELECT id FROM app_user WHERE email = CASE WHEN sa.app_idx % 2 = 1 THEN 'consultant1@partner.test' ELSE 'consultant2@partner.test' END)
       END,
       sj.pub_at + make_interval(hours => sa.app_idx),
       sj.pub_at + make_interval(hours => sa.app_idx),
       cm.app_user_id
FROM seed_app sa
JOIN seed_job sj ON sj.job_idx = sa.job_idx
JOIN cand_map cm ON cm.idx = sa.cand_idx
LEFT JOIN resume r ON r.candidate_profile_id = cm.profile_id AND r.is_primary
ORDER BY sa.app_idx;

ALTER TABLE seed_app ADD COLUMN application_id bigint;
UPDATE seed_app sa
   SET application_id = a.id
  FROM application a, seed_job sj, cand_map cm
 WHERE sj.job_idx = sa.job_idx AND cm.idx = sa.cand_idx
   AND a.job_requirement_id = sj.job_id AND a.candidate_profile_id = cm.profile_id;

-- Answers to screening questions
INSERT INTO application_answer (application_id, job_requirement_id, screening_question_id, answer_text, created_at, created_by)
SELECT a.id, a.job_requirement_id, q.id,
       CASE q.answer_type_id
         WHEN 1 THEN 'yes'
         WHEN 2 THEN '4'
         ELSE '30 days'
       END,
       a.applied_at, a.created_by
FROM application a
JOIN screening_question q ON q.job_requirement_id = a.job_requirement_id;

-- Step applications through their pipeline path so triggers record history, notifications, and filled positions
DO $$
DECLARE
  rec record;
  st int;
  step_no int;
BEGIN
  FOR rec IN SELECT sa.application_id, sa.path, a.applied_at FROM seed_app sa JOIN application a ON a.id = sa.application_id ORDER BY sa.app_idx LOOP
    step_no := 1;
    FOREACH st IN ARRAY rec.path LOOP
      UPDATE application
         SET application_status_id = st,
             status_changed_at = rec.applied_at + make_interval(days => step_no)
       WHERE id = rec.application_id;
      step_no := step_no + 1;
    END LOOP;
  END LOOP;
END $$;

-- Transition J4 and J12 to paused (3), J5 and J9 to closed (4), and soft-delete J9
UPDATE job_requirement SET job_status_id = 3 WHERE id IN (SELECT job_id FROM seed_job WHERE job_idx IN (4, 12));
UPDATE job_requirement SET job_status_id = 4 WHERE id IN (SELECT job_id FROM seed_job WHERE job_idx IN (5, 9));
UPDATE job_requirement SET deleted_at = now() - interval '1 day' WHERE id = (SELECT job_id FROM seed_job WHERE job_idx = 9);

------------------------------------------------------------------------------------------------------------------------
-- 8. Profile downloads & Candidate blocks
--   - Org 1 downloads cand25 (1 credit debit)
--   - Org 2 downloads cand1 (1 credit debit)
--   - Blocks:
--       cand23 blocks Org 3 (active company block)
--       cand24 blocks rec1@org2.test (active user block)
--       cand15 blocks Org 2 and later unblocks (historical lifted block: unblocked_at IS NOT NULL)
------------------------------------------------------------------------------------------------------------------------
DO $$
DECLARE
  rec1_org1 bigint := (SELECT id FROM app_user WHERE email = 'rec1@org1.test');
  rec1_org2 bigint := (SELECT id FROM app_user WHERE email = 'rec1@org2.test');
  cand25_p  bigint := (SELECT profile_id FROM cand_map WHERE idx = 25);
  cand1_p   bigint := (SELECT profile_id FROM cand_map WHERE idx = 1);
BEGIN
  PERFORM set_config('app.user_id', rec1_org1::text, true);
  PERFORM billing_download_profile(cand25_p);
  PERFORM candidate_contact(cand25_p);

  PERFORM set_config('app.user_id', rec1_org2::text, true);
  PERFORM billing_download_profile(cand1_p);
  PERFORM set_config('app.user_id', '', true);
END $$;

INSERT INTO candidate_block (candidate_profile_id, blocked_organisation_id, blocked_at, unblocked_at, created_at, created_by)
SELECT cm.profile_id, (SELECT org_id FROM org_map WHERE org_idx = 3), now() - interval '10 days', NULL, now() - interval '10 days', cm.app_user_id
FROM cand_map cm WHERE cm.idx = 23
UNION ALL
SELECT cm.profile_id, (SELECT org_id FROM org_map WHERE org_idx = 2), now() - interval '20 days', now() - interval '5 days', now() - interval '20 days', cm.app_user_id
FROM cand_map cm WHERE cm.idx = 15;

INSERT INTO candidate_block (candidate_profile_id, blocked_app_user_id, blocked_at, unblocked_at, created_at, created_by)
SELECT cm.profile_id, (SELECT id FROM app_user WHERE email = 'rec1@org2.test'), now() - interval '7 days', NULL, now() - interval '7 days', cm.app_user_id
FROM cand_map cm WHERE cm.idx = 24;

------------------------------------------------------------------------------------------------------------------------
-- 9. Devices and Sessions
--   Covers all 4 session_end_reason values: logout(1), idle_timeout(2), revoked_by_user(3), revoked_by_admin(4)
--   Note: cand1 (idx=1) is kept with 0 active sessions so t04 concurrency test #1 picks cand1 cleanly!
------------------------------------------------------------------------------------------------------------------------
INSERT INTO user_device (app_user_id, device_fingerprint_hash, device_label, first_seen_at, last_seen_at, created_at, created_by)
SELECT u.id, pg_temp.sha('device:' || u.id || ':1'), 'Chrome on Windows', u.created_at, now() - interval '1 day', u.created_at, u.id
FROM app_user u;

-- Active session for rec1@org1.test (needed by t03 :rec1_session) and for candidates idx 2..15
INSERT INTO user_session (app_user_id, user_device_id, token_hash, started_at, last_activity_at, expires_at, created_at, created_by)
SELECT d.app_user_id, d.id, pg_temp.sha('active-sess:' || d.app_user_id),
       now() - interval '2 hours', now() - interval '10 minutes', now() + interval '28 days', now() - interval '2 hours', d.app_user_id
FROM user_device d
JOIN app_user u ON u.id = d.app_user_id
WHERE u.email IN ('rec1@org1.test', 'rec1@org2.test', 'admin@org1.test',
                  'cand2@mail.test', 'cand3@mail.test', 'cand4@mail.test', 'cand5@mail.test');

-- Ended sessions covering all 4 session_end_reason codes (1=logout, 2=idle_timeout, 3=revoked_by_user, 4=revoked_by_admin)
INSERT INTO user_session (app_user_id, user_device_id, token_hash, started_at, last_activity_at, expires_at, ended_at, session_end_reason_id, created_at, created_by)
SELECT d.app_user_id, d.id, pg_temp.sha('ended-sess:' || d.app_user_id || ':' || r),
       now() - interval '10 days', now() - interval '10 days' + interval '30 minutes',
       now() + interval '20 days', now() - interval '10 days' + interval '35 minutes',
       r, now() - interval '10 days', d.app_user_id
FROM user_device d
JOIN cand_map cm ON cm.app_user_id = d.app_user_id
CROSS JOIN LATERAL (SELECT 1 + (cm.idx % 4) AS r) x
WHERE cm.idx BETWEEN 1 AND 8;

-- Revoke a device using the new V013 entry point auth_revoke_device() on cand16
DO $$
DECLARE
  u16 bigint := (SELECT app_user_id FROM cand_map WHERE idx = 16);
  d16 bigint := (SELECT id FROM user_device WHERE app_user_id = u16 LIMIT 1);
BEGIN
  PERFORM set_config('app.user_id', u16::text, true);
  PERFORM auth_revoke_device(d16);
  PERFORM set_config('app.user_id', '', true);
END $$;

------------------------------------------------------------------------------------------------------------------------
-- 10. Account statuses: suspend cand28, deactivate cand29, erase cand30 (covers all 4 account_status codes)
------------------------------------------------------------------------------------------------------------------------
DO $$
DECLARE
  staff_id bigint := (SELECT id FROM app_user WHERE email = 'admin@talentra.test');
  u28 bigint := (SELECT app_user_id FROM cand_map WHERE idx = 28);
  u29 bigint := (SELECT app_user_id FROM cand_map WHERE idx = 29);
  p30 bigint := (SELECT profile_id FROM cand_map WHERE idx = 30);
BEGIN
  PERFORM set_config('app.user_id', staff_id::text, true);
  PERFORM user_set_account_status(u28, 'suspended');
  PERFORM set_config('app.user_id', u29::text, true);
  PERFORM user_set_account_status(u29, 'deactivated');
  PERFORM set_config('app.user_id', staff_id::text, true);
  PERFORM candidate_erase(p30);
  PERFORM set_config('app.user_id', '', true);
END $$;

------------------------------------------------------------------------------------------------------------------------
-- 11. Notification preferences, job alerts, and notifications across all 5 statuses
--   Statuses: queued(1), sent(2), delivered(3), failed(4), suppressed(5)
------------------------------------------------------------------------------------------------------------------------
INSERT INTO notification_preference (app_user_id, notification_category_id, notification_channel_id, is_enabled, created_at, created_by)
SELECT app_user_id, 1, 1, false, created_at, app_user_id FROM cand_map WHERE idx = 4
UNION ALL
SELECT app_user_id, 5, 1, false, created_at, app_user_id FROM cand_map WHERE idx = 5;

INSERT INTO job_alert (candidate_profile_id, keywords, city_id, min_salary_amount, salary_currency_id, alert_frequency_id, is_active, last_sent_at, created_at, created_by)
SELECT profile_id, 'java spring', 1, 1000000.00, 1, 1, true,  now() - interval '1 day',  created_at, app_user_id FROM cand_map WHERE idx = 1
UNION ALL
SELECT profile_id, 'python data', 4,  800000.00, 1, 2, true,  now() - interval '2 days', created_at, app_user_id FROM cand_map WHERE idx = 3
UNION ALL
SELECT profile_id, 'react typescript', NULL, NULL, NULL, 3, false, NULL, created_at, app_user_id FROM cand_map WHERE idx = 4;

-- Trigger suppressed notification (status 5): cand4 opted out of job_alert(1) on email(1); cand20 has no marketing consent(4)
INSERT INTO notification (app_user_id, notification_category_id, notification_channel_id, template_key, payload)
SELECT app_user_id, 1, 1, 'job_alert.digest', '{"job_alert_id": 1, "matches": 3}'::jsonb FROM cand_map WHERE idx = 4
UNION ALL
SELECT app_user_id, 5, 1, 'marketing.campaign', '{"campaign_id": 10}'::jsonb FROM cand_map WHERE idx = 20;

-- Move some queued application notifications through notification_claim and notification_record_result
-- so sent(2), delivered(3), and failed(4) are all represented alongside queued(1) and suppressed(5)
DO $$
DECLARE
  n_sent bigint;
  n_deliv bigint;
  n_fail bigint;
BEGIN
  SELECT id INTO n_sent  FROM notification WHERE notification_status_id = 1 ORDER BY id LIMIT 1;
  SELECT id INTO n_deliv FROM notification WHERE notification_status_id = 1 AND id > n_sent ORDER BY id LIMIT 1;
  SELECT id INTO n_fail  FROM notification WHERE notification_status_id = 1 AND id > n_deliv ORDER BY id LIMIT 1;

  PERFORM notification_record_result(n_sent,  'sent',      'msg_prove_sent_1',  NULL);
  PERFORM notification_record_result(n_deliv, 'delivered', 'msg_prove_deliv_1', NULL);
  UPDATE notification SET attempt_count = 5 WHERE id = n_fail;
  PERFORM notification_record_result(n_fail,  'failed',    'msg_prove_fail_1',  'mailbox unavailable');
END $$;

------------------------------------------------------------------------------------------------------------------------
-- 12. System errors & Materialized View refresh
------------------------------------------------------------------------------------------------------------------------
INSERT INTO system_error (occurred_at, service_name, error_code, message, app_user_id, context) VALUES
  (now() - interval '3 days', 'notification-worker', 'SMTP_TIMEOUT',    'Provider timed out after 10s', NULL, '{"attempt": 3}'::jsonb),
  (now() - interval '2 days', 'payment-webhook',     'SIGNATURE_ERROR', 'Webhook HMAC mismatch',        NULL, '{"ip": "203.0.113.9"}'::jsonb),
  (now() - interval '1 day',  'search',              'SLOW_QUERY',      'Search exceeded 150ms budget', (SELECT app_user_id FROM cand_map WHERE idx = 1), '{"ap": "AP-04"}'::jsonb);

SELECT refresh_aggregates();
