# 01 — Functional requirements

Each requirement has an ID and a priority (MoSCoW: **M**ust, **S**hould, **C**ould, **W**on't in v2). Build status and verification are added after the rebuild. AP = access pattern ([03](03-data-requirements.md#4-access-patterns)).

## Reference data (REF)

| ID | Requirement | Pri |
|---|---|---|
| FR-REF-01 | Maintain countries, states, cities (with coordinates), currencies, languages, skills, industries, qualifications, employment types and work modes | M |
| FR-REF-02 | Every fixed set of values is a lookup table with a code, a translated label, an active flag and a sort order; no free-text enumerations | M |
| FR-REF-03 | UI strings are stored by key and translated per language; a missing translation falls back to English | M |
| FR-REF-04 | Skill type-ahead from two typed letters, tolerant of typos | S |

## Identity and access (IAM)

| ID | Requirement | Pri |
|---|---|---|
| FR-IAM-01 | A candidate registers themselves with email (optional phone) and password, accepting terms and privacy policy; the consent is recorded with its policy version | M |
| FR-IAM-02 | Recruiters, employers and consultants cannot register a candidate; they can only contact one | M |
| FR-IAM-03 | An employer registers their organisation; this creates the organisation (verification pending), its wallet, and the user as account admin | M |
| FR-IAM-04 | Nine actors with role-based permissions, checked by the database | M |
| FR-IAM-05 | Login opens a session on a registered device; past the licence's device limit the login is refused and the refusal is audited | M |
| FR-IAM-06 | A user can log out and revoke their sessions and devices; staff can revoke anyone's; revocations are audited | M |
| FR-IAM-07 | Consent per purpose is a history; withdrawing is a new record; the current state is queryable | M |
| FR-IAM-08 | Lock an account after repeated failed logins | S |
| FR-IAM-09 | OTP and social login | C |

## Organisation and account (ORG)

| ID | Requirement | Pri |
|---|---|---|
| FR-ORG-01 | Organisation profile: legal and display name, industry, country, website, locations (one headquarters), group hierarchy | M |
| FR-ORG-02 | A recruiter sees and acts only on their own company's job requirements and applications | M |
| FR-ORG-03 | Tax and registration identifiers are kept with country, type and verification status, without storing the value in clear | M |
| FR-ORG-04 | Membership is effective-dated; a user belongs to one organisation at a time; history is kept | M |
| FR-ORG-05 | The number of current members cannot exceed the seats of the active licence | M |
| FR-ORG-06 | Staff verify organisations (pending → verified / rejected), with the time of verification | M |
| FR-ORG-07 | Sub-roles inside an employer | W |

## Candidate profile (PRO)

| ID | Requirement | Pri |
|---|---|---|
| FR-PRO-01 | Profile core: name in any script, headline, summary, city, total experience, expected salary (disclosed / not disclosed / not provided), notice period, open to work | M |
| FR-PRO-02 | Education history | M |
| FR-PRO-03 | Work history; at most one current job | M |
| FR-PRO-04 | Skills with proficiency and experience | M |
| FR-PRO-05 | Languages with proficiency | M |
| FR-PRO-06 | Resume versions stored as files; one primary | M |
| FR-PRO-07 | Profile visibility: public, recruiters only, hidden | M |
| FR-PRO-08 | A candidate blocks a company or a person; the blocked party can no longer see the candidate, their applications or contact details, and never learns of the block | M |
| FR-PRO-09 | Job alerts: keywords, city, minimum salary, frequency | S |
| FR-PRO-10 | Profile completion score | C |
| FR-PRO-11 | Profile view history, activity log, bookmarks (docket tier 2) | S |
| FR-PRO-12 | Assessments, courses, projects | C |

## Job requirements (JOB)

| ID | Requirement | Pri |
|---|---|---|
| FR-JOB-01 | Post a job: title, description (language recorded), employment type, work mode, industry, experience range, salary range or "not disclosed", positions, locations, skills | M |
| FR-JOB-02 | Lifecycle: draft → open → paused / closed / filled; a published job cannot return to draft | M |
| FR-JOB-03 | Publishing costs credits, charged exactly once | M |
| FR-JOB-04 | A screening questionnaire is attached to a job | M |
| FR-JOB-05 | A job can be opened to consultants | M |
| FR-JOB-06 | Job search by words, city and salary, newest first | M |
| FR-JOB-07 | A closing date stops new applications | S |
| FR-JOB-08 | A job becomes filled when all positions are joined; joins beyond positions are refused | S |

## Applications and pipeline (APP)

| ID | Requirement | Pri |
|---|---|---|
| FR-APP-01 | A candidate applies once per job, optionally with one of their own resume versions | M |
| FR-APP-02 | Answers are only to the questions of the job applied for | M |
| FR-APP-03 | Applications only to open, published jobs, before the closing date | M |
| FR-APP-04 | The pipeline allows only the listed moves; anything else is refused | M |
| FR-APP-05 | A candidate can only withdraw; every other move belongs to the employer side | M |
| FR-APP-06 | Every status change is kept in an append-only history with time and actor | M |
| FR-APP-07 | Recruiter pipeline per job; candidate's application list in their language | M |
| FR-APP-08 | Each status change notifies the candidate | S |
| FR-APP-09 | Interviews, offer letters | C |

## Subscriptions, wallet and payments (BIL)

| ID | Requirement | Pri |
|---|---|---|
| FR-BIL-01 | Plans with price, period, seats, devices per user and included credits | M |
| FR-BIL-02 | A subscription is the licence: periods never overlap per organisation; renewals chain; cancellation never deletes | M |
| FR-BIL-03 | One wallet per organisation; an append-only ledger; the balance never goes negative | M |
| FR-BIL-04 | Payment orders with gateway webhooks: idempotent, amount-checked, ordered status changes | M |
| FR-BIL-05 | A profile download costs one credit; repeating it within 30 days is free; the history keeps who, whom, when and which debit | M |
| FR-BIL-06 | Contact details are released only after a download, and every release is audited | M |
| FR-BIL-07 | A GST invoice for every captured payment; a refund reverses the credits it granted | M |
| FR-BIL-08 | Outreach consumes credits | S |
| FR-BIL-09 | Wallet statement | M |

## Notifications and preferences (NOT)

| ID | Requirement | Pri |
|---|---|---|
| FR-NOT-01 | Preferences per category and channel; an opt-out is respected, except security notices | M |
| FR-NOT-02 | Reliable delivery: written in the same transaction as the event, retried with backoff, provider status recorded | M |
| FR-NOT-03 | In-app inbox | S |
| FR-NOT-04 | Language preference drives UI labels | M |
| FR-NOT-05 | Job alert digests | S |

## Audit and errors (AUD)

| ID | Requirement | Pri |
|---|---|---|
| FR-AUD-01 | Every sensitive action is recorded with actor, organisation, action, row and time; the trail is append-only and cannot be forged | M |
| FR-AUD-02 | Account admins read their organisation's trail; staff read all | M |
| FR-AUD-03 | System errors are logged with a retention period | S |

## Analytics (ANA)

| ID | Requirement | Pri |
|---|---|---|
| FR-ANA-01 | Employer hiring funnel by month: applied → joined, median days to join, only the own organisation | S |
| FR-ANA-02 | A KPI star schema (facts and dimensions for hiring, revenue and engagement KPIs derived from the workflows) | S |

## Deferred modules (designed at conceptual level, see [04](04-conceptual-model.md#4-deferred-subject-areas))

| ID | Requirement | Pri (docket) | Scope |
|---|---|---|---|
| FR-GIG-01..07 | Gig marketplace: requests with window and price, gig worker profiles and availability, applications accepted or rejected by the requester, assignments with handoff reference, favourites and blacklists, ratings, earnings from the fulfilment system | M | Deferred: separate subsystem (ADR-013) |
| FR-SRC-01..04 | Sourcing requests, consultant acceptance or decline, bulk outreach batches and recipients, sourcing shortlists | M | Deferred |
| FR-COM-01..04 | Community posts and reactions, support tickets, FAQs, referral events | S | Deferred |
