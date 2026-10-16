-- Parameters for the fixed and module queries, resolved from the seeded data (included before each query).
\set QUIET on
SELECT (SELECT id FROM city WHERE name = 'Bengaluru') AS city_blr,
       (SELECT id FROM city WHERE name = 'Chennai') AS city_chennai,
       (SELECT id FROM skill WHERE code = 'java') AS skill_java,
       (SELECT id FROM language WHERE code = 'ta') AS lang_ta \gset
SELECT f.job_requirement_id AS job_busy, r.organisation_id AS org_busy
FROM fact_job_posting f JOIN job_requirement r ON r.id = f.job_requirement_id
ORDER BY f.application_count DESC, f.job_requirement_id LIMIT 1 \gset
SELECT a.candidate_profile_id AS cand FROM application a WHERE a.id = (SELECT min(id) FROM application) \gset
SELECT min(a.id) AS app_applied FROM application a WHERE a.job_requirement_id = :job_busy AND a.application_status_id = 1 \gset
SELECT m.user_account_id AS recruiter FROM organisation_member m WHERE m.organisation_id = :org_busy AND m.role_id = 6 ORDER BY m.id LIMIT 1 \gset
-- a seat holder whose live sessions already fill the licence's device limit
SELECT s.user_account_id AS user_at_limit,
       (SELECT d.id FROM user_device d WHERE d.user_account_id = s.user_account_id AND d.revoked_at IS NULL ORDER BY d.id DESC LIMIT 1) AS device_at_limit
FROM licence_seat s JOIN licence l ON l.id = s.licence_id
WHERE s.released_at IS NULL
  AND (SELECT count(*) FROM user_session u WHERE u.licence_seat_id = s.id AND u.ended_at IS NULL AND u.expires_at > now()) >= l.max_devices_per_user
ORDER BY s.id LIMIT 1 \gset
SELECT w.id AS wallet, w.organisation_id AS wallet_org,
       (SELECT m.user_account_id FROM organisation_member m
        WHERE m.organisation_id = w.organisation_id AND m.role_id = 7 AND m.valid_to IS NULL ORDER BY m.id LIMIT 1) AS wallet_recruiter
FROM wallet w WHERE w.credit_balance > 0 ORDER BY w.id LIMIT 1 \gset
SELECT candidate_profile_id AS cand_downloaded FROM profile_download_event WHERE wallet_ledger_entry_id IS NOT NULL
ORDER BY downloaded_at DESC LIMIT 1 \gset
\set QUIET off
