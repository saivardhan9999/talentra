-- V012 Analytics: the hiring-funnel aggregate behind the employer dashboard (FR-ANA-01, NFR-PERF-01 AP-14).
-- Analytical objects carry the agg_ prefix (rule group 8). The full star schema is deferred (docs/08-gaps-and-next-steps.md).

CREATE MATERIALIZED VIEW agg_hiring_funnel_monthly AS
WITH reached AS (
    SELECT application_id,
           bool_or(to_status_id = 2) AS shortlisted, bool_or(to_status_id = 3) AS interviewed,
           bool_or(to_status_id = 4) AS offered,     bool_or(to_status_id = 5) AS joined,
           bool_or(to_status_id = 6) AS rejected,
           min(changed_at) FILTER (WHERE to_status_id = 5) AS joined_at
    FROM application_status_history GROUP BY application_id)
SELECT a.organisation_id,
       date_trunc('month', a.applied_at)::date                          AS month_start,
       count(*)                                                         AS applied_count,
       count(*) FILTER (WHERE r.shortlisted)                            AS shortlisted_count,
       count(*) FILTER (WHERE r.interviewed)                            AS interviewed_count,
       count(*) FILTER (WHERE r.offered)                                AS offered_count,
       count(*) FILTER (WHERE r.joined)                                 AS joined_count,
       count(*) FILTER (WHERE r.rejected)                               AS rejected_count,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM r.joined_at - a.applied_at) / 86400)
             FILTER (WHERE r.joined)::numeric, 1)                       AS median_days_to_join
FROM application a JOIN reached r ON r.application_id = a.id
GROUP BY a.organisation_id, date_trunc('month', a.applied_at)
WITH NO DATA;
CREATE UNIQUE INDEX uq_agg_hiring_funnel_monthly_organisation_id_month_start ON agg_hiring_funnel_monthly (organisation_id, month_start);

-- Refreshed by the scheduler (hourly is plenty for a monthly funnel); CONCURRENTLY keeps it readable during refresh.
CREATE FUNCTION refresh_aggregates() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_matviews WHERE matviewname = 'agg_hiring_funnel_monthly' AND ispopulated) THEN
    REFRESH MATERIALIZED VIEW CONCURRENTLY agg_hiring_funnel_monthly;
  ELSE
    REFRESH MATERIALIZED VIEW agg_hiring_funnel_monthly;
  END IF;
END $$;
REVOKE ALL ON FUNCTION refresh_aggregates() FROM PUBLIC;

-- Materialized views cannot have row-level security, so employers read through this view, which keeps only their
-- organisation's rows (it runs with the owner's rights on the aggregate, filtered by the caller's organisation).
CREATE VIEW employer_hiring_funnel WITH (security_barrier = true) AS
SELECT * FROM agg_hiring_funnel_monthly WHERE organisation_id = app_viewer_organisation_id();

GRANT SELECT ON employer_hiring_funnel TO v2_app;
GRANT SELECT ON agg_hiring_funnel_monthly TO v2_reporting;
