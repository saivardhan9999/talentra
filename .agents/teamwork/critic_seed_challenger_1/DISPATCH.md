## 2026-10-27T08:38:04Z
From: f78290bf-cb2e-40f3-879e-f4c6e5535a5a
Priority: MESSAGE_PRIORITY_HIGH

You are the Data Invariants & Seed Challenger for Phase 3.
Target project directory: C:\Users\gsjit\OneDrive\Documents\talentra\v2

You MUST read the original request file before doing anything else:
C:\Users\gsjit\OneDrive\Documents\talentra\.agents\teamwork\ORIGINAL_REQUEST.md

Your mission:
Empirically challenge and stress-test the Phase 3 sample dataset and data tests:
1. Challenge `v2/db/seed/seed_prove_sample.sql`:
   - Inspect script structure, PRNG determinism with `setseed(0.314159)`.
   - Verify coverage of all 30 candidate profiles, multilingual scripts (Devanagari, Tamil, mononyms), all 9 docket actors, all 4 account statuses, 3 verification statuses, 5 job statuses, 7 application statuses, and all 25 lookup tables (114 codes).
2. Challenge the 16 Data Quality Invariants (`R-01`..`R-16`) in `v2/db/tests/t05_data_quality.sql` and `phase3/15-test-suite-v1-data.md`:
   - Re-verify whether every invariant holds mathematically on the sample dataset with 0 violations.
3. Challenge the 6 Planted Findings (`F-01`..`F-06`):
   - Trace each planted finding to exact records in `seed_prove_sample.sql`.
   - Verify that detection queries in `t05_data_quality.sql` will detect each anomaly with count > 0.
4. Challenge the 16 Deliberate Invalid Rows (`BAD-01`..`BAD-16`):
   - Verify each bad row against PostgreSQL DDL constraints, triggers, composite FKs, or exclusion constraints.
   - Confirm that the database engine rejects each one.

Deliver your clear verdict: **APPROVE** or **CHALLENGE_FAILED** with detailed evidence.
Send a message with your complete report to the parent orchestrator.
