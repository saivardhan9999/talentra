-- A1 Administration / Organisation (B67): recruiters who moved company, with their effective-dated mappings
-- (the old mapping ends the day the new one starts).
SELECT m.user_account_id, o.legal_name AS organisation, r.code AS role, m.valid_from::date AS mapped_from, m.valid_to::date AS mapped_to
FROM organisation_member m
JOIN organisation o ON o.id = m.organisation_id
JOIN role r ON r.id = m.role_id
WHERE m.user_account_id IN (SELECT user_account_id FROM organisation_member WHERE valid_to IS NOT NULL ORDER BY user_account_id LIMIT 5)
ORDER BY m.user_account_id, m.valid_from;
