-- t04 Concurrency: limits hold when many sessions race (docket rule groups 2 and 9, B45/B47).
-- Uses dblink to open real parallel connections, so it must commit: run.sh runs this file on a throwaway clone
-- (talentra_v2_scratch) and drops it afterwards. Pattern for each race: the test session holds the row lock the rule
-- depends on, fires N concurrent attempts (they queue on the lock), then releases it and counts winners and losers.
CREATE EXTENSION IF NOT EXISTS dblink;

CREATE FUNCTION pg_temp.race_start(p_sqls text[]) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  FOR i IN 1 .. cardinality(p_sqls) LOOP
    PERFORM dblink_connect('race' || i, 'dbname=' || current_database() || ' user=postgres');
    PERFORM dblink_send_query('race' || i, p_sqls[i]);
  END LOOP;
  PERFORM pg_sleep(0.3);                 -- let every attempt reach the lock and queue behind it
END $$;

CREATE FUNCTION pg_temp.race_collect(p_n int) RETURNS TABLE (ok boolean, error text) LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
  FOR i IN 1 .. p_n LOOP
    SELECT count(*) INTO n FROM dblink_get_result('race' || i, false) AS t (v text);
    ok := n > 0; error := CASE WHEN n = 0 THEN dblink_error_message('race' || i) END;
    RETURN NEXT;
    PERFORM dblink_disconnect('race' || i);
  END LOOP;
END $$;

-- 1. device limit at login: a candidate (limit 3) with no active session logs in from 6 new devices at once
SELECT p.app_user_id AS cand_user FROM candidate_profile p
WHERE p.deleted_at IS NULL AND NOT EXISTS (SELECT 1 FROM user_session s WHERE s.app_user_id = p.app_user_id AND s.ended_at IS NULL)
ORDER BY p.id LIMIT 1 \gset
BEGIN;
SELECT 1 FROM app_user WHERE id = :cand_user FOR UPDATE \g /dev/null
SELECT pg_temp.race_start(ARRAY(
  SELECT format($$SELECT coalesce(auth_open_session(%s, sha256(%L::bytea), 'race device', sha256(%L::bytea))::text, 'refused')$$,
                :cand_user, 'race-device-' || g, 'race-token-' || g) FROM generate_series(1, 6) g)) \g /dev/null
COMMIT;
CREATE TEMP TABLE r1 AS SELECT * FROM pg_temp.race_collect(6);
SELECT pg_temp.check((SELECT count(*) = 3 FROM user_session WHERE app_user_id = :cand_user AND ended_at IS NULL)
                     AND (SELECT count(*) = 3 FROM audit_event WHERE actor_app_user_id = :cand_user AND action = 'user_session.refused.device_limit'),
                     't04 six concurrent logins, device limit 3: exactly 3 sessions, 3 refusals in the audit trail');

-- 2. wallet: 8 concurrent debits of 1 credit against a balance of 3
SELECT id AS wallet, balance_credits AS bal FROM wallet ORDER BY id LIMIT 1 \gset
SELECT CASE WHEN :bal > 3 THEN wallet_post(:wallet, 'outreach_debit', 3 - :bal, 'race-setup-debit')
            WHEN :bal < 3 THEN wallet_post(:wallet, 'recharge', 3 - :bal, 'race-setup-credit') END \g /dev/null
BEGIN;
SELECT 1 FROM wallet WHERE id = :wallet FOR UPDATE \g /dev/null
SELECT pg_temp.race_start(ARRAY(
  SELECT format($$SELECT wallet_post(%s, 'profile_download_debit', -1, %L)$$, :wallet, 'race-debit-' || g) FROM generate_series(1, 8) g)) \g /dev/null
COMMIT;
CREATE TEMP TABLE r2 AS SELECT * FROM pg_temp.race_collect(8);
SELECT pg_temp.check((SELECT count(*) FILTER (WHERE ok) = 3 AND count(*) FILTER (WHERE error ~ 'insufficient credits') = 5 FROM r2)
                     AND (SELECT balance_credits = 0 FROM wallet WHERE id = :wallet)
                     AND (SELECT sum(credits) = 0 FROM wallet_ledger_entry WHERE wallet_id = :wallet),
                     't04 eight concurrent debits on 3 credits: 3 succeed, 5 refused, balance 0 and equal to the ledger');

-- 3. seats: an organisation with exactly one free seat gets 3 concurrent new members
SELECT o.id AS org, s.max_seats - (SELECT count(*) FROM organisation_member m WHERE m.organisation_id = o.id AND m.valid_to IS NULL) AS free
FROM organisation o JOIN subscription s ON s.organisation_id = o.id AND current_date >= s.starts_on AND current_date < s.ends_on
WHERE s.max_seats - (SELECT count(*) FROM organisation_member m WHERE m.organisation_id = o.id AND m.valid_to IS NULL) >= 1
ORDER BY o.id LIMIT 1 \gset
CREATE TEMP TABLE spare AS SELECT app_user_id, row_number() OVER (ORDER BY id) AS n FROM candidate_profile
WHERE NOT EXISTS (SELECT 1 FROM organisation_member m WHERE m.app_user_id = candidate_profile.app_user_id) ORDER BY id LIMIT :free + 2;
INSERT INTO organisation_member (organisation_id, app_user_id, access_role_id) SELECT :org, app_user_id, 5 FROM spare WHERE n <= :free - 1;
BEGIN;
SELECT 1 FROM organisation WHERE id = :org FOR UPDATE \g /dev/null
SELECT pg_temp.race_start(ARRAY(
  SELECT format($$INSERT INTO organisation_member (organisation_id, app_user_id, access_role_id) VALUES (%s, %s, 5) RETURNING id$$, :org, app_user_id)
  FROM spare WHERE n > :free - 1)) \g /dev/null
COMMIT;
CREATE TEMP TABLE r3 AS SELECT * FROM pg_temp.race_collect(3);
SELECT pg_temp.check((SELECT count(*) FILTER (WHERE ok) = 1 AND count(*) FILTER (WHERE error ~ 'used all') = 2 FROM r3),
                     't04 three concurrent members for the last seat: one joins, two are refused');

-- 4. positions: two offers race to join a job with one position left
SELECT a.job_requirement_id AS job, min(a.id) AS app1, max(a.id) AS app2 FROM application a
WHERE a.application_status_id = 4 GROUP BY a.job_requirement_id HAVING count(*) >= 2 ORDER BY 1 LIMIT 1 \gset
UPDATE job_requirement SET positions_total = positions_filled + 1 WHERE id = :job;
BEGIN;
SELECT 1 FROM job_requirement WHERE id = :job FOR UPDATE \g /dev/null
SELECT pg_temp.race_start(ARRAY[
  format('UPDATE application SET application_status_id = 5 WHERE id = %s RETURNING id', :app1),
  format('UPDATE application SET application_status_id = 5 WHERE id = %s RETURNING id', :app2)]) \g /dev/null
COMMIT;
CREATE TEMP TABLE r4 AS SELECT * FROM pg_temp.race_collect(2);
SELECT pg_temp.check((SELECT count(*) FILTER (WHERE ok) = 1 AND count(*) FILTER (WHERE error ~ 'ck_job_requirement_positions') = 1 FROM r4)
                     AND (SELECT positions_filled = positions_total AND job_status_id = 5 FROM job_requirement WHERE id = :job),
                     't04 two concurrent joins for the last position: one wins, the job becomes filled');
