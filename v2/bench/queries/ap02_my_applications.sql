-- AP-02 My applications with status in my language (fallback English)
-- as: candidate
SELECT a.id, j.title, o.display_name AS company, ui_text(s.ui_label_id, u.preferred_language_id) AS status, a.status_changed_at
FROM application a JOIN job_requirement j ON j.id = a.job_requirement_id JOIN organisation o ON o.id = j.organisation_id
JOIN application_status s ON s.id = a.application_status_id JOIN app_user u ON u.id = :cand_user
WHERE a.candidate_profile_id = :cand_profile ORDER BY a.applied_at DESC LIMIT 20;
