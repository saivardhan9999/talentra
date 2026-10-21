# 03 — Data requirements

What data the platform holds, how much, how it is read and written, how long it is kept, where it comes from, and what "good data" means. This document drives the model: every index in [06](06-physical-model.md) exists for an access pattern listed here.

## 1. Data entity inventory

Highest class = the most sensitive column of the entity (docket rule group 6). Volume: rows at dev scale (measured), then full scale (projected, §3).

| Subject area | Entity | Holds | Owner (source of truth) | Highest class | Dev rows | Full-scale rows |
|---|---|---|---|---|---|---|
| Identity | app_user | login identity, contact, language, status | Talentra | Personal | 10,603 | 10.6M |
| | user_credential | argon2id password hash, lockout | Talentra | Sensitive | 10,543 | 10.6M |
| | user_access_role | role grants | Talentra | Internal | 10,603 | 10.6M |
| | consent_record | consent history per purpose | Talentra | Personal | 40,793 | 40M |
| | user_device, user_session | trusted devices, sessions (login history) | Talentra | Sensitive | 16.7k / 36.3k | 17M / 36M (1-year retention) |
| Organisation | organisation | company, hierarchy, verification | Talentra (verification: registry) | Public | 200 | 200k |
| | organisation_location | offices, coordinates | Talentra (geocoder) | Public | 200 | 300k |
| | organisation_tax_identifier | tokenised GSTIN / PAN / CIN | registry (reference) | Sensitive | 200 | 200k |
| | organisation_member | effective-dated recruiter mapping | Talentra | Internal | 559 | 600k |
| Profile | candidate_profile | profile core | candidate | Personal | 10,000 | 10M |
| | candidate_education / experience / skill / language | profile sections | candidate | Personal | 96k | 96M |
| | resume | file reference, checksum, version | candidate (file in object storage) | Personal | 10.6k | 10.6M |
| | candidate_block | blocks of companies or people | candidate | Internal | 229 | 230k |
| | job_alert | saved searches | candidate | Personal | 3,044 | 3M |
| Jobs | job_requirement (+ location, skill, screening_question) | postings | employer | Public | 1,050 (+5.2k) | 1M (+5M) |
| Applications | application | one candidate × one job | candidate / employer | Personal | 56,123 | 100M |
| | application_answer | screening answers | candidate | Personal | 39,114 | 70M |
| | application_status_history | pipeline history, append-only | Talentra | Internal | 117,088 | 210M |
| Billing | plan | product catalogue | Talentra | Public | 3 | ~10 |
| | subscription | licence periods | Talentra | Internal | 806 | 800k |
| | wallet, wallet_ledger_entry | credits, append-only ledger | Talentra | Internal | 200 / 5,201 | 200k / 5M |
| | payment_order, payment_event | orders, gateway webhooks | payment gateway (status), Talentra (order) | Sensitive | 893 / 1.7k | 900k / 1.7M |
| | invoice | GST invoices, append-only | Talentra | Internal | 897 | 900k |
| | profile_download | who downloaded whom, for which debit | Talentra | Internal | 3,330 | 3.3M |
| Notifications | notification_preference | opt-outs | user | Internal | 2,853 | 2.9M |
| | notification | outbox and delivery status | Talentra (status from provider) | Internal | 73,141 | 73M (180-day retention) |
| Audit | audit_event | sensitive actions, append-only, monthly partitions | Talentra | Internal | 35,981 | ~45M per year |
| | system_error | application errors | Talentra | Internal | 500 | 90-day window |
| Reference | 35 tables (geography, currencies, languages, skills, UI labels, 25 lookups) | | Talentra (migrations) | Public | ~600 | ~5k |

## 2. Data classification summary

| Class | Examples | Handling |
|---|---|---|
| **Public** | job posts, organisation names, locations | readable by anyone, including guests (open jobs only) |
| **Internal** | statuses, ledgers, audit, memberships | own organisation or staff only (RLS) |
| **Personal** | names, email, phone, profile sections, answers, IP addresses | the person; employers only within visibility and blocking; contact details only after a paid download, audited |
| **Sensitive** | password hashes, session tokens, device ids, tax identifiers, gateway references | hashed (argon2id, SHA-256) or tokenised (HMAC + last 4); credentials unreadable by every runtime role |

The class of each column is in the [data dictionary](data-dictionary.md) (generated from column comments; test t01 fails if an identifying column lacks its class).

## 3. Volumetrics and capacity

**Measured at dev scale** (10k profiles; `pg_total_relation_size`, so heap plus indexes plus update churn):

| Table group | Rows | Size | Bytes per row |
|---|---|---|---|
| candidate_profile | 10,000 | 14 MB | 1,427 |
| profile sections (skill, language, education, experience, resume) | 107k | 21 MB | ~2,100 per candidate |
| identity (user, credential, role, consent, device, session) | 126k | 33 MB | ~3,100 per user |
| job_requirement (+ children) | 6.3k | 4.5 MB | 3,542 per job |
| application | 56,123 | 41 MB | 760 |
| application_status_history | 117,088 | 17 MB | 150 |
| application_answer | 39,114 | 6.3 MB | 166 |
| notification | 73,141 | 51 MB | 728 |
| audit_event (24 partitions) | 35,981 | 9.3 MB | 270 |
| **database** | | **217 MB** | |

**Projected to full scale** (10M profiles, 1M jobs, 100M applications), using the measured bytes per row:

| Table group | Full-scale rows | Size |
|---|---|---|
| candidate_profile + sections | 10M + 107M | 35 GB |
| identity | 10.6M users | 33 GB (sessions bounded by 1-year retention) |
| jobs | 1M (+6M children) | 4.5 GB |
| application | 100M | 76 GB (about 40 GB right after VACUUM FULL; the dev figure includes pipeline-update churn) |
| history + answers | 210M + 70M | 43 GB |
| notification (180 days kept) | ~40M live | 30 GB |
| audit_event | ~45M per year | 12 GB per year |
| **total, year one** | | **~235 GB**, within one primary with NVMe; indexes ~40% of it |

**Workload at full scale.** Assumption A-06: 10% daily active users (1M), peak hour five times the average.

| Flow | Daily volume | Average | Peak |
|---|---|---|---|
| job and candidate searches (AP-01, AP-04, AP-05) | 10M | 116/s | **~600/s** |
| logins (AP-11) | 1M | 12/s | 60/s |
| applications (insert + history + notification) | 137k (100M over 2 years) | 1.6/s | 10/s |
| pipeline moves | 290k | 3.4/s | 17/s |
| notifications queued and delivered | 300k | 3.5/s | 15/s |
| downloads and contact reveals | 50k | 0.6/s | 3/s |
| read : write ratio | | ~50 : 1 | |

The writes are light for one PostgreSQL primary. The reads are what scale: they go to read replicas (search, dashboards), and from about 1M profiles free-text name search moves to a search engine (ADR-012).

## 4. Access patterns

Each pattern names its actor (so the benchmark runs through RLS as that actor), its full-scale frequency, its target and the index serving it. Queries are in `bench/queries/`; measured results are in [benchmark-results.md](benchmark-results.md).

| ID | Pattern | Actor | Peak at full scale | Target p95 | Served by |
|---|---|---|---|---|---|
| AP-01 | job search: words + city + salary, newest first | candidate, guest | 300/s | 50 ms | `idx_job_requirement_search_vector` (GIN, partial on open), `idx_job_requirement_location_city_id`, `idx_job_requirement_published_at` |
| AP-02 | my applications with status in my language | candidate | 50/s | 20 ms | `idx_application_candidate_profile_id` |
| AP-03 | applicants of one job by stage | recruiter | 30/s | 20 ms | `idx_application_job_requirement_status` |
| AP-04 | candidate search: skill + city + experience, most recent first | recruiter | 200/s | 100 ms | `idx_candidate_profile_search` (partial: open to work, live, not hidden), `idx_candidate_skill_skill_id` |
| AP-05 | candidate name search, typo-tolerant | recruiter | 100/s | 200 ms | `idx_candidate_profile_full_name_trgm` (see [06 §7](06-physical-model.md#7-performance) on RLS) |
| AP-06 | employer's jobs with applicant counts | employer, admin | 20/s | 50 ms | `idx_job_requirement_organisation_id`, `idx_application_job_requirement_status` |
| AP-07 | contact reveal after download | recruiter | 3/s | 20 ms | `idx_profile_download_candidate_profile_id` |
| AP-08 | wallet statement | account admin | 2/s | 20 ms | `idx_wallet_ledger_entry_wallet_id` |
| AP-09 | skill type-ahead | everyone | 100/s | 10 ms | `idx_skill_name_trgm` |
| AP-10 | notification inbox | user | 100/s | 10 ms | `idx_notification_app_user_id` |
| AP-11 | login: device limit + open session | user | 60/s | 20 ms | `idx_user_session_app_user_id_active` |
| AP-12 | duplicate check by phone at registration | system | 5/s | 10 ms | `idx_app_user_phone_e164` |
| AP-13 | outbox claim, 100 at a time | worker | 1/s per worker | 20 ms | `idx_notification_due` (partial on queued) |
| AP-14 | hiring funnel by month | employer | 10/s | 20 ms | `agg_hiring_funnel_monthly` (materialized, unique index) |

## 5. Retention and lifecycle

| Data | Deleted how | Rule | Mechanism |
|---|---|---|---|
| candidate personal data | erasure (anonymise) | on request (within 30 days); after 3 years of inactivity | `candidate_erase()`, `retention_erase_inactive()` (scheduled daily) |
| applications, history, answers | kept anonymised after erasure | employer's legitimate record; purge after 2 years closed (backlog job) | FK to the anonymous profile |
| jobs, organisations, users | soft delete (`deleted_at`) | hidden from default queries and RLS | soft-delete columns |
| ledgers, payments, invoices, downloads | never | financial records (8 years under Indian tax law) | append-only triggers |
| consent records | never (evidence) | kept with the anonymised user | append-only |
| audit_event | drop monthly partition | 7 years | `create_month_partitions()` ahead; detach + drop behind |
| user_session (ended) | delete | 1 year | scheduled delete |
| notification | delete | 180 days after final status | scheduled delete; monthly partitions from ~10M rows |
| system_error | delete | 90 days | scheduled delete |

## 6. Integration boundaries (docket section 6)

| Boundary | Source of truth | Stored vs referenced | When it is down | Idempotency | Audit |
|---|---|---|---|---|---|
| **Payment gateway** | gateway for payment status; Talentra for orders | order, amounts, gateway order and event ids, payload hash; never card or bank data | orders stay `created`; nothing is granted until a `captured` webhook; reconciliation job polls stale orders | `payment_event.gateway_event_ref` unique; webhook redelivery is a no-op (t02) | every applied status writes `audit_event` (`payment_order.<status>`) |
| **Identity verification** (national id) | verification service | outcome and token only; never the raw number (backlog table `identity_verification`) | candidate stays "unverified"; features needing it are gated | request id unique | verification outcome audited |
| **Company registry / tax verification** | registry | identifier HMAC + last 4, type, country, verification status and time | organisation stays `pending`; it can post (finding F-05 flags this for a product decision) | unique (country, type, HMAC) | trigger `audit_row_change` on the identifier table |
| **Gig fulfilment** (deferred module) | fulfilment system for assignments and earnings | handoff reference, assignment status, reconciled earnings | assignment stays `handed_off`; nightly reconciliation | unique handoff reference | handoff and reconciliation events audited |
| **Legacy job / candidate systems** | Talentra after cut-over; legacy before | one-off migration, then read-only | not a runtime dependency | a natural-key unique constraint per source (`source_system`, `source_record_id`) when ETL lands | migration batches logged |
| **Messaging providers** (email, SMS, WhatsApp) | provider for delivery status | outbox row with template key and variables, provider message id, status; no message body | rows stay `queued`; the worker retries with backoff, up to 5 attempts, then `failed` | `dedupe_key` per event; `provider_message_ref` unique | delivery status kept on the row |
| **Social sharing** | the social network | outbound share events only (backlog) | sharing button disabled | event id | not sensitive |
| **Mapping / geolocation** (optional) | geocoder | latitude and longitude (WGS 84, 6 decimals) with the city | location saved without coordinates (nullable, justified) | not needed (overwrite) | not sensitive |
| **Company reviews / salary data** | provider | reference only, with source and refresh date (backlog, tier 3) | stale data shown with its date | provider record id | not sensitive |

## 7. Data quality: rules, distributions and planted issues

**Seed distributions** (`db/seed/seed.sql`, deterministic):
- **Profiles:** 10k (scalable with `./run.sh seed N`). Names: 85% Latin-script Indian names, 8% Devanagari, 5% Tamil, 2% mononyms. 92% have a phone. Cities are skewed like real hiring (Bengaluru, Mumbai, Hyderabad, Chennai first; 2% abroad). Experience is skewed towards juniors. Salary is 60% disclosed, 25% not disclosed, 15% not provided.
- **Organisations:** 200, with plan mix 60 / 30 / 10 (starter, growth, enterprise). Monthly renewals; 7% churn per period; 4% declined cards before success; 3% webhook redeliveries.
- **Jobs:** 1,000 published plus 50 drafts, from 26 role templates (IT, BFSI, healthcare, manufacturing, retail, logistics); positions 1–25.
- **Applications:** ~56k, skewed towards active seekers and popular jobs. Funnel: 32% applied, 48% rejected, 8% withdrawn, then shortlisted, interviewing, offered; ~3% joined, capped by positions.
- **Also:** sessions and devices (with real refused logins at the device limit), downloads, blocks, preferences, alerts, notifications with delivery outcomes, errors.

**Invariants: must be 0 violations** (test t05). R-01..R-03: wallet equals ledger, and the ledger running sum holds in posting and time order. R-04, R-05: history matches status and uses only allowed transitions. R-06: applications after publication and registration. R-07: positions match joins. R-08, R-09: invoices and subscriptions for captured payments. R-10: every download paid by one credit. R-11: no user over their device limit. R-12: current consent. R-13: candidate role. R-14: every organisation has a wallet and an admin. R-15: applicants use their own resume. R-16: no contact data in notification payloads.

**Planted findings: must be detected** (test t05; real migrated data has them):

| ID | Finding | Dev count | Follow-up |
|---|---|---|---|
| F-01 | probable duplicate candidates (same phone and name) | 91 groups | dedupe key at registration (AP-12), merge tool (backlog) |
| F-02 | profiles without a city | 509 | prompt in the UI; such profiles are excluded from city search |
| F-03 | stated total experience shorter than the work history | 172 | recompute from history, or flag in the UI |
| F-04 | organisations over their seat limit after the subscription lapsed | 37 | product rule: grace period, then deactivate extra members (backlog job) |
| F-05 | open jobs from organisations not yet verified | 62 | product decision: gate publishing on verification |
| F-06 | "open to work" profiles inactive for 90+ days | 21 | auto-expire the flag after 90 days |
