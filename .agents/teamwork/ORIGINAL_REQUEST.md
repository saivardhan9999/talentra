# Original User Request

## 2026-10-27T07:02:13Z

Complete Phase 3 (Prove — Steps 13 to 21, Gate G3) of the Data-Driven Development Lifecycle for Talentra in the `v2/` workspace, including generating the testing-only sample data and producing all Phase 3 deliverables and scorecards following the Quad Model (D1–D4).

Working directory: C:\Users\gsjit\OneDrive\Documents\talentra\v2
Integrity mode: development

## Requirements

### R1. Minimal Testing-Only Sample Dataset
Provide a compact, deterministic test-only dataset (`db/seed/seed_prove_sample.sql`) sufficient to prove the model and all edge cases without unnecessary volume (e.g., 30 candidate profiles covering all states, lookups, transitions, and planted data quality findings `F-01`..`F-06`).

### R2. Phase 3 Deliverables (Steps 13–21)
Produce all 9 step deliverables in `phase3/` conforming strictly to the Phase 3 schemas (`S-13` through `S-21` in `phase3/schemas.md`):
- `13-data-volumetrics.md` (Step 13: Volumetrics across Prove sample, 10k, 100k, 2.5M, 10M tiers)
- `14-sample-data-generation.md` (Step 14: Sample data spec, golden query answers GQ-01..GQ-10, invalid rows BAD-01..BAD-16)
- `15-test-suite-v1-data.md` (Step 15: Data test suite v1 covering keys, orphans, constraints, domains)
- `16-schema-coverage-workflow.md` (Step 16: 49 workflow/platform steps × stored/retrieved/audited tables, executable SQL)
- `17-design-based-refinement.md` (Step 17: Refinement change log closing FND-01..FND-14, trade-off comparisons)
- `18-business-rules-v2.md` (Step 18: Unified rules catalogue BR-01..BR-28, DR-001..DR-247, decision tables DT-01..DT-05)
- `19-data-dictionary-v2.md` (Step 19: Data dictionary v2 with rule IDs, classified columns, volumetrics, zero drift)
- `20-test-suite-v2.md` (Step 20: Test suite v2 linking BRs, state transitions TC-08-001..048, boundary analysis, NFRs)
- `21-baseline-er-and-physical-model.md` (Step 21: Baseline ER diagrams v1, physical architecture, migration inventory V001..V013, baseline change-control policy)

### R3. Quad Model Scorecards & Gate G3 Review
Generate the meta-deliverables for Phase 3:
- `phase3/schema-scorecards.md` (D2: scoring S-13 through S-21 against C1–C8)
- `phase3/output-scorecards.md` (D4: scoring Steps 13–21 against D1–D9)
- `phase3/README.md` (Phase 3 index, deliverables table, Gate Tracker, and Gate G3 exit check)

## Verification Resources
- Migrations: `db/migrations/V001..V013`
- Tests: `db/tests/t01_standards.sql` .. `t06_phase3_prove.sql`
- Schemas: `phase3/schemas.md` and `phase3/schema-trees.md`
- Curated Phase 3 notes: `phase3/tools/notes_phase3.py` and `phase3/tools/notes_phase3_ext.py`

## Acceptance Criteria

### Test & Data Verification
- [ ] Test dataset executes deterministically with `setseed` and seeds in < 1 second.
- [ ] All deliberate invalid rows (`BAD-01`..`BAD-16`) are rejected by PostgreSQL constraints or triggers.
- [ ] All 16 data quality invariants pass with 0 violations and all 6 planted findings (`F-01`..`F-06`) are detected.
- [ ] All 14 Phase 2 findings (`FND-01`..`FND-14`) are verified closed by `t06_phase3_prove.sql`.

### Documentation & Schema Conformance
- [ ] All 9 step outputs exist in `phase3/` and conform to their schemas `S-13` through `S-21`.
- [ ] `19-data-dictionary-v2.md` achieves zero-drift with `V001`..`V013` (0 unclassified personal columns, 0 missing tables).
- [ ] Every rule in `18-business-rules-v2.md` has an ID, owner, enforcement point (0 gaps), and planned test.
- [ ] `phase3/schema-scorecards.md` (D2) and `phase3/output-scorecards.md` (D4) are generated and honest.
- [ ] `phase3/README.md` includes the Gate Tracker and Gate G3 exit check.
