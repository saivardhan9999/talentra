# Phase 2 — Output schemas (D1), version 1

One schema per Phase 2 step of the *Data-Driven Development Lifecycle* (steps 06–12, Model). Same format as [Phase 1](../stage1/output-schemas.md): each row is a node of the tree; **Path** gives its level (1 = L1 section, 1.1 = L2 parameter), **Allowed values** is L3, **Type** is L4. A/C = atomic or composite; M/O = mandatory or optional. Sources: *LC* = lifecycle playbook page for the step; *docket* = hackathon docket; *P1* = Phase 1 deliverables; *model* = v2 migrations. Each schema was scored against its schema scorecard (D2) in [schema-scorecards.md](schema-scorecards.md) before the output was generated.

## S-06 — Entities Discovery

| Path | Parameter | Definition | Reason | Type (L4) | A/C | Allowed values (L3) | M/O | Source |
|---|---|---|---|---|---|---|---|---|
| 1 | **Entity catalogue** | everything the business keeps data about | the playbook's PRODUCE for step 06 | section | C | | M | LC p.7 |
| 1.1 | entity_id | identifier of the entity | every later step cites it | id `ENT-[0-9]{2}` | A | | M | LC rule "give everything an ID" |
| 1.2 | name | business name, singular | shared language with the glossary | text ≤ 60 | A | | M | P1 glossary |
| 1.3 | definition | what one instance is | separates entity from attribute | text ≤ 300 | A | | M | LC p.7 |
| 1.4 | subject_area | grouping | ownership and diagrams | enum | A | Identity and access · Organisation · Candidate profile · Jobs and applications · Billing and licences · Notifications · Audit · Analytics · Reference data | M | docket §7 modules |
| 1.5 | kind | role of the entity in the model | makes hidden entities visible | enum | A | core · child · history · audit · configuration · reference · derived | M | LC go deeper |
| 1.6 | owner | source of truth for its data | the playbook's PRODUCE asks for it | text | A | | M | docket §6 boundaries |
| 1.7 | delete_rule | how instances leave | rule group 4 (soft or hard delete stated) | text | A | | M | docket rule group 4 |
| 1.8 | tables | tables that realise it | traceability to the model | ref list → tables | C | | M | model |
| 2 | **Hidden entities** | history, audit, configuration, reference entities | the playbook's go deeper | section | C | | M | LC p.7 |
| 2.1 | why_needed | what breaks without it | justifies each one | text | A | | M | docket, P1 |
| 3 | **Synonyms merged** | words that name one entity | the playbook's DO: merge synonyms | section | C | | M | LC p.7 |
| 3.1 | kept_term | the one name used | one concept, one name | ref → 1.2 | A | | M | P1 glossary |
| 3.2 | words_found | other words in the sources | shows the merge | text list | C | | M | docket, P1 |
| 4 | **Nouns kept as attributes** | nouns that did not become entities | the playbook's DO: separate entities from attributes | section | C | | M | LC p.7 |
| 4.1 | became | what the noun became | records the decision | enum | A | attribute · enumeration value · entity · derived attribute | M | review |
| 4.2 | reason | why | decision log | text | A | | M | review |
| 5 | **Deferred entities** | designed, no table in v2 | honest scope | section | C | | M | P1 scope |
| 5.1 | deferred_id | identifier | traceability | id `ENT-D[0-9]{2}` | A | | M | LC rule "give everything an ID" |
| 6 | **Workflow coverage (CRUD matrix)** | which step touches which entity | the exit test of step 06 | section | C | | M | LC done-when |
| 6.1 | step_id | workflow step | link to Phase 1 step 05 | ref → WF step | A | | M | P1 step 05 |
| 6.2 | operation | what the step does to the entity | finds entities nobody creates or reads | enum | A | C · R · U · D | M | LC done-when |

**Decision log:** *Kept* one entity per business concept even when it spans tables (ENT-51 groups 23 lookups). *Dropped* attribute counts per entity, which belong to step 07. *Added* the CRUD matrix, because the exit test ("every workflow step reads or writes at least one named entity") cannot be checked without it.

## S-07 — Attributes Discovery

| Path | Parameter | Definition | Reason | Type (L4) | A/C | Allowed values (L3) | M/O | Source |
|---|---|---|---|---|---|---|---|---|
| 1 | **Attribute list** | every attribute of every entity | the playbook's PRODUCE for step 07 | section | C | | M | LC p.7 |
| 1.1 | entity | entity the attribute belongs to | groups the list | ref → S-06 1.1 | A | | M | S-06 |
| 1.2 | attribute | business name | readable by non-engineers | text ≤ 60 | A | | M | P1 |
| 1.3 | column | technical name | rule group 1 naming | id `[a-z][a-z0-9_]*` | A | | M | docket rule group 1 |
| 1.4 | logical_type | standard domain | rule group 3: one rule per kind of data | enum | A | Identifier · Reference · Code · Person name · Short text · Medium text · Long text · Email · Phone (E.164) · Money · Credits · Coordinate · Digest · Flag · Timestamp · Date · IP address · Document (JSON) · Search vector · Integer · Formatted text | M | docket rule group 3 |
| 1.5 | length | size or precision | the playbook asks for length | text | A | | M | LC p.7 |
| 1.6 | mandatory | required, or optional with the reason | rule group 5: every nullable justified | enum + text | C | yes · no — reason | M | docket rule group 5 |
| 1.7 | unit | unit of the value | the playbook asks for unit | text | A | | O | LC p.7 |
| 1.8 | example | a realistic value | the playbook's exit test | text | A | | M | LC done-when |
| 1.9 | stored_or_derived | how the value comes to exist | the playbook's go deeper | enum + text | C | stored · derived · derived at write · snapshot | M | LC go deeper |
| 2 | **Multi-valued attributes** | repeating values found | the playbook's go deeper (flag them) | section | C | | M | LC p.7 |
| 2.1 | moved_to | relation that now holds them | first normal form | ref → table | A | | M | model |
| 3 | **Enumeration shape** | the one shape of every lookup | rule group 3 enumeration | section | C | | M | docket rule group 3 |
| 3.1 | values | the codes of each lookup | closed lists are visible | text list | C | | M | model |
| 4 | **Exit test check** | the step's DONE WHEN measured on this output | a step is not complete until its exit test is met | section | C | | M | LC done-when |

**Decision log:** *Kept* the logical level (no PostgreSQL types; those are in S-10). *Dropped* a per-attribute class column, because classification has its own step (12) and reviewing it twice would let the two disagree. *Kept* audit columns out of each table, stated once.

## S-08 — Entity Lifecycle and State Machines

| Path | Parameter | Definition | Reason | Type (L4) | A/C | Allowed values (L3) | M/O | Source |
|---|---|---|---|---|---|---|---|---|
| 1 | **State storage decision** | how each entity's state is stored | a design choice per entity | section | C | | M | model |
| 1.1 | pattern | storage pattern | stops a status column duplicating timestamps | enum | A | status column · derived from timestamps · derived from other rows | M | model |
| 2 | **State machine** | one per stateful entity | the playbook's PRODUCE: state diagram | section | C | | M | LC p.7 |
| 2.1 | entity | entity described | traceability | ref → S-06 1.1 | A | | M | S-06 |
| 2.2 | state | one state | the diagram's nodes | enum | A | values of the entity's status lookup, or derived states | M | model lookups |
| 2.3 | is_final | the state has no way out | the playbook's exit test | flag | A | yes · no | M | LC done-when |
| 3 | **Transition table** | every allowed move | the playbook's PRODUCE: transition table | section | C | | M | LC p.7 |
| 3.1 | from_state | state before | a transition needs both ends | ref → 2.2 | A | | M | model |
| 3.2 | to_state | state after | a transition needs both ends | ref → 2.2 | A | | M | model |
| 3.3 | triggered_by | who or what makes the move | the playbook's DO: who triggers each | ref → S-02 role or system | A | | M | P1 step 02 |
| 3.4 | guard | condition that must hold | the playbook's DO: guarding conditions | text | A | | M | LC p.7 |
| 3.5 | side_effects | what else changes | finds hidden writes (history, credits, notifications) | text | A | | O | model |
| 3.6 | enforced_by | where the database holds the rule | links to step 11 | text | A | | M | model |
| 4 | **Illegal transitions** | moves that must be refused | the playbook's go deeper | section | C | | M | LC go deeper |
| 4.1 | test_id | negative test identifier | each becomes a test in Phase 3 | id `TC-08-[0-9]{3}` | A | | M | LC rule "give everything an ID" |
| 4.2 | expected | outcome of the attempt | a test needs an expected result | enum | A | refused · no-op · stored, unchanged | M | LC go deeper |
| 5 | **Findings** | rules the model does not enforce yet | honest gaps for the rebuild | section | C | | M | review |
| 5.1 | finding_id | identifier | tracked to closure | id `FND-[0-9]{2}` | A | | M | LC rule "give everything an ID" |
| 6 | **Assumptions** | proposed transitions not yet agreed | keeps proposals apart from facts (accuracy and traceability) | section | C | | M | review |
| 6.1 | assumption_id | identifier | each needs a client answer | id `SA-[0-9]{2}` | A | | M | LC rule "give everything an ID" |
| 7 | **Exit test check** | the step's DONE WHEN measured on this output | a step is not complete until its exit test is met | section | C | | M | LC done-when |

**Decision log:** *Kept* derived-state entities (session, subscription) as state machines, because their rules (what counts against the device limit, what is a licence today) are state rules. *Dropped* timing per transition (SLAs), which belong to NFRs.

## S-09 — Database, Tables and Relationships Discovery

| Path | Parameter | Definition | Reason | Type (L4) | A/C | Allowed values (L3) | M/O | Source |
|---|---|---|---|---|---|---|---|---|
| 1 | **ER diagrams by subject area** | the logical ER model v0 drawn | the playbook's PRODUCE | section | C | | M | LC p.7 |
| 2 | **Relationship register** | every relationship between entities | the playbook's exit test | section | C | | M | LC done-when |
| 2.1 | rel_id | identifier | cited by reviews | id `R-[0-9]{2}` | A | | M | LC rule "give everything an ID" |
| 2.2 | parent | referenced table | direction of the key | ref → table | A | | M | model |
| 2.3 | child | referencing table | direction of the key | ref → table | A | | M | model |
| 2.4 | key | foreign-key column(s) | rule group 2: every relationship is a constraint | text | A | | M | docket rule group 2 |
| 2.5 | parent_to_child | how many children one parent has | cardinality in direction 1 | enum | A | 0..1 · 0..* · 1..* · 1 | M | LC done-when |
| 2.6 | child_to_parent | how many parents one child has | cardinality in direction 2, optionality | enum | A | exactly 1 · 0..1 | M | LC done-when |
| 2.7 | delete_rule | what deleting the parent does | rule group 2: stated delete behaviour | enum | A | restrict · cascade · set null | M | docket rule group 2 |
| 2.8 | note | composite key, self-reference, junction | explains the unusual ones | text | A | | O | model |
| 3 | **Summarised references** | enumeration and audit references | keeps the diagrams readable | section | C | | M | docket rule groups 3, 4 |
| 4 | **Many-to-many resolved** | junction relations | the playbook's DO: junction tables | section | C | | M | LC p.7 |
| 4.1 | resolves | the two entities joined | shows the many-to-many behind each junction | text | A | | M | model |
| 5 | **Normalisation** | 3NF and each denormalisation | the playbook's DO: 3NF, denormalise only with a reason | section | C | | M | LC p.7 |
| 5.1 | kept_consistent_by | what stops the copy drifting | a reason without a safeguard is not enough | text | A | | M | model |
| 6 | **History strategy** | how history is kept | the playbook's go deeper | section | C | | M | LC go deeper |
| 6.1 | pattern | history pattern | names the pattern so it can be compared | enum | A | event history · effective dating · snapshot · ledger with reversals · soft delete · row audit · SCD type 2 (not used) | M | LC go deeper |
| 6.2 | why | justification | the playbook asks to justify it | text | A | | M | LC go deeper |
| 7 | **Exit test check** | the step's DONE WHEN measured on this output | a step is not complete until its exit test is met | section | C | | M | LC done-when |

**Decision log:** *Kept* the model as v0, generated from the keys of the v2 model so the diagram cannot disagree with it. *Dropped* drawing the 40 enumeration references, which are summarised instead (they would double the diagram and add nothing).

## S-10 — Data Dictionary v1

| Path | Parameter | Definition | Reason | Type (L4) | A/C | Allowed values (L3) | M/O | Source |
|---|---|---|---|---|---|---|---|---|
| 1 | **Reading guide** | naming, joining and a worked query | the playbook's exit test (a newcomer writes a correct query) | section | C | | M | LC done-when |
| 2 | **Table entry** | one per table | the playbook's PRODUCE | section | C | | M | LC p.8 |
| 2.1 | table | technical table name | what a query names | id `[a-z][a-z0-9_]*` | A | | M | model |
| 2.2 | column | technical column name | what a query names | id `[a-z][a-z0-9_]*` | A | | M | model |
| 2.3 | business_name | name a business user recognises | the playbook's go deeper | text ≤ 60 | A | | M | LC go deeper |
| 2.4 | type | PostgreSQL type or domain | the physical rule behind the logical type | text | A | | M | model |
| 2.5 | null | nullable, with the reason | rule group 5 | enum + text | C | (not null) · yes — reason | M | docket rule group 5 |
| 2.6 | constraints | keys, checks, domain, default | the playbook's DO | text list | C | | M | model |
| 2.7 | definition | business meaning | the playbook's DO | text | A | | M | P1, model |
| 2.8 | example | a realistic value | the playbook's DO | text | A | | M | LC p.8 |
| 2.9 | class | sensitivity | rule group 6: every column tagged | enum | A | Public · Internal · Personal · Sensitive | M | docket rule group 6 |
| 2.10 | owner | source of truth for the field | the playbook's DO | text | A | | M | S-06 1.6 |
| 3 | **Lookup values** | every code of every enumeration | queries need the codes | section | C | | M | model |
| 4 | **Analytical objects** | aggregates and views | rule group 8 objects are data too | section | C | | M | docket rule group 8 |
| 5 | **Exit test check** | the step's DONE WHEN measured on this output | a step is not complete until its exit test is met | section | C | | M | LC done-when |

**Decision log:** *Kept* class as currently tagged in the model, with the reviewed class in S-12, so the dictionary shows the truth of the model and S-12 shows the target. *Dropped* index lists (physical tuning, Phase 4).

## S-11 — Data Rules and Constraints Discovery

| Path | Parameter | Definition | Reason | Type (L4) | A/C | Allowed values (L3) | M/O | Source |
|---|---|---|---|---|---|---|---|---|
| 1 | **Business and cross-table rules** | rules that span rows or tables | the playbook's go deeper | section | C | | M | LC p.8 |
| 1.1 | rule_id | identifier | the playbook's PRODUCE: ID | id `DR-[0-9]{3}` | A | | M | LC p.8 |
| 1.2 | rule | the rule in one sentence | unambiguous wording | text ≤ 200 | A | | M | P1 step 05 |
| 1.3 | tables | tables governed | the playbook's PRODUCE: table | ref list → tables | C | | M | model |
| 1.4 | enforcement_point | where it is enforced | the playbook's exit test | enum | A | database · application · pipeline · gap | M | LC done-when |
| 1.5 | mechanism | constraint, trigger, function, policy, job | proves the point | text | A | | M | model |
| 1.6 | business_rule | conceptual rule it implements | traceability to docs/04 | ref → BR-nn | A | | O | conceptual model |
| 2 | **Standard domains** | one rule per kind of data | rule group 3 | section | C | | M | docket rule group 3 |
| 3 | **Single-table constraints** | keys, uniqueness, ranges, formats | the playbook's DO | section | C | | M | LC p.8 |
| 3.1 | kind | kind of constraint | groups the rules by mechanism | enum | A | check · unique · unique (index) · exclusion | M | model |
| 3.2 | rule_as_declared | the exact declaration | no paraphrase drift | text | A | | M | model |
| 4 | **Cross-table mechanisms** | how cross-table rules hold under concurrency | why a CHECK is not enough | section | C | | M | docket rule group 2 |
| 5 | **Exit test check** | the step's DONE WHEN measured on this output | a step is not complete until its exit test is met | section | C | | M | LC done-when |

**Decision log:** *Kept* "gap" as an enforcement point, so a rule enforced nowhere is visible instead of missing. *Dropped* listing every NOT NULL and foreign key again (they are in S-10 and S-09).

## S-12 — Data Classification and Privacy

| Path | Parameter | Definition | Reason | Type (L4) | A/C | Allowed values (L3) | M/O | Source |
|---|---|---|---|---|---|---|---|---|
| 1 | **Classification rule** | how a column gets its class | repeatable, reviewable classes | section | C | | M | docket rule group 6 |
| 1.1 | class | sensitivity class | drives masking, retention and access | enum | A | Public · Internal · Personal · Sensitive | M | docket rule group 6 |
| 2 | **Masking codes** | rendering rules outside the authorised view | the playbook's DO: masking | section | C | | M | LC p.8 |
| 2.1 | masking_code | code of the rule | one rule reused by many columns | enum | A | M1 · M2 · M3 · M4 · M5 | M | LC p.8 |
| 3 | **Register** | every personal or sensitive column | the playbook's PRODUCE | section | C | | M | LC p.8 |
| 3.1 | column | table and column | what is classified | ref → S-10 2.2 | A | | M | S-10 |
| 3.2 | protection | encryption or hashing | the playbook's DO: encryption | enum | A | argon2id hash · SHA-256 · HMAC-SHA256 · object store encryption · volume encryption + TLS | M | NFR-SEC-03 |
| 3.3 | retention | how long it is kept | the playbook's exit test | text | A | | M | P1 data requirements §5 |
| 3.4 | on_erasure | what erasure does | the playbook's go deeper: right to erasure | enum | A | delete · anonymise · keep | M | DPDP Act 2023 |
| 3.5 | lawful_basis | why it may be processed | the playbook's DO: consent | enum | A | contract · legal obligation · legitimate use · consent | M | DPDP Act 2023 |
| 3.6 | audit | how access or change is recorded | the playbook's DO: audit | text | A | | M | docket §3 |
| 4 | **Reclassification** | columns whose tag changes | the review's result | section | C | | M | review |
| 5 | **Entity summary** | highest class and retention per table | one view for operations | section | C | | M | docs/03 §1 |
| 6 | **Privacy by design** | erasure, minimisation, test data | the playbook's go deeper | section | C | | M | LC go deeper |
| 7 | **Exit test check** | the step's DONE WHEN measured on this output | a step is not complete until its exit test is met | section | C | | M | LC done-when |

**Decision log:** *Kept* the docket's four classes (the client's standard) and mapped the playbook's "confidential" to Sensitive. *Dropped* Public and Internal columns from the register body (they need no masking); they appear in the entity summary and the dictionary.
