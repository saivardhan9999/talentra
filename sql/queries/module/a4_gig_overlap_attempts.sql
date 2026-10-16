-- A4 Gig marketplace (B67): overlapping assignment attempts rejected by uq_gig_assignment_no_overlap and logged,
-- per gig-handoff day.
SELECT occurred_at::date AS day, count(*) AS rejected_attempts, min(left(message, 90)) AS sample_message
FROM system_error_event
WHERE error_code = 'gig_assignment_overlap'
GROUP BY 1
ORDER BY 1 DESC
LIMIT 10;
