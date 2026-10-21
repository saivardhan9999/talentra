-- Milestone 21 (B70-B74): the performance work is in place and keeps working.
-- Latency figures come from perf/benchmark.py (docs/phase5-performance.md); this check proves the
-- structural part on any seeded database (CI runs it at 1% scale):
--   the M21 indexes exist and serve their queries; the ranked name search returns exactly what
--   row-level security allows; recent-window queries on the two history tables prune partitions.
\set ON_ERROR_STOP on
\ir ../queries/params.sql

CREATE FUNCTION pg_temp.plan_uses(p_sql text, p_index text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE plan text := ''; line text;
BEGIN
    -- sequential scans are switched off so a small (1%) dataset still proves the index can serve the query
    PERFORM set_config('enable_seqscan', 'off', true);
    FOR line IN EXECUTE 'EXPLAIN ' || p_sql LOOP plan := plan || line || E'\n'; END LOOP;
    PERFORM set_config('enable_seqscan', 'on', true);
    IF position(p_index IN plan) = 0 THEN RAISE EXCEPTION E'FAIL % not used for:\n%\n%', p_index, p_sql, plan; END IF;
    RAISE NOTICE 'PASS % serves: %', p_index, left(regexp_replace(p_sql, '\s+', ' ', 'g'), 100);
END $$;
CREATE FUNCTION pg_temp.prunes(p_sql text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE plan text := ''; line text;
BEGIN
    FOR line IN EXECUTE 'EXPLAIN (ANALYZE, COSTS OFF) ' || p_sql LOOP plan := plan || line || E'\n'; END LOOP;
    IF plan !~ 'Subplans Removed: [1-9]' THEN RAISE EXCEPTION E'FAIL no partition pruning for:\n%\n%', p_sql, plan; END IF;
    RAISE NOTICE 'PASS partitions pruned (%): %', substring(plan from 'Subplans Removed: [0-9]+'), left(regexp_replace(p_sql, '\s+', ' ', 'g'), 90);
END $$;

SELECT pg_temp.plan_uses(format($q$SELECT occurred_at FROM audit_event WHERE organisation_id = %s AND occurred_at >= now() - interval '30 days' ORDER BY occurred_at DESC LIMIT 50$q$, :org_busy),
                         'organisation_id_occurred_at') \g /dev/null   -- partition indexes carry generated names
SELECT pg_temp.plan_uses(format($q$SELECT count(*) FROM login_attempt WHERE attempted_identifier_hmac = decode(%L, 'hex') AND login_outcome_id <> 1 AND attempted_at >= now() - interval '15 minutes'$q$, :'hmac_failed'),
                         'attempted_identifier_hmac') \g /dev/null
SELECT pg_temp.plan_uses(format($q$SELECT id FROM notification_delivery WHERE provider_message_ref = %L$q$, :'delivery_ref'),
                         'provider_message_ref') \g /dev/null
SELECT pg_temp.plan_uses($q$SELECT count(*) FROM fact_application WHERE joined_date_id IS NOT NULL$q$, 'idx_fact_application_joined_date_id') \g /dev/null

SELECT pg_temp.prunes($q$SELECT count(*) FROM application_status_history WHERE changed_at >= now() - interval '7 days'$q$) \g /dev/null
SELECT pg_temp.prunes($q$SELECT count(*) FROM notification_delivery WHERE queued_at >= now() - interval '24 hours'$q$) \g /dev/null

-- ranked name search: same answer as row-level security, best matches first, never a hidden profile
BEGIN;
SELECT set_config('app.current_user_id', :'recruiter_busy', true) \g /dev/null
SET LOCAL ROLE talentra_app;
CREATE TEMP TABLE t_visible AS
    SELECT id, round(similarity(full_name, :'cand_name')::numeric, 4) AS s FROM candidate_profile WHERE full_name % :'cand_name';
CREATE TEMP TABLE t_found AS
    SELECT id, round(score::numeric, 4) AS s FROM app_search_candidates_by_name(:'cand_name', 100);
DO $$
DECLARE n_found int := (SELECT count(*) FROM t_found);
BEGIN
    IF n_found = 0 THEN RAISE EXCEPTION 'FAIL name search returned nothing'; END IF;
    IF EXISTS (SELECT 1 FROM t_found WHERE id NOT IN (SELECT id FROM t_visible)) THEN
        RAISE EXCEPTION 'FAIL name search returned a profile row-level security hides from this recruiter';
    END IF;
    IF EXISTS (SELECT 1 FROM t_visible WHERE s > (SELECT min(s) FROM t_found) AND id NOT IN (SELECT id FROM t_found)) THEN
        RAISE EXCEPTION 'FAIL name search skipped a better visible match';
    END IF;
    RAISE NOTICE 'PASS ranked name search: % best visible matches, none hidden from this recruiter, none better missed (of % visible)',
        n_found, (SELECT count(*) FROM t_visible);
END $$;
ROLLBACK;
\echo MILESTONE 21 CHECKS PASSED
