-- AP-06 Employer dashboard: own jobs with applicant counts
-- as: admin
SELECT j.id, j.title, js.code AS status, j.positions_filled || '/' || j.positions_total AS filled,
       count(a.id) AS applicants, count(a.id) FILTER (WHERE a.application_status_id = 1) AS unreviewed
FROM job_requirement j JOIN job_status js ON js.id = j.job_status_id LEFT JOIN application a ON a.job_requirement_id = j.id
WHERE j.organisation_id = :busy_org GROUP BY j.id, js.code ORDER BY j.published_at DESC NULLS FIRST LIMIT 50;
