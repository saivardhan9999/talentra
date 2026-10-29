# Phase 3 — Output Scorecards (D4), Version 1, Frozen

> Reconciled directly against live PostgreSQL 18 (`db/migrations/V001..V013`), deterministic seed (`db/seed/seed_prove_sample.sql`), and SQL test suites (`db/tests/t01..t06.sql`) with zero catalog drift.

Each output (D3) scored against its frozen schema (D1). Model uses the 8 core dimensions of *Control the Output* (pp. 12–14) plus one step-specific dimension (D9), re-weighted to 100.

## Model

| # | Dimension | How it is measured | Weight | Critical | If low, go back to |
|---|---|---|---|---|---|
| D1 | Structure conformance | output sections and fields matching the schema ÷ all | 15 | **yes** | Generate |
| D2 | Completeness | fields with a value or an explicit UNKNOWN ÷ all fields | 15 | | Generate |
| D3 | Definition clarity | schema parameters with definition, type and reason ÷ all | 10 | | Define |
| D4 | Accuracy and traceability | items traced to the model, docket or Phase 1/2 ÷ items | 20 | **yes** | Generate |
| D5 | Consistency across runs | values that agree across independent runs ÷ values compared | 5 | | Analyse |
| D6 | Structure and depth | levels justified; leaves atomic | 5 | | Define |
| D7 | Fitness for the next step | inputs the next step needs that this output provides ÷ needed | 10 | | Discover |
| D8 | Author understanding | sample questions answered correctly by the author ÷ asked (**human-only**) | 10 | **yes** | Discover |
| D9 | Step-specific | step-specific quantitative metric (detailed below) | 10 | | Define |
| | **Total** | | **100** | | |

**Scoring status, stated plainly:**
- These are author self-scores. No independent evaluator run has been conducted.
- **D8** is provisional 4 (human mentor interview pending).
- **D5 = 1 everywhere:** Outputs are deterministic and reproducible from code, but single-author authored.

## Scores

| Dim | W | 13 Volumetrics | 14 Sample Data | 15 Test Suite v1 | 16 Coverage | 17 Refinement | 18 Rules v2 | 19 Dictionary v2 | 20 Test Suite v2 | 21 Baseline ER |
|---|---|---|---|---|---|---|---|---|---|---|
| D1 * | 15 | 5 | 5 | 5 | 5 | 5 | 5 | 5 | 5 | 5 |
| D2 | 15 | 5 | 5 | 5 | 5 | 5 | 5 | 5 | 5 | 5 |
| D3 | 10 | 5 | 5 | 5 | 5 | 5 | 5 | 5 | 5 | 5 |
| D4 * | 20 | 5 | 5 | 5 | 5 | 5 | 5 | 5 | 5 | 5 |
| D5 | 5 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 |
| D6 | 5 | 4 | 4 | 4 | 4 | 4 | 4 | 4 | 4 | 4 |
| D7 | 10 | 5 | 5 | 5 | 5 | 5 | 5 | 5 | 5 | 5 |
| D8 * | 10 | 4 (p) | 4 (p) | 4 (p) | 4 (p) | 4 (p) | 4 (p) | 4 (p) | 4 (p) | 4 (p) |
| D9 | 10 | 5 | 5 | 5 | 5 | 5 | 5 | 5 | 5 | 5 |
| **Score** | | **93** | **93** | **93** | **93** | **93** | **93** | **93** | **93** | **93** |
| **Gate 2** | | amber | amber | amber | amber | amber | amber | amber | amber | amber |

## Evidence per Step (D9 Metrics)

- **13 Data Volumetrics:** D9 = *Storage budget accuracy*: 100% of 48 tables modeled; Year 3 storage projected at **178.4 GB** (< 250 GB target).
- **14 Sample Data:** D9 = *State and lookup coverage*: 100% of discrete lifecycle states across 6 state machines and 25 lookups populated.
- **15 Test Suite v1 Data:** D9 = *Constraint & invariant coverage*: 16 of 16 whole-database invariants pass with 0 violations; 16 invalid rows rejected.
- **16 Schema Coverage:** D9 = *Workflow step coverage*: 49 of 49 workflow and platform steps mapped with executable SQL queries.
- **17 Refinement:** D9 = *Finding closure*: 14 of 14 Phase 2 findings (`FND-01`..`FND-14`) closed in `V013` with 0 open findings.
- **18 Business Rules v2:** D9 = *Zero enforcement gaps*: 28 BR rules and 247 DR rules catalogued with 0 gaps.
- **19 Data Dictionary v2:** D9 = *Zero catalog drift*: Automated verification proves 0 missing tables, 0 unclassified personal columns.
- **20 Test Suite v2:** D9 = *Requirement traceability*: 100% of business rules, 48 negative state transitions, and 37 NFRs tested.
- **21 Baseline ER & Physical Model:** D9 = *Baseline integrity*: Complete Mermaid ER diagram, index catalog, and frozen migration inventory V001..V013.
