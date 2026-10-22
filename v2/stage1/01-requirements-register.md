# Step 01 — Requirements register

Part of the step 01 output; it conforms to [S-01 §4](output-schemas.md#s-01--requirement-analysis-docket). Every section of the docket maps to a REQ ID or an explicit out-of-scope line.

Columns follow the schema (req_id, statement, source, actor, priority, ambiguity note), plus "realised by": the feature or NFR IDs in [`../docs/01`](../docs/01-functional-requirements.md) and [`../docs/02`](../docs/02-non-functional-requirements.md).

| req_id | Statement | Source | Actor | Priority | Ambiguity note | Realised by |
|---|---|---|---|---|---|---|
| REQ-001 | Provide one consistent store for job requirements, candidate profiles and applications that replaces the legacy formats | §1 problem | all | Must | "single view" = one schema, one id per entity | whole model |
| REQ-002 | Support transactional workflows and analytics at 10M candidate profiles | §1 purpose | system | Must | "scale" = 10M profiles, 1M jobs, 100M applications (§6) | NFR-SCAL-01..03 |
| REQ-003 | Candidates register, log in, build a profile and resume, and self-assess | §2 workflows | candidate | Must | self-assessment deferred (assessments) | FR-IAM-01, FR-PRO-01..06, FR-PRO-12 |
| REQ-004 | Candidates search jobs, apply and track status | §2 | candidate | Must | "track" = full status history + notifications | FR-JOB-06, FR-APP-01..08 |
| REQ-005 | Employers register, are verified, and post job requirements | §2 | employer | Must | | FR-IAM-03, FR-ORG-01..06, FR-JOB-01..02 |
| REQ-006 | Questionnaires can be attached to job requirements | §2 | employer | Must | | FR-JOB-04, FR-APP-02 |
| REQ-007 | Employers and recruiters source candidates, including bulk outreach | §2 | recruiter | Must | bulk outreach deferred | FR-JOB-06, AP-04, FR-SRC-03 |
| REQ-008 | Consultants request to source for a job; the employer accepts or declines | §2 | consultant, employer | Should | central vs secondary judged in WF inventory | FR-SRC-01..02 (deferred) |
| REQ-009 | Users can block users and companies | §2, §3 | candidate | Must | | FR-PRO-08 |
| REQ-010 | Wallet recharge and credit use for postings, downloads and outreach | §2 | account admin | Must | prices: 5 credits per post, 1 per download (assumption) | FR-BIL-03..05, FR-JOB-03 |
| REQ-011 | Notifications and job alerts | §2 | user | Must | | FR-NOT-01..05 |
| REQ-012 | Support tickets and FAQs | §2 | user, admin | Should | judged secondary | FR-COM-02..03 (deferred) |
| REQ-013 | Gig work: windows, prices, apply / accept, external fulfilment, favourites and blacklists, ratings, earnings | §2 gig | requester, gig worker | Must | must decide shared vs separate model | ADR-013, FR-GIG-01..07 (deferred) |
| REQ-014 | Every privilege is enforced in the database or access layer, not only in the UI | §3 | system | Must | | NFR-SEC-04 |
| REQ-015 | A recruiter sees and acts only on their own company's job requirements | §3 | recruiter | Must | | FR-ORG-02 |
| REQ-016 | A consultant works only on job requirements open to consultants | §3 | consultant | Must | | FR-JOB-05 |
| REQ-017 | A blocked party must not see the candidate | §3 | candidate | Must | covers applications and contact details too | FR-PRO-08, NFR-PRIV-02 |
| REQ-018 | Recruiters cannot register candidates on a candidate's behalf | §3 | recruiter | Must | | FR-IAM-02 |
| REQ-019 | Every sensitive action is audited | §3 | system | Must | "sensitive" = roles, credentials, memberships, verification, blocks, sessions, payments, downloads, contact reads | FR-AUD-01, NFR-AUD-02 |
| REQ-020 | Sub-roles inside an employer organisation | §3 | employer | Won't (v2) | out of scope per the docket; extension path documented | FR-ORG-07 |
| REQ-021 | Model all tier-1 data domains | §4 tier 1 | system | Must | gig, sourcing deferred in v2 | data requirements §1 |
| REQ-022 | Model tier-2 domains or justify their omission | §4 tier 2 | system | Should | | FR-PRO-10..12, FR-COM (deferred, justified) |
| REQ-023 | Tier-3 reference domains are optional | §4 tier 3 | system | Could | | deferred |
| REQ-024 | Compare data coverage with Naukri, Monster and LinkedIn, and exceed them where it matters | §4 benchmark | team | Must | | competitor matrix (step 03) |
| REQ-025 | Naming conventions (rule group 1) | §5 | system | Must | | NFR-MNT-02 |
| REQ-026 | Surrogate keys, enforced foreign keys, check constraints, limits by the database (rule group 2) | §5 | system | Must | | NFR-INT-02..03 |
| REQ-027 | Standard domains for names, email, phone, money, dates and enumerations (rule group 3) | §5 | system | Must | | NFR-INT-01, FR-REF-02 |
| REQ-028 | Audit columns, soft or hard delete per entity, append-only audit, retention (rule group 4) | §5 | system | Must | retention periods chosen by the team | NFR-AUD-01..03, NFR-PRIV-04 |
| REQ-029 | Every nullable column justified; unknown ≠ not applicable; no sentinels (rule group 5) | §5 | system | Must | | logical model §4 |
| REQ-030 | Every column classified Public / Internal / Personal / Sensitive (rule group 6) | §5 | system | Must | | data dictionary, NFR-SEC-03 |
| REQ-031 | UTF-8, translated UI labels with fallback, user content stored once with language (rule group 7) | §5 | system | Must | | NFR-I18N-01..03 |
| REQ-032 | Naming patterns for partitions, views and analytical objects (rule group 8) | §5 | system | Must | | NFR-MNT-02 |
| REQ-033 | Licence seat and device limits; device limit at login; revocation audited (rule group 9) | §5 | account admin, user | Must | | FR-ORG-05, FR-IAM-05..06 |
| REQ-034 | Append-only ledgers; non-overlapping subscription periods; append-only download history (rule group 10) | §5 | system | Must | | FR-BIL-02..05 |
| REQ-035 | For each external system: ownership, stored vs referenced, failure behaviour, idempotency, audit | §6 | system | Must | | data requirements §6 |
| REQ-036 | Measure at laptop scale and extrapolate to full scale, naming the query that degrades first | §6 sizing | team | Must | v2 measures at 10k (user decision); v1 at 1M | NFR-PERF-01, physical model §7 |
| REQ-037 | The data generator is a deliverable and respects the stated distributions and data-quality issues | §6 note | team | Must | | data requirements §6, NFR-INT-05 |
| REQ-038 | Payments and subscriptions, licences and devices, multilingual UI data, security design, analytics layer | §1 scope | system | Must | analytics: funnel in the v2 core, star schema deferred | FR-BIL, FR-IAM, NFR-I18N, NFR-SEC, FR-ANA |
| REQ-039 | Out of scope: UI, live integrations, loading 10M profiles on a laptop, ETL | §1 scope | — | Won't | explicit out-of-scope line | scope §3 |

## Open questions (ranked by design impact)

| ID | Question | Design impact |
|---|---|---|
| Q-01 | Should unverified organisations be allowed to publish jobs? (finding F-05) | medium |
| Q-02 | Credit prices per action and per plan | low: prices are data, not schema |
| Q-03 | Seat over-use after a subscription lapses: grace period length? (finding F-04) | low |
