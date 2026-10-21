-- AP-03 Recruiter pipeline: applicants of one job by stage
-- as: recruiter
SELECT s.code AS stage, count(*) AS applicants, max(a.status_changed_at) AS last_move
FROM application a JOIN application_status s ON s.id = a.application_status_id
WHERE a.job_requirement_id = :busy_job GROUP BY s.code, s.sort_order ORDER BY s.sort_order;
