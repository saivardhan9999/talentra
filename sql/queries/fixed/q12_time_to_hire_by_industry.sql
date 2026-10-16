-- Q12 Time to hire by industry (reporting, performance): hires in the last 12 months from the star schema, with
-- the median and average number of days from application to joining.
SELECT coalesce(dj.industry_code, 'not stated') AS industry, count(*) AS hires,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY f.days_to_hire) AS median_days, round(avg(f.days_to_hire), 1) AS avg_days
FROM fact_application f
JOIN dim_job_requirement dj ON dj.id = f.dim_job_requirement_id
JOIN dim_date d ON d.id = f.joined_date_id
WHERE d.calendar_date >= current_date - 365
GROUP BY 1
ORDER BY hires DESC;
