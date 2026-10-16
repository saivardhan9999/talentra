-- =============================================================================
-- Talentra seed :: 03_organisations.sql  (B62: users, roles, organisations, mapped recruiters)
-- Distributions:
--   organisations  20k; 85% direct employers, 12% staffing agencies, 3% clients; size skewed small;
--                  60% verified, 30% pending, 5% rejected, 5% expired; 97% active; 5% are subsidiaries
--   locations      one headquarters each (big cities favoured) + a branch for 30%
--   identifiers    60% have a GSTIN (vault token + HMAC + masked form only); verified ones carry evidence
--   people         one employer per organisation, 2-6 recruiters, an account admin for 20%;
--                  2% of recruiters moved company (ended mapping + new mapping: effective-dated history)
--   platform       5k consultants, 500 placement officers, 4 platform admins (1 super admin)
-- =============================================================================
\set ON_ERROR_STOP on
SET app.current_user_id = '1';
SET synchronous_commit = off;

CREATE TABLE seed.org AS
SELECT g,
       seed.pick(ARRAY['Sri','Apex','Blue','Bharat','Global','Vision','Prime','Sunrise','Metro','Nova','Shakti','Zenith','Pioneer','Royal','Unity',
                       'Lakshmi','Ganesh','Matrix','Sapphire','Orbit'], g, 1) || ' ' ||
       seed.pick(ARRAY['Infotech','Logistics','Staffing','Pharma','Retail','Motors','Textiles','Foods','Builders','Fintech','Healthcare','Electricals',
                       'Consulting','Hospitality','Agro','Solutions','Technologies','Manpower','Engineering','Traders'], g, 2) AS core,
       seed.pick(ARRAY['Pvt Ltd','Private Limited','LLP','Ltd','India Pvt Ltd'], g, 3) AS suffix,
       CASE WHEN seed.r(g, 4) < 0.85 THEN 1 WHEN seed.r(g, 4) < 0.97 THEN 2 ELSE 3 END AS org_type,
       seed.skew(6, g, 5, 1.8) AS size_band,
       now() - interval '600 days' - interval '400 days' * seed.r(g, 6) AS created_at   -- every organisation predates its postings
FROM generate_series(1, seed.n(20000)) g;
ALTER TABLE seed.org ADD PRIMARY KEY (g);
ALTER TABLE seed.org ADD COLUMN slug text;
UPDATE seed.org SET slug = lower(regexp_replace(core, '[^A-Za-z]', '', 'g')) || g;

INSERT INTO organisation (legal_name, trade_name, organisation_type_id, industry_id, company_size_band_id, founded_year, website_url,
                          contact_email, contact_phone_e164, contact_phone_country_id, organisation_account_status_id, verification_status_id,
                          created_at, updated_at)
SELECT o.core || ' ' || o.suffix, CASE WHEN seed.r(o.g, 7) < 0.4 THEN o.core END, o.org_type,
       (SELECT id FROM industry ORDER BY id OFFSET floor(seed.r(o.g, 8) * 30)::int LIMIT 1), o.size_band,
       1950 + floor(seed.r(o.g, 9) * 75)::int, 'https://www.' || o.slug || '.in', 'hr@' || o.slug || '.in',
       '+9180' || lpad(floor(seed.r(o.g, 10) * 99999999)::bigint::text, 8, '0'), (SELECT id FROM country WHERE iso_alpha2 = 'IN'),
       CASE WHEN seed.r(o.g, 11) < 0.97 THEN 1 WHEN seed.r(o.g, 11) < 0.99 THEN 2 ELSE 3 END,
       CASE WHEN seed.r(o.g, 12) < 0.60 THEN 2 WHEN seed.r(o.g, 12) < 0.90 THEN 1 WHEN seed.r(o.g, 12) < 0.95 THEN 3 ELSE 4 END,
       o.created_at, o.created_at
FROM seed.org o ORDER BY o.g;
ALTER TABLE seed.org ADD COLUMN org_id bigint;
UPDATE seed.org o SET org_id = x.id FROM organisation x WHERE x.contact_email = 'hr@' || o.slug || '.in';
CREATE UNIQUE INDEX ON seed.org (org_id);

-- 5% are subsidiaries of an earlier (so never a descendant) organisation
UPDATE organisation x SET parent_organisation_id = p.org_id
FROM seed.org c JOIN seed.org p ON p.g = c.g / 10
WHERE x.id = c.org_id AND c.g > 100 AND seed.r(c.g, 13) < 0.05;

INSERT INTO organisation_location (organisation_id, city_id, address_line_1, postal_code, latitude, longitude, coordinate_source_id, is_headquarters)
SELECT o.org_id, cr.city_id, 'Plot ' || (1 + floor(seed.r(o.g * 2 + k, 14) * 300))::int || ', '
       || seed.pick(ARRAY['MG Road','Industrial Estate','IT Park','Ring Road','Station Road','Anna Salai','SIDCO Estate','Sector 62'], o.g * 2 + k, 15),
       lpad((110001 + floor(seed.r(o.g * 2 + k, 16) * 750000))::int::text, 6, '0'),
       round(ci.latitude + (seed.r(o.g * 2 + k, 17) - 0.5) * 0.1, 6), round(ci.longitude + (seed.r(o.g * 2 + k, 18) - 0.5) * 0.1, 6),
       ci.coordinate_source_id, k = 1
FROM seed.org o CROSS JOIN generate_series(1, 2) k
JOIN seed.city_rank cr ON cr.rank = seed.skew(60, o.g * 2 + k, 19, 1.6)
JOIN city ci ON ci.id = cr.city_id
WHERE k = 1 OR seed.r(o.g, 20) < 0.30;

INSERT INTO organisation_registration_identifier (organisation_id, registration_identifier_type_id, issuing_country_id, identifier_token,
                                                  identifier_hmac, identifier_masked, verification_status_id, verified_at, verification_ref)
SELECT o.org_id, 1, (SELECT id FROM country WHERE iso_alpha2 = 'IN'), 'vault_tok_' || md5('gstin' || o.g), seed.hmac('gstin' || o.g),
       lpad((1 + o.g % 37)::text, 2, '0') || 'XXXXXX' || lpad((o.g % 10000)::text, 4, '0') || 'X1Z' || (o.g % 10),
       x.verification_status_id,
       CASE WHEN x.verification_status_id = 2 THEN o.created_at + interval '3 days' END,
       CASE WHEN x.verification_status_id = 2 THEN 'GSTN-' || upper(substr(md5('ref' || o.g), 1, 12)) END
FROM seed.org o JOIN organisation x ON x.id = o.org_id
WHERE seed.r(o.g, 21) < 0.60;

-- People of the organisations: employer (role 6), recruiters (7), account admin (3)
CREATE TABLE seed.org_person AS
SELECT o.g AS org_g, o.org_id, k, CASE WHEN k = 1 THEN 6 WHEN k = 7 THEN 3 ELSE 7 END AS role_id,
       lower(seed.pick(ARRAY['anil','bhavna','chitra','dinesh','esha','farah','girish','hema','irfan','jyoti','kunal','latha','mahesh','nisha',
                             'omkar','preeti','rajiv','sowmya','tarun','usha','varun','yasmin'], o.g * 10 + k, 22))
       || '.' || k || '@' || o.slug || '.in' AS email,
       o.created_at + interval '1 day' * k AS joined_at
FROM seed.org o CROSS JOIN generate_series(1, 7) k
WHERE k = 1 OR (k BETWEEN 2 AND 6 AND k <= 2 + floor(seed.r(o.g, 23) * 5)) OR (k = 7 AND seed.r(o.g, 24) < 0.20);
INSERT INTO user_account (email, created_at, updated_at) SELECT email, joined_at, joined_at FROM seed.org_person ORDER BY org_g, k;
ALTER TABLE seed.org_person ADD COLUMN user_id bigint;
UPDATE seed.org_person p SET user_id = u.id FROM user_account u WHERE u.email = p.email;
CREATE INDEX ON seed.org_person (org_id, role_id);

INSERT INTO organisation_member (organisation_id, user_account_id, role_id, valid_from, valid_to)
SELECT org_id, user_id, role_id, joined_at,
       CASE WHEN role_id = 7 AND seed.r(user_id, 25) < 0.02 THEN joined_at + interval '120 days' END
FROM seed.org_person;
-- recruiters who moved: a new mapping at another organisation from the day the old one ended
INSERT INTO organisation_member (organisation_id, user_account_id, role_id, valid_from)
SELECT n.org_id, p.user_id, 7, m.valid_to
FROM seed.org_person p JOIN organisation_member m ON m.user_account_id = p.user_id AND m.valid_to IS NOT NULL
JOIN seed.org n ON n.g = 1 + (p.org_g * 7919) % (SELECT count(*) FROM seed.org)
WHERE n.org_id <> p.org_id;

-- Platform people
CREATE TABLE seed.platform_person AS
SELECT 'consultant' AS kind, g, 'consultant' || g || '@' || seed.pick(ARRAY['talentbridge.in','hirewise.in','gmail.com'], g, 26) AS email, 8 AS role_id
FROM generate_series(1, seed.n(5000)) g
UNION ALL SELECT 'tpo', g, 'tpo' || g || '@college' || g || '.edu.in', 9 FROM generate_series(1, seed.n(500)) g
UNION ALL SELECT 'admin', g, 'admin' || g || '@talentra.in', CASE WHEN g = 1 THEN 1 ELSE 2 END FROM generate_series(1, 4) g;
INSERT INTO user_account (email, created_at, updated_at) SELECT email, now() - interval '600 days', now() - interval '600 days' FROM seed.platform_person;
ALTER TABLE seed.platform_person ADD COLUMN user_id bigint;
UPDATE seed.platform_person p SET user_id = u.id FROM user_account u WHERE u.email = p.email;
INSERT INTO user_account_role (user_account_id, role_id, granted_at) SELECT user_id, role_id, now() - interval '600 days' FROM seed.platform_person;
INSERT INTO user_account_role (user_account_id, role_id, granted_at) SELECT user_id, 5, now() - interval '540 days' FROM seed.cand_user;

DO $$
BEGIN
    PERFORM seed.done('organisation: organisations', (SELECT count(*) FROM organisation));
    PERFORM seed.done('organisation: subsidiaries', (SELECT count(*) FROM organisation WHERE parent_organisation_id IS NOT NULL));
    PERFORM seed.done('organisation: locations', (SELECT count(*) FROM organisation_location));
    PERFORM seed.done('organisation: tax identifiers', (SELECT count(*) FROM organisation_registration_identifier));
    PERFORM seed.done('organisation: member mappings (incl. moves)', (SELECT count(*) FROM organisation_member));
    PERFORM seed.done('administration: platform users', (SELECT count(*) FROM seed.platform_person));
    PERFORM seed.done('administration: role grants', (SELECT count(*) FROM user_account_role));
END $$;
