-- Prepended to every test file by run.sh. Session-local helpers (pg_temp), gone when the test's connection closes.
\set ON_ERROR_STOP on
SET client_min_messages = notice;

-- p_sql must fail with an error whose message matches p_pattern (case-insensitive regex)
CREATE FUNCTION pg_temp.expect_error(p_sql text, p_pattern text, p_label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM !~* p_pattern THEN
      RAISE EXCEPTION 'FAIL %: expected an error matching "%", got "%"', p_label, p_pattern, SQLERRM;
    END IF;
    RAISE NOTICE 'PASS %', p_label;
    RETURN;
  END;
  RAISE EXCEPTION 'FAIL %: expected an error matching "%", but the statement succeeded', p_label, p_pattern;
END $$;

CREATE FUNCTION pg_temp.check(p_ok boolean, p_label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF p_ok IS NOT TRUE THEN RAISE EXCEPTION 'FAIL %', p_label; END IF;
  RAISE NOTICE 'PASS %', p_label;
END $$;

-- act as a user of the API: runtime role plus the transaction's identity
CREATE FUNCTION pg_temp.act_as(p_app_user_id bigint) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('app.user_id', coalesce(p_app_user_id::text, ''), true);
END $$;
