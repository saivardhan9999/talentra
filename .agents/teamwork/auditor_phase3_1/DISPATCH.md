## 2026-10-27T08:38:27Z
You are the Forensic Integrity Auditor for Phase 3 (Prove — Steps 13 to 21, Gate G3).
Target project directory: C:\Users\gsjit\OneDrive\Documents\talentra\v2

You MUST read the original request file before doing anything else:
C:\Users\gsjit\OneDrive\Documents\talentra\.agents\teamwork\ORIGINAL_REQUEST.md

Your mission:
Conduct an independent, rigorous forensic integrity audit across all Phase 3 deliverables, code, migrations, tests, and seed scripts.
Verify that all work products represent authentic, genuine implementations:
1. Static Analysis & Authenticity:
   - Check `v2/phase3/tools/build_phase3.py` and generated markdown files (`13-data-volumetrics.md` through `21-baseline-er-and-physical-model.md`, `schema-scorecards.md`, `output-scorecards.md`, `README.md`).
   - Verify that there are NO dummy or facade implementations, NO hardcoded fake test results, and NO circumventions of the intended tasks.
2. DDL & Finding Closure Authenticity:
   - Verify that `v2/db/migrations/V013__phase3_refinements.sql` is a genuine forward-only migration.
   - Verify that the 14 Phase 2 findings (`FND-01`..`FND-14`) are genuinely resolved in SQL DDL with triggers, functions, tables, and column comments.
   - Verify that `t06_phase3_prove.sql` genuinely asserts each finding closure.
3. Test & Invariant Authenticity:
   - Verify that `v2/db/seed/seed_prove_sample.sql` is a genuine SQL seeding script that deterministically populates the database and plants findings F-01..F-06.
   - Verify that invariants R-01..R-16 and invalid rows BAD-01..BAD-16 are genuine technical checks.
4. Scorecard Integrity:
   - Verify that Quad Model scorecards (`schema-scorecards.md`, `output-scorecards.md`) and Gate G3 exit checks in `README.md` are honest and rigorously documented.

HARD VETO CRITERIA:
If you find ANY evidence of cheating, dummy implementations, hardcoded fake test outputs, or falsified documentation, you MUST return:
**INTEGRITY VIOLATION** with full evidence.
If all implementations, migrations, tests, and deliverables are authentic, genuine, and verified, return:
**CLEAN**.

Send a message with your complete forensic audit report to the parent orchestrator.
