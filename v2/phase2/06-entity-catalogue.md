# Step 06 — Entities Discovery (entity catalogue)

Reconciled directly against the PostgreSQL physical DDL (`db/migrations/V001..V013`) with zero catalog drift.

Conforms to schema [S-06](schemas.md#s-06--entities-discovery). Entities were found by extracting the nouns of the requirements register, the feature inventory and the workflow maps (Phase 1), merging synonyms and moving properties to attributes. Every entity has an ID (ENT-nn) that steps 07–12 use.

**Size:** 51 entities in the v2 core (17 of them hidden: history, audit, configuration or derived), 16 deferred, realised by 73 tables (25 of them enumeration lookups).

## 1. Catalogue

| ID | Entity | Definition | Subject area | Kind | Owner (source of truth) | Delete rule | Physical Table(s) | Base Tables Count |
|---|---|---|---|---|---|---|---|---|
| ENT-01 | **User** | Anyone who can sign in: candidate, organisation staff or Talentra staff. Holds login identity and contact details once. | Identity and access | core | Talentra (identity) | soft delete; erasure blanks contact | `app_user` | 1 |
| ENT-02 | **Credential** | The password hash and lockout state of one user, split off so the runtime role cannot read it at all. | Identity and access | child | Talentra (auth service) | hard delete on erasure | `user_credential` | 1 |
| ENT-03 | **Role** | One of the nine docket actors as a system role (guest has no row). | Identity and access | configuration | Talentra (product) | never deleted; deactivated | `access_role` | 1 |
| ENT-04 | **Permission** | One action on data that a role may be allowed to perform. | Identity and access | configuration | Talentra (product) | never deleted; deactivated | `access_permission` | 1 |
| ENT-05 | **Role permission** | Which permission each role has: the role-permission matrix of step 02, stored as data. | Identity and access | configuration | Talentra (product) | changed by migration | `access_role_permission` | 1 |
| ENT-06 | **Role grant** | A role held by a user. | Identity and access | child | Talentra (admin) | hard delete (audited) | `user_access_role` | 1 |
| ENT-07 | **Consent record** | One yes or no from a user to one purpose at one policy version. The latest record per purpose is the current consent. | Identity and access | history | the user | never deleted (evidence) | `consent_record` | 1 |
| ENT-08 | **Device** | A client device a user has signed in from, identified by a hash of its fingerprint. | Identity and access | child | the user | hard delete with the user | `user_device` | 1 |
| ENT-09 | **Session** | One signed-in period on one device. Active sessions count against the device limit. | Identity and access | history | Talentra (auth service) | deleted 1 year after it ends | `user_session` | 1 |
| ENT-10 | **Organisation** | An employer or client company, possibly part of a group. | Organisation | core | the organisation (verification: registry) | soft delete | `organisation` | 1 |
| ENT-11 | **Office location** | An office of an organisation; at most one headquarters. | Organisation | child | the organisation | hard delete | `organisation_location` | 1 |
| ENT-12 | **Tax identifier** | A GSTIN, PAN, CIN, VAT or EIN of an organisation, kept only as a keyed hash plus the last four characters. | Organisation | child | company registry (reference) | hard delete with the organisation | `organisation_tax_identifier` | 1 |
| ENT-13 | **Membership** | A user working for an organisation over a period, in the role account admin, employer or recruiter. | Organisation | history | the organisation (account admin) | never deleted; closed by valid_to | `organisation_member` | 1 |
| ENT-14 | **Candidate profile** | The job-seeking side of a user: name, headline, city, experience, salary expectation, visibility. | Candidate profile | core | the candidate | soft delete; erasure anonymises | `candidate_profile` | 1 |
| ENT-15 | **Education** | One qualification a candidate studied for. | Candidate profile | child | the candidate | hard delete | `candidate_education` | 1 |
| ENT-16 | **Work experience** | One job a candidate held; at most one current. | Candidate profile | child | the candidate | hard delete | `candidate_experience` | 1 |
| ENT-17 | **Candidate skill** | A skill a candidate has, with proficiency and experience. | Candidate profile | child | the candidate | hard delete | `candidate_skill` | 1 |
| ENT-18 | **Candidate language** | A language a candidate speaks, with proficiency. | Candidate profile | child | the candidate | hard delete | `candidate_language` | 1 |
| ENT-19 | **Resume** | One version of a resume file; at most one primary. | Candidate profile | child | the candidate (file in object storage) | hard delete; file deleted via the outbox | `resume` | 1 |
| ENT-20 | **Block** | A candidate hiding from one company or one person. | Candidate profile | history | the candidate | never deleted; lifted by unblocked_at | `candidate_block` | 1 |
| ENT-21 | **Job alert** | A saved search that sends matching new jobs at a chosen frequency. | Notifications | child | the candidate | hard delete | `job_alert` | 1 |
| ENT-22 | **Job requirement** | Positions to fill, posted by an organisation: a job posting. | Jobs and applications | core | the employer | soft delete | `job_requirement` | 1 |
| ENT-23 | **Job location** | A city a job is located in (a job can have several). | Jobs and applications | child | the employer | hard delete | `job_requirement_location` | 1 |
| ENT-24 | **Required skill** | A skill a job asks for, mandatory or nice to have. | Jobs and applications | child | the employer | hard delete | `job_requirement_skill` | 1 |
| ENT-25 | **Screening question** | A question every applicant to the job answers. | Jobs and applications | child | the employer | hard delete | `screening_question` | 1 |
| ENT-26 | **Application** | One candidate's bid for one job, moving through the pipeline. | Jobs and applications | core | candidate (submits) · employer (moves) | kept; anonymised by erasure | `application` | 1 |
| ENT-27 | **Answer** | An applicant's answer to one screening question. | Jobs and applications | child | the candidate | deleted with the application | `application_answer` | 1 |
| ENT-28 | **Status change** | One move of an application from one status to another, with time and actor. | Jobs and applications | history | Talentra (written by trigger) | never deleted (append-only) | `application_status_history` | 1 |
| ENT-29 | **Allowed transition** | A pipeline or job lifecycle move the database allows. Anything not listed is refused. | Jobs and applications | configuration | Talentra (product) | changed by migration | `application_status_transition`, `job_status_transition` | 2 |
| ENT-30 | **Plan** | A product sold: price, period, seats, devices per user, included credits. | Billing and licences | reference | Talentra (product) | never deleted; deactivated | `plan` | 1 |
| ENT-31 | **Subscription (licence)** | One paid period of a plan for an organisation. It is the licence: seats and devices per user, copied at purchase. | Billing and licences | history | Talentra (billing) | never deleted; cancelled | `subscription` | 1 |
| ENT-32 | **Wallet** | An organisation's credit balance (one per organisation). | Billing and licences | core | the organisation | never deleted | `wallet` | 1 |
| ENT-33 | **Ledger entry** | One signed credit movement in a wallet: recharge, grant, debit or reversal. | Billing and licences | history | Talentra (billing) | never deleted (append-only) | `wallet_ledger_entry` | 1 |
| ENT-34 | **Payment order** | Money asked from an organisation for a recharge or a subscription. | Billing and licences | core | Talentra (order) · gateway (status) | never deleted (8 years) | `payment_order` | 1 |
| ENT-35 | **Payment event** | One gateway webhook exactly as received; the evidence behind every payment status. | Billing and licences | history | payment gateway | never deleted (append-only) | `payment_event` | 1 |
| ENT-36 | **Invoice** | The GST invoice for one captured payment. | Billing and licences | history | Talentra (finance) | never deleted (append-only) | `invoice` | 1 |
| ENT-37 | **Profile download** | An organisation buying 30 days of access to one candidate's contact details, with the credit debit that paid for it. | Billing and licences | history | Talentra (billing) | never deleted (append-only) | `profile_download` | 1 |
| ENT-38 | **Notification preference** | A user's explicit choice for one category on one channel; no row means the default. | Notifications | child | the user | hard delete | `notification_preference` | 1 |
| ENT-39 | **Notification** | A message owed to a user: the outbox row, written with the business change it reports. | Notifications | core | Talentra (status from the provider) | deleted 180 days after final status | `notification` | 1 |
| ENT-40 | **Audit event** | A record of one sensitive action: who, which organisation, what, which row, when. | Audit | audit | Talentra (compliance) | monthly partition dropped after 7 years | `audit_event` | 1 |
| ENT-41 | **System error** | An application error, for operations. | Audit | audit | Talentra (engineering) | deleted after 90 days | `system_error` | 1 |
| ENT-42 | **Hiring funnel month** | An organisation's applications in one month and how far they got, from applied to joined. | Analytics | derived | Talentra (derived) | rebuilt on refresh | `agg_hiring_funnel_monthly` | 0 |
| ENT-43 | **Language** | A language for UI labels, profiles and content. | Reference data | reference | Talentra (migrations) | never deleted; deactivated | `language` | 1 |
| ENT-44 | **UI label** | A key that identifies one UI string; never shown to users. | Reference data | reference | Talentra (migrations) | never deleted | `ui_label` | 1 |
| ENT-45 | **UI translation** | The text of one UI label in one language. | Reference data | reference | Talentra (localisation) | replaced by migration | `ui_translation` | 1 |
| ENT-46 | **Currency** | A currency money amounts are stated in. | Reference data | reference | ISO 4217 (migrations) | never deleted; deactivated | `currency` | 1 |
| ENT-47 | **Country** | A country, with its phone code and currency. | Reference data | reference | ISO 3166 (migrations) | never deleted; deactivated | `country` | 1 |
| ENT-48 | **State** | A state or region of a country. | Reference data | reference | Talentra (migrations) | never deleted | `state` | 1 |
| ENT-49 | **City** | A city with its coordinates. | Reference data | reference | Talentra (geocoder for coordinates) | never deleted; deactivated | `city` | 1 |
| ENT-50 | **Skill** | A skill in the shared taxonomy that candidates and jobs refer to. | Reference data | reference | Talentra (taxonomy) | never deleted; deactivated | `skill` | 1 |
| ENT-51 | **Enumeration value** | One value of a fixed list (23 lists): code, translated label, active flag, sort order. | Reference data | reference | Talentra (migrations) | never deleted; deactivated | `account_status`, `verification_status`, `employment_type`, `work_mode`, `industry`, `qualification`, `proficiency_level`, `salary_disclosure`, `profile_visibility`, `consent_purpose`, `tax_identifier_type`, `job_status`, `application_status`, `application_source`, `answer_type`, `ledger_entry_type`, `payment_purpose`, `payment_status`, `notification_channel`, `notification_category`, `notification_status`, `alert_frequency`, `session_end_reason` | 23 |

### 1.A Entity-to-Physical-Table Reconciliation (51 Logical Entities → 73 Physical Base Tables + 1 Materialized View)

| Logical Entity Group | Entity IDs | Entity Count | Physical Realisation in PostgreSQL (`public` schema) | Base Tables (`pg_class`) | Views / MatViews |
|---|---|---|---|---|---|
| Single-table Business & Reference Entities | `ENT-01..02`, `ENT-05..28`, `ENT-30..41`, `ENT-43..50` | 46 | 1 physical base table per entity (`app_user` .. `skill`) | **46** | 0 |
| State-Machine Transition Tables | `ENT-29` (Allowed transition) | 1 | 2 physical tables: `application_status_transition` (`V007`) + `job_status_transition` (`V013`) | **2** | 0 |
| Dedicated Security Lookup Entities | `ENT-03` (Role), `ENT-04` (Permission) | 2 | 2 lookup tables: `access_role`, `access_permission` (`V002`) | **2** | 0 |
| Grouped Enumeration Lookup Category | `ENT-51` (Enumeration value) | 1 | 23 enumeration lookup tables (`account_status` .. `session_end_reason` in `V002`) | **23** | 0 |
| Analytical Aggregation Entity | `ENT-42` (Hiring funnel month) | 1 | Materialized view `agg_hiring_funnel_monthly` + security-barrier view `employer_hiring_funnel` (`V012`) | **0** | **1 MatView (+2 Views)** |
| **Total Reconciled** | **`ENT-01` .. `ENT-51`** | **51 Entities** | **48 Business/Ref/Config Tables + 25 Lookup Tables = 73 Base Tables** | **73 Base Tables** | **1 MatView (+2 Views)** |

**Kinds.** *core*: the business revolves around it. *child*: belongs to one core entity. *history*: records facts over time, never rewritten. *audit*: evidence of actions. *configuration*: rules stored as data. *reference*: shared lists. *derived*: computed from other entities.

## 2. Hidden entities (the playbook's "go deeper")

Entities nobody names in a brief, but the platform cannot work or prove anything without them:

| ID | Entity | Kind | Why it must exist |
|---|---|---|---|
| ENT-05 | Role permission | configuration | the role–permission matrix of step 02, enforceable by the database |
| ENT-07 | Consent record | history | DPDP Act 2023 needs proof of what was agreed, when, at which policy version; a flag on the user would lose history |
| ENT-09 | Session | history | the device limit (rule group 9) counts active sessions; revocation needs a row to end |
| ENT-13 | Membership | history | seats count current members; who worked where, and when, must survive leaving |
| ENT-20 | Block | history | blocking must hide the candidate from a company without the company ever seeing a row |
| ENT-28 | Status change | history | the pipeline rules, time-to-hire and the funnel all need every move, not just the current status |
| ENT-29 | Allowed transition | configuration | allowed moves as data: a new stage is a row, not a code change |
| ENT-31 | Subscription (licence) | history | the licence: limits must not change when a plan is repriced, so each sold period is kept |
| ENT-33 | Ledger entry | history | money is never edited: a balance must be explainable entry by entry (rule group 10) |
| ENT-35 | Payment event | history | webhooks arrive twice and out of order; the raw evidence makes them idempotent and auditable |
| ENT-37 | Profile download | history | docket rule group 10: download history with actor, subject, time and the credit debit |
| ENT-40 | Audit event | audit | docket §3: every sensitive action audited, append-only |
| ENT-41 | System error | audit | operations need errors in one place with a retention period |
| ENT-42 | Hiring funnel month | derived | dashboards must not scan 100M applications on every view |
| ENT-44 | UI label | reference | rule group 7: UI strings by key, translated per language |

## 3. Synonyms merged

| Entity kept | Words found in the sources | Decision |
|---|---|---|
| job requirement | job, posting, vacancy, opening | the docket term; one entity |
| subscription (licence) | licence, plan purchase, package | the licence is the subscription period (ADR-005); no separate licence entity |
| membership | recruiter mapping, employee, seat | a user working for an organisation; a seat is one current membership |
| user | account, login, member | one sign-in identity for every actor; roles say what they can do |
| candidate profile | job seeker, applicant, talent | the job-seeking side of a user; "applicant" is a candidate with an application |
| profile download | unlock, contact purchase, profile view (paid) | buying 30 days of access to contact details |
| notification | message, alert delivery, outbox row | a message owed to a user; a job alert is the saved search, not the message |
| ledger entry | credit transaction, debit, top-up | every credit movement is one signed entry |
| organisation | company, employer (as a company), client | "employer" is also a role, so the company is called organisation |

## 4. Nouns that are attributes, not entities

| Noun | Became | Reason |
|---|---|---|
| salary (expected, offered) | attribute | amount + currency + a disclosure code on the profile or job; never shared or searched on its own |
| phone, email | attribute of user | one of each per user in the docket; a second phone would make them an entity |
| address | attribute of office location | not reused across entities |
| status values | enumeration value (ENT-51) | fixed lists with translated labels, not things with a life of their own |
| headline, summary | attribute of candidate profile | one per profile |
| skill | entity (ENT-50), not text | shared by candidates and jobs, searched and typed ahead: a free-text column would fragment it |
| job city | entity (ENT-23) | a job has several cities: a multi-valued attribute becomes its own relation |
| wallet balance | derived attribute of wallet | the sum of the ledger, cached for the debit check |

## 5. Deferred entities (designed at conceptual level, no table in v2)

| ID | Entity | Area | Definition |
|---|---|---|---|
| ENT-D01 | Gig request | Gig marketplace | work wanted in a time window, at a fixed price or a rate |
| ENT-D02 | Gig worker | Gig marketplace | the gig side of a user: services, availability, ratings |
| ENT-D03 | Availability window | Gig marketplace | when a gig worker can work; no overlaps per worker |
| ENT-D04 | Service offering | Gig marketplace | a service a gig worker sells |
| ENT-D05 | Gig application | Gig marketplace | a gig worker applying to a request |
| ENT-D06 | Gig assignment | Gig marketplace | an accepted application handed to the fulfilment system |
| ENT-D07 | Earnings reference | Gig marketplace | earnings reconciled from the fulfilment system |
| ENT-D08 | Gig rating | Gig marketplace | the requester's rating of an assignment |
| ENT-D09 | Worker list entry | Gig marketplace | an organisation's favourite or blacklisted worker |
| ENT-D10 | Sourcing request | Sourcing | a consultant asking to source for a job open to consultants |
| ENT-D11 | Outreach batch | Sourcing | a bulk message campaign to candidates, paid in credits |
| ENT-D12 | Outreach recipient | Sourcing | one candidate in an outreach batch and their response |
| ENT-D13 | Community post | Community | a post in the community feed, with reactions |
| ENT-D14 | Support ticket | Community | a user request handled by support |
| ENT-D15 | Identity verification | Identity and access | national-id check outcome and token, never the number (docket §6) |
| ENT-D16 | Share event | Integration | an outbound share of a job to a social network (docket §6) |

## 6. Workflow coverage: every workflow step reads or writes a named entity

C = create, R = read, U = update, D = delete. Steps come from [Phase 1 step 05](../stage1/05-business-workflows.md); "PLATFORM" lists cross-cutting processes so that every entity is accounted for.

### WF-01 Candidate registration and profile building

| Step | What happens | Actor | Entities touched |
|---|---|---|---|
| 01.1 | Guest signs up with email, phone and password | candidate | ENT-01 User (C), ENT-02 Credential (C), ENT-06 Role grant (C), ENT-14 Candidate profile (C) |
| 01.2 | Terms and privacy consent recorded with the policy version | candidate | ENT-07 Consent record (C) |
| 01.3 | Adds education, work history, skills and languages | candidate | ENT-15 Education (CUD), ENT-16 Work experience (CUD), ENT-17 Candidate skill (CUD), ENT-18 Candidate language (CUD), ENT-50 Skill (R) |
| 01.4 | Uploads resume versions, picks the primary one | candidate | ENT-19 Resume (CU) |
| 01.5 | Sets visibility, salary disclosure and open-to-work | candidate | ENT-14 Candidate profile (U) |
| 01.6 | Saves job alerts | candidate | ENT-21 Job alert (CUD), ENT-49 City (R) |

### WF-02 Employer registration and verification

| Step | What happens | Actor | Entities touched |
|---|---|---|---|
| 02.1 | Employer signs up: user, organisation (pending), wallet, admin membership | employer | ENT-01 User (C), ENT-02 Credential (C), ENT-06 Role grant (C), ENT-10 Organisation (C), ENT-32 Wallet (C), ENT-13 Membership (C), ENT-07 Consent record (C) |
| 02.2 | Adds offices | account admin | ENT-11 Office location (CUD), ENT-49 City (R) |
| 02.3 | Submits a tax identifier (stored as HMAC + last 4) | account admin | ENT-12 Tax identifier (C) |
| 02.4 | Registry result; staff mark the organisation verified or rejected | admin | ENT-10 Organisation (U), ENT-12 Tax identifier (U), ENT-40 Audit event (C) |
| 02.5 | Account admin adds or removes recruiters (seat limit) | account admin | ENT-13 Membership (CU), ENT-31 Subscription (licence) (R), ENT-06 Role grant (C), ENT-40 Audit event (C) |

### WF-03 Job requirement posting

| Step | What happens | Actor | Entities touched |
|---|---|---|---|
| 03.1 | Drafts the job with locations and skills | employer, recruiter | ENT-22 Job requirement (C), ENT-23 Job location (C), ENT-24 Required skill (C), ENT-50 Skill (R), ENT-49 City (R) |
| 03.2 | Adds screening questions | employer, recruiter | ENT-25 Screening question (CUD) |
| 03.3 | Publishes: 5 credits debited once | employer | ENT-22 Job requirement (U), ENT-32 Wallet (U), ENT-33 Ledger entry (C) |
| 03.4 | Pauses or closes the job | employer, recruiter | ENT-22 Job requirement (U), ENT-29 Allowed transition (R) |

### WF-04 Job search and application

| Step | What happens | Actor | Entities touched |
|---|---|---|---|
| 04.1 | Searches open jobs by words, city and salary | candidate, guest | ENT-22 Job requirement (R), ENT-23 Job location (R), ENT-10 Organisation (R) |
| 04.2 | Applies with a resume version and answers | candidate | ENT-26 Application (C), ENT-27 Answer (C), ENT-28 Status change (C), ENT-19 Resume (R), ENT-25 Screening question (R) |

### WF-05 Application pipeline

| Step | What happens | Actor | Entities touched |
|---|---|---|---|
| 05.1 | Recruiter lists applicants by stage | recruiter | ENT-26 Application (R), ENT-14 Candidate profile (R) |
| 05.2 | Recruiter moves an application; candidate notified | recruiter | ENT-26 Application (U), ENT-29 Allowed transition (R), ENT-28 Status change (C), ENT-39 Notification (C) |
| 05.3 | A join fills a position; the job is filled when all are | recruiter | ENT-22 Job requirement (U) |
| 05.4 | Candidate withdraws | candidate | ENT-26 Application (U), ENT-28 Status change (C) |

### WF-06 Candidate sourcing and profile download

| Step | What happens | Actor | Entities touched |
|---|---|---|---|
| 06.1 | Recruiter searches visible candidates by skill, city and experience | recruiter | ENT-14 Candidate profile (R), ENT-17 Candidate skill (R), ENT-20 Block (R) |
| 06.2 | Downloads a profile: 1 credit, free again within 30 days | recruiter | ENT-37 Profile download (CR), ENT-32 Wallet (U), ENT-33 Ledger entry (C), ENT-40 Audit event (C) |
| 06.3 | Contact details revealed; the read is audited | recruiter | ENT-01 User (R), ENT-40 Audit event (C) |

### WF-07 Subscription, recharge and credit use

| Step | What happens | Actor | Entities touched |
|---|---|---|---|
| 07.1 | Account admin buys a plan or a recharge | account admin | ENT-34 Payment order (C), ENT-30 Plan (R) |
| 07.2 | Gateway webhook applied once | payment gateway | ENT-35 Payment event (C), ENT-34 Payment order (U), ENT-40 Audit event (C) |
| 07.3 | Capture grants a period or credits, and an invoice | payment gateway | ENT-31 Subscription (licence) (C), ENT-32 Wallet (U), ENT-33 Ledger entry (C), ENT-36 Invoice (C) |
| 07.4 | Refund reverses the credits it granted | payment gateway | ENT-33 Ledger entry (C), ENT-32 Wallet (U), ENT-31 Subscription (licence) (U) |
| 07.5 | Account admin turns off auto-renew or cancels | account admin | ENT-31 Subscription (licence) (U) |

### WF-08 Login with device limit

| Step | What happens | Actor | Entities touched |
|---|---|---|---|
| 08.1 | Auth service checks the password; failed attempts counted | user | ENT-02 Credential (RU) |
| 08.2 | Expired sessions closed; device registered or recognised | user | ENT-09 Session (U), ENT-08 Device (CU) |
| 08.3 | Device limit checked; a refusal is audited | user | ENT-09 Session (R), ENT-31 Subscription (licence) (R), ENT-13 Membership (R), ENT-40 Audit event (C) |
| 08.4 | Session opened, token stored as a hash | user | ENT-09 Session (C), ENT-01 User (U) |
| 08.5 | Logout or revocation of a session or device | user, admin | ENT-09 Session (U), ENT-08 Device (U), ENT-40 Audit event (C) |

### WF-09 Blocking

| Step | What happens | Actor | Entities touched |
|---|---|---|---|
| 09.1 | Candidate blocks a company or a person | candidate | ENT-20 Block (C), ENT-40 Audit event (C) |
| 09.2 | Candidate lifts the block | candidate | ENT-20 Block (U), ENT-40 Audit event (C) |

### WF-10 Notifications and job alerts

| Step | What happens | Actor | Entities touched |
|---|---|---|---|
| 10.1 | A business change writes a notification; preferences applied | system | ENT-39 Notification (C), ENT-38 Notification preference (R) |
| 10.2 | Worker claims due notifications and sends them | worker | ENT-39 Notification (U) |
| 10.3 | Delivery result recorded; retry with backoff or fail | worker | ENT-39 Notification (U), ENT-41 System error (C) |
| 10.4 | Job alert digest built from new open jobs | scheduler | ENT-21 Job alert (RU), ENT-22 Job requirement (R), ENT-39 Notification (C) |
| 10.5 | User sets notification preferences | user | ENT-38 Notification preference (CUD) |

### WF-14 Data erasure (DPDP Act 2023)

| Step | What happens | Actor | Entities touched |
|---|---|---|---|
| 14.1 | Erasure on request: sections deleted, profile and contact blanked, history kept anonymised | candidate, admin | ENT-14 Candidate profile (U), ENT-15 Education (D), ENT-16 Work experience (D), ENT-17 Candidate skill (D), ENT-18 Candidate language (D), ENT-19 Resume (D), ENT-21 Job alert (D), ENT-26 Application (U), ENT-39 Notification (C), ENT-09 Session (U), ENT-02 Credential (D), ENT-01 User (U), ENT-40 Audit event (C) |
| 14.2 | Scheduler erases profiles inactive for 3 years | scheduler | ENT-14 Candidate profile (RU) |

### PLATFORM Cross-cutting platform processes

| Step | What happens | Actor | Entities touched |
|---|---|---|---|
| P.1 | Every request: role and permission check | system | ENT-06 Role grant (R), ENT-03 Access role (R), ENT-04 Access permission (R), ENT-05 Role permission (R) |
| P.2 | Screens render labels in the user language, falling back to English | system | ENT-44 UI label (R), ENT-45 UI translation (R), ENT-43 Language (R) |
| P.3 | Forms offer lookup values, countries, states and currencies | system | ENT-47 Country (R), ENT-48 State (R), ENT-46 Currency (R) |
| P.4 | Hourly refresh of the hiring funnel; employer dashboard reads it | scheduler, employer | ENT-42 Hiring funnel month (CR), ENT-28 Status change (R) |
| P.5 | Admins and account admins review the audit trail | admin, account admin | ENT-40 Audit event (R) |
| P.6 | Services log errors; retention job deletes old rows | system | ENT-41 System error (CD) |

### Coverage check

- **Steps:** 49; steps touching no entity: **0** (the exit test of step 06 needs 0).
- **Entities with no workflow or platform step:** none. Enumeration values (ENT-51) are read by every form.
- **Entity × step cells filled:** 134.
