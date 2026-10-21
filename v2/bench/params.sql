-- Benchmark parameters, resolved from the data so the queries work at any seed scale (psql \gset variables).
SELECT p.app_user_id AS cand_user, p.id AS cand_profile FROM candidate_profile p
WHERE p.deleted_at IS NULL AND (SELECT count(*) FROM application a WHERE a.candidate_profile_id = p.id) >= 5 ORDER BY p.id LIMIT 1 \gset
SELECT a.job_requirement_id AS busy_job, a.organisation_id AS busy_org FROM application a GROUP BY 1, 2 ORDER BY count(*) DESC LIMIT 1 \gset
SELECT app_user_id AS rec_user FROM organisation_member WHERE organisation_id = :busy_org AND valid_to IS NULL AND access_role_id IN (4, 5) ORDER BY id LIMIT 1 \gset
SELECT app_user_id AS admin_user FROM organisation_member WHERE organisation_id = :busy_org AND valid_to IS NULL AND access_role_id = 3 \gset
SELECT id AS skill_java FROM skill WHERE name = 'Java' \gset
SELECT p.current_city_id AS city_java FROM candidate_skill s JOIN candidate_profile p ON p.id = s.candidate_profile_id
WHERE s.skill_id = :skill_java AND p.current_city_id IS NOT NULL GROUP BY 1 ORDER BY count(*) DESC LIMIT 1 \gset
SELECT l.city_id AS city_jobs FROM job_requirement_location l JOIN job_requirement j ON j.id = l.job_requirement_id
WHERE j.job_status_id = 2 GROUP BY 1 ORDER BY count(*) DESC LIMIT 1 \gset
SELECT split_part(full_name, ' ', 1) AS common_name FROM candidate_profile WHERE full_name ~ '^[A-Za-z]+ ' GROUP BY 1 ORDER BY count(*) DESC LIMIT 1 \gset
SELECT phone_e164 AS dup_phone FROM app_user WHERE phone_e164 IS NOT NULL GROUP BY 1 ORDER BY count(*) DESC, 1 LIMIT 1 \gset
SELECT d.candidate_profile_id AS downloaded_cand, d.organisation_id AS dl_org,
       (SELECT app_user_id FROM organisation_member m WHERE m.organisation_id = d.organisation_id AND m.valid_to IS NULL AND m.access_role_id IN (3, 4, 5) ORDER BY m.id LIMIT 1) AS dl_user
FROM profile_download d JOIN candidate_profile p ON p.id = d.candidate_profile_id
WHERE d.downloaded_at > now() - interval '25 days' AND p.profile_visibility_id <> 3 AND p.deleted_at IS NULL
  AND NOT EXISTS (SELECT 1 FROM candidate_block b WHERE b.candidate_profile_id = p.id AND b.unblocked_at IS NULL)
ORDER BY d.id DESC LIMIT 1 \gset
