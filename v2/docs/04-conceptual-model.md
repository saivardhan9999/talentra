# 04 — Conceptual model

Level 1 of the three-level model: **what the business deals with and how the things relate.** No columns, no types, no technology. Entities are business concepts named in the language of [00](00-scope.md#7-glossary); the logical model ([05](05-logical-model.md)) gives them attributes and keys, and the physical model ([06](06-physical-model.md)) builds them in PostgreSQL.

## 1. Subject areas

```mermaid
flowchart LR
  REF[Reference data<br/>geography, skills, languages,<br/>enumerations, UI labels]
  IAM[Identity and access<br/>users, roles, consent,<br/>devices, sessions]
  ORG[Organisation<br/>companies, offices,<br/>tax ids, members]
  PRO[Candidate profile<br/>profile, education, work,<br/>skills, resumes, blocks]
  JOB[Jobs and applications<br/>postings, questions,<br/>applications, pipeline]
  BIL[Billing and licences<br/>plans, subscriptions, wallet,<br/>payments, downloads]
  NOT[Notifications<br/>preferences, alerts, outbox]
  AUD[Audit<br/>sensitive actions, errors]
  ANA[Analytics<br/>hiring funnel]
  IAM --> ORG & PRO
  ORG --> JOB & BIL
  PRO --> JOB
  BIL -. contact access .-> PRO
  JOB --> NOT & ANA
  IAM & ORG & PRO & JOB & BIL -.-> AUD
  REF -.-> IAM & ORG & PRO & JOB
```

## 2. Core entity–relationship diagram

```mermaid
erDiagram
    USER ||--o| CANDIDATE : "is (if a candidate)"
    USER ||--o{ ROLE_GRANT : holds
    USER ||--o{ CONSENT : gives
    USER ||--o{ DEVICE : "logs in from"
    DEVICE ||--o{ SESSION : opens
    USER ||--o{ MEMBERSHIP : "works through"
    ORGANISATION ||--o{ MEMBERSHIP : employs
    ORGANISATION |o--o{ ORGANISATION : "parent of"
    ORGANISATION ||--o{ OFFICE : has
    ORGANISATION ||--o{ TAX_IDENTIFIER : "registered with"
    CANDIDATE ||--o{ EDUCATION : studied
    CANDIDATE ||--o{ WORK_EXPERIENCE : worked
    CANDIDATE ||--o{ CANDIDATE_SKILL : has
    SKILL ||--o{ CANDIDATE_SKILL : "known as"
    CANDIDATE ||--o{ RESUME : uploads
    CANDIDATE ||--o{ BLOCK : places
    BLOCK }o--o| ORGANISATION : "hides from"
    BLOCK }o--o| USER : "hides from"
    CANDIDATE ||--o{ JOB_ALERT : saves
    ORGANISATION ||--o{ JOB_REQUIREMENT : posts
    JOB_REQUIREMENT ||--o{ SCREENING_QUESTION : asks
    JOB_REQUIREMENT }o--o{ SKILL : requires
    JOB_REQUIREMENT }o--o{ CITY : "located in"
    CANDIDATE ||--o{ APPLICATION : submits
    JOB_REQUIREMENT ||--o{ APPLICATION : receives
    APPLICATION |o--o| RESUME : attaches
    APPLICATION ||--o{ ANSWER : contains
    SCREENING_QUESTION ||--o{ ANSWER : "answered by"
    APPLICATION ||--|{ STATUS_CHANGE : "moves through"
    PLAN ||--o{ SUBSCRIPTION : "sold as"
    ORGANISATION ||--o{ SUBSCRIPTION : "licensed by"
    ORGANISATION ||--|| WALLET : owns
    WALLET ||--o{ LEDGER_ENTRY : records
    ORGANISATION ||--o{ PAYMENT_ORDER : places
    PAYMENT_ORDER ||--o{ PAYMENT_EVENT : "confirmed by"
    PAYMENT_ORDER ||--o| INVOICE : billed
    PAYMENT_ORDER |o--o| SUBSCRIPTION : buys
    ORGANISATION ||--o{ PROFILE_DOWNLOAD : makes
    CANDIDATE ||--o{ PROFILE_DOWNLOAD : "subject of"
    LEDGER_ENTRY ||--o| PROFILE_DOWNLOAD : "pays for"
    USER ||--o{ NOTIFICATION : receives
    USER ||--o{ PREFERENCE : sets
    USER |o--o{ AUDIT_EVENT : performs
```

## 3. Entity definitions and business rules

| Entity | Definition | Key business rules |
|---|---|---|
| User | anyone who can sign in | email identifies one account; contact details are personal; erased users keep no personal data (BR-01) |
| Candidate | a user looking for work | registers themselves only (BR-02); controls visibility (BR-03) and blocks (BR-04) |
| Role grant | what a user may do | permissions belong to roles; checked by the database (BR-05) |
| Consent | a user's yes or no to one purpose, at one policy version | a history; the latest record per purpose is current (BR-06) |
| Device / Session | where and when a user is signed in | active sessions per user ≤ the licence's devices per user; refusals audited (BR-07) |
| Organisation | an employer or client company | may belong to a group (a tree, no cycles); verified by staff |
| Membership | a user working for an organisation, from–to | one organisation at a time (BR-08); current members ≤ licence seats (BR-09) |
| Tax identifier | GSTIN, PAN, CIN… of an organisation | never stored in clear; unique per country and type (BR-10) |
| Job requirement | positions to fill, posted by an organisation | draft until published; publishing costs credits once (BR-11); filled when all positions are joined (BR-12) |
| Application | a candidate's bid for one job | one per candidate per job; only to open jobs (BR-13); allowed moves only (BR-14); the candidate may only withdraw (BR-15) |
| Status change | one move of an application | append-only; the full history explains every status (BR-16) |
| Plan / Subscription | what an organisation buys / the period it bought | the subscription is the licence; periods never overlap (BR-17) |
| Wallet / Ledger entry | an organisation's credits / one movement | the balance never goes negative; entries are never changed, only reversed (BR-18) |
| Payment order / event | money asked for / the gateway's confirmations | each gateway event is applied at most once (BR-19); capture grants credits or a period, plus an invoice |
| Profile download | an organisation buying access to a candidate's contact details | 1 credit; free again within 30 days; contact details only through a download (BR-20) |
| Notification | a message owed to a user | created with the event it reports (BR-21); opt-outs respected except security notices |
| Audit event | a record of a sensitive action | append-only; the actor cannot be forged (BR-22) |

The rules BR-01..BR-22 are realised in [06 §3–4](06-physical-model.md#3-constraints-and-rules) and traced to tests in [07](07-traceability.md).

## 4. Deferred subject areas

Designed at this level only, so that the core leaves room for them; built later ([08](08-gaps-and-next-steps.md)).

```mermaid
erDiagram
    ORGANISATION ||--o{ GIG_REQUEST : "requests (as requester)"
    USER ||--o| GIG_WORKER : "is (if a gig worker)"
    GIG_WORKER ||--o{ AVAILABILITY_WINDOW : offers
    GIG_WORKER ||--o{ SERVICE_OFFERING : sells
    GIG_REQUEST ||--o{ GIG_APPLICATION : receives
    GIG_WORKER ||--o{ GIG_APPLICATION : submits
    GIG_APPLICATION ||--o| GIG_ASSIGNMENT : "accepted into"
    GIG_ASSIGNMENT ||--o{ EARNINGS_REFERENCE : "reconciled from fulfilment"
    GIG_ASSIGNMENT ||--o| GIG_RATING : "rated by requester"
    ORGANISATION ||--o{ WORKER_LIST_ENTRY : "favourites / blacklists"
    JOB_REQUIREMENT ||--o{ SOURCING_REQUEST : "consultants ask to source"
    CONSULTANT ||--o{ SOURCING_REQUEST : raises
    ORGANISATION ||--o{ OUTREACH_BATCH : sends
    OUTREACH_BATCH ||--o{ OUTREACH_RECIPIENT : targets
    CANDIDATE ||--o{ OUTREACH_RECIPIENT : "contacted as"
    USER ||--o{ COMMUNITY_POST : writes
    COMMUNITY_POST ||--o{ REACTION : gets
    USER ||--o{ SUPPORT_TICKET : opens
```

**Gig decision (ADR-013):** gigs are a separate subsystem, not a kind of job requirement. Gigs have windows, prices, a request–accept flow with no bidding, external fulfilment and ratings; forcing them into `job_requirement` / `application` would make most columns conditional. They share identity, organisation, reference data, the wallet and the audit trail with the core.
