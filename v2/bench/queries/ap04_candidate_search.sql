-- AP-04 Recruiter candidate search: skill + city + 3-8 years, most recently active
-- as: recruiter
SELECT p.id, p.full_name, p.total_experience_months / 12 AS years, p.last_active_at::date
FROM candidate_profile p
WHERE p.current_city_id = :city_java AND p.is_open_to_work AND p.deleted_at IS NULL AND p.profile_visibility_id <> 3
  AND p.total_experience_months BETWEEN 36 AND 96
  AND EXISTS (SELECT 1 FROM candidate_skill s WHERE s.candidate_profile_id = p.id AND s.skill_id = :skill_java)
ORDER BY p.last_active_at DESC LIMIT 50;
