-- Talentra v2 synthetic data generator. Deterministic (setseed) and scaled by :profiles (default 10,000).
-- Ratios follow the docket's laptop scale (profiles : jobs : applications = 10 : 1 : 50).
-- Everything that has a business rule goes through it: applications through the pipeline trigger, money through
-- billing_apply_payment_event() and wallet_post(), logins through auth_open_session(). So the seed is also a test.
-- Distributions and deliberate data-quality issues are documented in docs/03-data-requirements.md (section 6).

\if :{?profiles}
\else
  \set profiles 10000
\endif
SET client_min_messages = warning;
SET app.hmac_key = 'dev-only-key-not-a-secret';
SELECT set_config('seed.profiles', :'profiles', false) \g /dev/null
SELECT setseed(0.42) \g /dev/null

-- helpers ------------------------------------------------------------------------------------------------------------
CREATE FUNCTION pg_temp.pick(a text[]) RETURNS text LANGUAGE sql VOLATILE AS $$ SELECT a[1 + floor(random() * cardinality(a))::int] $$;
-- 1..n, skewed towards 1 (skew > 1): a few popular values, a long tail
CREATE FUNCTION pg_temp.skewed(n int, skew float8) RETURNS int LANGUAGE sql VOLATILE AS $$ SELECT 1 + floor(n * power(random(), skew))::int $$;
CREATE FUNCTION pg_temp.between_ts(a timestamptz, b timestamptz) RETURNS timestamptz LANGUAGE sql VOLATILE AS $$ SELECT a + random() * (b - a) $$;
CREATE FUNCTION pg_temp.sha(t text) RETURNS bytea LANGUAGE sql IMMUTABLE AS $$ SELECT sha256(convert_to(t, 'UTF8')) $$;
CREATE FUNCTION pg_temp.letters(n int) RETURNS text LANGUAGE sql VOLATILE AS
$$ SELECT string_agg(chr(65 + floor(random() * 26)::int), '') FROM generate_series(1, n) $$;
-- cities by hiring popularity (Bengaluru, Mumbai, Hyderabad, Chennai, Delhi, Pune, Gurugram, Noida, Kolkata, ...)
CREATE FUNCTION pg_temp.city() RETURNS int LANGUAGE sql VOLATILE AS $$
  SELECT (ARRAY[1,4,12,8,14,5,25,15,18,19,9,22,29,24,16,20,21,26,10,6,30,31,2,23,27,28,3,7,11,13,17,32,33,34,35,36])[pg_temp.skewed(36, 1.8)] $$;
CREATE FUNCTION pg_temp.person_name() RETURNS text LANGUAGE plpgsql VOLATILE AS $$
DECLARE r float8 := random();
BEGIN
  IF r < 0.08 THEN RETURN pg_temp.pick(ARRAY['राहुल शर्मा', 'प्रिया वर्मा', 'अमित कुमार', 'सुनीता देवी', 'विकास सिंह', 'पूजा गुप्ता', 'अंकित जोशी', 'नेहा अग्रवाल']);
  ELSIF r < 0.13 THEN RETURN pg_temp.pick(ARRAY['கார்த்திக் சுப்பிரமணியம்', 'லக்ஷ்மி நாராயணன்', 'செந்தில் குமார்', 'பிரியா ராஜன்', 'முருகன் செல்வம்', 'கவிதா சுந்தரம்']);
  ELSIF r < 0.15 THEN RETURN pg_temp.pick(ARRAY['Murugan', 'Selvi', 'Lakshmi', 'Ramesh']);      -- mononyms are common
  END IF;
  RETURN pg_temp.pick(ARRAY['Aarav', 'Vivaan', 'Aditya', 'Arjun', 'Sai', 'Reyansh', 'Krishna', 'Ishaan', 'Rohan', 'Karthik', 'Priya',
      'Ananya', 'Diya', 'Aditi', 'Kavya', 'Lakshmi', 'Meera', 'Pooja', 'Sneha', 'Divya', 'Rahul', 'Vikram', 'Suresh', 'Ramesh', 'Mohammed',
      'Imran', 'Fatima', 'Ayesha', 'Joseph', 'Mary', 'Harpreet', 'Gurpreet', 'Siddharth', 'Nikhil', 'Neha', 'Swati', 'Deepak', 'Manoj',
      'Anil', 'Sunita', 'Lavanya', 'Vignesh', 'Senthil', 'Arun', 'Bhavana', 'Chitra', 'Ganesh', 'Hari'])
    || ' ' || pg_temp.pick(ARRAY['Sharma', 'Verma', 'Iyer', 'Nair', 'Reddy', 'Rao', 'Patel', 'Shah', 'Singh', 'Kumar', 'Das', 'Banerjee',
      'Mukherjee', 'Gupta', 'Agarwal', 'Khan', 'Ansari', 'Fernandes', 'D''Souza', 'Pillai', 'Menon', 'Naidu', 'Chowdhury', 'Joshi',
      'Kulkarni', 'Deshpande', 'Murthy', 'Subramanian', 'Krishnan', 'Gill']);
END $$;
CREATE FUNCTION pg_temp.skill_id() RETURNS int LANGUAGE plpgsql VOLATILE AS
$$ BEGIN RETURN pg_temp.skewed((SELECT count(*)::int FROM skill), 1.7); END $$;
CREATE FUNCTION pg_temp.skill_name() RETURNS text LANGUAGE plpgsql VOLATILE AS
$$ DECLARE k int := pg_temp.skill_id(); BEGIN RETURN (SELECT name FROM skill WHERE id = k); END $$;
CREATE FUNCTION pg_temp.phone() RETURNS text LANGUAGE sql VOLATILE AS
$$ SELECT '+91' || (6 + floor(random() * 4))::int || lpad(floor(random() * 1e9)::bigint::text, 9, '0') $$;

\set pw '''$argon2id$v=19$m=65536,t=3,p=4$c2VlZHNhbHRzZWVkc2FsdA$c2VlZGhhc2hzZWVkaGFzaHNlZWRoYXNoc2VlZGhhc2g'''

-- 1. staff ------------------------------------------------------------------------------------------------------------
INSERT INTO app_user (email, created_at) VALUES ('superadmin@talentra.test', now() - interval '320 days'), ('admin@talentra.test', now() - interval '320 days');
INSERT INTO user_access_role (app_user_id, access_role_id, created_at)
SELECT id, CASE WHEN email LIKE 'super%' THEN 1 ELSE 2 END, created_at FROM app_user WHERE email LIKE '%@talentra.test';
INSERT INTO user_credential (app_user_id, password_hash) SELECT id, :pw FROM app_user;

-- 2. candidates -------------------------------------------------------------------------------------------------------
CREATE TEMP TABLE sc AS
SELECT i, pg_temp.between_ts(now() - interval '300 days', now() - interval '2 days') AS created_at,
       pg_temp.person_name() AS full_name, CASE WHEN random() < 0.92 THEN pg_temp.phone() END AS phone,
       random() AS r1, random() AS r2, random() AS r3, floor(power(random(), 1.6) * 240)::int AS months
FROM generate_series(1, :profiles) i;
-- deliberate duplicates (finding F-01): 1% of candidates registered twice with the same phone and name
UPDATE sc SET full_name = d.full_name, phone = d.phone
FROM sc d WHERE sc.i % 100 = 0 AND d.i = sc.i - 1 AND d.phone IS NOT NULL;

INSERT INTO app_user (email, phone_e164, phone_country_id, preferred_language_id, created_at, last_login_at)
SELECT 'cand' || i || '@mail.test', phone, CASE WHEN phone IS NOT NULL THEN 1 END,
       CASE WHEN full_name ~ '[ऀ-ॿ]' AND r1 < 0.6 THEN 2 WHEN full_name ~ '[஀-௿]' AND r1 < 0.6 THEN 3 WHEN r1 < 0.05 THEN 2 ELSE 1 END,
       created_at, pg_temp.between_ts(created_at, now())
FROM sc ORDER BY i;
CREATE TEMP TABLE scu AS SELECT sc.*, u.id AS app_user_id FROM sc JOIN app_user u ON u.email = 'cand' || sc.i || '@mail.test';
CREATE INDEX ON scu (i);

INSERT INTO user_credential (app_user_id, password_hash, created_at, created_by) SELECT app_user_id, :pw, created_at, app_user_id FROM scu;
INSERT INTO user_access_role (app_user_id, access_role_id, created_at, created_by) SELECT app_user_id, 8, created_at, app_user_id FROM scu;
INSERT INTO consent_record (app_user_id, consent_purpose_id, is_granted, policy_version, recorded_at, ip_address, created_at, created_by)
SELECT app_user_id, p, true, '2026-01', created_at, ('10.' || (i % 250) || '.' || (i % 200) || '.1')::inet, created_at, app_user_id
FROM scu CROSS JOIN (VALUES (1), (2), (3)) v (p)
UNION ALL SELECT app_user_id, 4, r2 < 0.4, '2026-01', created_at, NULL, created_at, app_user_id FROM scu;
-- some later withdraw marketing consent: consent is a history, the newest record wins
INSERT INTO consent_record (app_user_id, consent_purpose_id, is_granted, policy_version, recorded_at, created_at, created_by)
SELECT app_user_id, 4, false, '2026-01', t, t, app_user_id
FROM (SELECT app_user_id, pg_temp.between_ts(created_at, now()) t FROM scu WHERE r2 < 0.08) w;

INSERT INTO candidate_profile (app_user_id, full_name, headline, profile_language_id, current_city_id, total_experience_months,
    expected_salary_amount, expected_salary_currency_id, salary_disclosure_id, notice_period_days, is_open_to_work,
    profile_visibility_id, last_active_at, created_at, created_by)
SELECT app_user_id, full_name, h.headline,
       CASE WHEN full_name ~ '[ऀ-ॿ]' THEN 2 WHEN full_name ~ '[஀-௿]' THEN 3 WHEN r3 < 0.9 THEN 1 END,
       CASE WHEN r1 > 0.05 THEN pg_temp.city() END,                       -- finding F-02: 5% never gave a city
       months,
       CASE WHEN r2 < 0.6 THEN round((150000 + months * 12000 * (0.6 + r3))::numeric, -3) END,
       CASE WHEN r2 < 0.6 THEN 1 END,
       CASE WHEN r2 < 0.6 THEN 1 WHEN r2 < 0.85 THEN 2 ELSE 3 END,
       CASE WHEN r3 < 0.8 THEN (ARRAY[0, 15, 30, 60, 90])[1 + floor(random() * 5)::int] END,
       r1 < 0.7, CASE WHEN r3 < 0.85 THEN 1 WHEN r3 < 0.97 THEN 2 ELSE 3 END,
       pg_temp.between_ts(created_at, now()), created_at, app_user_id
FROM scu
CROSS JOIN LATERAL (SELECT CASE WHEN random() < 0.8 + 0 * scu.i THEN pg_temp.skill_name() || ' professional, ' || (scu.months / 12) || ' years' END AS headline) h;
CREATE TEMP TABLE sp AS SELECT p.id, p.app_user_id, p.created_at, p.total_experience_months, p.is_open_to_work, p.profile_visibility_id FROM candidate_profile p;
CREATE INDEX ON sp (id);

INSERT INTO candidate_skill (candidate_profile_id, skill_id, proficiency_level_id, experience_months, created_at, created_by)
SELECT id, pg_temp.skill_id(), 1 + floor(random() * 4)::int, CASE WHEN random() < 0.7 THEN floor(random() * (total_experience_months + 1))::int END,
       created_at, app_user_id
FROM sp CROSS JOIN LATERAL generate_series(1, 3 + (id % 6)::int) g
ON CONFLICT DO NOTHING;
INSERT INTO candidate_language (candidate_profile_id, language_id, proficiency_level_id, created_at, created_by)
SELECT id, l, CASE WHEN l = 1 THEN 2 + floor(random() * 3)::int ELSE 5 END, created_at, app_user_id
FROM sp CROSS JOIN LATERAL (SELECT DISTINCT unnest(ARRAY[1, 1 + ((id + floor(random() * 8))::int % 8), 1 + ((id + floor(random() * 3))::int % 3)]) l) x;
INSERT INTO candidate_education (candidate_profile_id, qualification_id, institution_name, field_of_study, start_date, end_date, created_at, created_by)
SELECT id, q, pg_temp.pick(ARRAY['Anna University', 'University of Mumbai', 'Delhi University', 'VIT Vellore', 'Osmania University',
                                 'Government ITI Pune', 'Bangalore University', 'Amity University', 'Jadavpur University', 'Kerala University']),
       CASE WHEN q >= 5 THEN pg_temp.pick(ARRAY['Computer Science', 'Commerce', 'Mechanical Engineering', 'Electronics', 'Nursing', 'Business Administration']) END,
       s, CASE WHEN random() < 0.95 THEN s + 365 * (2 + floor(random() * 3)::int) END, created_at, app_user_id
FROM sp CROSS JOIN LATERAL (SELECT 3 + pg_temp.skewed(5, 0.7) AS q, (current_date - 365 * (3 + total_experience_months / 12 + floor(random() * 3)::int)) AS s) x;
INSERT INTO candidate_experience (candidate_profile_id, company_name, job_title, employment_type_id, start_date, end_date, created_at, created_by)
SELECT id, pg_temp.pick(ARRAY['Infosys', 'TCS', 'Wipro', 'HDFC Bank', 'Reliance Retail', 'Flipkart', 'Apollo Hospitals', 'Tata Motors',
                              'Zomato', 'Local Traders', 'Self-employed']),
       pg_temp.pick(ARRAY['Associate', 'Executive', 'Engineer', 'Senior Engineer', 'Operator', 'Supervisor', 'Analyst']),
       pg_temp.skewed(4, 1.5), current_date - total_experience_months * 30 - CASE WHEN random() < 0.03 THEN 400 ELSE 0 END,   -- finding F-03: 3% understate their experience
       CASE WHEN random() < 0.4 THEN current_date - total_experience_months * 30 + floor(random() * total_experience_months * 30)::int END,
       created_at, app_user_id
FROM sp WHERE total_experience_months > 6;
INSERT INTO resume (candidate_profile_id, version_number, storage_key, file_sha256, content_language_id, is_primary, created_at, created_by)
SELECT id, v, 'resumes/' || id || '/' || gen_random_uuid() || '.pdf', pg_temp.sha(id || ':' || v), 1, v = n, created_at, app_user_id
FROM sp CROSS JOIN LATERAL (SELECT CASE WHEN random() < 0.7 + 0 * id THEN 1 + floor(random() * 2)::int ELSE 0 END AS n) x
CROSS JOIN LATERAL generate_series(1, x.n) v;

-- 3. consultants and placement officers -------------------------------------------------------------------------------
INSERT INTO app_user (email, phone_e164, phone_country_id, created_at)
SELECT CASE WHEN g <= greatest(5, :profiles / 200) THEN 'consultant' ELSE 'tpo' END || g || '@partner.test', pg_temp.phone(), 1,
       now() - interval '290 days' + random() * interval '200 days'
FROM generate_series(1, greatest(5, :profiles / 200) + greatest(2, :profiles / 1000)) g;
INSERT INTO user_access_role (app_user_id, access_role_id, created_at)
SELECT id, CASE WHEN email LIKE 'consultant%' THEN 6 ELSE 7 END, created_at FROM app_user WHERE email LIKE '%@partner.test';

-- 4. organisations, billing, members, jobs and downloads: one time-ordered event stream, so that every wallet's
--    ledger reads correctly in time order (balance_after follows occurred_at).
CREATE TEMP TABLE seed_event (id serial PRIMARY KEY, at timestamptz NOT NULL, kind text NOT NULL, organisation_id bigint NOT NULL, k int NOT NULL DEFAULT 0);
CREATE INDEX ON seed_event (at, id);

DO $$
DECLARE
  n_org int := greatest(10, current_setting('seed.profiles')::int / 50);
  prefixes text[] := ARRAY['Apex', 'Blue River', 'Crescent', 'Deccan', 'Everest', 'Falcon', 'Ganga', 'Horizon', 'Indus', 'Jade', 'Kaveri',
                           'Lotus', 'Meridian', 'Nimbus', 'Orchid', 'Peacock', 'Quantum', 'Riverstone', 'Saffron', 'Teak', 'Unity', 'Vertex', 'Willow', 'Zenith'];
  suffixes text[] := ARRAY['Technologies', 'Finserv', 'Healthcare', 'Manufacturing', 'Retail', 'Commerce', 'Logistics', 'Learning', 'Telecom', 'Infra'];
  i int; u bigint; o bigint; created timestamptz; gstin text; nm text; v smallint; cid int;
BEGIN
  FOR i IN 1 .. n_org LOOP
    created := now() - interval '300 days' + random() * interval '230 days';
    nm := prefixes[1 + (i - 1) % 24] || ' ' || suffixes[1 + ((i - 1) / 24) % 10] || CASE WHEN i > 240 THEN ' ' || (i / 240 + 1) ELSE '' END;
    INSERT INTO app_user (email, phone_e164, phone_country_id, created_at) VALUES ('admin@org' || i || '.test', pg_temp.phone(), 1, created) RETURNING id INTO u;
    INSERT INTO user_credential (app_user_id, password_hash, created_at, created_by)
    VALUES (u, '$argon2id$v=19$m=65536,t=3,p=4$c2VlZHNhbHRzZWVkc2FsdA$c2VlZGhhc2hzZWVkaGFzaHNlZWRoYXNoc2VlZGhhc2g', created, u);
    v := CASE WHEN random() < 0.85 THEN 2 WHEN random() < 0.7 THEN 1 ELSE 3 END;
    cid := pg_temp.city();
    INSERT INTO user_access_role (app_user_id, access_role_id, created_at, created_by) VALUES (u, 3, created, u);
    INSERT INTO organisation (legal_name, display_name, industry_id, country_id, parent_organisation_id, website_url,
                              verification_status_id, verified_at, created_at, created_by)
    VALUES (nm || ' Private Limited', nm, (ARRAY[1, 2, 3, 4, 5, 6, 7, 8, 9, 10])[1 + ((i - 1) / 24) % 10], 1,
            CASE WHEN i > 20 AND random() < 0.05 THEN (SELECT id FROM organisation ORDER BY random() LIMIT 1) END,
            CASE WHEN random() < 0.8 THEN 'https://www.' || lower(replace(nm, ' ', '')) || '.example' END,
            v, CASE WHEN v = 2 THEN created + interval '2 days' END, created, u)
    RETURNING id INTO o;
    INSERT INTO organisation_location (organisation_id, city_id, address_line, postal_code, latitude, longitude, is_headquarters, created_at, created_by)
    SELECT o, c.id, 'Plot ' || (1 + floor(random() * 400))::int || ', ' || pg_temp.pick(ARRAY['Tech Park', 'Industrial Estate', 'MG Road', 'Ring Road', 'SEZ Phase 2']),
           (100000 + floor(random() * 800000))::int::text, c.latitude, c.longitude, true, created, u
    FROM city c WHERE c.id = cid;
    gstin := lpad((1 + floor(random() * 37))::int::text, 2, '0') || pg_temp.letters(5) || lpad(floor(random() * 10000)::int::text, 4, '0') || pg_temp.letters(1) || '1Z' || floor(random() * 10)::int;
    INSERT INTO organisation_tax_identifier (organisation_id, country_id, tax_identifier_type_id, identifier_hmac, identifier_last4,
                                             verification_status_id, verified_at, created_at, created_by)
    VALUES (o, 1, 1, pii_hmac(gstin), right(gstin, 4), 2, created + interval '1 day', created, u);
    INSERT INTO wallet (organisation_id, created_at, created_by) VALUES (o, created, u);
    INSERT INTO organisation_member (organisation_id, app_user_id, access_role_id, valid_from, created_at, created_by) VALUES (o, u, 3, created, created, u);
    -- plan mix 60% starter, 30% growth, 10% enterprise: the first subscription payment a few hours after sign-up
    INSERT INTO seed_event (at, kind, organisation_id, k) VALUES (created + interval '3 hours', 'subscribe', o, CASE WHEN random() < 0.6 THEN 1 WHEN random() < 0.75 THEN 2 ELSE 3 END);
    IF random() < 0.5 THEN INSERT INTO seed_event (at, kind, organisation_id) VALUES (created + interval '1 day', 'recharge', o); END IF;
  END LOOP;
END $$;

-- job posts and downloads, spread over each organisation's life; bigger plans hire more (weighting applied when processed)
INSERT INTO seed_event (at, kind, organisation_id)
SELECT pg_temp.between_ts(o.created_at + interval '4 days', now() - interval '1 day'), 'job', o.id
FROM generate_series(1, :profiles / 10) g CROSS JOIN LATERAL (SELECT id, created_at FROM organisation WHERE g > 0 ORDER BY random() LIMIT 1) o;
INSERT INTO seed_event (at, kind, organisation_id)
SELECT pg_temp.between_ts(o.created_at + interval '5 days', now() - interval '1 hour'), 'download', o.id
FROM generate_series(1, :profiles / 3) g CROSS JOIN LATERAL (SELECT id, created_at FROM organisation WHERE g > 0 ORDER BY random() LIMIT 1) o;

CREATE TEMP TABLE job_template (title text, skill text, industry_code text, employment_type_id int, min_exp int, max_exp int, salary_lakh numeric, positions int);
INSERT INTO job_template VALUES
  ('Java Developer', 'Java', 'information_technology', 1, 24, 72, 6, 2), ('Senior Java Developer', 'Java', 'information_technology', 1, 60, 120, 15, 1),
  ('Python Developer', 'Python', 'information_technology', 1, 12, 60, 6, 2), ('Data Analyst', 'Data Analysis', 'information_technology', 1, 0, 36, 4, 2),
  ('React Frontend Engineer', 'React', 'information_technology', 1, 24, 84, 8, 2), ('DevOps Engineer', 'DevOps', 'information_technology', 1, 36, 96, 12, 1),
  ('QA Engineer', 'Manual Testing', 'information_technology', 3, 12, 48, 4, 2), ('Android Developer', 'Android', 'information_technology', 1, 12, 60, 6, 1),
  ('Accountant', 'Accounting', 'banking_financial_services', 1, 12, 60, 3.5, 1), ('Relationship Manager', 'Banking Operations', 'banking_financial_services', 1, 24, 72, 5, 3),
  ('Staff Nurse', 'Nursing', 'healthcare', 1, 0, 60, 3, 5), ('Pharmacist', 'Pharmacy', 'healthcare', 1, 0, 48, 3, 2),
  ('CNC Operator', 'CNC Programming', 'manufacturing', 1, 12, 60, 2.5, 6), ('Quality Inspector', 'Quality Control', 'manufacturing', 3, 12, 60, 2.8, 3),
  ('Retail Sales Associate', 'Retail Sales', 'retail', 2, 0, 24, 1.8, 10), ('Store Manager', 'Operations Management', 'retail', 1, 36, 96, 5, 1),
  ('Delivery Executive', 'Last-mile Delivery', 'logistics', 3, 0, 24, 2, 25), ('Warehouse Associate', 'Warehouse Operations', 'logistics', 6, 0, 24, 1.8, 20),
  ('Forklift Operator', 'Forklift Operation', 'logistics', 1, 12, 60, 2.4, 4), ('Customer Support Executive', 'Customer Support', 'ecommerce', 1, 0, 36, 2.6, 10),
  ('Telecaller', 'Telecalling', 'telecom', 1, 0, 24, 1.8, 8), ('Site Supervisor', 'Site Supervision', 'construction', 3, 24, 96, 3.6, 2),
  ('Mathematics Teacher', 'Teaching', 'education', 1, 12, 84, 3.2, 2), ('Digital Marketing Executive', 'Digital Marketing', 'media', 1, 12, 48, 3.5, 1),
  ('Graduate Apprentice', 'English Communication', 'manufacturing', 5, 0, 12, 1.5, 10), ('Software Engineering Intern', 'Python', 'information_technology', 4, 0, 6, 1.2, 4);

DO $$
DECLARE
  e seed_event; p plan; ord bigint; s subscription; w bigint; bal int; u bigint; seats int; j bigint; t job_template;
  sal numeric; cand bigint; n int := 0;
BEGIN
  LOOP
    SELECT * INTO e FROM seed_event ORDER BY at, id LIMIT 1;
    EXIT WHEN NOT FOUND;
    DELETE FROM seed_event WHERE id = e.id;
    SELECT id, balance_credits INTO w, bal FROM wallet WHERE organisation_id = e.organisation_id;

    IF e.kind IN ('subscribe', 'renew') THEN
      SELECT * INTO p FROM plan WHERE id = e.k;
      IF random() < 0.04 THEN                                           -- a declined card first, then the retry succeeds
        INSERT INTO payment_order (organisation_id, payment_purpose_id, amount, currency_id, plan_id, gateway_order_ref, idempotency_key, created_at)
        VALUES (e.organisation_id, 2, p.price_amount, 1, p.id, 'order_' || e.id || 'f', 'seed-order-' || e.id || '-f', e.at - interval '20 minutes') RETURNING id INTO ord;
        PERFORM billing_apply_payment_event(ord, 'failed', 'evt_' || e.id || '_f', p.price_amount, e.at - interval '19 minutes', pg_temp.sha('f' || e.id));
      END IF;
      INSERT INTO payment_order (organisation_id, payment_purpose_id, amount, currency_id, plan_id, gateway_order_ref, idempotency_key, created_at)
      VALUES (e.organisation_id, 2, p.price_amount, 1, p.id, 'order_' || e.id, 'seed-order-' || e.id, e.at - interval '10 minutes') RETURNING id INTO ord;
      PERFORM billing_apply_payment_event(ord, 'authorised', 'evt_' || e.id || '_a', p.price_amount, e.at - interval '5 minutes', pg_temp.sha('a' || e.id));
      PERFORM billing_apply_payment_event(ord, 'captured', 'evt_' || e.id || '_c', p.price_amount, e.at, pg_temp.sha('c' || e.id));
      IF random() < 0.03 THEN     -- webhook redelivered by the gateway: must be a no-op
        PERFORM billing_apply_payment_event(ord, 'captured', 'evt_' || e.id || '_c', p.price_amount, e.at, pg_temp.sha('c' || e.id));
      END IF;
      SELECT * INTO s FROM subscription WHERE payment_order_id = ord;
      IF e.kind = 'subscribe' THEN
        INSERT INTO seed_event (at, kind, organisation_id) VALUES (e.at + interval '2 days', 'members', e.organisation_id);
      END IF;
      IF random() < 0.07 THEN                                           -- churn: cancels, no renewal
        UPDATE subscription SET auto_renew = false, cancelled_at = pg_temp.between_ts(e.at, least(now(), s.ends_on::timestamptz)) WHERE id = s.id;
      ELSIF s.ends_on < current_date THEN
        INSERT INTO seed_event (at, kind, organisation_id, k) VALUES (s.ends_on + interval '30 minutes', 'renew', e.organisation_id, e.k);
      END IF;

    ELSIF e.kind = 'recharge' OR (e.kind IN ('job', 'download') AND bal < 5) THEN
      INSERT INTO payment_order (organisation_id, payment_purpose_id, amount, currency_id, credits_to_grant, gateway_order_ref, idempotency_key, created_at)
      VALUES (e.organisation_id, 1, 5000, 1, 100, 'order_' || e.id || 'r', 'seed-order-' || e.id || '-r', e.at - interval '2 hours') RETURNING id INTO ord;
      PERFORM billing_apply_payment_event(ord, 'captured', 'evt_' || e.id || '_r', 5000, e.at - interval '1 second', pg_temp.sha('r' || e.id));
      IF e.kind = 'recharge' AND random() < 0.05 THEN                   -- refunded at once, before any credit was spent (keeps the ledger in time order)
        PERFORM billing_apply_payment_event(ord, 'refunded', 'evt_' || e.id || '_rf', 5000, e.at, pg_temp.sha('rf' || e.id));
      END IF;
    END IF;

    IF e.kind = 'members' THEN
      SELECT coalesce(max(max_seats), 1) INTO seats FROM subscription WHERE organisation_id = e.organisation_id AND e.at::date >= starts_on AND e.at::date < ends_on;
      FOR m IN 1 .. floor(random() * seats)::int LOOP                   -- 0 .. seats-1 more members beside the account admin
        INSERT INTO app_user (email, phone_e164, phone_country_id, created_at)
        VALUES ('member' || m || '@org' || e.organisation_id || '.test', pg_temp.phone(), 1, e.at) RETURNING id INTO u;
        INSERT INTO user_credential (app_user_id, password_hash, created_at) VALUES (u, '$argon2id$v=19$m=65536,t=3,p=4$c2VlZHNhbHRzZWVkc2FsdA$c2VlZGhhc2hzZWVkaGFzaHNlZWRoYXNoc2VlZGhhc2g', e.at);
        INSERT INTO user_access_role (app_user_id, access_role_id, created_at) VALUES (u, CASE WHEN random() < 0.7 THEN 5 ELSE 4 END, e.at);
        INSERT INTO organisation_member (organisation_id, app_user_id, access_role_id, valid_from, created_at)
        SELECT e.organisation_id, u, access_role_id, e.at, e.at FROM user_access_role WHERE app_user_id = u;
      END LOOP;

    ELSIF e.kind = 'job' THEN
      SELECT * INTO t FROM job_template ORDER BY random() LIMIT 1;
      sal := round(t.salary_lakh * 100000 * (0.85 + random() * 0.3)::numeric, -3);
      SELECT app_user_id INTO u FROM organisation_member WHERE organisation_id = e.organisation_id AND valid_from <= e.at ORDER BY random() LIMIT 1;
      INSERT INTO job_requirement (organisation_id, title, description, description_language_id, employment_type_id, work_mode_id, industry_id,
          min_experience_months, max_experience_months, salary_min_amount, salary_max_amount, salary_currency_id, salary_disclosure_id,
          positions_total, job_status_id, is_open_to_consultants, published_at, closes_on, created_at, created_by)
      SELECT e.organisation_id, t.title,
             t.title || ' at ' || o.display_name || '. We are hiring ' || t.positions || ' ' || lower(t.title) || '(s) with ' || (t.min_exp / 12)
               || '+ years of experience. You will work with a friendly team, follow company processes, and grow with us. Required skill: '
               || t.skill || '. Benefits: provident fund, health insurance, paid leave.',
             1, t.employment_type_id, CASE WHEN t.industry_code = 'information_technology' THEN pg_temp.skewed(3, 1) ELSE 1 END,
             (SELECT id FROM industry WHERE code = t.industry_code), t.min_exp, t.max_exp,
             CASE WHEN r < 0.7 THEN sal END, CASE WHEN r < 0.6 THEN round(sal * 1.4, -3) END, CASE WHEN r < 0.7 THEN 1 END, CASE WHEN r < 0.7 THEN 1 ELSE 2 END,
             greatest(1, (t.positions * (0.5 + random()))::int), 2, random() < 0.3, e.at,
             CASE WHEN random() < 0.4 THEN (e.at + (30 + floor(random() * 60)::int) * interval '1 day')::date END, e.at - interval '1 hour', u
      FROM organisation o CROSS JOIN (SELECT random() AS r) x WHERE o.id = e.organisation_id
      RETURNING id INTO j;
      INSERT INTO job_requirement_skill (job_requirement_id, skill_id, is_mandatory, created_at, created_by)
      SELECT j, id, true, e.at, u FROM skill WHERE name = t.skill
      UNION SELECT j, pg_temp.skill_id(), false, e.at, u FROM generate_series(1, 1 + floor(random() * 3)::int)
      ON CONFLICT DO NOTHING;
      INSERT INTO job_requirement_location (job_requirement_id, city_id, created_at, created_by)
      SELECT DISTINCT j, pg_temp.city(), e.at, u FROM generate_series(1, pg_temp.skewed(3, 2)) ON CONFLICT DO NOTHING;
      IF random() < 0.4 THEN
        INSERT INTO screening_question (job_requirement_id, question_text, answer_type_id, is_required, sort_order, created_at, created_by)
        SELECT j, q.txt, q.typ, q.req, row_number() OVER (), e.at, u
        FROM (SELECT * FROM (VALUES ('Are you willing to relocate?', 1, true), ('How many years of relevant experience do you have?', 2, true),
                                    ('What is your notice period?', 3, false), ('Do you have a two-wheeler and licence?', 1, false)) v (txt, typ, req)
              ORDER BY random() LIMIT 1 + floor(random() * 3)::int) q;
      END IF;

    ELSIF e.kind = 'download' THEN
      SELECT app_user_id INTO u FROM organisation_member
      WHERE organisation_id = e.organisation_id AND valid_from <= e.at AND access_role_id IN (3, 4, 5) ORDER BY random() LIMIT 1;
      SELECT id INTO cand FROM sp WHERE profile_visibility_id <> 3 AND created_at < e.at AND id >= (SELECT floor(random() * max(id)) FROM sp) ORDER BY id LIMIT 1;
      IF cand IS NOT NULL AND NOT EXISTS (SELECT 1 FROM profile_download WHERE organisation_id = e.organisation_id AND candidate_profile_id = cand
                                          AND downloaded_at > e.at - interval '30 days') THEN
        INSERT INTO profile_download (organisation_id, app_user_id, candidate_profile_id, wallet_ledger_entry_id, downloaded_at, created_at, created_by)
        VALUES (e.organisation_id, u, cand, wallet_post(w, 'profile_download_debit', -1, 'download:' || e.id, p_occurred_at => e.at), e.at, e.at, u);
      END IF;
    END IF;
    n := n + 1;
  END LOOP;
  RAISE NOTICE 'processed % events', n;
END $$;

-- a few recruiters left their company: the membership is closed, never deleted (history kept)
UPDATE organisation_member SET valid_to = valid_from + (now() - valid_from) / 2 WHERE access_role_id = 5 AND valid_to IS NULL AND random() < 0.05;

-- 5. draft jobs (never published, so never charged) and applications -------------------------------------------------
INSERT INTO job_requirement (organisation_id, title, description, employment_type_id, work_mode_id, industry_id, salary_disclosure_id, created_at, created_by)
SELECT o.id, 'Draft: ' || t.title, 'Draft description for ' || t.title || '.', t.employment_type_id, 1, (SELECT id FROM industry WHERE code = t.industry_code), 2,
       now() - random() * interval '20 days', (SELECT app_user_id FROM organisation_member m WHERE m.organisation_id = o.id ORDER BY m.id LIMIT 1)
FROM generate_series(1, greatest(5, :profiles / 200)) g
CROSS JOIN LATERAL (SELECT id FROM organisation WHERE g > 0 ORDER BY random() LIMIT 1) o
CROSS JOIN LATERAL (SELECT * FROM job_template WHERE g > 0 ORDER BY random() LIMIT 1) t;

CREATE TEMP TABLE sj AS
SELECT j.id, j.organisation_id, j.published_at, j.is_open_to_consultants,
       least(now() - interval '1 hour', coalesce(j.closes_on::timestamptz, now())) AS open_until, row_number() OVER (ORDER BY random()) AS rk
FROM job_requirement j WHERE j.job_status_id = 2;
CREATE INDEX ON sj (rk);
-- candidates who are open to work apply more; some jobs attract far more applicants than others
CREATE TEMP TABLE sa AS
WITH picks AS MATERIALIZED (
  SELECT pg_temp.skewed((SELECT count(*)::int FROM sj), 1.6) AS job_rk,
         (SELECT min(id) FROM sp) + pg_temp.skewed((SELECT count(*)::int FROM sp), 1.2) - 1 AS profile_id
  FROM generate_series(1, :profiles * 6) g)
SELECT DISTINCT ON (j.id, p.id) j.id AS job_id, p.id AS profile_id, p.app_user_id, j.organisation_id, j.is_open_to_consultants,
       greatest(j.published_at, p.created_at) AS window_start, j.open_until AS window_end
FROM picks k JOIN sj j ON j.rk = k.job_rk JOIN sp p ON p.id = k.profile_id
WHERE greatest(j.published_at, p.created_at) < j.open_until;

INSERT INTO application (job_requirement_id, candidate_profile_id, resume_id, application_source_id, sourced_by_app_user_id, applied_at, created_at, created_by)
SELECT a.job_id, a.profile_id, r.id, src,
       CASE src WHEN 2 THEN (SELECT app_user_id FROM organisation_member m WHERE m.organisation_id = a.organisation_id AND m.valid_to IS NULL ORDER BY random() LIMIT 1)
                WHEN 3 THEN (SELECT u.id FROM app_user u WHERE u.email LIKE 'consultant%' ORDER BY random() LIMIT 1) END,
       t, t, a.app_user_id
FROM sa a
CROSS JOIN LATERAL (SELECT pg_temp.between_ts(a.window_start, a.window_end) AS t, random() AS x) v
CROSS JOIN LATERAL (SELECT CASE WHEN v.x < 0.05 THEN 2 WHEN v.x < 0.08 AND a.is_open_to_consultants THEN 3 WHEN v.x < 0.12 THEN 4
                                WHEN v.x < 0.15 THEN 5 ELSE 1 END AS src) s
LEFT JOIN resume r ON r.candidate_profile_id = a.profile_id AND r.is_primary;

INSERT INTO application_answer (application_id, job_requirement_id, screening_question_id, answer_text, created_at, created_by)
SELECT a.id, a.job_requirement_id, q.id,
       CASE q.answer_type_id WHEN 1 THEN pg_temp.pick(ARRAY['yes', 'no']) WHEN 2 THEN floor(random() * 12)::int::text
            ELSE pg_temp.pick(ARRAY['Immediate joiner', '30 days', '60 days', 'Serving notice']) END,
       a.applied_at, a.created_by
FROM application a JOIN screening_question q ON q.job_requirement_id = a.job_requirement_id
WHERE q.is_required OR random() < 0.6;

-- 6. the pipeline: each application gets a final stage; updates walk it step by step through the guard trigger --------
CREATE TEMP TABLE pipeline AS
SELECT id, job_requirement_id, applied_at,
       CASE WHEN r < 0.72 THEN 1 WHEN r < 0.85 THEN 2 WHEN r < 0.94 THEN 3 WHEN r < 0.985 THEN 4 ELSE 5 END AS max_stage,
       CASE WHEN r < 0.32 THEN NULL WHEN r < 0.70 THEN 6 WHEN r < 0.72 THEN 7
            WHEN r < 0.85 THEN (ARRAY[NULL, 6, 6, 7]::int[])[1 + floor(random() * 4)::int]
            WHEN r < 0.94 THEN (ARRAY[NULL, 6, 6, 7]::int[])[1 + floor(random() * 4)::int]
            WHEN r < 0.985 THEN (ARRAY[NULL, NULL, 6, 7]::int[])[1 + floor(random() * 4)::int] END AS terminal
FROM (SELECT a.id, a.job_requirement_id, a.applied_at, random() AS r FROM application a) x;
-- joins are capped by the positions of each job; extra would-be joiners stay at "offered"
UPDATE pipeline p SET max_stage = 4 FROM (
  SELECT pl.id, row_number() OVER (PARTITION BY pl.job_requirement_id ORDER BY pl.applied_at) AS n, j.positions_total
  FROM pipeline pl JOIN job_requirement j ON j.id = pl.job_requirement_id WHERE pl.max_stage = 5) c
WHERE p.id = c.id AND c.n > c.positions_total;

DO $$
BEGIN
  FOR s IN 2 .. 5 LOOP
    UPDATE application a SET application_status_id = s, status_changed_at = a.applied_at + (now() - a.applied_at) * (0.18 * (s - 1))
    FROM pipeline p WHERE p.id = a.id AND p.max_stage >= s;
  END LOOP;
  UPDATE application a SET application_status_id = p.terminal, status_changed_at = a.applied_at + (now() - a.applied_at) * (0.18 * p.max_stage + 0.05)
  FROM pipeline p WHERE p.id = a.id AND p.terminal IS NOT NULL;
END $$;

-- final job states: some closed by hand or past their closing date, some paused (filled jobs were closed by the trigger)
UPDATE job_requirement SET job_status_id = 4 WHERE job_status_id = 2 AND (closes_on < current_date OR random() < 0.12);
UPDATE job_requirement SET job_status_id = 3 WHERE job_status_id = 2 AND random() < 0.05;
UPDATE job_requirement SET deleted_at = now() - random() * interval '30 days' WHERE job_status_id = 4 AND random() < 0.03;
-- profiles were active at least when they last applied
UPDATE candidate_profile p SET last_active_at = greatest(p.last_active_at, a.last_applied)
FROM (SELECT candidate_profile_id, max(applied_at) AS last_applied FROM application GROUP BY 1) a WHERE a.candidate_profile_id = p.id;

-- 7. blocks ----------------------------------------------------------------------------------------------------------
INSERT INTO candidate_block (candidate_profile_id, blocked_organisation_id, blocked_at, created_at, created_by)
SELECT DISTINCT ON (a.candidate_profile_id) a.candidate_profile_id, a.organisation_id, t, t, p.app_user_id
FROM application a JOIN sp p ON p.id = a.candidate_profile_id
CROSS JOIN LATERAL (SELECT pg_temp.between_ts(a.applied_at, now()) AS t) v
WHERE random() < 0.004;
INSERT INTO candidate_block (candidate_profile_id, blocked_app_user_id, blocked_at, created_at, created_by)
SELECT p.id, m.app_user_id, now() - interval '3 days', now() - interval '3 days', p.app_user_id
FROM (SELECT id, app_user_id FROM sp ORDER BY random() LIMIT greatest(3, :profiles / 1000)) p
CROSS JOIN LATERAL (SELECT app_user_id FROM organisation_member WHERE access_role_id = 5 AND valid_to IS NULL AND p.id > 0 ORDER BY random() LIMIT 1) m
ON CONFLICT DO NOTHING;
UPDATE candidate_block SET unblocked_at = blocked_at + (now() - blocked_at) / 2 WHERE random() < 0.1;

-- 8. devices and sessions -------------------------------------------------------------------------------------------
INSERT INTO user_device (app_user_id, device_fingerprint_hash, device_label, first_seen_at, last_seen_at, created_at, created_by)
SELECT u.id, pg_temp.sha('device:' || u.id || ':' || d), pg_temp.pick(ARRAY['Chrome on Windows', 'Android app', 'iPhone app', 'Firefox on Linux', 'Safari on Mac']),
       u.created_at, pg_temp.between_ts(u.created_at, now()), u.created_at, u.id
FROM app_user u CROSS JOIN LATERAL generate_series(1, CASE WHEN u.id % 10 < 6 THEN 1 WHEN u.id % 10 < 9 THEN 2 ELSE 3 END) d;
UPDATE user_device SET last_seen_at = greatest(last_seen_at, first_seen_at);
-- ended sessions (login history) ...
INSERT INTO user_session (app_user_id, user_device_id, token_hash, started_at, last_activity_at, expires_at, ended_at, session_end_reason_id, created_at, created_by)
SELECT d.app_user_id, d.id, pg_temp.sha(gen_random_uuid()::text), s, s + interval '20 minutes', s + interval '30 days', s + interval '25 minutes',
       CASE WHEN random() < 0.6 THEN 1 ELSE 2 END, s, d.app_user_id
FROM user_device d CROSS JOIN LATERAL generate_series(1, 1 + (d.id % 3)::int) g
CROSS JOIN LATERAL (SELECT pg_temp.between_ts(greatest(d.first_seen_at, now() - interval '60 days'), now() - interval '1 day') AS s) v;
-- ... and one active session for 40% of users, on their first device (within every device limit)
INSERT INTO user_session (app_user_id, user_device_id, token_hash, started_at, last_activity_at, expires_at, created_at, created_by)
SELECT DISTINCT ON (d.app_user_id) d.app_user_id, d.id, pg_temp.sha(gen_random_uuid()::text), s, s, s + interval '30 days', s, d.app_user_id
FROM (SELECT ud.*, now() - random() * interval '6 days' AS s FROM user_device ud) d
WHERE d.app_user_id % 5 < 2 ORDER BY d.app_user_id, d.id;
-- real logins through the device-limit function: org staff on new devices; attempts over the limit are refused and audited
DO $$
DECLARE r record; refused int := 0;
BEGIN
  FOR r IN SELECT m.app_user_id FROM organisation_member m WHERE m.valid_to IS NULL ORDER BY random() LIMIT greatest(20, current_setting('seed.profiles')::int / 50) LOOP
    FOR d IN 1 .. 4 LOOP
      IF auth_open_session(r.app_user_id, pg_temp.sha('newdevice:' || r.app_user_id || ':' || d), 'Seed login device ' || d, pg_temp.sha(gen_random_uuid()::text)) IS NULL THEN
        refused := refused + 1;
      END IF;
    END LOOP;
  END LOOP;
  RAISE NOTICE 'logins refused at the device limit: %', refused;
END $$;
-- users revoke an old device now and then (auditable action)
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT s.id, s.app_user_id FROM user_session s WHERE s.ended_at IS NULL ORDER BY random() LIMIT 25 LOOP
    PERFORM set_config('app.user_id', r.app_user_id::text, true);
    PERFORM auth_end_session(r.id, 'revoked_by_user');
  END LOOP;
  PERFORM set_config('app.user_id', '', true);
END $$;

-- 9. preferences, job alerts, notifications -------------------------------------------------------------------------
INSERT INTO notification_preference (app_user_id, notification_category_id, notification_channel_id, is_enabled, created_at, created_by)
SELECT app_user_id, c, ch, false, created_at, app_user_id
FROM sp CROSS JOIN LATERAL (VALUES (5, 1), (5, 2), (1, 3)) v (c, ch) WHERE random() < 0.1;
INSERT INTO job_alert (candidate_profile_id, keywords, city_id, min_salary_amount, salary_currency_id, alert_frequency_id, last_sent_at, created_at, created_by)
SELECT p.id, pg_temp.skill_name(), CASE WHEN random() < 0.7 THEN pg_temp.city() END,
       CASE WHEN x < 0.3 THEN 300000 END, CASE WHEN x < 0.3 THEN 1 END, pg_temp.skewed(3, 1.5), now() - random() * interval '7 days', p.created_at, p.app_user_id
FROM (SELECT sp.*, random() AS x FROM sp) p WHERE random() < 0.3;
INSERT INTO notification (app_user_id, notification_category_id, notification_channel_id, template_key, payload, queued_at, next_attempt_at, created_at)
SELECT p.app_user_id, 1, (ARRAY[1, 3, 4])[1 + floor(random() * 3)::int], 'job_alert.digest', jsonb_build_object('job_alert_id', a.id, 'matches', 1 + floor(random() * 9)::int), t, t, t
FROM job_alert a JOIN sp p ON p.id = a.candidate_profile_id
CROSS JOIN LATERAL (SELECT now() - random() * interval '60 days' + 0 * a.id * interval '1 s' AS t FROM generate_series(1, 4)) v;
-- delivery outcomes for everything older than 10 minutes
WITH x AS MATERIALIZED (SELECT id, random() AS r FROM notification WHERE notification_status_id = 1 AND queued_at < now() - interval '10 minutes')
UPDATE notification n SET notification_status_id = CASE WHEN r < 0.02 THEN 4 WHEN r < 0.05 THEN 2 ELSE 3 END,
       attempt_count = CASE WHEN r < 0.02 THEN 5 ELSE 1 END, sent_at = queued_at + interval '1 minute',
       delivered_at = CASE WHEN r >= 0.05 THEN queued_at + interval '2 minutes' END,
       provider_message_ref = 'msg_' || n.id, failure_reason = CASE WHEN r < 0.02 THEN 'recipient unreachable' END
FROM x WHERE x.id = n.id;

-- 10. system errors ---------------------------------------------------------------------------------------------------
INSERT INTO system_error (occurred_at, service_name, error_code, message, app_user_id, context)
SELECT now() - random() * interval '80 days', pg_temp.pick(ARRAY['api', 'notification-worker', 'payment-webhook', 'search']),
       pg_temp.pick(ARRAY['TIMEOUT', 'UPSTREAM_5XX', 'VALIDATION', 'RATE_LIMITED']), 'Synthetic error for monitoring tests',
       CASE WHEN random() < 0.5 THEN (SELECT id FROM app_user WHERE g > 0 ORDER BY random() LIMIT 1) END, jsonb_build_object('request_id', gen_random_uuid())
FROM generate_series(1, greatest(50, :profiles / 20)) g;

SELECT refresh_aggregates() \g /dev/null
