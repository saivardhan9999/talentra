-- Q1 Job search (functional, performance): published, open requirements matching "java developer" in Bengaluru,
-- paying from 6 lakh a year (or salary not disclosed), newest first.
SELECT r.id, r.title, o.legal_name AS company, r.salary_min_amount, r.salary_max_amount, r.published_at::date AS published
FROM job_requirement r
JOIN organisation o ON o.id = r.organisation_id
WHERE r.search_document @@ websearch_to_tsquery('simple', 'java developer')
  AND r.publish_state_id = 3 AND r.job_requirement_status_id = 3 AND r.deleted_at IS NULL
  AND EXISTS (SELECT 1 FROM job_requirement_location l WHERE l.job_requirement_id = r.id AND l.city_id = :city_blr)
  AND (r.salary_min_amount >= 600000 OR r.salary_disclosure_status_id <> 1)
ORDER BY r.published_at DESC
LIMIT 20;
