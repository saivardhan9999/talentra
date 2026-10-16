-- Generates a data dictionary (markdown) from the live catalog (class/nullability from column comments).
-- Optional: -v tables='^(a|b)$' limits it to tables matching the regex (default: all tables).
\if :{?tables}
\else
\set tables '.*'
\endif
\pset format unaligned
\pset tuples_only on
WITH cols AS (
  SELECT c.relname AS tbl, a.attnum, a.attname AS col,
         format_type(a.atttypid, a.atttypmod) AS typ,
         CASE WHEN a.attnotnull THEN 'NOT NULL' ELSE 'NULL' END AS nul,
         coalesce(substring(col_description(c.oid, a.attnum) from 'class=([A-Za-z]+)'),
                  CASE WHEN a.attname IN ('code','sort_order','is_active','name') THEN 'Public' ELSE 'Internal' END) AS cls,
         coalesce(regexp_replace(col_description(c.oid, a.attnum), '^class=[A-Za-z]+;? ?', ''), '') AS note,
         (SELECT string_agg(rc.relname, ',') FROM pg_constraint k JOIN pg_class rc ON rc.oid = k.confrelid
           WHERE k.conrelid = c.oid AND k.contype = 'f' AND a.attnum = ANY (k.conkey)) AS fk
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
  WHERE n.nspname = 'public' AND c.relkind IN ('r','p') AND NOT c.relispartition AND c.relname ~ :'tables'
)
SELECT string_agg(line, E'\n' ORDER BY tbl, ord) FROM (
  SELECT tbl, -1 AS ord, E'\n### ' || tbl || coalesce(E'\n' || obj_description((tbl)::regclass, 'pg_class'), '')
         || E'\n\n| Column | Type | Null | Class | FK → | Note |\n|---|---|---|---|---|---|' AS line
  FROM cols GROUP BY tbl
  UNION ALL
  SELECT tbl, attnum, format('| %s | %s | %s | %s | %s | %s |', col, typ, nul, cls, coalesce(fk, ''), replace(note, '|', '/'))
  FROM cols
) x;
