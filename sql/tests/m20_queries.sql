-- Milestone 20 (B65-B69): the fixed query set and the module queries run against the seeded data and return
-- results; the seed validation finds no rule violations and detects the data-quality findings.
-- Outputs and execution plans are written to docs/phase5-query-report.md by run_report.sh.
\set ON_ERROR_STOP on
CREATE FUNCTION pg_temp.t_rows(p_label text, p_rows bigint) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_rows < 1 THEN RAISE EXCEPTION 'FAIL % returned no rows', p_label; END IF;
    RAISE NOTICE 'PASS % (% rows)', p_label, p_rows;
END $$;
\ir ../queries/params.sql
\o /dev/null
\ir ../queries/fixed/q01_job_search.sql
\o
SELECT pg_temp.t_rows('Q1 job search', :ROW_COUNT) \g /dev/null
\o /dev/null
\ir ../queries/fixed/q02_candidate_search.sql
\o
SELECT pg_temp.t_rows('Q2 candidate search', :ROW_COUNT) \g /dev/null
\o /dev/null
\ir ../queries/fixed/q03_candidate_applications.sql
\o
SELECT pg_temp.t_rows('Q3 application tracker (Tamil labels with fallback)', :ROW_COUNT) \g /dev/null
\o /dev/null
\ir ../queries/fixed/q04_recruiter_pipeline.sql
\o
SELECT pg_temp.t_rows('Q4 recruiter pipeline', :ROW_COUNT) \g /dev/null
\o /dev/null
\ir ../queries/fixed/q05_pipeline_move.sql
\ir ../queries/fixed/q06_login_at_device_limit.sql
\ir ../queries/fixed/q07_download_with_credit.sql
\o
\echo PASS Q5-Q7 transactional queries ran and rolled back (pipeline move, login at the device limit, paid download)
\o /dev/null
\ir ../queries/fixed/q08_status_lookup.sql
\o
SELECT pg_temp.t_rows('Q8 status lookup with fallback', :ROW_COUNT) \g /dev/null
\o /dev/null
\ir ../queries/fixed/q09_skill_alias_lookup.sql
\o
SELECT pg_temp.t_rows('Q9 skill alias lookup', :ROW_COUNT) \g /dev/null
\o /dev/null
\ir ../queries/fixed/q10_hiring_funnel.sql
\o
SELECT pg_temp.t_rows('Q10 hiring funnel', :ROW_COUNT) \g /dev/null
\o /dev/null
\ir ../queries/fixed/q11_duplicate_candidates.sql
\o
SELECT pg_temp.t_rows('Q11 duplicate detection', :ROW_COUNT) \g /dev/null
\o /dev/null
\ir ../queries/fixed/q12_time_to_hire_by_industry.sql
\o
SELECT pg_temp.t_rows('Q12 time to hire by industry', :ROW_COUNT) \g /dev/null
\o /dev/null
\ir ../queries/fixed/q13_download_history.sql
\o
SELECT pg_temp.t_rows('Q13 download history with credit deduction', :ROW_COUNT) \g /dev/null

-- module queries (B67-B69)
\o /dev/null
\ir ../queries/module/a1_recruiter_mapping_history.sql
\o
SELECT pg_temp.t_rows('A1 recruiter mapping history', :ROW_COUNT) \g /dev/null
\o /dev/null
\ir ../queries/module/a2_organisation_hierarchy.sql
\o
SELECT pg_temp.t_rows('A2 organisation hierarchy', :ROW_COUNT) \g /dev/null
\o /dev/null
\ir ../queries/module/a3_gig_worker_leaderboard.sql
\o
SELECT pg_temp.t_rows('A3 gig worker leaderboard', :ROW_COUNT) \g /dev/null
\o /dev/null
\ir ../queries/module/a4_gig_overlap_attempts.sql
\o
SELECT pg_temp.t_rows('A4 gig overlap attempts', :ROW_COUNT) \g /dev/null
\o /dev/null
\ir ../queries/module/b1_seat_utilisation.sql
\o
SELECT pg_temp.t_rows('B1 seat utilisation', :ROW_COUNT) \g /dev/null
\o /dev/null
\ir ../queries/module/b2_device_limit_refusals.sql
\o
SELECT pg_temp.t_rows('B2 login outcomes incl. device-limit refusals', :ROW_COUNT) \g /dev/null
\o /dev/null
\ir ../queries/module/b3_consultant_acceptance.sql
\o
SELECT pg_temp.t_rows('B3 consultant acceptance', :ROW_COUNT) \g /dev/null
\o /dev/null
\ir ../queries/module/b4_monthly_revenue.sql
\o
SELECT pg_temp.t_rows('B4 monthly revenue', :ROW_COUNT) \g /dev/null
\o /dev/null
\ir ../queries/module/c1_delivery_rate_by_channel.sql
\o
SELECT pg_temp.t_rows('C1 delivery rate by channel', :ROW_COUNT) \g /dev/null
\o /dev/null
\ir ../queries/module/c2_consent_current_state.sql
\o
SELECT pg_temp.t_rows('C2 consent current state', :ROW_COUNT) \g /dev/null
\o /dev/null
\ir ../queries/module/c3_blocks.sql
\o
SELECT pg_temp.t_rows('C3 blocking lists', :ROW_COUNT) \g /dev/null

-- reconciliations that must come out exactly
-- (a query file is loaded into a variable without its final semicolon, so it can become CREATE TABLE AS)
\set q `sed 's/;[[:space:]]*$//' /sql/queries/module/b5_wallet_reconciliation.sql`
CREATE TEMP TABLE t_wallet AS :q;
\set q `sed 's/;[[:space:]]*$//' /sql/queries/module/c4_aggregate_reconciliation.sql`
CREATE TEMP TABLE t_agg AS :q;
DO $$
BEGIN
    IF (SELECT wallets_out_of_balance FROM t_wallet) <> 0 THEN RAISE EXCEPTION 'FAIL wallets out of balance'; END IF;
    RAISE NOTICE 'PASS B5 every wallet balance equals its ledger (% wallets)', (SELECT wallets FROM t_wallet);
    IF EXISTS (SELECT 1 FROM t_agg WHERE difference <> 0) THEN
        RAISE EXCEPTION 'FAIL C4 reconciliation: %', (SELECT string_agg(check_name || ' = ' || difference, '; ') FROM t_agg WHERE difference <> 0);
    END IF;
    RAISE NOTICE 'PASS C4 aggregates, facts and source rows reconcile (% checks)', (SELECT count(*) FROM t_agg);
END $$;

-- seed validation (B66)
\set q `sed 's/;[[:space:]]*$//' /sql/queries/validation.sql`
CREATE TEMP TABLE t_validation AS :q;
DO $$
DECLARE r record;
BEGIN
    FOR r IN SELECT * FROM t_validation WHERE kind = 'rule' AND violations <> 0 LOOP
        RAISE WARNING 'rule broken: [%] % = %', r.rule_group, r.check_name, r.violations;
    END LOOP;
    IF EXISTS (SELECT 1 FROM t_validation WHERE kind = 'rule' AND violations <> 0) THEN
        RAISE EXCEPTION 'FAIL seed validation: % rule(s) broken', (SELECT count(*) FROM t_validation WHERE kind = 'rule' AND violations <> 0);
    END IF;
    RAISE NOTICE 'PASS seed validation: % rules checked, 0 violations', (SELECT count(*) FROM t_validation WHERE kind = 'rule');
    IF (SELECT violations FROM t_validation WHERE check_name LIKE 'duplicate registrations%') = 0
       OR (SELECT violations FROM t_validation WHERE check_name LIKE 'names with stray whitespace%') = 0 THEN
        RAISE EXCEPTION 'FAIL the planted data-quality issues were not detected';
    END IF;
    FOR r IN SELECT * FROM t_validation WHERE kind = 'finding' LOOP
        RAISE NOTICE 'FINDING % = %', rpad(r.check_name, 88), r.violations;
    END LOOP;
END $$;
\echo MILESTONE 20 CHECKS PASSED
