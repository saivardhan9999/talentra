# 01 — Functional requirements

Each requirement has an ID (cited in the migrations and tests), a priority (MoSCoW: **M**ust, **S**hould, **C**ould, **W**on't in v2), its v2 status, and how it is verified. Status: **Built** = in the schema and tested; **Partial** = schema in place, part of the logic belongs to the API; **Deferred** = designed, in the backlog ([08](08-gaps-and-next-steps.md)). Test IDs refer to `db/tests/`; AP = access pattern ([03](03-data-requirements.md#4-access-patterns)).

## Reference data (REF)

| ID | Requirement | Pri | Status | Verified by |
|---|---|---|---|---|
| FR-REF-01 | Maintain countries, states, cities (with coordinates), currencies, languages, skills, industries, qualifications, employment types and work modes | M | Built | V002, t01 |
| FR-REF-02 | Every fixed set of values is a lookup table with a code, a translated label, an active flag and a sort order; no free-text enumerations | M | Built | t01 (lookup shape) |
| FR-REF-03 | UI strings are stored by key and translated per language; a missing translation falls back to English | M | Built | t02 (Tamil, Telugu → English) |
| FR-REF-04 | Skill type-ahead from two typed letters, tolerant of typos | S | Built | AP-09 |

## Identity and access (IAM)

| ID | Requirement | Pri | Status | Verified by |
|---|---|---|---|---|
| FR-IAM-01 | A candidate registers themselves with email (optional phone) and password, accepting terms and privacy policy; the consent is recorded with its policy version | M | Built | `auth_register_candidate`, t03 |
| FR-IAM-02 | Recruiters, employers and consultants cannot register a candidate; they can only contact one | M | Built | t03 |
| FR-IAM-03 | An employer registers their organisation; this creates the organisation (verification pending), its wallet, and the user as account admin | M | Built | `auth_register_employer` |
| FR-IAM-04 | Nine actors with role-based permissions, checked by the database | M | Built | `access_role_permission`, t03 |
| FR-IAM-05 | Login opens a session on a registered device; past the licence's device limit the login is refused and the refusal is audited | M | Built | `auth_open_session`, t04 race |
| FR-IAM-06 | A user can log out and revoke their sessions and devices; staff can revoke anyone's; revocations are audited | M | Built | `auth_end_session`, t03 |
| FR-IAM-07 | Consent per purpose is a history; withdrawing is a new record; the current state is queryable | M | Built | `consent_current`, t05 R-12 |
| FR-IAM-08 | Lock an account after repeated failed logins | S | Partial | columns in `user_credential`; counting in the auth service |
| FR-IAM-09 | OTP and social login | C | Deferred | |

## Organisation and account (ORG)

| ID | Requirement | Pri | Status | Verified by |
|---|---|---|---|---|
| FR-ORG-01 | Organisation profile: legal and display name, industry, country, website, locations (one headquarters), group hierarchy | M | Built | V004, t02 (cycle) |
| FR-ORG-02 | A recruiter sees and acts only on their own company's job requirements and applications | M | Built | RLS, t03 |
| FR-ORG-03 | Tax and registration identifiers are kept with country, type and verification status, without storing the value in clear | M | Built | `pii_hmac`, t01 |
| FR-ORG-04 | Membership is effective-dated; a user belongs to one organisation at a time; history is kept | M | Built | exclusion constraint, t02 |
| FR-ORG-05 | The number of current members cannot exceed the seats of the active licence | M | Built | trigger with row lock, t02, t04 race |
| FR-ORG-06 | Staff verify organisations (pending → verified / rejected), with the time of verification | M | Built | `ck_organisation_verified_at` |
| FR-ORG-07 | Sub-roles inside an employer | W | Out of scope (docket) | extension noted in [00](00-scope.md#4-stakeholders-and-actors) |

## Candidate profile (PRO)

| ID | Requirement | Pri | Status | Verified by |
|---|---|---|---|---|
| FR-PRO-01 | Profile core: name in any script, headline, summary, city, total experience, expected salary (disclosed / not disclosed / not provided), notice period, open to work | M | Built | t02 (salary rules) |
| FR-PRO-02 | Education history | M | Built | V006 |
| FR-PRO-03 | Work history; at most one current job | M | Built | `uq_candidate_experience_one_current` |
| FR-PRO-04 | Skills with proficiency and experience | M | Built | V006 |
| FR-PRO-05 | Languages with proficiency | M | Built | V006 |
| FR-PRO-06 | Resume versions stored as files; one primary | M | Built | `uq_resume_one_primary` |
| FR-PRO-07 | Profile visibility: public, recruiters only, hidden | M | Built | t03 (hidden never found) |
| FR-PRO-08 | A candidate blocks a company or a person; the blocked party can no longer see the candidate, their applications or contact details, and never learns of the block | M | Built | t03 (5 checks) |
| FR-PRO-09 | Job alerts: keywords, city, minimum salary, frequency | S | Built | V009 |
| FR-PRO-10 | Profile completion score | C | Deferred | |
| FR-PRO-11 | Profile view history, activity log, bookmarks (docket tier 2) | S | Deferred | |
| FR-PRO-12 | Assessments, courses, projects | C | Deferred | |

## Job requirements (JOB)

| ID | Requirement | Pri | Status | Verified by |
|---|---|---|---|---|
| FR-JOB-01 | Post a job: title, description (language recorded), employment type, work mode, industry, experience range, salary range or "not disclosed", positions, locations, skills | M | Built | t02 (salary, experience) |
| FR-JOB-02 | Lifecycle: draft → open → paused / closed / filled; a published job cannot return to draft | M | Built | `ck_job_requirement_published`, t02 |
| FR-JOB-03 | Publishing costs credits, charged exactly once | M | Built | `job_requirement_charge_posting` |
| FR-JOB-04 | A screening questionnaire is attached to a job | M | Built | V007 |
| FR-JOB-05 | A job can be opened to consultants | M | Built | t02 (consultant refused otherwise) |
| FR-JOB-06 | Job search by words, city and salary, newest first | M | Built | AP-01 |
| FR-JOB-07 | A closing date stops new applications | S | Built | `application_guard` |
| FR-JOB-08 | A job becomes filled when all positions are joined; joins beyond positions are refused | S | Built | t02, t04 race |

## Applications and pipeline (APP)

| ID | Requirement | Pri | Status | Verified by |
|---|---|---|---|---|
| FR-APP-01 | A candidate applies once per job, optionally with one of their own resume versions | M | Built | t02 (composite key) |
| FR-APP-02 | Answers are only to the questions of the job applied for | M | Built | t02 (composite key) |
| FR-APP-03 | Applications only to open, published jobs, before the closing date | M | Built | t02 |
| FR-APP-04 | The pipeline allows only the listed moves; anything else is refused | M | Built | `application_status_transition`, t02, t05 R-05 |
| FR-APP-05 | A candidate can only withdraw; every other move belongs to the employer side | M | Built | t03 |
| FR-APP-06 | Every status change is kept in an append-only history with time and actor | M | Built | trigger, t05 R-04 |
| FR-APP-07 | Recruiter pipeline per job; candidate's application list in their language | M | Built | AP-02, AP-03 |
| FR-APP-08 | Each status change notifies the candidate | S | Built | outbox trigger, t02 |
| FR-APP-09 | Interviews, offer letters | C | Deferred | |

## Subscriptions, wallet and payments (BIL)

| ID | Requirement | Pri | Status | Verified by |
|---|---|---|---|---|
| FR-BIL-01 | Plans with price, period, seats, devices per user and included credits | M | Built | V008 |
| FR-BIL-02 | A subscription is the licence: periods never overlap per organisation; renewals chain; cancellation never deletes | M | Built | exclusion constraint, t02 |
| FR-BIL-03 | One wallet per organisation; an append-only ledger; the balance never goes negative | M | Built | t02, t04 race, t05 R-01..R-03 |
| FR-BIL-04 | Payment orders with gateway webhooks: idempotent, amount-checked, ordered status changes | M | Built | `billing_apply_payment_event`, t02 |
| FR-BIL-05 | A profile download costs one credit; repeating it within 30 days is free; the history keeps who, whom, when and which debit | M | Built | `billing_download_profile`, t03, t05 R-10 |
| FR-BIL-06 | Contact details are released only after a download, and every release is audited | M | Built | `candidate_contact`, t03 |
| FR-BIL-07 | A GST invoice for every captured payment; a refund reverses the credits it granted | M | Built | t02, t05 R-08 |
| FR-BIL-08 | Outreach consumes credits | S | Partial | ledger type exists; outreach module deferred |
| FR-BIL-09 | Wallet statement | M | Built | AP-08 |

## Notifications and preferences (NOT)

| ID | Requirement | Pri | Status | Verified by |
|---|---|---|---|---|
| FR-NOT-01 | Preferences per category and channel; an opt-out is respected, except security notices | M | Built | t02 |
| FR-NOT-02 | Reliable delivery: written in the same transaction as the event, retried with backoff, provider status recorded | M | Built | `notification_claim`, AP-13 |
| FR-NOT-03 | In-app inbox | S | Built | AP-10 |
| FR-NOT-04 | Language preference drives UI labels | M | Built | AP-02 |
| FR-NOT-05 | Job alert digests | S | Built | seed, V009 |

## Audit and errors (AUD)

| ID | Requirement | Pri | Status | Verified by |
|---|---|---|---|---|
| FR-AUD-01 | Every sensitive action is recorded with actor, organisation, action, row and time; the trail is append-only and cannot be forged | M | Built | triggers, `audit_log`, t02, t03 |
| FR-AUD-02 | Account admins read their organisation's trail; staff read all | M | Built | t03 |
| FR-AUD-03 | System errors are logged with a retention period | S | Built | `system_error` |

## Analytics (ANA)

| ID | Requirement | Pri | Status | Verified by |
|---|---|---|---|---|
| FR-ANA-01 | Employer hiring funnel by month: applied → joined, median days to join, only the own organisation | S | Built | `employer_hiring_funnel`, t03, AP-14 |
| FR-ANA-02 | The KPI star schema of docket section 8 | S | Deferred | v1 Phase 4 design reusable |

## Deferred modules (designed at conceptual level, see [04](04-conceptual-model.md#4-deferred-subject-areas))

| ID | Requirement | Pri (docket) | Status |
|---|---|---|---|
| FR-GIG-01..07 | Gig marketplace: requests with window and price, gig worker profiles and availability, applications accepted or rejected by the requester, assignments with handoff reference, favourites and blacklists, ratings, earnings from the fulfilment system | M | Deferred: separate subsystem (ADR-013) |
| FR-SRC-01..04 | Sourcing requests, consultant acceptance or decline, bulk outreach batches and recipients, sourcing shortlists | M | Deferred |
| FR-COM-01..04 | Community posts and reactions, support tickets, FAQs, referral events | S | Deferred |
