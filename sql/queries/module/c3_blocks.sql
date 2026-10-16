-- C3 Shared items (B69): blocking lists. Live blocks by target kind and reason; each one hides the candidate
-- from the blocked recruiter or from every member of the blocked company (row-level security, M18).
SELECT CASE WHEN b.blocked_user_account_id IS NOT NULL THEN 'recruiter' ELSE 'company' END AS blocked,
       coalesce(r.code, 'no reason given') AS reason, count(*) FILTER (WHERE b.unblocked_at IS NULL) AS live_blocks,
       count(*) FILTER (WHERE b.unblocked_at IS NOT NULL) AS unblocked
FROM block_entry b LEFT JOIN block_reason r ON r.id = b.block_reason_id
GROUP BY 1, 2
ORDER BY 1, live_blocks DESC;
