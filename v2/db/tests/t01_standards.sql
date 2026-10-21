-- t01 Standards: the docket's section 5 rules checked against the live catalog, so a new table that breaks one fails CI.
-- Covers NFR-MNT-02. Read-only.
\set ON_ERROR_STOP on
SET client_min_messages = notice;

CREATE TEMP VIEW t_table AS
SELECT c.oid, c.relname, c.relkind, c.relispartition,
       EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = c.oid AND a.attname = 'created_by') AS is_business,
       EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = c.oid AND a.attname = 'ui_label_id')
         AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = c.oid AND a.attname = 'code') AS is_lookup
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p') AND c.relname <> 'schema_migration';

CREATE TEMP VIEW t_column AS
SELECT t.relname, t.is_business, t.relispartition, a.attname, a.attnotnull, format_type(a.atttypid, a.atttypmod) AS type_name,
       col_description(t.oid, a.attnum) AS comment
FROM t_table t JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum > 0 AND NOT a.attisdropped;

DO $$
DECLARE bad text;
BEGIN
  -- rule group 1: snake_case, singular, no reserved words
  SELECT string_agg(relname || '.' || attname, ', ') INTO bad FROM t_column WHERE relname !~ '^[a-z][a-z0-9_]*$' OR attname !~ '^[a-z][a-z0-9_]*$';
  ASSERT bad IS NULL, 'names not in snake_case: ' || bad;
  RAISE NOTICE 'PASS t01 table and column names are snake_case';

  SELECT string_agg(relname, ', ') INTO bad FROM t_table WHERE NOT relispartition AND relname ~ 's$' AND relname !~ 'status$';
  ASSERT bad IS NULL, 'plural table names: ' || bad;
  RAISE NOTICE 'PASS t01 table names are singular';

  SELECT string_agg(DISTINCT x.name, ', ') INTO bad
  FROM (SELECT relname AS name FROM t_table UNION SELECT attname FROM t_column) x JOIN pg_get_keywords() k ON k.word = x.name WHERE k.catcode IN ('R', 'T', 'C');
  ASSERT bad IS NULL, 'reserved words used as identifiers: ' || bad;
  RAISE NOTICE 'PASS t01 no reserved keywords as identifiers';

  -- rule group 2: surrogate key "id" on every table (partitioned audit_event: (id, occurred_at), deviation D-02)
  SELECT string_agg(t.relname, ', ') INTO bad FROM t_table t
  WHERE NOT t.relispartition AND NOT EXISTS (
    SELECT 1 FROM pg_constraint k JOIN pg_attribute a ON a.attrelid = k.conrelid AND a.attnum = k.conkey[1]
    WHERE k.conrelid = t.oid AND k.contype = 'p' AND a.attname = 'id' AND format_type(a.atttypid, NULL) IN ('bigint', 'integer', 'smallint'));
  ASSERT bad IS NULL, 'tables without an integer surrogate key named id: ' || bad;
  RAISE NOTICE 'PASS t01 every table has an integer surrogate key named id';

  SELECT string_agg(k.conrelid::regclass || '.' || a.attname, ', ') INTO bad
  FROM pg_constraint k JOIN pg_attribute a ON a.attrelid = k.conrelid AND a.attnum = ANY (k.conkey)
  JOIN t_table t ON t.oid = k.conrelid AND NOT t.relispartition
  WHERE k.contype = 'f' AND a.attname !~ '_id$' AND a.attname NOT IN ('created_by', 'updated_by');
  ASSERT bad IS NULL, 'foreign key columns not ending in _id: ' || bad;
  RAISE NOTICE 'PASS t01 foreign key columns end in _id';

  -- every foreign key to a business table is backed by an index led by its first column (deletes and joins stay fast);
  -- keys to reference tables and the audit columns are exempt (rows there are never deleted, D-04)
  SELECT string_agg(k.conname, ', ') INTO bad
  FROM pg_constraint k JOIN t_table child ON child.oid = k.conrelid AND NOT child.relispartition
  JOIN t_table parent ON parent.oid = k.confrelid
  WHERE k.contype = 'f' AND parent.is_business AND k.conname NOT LIKE '%created_by' AND k.conname NOT LIKE '%updated_by'
    AND NOT EXISTS (SELECT 1 FROM pg_index i WHERE i.indrelid = k.conrelid AND i.indkey[0] = k.conkey[1]);
  ASSERT bad IS NULL, 'foreign keys without a supporting index: ' || bad;
  RAISE NOTICE 'PASS t01 every foreign key to a business table has a supporting index';

  SELECT string_agg(conname, ', ') INTO bad FROM pg_constraint k JOIN t_table t ON t.oid = k.conrelid AND NOT t.relispartition
  WHERE k.contype = 'u' AND conname !~ '^uq_';
  ASSERT bad IS NULL, 'unique constraints not named uq_: ' || bad;
  SELECT string_agg(i.relname, ', ') INTO bad FROM pg_index x JOIN pg_class i ON i.oid = x.indexrelid JOIN t_table t ON t.oid = x.indrelid AND NOT t.relispartition
  WHERE i.relname !~ '^(idx|uq|ex)_' AND i.relname !~ '_pkey$';
  ASSERT bad IS NULL, 'indexes not named idx_ / uq_: ' || bad;
  RAISE NOTICE 'PASS t01 index and unique constraint names follow idx_ / uq_';

  -- rule group 3: no floating point, money has a currency companion
  SELECT string_agg(relname || '.' || attname, ', ') INTO bad FROM t_column WHERE type_name IN ('real', 'double precision', 'money');
  ASSERT bad IS NULL, 'floating point or money type columns: ' || bad;
  SELECT string_agg(relname || '.' || attname, ', ') INTO bad FROM t_column c
  WHERE type_name = 'money_amount' AND NOT EXISTS (SELECT 1 FROM t_column x WHERE x.relname = c.relname AND x.attname LIKE '%currency_id');
  ASSERT bad IS NULL, 'money columns without a currency column: ' || bad;
  RAISE NOTICE 'PASS t01 money is fixed precision with a currency column';

  -- every enumeration is a lookup table of the standard shape with a translated label
  SELECT string_agg(relname, ', ') INTO bad FROM t_table t WHERE is_lookup AND (
    SELECT count(*) FROM t_column c WHERE c.relname = t.relname AND c.attname IN ('id', 'code', 'ui_label_id', 'is_active', 'sort_order') AND c.attnotnull) <> 5;
  ASSERT bad IS NULL, 'lookup tables missing standard columns: ' || bad;
  SELECT string_agg(l.label_key, ', ') INTO bad FROM ui_label l WHERE NOT EXISTS (SELECT 1 FROM ui_translation t WHERE t.ui_label_id = l.id AND t.language_id = 1);
  ASSERT bad IS NULL, 'UI labels without an English (fallback) translation: ' || bad;
  RAISE NOTICE 'PASS t01 lookups have the standard shape and every label has the fallback language';

  -- rule group 4: audit columns and trigger on every business table; reference tables are the documented exception (D-01)
  SELECT string_agg(relname, ', ') INTO bad FROM t_table t WHERE NOT relispartition AND NOT is_business AND NOT is_lookup
    AND relname NOT IN ('language', 'ui_label', 'ui_translation', 'currency', 'country', 'state', 'city', 'skill', 'access_role_permission',
                        'application_status_transition', 'audit_event', 'system_error');
  ASSERT bad IS NULL, 'tables without audit columns that are not documented reference or log tables: ' || bad;
  SELECT string_agg(relname, ', ') INTO bad FROM t_table t WHERE is_business AND NOT relispartition AND (
       (SELECT count(*) FROM t_column c WHERE c.relname = t.relname AND c.attname IN ('created_at', 'created_by', 'updated_at', 'updated_by')) <> 4
    OR NOT EXISTS (SELECT 1 FROM pg_trigger g WHERE g.tgrelid = t.oid AND g.tgname = 'trg_' || t.relname || '_audit_columns'));
  ASSERT bad IS NULL, 'business tables missing audit columns or their trigger: ' || bad;
  RAISE NOTICE 'PASS t01 every business table has created_at/by, updated_at/by and the audit-columns trigger';

  SELECT string_agg(x, ', ') INTO bad FROM unnest(ARRAY['consent_record', 'application_status_history', 'payment_event', 'wallet_ledger_entry',
                                                       'invoice', 'profile_download', 'audit_event']) x
  WHERE NOT EXISTS (SELECT 1 FROM pg_trigger g WHERE g.tgrelid = x::regclass AND g.tgname = 'trg_' || x || '_append_only');
  ASSERT bad IS NULL, 'append-only tables without the protecting trigger: ' || bad;
  RAISE NOTICE 'PASS t01 history, ledger and audit tables are append-only';

  -- rule group 5: every nullable column says why (comment "NULL: ..."); audit and soft-delete columns are documented once
  SELECT string_agg(relname || '.' || attname, ', ') INTO bad FROM t_column
  WHERE NOT relispartition AND NOT attnotnull AND attname NOT IN ('created_by', 'updated_by', 'deleted_at') AND coalesce(comment, '') NOT LIKE '%NULL:%';
  ASSERT bad IS NULL, 'nullable columns without a justification: ' || bad;
  RAISE NOTICE 'PASS t01 every nullable column has a written justification';

  -- rule group 6: identifying and secret columns carry their class
  SELECT string_agg(relname || '.' || attname, ', ') INTO bad FROM t_column
  WHERE NOT relispartition AND attname IN ('email', 'phone_e164', 'full_name', 'password_hash', 'token_hash', 'identifier_hmac', 'ip_address', 'gateway_order_ref')
    AND coalesce(comment, '') !~ '^(Personal|Sensitive)\.';
  ASSERT bad IS NULL, 'personal or sensitive columns without their class: ' || bad;
  RAISE NOTICE 'PASS t01 personal and sensitive columns are classified';

  -- rule group 8: partitions and analytical objects follow the naming pattern
  SELECT string_agg(relname, ', ') INTO bad FROM t_table WHERE relispartition AND relname !~ '^[a-z_]+_p([0-9]{6}|default)$';
  ASSERT bad IS NULL, 'partitions not named <table>_pYYYYMM: ' || bad;
  SELECT string_agg(matviewname, ', ') INTO bad FROM pg_matviews WHERE schemaname = 'public' AND matviewname !~ '^agg_';
  ASSERT bad IS NULL, 'materialized views without the agg_ prefix: ' || bad;
  RAISE NOTICE 'PASS t01 partitions and analytical objects follow the naming pattern';

  -- security baseline: row-level security on every business table (plan is the public catalogue)
  SELECT string_agg(t.relname, ', ') INTO bad FROM t_table t JOIN pg_class c ON c.oid = t.oid
  WHERE t.is_business AND NOT t.relispartition AND NOT c.relrowsecurity AND t.relname NOT IN ('plan', 'user_credential');
  ASSERT bad IS NULL, 'business tables without row-level security: ' || bad;
  ASSERT NOT has_table_privilege('v2_app', 'user_credential', 'SELECT'), 'v2_app must not read credentials';
  RAISE NOTICE 'PASS t01 row-level security is on for every business table; credentials are unreachable';
END $$;
