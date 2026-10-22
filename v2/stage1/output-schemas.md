# Stage 1 — Output Schema Definitions (deliverable a), version 1 (frozen 21-Oct-2026)

These schemas follow *Control the Output, Process Playbook v2*. Each schema is a tree:
- **L1:** section
- **L2:** parameter
- **L3:** allowed values or sub-parameters
- **L4:** atomic definition (type, format, validation)

Every parameter states its definition, reason, data type, whether it is **A**tomic or **C**omposite, its allowed values, whether it is **M**andatory or **O**ptional, and its source. Each schema ends with a decision log of what was kept and dropped, and why. The scorecards are in [scorecards.md](scorecards.md). The same schemas are drawn as trees, with the size of each level, in [schema-trees.md](schema-trees.md).

**Common atomic types:**
- `id`: text with a pattern per step, unique
- `text`: free text, bounded
- `enum`: closed list of codes
- `ref`: an id from another register
- `number`, with its unit
- `diagram`: Mermaid

Missing values are written `UNKNOWN`, with the reason.

---

## S-01 — Requirement Analysis Docket

| Path | Parameter | Definition | Reason | Type (L4) | A/C | Allowed values (L3) | M/O | Source |
|---|---|---|---|---|---|---|---|---|
| 1 | **Problem statement** | current state and who is hurt | anchors every later decision | section | C | | M | docket §1 |
| 1.1 | pain_point | one problem in the current systems | must be solvable and testable | text ≤ 200 | A | | M | docket §1 |
| 2 | **Goals** | outcomes the system must achieve | scope is judged against them | section | C | | M | docket §1–2 |
| 2.1 | goal_id | identifier | traceability | id `G[0-9]+` | A | | M | team |
| 2.2 | success_measure | how we know the goal is met | turns vague goals into checks | text | A | | M | team |
| 3 | **Scope** | what is in, out and deferred | stops scope creep | section | C | | M | docket §1 |
| 3.1 | scope_status | status of a capability | explicit out-of-scope lines | enum | A | in · out · deferred | M | docket §1 |
| 3.2 | reason | why it is out or deferred | the docket asks for justification | text | A | | M if not "in" | team |
| 4 | **Requirements register** ([01-requirements-register.md](01-requirements-register.md)) | every requirement in the brief | every brief sentence maps to an ID or out-of-scope | section | C | | M | docket §2–7 |
| 4.1 | req_id | identifier | the traceability thread starts here | id `REQ-[0-9]{3}` | A | | M | team |
| 4.2 | statement | the requirement in one sentence | unambiguous wording | text ≤ 300 | A | | M | docket |
| 4.3 | source | where it comes from | accuracy and traceability | ref | A | docket §n · stakeholder · law | M | docket |
| 4.4 | actor | who needs it | G1 exit rule: every requirement names an actor | ref → S-02 role | A | 9 docket actors + guest + system | M | docket §3 |
| 4.5 | priority | importance | release planning | enum | A | Must · Should · Could · Won't | M | team |
| 4.6 | ambiguity_note | vague words turned into numbers or questions | the playbook asks to remove "fast" and "many" | text | A | | O | team |
| 5 | **Assumptions** | beliefs not yet confirmed | risks made visible | section | C | | M | team |
| 5.1 | impact_if_wrong | consequence | ranks assumptions | text | A | | M | team |
| 6 | **Constraints** | fixed limits | design must respect them | section | C | | M | docket §5, law |
| 6.1 | constraint_source | origin | weight of the constraint | enum | A | docket · law · technology · user | M | |
| 7 | **Open questions** | what must be answered by the client | ranked by design impact | section | C | | M | team |
| 7.1 | design_impact | effect on the model | ranking | enum | A | high · medium · low | M | team |
| 8 | **Glossary** | domain terms | shared language | section | C | | M | docket |

**Decision log:**
- **Kept:** the docket's split (goals, scope, out-of-scope, assumptions, open questions).
- **Dropped:** a separate "business rules" section, because the rules live with their requirement (REQ) and are detailed in S-05.
- **Dropped:** stakeholder lists here, because they belong to S-02.

## S-02 — Stakeholders, Personas and Roles

| Path | Parameter | Definition | Reason | Type (L4) | A/C | Allowed values (L3) | M/O | Source |
|---|---|---|---|---|---|---|---|---|
| 1 | **Stakeholder map** | everyone affected | nobody forgotten | section | C | | M | docket §3 |
| 1.1 | stakeholder_type | kind | edge actors included | enum | A | primary user · payer · partner · internal · regulator · external system | M | |
| 1.2 | interest / influence | engagement level | prioritises needs | enum | A | low · medium · high | M | team |
| 2 | **Persona cards** | archetypal users | design for real people | section | C | | M | team |
| 2.1 | persona_id | identifier | traceability | id `P[0-9]+` | A | | M | |
| 2.2 | role | docket actor played | links persona to permissions | ref → 3.1 | A | | M | docket §3 |
| 2.3 | goals / frustrations | what they want / what hurts now | drives features | text list | C | | M | team |
| 2.4 | frequency_of_use | how often they use the system | load and UX priority | enum | A | daily · weekly · monthly · seasonal | M | team |
| 2.5 | requirements_served | linked requirement ids | traceability | ref list → REQ / FR | C | | M | S-01, S-03 |
| 3 | **Role–permission matrix** | who may do what | access design | section | C | | M | docket §3 |
| 3.1 | role | system role | | enum | A | 9 docket actors + guest | M | docket §3 |
| 3.2 | permission | an action on data | least privilege | enum | A | 13 permission codes | M | schema |
| 4 | **Hard access rules** | non-negotiable rules | enforced in the database | section | C | | M | docket §3 |
| 4.1 | enforcement_point | where it is enforced | the docket demands DB or access layer | text | A | | M | design |
| 5 | **Out-of-scope roles** | roles excluded | docket requirement | section | C | | M | docket §3 |

**Decision log:**
- **Kept:** frequency of use (the playbook asks for it).
- **Dropped:** demographics beyond city and age, which add no requirements.
- **Dropped:** employer sub-roles, which are out of scope per the docket.

## S-03 — Feature Discovery

| Path | Parameter | Definition | Reason | Type (L4) | A/C | Allowed values (L3) | M/O | Source |
|---|---|---|---|---|---|---|---|---|
| 1 | **Feature inventory** | what the product must do | basis of the build | section | C | | M | docket §2 |
| 1.1 | feature_id | identifier | traceability | id `FR-[A-Z]{3}-[0-9]{2}` | A | | M | team |
| 1.2 | statement | actor + capability | testable | text | A | | M | |
| 1.3 | module | grouping | ownership | enum | A | REF · IAM · ORG · PRO · JOB · APP · BIL · NOT · AUD · ANA · GIG · SRC · COM | M | docket §7 |
| 1.4 | priority / classification | importance | release scope | enum | A | Must (= must-have) · Should (= should-have) · Could · differentiator flag | M | team |
| 1.5 | status | build state | honest progress | enum | A | Built · Partial · Deferred | M | |
| 1.6 | verified_by | proof | every Must is proven | text | A | | M if Must | tests |
| 1.7 | traces_to | requirement or new insight | the playbook's exit rule | ref → REQ / "new insight" | A | | M | S-01 |
| 2 | **Competitor coverage matrix** ([coverage-gap-register.md](../../docs/coverage-gap-register.md)) | what market leaders capture | ≥ 3 competitors | section | C | | M | docket §4 |
| 2.1 | competitor | product compared | | enum | A | Naukri · Monster / foundit · LinkedIn | M | public sites |
| 2.2 | coverage | does each one capture the element | gap analysis | enum | A | ✔ · ◐ · ✘ · — | M | |
| 2.3 | talentra_position | our standing | differentiators | enum | A | matches · exceeds · gap Gn | M | |
| 3 | **Deferred features** | not built now | honest scope | section | C | | M | |

**Decision log:**
- **Kept:** MoSCoW, mapped to the playbook's must-have / should-have / differentiator.
- **Dropped:** effort estimates, which belong to release planning.

## S-04 — NFR Discovery

| Path | Parameter | Definition | Reason | Type (L4) | A/C | Allowed values (L3) | M/O | Source |
|---|---|---|---|---|---|---|---|---|
| 1 | **NFR register** | measurable quality targets | design must meet them | section | C | | M | docket §1, §6 |
| 1.1 | nfr_id | identifier | traceability | id `NFR-[A-Z0-9]+-[0-9]{2}` | A | | M | |
| 1.2 | category | quality attribute | coverage of all areas | enum | A | PERF · SCAL · REL · SEC · PRIV · INT · AUD · I18N · MNT · OBS · CMP (+ accessibility planned) | M | playbook step 04 |
| 1.3 | metric | what is measured | numbers, not adjectives | text | A | | M | |
| 1.4 | target | the number to meet | the playbook's exit rule | number + unit | A | | M | workload model |
| 1.5 | test_method | how it is measured | every NFR is testable | text | A | benchmark · test suite · drill · review | M | |
| 1.6 | status | met or not | honest gaps | enum | A | Met · Projected · Production concern · Gap | M | measurements |
| 2 | **Workload assumptions** | users, rates, volumes | targets derived from volumes | section | C | | M | docket §6 sizing |
| 3 | **Regulations** | laws that apply | compliance | section | C | DPDP Act 2023 · GST · PCI (avoided) | M | law |

**Decision log:**
- **Kept:** status, to report honestly.
- **Dropped:** cost targets, which have no source data yet.

## S-05 — Business Workflow Analysis

| Path | Parameter | Definition | Reason | Type (L4) | A/C | Allowed values (L3) | M/O | Source |
|---|---|---|---|---|---|---|---|---|
| 1 | **Workflow inventory** | all workflows | none forgotten | section | C | | M | docket §2 |
| 1.1 | workflow_id | identifier | traceability | id `WF-[0-9]{2}` | A | | M | |
| 1.2 | centrality | central or secondary, with reason | the docket asks to justify it | enum + text | C | central · secondary | M | docket §2 note |
| 2 | **Workflow map** (per central workflow) | end-to-end flow | design input for entities | section | C | | M | |
| 2.1 | trigger | what starts it | | text | A | | M | |
| 2.2 | actors | who takes part | links to S-02 | ref list | C | | M | S-02 |
| 2.3 | steps | ordered actions | | diagram | C | flowchart · sequence · state | M | |
| 2.4 | decisions | branch points | | text | A | | M | |
| 2.5 | business_rules | what must hold | becomes constraints and tests | text list | C | | M | docket §3, §5 |
| 2.6 | outputs / data touched | records created or changed | feeds entity discovery (step 06) | ref list → tables | C | | M | |
| 2.7 | enforcement | where each rule is enforced | the docket requires DB enforcement | text | A | | M | design |
| 3 | **Exception catalogue** | what goes wrong | not only the happy path | section | C | | M | playbook step 05 |
| 3.1 | exception_id | identifier | | id `EX-[0-9]{2}` | A | | M | |
| 3.2 | exception_type | kind of failure | covers cancel, refund, retry and timeout | enum | A | validation · business rule · concurrency · cancel · refund · retry · timeout · external down | M | |
| 3.3 | handling | system response | | text | A | | M | |
| 4 | **State models** | allowed transitions | stateful entities | section | C | | M | |

**Decision log:**
- **Kept:** enforcement per rule, which links workflows to the database.
- **Dropped:** swimlane timing (SLAs per step), which belongs to NFRs.
