# Phase 2 — Model (lifecycle steps 06–12, gate G2)

*Data-Driven Development Lifecycle*, phase 2 of 8: **turn requirements and workflows into entities, attributes, relationships, rules and a first data dictionary, with privacy designed in.** It starts from the Phase 1 deliverables ([stage1/](../stage1/README.md)) and the v2 model (`db/migrations`).

Every step follows the **quad model** of the *Agentic Roadmap* (p.3): a schema (D1), the scorecard that judges the schema (D2), the output generated strictly inside the schema (D3), and the scorecard that judges the output (D4). Each step passes two gates: D1 against D2, then D3 against D4.

## Deliverables

| Step | D1 schema | D2 schema score | D3 output | D4 output score |
|---|---|---|---|---|
| 06 Entities Discovery | [S-06](schemas.md#s-06--entities-discovery) | 96 | [Entity catalogue](06-entity-catalogue.md): 51 entities, 16 deferred, CRUD matrix of 49 steps | 89 |
| 07 Attributes Discovery | [S-07](schemas.md#s-07--attributes-discovery) | 94 | [Attribute lists](07-attribute-lists.md): 334 attributes, each typed with an example | 89 |
| 08 Entity Lifecycle and State Machines | [S-08](schemas.md#s-08--entity-lifecycle-and-state-machines) | 96 | [State machines](08-state-machines.md): 14 entities, 48 negative tests | 86 |
| 09 Database, Tables and Relationships | [S-09](schemas.md#s-09--database-tables-and-relationships-discovery) | 96 | [Logical ER model v0](09-logical-er-model-v0.md): 80 relationships, both directions | 93 |
| 10 Data Dictionary v1 | [S-10](schemas.md#s-10--data-dictionary-v1) | 94 | [Data dictionary v1](10-data-dictionary-v1.md): 334 columns, business names, worked query | 89 |
| 11 Data Rules and Constraints | [S-11](schemas.md#s-11--data-rules-and-constraints-discovery) | 92 | [Data rules catalogue](11-data-rules-catalogue.md): 208 rules, each with its enforcement point | 93 |
| 12 Data Classification and Privacy | [S-12](schemas.md#s-12--data-classification-and-privacy) | 96 | [Classification register](12-data-classification-register.md): 78 personal or sensitive columns | 89 |

Scorecards: [schema scorecards (D2)](schema-scorecards.md) · [output scorecards (D4)](output-scorecards.md). The schemas drawn as trees, L1 to L4: [schema-trees.md](schema-trees.md). What the model does not yet enforce: [findings.md](findings.md).

## Gate tracker

| Step | D1 schema | D2 | D3 output | D4 | Step status |
|---|---|---|---|---|---|
| 06 | amber (96) | frozen | amber (89) | frozen | open |
| 07 | amber (94) | frozen | amber (89) | frozen | open |
| 08 | amber (96) | frozen | amber (86) | frozen | open |
| 09 | amber (96) | frozen | amber (93) | frozen | open |
| 10 | amber (94) | frozen | amber (89) | frozen | open |
| 11 | amber (92) | frozen | amber (93) | frozen | open |
| 12 | amber (96) | frozen | amber (89) | frozen | open |

**Why everything is amber.** The scores are author self-scores. Author understanding (C8 and D8) is human-only evidence: a mentor interview that has not happened. The roadmap does not let a deliverable turn green without it. Four outputs are also just below 90 because consistency across runs (D5) is 1: one authoring run, no second independent run to compare. The path to green is at the end of [output-scorecards.md](output-scorecards.md#path-to-green-gate-2-in-priority-order).

## G2 exit check: model defined

| G2 criterion | Result |
|---|---|
| Dictionary v1 is complete | 334 of 334 columns with type, constraints, definition, example, class and owner; worked query written from the dictionary alone |
| Every rule states where it is enforced | 208 of 208 rules: database 185, application 6, pipeline 11, gap 6 (each gap is a finding) |
| Every personal-data column is classified with a retention period | 78 of 78 personal or sensitive columns, each with masking and retention |

The content meets G2. The gate itself is a person's decision, after the D8 interviews.

## What Phase 2 found

Building the model step by step surfaced **14 findings** ([findings.md](findings.md)): 3 high, 7 medium, 4 low. These are what the rebuild should fix. The high ones:
- **FND-01:** a published job can be set back to draft.
- **FND-03:** staff have no way to verify an organisation.
- **FND-09:** consent purposes exist but nothing checks them before marketing messages or recruiter visibility.

It also raised **six assumptions** (SA-01 to SA-06 in [step 08](08-state-machines.md)) that need client answers.

## How it is built

```bash
python v2/phase2/tools/build_phase2.py        # 06, 07, 09, 10, 11, 12 and findings.md from db/migrations + tools/notes.py
python v2/stage1/schema_trees.py v2/phase2/schemas.md v2/phase2/schema-trees.md "# Phase 2 — Output schemas as trees (generated)"
```

- **Generated, not written by hand:** six of the seven outputs. The builder reads the DDL as text, so no database is needed, and it combines it with curated knowledge in [`tools/notes.py`](tools/notes.py): entity IDs, workflow steps, business names, definitions, examples, masking rules, retention, rules and findings. One source keeps every ID, table and column consistent across all six documents, and a schema change shows up everywhere on the next run.
- **Written by hand:** step 08 and the schemas, because state rules and gaps need judgement.
- **For the rebuild:** these documents become its design input. After the rebuild, the dictionary goes back to being generated from the live catalog (`./run.sh dictionary`).
