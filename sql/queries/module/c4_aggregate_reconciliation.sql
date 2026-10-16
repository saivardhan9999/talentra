-- C4 Analytics (B69): the aggregates agree with the facts they summarise, and the facts with the source rows
-- (expected: every difference is 0).
SELECT 'applications: source vs fact' AS check_name, (SELECT count(*) FROM application) - (SELECT count(*) FROM fact_application) AS difference
UNION ALL
SELECT 'fact_application vs agg_hiring_funnel_monthly', (SELECT count(*) FROM fact_application) - (SELECT sum(applied_count) FROM agg_hiring_funnel_monthly)
UNION ALL
SELECT 'job requirements: source vs fact', (SELECT count(*) FROM job_requirement) - (SELECT count(*) FROM fact_job_posting)
UNION ALL
SELECT 'paid orders: fact vs agg_revenue_monthly', (SELECT sum(paid_amount) FROM fact_payment) - (SELECT sum(paid_amount) FROM agg_revenue_monthly)
UNION ALL
SELECT 'ledger entries: source vs fact', (SELECT count(*) FROM wallet_ledger_entry) - (SELECT count(*) FROM fact_wallet_transaction);
