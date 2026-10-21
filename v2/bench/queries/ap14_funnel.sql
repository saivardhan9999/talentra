-- AP-14 Employer hiring funnel from the aggregate
-- as: admin
SELECT month_start, applied_count, shortlisted_count, interviewed_count, offered_count, joined_count, median_days_to_join
FROM employer_hiring_funnel ORDER BY month_start;
