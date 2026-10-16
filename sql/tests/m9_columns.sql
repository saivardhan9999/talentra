-- Milestone 9 (B30-B32): Phase 2 columns carry a type, standard domain, justified nullability and an
-- explicit sensitive-data class. The generic column rules (naming, money, timestamps, null
-- justification, audit columns) run schema-wide in m4; this adds the domain and class rules.
\set ON_ERROR_STOP on
SET t.phase = '2';
\ir check_columns.sql
