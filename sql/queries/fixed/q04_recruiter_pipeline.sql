-- Q4 Recruiter pipeline for one requirement (functional, performance): applications per stage of the
-- busiest requirement, in pipeline order, with the latest movement.
SELECT s.code AS stage, count(*) AS applications, max(a.status_changed_at)::date AS last_movement
FROM application a
JOIN application_status s ON s.id = a.application_status_id
WHERE a.job_requirement_id = :job_busy
GROUP BY s.code, s.sort_order, s.id
ORDER BY s.sort_order, s.id;
