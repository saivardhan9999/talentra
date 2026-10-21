# 00 — Scope, stakeholders and constraints

## 1. Why a v2

v1 (the repository root) follows the docket's 23 milestones and covers every module: about 132 tables, seeded at laptop scale (1M profiles). v2 redoes the design the way a product team would: **analysis first, then the three-level data model, then a smaller and deeper build**.

| | v1 | v2 |
|---|---|---|
| Order of work | milestone by milestone, module by module | requirements → conceptual → logical → physical, with traceability |
| Breadth | all 14 modules, ~132 tables | the transactional core: 35 business tables, 35 reference tables, 2 log tables; other modules designed but deferred ([08](08-gaps-and-next-steps.md)) |
| Scale | 1M profiles (16 GB, 1 h 40 min seed) | 10k profiles (217 MB, under a minute), with a capacity model up to 10M |
| Schema changes | rebuild scripts | versioned, checksummed, forward-only migrations |
| Proof | milestone checks | 111 automated checks (standards 15, integrity 40, security 36, concurrency 4, data quality 16) plus 6 detected data-quality findings |

## 2. Problem statement

Northbridge Workforce Systems runs several legacy systems that hold job requirements, candidate profiles and applications in inconsistent formats. Candidate retention is low, and there is no single view of the hiring pipeline. Talentra is the platform that replaces them: candidates find jobs and apply; employers and recruiters post requirements, source candidates and run their pipeline; the platform earns through subscriptions and credits.

## 3. Goals and non-goals

**Goals**
- **G1:** One trustworthy record of candidates, organisations, jobs and applications, with every business rule enforced by the database, not only by the application.
- **G2:** Privacy by design: a candidate controls who sees them (visibility, blocking, consent); contact details are released only through a paid, audited download.
- **G3:** Money is exact and auditable: append-only ledgers, idempotent payments, invoices.
- **G4:** Fast at small scale, with a measured path to 10M profiles.
- **G5:** Multilingual from the start (Indian languages, any script).
- **G6:** Every requirement traceable to a database object and an automated test.

**Non-goals (v2)**
- The user interface, the API service code, and live integrations (docket section 1).
- ETL from the legacy systems (a separate requirement per the docket); v2 defines the boundary only.
- The deferred modules: gig marketplace, sourcing and outreach, community and support, the full analytics star schema. They are designed at the conceptual level and backlogged in [08](08-gaps-and-next-steps.md).

## 4. Stakeholders and actors

| Actor | Goal on the platform | What the data model gives them |
|---|---|---|
| **Guest** (not signed in) | browse jobs, register | published open jobs only; self-registration |
| **Candidate** | build a profile, find jobs, apply, track status, control privacy | own profile and applications; visibility, blocking, consent, alerts; labels in own language |
| **Employer** (organisation member) | post jobs, hire | own organisation's jobs and pipeline; downloads with credits |
| **Recruiter** (organisation member) | find and move candidates through the pipeline | same as employer except posting; candidate search |
| **Account admin** (organisation member) | run the company account: members, billing, audit | members (within seats), wallet, subscriptions, invoices, own audit trail |
| **Consultant** (freelance recruiter) | source candidates for jobs open to consultants | candidate search; only jobs flagged open to consultants (sourcing module deferred) |
| **Placement officer (TPO)** | place campus students | candidate search (campus drives module deferred) |
| **Admin / Super admin** (Talentra staff) | verify companies, support users, investigate | everything, through audited functions |
| **System actors** | payment webhook, notification worker, scheduler, reporting | dedicated database roles `v2_payments`, `v2_worker`, owner jobs, `v2_reporting` |

Sub-roles inside an employer (posting, interviewing, pipeline) are out of scope (docket section 3). Extension path: a `member_permission` table keyed by `organisation_member`, read by `app_has_permission()`. No policy has to change.

## 5. Assumptions

| ID | Assumption | If wrong |
|---|---|---|
| A-01 | The API is the only client; it sets `app.user_id` per transaction and uses the role for its function | The RLS and audit actor would be wrong: connection setup must be reviewed |
| A-02 | Passwords are hashed by the API (argon2id); the database stores and format-checks the hash | none for the schema |
| A-03 | Resume files live in object storage (encrypted at rest); the database keeps the key and checksum | resume bodies would need a large-object design |
| A-04 | One currency per organisation's billing (INR at launch); money is never converted in the database | a currency-conversion table would be added |
| A-05 | A recruiter works for one organisation at a time | the exclusion constraint on membership would be relaxed |
| A-06 | Peak load at 10M profiles: 1M daily active users, about 600 searches/s at peak (see [03](03-data-requirements.md)) | the capacity model changes, not the schema |

## 6. Constraints

| ID | Constraint | Source |
|---|---|---|
| C-01 | PostgreSQL 16 | docket M1 (v1 decision ADR-001, kept) |
| C-02 | Docket section 5 data standards (naming, keys, domains, audit, nullability, classification, multilingual, licences, money) | docket; enforced by test t01 |
| C-03 | Privileges enforced in the database or access layer, never only in the UI | docket section 3 |
| C-04 | India's Digital Personal Data Protection Act 2023: consent, purpose, erasure | law |
| C-05 | GST invoices for every payment | law |
| C-06 | No card or bank data stored (keeps the platform out of PCI scope) | docket section 6 |
| C-07 | Laptop development environment: Docker, port 5433, under 1 GB of data | user decision: 10k profiles |

## 7. Glossary

| Term | Meaning |
|---|---|
| Job requirement | a job posting with positions to fill |
| Application | one candidate's application to one job requirement |
| Pipeline | the status path of an application: applied → shortlisted → interviewing → offered → joined, or rejected / withdrawn |
| Licence | the subscription period an organisation bought: seats (users) and devices per user (ADR-005) |
| Seat | one current organisation member counted against the licence |
| Credit | the wallet unit spent on job posts (5) and profile downloads (1) |
| Download | buying access to a candidate's contact details for 30 days |
| Outbox | the notification table, written in the same transaction as the change it announces (ADR-010) |
| Block | a candidate hiding from a company or a person |
| RLS | PostgreSQL row-level security: per-row access policies |
| Definer function | a function running with its owner's rights; the only way to perform guarded writes |
