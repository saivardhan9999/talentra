-- =============================================================================
-- Talentra seed :: 04_jobs_applications.sql  (B61: 100k job requirements, 5M applications, full pipeline)
-- Distributions:
--   requirements  posted by organisations skewed towards large employers; status 45% open, 20% closed,
--                 15% filled, 5% each on hold / draft / pending approval / cancelled; 15% open to
--                 consultants (fee 5-12%); 60% disclose salary; 5% described in Hindi
--   applications  only to published requirements; popularity skewed; final status follows the pipeline
--                 paths in seed.path (30.5% still applied, 38% rejected at some stage, 6% withdrawn,
--                 1.5% joined ...). Every application gets its full status history with dated steps.
--   activity      1M saved jobs, 2M searches, 3M candidate activity events, 2M profile views,
--                 talent lists with entries, 20k referrals
-- The two pipeline triggers stamp "now" on every status change, so for the bulk load they are paused
-- and history is written directly with real dates; every other trigger, constraint and FK stays on.
-- M20 proves each seeded history is a legal path through application_status_transition.
-- =============================================================================
\set ON_ERROR_STOP on
SET app.current_user_id = '1';
SET synchronous_commit = off;

-- ---------------------------------------------------------------- requirements
CREATE TABLE seed.job AS
SELECT g, o.org_id, p.user_id AS poster_id, jr.id AS role_id, jr.name AS role_name, cr.city_id, ci.name AS city_name, s.status,
       CASE WHEN seed.r(g, 6) < 0.15 THEN 'Senior ' WHEN seed.r(g, 6) < 0.25 THEN 'Junior ' WHEN seed.r(g, 6) < 0.30 THEN 'Lead ' ELSE '' END AS level,
       CASE WHEN seed.r(g, 7) < 0.70 THEN 1 + floor(seed.r(g, 8) * 3)::int
            WHEN seed.r(g, 7) < 0.95 THEN 4 + floor(seed.r(g, 8) * 7)::int ELSE 20 + floor(seed.r(g, 8) * 81)::int END AS positions,
       CASE WHEN s.status IN (3, 4) THEN now() - interval '120 days' * seed.r(g, 9)
            WHEN s.status IN (5, 6, 7) THEN now() - interval '60 days' - interval '480 days' * seed.r(g, 9) END AS published_at,
       seed.r(g, 10) < 0.15 AS consultant_open, seed.r(g, 11) < 0.60 AS salary_disclosed, seed.r(g, 12) < 0.05 AS hindi
FROM generate_series(1, seed.n(100000)) g
JOIN (SELECT g AS org_g, org_id FROM seed.org) o ON o.org_g = seed.skew((SELECT count(*) FROM seed.org), g, 1, 1.5)
JOIN seed.org_person p ON p.org_id = o.org_id AND p.k = 1
JOIN seed.role_rank jr ON jr.rank = 1 + floor(seed.r(g, 2) * (SELECT count(*) FROM seed.role_rank))
JOIN seed.city_rank cr ON cr.rank = seed.skew(60, g, 3, 1.6)
JOIN city ci ON ci.id = cr.city_id
CROSS JOIN LATERAL (SELECT CASE WHEN seed.r(g, 4) < 0.45 THEN 3 WHEN seed.r(g, 4) < 0.65 THEN 5 WHEN seed.r(g, 4) < 0.80 THEN 6
                                WHEN seed.r(g, 4) < 0.85 THEN 4 WHEN seed.r(g, 4) < 0.90 THEN 1 WHEN seed.r(g, 4) < 0.95 THEN 2 ELSE 7 END AS status) s;
ALTER TABLE seed.job ADD PRIMARY KEY (g);

INSERT INTO job_requirement (organisation_id, posted_by_user_account_id, requirement_code, title, description, description_language_id,
    job_category_id, employment_type_id, work_mode_id, job_role_id, industry_id, number_of_positions, min_experience_months, max_experience_months,
    salary_disclosure_status_id, salary_min_amount, salary_max_amount, salary_currency_id, salary_period_id,
    job_requirement_status_id, publish_state_id, published_at, expires_at, is_open_to_consultants, consultant_fee_pct, created_at, updated_at,
    created_by, updated_by)
SELECT j.org_id, j.poster_id, 'REQ-' || lpad(j.g::text, 7, '0'), j.level || j.role_name,
       CASE WHEN j.hindi THEN j.city_name || ' में ' || j.role_name || ' की भर्ती। अनुभव ' || x.min_m / 12 || ' वर्ष से। आज ही आवेदन करें।'
            ELSE 'We are hiring a ' || lower(j.level || j.role_name) || ' in ' || j.city_name || '. You will work with '
                 || seed.pick(ARRAY['java and spring boot','react and typescript','sql and power bi','tally and gst','two wheeler last mile delivery',
                                    'industrial electrical wiring','customer support in hindi and english','b2b field sales','warehouse inventory',
                                    'patient care in a multi-speciality hospital'], j.g, 13)
                 || '. Experience: ' || x.min_m / 12 || ' to ' || x.max_m / 12 || ' years. Benefits include PF, health insurance and paid leave.' END,
       (SELECT id FROM language WHERE code = CASE WHEN j.hindi THEN 'hi' ELSE 'en' END),
       CASE WHEN seed.r(j.g, 14) < 0.50 THEN 4 WHEN seed.r(j.g, 14) < 0.65 THEN 2 WHEN seed.r(j.g, 14) < 0.75 THEN 3 WHEN seed.r(j.g, 14) < 0.85 THEN 8
            WHEN seed.r(j.g, 14) < 0.90 THEN 6 WHEN seed.r(j.g, 14) < 0.95 THEN 5 ELSE 7 END,
       CASE WHEN seed.r(j.g, 15) < 0.75 THEN 1 WHEN seed.r(j.g, 15) < 0.85 THEN 3 WHEN seed.r(j.g, 15) < 0.92 THEN 4 ELSE 2 END,
       CASE WHEN seed.r(j.g, 16) < 0.70 THEN 1 WHEN seed.r(j.g, 16) < 0.90 THEN 3 ELSE 2 END,
       j.role_id, (SELECT id FROM industry ORDER BY id OFFSET floor(seed.r(j.g, 17) * 30)::int LIMIT 1),
       j.positions, x.min_m, x.max_m,
       CASE WHEN j.salary_disclosed THEN 1 ELSE 2 END,
       CASE WHEN j.salary_disclosed THEN round(180000 + x.min_m * 3000 * (0.8 + seed.r(j.g, 18)), -3) END,
       CASE WHEN j.salary_disclosed THEN round((180000 + x.min_m * 3000 * (0.8 + seed.r(j.g, 18))) * 1.4, -3) END,
       CASE WHEN j.salary_disclosed THEN 1 END, CASE WHEN j.salary_disclosed THEN 1 END,
       j.status, CASE WHEN j.published_at IS NULL THEN 1 WHEN j.status IN (3, 4) THEN 3 WHEN j.status = 7 THEN 5 ELSE 4 END,
       j.published_at, j.published_at + interval '30 days' + interval '60 days' * seed.r(j.g, 19) + CASE WHEN j.status IN (3, 4) THEN interval '120 days' ELSE interval '0' END,
       j.consultant_open, CASE WHEN j.consultant_open THEN round(5 + seed.r(j.g, 20) * 7, 2) END,
       coalesce(j.published_at, now() - interval '20 days' * seed.r(j.g, 21)) - interval '2 days',
       coalesce(j.published_at, now() - interval '20 days' * seed.r(j.g, 21)) - interval '2 days',
       j.poster_id, j.poster_id
FROM seed.job j
CROSS JOIN LATERAL (SELECT CASE WHEN j.level = 'Senior ' THEN 60 WHEN j.level = 'Lead ' THEN 96 WHEN j.level = 'Junior ' THEN 0
                                ELSE 12 * floor(seed.r(j.g, 22) * 4)::int END AS min_m) m
CROSS JOIN LATERAL (SELECT m.min_m, m.min_m + 24 + 12 * floor(seed.r(j.g, 23) * 4)::int AS max_m) x
ORDER BY j.g;
ALTER TABLE seed.job ADD COLUMN job_id bigint;
UPDATE seed.job j SET job_id = r.id FROM job_requirement r WHERE r.requirement_code = 'REQ-' || lpad(j.g::text, 7, '0');
CREATE UNIQUE INDEX ON seed.job (job_id);

INSERT INTO job_requirement_location (job_requirement_id, city_id) SELECT job_id, city_id FROM seed.job;
INSERT INTO job_requirement_location (job_requirement_id, city_id)
SELECT j.job_id, cr.city_id FROM seed.job j JOIN seed.city_rank cr ON cr.rank = seed.skew(30, j.g, 24)
WHERE seed.r(j.g, 25) < 0.25 AND cr.city_id <> j.city_id;
INSERT INTO job_requirement_skill (job_requirement_id, skill_id, is_mandatory, min_experience_months)
SELECT j.job_id, sr.skill_id, k <= 2, 12 * floor(seed.r(j.g * 5 + k, 26) * 3)::int
FROM seed.job j CROSS JOIN generate_series(1, 5) k
JOIN seed.skill_rank sr ON sr.rank = 1 + ((seed.skew(90, j.g, 27) - 1 + (k - 1) * 23) % 90)
WHERE k <= 3 + floor(seed.r(j.g, 28) * 3);
INSERT INTO job_position (job_requirement_id, position_number, city_id, job_position_status_id)
SELECT j.job_id, n, j.city_id, CASE WHEN j.status = 7 THEN 3 ELSE 1 END
FROM seed.job j CROSS JOIN LATERAL generate_series(1, j.positions) n;

-- ---------------------------------------------------------------- applications and their history
CREATE TABLE seed.path (bucket int PRIMARY KEY, lo numeric, hi numeric, path int[]);
-- status ids: 1 applied 2 screening 3 shortlisted 4 interview_scheduled 5 interviewed 6 offered 7 offer_accepted 8 joined
--             9 rejected 10 withdrawn 11 offer_declined 12 on_hold
INSERT INTO seed.path VALUES
 (1, 0.000, 0.305, '{1}'),              (2, 0.305, 0.385, '{1,2}'),          (3, 0.385, 0.455, '{1,3}'),
 (4, 0.455, 0.485, '{1,3,4}'),          (5, 0.485, 0.505, '{1,3,4,5}'),      (6, 0.505, 0.515, '{1,3,4,5,6}'),
 (7, 0.515, 0.520, '{1,3,4,5,6,7}'),    (8, 0.520, 0.535, '{1,3,4,5,6,7,8}'),(9, 0.535, 0.540, '{1,3,4,5,6,11}'),
 (10, 0.540, 0.790, '{1,9}'),           (11, 0.790, 0.840, '{1,2,9}'),       (12, 0.840, 0.890, '{1,3,9}'),
 (13, 0.890, 0.920, '{1,3,4,5,9}'),     (14, 0.920, 0.980, '{1,10}'),        (15, 0.980, 1.000, '{1,12}');

-- applications arrive while the posting is live (a small share of late ones comes from candidates who registered later)
CREATE TABLE seed.pub_job AS
SELECT row_number() OVER (ORDER BY j.g) AS rank, j.job_id, j.org_id, j.published_at,
       least(now(), r.expires_at) AS closes_at
FROM seed.job j JOIN job_requirement r ON r.id = j.job_id WHERE j.published_at IS NOT NULL;
CREATE UNIQUE INDEX ON seed.pub_job (rank);
CREATE TABLE seed.cand_resume AS
SELECT r.candidate_profile_id AS profile_id, max(v.id) AS version_id FROM resume r JOIN resume_version v ON v.resume_id = r.id GROUP BY 1;
CREATE UNIQUE INDEX ON seed.cand_resume (profile_id);

CREATE TABLE seed.app AS
WITH raw AS (
    SELECT a, c.profile_id, c.user_id, pj.job_id, pj.org_id,
           -- never before the job was published or the candidate registered, never in the future
           greatest(pj.published_at, least(now() - interval '1 hour', greatest(pj.published_at + (pj.closes_at - pj.published_at) * seed.r(a, 3), c.registered_at + interval '1 hour'))) AS applied_at,
           p.path, seed.r(a, 5) AS src
    FROM generate_series(1, seed.n(5000000)) a
    JOIN seed.cand_p c ON c.g = 1 + (a * 2654435761) % (SELECT count(*) FROM seed.cand_p)
    JOIN seed.pub_job pj ON pj.rank = seed.skew((SELECT count(*) FROM seed.pub_job), a, 2, 1.3)
    JOIN seed.path p ON seed.r(a, 4) >= p.lo AND seed.r(a, 4) < p.hi
)
SELECT DISTINCT ON (job_id, profile_id) *, (now() - applied_at) / cardinality(path) * (0.2 + 0.8 * seed.r(a, 6)) AS gap
FROM raw ORDER BY job_id, profile_id, a;

ALTER TABLE application DISABLE TRIGGER trg_application_status_guard;
ALTER TABLE application DISABLE TRIGGER trg_application_status_history;
INSERT INTO application (job_requirement_id, candidate_profile_id, application_status_id, status_changed_at, application_source_id, applied_at,
                         resume_version_id, cover_note, rejection_reason_id, legacy_source_system_id, legacy_record_ref,
                         created_at, created_by, updated_at, updated_by)
SELECT s.job_id, s.profile_id, s.path[cardinality(s.path)], s.applied_at + s.gap * (cardinality(s.path) - 1),
       CASE WHEN s.src < 0.70 THEN 1 WHEN s.src < 0.80 THEN 2 WHEN s.src < 0.83 THEN 3 WHEN s.src < 0.88 THEN 4
            WHEN s.src < 0.91 THEN 5 WHEN s.src < 0.95 THEN 6 ELSE 7 END,
       s.applied_at, cr.version_id,
       CASE WHEN seed.r(s.a, 7) < 0.10 THEN 'I am interested in this role and can join within a month.' END,
       CASE WHEN s.path[cardinality(s.path)] = 9 THEN 1 + floor(seed.r(s.a, 8) * 8)::int END,
       CASE WHEN s.src >= 0.95 THEN 1 END, CASE WHEN s.src >= 0.95 THEN 'LEGAPP-' || s.a END,
       s.applied_at, s.user_id, s.applied_at + s.gap * (cardinality(s.path) - 1), 1
FROM seed.app s LEFT JOIN seed.cand_resume cr ON cr.profile_id = s.profile_id;
ALTER TABLE application ENABLE TRIGGER trg_application_status_guard;
ALTER TABLE application ENABLE TRIGGER trg_application_status_history;

CREATE TABLE seed.app_id AS
SELECT s.a, x.id AS application_id, s.job_id, s.org_id, s.profile_id, s.path, s.applied_at, s.gap
FROM seed.app s JOIN application x ON x.job_requirement_id = s.job_id AND x.candidate_profile_id = s.profile_id;
CREATE INDEX ON seed.app_id (application_id);

INSERT INTO application_status_history (application_id, from_application_status_id, to_application_status_id, rejection_reason_id,
                                        changed_at, created_at, created_by)
SELECT s.application_id, CASE WHEN i > 1 THEN s.path[i - 1] END, st,
       CASE WHEN st = 9 THEN 1 + floor(seed.r(s.a, 8) * 8)::int END,
       s.applied_at + s.gap * (i - 1), s.applied_at + s.gap * (i - 1), 1
FROM seed.app_id s CROSS JOIN LATERAL unnest(s.path) WITH ORDINALITY u(st, i);

-- interviews, offers and placements for the applications that reached those stages
INSERT INTO interview (application_id, round_number, interview_round_type_id, interview_mode_id, scheduled_start_at, scheduled_end_at,
                       display_time_zone, interviewer_user_account_id, interview_outcome_id, rating)
SELECT s.application_id, rnd, CASE WHEN rnd = 1 THEN 2 ELSE 3 END, 1 + floor(seed.r(s.a * 2 + rnd, 30) * 3)::int,
       s.applied_at + s.gap * (2 + rnd - 1), s.applied_at + s.gap * (2 + rnd - 1) + interval '45 minutes', 'Asia/Kolkata', p.user_id,
       CASE WHEN 5 = ANY (s.path) THEN CASE WHEN 6 = ANY (s.path) OR rnd = 1 THEN 1 ELSE 2 END END,
       CASE WHEN 5 = ANY (s.path) THEN round(2.5 + seed.r(s.a * 2 + rnd, 31) * 2.5, 1) END
FROM seed.app_id s CROSS JOIN generate_series(1, 2) rnd
JOIN seed.org_person p ON p.org_id = s.org_id AND p.k = 2
WHERE 4 = ANY (s.path) AND (rnd = 1 OR 6 = ANY (s.path));

INSERT INTO offer (application_id, offer_status_id, offered_at, salary_amount, salary_currency_id, salary_period_id,
                   proposed_joining_date, valid_until, responded_at)
SELECT s.application_id,
       CASE s.path[cardinality(s.path)] WHEN 6 THEN 1 WHEN 11 THEN 3 ELSE 2 END,
       s.applied_at + s.gap * 4, coalesce(r.salary_max_amount, round(240000 + seed.r(s.a, 32) * 900000, -3)), 1, 1,
       (s.applied_at + s.gap * 4 + interval '30 days')::date, (s.applied_at + s.gap * 4 + interval '14 days')::date,
       CASE WHEN s.path[cardinality(s.path)] <> 6 THEN s.applied_at + s.gap * 5 END
FROM seed.app_id s JOIN job_requirement r ON r.id = s.job_id
WHERE 6 = ANY (s.path);

INSERT INTO placement (application_id, job_position_id, job_requirement_id, offer_id, joined_on)
SELECT x.application_id, jp.id, x.job_id, o.id, (x.applied_at + x.gap * 6)::date
FROM (SELECT s.*, row_number() OVER (PARTITION BY s.job_id ORDER BY s.application_id) AS n FROM seed.app_id s WHERE 8 = ANY (s.path)) x
JOIN job_position jp ON jp.job_requirement_id = x.job_id AND jp.position_number = x.n
JOIN offer o ON o.application_id = x.application_id;
UPDATE job_position jp SET job_position_status_id = 2 FROM placement pl WHERE pl.job_position_id = jp.id;

-- ---------------------------------------------------------------- candidate activity and employer engagement
INSERT INTO saved_job (candidate_profile_id, job_requirement_id, saved_at)
SELECT c.profile_id, pj.job_id, pj.published_at + (pj.closes_at - pj.published_at) * seed.r(v, 41)
FROM generate_series(1, seed.n(1000000)) v
JOIN seed.cand_p c ON c.g = 1 + (v * 40503) % (SELECT count(*) FROM seed.cand_p)
JOIN seed.pub_job pj ON pj.rank = seed.skew((SELECT count(*) FROM seed.pub_job), v, 42, 1.3)
ON CONFLICT DO NOTHING;

INSERT INTO job_search_event (user_account_id, anonymous_session_ref, searched_at, keyword_text, city_id, result_count)
SELECT CASE WHEN seed.r(v, 43) < 0.8 THEN c.user_id END, CASE WHEN seed.r(v, 43) >= 0.8 THEN 'anon-' || md5(v::text) END,
       seed.ts(v, 44), lower(jr.name), CASE WHEN seed.r(v, 45) < 0.7 THEN cr.city_id END, floor(seed.r(v, 46) * 400)::int
FROM generate_series(1, seed.n(2000000)) v
JOIN seed.cand_p c ON c.g = 1 + (v * 7907) % (SELECT count(*) FROM seed.cand_p)
JOIN seed.role_rank jr ON jr.rank = 1 + floor(seed.r(v, 47) * (SELECT count(*) FROM seed.role_rank))
JOIN seed.city_rank cr ON cr.rank = seed.skew(60, v, 48);

INSERT INTO candidate_activity_log (candidate_profile_id, activity_type_id, occurred_at, source_ip)
SELECT c.profile_id, CASE WHEN seed.r(v, 49) < 0.60 THEN 1 WHEN seed.r(v, 49) < 0.80 THEN 3 WHEN seed.r(v, 49) < 0.90 THEN 4
                          WHEN seed.r(v, 49) < 0.97 THEN 5 ELSE 8 END,
       seed.ts(v, 50), ('10.' || (v % 250) || '.' || ((v / 250) % 250) || '.' || (1 + v % 250))::inet
FROM generate_series(1, seed.n(3000000)) v
JOIN seed.cand_p c ON c.g = 1 + (v * 6007) % (SELECT count(*) FROM seed.cand_p);

INSERT INTO profile_view_event (candidate_profile_id, viewer_user_account_id, viewer_organisation_id, view_context_id, job_requirement_id, viewed_at)
SELECT c.profile_id, p.user_id, p.org_id, 1 + floor(seed.r(v, 51) * 5)::int, CASE WHEN seed.r(v, 52) < 0.5 THEN pj.job_id END, seed.ts(v, 53)
FROM generate_series(1, seed.n(2000000)) v
JOIN seed.cand_p c ON c.g = 1 + (v * 5003) % (SELECT count(*) FROM seed.cand_p)
JOIN seed.pub_job pj ON pj.rank = seed.skew((SELECT count(*) FROM seed.pub_job), v, 54, 1.3)
JOIN seed.org_person p ON p.org_id = pj.org_id AND p.k = 2;

-- talent lists (shortlists and bookmarks) kept by recruiters, with shortlist history
INSERT INTO talent_list (owner_user_account_id, organisation_id, talent_list_type_id, job_requirement_id, name)
SELECT p.user_id, p.org_id, CASE WHEN seed.r(p.user_id, 55) < 0.7 THEN 1 ELSE 2 END,
       (SELECT job_id FROM seed.job j WHERE j.org_id = p.org_id ORDER BY j.g LIMIT 1),
       'Shortlist ' || p.k || ' - ' || to_char(p.joined_at, 'Mon YYYY')
FROM seed.org_person p WHERE p.role_id = 7 AND seed.r(p.user_id, 56) < 0.5;
INSERT INTO talent_list_entry (talent_list_id, candidate_profile_id, added_at, added_by_user_account_id, removed_at, removed_by_user_account_id)
SELECT DISTINCT ON (t.id, c.profile_id) t.id, c.profile_id, t.created_at + interval '1 day' * n, t.owner_user_account_id,
       CASE WHEN seed.r(t.id * 40 + n, 57) < 0.10 THEN t.created_at + interval '1 day' * (n + 5) END,
       CASE WHEN seed.r(t.id * 40 + n, 57) < 0.10 THEN t.owner_user_account_id END
FROM talent_list t CROSS JOIN generate_series(1, 30) n
JOIN seed.cand_p c ON c.g = 1 + (t.id * 104729 + n * 7919) % (SELECT count(*) FROM seed.cand_p)
WHERE n <= 10 + floor(seed.r(t.id, 58) * 21)
ORDER BY t.id, c.profile_id, n;

INSERT INTO referral (referrer_user_account_id, referral_code, referred_email, referred_candidate_profile_id, job_requirement_id,
                      referral_status_id, referred_at, converted_at)
SELECT c.user_id, 'REF' || upper(substr(md5('ref' || v), 1, 10)),
       CASE WHEN seed.r(v, 59) < 0.6 THEN 'friend' || v || '@gmail.com' END,
       CASE WHEN seed.r(v, 59) >= 0.6 THEN c2.profile_id END,
       pj.job_id, CASE WHEN seed.r(v, 59) < 0.6 THEN 1 ELSE 2 + floor(seed.r(v, 60) * 3)::int END,
       pj.published_at, CASE WHEN seed.r(v, 59) >= 0.6 THEN pj.published_at + interval '5 days' END
FROM generate_series(1, seed.n(20000)) v
JOIN seed.cand_p c ON c.g = 1 + (v * 3001) % (SELECT count(*) FROM seed.cand_p)
JOIN seed.cand_p c2 ON c2.g = 1 + (v * 9973) % (SELECT count(*) FROM seed.cand_p)
JOIN seed.pub_job pj ON pj.rank = 1 + (v * 31) % (SELECT count(*) FROM seed.pub_job);

DO $$
BEGIN
    PERFORM seed.done('jobs: requirements', (SELECT count(*) FROM job_requirement));
    PERFORM seed.done('jobs: locations + skills', (SELECT count(*) FROM job_requirement_location) + (SELECT count(*) FROM job_requirement_skill));
    PERFORM seed.done('jobs: positions', (SELECT count(*) FROM job_position));
    PERFORM seed.done('applications: applications', (SELECT count(*) FROM application));
    PERFORM seed.done('applications: status history', (SELECT count(*) FROM application_status_history));
    PERFORM seed.done('applications: interviews / offers / placements',
        (SELECT count(*) FROM interview) + (SELECT count(*) FROM offer) + (SELECT count(*) FROM placement));
    PERFORM seed.done('activity: saved jobs', (SELECT count(*) FROM saved_job));
    PERFORM seed.done('activity: searches', (SELECT count(*) FROM job_search_event));
    PERFORM seed.done('activity: candidate activity log', (SELECT count(*) FROM candidate_activity_log));
    PERFORM seed.done('activity: profile views', (SELECT count(*) FROM profile_view_event));
    PERFORM seed.done('activity: talent lists + entries', (SELECT count(*) FROM talent_list) + (SELECT count(*) FROM talent_list_entry));
    PERFORM seed.done('activity: referrals', (SELECT count(*) FROM referral));
END $$;
