# Phase 2 — Schema scorecards (D2), version 1, frozen

The quad model of the *Agentic Roadmap* (p.3): every step has four deliverables. **D1** is the schema ([schemas.md](schemas.md)), **D2** is this scorecard that judges it, **D3** is the output and **D4** is the output scorecard ([output-scorecards.md](output-scorecards.md)). This scorecard was frozen before the schemas were scored, so the target did not move. Gate 1 of each step is "D1 passes D2"; only then was the output generated.

## Model

Built from *Control the Output*: the Define stage's exit test (every parameter has a definition, a type and a reason), the measurable results table (p.18) and the depth rules (p.5). C8 follows the roadmap's lesson that author understanding can only be proven by an interview.

| # | Dimension | How it is measured | Weight | Critical | If low, go back to |
|---|---|---|---|---|---|
| C1 | Step conformance | items of the lifecycle step (PRODUCE, DO, DONE WHEN, GO DEEPER) the schema asks for ÷ items | 20 | **yes** | Discover |
| C2 | Definition coverage | parameters with definition, type and reason ÷ all parameters | 20 | **yes** | Define |
| C3 | Closed lists | enumerated parameters with their allowed values listed ÷ enumerated parameters | 10 | | Define |
| C4 | Depth and atomicity | at least 2 levels; no parent above ~15 children; every leaf atomic | 10 | | Define |
| C5 | Source traceability | nodes with a source ÷ all nodes | 10 | | Discover |
| C6 | Decision log | kept, dropped and added decisions, each with a reason | 10 | | Define |
| C7 | Fitness for the next step | what the next step needs that the schema asks for ÷ what it needs | 10 | | Discover |
| C8 | Author understanding | sample questions on nodes answered correctly by the author ÷ asked (**human-only**) | 10 | **yes** | Discover |
| | **Total** | | **100** | | |

**Anchors:** 5 = 98%+, 4 = 90–97%, 3 = 75–89%, 2 = 50–74%, 1 = 1–49%, 0 = absent. **Score** = Σ weight × score ÷ 5. **Decision:** accept (green) at ≥ 90 with every critical dimension ≥ 4 and the human-only evidence supplied; refine (amber) at 75–89, or when a critical dimension is below 4, or while human-only evidence is missing; rework (red) below 75.

**Scoring status, stated plainly:** these are **author self-scores**. The roadmap's own lesson applies: "a review run by the session that wrote the schema is not independent". The independent 3 + 1 evaluator run and the peer score are not done. C8 needs a mentor interview, so it is shown as provisional 4 and no schema can be green yet.

## Measurements (taken from schemas.md)

| Schema | L1 | L2 | Def + type + reason | Source | Enums with values | Largest parent |
|---|---|---|---|---|---|---|
| S-06 | 6 | 16 | 16/16 | 22/22 | 4/4 | 8 |
| S-07 | 4 | 11 | 11/11 | 15/15 | 3/3 | 9 |
| S-08 | 7 | 14 | 14/14 | 21/21 | 3/3 | 6 |
| S-09 | 7 | 12 | 12/12 | 19/19 | 4/4 | 8 |
| S-10 | 5 | 10 | 10/10 | 15/15 | 2/2 | 10 |
| S-11 | 5 | 8 | 8/8 | 13/13 | 2/2 | 6 |
| S-12 | 7 | 8 | 8/8 | 15/15 | 5/5 | 6 |

## Scores

| Dim | W | S-06 | S-07 | S-08 | S-09 | S-10 | S-11 | S-12 |
|---|---|---|---|---|---|---|---|---|
| C1 * | 20 | 5 | 5 | 5 | 5 | 5 | 4 | 5 |
| C2 * | 20 | 5 | 5 | 5 | 5 | 5 | 5 | 5 |
| C3 | 10 | 5 | 5 | 5 | 5 | 5 | 5 | 5 |
| C4 | 10 | 5 | 4 | 5 | 5 | 4 | 5 | 5 |
| C5 | 10 | 5 | 5 | 5 | 5 | 5 | 5 | 5 |
| C6 | 10 | 4 | 4 | 4 | 4 | 4 | 4 | 4 |
| C7 | 10 | 5 | 5 | 5 | 5 | 5 | 5 | 5 |
| C8 * | 10 | 4 (prov.) | 4 (prov.) | 4 (prov.) | 4 (prov.) | 4 (prov.) | 4 (prov.) | 4 (prov.) |
| **Score** | | **96** | **94** | **96** | **96** | **94** | **92** | **96** |
| **Gate 1** | | amber | amber | amber | amber | amber | amber | amber |

Every schema clears the score threshold. Each one stays **amber** only because C8 is human-only evidence that has not been supplied (and no independent evaluation has run).

**Evidence per score below 5:**
- **C1, S-11 = 4:** the step's DO lists not-null and allowed values. The schema delegates them to S-10 (null column) and S-09 (enumeration references) instead of listing them again. That is a deliberate choice, but a reviewer may count it as missing.
- **C4, S-07 and S-10 = 4:** `mandatory` and `null` are composite leaves (a yes or no flag plus a reason). They are atomic in meaning but not in type.
- **C6, all = 4:** every decision log has kept and dropped items with reasons, but none records the alternatives that were considered and rejected.

**Path to green (Gate 1):** the C8 author interview with a mentor; then an independent 3 + 1 evaluator run, so these numbers become calibration evidence rather than self-assessment.
