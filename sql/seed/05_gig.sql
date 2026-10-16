-- =============================================================================
-- Talentra seed :: 05_gig.sql  (B62: gig requests and assignments, including overlap attempts)
-- Distributions:
--   workers        50k self-registered gig workers, 1-3 services each (trade, tool and field skills),
--                  1-2 availability windows; base city skewed to metros
--   requests       20k; 70% posted for an organisation by a mapped member, 30% by individuals;
--                  windows of 4 hours to 5 days across the last 300 days and the next 30;
--                  final status 45% filled, 25% open, 15% closed, 10% cancelled, 5% draft
--   applications   3 per open-or-later request on average, from popular workers (skewed)
--   assignments    one accepted application per filled request; popular workers win overlapping gigs,
--                  and every overlap attempt is rejected by uq_gig_assignment_no_overlap and logged
--                  to system_error_event (error_code gig_assignment_overlap)
--   outcomes       past windows: 85% completed (rated 80% of the time, earnings reported), 5% disputed,
--                  10% cancelled; future windows stay handed off
--   lists          favourites and blacklists kept by requesters, added after the gigs ran
-- All rows are written by the system actor (user 1), which every gig rule accepts as the migration path.
-- =============================================================================
\set ON_ERROR_STOP on
SET app.current_user_id = '1';
SET synchronous_commit = off;

INSERT INTO user_account (email, created_at, updated_at)
SELECT 'gigworker' || g || '@gmail.com', seed.ts(g, 1), seed.ts(g, 1) FROM generate_series(1, seed.n(50000)) g;
CREATE TABLE seed.worker AS
SELECT g, u.id AS user_id FROM generate_series(1, seed.n(50000)) g JOIN user_account u ON u.email = 'gigworker' || g || '@gmail.com';
INSERT INTO gig_worker_profile (user_account_id, display_name, headline, base_city_id, is_available, created_at, updated_at)
SELECT w.user_id,
       seed.pick(ARRAY['Ravi','Sunil','Meena','Arif','Kumar','Lakshmi','Rajesh','Pooja','Imran','Selvi','Babu','Geeta','Manoj','Anita'], w.g, 2)
       || ' ' || seed.pick(ARRAY['K','S','R','M','P','B','N','T'], w.g, 3),
       seed.pick(ARRAY['Electrician for homes and offices','Two-wheeler delivery partner','Plumbing and bathroom fittings','AC and HVAC servicing',
                       'Event staff and promoters','Data entry and back office','Carpentry and furniture repair','Driver with LMV licence',
                       'Warehouse loading and packing','Tailoring and alterations'], w.g, 4),
       cr.city_id, seed.r(w.g, 5) < 0.8, seed.ts(w.g, 1), seed.ts(w.g, 1)
FROM seed.worker w JOIN seed.city_rank cr ON cr.rank = seed.skew(40, w.g, 6, 1.6);
ALTER TABLE seed.worker ADD COLUMN profile_id bigint;
UPDATE seed.worker w SET profile_id = p.id FROM gig_worker_profile p WHERE p.user_account_id = w.user_id;
CREATE UNIQUE INDEX ON seed.worker (g);

CREATE TABLE seed.gig_skill AS
SELECT row_number() OVER (ORDER BY id) AS rank, id, name FROM skill
WHERE code IN ('electrical_wiring','welding','plumbing','carpentry','driving_lmv','driving_hmv','two_wheeler_riding','forklift_operation',
               'machine_operation','hvac_maintenance','masonry','tailoring','nursing_care','ms_excel','ms_office','telecalling','field_sales','customer_service');
INSERT INTO gig_worker_service (gig_worker_profile_id, skill_id, title, gig_price_type_id, rate_amount, rate_currency_id)
SELECT DISTINCT ON (w.profile_id, s.id) w.profile_id, s.id, s.name || ' services', 1 + floor(seed.r(w.g * 3 + k, 7) * 3)::int,
       round(200 + seed.r(w.g * 3 + k, 8) * 1800, -1), 1
FROM seed.worker w CROSS JOIN generate_series(1, 3) k
JOIN seed.gig_skill s ON s.rank = 1 + floor(seed.r(w.g * 3 + k, 9) * (SELECT count(*) FROM seed.gig_skill))
WHERE k <= 1 + floor(seed.r(w.g, 10) * 3)
ORDER BY w.profile_id, s.id;
INSERT INTO gig_worker_availability (gig_worker_profile_id, available_from, available_to)
SELECT w.profile_id, now() + interval '1 day' * (k * 20 + floor(seed.r(w.g * 2 + k, 11) * 10)),
       now() + interval '1 day' * (k * 20 + 10 + floor(seed.r(w.g * 2 + k, 11) * 10))
FROM seed.worker w CROSS JOIN generate_series(0, 1) k WHERE k = 0 OR seed.r(w.g, 12) < 0.5;
-- gig projects on worker profiles, and projects on 5% of candidate profiles (Tier 1 "profile projects")
INSERT INTO profile_project (project_kind_id, gig_worker_profile_id, title, role_name, start_date, end_date, outcome)
SELECT seed.id('project_kind', 'gig_project'), w.profile_id, 'Wiring for a 40-flat housing society', 'Lead electrician',
       (now() - interval '200 days')::date, (now() - interval '170 days')::date, 'Completed on time; society certificate issued'
FROM seed.worker w WHERE seed.r(w.g, 13) < 0.10;
INSERT INTO profile_project (project_kind_id, candidate_profile_id, title, role_name, start_date, end_date, outcome, project_url)
SELECT seed.id('project_kind', 'candidate_project'), c.profile_id, 'Inventory dashboard for a retail chain', 'Developer',
       (now() - interval '400 days')::date, (now() - interval '300 days')::date, 'Cut stock-out reports from a day to an hour',
       'https://github.com/example/inventory-dashboard'
FROM seed.cand_p c WHERE seed.r(c.g, 70) < 0.05;

-- requests
CREATE TABLE seed.gig_req AS
SELECT v AS g,
       CASE WHEN seed.r(v, 20) < 0.70 THEN p.user_id ELSE c.user_id END AS requester_id,
       CASE WHEN seed.r(v, 20) < 0.70 THEN p.org_id END AS org_id,
       now() - interval '300 days' + interval '330 days' * seed.r(v, 21) AS window_start,
       interval '4 hours' + interval '116 hours' * seed.r(v, 22) AS window_len,
       s.id AS skill_id, s.name AS skill_name, cr.city_id,
       CASE WHEN seed.r(v, 23) < 0.45 THEN 3 WHEN seed.r(v, 23) < 0.70 THEN 2 WHEN seed.r(v, 23) < 0.85 THEN 4
            WHEN seed.r(v, 23) < 0.95 THEN 5 ELSE 1 END AS final_status
FROM generate_series(1, seed.n(20000)) v
JOIN seed.org_person p ON p.org_id = (SELECT org_id FROM seed.org WHERE seed.org.g = 1 + (v * 13) % (SELECT count(*) FROM seed.org)) AND p.k = 1
JOIN seed.cand_p c ON c.g = 1 + (v * 29) % (SELECT count(*) FROM seed.cand_p)
JOIN seed.gig_skill s ON s.rank = 1 + floor(seed.r(v, 24) * (SELECT count(*) FROM seed.gig_skill))
JOIN seed.city_rank cr ON cr.rank = seed.skew(40, v, 25, 1.6);
INSERT INTO gig_request (requester_user_account_id, requester_organisation_id, title, description, work_mode_id, city_id,
                         window_start_at, window_end_at, gig_price_type_id, price_amount, price_currency_id, gig_request_status_id,
                         created_at, updated_at)
SELECT requester_id, org_id, skill_name || ' needed', 'Need an experienced person for ' || lower(skill_name) || '. Tools provided on site.',
       1, city_id, window_start, window_start + window_len, 1, round(500 + seed.r(g, 26) * 9500, -1), 1,
       CASE WHEN final_status = 1 THEN 1 ELSE 2 END, window_start - interval '7 days', window_start - interval '7 days'
FROM seed.gig_req ORDER BY g;
ALTER TABLE seed.gig_req ADD COLUMN request_id bigint;
UPDATE seed.gig_req s SET request_id = r.id
FROM (SELECT id, row_number() OVER (ORDER BY id) AS rn FROM gig_request) r WHERE r.rn = s.g;

-- applications from popular workers (skewed), never to one's own request
INSERT INTO gig_application (gig_request_id, gig_worker_profile_id, cover_note, applied_at)
SELECT DISTINCT ON (r.request_id, w.profile_id) r.request_id, w.profile_id, 'Available for the full window.',
       least(now() - interval '1 day', r.window_start - interval '5 days') + interval '1 hour' * k
FROM seed.gig_req r CROSS JOIN generate_series(1, 5) k
JOIN seed.worker w ON w.g = seed.skew((SELECT count(*) FROM seed.worker), r.g * 5 + k, 27, 2.5)
WHERE r.final_status <> 1 AND k <= 1 + floor(seed.r(r.g, 28) * 5) AND w.user_id <> r.requester_id
ORDER BY r.request_id, w.profile_id;

-- accept the first application of each filled request; reject the others; workers withdraw some on open requests
UPDATE gig_application a SET gig_application_status_id = 2
FROM (SELECT DISTINCT ON (a2.gig_request_id) a2.id FROM gig_application a2 JOIN seed.gig_req r ON r.request_id = a2.gig_request_id
      WHERE r.final_status = 3 ORDER BY a2.gig_request_id, a2.id) f WHERE a.id = f.id;
UPDATE gig_application a SET gig_application_status_id = 3
FROM seed.gig_req r WHERE r.request_id = a.gig_request_id AND r.final_status IN (3, 4) AND a.gig_application_status_id = 1;
UPDATE gig_application a SET gig_application_status_id = 4
FROM seed.gig_req r WHERE r.request_id = a.gig_request_id AND r.final_status = 2 AND a.gig_application_status_id = 1 AND seed.r(a.id, 29) < 0.15;
UPDATE gig_application SET decided_at = least(now(), applied_at + interval '1 day') WHERE decided_at IS NOT NULL;   -- the trigger stamped "now"

-- assignments one by one: overlapping windows for the same worker are rejected by the exclusion constraint
CREATE TABLE seed.gig_overlap (gig_application_id bigint, gig_worker_profile_id bigint, message text);
DO $$
DECLARE r record; n_ok int := 0; n_overlap int := 0;
BEGIN
    FOR r IN SELECT a.id, a.gig_worker_profile_id, q.window_end_at
             FROM gig_application a JOIN gig_request q ON q.id = a.gig_request_id
             WHERE a.gig_application_status_id = 2 ORDER BY q.window_start_at LOOP
        BEGIN
            INSERT INTO gig_assignment (gig_application_id, gig_worker_profile_id, window_start_at, window_end_at, handoff_ref, gig_assignment_status_id)
            VALUES (r.id, r.gig_worker_profile_id, now(), now() + interval '1 hour', 'HND-' || lpad(r.id::text, 9, '0'), 1);
            n_ok := n_ok + 1;
        EXCEPTION WHEN exclusion_violation THEN
            INSERT INTO seed.gig_overlap VALUES (r.id, r.gig_worker_profile_id, SQLERRM);
            n_overlap := n_overlap + 1;
        END;
    END LOOP;
    RAISE NOTICE 'seeded % : % assigned, % overlap attempts rejected', rpad('gig: assignments', 44), n_ok, n_overlap;
END $$;
INSERT INTO system_error_event (error_severity_id, source_component, error_code, message, correlation_ref, occurred_at)
SELECT 1, 'gig-handoff-service', 'gig_assignment_overlap', left('assignment for application ' || gig_application_id || ' rejected: ' || message, 1000),
       'app-' || gig_application_id, now() - interval '1 hour' * (gig_application_id % 2000)
FROM seed.gig_overlap;

-- outcomes of gigs whose window has passed
UPDATE gig_assignment s SET gig_assignment_status_id = 3, completed_at = s.window_end_at, last_reconciled_at = s.window_end_at + interval '1 day'
WHERE s.window_end_at < now() AND seed.r(s.id, 30) < 0.85;
UPDATE gig_assignment s SET gig_assignment_status_id = 5 WHERE s.window_end_at < now() AND s.gig_assignment_status_id = 1 AND seed.r(s.id, 31) < 0.33;
UPDATE gig_assignment s SET gig_assignment_status_id = 4 WHERE s.window_end_at < now() AND s.gig_assignment_status_id = 1;
UPDATE gig_assignment s SET gig_assignment_status_id = 2 WHERE s.window_start_at < now() AND s.window_end_at >= now();

INSERT INTO gig_earning_snapshot (gig_assignment_id, gig_earning_type_id, earning_amount, earning_currency_id, external_event_ref, reported_at)
SELECT s.id, t, round(q.price_amount * CASE WHEN t = 1 THEN 1 ELSE 0.92 + seed.r(s.id, 32) * 0.08 END, 2), 1,
       'GFS-' || s.id || '-' || t, s.window_end_at + interval '1 day' * t
FROM gig_assignment s JOIN gig_application a ON a.id = s.gig_application_id JOIN gig_request q ON q.id = a.gig_request_id
CROSS JOIN generate_series(1, 2) t WHERE s.gig_assignment_status_id = 3;
INSERT INTO gig_rating (gig_assignment_id, rated_by_user_account_id, rating_score, review_text)
SELECT s.id, q.requester_user_account_id, CASE WHEN seed.r(s.id, 33) < 0.7 THEN 5 WHEN seed.r(s.id, 33) < 0.9 THEN 4 ELSE 1 + floor(seed.r(s.id, 34) * 3)::int END,
       CASE WHEN seed.r(s.id, 35) < 0.3 THEN 'Punctual and did a neat job.' END
FROM gig_assignment s JOIN gig_application a ON a.id = s.gig_application_id JOIN gig_request q ON q.id = a.gig_request_id
WHERE s.gig_assignment_status_id = 3 AND seed.r(s.id, 36) < 0.80;

-- final request statuses
UPDATE gig_request q SET gig_request_status_id = r.final_status FROM seed.gig_req r WHERE r.request_id = q.id AND r.final_status IN (3, 4, 5);

-- favourites and blacklists, kept after the gigs ran
INSERT INTO gig_worker_list_entry (owner_user_account_id, owner_organisation_id, gig_worker_profile_id, gig_worker_list_type_id, reason, added_at)
SELECT DISTINCT ON (q.requester_user_account_id, s.gig_worker_profile_id) q.requester_user_account_id, q.requester_organisation_id,
       s.gig_worker_profile_id, CASE WHEN g.rating_score >= 4 THEN 1 ELSE 2 END,
       CASE WHEN g.rating_score < 4 THEN 'Low rating on a completed gig' END, s.completed_at + interval '2 days'
FROM gig_rating g JOIN gig_assignment s ON s.id = g.gig_assignment_id JOIN gig_application a ON a.id = s.gig_application_id
JOIN gig_request q ON q.id = a.gig_request_id
WHERE g.rating_score <= 2 OR seed.r(g.id, 37) < 0.25
ORDER BY q.requester_user_account_id, s.gig_worker_profile_id, g.id;

DO $$
BEGIN
    PERFORM seed.done('gig: worker profiles', (SELECT count(*) FROM gig_worker_profile));
    PERFORM seed.done('gig: services + availability', (SELECT count(*) FROM gig_worker_service) + (SELECT count(*) FROM gig_worker_availability));
    PERFORM seed.done('gig: requests', (SELECT count(*) FROM gig_request));
    PERFORM seed.done('gig: applications', (SELECT count(*) FROM gig_application));
    PERFORM seed.done('gig: overlap attempts rejected + logged', (SELECT count(*) FROM system_error_event WHERE error_code = 'gig_assignment_overlap'));
    PERFORM seed.done('gig: earnings snapshots + ratings', (SELECT count(*) FROM gig_earning_snapshot) + (SELECT count(*) FROM gig_rating));
    PERFORM seed.done('gig: favourite / blacklist entries', (SELECT count(*) FROM gig_worker_list_entry));
    PERFORM seed.done('profile: projects (candidate + gig)', (SELECT count(*) FROM profile_project));
END $$;
