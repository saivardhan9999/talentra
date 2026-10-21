-- I1 Organisation audit trail (Administration, B71): an account admin reviews the last 30 days of sensitive changes in their organisation
SELECT a.occurred_at, x.code AS action, a.target_table, a.target_record_id, a.created_by AS actor
FROM audit_event a
JOIN audit_action x ON x.id = a.audit_action_id
WHERE a.organisation_id = :org_busy AND a.occurred_at >= now() - interval '30 days'
ORDER BY a.occurred_at DESC
LIMIT 50;
