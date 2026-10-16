-- B2 Licences (B68): login outcomes over the last 30 days, including refusals at the device limit
-- (rule group 9: every attempt to exceed the limit is recorded).
SELECT o.code AS outcome, count(*) AS attempts, count(DISTINCT la.user_account_id) AS users
FROM login_attempt la
JOIN login_outcome o ON o.id = la.login_outcome_id
WHERE la.attempted_at >= now() - interval '30 days'
GROUP BY o.code, o.id
ORDER BY o.id;
