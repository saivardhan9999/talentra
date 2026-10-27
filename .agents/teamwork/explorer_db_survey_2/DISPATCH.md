## 2026-10-27T07:07:26Z
From: f78290bf-cb2e-40f3-879e-f4c6e5535a5a (parent)
Mission:
You are the Database & Test Explorer for Phase 3.
Your working directory is: C:\Users\gsjit\OneDrive\Documents\talentra\.agents\teamwork\explorer_db_survey_2
Target project directory: C:\Users\gsjit\OneDrive\Documents\talentra\v2
You MUST read the original request file: C:\Users\gsjit\OneDrive\Documents\talentra\.agents\teamwork\ORIGINAL_REQUEST.md before doing anything else.

Your mission:
Investigate the database architecture, schema migrations, and tests in:
- C:\Users\gsjit\OneDrive\Documents\talentra\v2\db\migrations\ (all V001..V013 migration files)
- C:\Users\gsjit\OneDrive\Documents\talentra\v2\db\tests\ (t01_standards.sql through t06_phase3_prove.sql, and any test runner scripts)
- C:\Users\gsjit\OneDrive\Documents\talentra\v2\db\seed\ (any existing seed or sample data scripts)

Specifically extract and document:
1. The exact inventory of all tables (e.g. 33 tables across schemas/domains), columns, data types, constraints, foreign keys, triggers, and enums introduced across V001..V013.
2. The exact requirements of t06_phase3_prove.sql:
   - What are the 16 data quality invariants?
   - What are the 6 planted findings F-01..F-06?
   - What are the 16 invalid rows BAD-01..BAD-16 and how are they validated/rejected?
   - What are the 14 Phase 2 findings FND-01..FND-14 that must be verified closed?
   - What are the golden query answers GQ-01..GQ-10?
3. How tests are run in this environment (test runner commands, python test runner, psql / sqlite / postgres connection, etc.).
4. The exact requirements for `db/seed/seed_prove_sample.sql` (determinism with setseed, execution time, profile counts, coverage of all states and edge cases).

Write your comprehensive findings to:
C:\Users\gsjit\OneDrive\Documents\talentra\.agents\teamwork\explorer_db_survey_2\db_test_survey.md
and write a standard handoff.md in your working directory. Send a message to parent when complete.
