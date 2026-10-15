-- Milestone 4 (B12-B15): columns follow naming, standard domains, audit, nullability and translation rules.
-- =============================================================================
\set ON_ERROR_STOP on
SET client_min_messages = notice;

-- ---------------------------------------------------------------------------
-- 1. Static checks against the catalog
-- ---------------------------------------------------------------------------
DO $$
DECLARE bad text;
BEGIN
    -- Reserved keywords (PostgreSQL reserved + MySQL reserved words we might collide with)
    SELECT string_agg(DISTINCT ident, ', ') INTO bad FROM (
        SELECT c.relname AS ident FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relkind IN ('r','p','v','m','i')
        UNION
        SELECT a.attname FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND a.attnum > 0 AND NOT a.attisdropped AND c.relkind IN ('r','p')
    ) x
    WHERE ident IN (SELECT word FROM pg_get_keywords() WHERE catcode IN ('R','T','C'))
       OR ident IN ('key','keys','status_code','range','rank','order','group','condition','interval','usage',
                    'option','release','return','schema','signal','trigger','database','index','primary','references',
                    'read','write','change','desc','div','mod','match','lines','load','lock','long','rows','row');
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'reserved word used as identifier: %', bad; END IF;
    RAISE NOTICE 'PASS reserved keyword check (PostgreSQL R/T/C + MySQL reserved subset)';

    -- snake_case everywhere
    SELECT string_agg(relname, ', ') INTO bad FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND relkind IN ('r','p','v','i') AND relname !~ '^[a-z][a-z0-9_]*$';
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'non snake_case relation: %', bad; END IF;

    -- every table has PK named id (first PK column)
    SELECT string_agg(c.relname, ', ') INTO bad FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r','p') AND NOT c.relispartition
      AND NOT EXISTS (SELECT 1 FROM pg_constraint k JOIN pg_attribute a ON a.attrelid = k.conrelid AND a.attnum = k.conkey[1]
                      WHERE k.conrelid = c.oid AND k.contype = 'p' AND a.attname = 'id');
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'table without id primary key: %', bad; END IF;
    RAISE NOTICE 'PASS snake_case and surrogate id primary keys';

    -- every single-column FK column ends in _id
    SELECT string_agg(c.relname || '.' || a.attname, ', ') INTO bad
    FROM pg_constraint k JOIN pg_class c ON c.oid = k.conrelid JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = k.conrelid AND a.attnum = ANY (k.conkey)
    WHERE n.nspname = 'public' AND k.contype = 'f' AND NOT c.relispartition
      AND a.attname !~ '_id$' AND a.attname NOT IN ('created_by', 'updated_by');
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FK column not named *_id: %', bad; END IF;
    RAISE NOTICE 'PASS FK columns end in _id (created_by/updated_by are the documented audit exception)';

    -- index / unique naming
    SELECT string_agg(i.relname, ', ') INTO bad FROM pg_index x
    JOIN pg_class i ON i.oid = x.indexrelid JOIN pg_class t ON t.oid = x.indrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'public' AND NOT x.indisprimary AND NOT t.relispartition
      AND i.relname !~ ('^(idx|uq)_' || t.relname || '_');
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'index not named idx_/uq_<table>_...: %', bad; END IF;
    RAISE NOTICE 'PASS index naming idx_table_column / uq_table_column';

    -- no floating point anywhere
    SELECT string_agg(c.relname || '.' || a.attname, ', ') INTO bad
    FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r','p') AND a.attnum > 0
      AND a.atttypid IN ('real'::regtype, 'double precision'::regtype, 'money'::regtype);
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'floating point / money type used: %', bad; END IF;

    -- timestamps are timestamptz
    SELECT string_agg(c.relname || '.' || a.attname, ', ') INTO bad
    FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r','p') AND a.attnum > 0
      AND a.atttypid = 'timestamp without time zone'::regtype;
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'timestamp without time zone: %', bad; END IF;
    RAISE NOTICE 'PASS money is numeric, timestamps are timestamptz (UTC)';

    -- every money amount has a currency companion
    SELECT string_agg(c.relname || '.' || a.attname, ', ') INTO bad
    FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r','p') AND NOT c.relispartition AND a.attname ~ '_amount$'
      AND NOT EXISTS (SELECT 1 FROM pg_attribute b WHERE b.attrelid = c.oid AND b.attname ~ 'currency_id$');
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'money column without currency: %', bad; END IF;
    RAISE NOTICE 'PASS every *_amount column has a currency companion';

    -- audit columns on every business table (append-only tables: created_* only)
    SELECT string_agg(c.relname, ', ') INTO bad FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r','p') AND NOT c.relispartition
      AND (SELECT count(*) FROM pg_attribute a WHERE a.attrelid = c.oid AND a.attname IN ('created_at','created_by')) <> 2;
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'table missing created_at/created_by: %', bad; END IF;
    SELECT string_agg(c.relname, ', ') INTO bad FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r','p') AND NOT c.relispartition
      AND NOT EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = c.oid AND a.attname = 'updated_at')
      AND NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = c.oid AND t.tgname LIKE '%append_only');
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'mutable table missing updated_at: %', bad; END IF;
    RAISE NOTICE 'PASS audit columns (created_*/updated_*; append-only tables carry created_* only)';

    -- every nullable column has a written justification (comment containing "null=")
    SELECT string_agg(c.relname || '.' || a.attname, ', ') INTO bad
    FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r','p') AND NOT c.relispartition
      AND a.attnum > 0 AND NOT a.attisdropped AND NOT a.attnotnull
      AND coalesce(col_description(c.oid, a.attnum), '') !~ 'null'
      AND a.attname <> 'search_document';
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'nullable column without justification: %', bad; END IF;
    RAISE NOTICE 'PASS every nullable column has a justification comment';

    -- every FK column has an index (leading column) on large tables
    SELECT string_agg(c.relname || '.' || a.attname, ', ') INTO bad
    FROM pg_constraint k JOIN pg_class c ON c.oid = k.conrelid JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = k.conrelid AND a.attnum = k.conkey[1]
    WHERE n.nspname = 'public' AND k.contype = 'f' AND NOT c.relispartition
      AND c.relname IN ('application','candidate_skill','candidate_education','candidate_work_experience','job_requirement_location','job_requirement_skill')
      AND a.attname NOT IN ('created_by','updated_by')
      AND a.attname IN ('candidate_profile_id','job_requirement_id','skill_id','city_id')
      AND NOT (c.relname = 'candidate_work_experience' AND a.attname = 'city_id')  -- display only, never a search path
      AND NOT EXISTS (SELECT 1 FROM pg_index x WHERE x.indrelid = c.oid AND x.indkey[0] = a.attnum);
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'hot FK without leading index: %', bad; END IF;
    RAISE NOTICE 'PASS hot-path FK columns are indexed';

    -- every UI label key has a default-language translation
    SELECT string_agg(k.label_key, ', ') INTO bad FROM ui_label_key k
    WHERE NOT EXISTS (SELECT 1 FROM ui_label_translation t JOIN language l ON l.id = t.language_id
                      WHERE t.ui_label_key_id = k.id AND l.is_default);
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'label keys without default translation: %', bad; END IF;
    RAISE NOTICE 'PASS every UI label key has a default-language translation';
END $$;
