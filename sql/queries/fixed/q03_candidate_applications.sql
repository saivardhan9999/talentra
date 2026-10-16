-- Q3 Application tracker for one candidate (functional, multilingual): every application with its status label
-- in Tamil, falling back to the default language where no Tamil translation exists.
SELECT a.id, r.title, o.legal_name AS company, coalesce(t.label_text, d.label_text) AS status_label, a.status_changed_at::date AS since
FROM application a
JOIN job_requirement r ON r.id = a.job_requirement_id
JOIN organisation o ON o.id = r.organisation_id
JOIN application_status s ON s.id = a.application_status_id
LEFT JOIN ui_label_translation t ON t.ui_label_key_id = s.ui_label_key_id AND t.language_id = :lang_ta
JOIN ui_label_translation d ON d.ui_label_key_id = s.ui_label_key_id AND d.language_id = (SELECT id FROM language WHERE is_default)
WHERE a.candidate_profile_id = :cand
ORDER BY a.applied_at DESC;
