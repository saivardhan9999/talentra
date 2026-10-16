-- Q10 Hiring funnel (reporting, performance): monthly conversion for the busiest employer over the last
-- 6 months, read from the pre-computed aggregate.
SELECT month_start, applied_count, shortlisted_count, interviewed_count, offered_count, joined_count,
       round(100.0 * shortlisted_count / nullif(applied_count, 0), 1) AS shortlist_pct,
       round(100.0 * joined_count / nullif(applied_count, 0), 2) AS hire_pct, avg_days_to_hire
FROM agg_hiring_funnel_monthly
WHERE organisation_id = :org_busy AND month_start >= date_trunc('month', now()) - interval '6 months'
ORDER BY month_start;
