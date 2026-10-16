-- Column rules shared by m9 (Phase 2) and m13 (Phase 3). The including script sets t.phase.
-- Per phase: every data column states its class; every date range has a CHECK.
-- Schema-wide: Sensitive = token/hash only; email, phone, money and free-text domains.
\ir expected_entity.sql

DO $$
DECLARE bad text; n int; p int := current_setting('t.phase')::int;
BEGIN
    -- 1. Every data column of a table of this phase states its class. Exempt: keys and audit columns
    --    (Internal by definition), lookup-shaped columns, and boolean flags.
    SELECT string_agg(c.relname || '.' || a.attname, ', '), count(*) INTO bad, n
    FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
    WHERE c.relname IN (SELECT table_name FROM expected_entity WHERE phase = p OR (p = 2 AND table_name IN ('user_account', 'organisation')))
      AND a.attnum > 0 AND NOT a.attisdropped
      AND a.attname NOT IN ('id', 'created_at', 'created_by', 'updated_at', 'updated_by', 'code', 'sort_order')
      AND a.attname !~ '_id$' AND a.atttypid <> 'boolean'::regtype
      AND coalesce(col_description(c.oid, a.attnum), '') !~ 'class=(Public|Internal|Personal|Sensitive)';
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL % data column(s) without an explicit class: %', n, bad; END IF;
    SELECT count(*) INTO n FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
    WHERE c.relname IN (SELECT table_name FROM expected_entity WHERE phase = p OR (p = 2 AND table_name IN ('user_account', 'organisation')))
      AND a.attnum > 0 AND NOT a.attisdropped;
    RAISE NOTICE 'PASS every data column of the Phase % tables states its class (% columns checked)', p, n;

    -- 2. Sensitive values are never stored in clear: every Sensitive column is a vault token or a keyed hash.
    SELECT string_agg(c.relname || '.' || a.attname, ', ') INTO bad
    FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid JOIN pg_namespace s ON s.oid = c.relnamespace
    WHERE s.nspname = 'public' AND c.relkind IN ('r','p') AND NOT c.relispartition AND a.attnum > 0
      AND col_description(c.oid, a.attnum) ~ 'class=Sensitive'
      AND a.attname !~ '_(token|hmac|hash)$';
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL Sensitive column that is not a token or hash: %', bad; END IF;
    SELECT count(*) INTO n FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
    WHERE a.attnum > 0 AND NOT c.relispartition AND col_description(c.oid, a.attnum) ~ 'class=Sensitive';
    RAISE NOTICE 'PASS % Sensitive column(s), all vault tokens or keyed hashes', n;

    -- 3. Standard domains (rule group 3), schema-wide
    SELECT string_agg(c.relname || '.' || a.attname, ', ') INTO bad
    FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid JOIN pg_namespace s ON s.oid = c.relnamespace
    WHERE s.nspname = 'public' AND c.relkind IN ('r','p') AND NOT c.relispartition AND a.attnum > 0
      AND a.attname ~ 'email$' AND (format_type(a.atttypid, a.atttypmod) <> 'character varying(254)'
          OR NOT EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = c.oid AND k.contype = 'c'
                         AND a.attnum = ANY (k.conkey) AND pg_get_constraintdef(k.oid) ~ 'lower\('));
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL email column not varchar(254) with a lowercase CHECK: %', bad; END IF;
    RAISE NOTICE 'PASS email columns are varchar(254) with a lowercase CHECK';

    SELECT string_agg(c.relname || '.' || a.attname, ', ') INTO bad
    FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid JOIN pg_namespace s ON s.oid = c.relnamespace
    WHERE s.nspname = 'public' AND c.relkind IN ('r','p') AND NOT c.relispartition AND a.attnum > 0
      AND a.attname ~ 'phone_e164$' AND (
          NOT EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = c.oid AND k.contype = 'c'
                      AND a.attnum = ANY (k.conkey) AND pg_get_constraintdef(k.oid) ~ '\[1-9\]')
          OR NOT EXISTS (SELECT 1 FROM pg_attribute b WHERE b.attrelid = c.oid AND b.attname ~ 'country_id$'));
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL phone column without E.164 CHECK and country companion: %', bad; END IF;
    RAISE NOTICE 'PASS phone columns are E.164 with a country column';

    SELECT string_agg(c.relname || '.' || a.attname, ', ') INTO bad
    FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid JOIN pg_namespace s ON s.oid = c.relnamespace
    WHERE s.nspname = 'public' AND c.relkind IN ('r','p') AND NOT c.relispartition AND a.attnum > 0
      AND a.attname ~ '_amount$' AND format_type(a.atttypid, a.atttypmod) <> 'numeric(14,2)';
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL money column not numeric(14,2): %', bad; END IF;
    RAISE NOTICE 'PASS money columns are numeric(14,2)';

    -- Free text is bounded; unbounded text only where justified (job description, resume body)
    SELECT string_agg(c.relname || '.' || a.attname, ', ') INTO bad
    FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid JOIN pg_namespace s ON s.oid = c.relnamespace
    WHERE s.nspname = 'public' AND c.relkind IN ('r','p') AND NOT c.relispartition AND a.attnum > 0
      AND (a.atttypid = 'text'::regtype OR format_type(a.atttypid, a.atttypmod) = 'character varying')
      AND (c.relname, a.attname) NOT IN (('job_requirement', 'description'), ('resume_version', 'body_text'));
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL unbounded text column: %', bad; END IF;
    RAISE NOTICE 'PASS free text is bounded except the two justified columns';

    -- Date ranges carry a CHECK (rule group 3): every table with a start/end pair has a range CHECK
    SELECT string_agg(DISTINCT c.relname, ', ') INTO bad
    FROM pg_class c JOIN pg_namespace s ON s.oid = c.relnamespace
    WHERE s.nspname = 'public' AND c.relkind IN ('r','p') AND NOT c.relispartition
      AND c.relname IN (SELECT table_name FROM expected_entity WHERE phase = p)
      AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = c.oid AND a.attname ~ '(_to|_end_at|revoked_at|removed_at|decided_at|released_at|ended_at|cancelled_at|processed_at|delivered_at|responded_at|unblocked_at|resolved_at|closed_at|read_at)$')
      AND NOT EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = c.oid AND k.contype IN ('c','x')
                      AND (k.conname ~ '(date_range|after_applied|no_overlap)'));
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL date range without CHECK: %', bad; END IF;
    RAISE NOTICE 'PASS every Phase % date range has a CHECK', p;
END $$;
