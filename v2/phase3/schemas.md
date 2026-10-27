# Phase 3 — Output schemas (D1), version 1

One schema per Phase 3 step of the *Data-Driven Development Lifecycle* (steps 13–21, Prove). Same format as [Phase 1](../stage1/output-schemas.md) and [Phase 2](../phase2/schemas.md): each row is a node of the tree; **Path** gives its level (1 = L1 section, 1.1 = L2 parameter), **Allowed values** is L3, **Type** is L4. A/C = atomic or composite; M/O = mandatory or optional. Sources: *LC* = lifecycle playbook pages 9–10 for the step; *docket* = hackathon docket; *P1* = Phase 1 deliverables; *P2* = Phase 2 deliverables; *model* = v2 migrations (`V001`–`V013`). Each schema was scored against its schema scorecard (D2) in [schema-scorecards.md](schema-scorecards.md) before the output was generated.

## S-13 — Data Volumetrics and Distribution Profile

| Path | Parameter | Definition | Reason | Type (L4) | A/C | Allowed values (L3) | M/O | Source |
|---|---|---|---|---|---|---|---|---|
| 1 | **Scale tiers** | the sizing horizons modeled across the lifecycle | anchors test sample, laptop dev, launch, Year 1 and Year 3 | section | C | | M | LC p.9, docket §6 |
| 1.1 | tier_code | identifier of the scale tier | columns in the volumetric table cite it | enum | A | prove_sample · dev_10k · launch_100k · year1_2_5m · year3_10m | M | docket §6, P1 |
| 1.2 | profile_anchor | candidate profiles in this tier | the docket's 10 : 1 : 50 ratio scales from profiles | int ≥ 1 | A | 30 · 10000 · 100000 · 2500000 · 10000000 | M | docket §6 |
| 2 | **Table volumetric sheet** | row counts, growth and storage per table across tiers | the playbook's PRODUCE for step 13 | section | C | | M | LC p.9 |
| 2.1 | table | technical table name | links to S-10 and S-19 | ref → table | A | | M | model |
| 2.2 | entity_id | entity realised by the table | traceability to Phase 2 | ref → S-06 1.1 | A | | M | P2 step 06 |
| 2.3 | rows_prove_sample | exact rows in the Phase 3 testing-only sample | verifies Step 14 sample stays minimal | int ≥ 0 | A | | M | Step 14 seed |
| 2.4 | rows_launch | projected rows at launch (100k profiles) | the playbook's DO: rows at launch | int ≥ 0 | A | | M | LC p.9 |
| 2.5 | rows_year1 | projected rows at 1 year (2.5M profiles) | the playbook's DO: rows at 1 year | int ≥ 0 | A | | M | LC p.9 |
| 2.6 | rows_year3 | projected rows at 3 years (10M profiles) | the playbook's DO: rows at 3 years | int ≥ 0 | A | | M | LC p.9 |
| 2.7 | growth_pattern | how rows accumulate over time | separates static reference from append-only logs | enum | A | static · linear with users · linear with orgs · event-driven append · bounded by retention | M | LC p.9 |
| 2.8 | avg_row_bytes | estimated width of one row including tuple header | needed to convert row counts to GB | int ≥ 24 | A | | M | model |
| 2.9 | year3_size_gb | table + index storage at Year 3 | checks NFR-SCAL-03 (~250 GB budget) | numeric ≥ 0 | A | | M | NFR-SCAL-03 |
| 3 | **Cardinality and distribution profile** | parent-to-child fan-out, skew and Zipf exponents | the playbook's DO: cardinality and skew | section | C | | M | LC p.9 |
| 3.1 | relationship | parent → child pair | links to S-09 relationship register | ref → S-09 2.1 | A | | M | P2 step 09 |
| 3.2 | min_median_p95_max | distribution of children per parent | average alone hides hot keys | text | A | | M | LC p.9 |
| 3.3 | skew_profile | power-law or concentration rule | drives realistic synthetic data and index choices | text | A | | M | docs/03 §6 |
| 4 | **Null-rate profile** | expected null rate of optional columns | the playbook's DO: null rates | section | C | | M | LC p.9 |
| 4.1 | column | table and nullable column | links to S-10 | ref → S-10 2.2 | A | | M | model |
| 4.2 | expected_null_pct | percentage of rows where the column is NULL | guides partial indexes (`WHERE col IS NOT NULL`) | pct 0–100 | A | | M | docs/03 §6 |
| 5 | **Seasonality, peak days and burst traffic** | time-of-day, day-of-week, seasonal and burst multipliers | the playbook's go deeper | section | C | | M | LC p.9 go deeper |
| 5.1 | workload | traffic stream or business event | maps to NFR-SCAL-02 throughput | enum | A | job_search · candidate_search · login · application_submit · job_alert_digest · webhook_burst · campus_drive | M | NFR-SCAL-02 |
| 5.2 | average_rps | sustained rate at Year 3 | baseline capacity | numeric ≥ 0 | A | | M | NFR-SCAL-02 |
| 5.3 | peak_burst_rps | peak rate during placement season or Monday 10:00 IST | sizes connection pools, locks and outbox workers | numeric ≥ 0 | A | | M | LC p.9 go deeper |
| 6 | **Exit test check** | verification that every table has realistic numbers | a step is not complete until its exit test is met | section | C | | M | LC done-when |

**Decision log:** *Kept* five scale tiers (`prove_sample`, `dev_10k`, `launch_100k`, `year1_2_5m`, `year3_10m`) so the testing-only sample, the laptop benchmark, and the 3-year production target sit in one table. *Dropped* per-column histogram buckets for uniform IDs, focusing section 3 and 4 on skewed foreign keys and nullable columns. *Rejected* a flat 10× annual growth factor across all tables, because reference tables stay static and `system_error` / `notification` are capped by retention jobs.

## S-14 — Sample Data Generation (Discovery)

| Path | Parameter | Definition | Reason | Type (L4) | A/C | Allowed values (L3) | M/O | Source |
|---|---|---|---|---|---|---|---|---|
| 1 | **Generator architecture** | how the testing-only sample (`seed_prove_sample.sql`) and scaled generator (`seed.sql`) work | the playbook's PRODUCE: seeded generator | section | C | | M | LC p.9 |
| 1.1 | script_path | SQL seed script path | executable entrypoint | text | A | `db/seed/seed_prove_sample.sql` · `db/seed/seed.sql` | M | repo |
| 1.2 | prng_seed | deterministic seed value | reproducible across runs (NFR-PERF-05) | numeric | A | `0.314159` · `0.42` | M | LC p.9 |
| 2 | **State and lookup coverage proof** | proof that every entity and lookup state is populated in the sample | the playbook's DO: cover every state and relationship | section | C | | M | LC p.9 |
| 2.1 | lookup_or_entity | table or state machine | links to S-08 and S-06 | ref → table | A | | M | P2 steps 06, 08 |
| 2.2 | states_covered | distinct states present in the sample vs total states | must be 100% of lifecycle states | text | A | | M | LC p.9 |
| 3 | **Golden dataset with pre-known answers** | named records and queries whose exact answers are known in advance | the playbook's go deeper: golden dataset | section | C | | M | LC p.9 go deeper |
| 3.1 | golden_id | identifier of the golden query | cited by workflow and test steps | id `GQ-[0-9]{2}` | A | | M | LC rule "give everything an ID" |
| 3.2 | question | business question asked of the sample | human-readable intent | text | A | | M | P1 workflows |
| 3.3 | expected_answer | exact pre-known result (count, amount, row set) | deterministic oracle for tests | text | A | | M | LC p.9 go deeper |
| 4 | **Planted data-quality findings** | realistic migration anomalies deliberately planted for detection | docket §6 and `t05_data_quality.sql` | section | C | | M | docket §6 |
| 4.1 | finding_code | identifier `F-01`..`F-06` | links to `t05` | id `F-0[1-6]` | A | | M | docs/03 §6 |
| 4.2 | planted_records | exact rows in the prove sample carrying the anomaly | makes detection verifiable on small data | text | A | | M | `seed_prove_sample.sql` |
| 5 | **Deliberate invalid rows (negative sample)** | bad records attempted against the schema and rejected | the playbook's DO and exit test | section | C | | M | LC done-when |
| 5.1 | bad_row_id | identifier of the invalid record attempt | traced to Step 15 test cases | id `BAD-[0-9]{2}` | A | | M | LC p.9 |
| 5.2 | target_table | table the bad row targets | links to S-10 | ref → table | A | | M | model |
| 5.3 | violation | what makes the row invalid | domain, FK, unique, check, or trigger rule | text | A | | M | P2 step 11 |
| 5.4 | rejected_by | exact constraint or trigger that rejects it | proves the database refuses it | text | A | | M | model |
| 6 | **Exit test check** | verification that valid sample loads and invalid rows are rejected | a step is not complete until its exit test is met | section | C | | M | LC done-when |

**Decision log:** *Kept* a dedicated small testing-only dataset (`seed_prove_sample.sql`, 30 profiles, ~420 business rows) alongside the parameterized `seed.sql`, directly fulfilling the user's requirement for a small, fast Prove dataset. *Dropped* external Python/Faker dependencies so the seed runs in pure SQL inside `psql`. *Rejected* inserting invalid rows by disabling triggers, keeping them instead as an executable negative-test block (`expect_error`) so the database itself proves rejection.

## S-15 — Test Suite v1 · Data

| Path | Parameter | Definition | Reason | Type (L4) | A/C | Allowed values (L3) | M/O | Source |
|---|---|---|---|---|---|---|---|---|
| 1 | **Test harness and execution model** | how data tests run and roll back cleanly | repeatable, zero side effects on seeded data | section | C | | M | `db/tests/_helpers.sql` |
| 2 | **Structural and catalogue test cases** | tests of naming, keys, FKs, indexes, domains, audit columns, RLS | proves docket §5 standards on the live catalog | section | C | | M | `t01_standards.sql` |
| 2.1 | test_id | unique test identifier | the playbook's PRODUCE | id `TC-15-[0-9]{3}` | A | | M | LC p.9 |
| 2.2 | rule_id | data rule(s) verified | links to S-11 (`DR-nnn`) | ref → S-11 1.1 | A | | M | P2 step 11 |
| 2.3 | category | aspect of data quality tested | the playbook's DO list | enum | A | naming & standards · primary & foreign keys · uniqueness · domain & format · range & boundary · cross-field check · append-only & audit · data quality invariant · planted anomaly detection | M | LC p.9 |
| 2.4 | polarity | whether the test asserts acceptance/invariance or rejection | the playbook's go deeper: positive + negative | enum | A | positive · negative · invariant · detection | M | LC p.9 go deeper |
| 2.5 | assertion | what is executed against PostgreSQL | concrete SQL check | text | A | | M | `db/tests/` |
| 2.6 | expected_result | exact pass condition or error pattern | deterministic oracle | text | A | | M | LC p.9 |
| 3 | **Constraint and domain positive/negative matrix** | paired positive and negative tests for domains and table constraints | the playbook's go deeper | section | C | | M | LC p.9 go deeper |
| 4 | **Seeded data-quality invariants (`R-01`..`R-16`)** | whole-database consistency checks on the loaded sample | proves 0 orphan or drifted rows | section | C | | M | `t05_data_quality.sql` |
| 5 | **Exit test check** | verification that every invalid record is rejected and every rule has a test | a step is not complete until its exit test is met | section | C | | M | LC done-when |

**Decision log:** *Kept* every test in pure SQL (`t01`, `t02`, `t05`, `t06`) using `pg_temp.check()` and `pg_temp.expect_error()`. *Dropped* application-layer mock tests, because Phase 3 Step 15 is strictly a data-layer test suite. *Rejected* manual visual inspection of query output; every test raises an exception on failure (`ON_ERROR_STOP=1`).

## S-16 — Schema Coverage against Business Workflow

| Path | Parameter | Definition | Reason | Type (L4) | A/C | Allowed values (L3) | M/O | Source |
|---|---|---|---|---|---|---|---|---|
| 1 | **Workflow × table coverage matrix** | every workflow step mapped to tables stored, retrieved and audited | the playbook's PRODUCE for step 16 | section | C | | M | LC p.9 |
| 1.1 | step_id | workflow step identifier from Phase 1 step 05 | links to S-05 and S-06 | ref → WF step | A | | M | P1 step 05 |
| 1.2 | actor | role or system executing the step | links to S-02 | ref → S-02 role | A | | M | P1 step 02 |
| 1.3 | tables_stored | tables inserted or updated (`C`, `U`, `D`) | the playbook's DO: stored | text list | C | | M | LC p.9 |
| 1.4 | tables_retrieved | tables read (`R`) to validate or render the step | the playbook's DO: retrieved | text list | C | | M | LC p.9 |
| 1.5 | audited_how | audit column trigger, `audit_event` action, or append-only history | the playbook's DO: audited | text | A | | M | LC p.9 |
| 1.6 | entry_point | SQL function, trigger, view or table policy used | proves how the step runs | text | A | | M | model |
| 2 | **Executable SQL queries per workflow** | actual SQL statements for every workflow run against the golden sample | the playbook's go deeper | section | C | | M | LC p.9 go deeper |
| 2.1 | workflow_id | workflow `WF-01`..`WF-10`, `WF-14`, `PLATFORM` | links to P1 step 05 | ref → WF | A | | M | P1 step 05 |
| 2.2 | sql_listing | runnable SQL query or transaction block | proves no missing join path or column | text | A | | M | LC p.9 go deeper |
| 2.3 | sample_result | result returned on `seed_prove_sample.sql` | connects to S-14 golden answers | text | A | | M | S-14 |
| 3 | **Gap list discovered during walkthrough** | workflow steps or exceptions that lacked a database entry point or guard before V013 | the playbook's PRODUCE: gap list | section | C | | M | LC p.9 |
| 3.1 | gap_id | finding or workflow gap identifier | feeds directly into Step 17 | ref → `FND-nn` | A | | M | P2 findings |
| 3.2 | resolution_in_step17 | how Step 17 (`V013`) closes the gap | closes the loop | text | A | | M | `V013` |
| 4 | **Exit test check** | verification that 100% of workflow steps are supported | a step is not complete until its exit test is met | section | C | | M | LC done-when |

**Decision log:** *Kept* all 49 workflow and platform steps from Phase 2 Step 06 and split their operations explicitly into *Stored*, *Retrieved*, and *Audited* as required by Step 16. *Dropped* deferred workflows (`WF-11`..`WF-13`), which were scoped out in Stage 1. *Rejected* pseudo-code queries; every workflow has real PostgreSQL SQL tested against the golden schema.

## S-17 — Design-Based Refinement

| Path | Parameter | Definition | Reason | Type (L4) | A/C | Allowed values (L3) | M/O | Source |
|---|---|---|---|---|---|---|---|---|
| 1 | **Refinement change log** | every model change made in `V013__phase3_refinements.sql` with its reason | the playbook's PRODUCE for step 17 | section | C | | M | LC p.9 |
| 1.1 | finding_id | Phase 2 finding or workflow gap closed | links to `findings.md` (`FND-01`..`FND-14`) | id `FND-[0-9]{2}` | A | | M | P2 findings |
| 1.2 | severity | severity of the finding | high blocks green, medium fixed in pass | enum | A | high · medium · low | M | P2 findings |
| 1.3 | objects_changed | table, trigger, function, policy or comment added/modified | exact DDL traceability | text | A | | M | `V013` |
| 1.4 | before_state | what the v2 model did before `V013` | shows the flaw clearly | text | A | | M | `V001`..`V012` |
| 1.5 | after_state | what the refined model does after `V013` | shows the fix | text | A | | M | `V013` |
| 1.6 | verification_test | test case in `t06_phase3_prove.sql` proving the fix | proves closure | ref → `TC-20-nnn` | A | | M | `t06` |
| 2 | **Design trade-off comparisons (hardest areas)** | side-by-side comparison of at least two designs for the hardest areas | the playbook's go deeper | section | C | | M | LC p.9 go deeper |
| 2.1 | area | architectural problem compared | e.g. RLS visibility + consent performance, wallet/seat concurrency, state transition enforcement | text | A | | M | model |
| 2.2 | option_a | first candidate design | concrete alternative | text | A | | M | review |
| 2.3 | option_b | second candidate design | concrete alternative | text | A | | M | review |
| 2.4 | chosen_and_why | which option won and the measured/structural reason | records the engineering trade-off | text | A | | M | ADR, benchmark |
| 3 | **Regression verification** | result of re-running Test Suite v1 + v2 after refinement | the playbook's DO: re-run test suite v1 | section | C | | M | LC p.9 |
| 4 | **Exit test check** | verification that all high/medium/low findings are closed (0 open gaps) | a step is not complete until its exit test is met | section | C | | M | LC done-when |

**Decision log:** *Kept* all refinements in a forward-only migration (`V013__phase3_refinements.sql`) rather than editing `V001`–`V012` in place, honouring `NFR-MNT-01` (checksummed immutable migrations). *Dropped* cosmetic renaming of existing constraints so existing tests `t01`–`t05` remain 100% compatible. *Rejected* deferring the 4 low-severity findings (`FND-06`, `FND-07`, `FND-08`, `FND-11`); fixing all 14 brings open findings to zero.

## S-18 — Business Rules and Data Constraints v2

| Path | Parameter | Definition | Reason | Type (L4) | A/C | Allowed values (L3) | M/O | Source |
|---|---|---|---|---|---|---|---|---|
| 1 | **Unified rules catalogue v2** | every business policy, calculation, limit, state rule and data constraint in one list | the playbook's PRODUCE for step 18 | section | C | | M | LC p.10 |
| 1.1 | rule_id | stable rule identifier (`BR-01`..`BR-28` and `DR-001`..`DR-245`) | links to S-11, S-19, S-20 | id `(BR\|DR)-[0-9]+` | A | | M | LC p.10 |
| 1.2 | category | kind of rule | the playbook's DO list | enum | A | policy & eligibility · calculation & pricing · limit & quota · approval & verification · state transition · privacy & consent · domain & format · single-table constraint · retention & lifecycle | M | LC p.10 |
| 1.3 | statement | unambiguous statement of the rule | single source of truth | text | A | | M | P1, P2, V013 |
| 1.4 | owner | business or technical owner of the rule | the playbook's exit test | text | A | | M | LC done-when |
| 1.5 | enforcement_point | where the rule is enforced after `V013` (0 gaps) | the playbook's exit test | enum | A | Database · Application · Pipeline | M | LC done-when |
| 1.6 | mechanism | exact function, trigger, constraint, policy or job | proves enforcement | text | A | | M | model |
| 1.7 | planned_test | test ID(s) in Suite v1 / Suite v2 | the playbook's exit test | ref → `TC-nn-nnn` | A | | M | S-15, S-20 |
| 2 | **Decision tables for complex rules** | multi-condition rules expressed as complete decision tables | the playbook's go deeper | section | C | | M | LC p.10 go deeper |
| 2.1 | decision_table_id | identifier `DT-01`..`DT-05` | referenced by rules and tests | id `DT-[0-9]{2}` | A | | M | LC p.10 go deeper |
| 2.2 | conditions_and_outcomes | input condition columns and resulting action/status | eliminates ambiguity in branching logic | text | A | | M | model |
| 3 | **Exit test check** | verification that every rule has ID, owner, enforcement point, and test (0 gaps) | a step is not complete until its exit test is met | section | C | | M | LC done-when |

**Decision log:** *Kept* both the conceptual `BR-nn` identifiers (expanded from `BR-01`..`BR-22` to `BR-01`..`BR-28` so every cross-table policy has a `BR-` ID) and the granular `DR-nnn` identifiers from Step 11. *Dropped* the `Gap` enforcement point value from `Allowed values (L3)` in v2 because `V013` closed all 6 rule gaps from Phase 2. *Rejected* prose-only descriptions for multi-variable rules (candidate visibility, notification suppression, login admission, profile download billing, payment webhook handling), expressing all five as formal decision tables (`DT-01`..`DT-05`).

## S-19 — Data Dictionary v2

| Path | Parameter | Definition | Reason | Type (L4) | A/C | Allowed values (L3) | M/O | Source |
|---|---|---|---|---|---|---|---|---|
| 1 | **Zero-drift verification header** | automated check that dictionary tables and columns match `V001`..`V013` 1:1 | the playbook's go deeper and exit test | section | C | | M | LC p.10 |
| 2 | **Table entry v2** | one section per table, regenerated from `V001`..`V013` | the playbook's PRODUCE for step 19 | section | C | | M | LC p.10 |
| 2.1 | table_volumetrics | prove sample, launch, Year 1 and Year 3 row counts for the table | the playbook's DO: add volumetrics | text | A | | M | S-13 |
| 2.2 | column | technical column name | links to DDL | id `[a-z][a-z0-9_]*` | A | | M | model |
| 2.3 | business_name | human-readable name | carried from v1 | text ≤ 60 | A | | M | S-10 |
| 2.4 | type | PostgreSQL type or domain | physical type | text | A | | M | model |
| 2.5 | null | mandatory or nullable with reason | rule group 5 | text | A | | M | model |
| 2.6 | constraints_and_rules | constraints plus governing `DR-` / `BR-` rule IDs | the playbook's DO: add rule IDs | text | A | | M | S-18 |
| 2.7 | definition | business meaning | carried from v1 | text | A | | M | S-10 |
| 2.8 | example | realistic value | carried from v1 | text | A | | M | S-10 |
| 2.9 | reviewed_class | sensitivity class after `V013` reclassification (0 drift with S-12) | the playbook's DO: add classification | enum | A | Public · Internal · Personal · Sensitive | M | S-12, `V013` |
| 2.10 | owner | source of truth | carried from v1 | text | A | | M | S-10 |
| 3 | **Lookup and analytical objects** | enumeration lookups (`ENT-51`), `job_status_transition`, and `agg_hiring_funnel_monthly` | complete coverage of all relations | section | C | | M | model |
| 4 | **Exit test check** | verification of 0 drift between schema and dictionary | a step is not complete until its exit test is met | section | C | | M | LC done-when |

**Decision log:** *Kept* generation directly from the parsed `V001`..`V013` SQL files in `build_phase3.py` so human copy-paste drift is impossible. *Dropped* the separate "tagged now vs should be" split from Step 12 because `V013` applied all 52 `COMMENT ON COLUMN` tags directly in the DDL. *Rejected* omitting rule IDs on unconstrained columns; foreign-key, domain, and table-level `DR-`/`BR-` IDs are linked directly in the column or table footer.

## S-20 — Test Suite v2 · Data, Business and NFR

| Path | Parameter | Definition | Reason | Type (L4) | A/C | Allowed values (L3) | M/O | Source |
|---|---|---|---|---|---|---|---|---|
| 1 | **Coverage summary** | count of tests covering data rules, business rules, state transitions and NFRs | proves 100% requirement & rule coverage | section | C | | M | LC p.10 |
| 2 | **Business rule test register** | tests verifying every business rule `BR-01`..`BR-28` | the playbook's DO: every business rule | section | C | | M | LC p.10 |
| 2.1 | test_id | unique test identifier | traceability | id `TC-20-[0-9]{3}` | A | | M | LC p.10 |
| 2.2 | target_id | `BR-nn`, `DR-nnn`, `TC-08-nnn`, or `NFR-xxx-nn` verified | the playbook's PRODUCE: link every test to a rule or NFR ID | ref → rule or NFR | A | | M | LC p.10 |
| 2.3 | test_file | SQL test file or benchmark runner executing the test | executable location | enum | A | `t01_standards.sql` · `t02_integrity.sql` · `t03_security.sql` · `t04_concurrency.sql` · `t05_data_quality.sql` · `t06_phase3_prove.sql` · `bench/bench.py` | M | repo |
| 2.4 | scenario | what is tested | human-readable test case | text | A | | M | LC p.10 |
| 2.5 | expected_outcome | pass assertion or expected error regex | verifiable oracle | text | A | | M | LC p.10 |
| 3 | **State transition test matrix (`TC-08-001`..`048` + allowed moves)** | positive tests for all allowed moves and negative tests for all 48 illegal moves from Step 08 | the playbook's DO: every state transition | section | C | | M | P2 step 08 |
| 4 | **Boundary value analysis register** | tests right on the exact limit (`N - 1`, `N`, `N + 1`) | the playbook's go deeper: boundary values | section | C | | M | LC p.10 go deeper |
| 4.1 | boundary_parameter | column, domain, seat limit, device limit, credit balance, or position count | what limit is stressed | text | A | | M | model |
| 4.2 | at_limit_test | test at exact limit `N` (must succeed) | proves limit is inclusive | text | A | | M | `t02`, `t04`, `t06` |
| 4.3 | over_limit_test | test at `N + 1` or `min - 1` (must fail) | proves limit is enforced | text | A | | M | `t02`, `t04`, `t06` |
| 5 | **NFR verification register** | tests and measurements for every NFR (`PERF`, `SCAL`, `REL`, `SEC`, `PRIV`, `INT`, `AUD`, `I18N`, `MNT`, `OBS`, `CMP`) | the playbook's DO: NFRs | section | C | | M | `docs/02` |
| 6 | **Exit test check** | verification that every rule, state transition and NFR has ≥ 1 test | a step is not complete until its exit test is met | section | C | | M | LC done-when |

**Decision log:** *Kept* explicit cross-references to the 48 negative state-machine test IDs (`TC-08-001`..`TC-08-048`) defined in Phase 2 Step 08 so nothing promised in Phase 2 is left untested. *Dropped* UI latency tests (out of scope per REQ-039). *Rejected* testing concurrency with sequential transactions; `t04_concurrency.sql` uses `dblink` parallel sessions queued behind row locks to test true race conditions at exact boundaries.

## S-21 — Baseline ER and Physical Model

| Path | Parameter | Definition | Reason | Type (L4) | A/C | Allowed values (L3) | M/O | Source |
|---|---|---|---|---|---|---|---|---|
| 1 | **Baseline ER diagrams v1** | updated Mermaid ER diagrams including `V013` refinements (`job_status_transition`) | the playbook's PRODUCE: ER diagram v1 | section | C | | M | LC p.10 |
| 2 | **Physical table and storage architecture** | tables, primary keys, partitioning, fillfactor/TOAST and row-level security | the playbook's DO: physical types, partitioning | section | C | | M | LC p.10 |
| 3 | **Index catalogue and access-pattern mapping** | every B-tree, GIN, GiST, BRIN, partial and unique index mapped to access patterns `AP-01`..`AP-14` and FKs | the playbook's DO: indexes | section | C | | M | LC p.10 |
| 3.1 | index_name | technical index name (`idx_`, `uq_`, `ex_`) | links to DDL | id `(idx\|uq\|ex)_[a-z0-9_]+` | A | | M | model |
| 3.2 | table_and_columns | table, key columns, index method and `WHERE` predicate | complete physical spec | text | A | | M | model |
| 3.3 | purpose | access pattern (`AP-nn`), FK join support, or uniqueness/exclusion rule | justifies the write overhead of the index | text | A | | M | docs/03 §4 |
| 4 | **Concurrency, locking and security architecture** | runtime roles, RLS initPlans, row-lock hierarchy and deadlock prevention | physical enforcement of NFR-SEC and NFR-INT | section | C | | M | `V010`, `V011`, `V013` |
| 5 | **Versioned DDL migration inventory and change-control policy** | `V001`..`V013` scripts, SHA-256 checksums, and the Gate G3 baseline rule | the playbook's go deeper and exit test | section | C | | M | LC p.10 |
| 5.1 | version | migration version `V001`..`V013` | execution order | id `V[0-9]{3}` | A | | M | `db/migrations/` |
| 5.2 | file_name | SQL filename | reproducible build | text | A | | M | `db/migrations/` |
| 5.3 | objects_created | tables, domains, functions, triggers, policies created | inventory of the baseline | text | A | | M | `db/migrations/` |
| 6 | **Documented standard deviations** | justified physical exceptions (`D-01`..`D-04`) | transparency on docket §5 rules | section | C | | M | `t01_standards.sql` |
| 7 | **Exit test check** | verification that the model is frozen as v1 and changes require a change log | a step is not complete until its exit test is met | section | C | | M | LC done-when |

**Decision log:** *Kept* the physical model tied directly to the 13 versioned migration files (`V001`..`V013`) and the `run.sh` migration runner (`schema_migration` checksum table). *Dropped* cloud-vendor-specific Terraform scripts, keeping the physical model portable to any managed PostgreSQL 16 instance. *Rejected* unversioned `ALTER TABLE` scripts; all post-baseline changes must land as `V014+` migrations with a change-log entry.
