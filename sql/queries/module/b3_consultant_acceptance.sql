-- B3 Sourcing (B68): consultants ranked by sourcing requests, with the employer acceptance rate and the
-- median time to a decision.
SELECT u.email AS consultant, count(*) AS requests,
       count(*) FILTER (WHERE r.sourcing_request_status_id = 2) AS accepted,
       round(100.0 * count(*) FILTER (WHERE r.sourcing_request_status_id = 2)
             / nullif(count(*) FILTER (WHERE r.sourcing_request_status_id IN (2, 3)), 0), 1) AS acceptance_pct,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM r.decided_at - r.requested_at) / 3600) AS median_hours_to_decision
FROM sourcing_request r
JOIN user_account u ON u.id = r.consultant_user_account_id
GROUP BY u.email
ORDER BY requests DESC, consultant
LIMIT 10;
