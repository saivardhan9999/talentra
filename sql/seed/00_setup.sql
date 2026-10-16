-- =============================================================================
-- Talentra seed :: 00_setup.sql
-- Synthetic data generator (Phase 5, M19). Runs inside PostgreSQL, set-based, deterministic:
-- every value is derived from a row number through seed.r(), so a rerun at the same scale
-- produces the same data. Scale 1 = laptop scale (1M candidate profiles, 100k job
-- requirements, 5M applications); the runner passes -v scale=...
-- Helpers live in schema "seed", which 99_finish.sql drops again.
-- =============================================================================
\set ON_ERROR_STOP on
-- the scale is stored on the database, so every later seed file (a new session) and the M19 check read it
SELECT set_config('talentra.seed_scale', :'scale', false) \g /dev/null
DO $$ BEGIN
    EXECUTE format('ALTER DATABASE %I SET talentra.seed_scale = %L', current_database(), current_setting('talentra.seed_scale'));
END $$;

SET client_min_messages = warning;
DROP SCHEMA IF EXISTS seed CASCADE;
RESET client_min_messages;
CREATE SCHEMA seed;

-- row count at the configured scale
CREATE FUNCTION seed.n(p_base numeric) RETURNS bigint LANGUAGE sql STABLE AS
$$ SELECT greatest(1, round(p_base * current_setting('talentra.seed_scale')::numeric))::bigint $$;
-- deterministic uniform value in [0, 1) from a row number and a salt
CREATE FUNCTION seed.r(p_row bigint, p_salt int DEFAULT 0) RETURNS numeric LANGUAGE sql IMMUTABLE AS
$$ SELECT ((hashint8(p_row * 1009 + p_salt) & 2147483647)::numeric / 2147483648) $$;
-- skewed index 1..n (low indexes are popular: big cities, common skills, large employers)
CREATE FUNCTION seed.skew(p_n bigint, p_row bigint, p_salt int DEFAULT 0, p_power numeric DEFAULT 2.2) RETURNS bigint LANGUAGE sql IMMUTABLE AS
$$ SELECT 1 + floor(p_n * power(seed.r(p_row, p_salt), p_power))::bigint $$;
-- uniform pick from an array
CREATE FUNCTION seed.pick(p_arr text[], p_row bigint, p_salt int DEFAULT 0) RETURNS text LANGUAGE sql IMMUTABLE AS
$$ SELECT p_arr[1 + floor(seed.r(p_row, p_salt) * array_length(p_arr, 1))::int] $$;
-- fake keyed hash / token (32 bytes): the generator never holds a real secret
CREATE FUNCTION seed.hmac(p_text text) RETURNS bytea LANGUAGE sql IMMUTABLE AS
$$ SELECT decode(md5(p_text) || md5('k:' || p_text), 'hex') $$;
-- moment within the seeded history window (last 18 months)
CREATE FUNCTION seed.ts(p_row bigint, p_salt int DEFAULT 0) RETURNS timestamptz LANGUAGE sql STABLE AS
$$ SELECT now() - interval '540 days' * seed.r(p_row, p_salt) $$;

-- Lookups by code, so the generator never hard-codes ids it does not own.
CREATE FUNCTION seed.id(p_table text, p_code text) RETURNS bigint LANGUAGE plpgsql STABLE AS $$
DECLARE v bigint;
BEGIN
    EXECUTE format('SELECT id FROM %I WHERE code = $1', p_table) INTO v USING p_code;
    IF v IS NULL THEN RAISE EXCEPTION 'seed: %.% not found', p_table, p_code; END IF;
    RETURN v;
END $$;

-- Run log: one row per seed step (visible in the runner output).
CREATE TABLE seed.step (name text PRIMARY KEY, rows_written bigint, finished_at timestamptz DEFAULT clock_timestamp());
CREATE FUNCTION seed.done(p_name text, p_rows bigint) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO seed.step (name, rows_written) VALUES (p_name, p_rows)
    ON CONFLICT (name) DO UPDATE SET rows_written = EXCLUDED.rows_written, finished_at = clock_timestamp();
    RAISE NOTICE 'seeded % : % rows', rpad(p_name, 44), p_rows;
END $$;
