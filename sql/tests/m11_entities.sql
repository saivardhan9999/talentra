-- Milestone 11 (B36-B38): Licences, Sourcing and Subscriptions entities exist.
-- The orphan-table check in m2 covers these modules too (shared expected_entity.sql).
\set ON_ERROR_STOP on
\ir expected_entity.sql

DO $$
DECLARE bad text; n int;
BEGIN
    SELECT string_agg(table_name, ', ') INTO bad FROM expected_entity e
    WHERE e.phase = 3 AND to_regclass(e.table_name) IS NULL;
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL expected entity missing: %', bad; END IF;
    FOR bad, n IN SELECT module, count(*) FROM expected_entity WHERE phase = 3 GROUP BY module ORDER BY module LOOP
        RAISE NOTICE 'PASS % : % entities present', rpad(bad, 22), n;
    END LOOP;

    -- Hand-offs from earlier phases are wired: credit-consuming views, consultant shortlists
    SELECT string_agg(t || '.' || c, ', ') INTO bad FROM (VALUES ('profile_view_event', 'wallet_ledger_entry_id'),
        ('talent_list', 'sourcing_request_id')) v(t, c)
    WHERE NOT EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = v.t::regclass AND a.attname = v.c AND NOT a.attisdropped);
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL hand-off column missing: %', bad; END IF;
    RAISE NOTICE 'PASS Phase 1 hand-offs wired (profile_view_event credit reference, consultant shortlist on talent_list)';

    -- Payment gateway boundary (docket §6): no card or bank data anywhere in the schema
    SELECT string_agg(c.relname || '.' || a.attname, ', ') INTO bad
    FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid JOIN pg_namespace s ON s.oid = c.relnamespace
    WHERE s.nspname = 'public' AND c.relkind IN ('r','p') AND NOT c.relispartition AND a.attnum > 0
      AND a.attname ~ '(card|cvv|pan_number|expiry_month|iban|ifsc|bank_account|account_number)';
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL card or bank data column: %', bad; END IF;
    RAISE NOTICE 'PASS no card or bank data columns (gateway boundary)';

    -- Rule group 9: licence limits are explicit columns
    IF (SELECT count(*) FROM pg_attribute WHERE attrelid = 'licence'::regclass AND attname IN ('max_users', 'max_devices_per_user') AND attnotnull) <> 2 THEN
        RAISE EXCEPTION 'FAIL licence must store max_users and max_devices_per_user';
    END IF;
    RAISE NOTICE 'PASS licence stores max_users and max_devices_per_user as explicit columns';
END $$;
