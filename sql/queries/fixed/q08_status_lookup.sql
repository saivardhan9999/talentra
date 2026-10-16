-- Q8 Lookup with translation fallback (lookup): application statuses as a Tamil-speaking user sees them,
-- falling back to the default language for keys without a Tamil translation.
SELECT s.code, coalesce(t.label_text, d.label_text) AS label, t.label_text IS NULL AS fell_back, s.is_terminal
FROM application_status s
LEFT JOIN ui_label_translation t ON t.ui_label_key_id = s.ui_label_key_id AND t.language_id = :lang_ta
JOIN ui_label_translation d ON d.ui_label_key_id = s.ui_label_key_id AND d.language_id = (SELECT id FROM language WHERE is_default)
WHERE s.is_active
ORDER BY s.sort_order, s.id;
