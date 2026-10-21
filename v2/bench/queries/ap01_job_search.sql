-- AP-01 Job search: words + city + minimum salary, newest first
-- as: candidate
SELECT j.id, j.title, o.display_name AS company, j.salary_min_amount, j.published_at::date
FROM job_requirement j JOIN organisation o ON o.id = j.organisation_id
WHERE j.search_vector @@ websearch_to_tsquery('simple', 'java developer') AND j.job_status_id = 2 AND j.deleted_at IS NULL
  AND EXISTS (SELECT 1 FROM job_requirement_location l WHERE l.job_requirement_id = j.id AND l.city_id = :city_jobs)
  AND (j.salary_min_amount >= 300000 OR j.salary_disclosure_id = 2)
ORDER BY j.published_at DESC LIMIT 20;
