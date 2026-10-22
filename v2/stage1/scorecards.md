# Stage 1 — Schema Rating Scorecards (deliverable b), version 1

Built on the scorecard model of *Talencia Global — Control the Output, Process Playbook v2* (pp. 12–14): the 8 core dimensions plus one dimension specific to each deliverable, re-weighted to 100.

## Common model (frozen with the schemas, before scoring)

| # | Dimension | How it is measured | Weight | Critical | If low, go back to |
|---|---|---|---|---|---|
| D1 | Structure conformance | output fields matching the schema ÷ all output fields | 15 | **yes** | Generate |
| D2 | Completeness | fields with a value or explicit UNKNOWN ÷ all fields; every section covered | 15 | | Generate |
| D3 | Definition clarity | parameters with definition, type and reason ÷ all parameters | 10 | | Define |
| D4 | Accuracy and traceability | items traced to a source (docket §, stakeholder, measurement) or marked as assumptions ÷ all items | 20 | **yes** | Generate |
| D5 | Consistency across runs | parameters whose values agree across runs ÷ parameters compared | 5 | | Analyse |
| D6 | Structure and depth | levels justified; no parent with more than ~15 children; leaves atomic | 5 | | Define |
| D7 | Fitness for the next step | inputs the next step needs that this output provides ÷ inputs needed | 10 | | Discover |
| D8 | Author understanding | sample questions on fields answered correctly by the author ÷ questions asked | 10 | **yes** | Discover |
| D9 | Deliverable-specific (per step, below) | | 10 | | Define |
| | **Total** | | **100** | | |

**Re-weighting:** D5 and D6 go from 10 to 5 each, to make room for D9.

**Rules:**
- **Scores:** 0–5 per dimension (5 = 98%+, 4 = 90–97%, 3 = 75–89%, 2 = 50–74%, 1 = 1–49%, 0 = absent).
- **Weighted score:** Σ weight × score ÷ 5.
- **Decision:** Accept when the score is ≥ 90 and every critical dimension is ≥ 4. Refine at 75–89, or when a critical dimension is below 4. Rework below 75.

**Scoring status (honest):**
- **Pass 1 author scores:** filled below by the team with LLM assistance.
- **D8 (Author understanding):** pending. A mentor or peer must ask each author sample questions; the provisional score of 4 assumes the team has read the documents.
- **D5:** low in every step, because each output was generated in one run with one LLM. The second run is the planned refinement.
- **Peer scoring:** not yet done.

## Step 01 — Requirement Analysis Docket
Output: [`../docs/00-scope.md`](../docs/00-scope.md) + [requirements register](01-requirements-register.md) · Schema: [S-01](output-schemas.md#s-01--requirement-analysis-docket)
D9 = **Source coverage**: every section of the docket mapped to a REQ ID or an explicit out-of-scope line.

| Dim | W | Score | Points | Evidence |
|---|---|---|---|---|
| D1 * | 15 | 4 | 12 | sections match S-01; register columns match the parameters |
| D2 | 15 | 4 | 12 | all sections filled; open questions listed |
| D3 | 10 | 4 | 8 | every parameter defined in S-01 |
| D4 * | 20 | 4 | 16 | each REQ carries its docket § source |
| D5 | 5 | 1 | 1 | single run |
| D6 | 5 | 4 | 4 | 3 levels; no parent above 15 children except the REQ list (a list, not a parent) |
| D7 | 10 | 5 | 10 | the data model (docs 03–05) is derived directly from it |
| D8 * | 10 | 4 (provisional) | 8 | pending Q&A |
| D9 | 10 | 5 | 10 | every docket section (§1–§7) mapped to REQ-001..039 or an out-of-scope line |
| | | | **81** | **Refine:** second run, peer score, D8 Q&A |

## Step 02 — Stakeholders, Personas and Roles
Output: [`02-stakeholders-personas-roles.md`](02-stakeholders-personas-roles.md) · Schema: [S-02](output-schemas.md#s-02--stakeholders-personas-and-roles)
D9 = **Every requirement has an actor; permission matrix complete.**

| Dim | W | Score | Points | Evidence |
|---|---|---|---|---|
| D1 * | 15 | 4 | 12 | persona cards follow the card schema; frequency of use added in v1.1 |
| D2 | 15 | 4 | 12 | 11 stakeholders, 7 personas; edge actors (scheduler, payment webhook, regulator) present |
| D3 | 10 | 4 | 8 | parameters defined in S-02 |
| D4 * | 20 | 4 | 16 | personas linked to FR IDs; matrix taken from `access_role_permission` |
| D5 | 5 | 1 | 1 | single run |
| D6 | 5 | 4 | 4 | 3 levels |
| D7 | 10 | 5 | 10 | roles drive the row-level security design |
| D8 * | 10 | 4 (provisional) | 8 | pending Q&A |
| D9 | 10 | 5 | 10 | 9 actors + guest × 13 permissions, from the live schema |
| | | | **81** | **Refine** |

## Step 03 — Feature Discovery
Output: [`../docs/01-functional-requirements.md`](../docs/01-functional-requirements.md) + competitor matrix [`../../docs/coverage-gap-register.md`](../../docs/coverage-gap-register.md) · Schema: [S-03](output-schemas.md#s-03--feature-discovery)
D9 = **At least three competitors covered; every feature traced.**

| Dim | W | Score | Points | Evidence |
|---|---|---|---|---|
| D1 * | 15 | 4 | 12 | feature inventory matches S-03; the classification column uses MoSCoW, mapped to must / should / differentiator in S-03 |
| D2 | 15 | 4 | 12 | 71 features in 10 modules + 3 deferred modules |
| D3 | 10 | 4 | 8 | parameters defined in S-03 |
| D4 * | 20 | 3 | 12 | every Must has a verification; the feature → REQ link is by module, not per row |
| D5 | 5 | 1 | 1 | single run |
| D6 | 5 | 4 | 4 | module → feature → attributes |
| D7 | 10 | 5 | 10 | the schema design is derived from it |
| D8 * | 10 | 4 (provisional) | 8 | pending Q&A |
| D9 | 10 | 4 | 8 | Naukri, Monster / foundit and LinkedIn compared (63 elements, 7 gaps registered) |
| | | | **75** | **Refine:** D4 critical below 4 (add per-feature REQ IDs) |

## Step 04 — NFR Discovery
Output: [`../docs/02-non-functional-requirements.md`](../docs/02-non-functional-requirements.md) · Schema: [S-04](output-schemas.md#s-04--nfr-discovery)
D9 = **Every NFR has a number; targets derived from volumes.**

| Dim | W | Score | Points | Evidence |
|---|---|---|---|---|
| D1 * | 15 | 5 | 15 | register columns match S-04 exactly (ID, requirement, target) |
| D2 | 15 | 5 | 15 | 37 NFRs in 11 categories |
| D3 | 10 | 4 | 8 | parameters defined in S-04 |
| D4 * | 20 | 4 | 16 | targets derived from the workload model (data requirements §3) |
| D5 | 5 | 1 | 1 | single run |
| D6 | 5 | 4 | 4 | category → NFR → metric |
| D7 | 10 | 5 | 10 | targets are concrete enough to verify after the rebuild |
| D8 * | 10 | 4 (provisional) | 8 | pending Q&A |
| D9 | 10 | 4 | 8 | DPDP Act 2023 and GST named; accessibility not yet covered (gap) |
| | | | **85** | **Refine** |

## Step 05 — Business Workflow Analysis
Output: [`05-business-workflows.md`](05-business-workflows.md) (workflow maps + exception catalogue) · Schema: [S-05](output-schemas.md#s-05--business-workflow-analysis)
D9 = **Every must-have feature appears in a workflow; exceptions cover cancel, refund, retry and timeout.**

| Dim | W | Score | Points | Evidence |
|---|---|---|---|---|
| D1 * | 15 | 4 | 12 | each central workflow has trigger, actors, steps, rules, exceptions, data |
| D2 | 15 | 4 | 12 | 14 workflows; 10 with diagrams; exception catalogue |
| D3 | 10 | 4 | 8 | parameters defined in S-05 |
| D4 * | 20 | 4 | 16 | each workflow names its docket §2 source and its enforcement object |
| D5 | 5 | 1 | 1 | single run |
| D6 | 5 | 4 | 4 | workflow → step → decision / exception |
| D7 | 10 | 5 | 10 | feeds entity discovery (docs 04–05 already done) |
| D8 * | 10 | 4 (provisional) | 8 | pending Q&A |
| D9 | 10 | 4 | 8 | cancel, refund, retry and timeout paths in the catalogue |
| | | | **79** | **Refine** |

## Summary and next pass

| Step | a) Schema | b) Scorecard | c) Output | Pass 1 score | Decision |
|---|---|---|---|---|---|
| 01 | ✔ | ✔ | ✔ | 81 | Refine |
| 02 | ✔ | ✔ | ✔ | 81 | Refine |
| 03 | ✔ | ✔ | ✔ | 75 | Refine |
| 04 | ✔ | ✔ | ✔ | 85 | Refine |
| 05 | ✔ | ✔ | ✔ | 79 | Refine |

**Pass 2 plan (to reach Accept ≥ 90):**
1. Regenerate each output with a second LLM against the frozen schema, and compare (D5 → 4).
2. Peer-score independently and discuss any gap above 1 point.
3. Mentor or peer Q&A for D8.
4. Step 03: add a REQ ID per feature (D4 → 4).
5. Step 04: add accessibility NFRs.
