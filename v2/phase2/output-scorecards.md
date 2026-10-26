# Phase 2 — Output scorecards (D4), version 1, frozen

Each output (D3) scored against its frozen schema (D1). The model is the same one used in [Phase 1](../stage1/scorecards.md): the 8 core dimensions of *Control the Output* (pp. 12–14) plus one dimension specific to each step, re-weighted to 100. Frozen after Gate 1 and before any output was generated, as the roadmap requires (p.4).

## Model

| # | Dimension | How it is measured | Weight | Critical | If low, go back to |
|---|---|---|---|---|---|
| D1 | Structure conformance | output sections and fields matching the schema ÷ all | 15 | **yes** | Generate |
| D2 | Completeness | fields with a value or an explicit UNKNOWN ÷ all fields | 15 | | Generate |
| D3 | Definition clarity | schema parameters with definition, type and reason ÷ all | 10 | | Define |
| D4 | Accuracy and traceability | items traced to the model, docket or Phase 1, or marked as assumptions ÷ items | 20 | **yes** | Generate |
| D5 | Consistency across runs | values that agree across independent runs ÷ values compared | 5 | | Analyse |
| D6 | Structure and depth | levels justified; leaves atomic | 5 | | Define |
| D7 | Fitness for the next step | inputs the next step needs that this output provides ÷ needed | 10 | | Discover |
| D8 | Author understanding | sample questions answered correctly by the author ÷ asked (**human-only**) | 10 | **yes** | Discover |
| D9 | Step-specific (below) | | 10 | | Define |
| | **Total** | | **100** | | |

Anchors, score formula and decision rule as in the [schema scorecards](schema-scorecards.md#model).

**Scoring status, stated plainly:**
- These are **author self-scores**. No independent evaluator run or peer score has been done.
- **D8** is provisional 4 and needs a mentor interview.
- **D5 = 1 everywhere:** each output was authored in one run. The six generated outputs are deterministic, so rerunning the builder reproduces them exactly. But no second, independent author or model has produced them for comparison, and that comparison is what D5 measures.

## Scores

| Dim | W | 06 Entities | 07 Attributes | 08 States | 09 ER v0 | 10 Dictionary | 11 Rules | 12 Classification |
|---|---|---|---|---|---|---|---|---|
| D1 * | 15 | 5 | 5 | 5 | 5 | 5 | 5 | 5 |
| D2 | 15 | 5 | 5 | 4 | 5 | 5 | 5 | 5 |
| D3 | 10 | 5 | 5 | 5 | 5 | 5 | 5 | 5 |
| D4 * | 20 | 4 | 4 | 4 | 5 | 4 | 5 | 4 |
| D5 | 5 | 1 | 1 | 1 | 1 | 1 | 1 | 1 |
| D6 | 5 | 4 | 4 | 4 | 4 | 4 | 4 | 4 |
| D7 | 10 | 5 | 5 | 5 | 5 | 5 | 5 | 5 |
| D8 * | 10 | 4 (prov.) | 4 (prov.) | 4 (prov.) | 4 (prov.) | 4 (prov.) | 4 (prov.) | 4 (prov.) |
| D9 | 10 | 5 | 5 | 5 | 5 | 5 | 5 | 5 |
| **Score** | | **89** | **89** | **86** | **93** | **89** | **93** | **89** |
| **Gate 2** | | amber | amber | amber | amber | amber | amber | amber |

## Evidence per step

**06 Entity catalogue** ([output](06-entity-catalogue.md)). D9 = *workflow coverage*: 49 of 49 workflow and platform steps touch at least one named entity; 0 entities untouched.
- **D1:** all six schema sections are present.
- **D2:** 51 entities with every field filled; 16 deferred.
- **D4 = 4:** each entity traces to its tables and to Phase 1 steps. The definitions, owners and kinds are authored from the docket and the model but have not been peer-checked.
- **D7:** step 07 lists attributes under these entity IDs.

**07 Attribute lists** ([output](07-attribute-lists.md)). D9 = *typed examples*: 334 of 334 attributes have a logical type and an example value.
- **D2:** 0 missing; every optional attribute states why.
- **D4 = 4:** type, length and the mandatory flag come from the model mechanically. Business names, examples and units are curated, and the examples are illustrative.
- **D7:** 15 derived or snapshot attributes are flagged for the rules step.

**08 State machines** ([output](08-state-machines.md)). D9 = *negative-test coverage*: every illegal transition listed has a test (TC-08-001 to 048).
- **D2 = 4:** the derived-state machines (device, membership, block) are condensed into one table without separate guard and side-effect columns.
- **D4 = 4:** every transition cites the trigger, function or check that enforces it. The six design proposals are marked SA-01 to SA-06.
- **D7:** the 48 tests feed test suite v1 (Phase 3, step 15).
- **Findings:** FND-01 to FND-08.

**09 Logical ER model v0** ([output](09-logical-er-model-v0.md)). D9 = *cardinality in both directions*: 80 of 80 relationships.
- **D4 = 5:** every relationship is read from a foreign key of the model, so it cannot disagree with it.
- **D7:** junctions, normalisation decisions and the history strategy are stated for the dictionary and for Phase 3 volumetrics.

**10 Data dictionary v1** ([output](10-data-dictionary-v1.md)). D9 = *newcomer test*: the worked query uses only names and joins from the dictionary; 334 of 334 columns have a definition and an example.
- **D4 = 4:** types and constraints are mechanical; definitions and business names are curated.
- **D7:** the rules step reads its constraint names.

**11 Data rules catalogue** ([output](11-data-rules-catalogue.md)). D9 = *enforcement stated*: 208 of 208 rules name their enforcement point. The split is database 185, application 6, pipeline 11, gap 6, and each gap is a finding.
- **D4 = 5:** the 128 single-table constraints are quoted exactly as declared. Each of the 67 business rules names its mechanism.

**12 Classification register** ([output](12-data-classification-register.md)). D9 = *privacy completeness*: 78 of 78 personal or sensitive columns have a masking rule and a retention period.
- **D4 = 4:** the classes follow a written rule. Masking choices and lawful bases are design judgements awaiting review.
- **D7:** the reclassification list (52 columns, FND-12) and the test-data rule feed sample-data generation (Phase 3, step 14).

## Path to green (Gate 2), in priority order

1. **Author interview (D8)** with a mentor, for every step: this is human-only and nothing turns green without it.
2. **A second, independent run (D5):** another person or model fills S-06, S-08 and S-12 from the same sources, and the differences are explained. Moving D5 from 1 to 3 takes 06, 07, 10 and 12 to 91 (accept).
3. **Step 08 (D2):** add guard and side-effect columns to the device, membership and block machines. With item 2, this takes 08 to 91.
4. **Peer review** of curated definitions (07, 10) and masking choices (12), which would justify D4 = 5.
