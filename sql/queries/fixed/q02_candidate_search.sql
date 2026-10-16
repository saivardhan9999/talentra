-- Q2 Candidate search by a recruiter (functional, performance): Java, living in the city with the most such candidates, 3 to 8 years of
-- experience, actively looking, not hidden, not deleted; most recently active first.
SELECT p.id, p.full_name, p.total_experience_months / 12 AS years, c.name AS city, p.last_active_at::date AS last_active
FROM candidate_skill s
JOIN candidate_profile p ON p.id = s.candidate_profile_id
JOIN city c ON c.id = p.current_city_id
WHERE s.skill_id = :skill_java AND p.current_city_id = :city_cands AND p.total_experience_months BETWEEN 36 AND 96
  AND p.is_actively_looking AND p.profile_visibility_id <> 3 AND p.deleted_at IS NULL
ORDER BY p.last_active_at DESC
LIMIT 50;
