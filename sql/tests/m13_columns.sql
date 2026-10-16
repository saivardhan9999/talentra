-- Milestone 13 (B42-B44): Licences, Sourcing and Subscriptions columns carry a type, standard domain,
-- justified nullability and an explicit sensitive-data class (same rules as m9, for Phase 3), plus
-- the column contents rule groups 9 and 10 prescribe.
\set ON_ERROR_STOP on
SET t.phase = '3';
\ir check_columns.sql

DO $$
DECLARE bad text;
BEGIN
    -- Rule group 9: a session records device, start, last activity and end
    SELECT string_agg(c, ', ') INTO bad FROM unnest(ARRAY['user_device_id', 'started_at', 'last_activity_at', 'ended_at']) c
    WHERE NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'user_session'::regclass AND attname = c AND NOT attisdropped);
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL user_session missing %', bad; END IF;
    RAISE NOTICE 'PASS sessions store device, start, last activity and end (rule group 9)';

    -- Rule group 10: download and view history carry actor, subject, timestamp and credit deduction
    SELECT string_agg(t || '.' || c, ', ') INTO bad FROM (VALUES
        ('profile_download_event', 'downloader_user_account_id'), ('profile_download_event', 'candidate_profile_id'),
        ('profile_download_event', 'downloaded_at'), ('profile_download_event', 'wallet_ledger_entry_id'),
        ('profile_view_event', 'viewer_user_account_id'), ('profile_view_event', 'candidate_profile_id'),
        ('profile_view_event', 'viewed_at'), ('profile_view_event', 'wallet_ledger_entry_id')) v(t, c)
    WHERE NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = v.t::regclass AND attname = v.c AND NOT attisdropped);
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL history column missing: %', bad; END IF;
    RAISE NOTICE 'PASS download and view history carry actor, subject, timestamp and credit deduction (rule group 10)';

    -- D17: credits are whole numbers; money is numeric(14,2) (checked schema-wide above)
    SELECT string_agg(c.relname || '.' || a.attname, ', ') INTO bad
    FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
    WHERE c.relname IN (SELECT table_name FROM expected_entity WHERE phase = 3) AND a.attnum > 0
      AND a.attname ~ '^(credit_|balance_)' AND a.atttypid <> 'integer'::regtype;
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL credit column not an integer: %', bad; END IF;
    RAISE NOTICE 'PASS credit columns are integers, money columns numeric(14,2) (D17)';

    -- Integration references (gateway, messaging provider) are bounded strings, unique where they key callbacks
    SELECT string_agg(c.relname || '.' || a.attname, ', ') INTO bad
    FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
    WHERE c.relname IN (SELECT table_name FROM expected_entity WHERE phase = 3) AND a.attnum > 0
      AND a.attname ~ '^(gateway|provider)_.*_ref$' AND format_type(a.atttypid, a.atttypmod) <> 'character varying(100)';
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL integration reference not varchar(100): %', bad; END IF;
    RAISE NOTICE 'PASS gateway and provider references are varchar(100)';
END $$;
