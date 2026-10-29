# Step 11 — Data Rules and Constraints Discovery (data rules catalogue)

Reconciled directly against the PostgreSQL physical DDL (`db/migrations/V001..V013`) with zero catalog drift.

Conforms to schema [S-11](schemas.md#s-11--data-rules-and-constraints-discovery). Every rule has an ID, the table(s) it governs and its **enforcement point**: database (constraint, trigger, function, row-level security, grant), application (API or auth service), or pipeline (scheduler, worker, data generator, ETL). A rule enforced nowhere is marked **Gap** and carries a finding.

## 0. Business Rules Register (BR-01..BR-28 — 28 Explicit Rows)

| Rule ID | Category | Rule Statement | Owner | Phase Introduced | Enforcement Mechanism |
|---|---|---|---|---|---|
| BR-01 | policy & eligibility | Every table uses an integer surrogate key `id`; foreign keys and check constraints are enforced by the database. | Talentra (data architecture) | Phase 1/2 (Steps 01–11) | `PK/FK constraints + `t01_standards.sql`` |
| BR-02 | policy & eligibility | Candidates register themselves (or via staff at a placement drive); recruiters/employers cannot register candidates. Sign-up creates user, credential, candidate role, profile, and mandatory terms + privacy consents in one transaction. | Talentra (identity) | Phase 1/2 (Steps 01–11) | ``auth_register_candidate()`` |
| BR-03 | privacy & consent | A candidate profile is visible to recruiters only when `deleted_at IS NULL`, `profile_visibility_id <> 3` (not hidden), and the candidate currently grants `profile_visible_to_recruiters` consent (purpose 3). | Candidate / Compliance | Phase 1/2 (Steps 01–11) | `RLS `candidate_profile_read`, `app_candidate_visible()`, `app_users_without_recruiter_consent()`` |
| BR-04 | privacy & consent | When a candidate blocks an organisation or user, the blocked party immediately loses visibility of the candidate profile, their applications, and their contact details (even if previously downloaded), and never sees the block row. | Candidate | Phase 1/2 (Steps 01–11) | `RLS on `candidate_profile`, `application`, `candidate_block` + `candidate_contact()`` |
| BR-05 | policy & eligibility | Permissions derive strictly from `user_access_role -> access_role_permission`, and only users with `account_status_id = 1` (`active`) hold any permission. | Talentra (security) | Phase 1/2 (Steps 01–11) | ``app_has_permission()`` |
| BR-06 | privacy & consent | Consent is an append-only history per user and purpose with `policy_version`; the latest record (`consent_current`) governs processing. | Candidate / Compliance | Phase 1/2 (Steps 01–11) | ``consent_record` (append-only) + view `consent_current`` |
| BR-07 | limit & quota | Active sessions per user cannot exceed the device limit (3 for candidates; `subscription.max_devices_per_user` for org members, or 1 without an active subscription). Expired sessions are closed first; revoked devices and over-limit logins are refused and audited. | Talentra (identity) | Phase 1/2 (Steps 01–11) | ``auth_open_session()` with `FOR UPDATE` lock on `app_user` + `auth_revoke_device()`` |
| BR-08 | policy & eligibility | After 5 consecutive failed password checks, the credential is locked for 15 minutes (`locked_until`), audited, and refused by `auth_open_session()`; a successful login resets the counter. | Talentra (auth service) | Phase 1/2 (Steps 01–11) | ``auth_record_login_failure()` + `auth_open_session()`` |
| BR-09 | limit & quota | An organisation has at most `subscription.max_seats` current members (`valid_to IS NULL`) under its active subscription (1 without one). A user belongs to at most one organisation at any point in time, and closed memberships (`valid_to`) are write-once. | Talentra (billing & org) | Phase 1/2 (Steps 01–11) | ``trg_organisation_member_seat_limit` + `ex_organisation_member_one_organisation` + `trg_organisation_member_close_once`` |
| BR-10 | approval & verification | Tax identifiers (GSTIN, PAN, CIN, VAT, EIN) are validated for format, tokenised via `pii_hmac()` + `identifier_last4`, and never stored in clear. Staff verify or reject organisations via `organisation_set_verification()`, recording `verified_at` and an audit event. | Talentra (compliance) | Phase 1/2 (Steps 01–11) | ``pii_hmac()`, `uq_organisation_tax_identifier_country_id_type_hmac`, `organisation_set_verification()`` |
| BR-11 | calculation & pricing | Publishing a job (`draft -> open`) sets `published_at` (write-once) and debits 5 credits from the organisation wallet exactly once (`idempotency_key = job_post:<id>`). Published jobs never return to `draft`; `closed` and `filled` are final. | Talentra (product) | Phase 1/2 (Steps 01–11) | ``trg_job_requirement_guard`, `job_status_transition`, `trg_job_requirement_charge_posting`` |
| BR-12 | limit & quota | Each application moving to `joined` increments `job_requirement.positions_filled` under a job row lock; when `positions_filled = positions_total`, `job_status_id` automatically becomes `filled` (5); joins beyond `positions_total` are refused. | Talentra (product) | Phase 1/2 (Steps 01–11) | ``application_guard()` + `ck_job_requirement_positions`` |
| BR-13 | policy & eligibility | A candidate can apply at most once per job, only while the job is `open` (2), not deleted, and on or before `closes_on`, starting in status `applied` (1). Attached resumes must belong to the candidate; answers must belong to questions of that job. | Candidate / Employer | Phase 1/2 (Steps 01–11) | ``application_guard()`, `uq_application_job_requirement_id_candidate_profile_id`, composite FKs `fk_application_resume`, `fk_application_answer_screening_question`` |
| BR-14 | state transition | Applications move only along the 12 edges in `application_status_transition`; `joined`, `rejected`, and `withdrawn` are final. | Employer / Recruiter | Phase 1/2 (Steps 01–11) | ``application_status_transition` + `application_guard()`` |
| BR-15 | policy & eligibility | A candidate may only transition their own application to `withdrawn` (7); all forward and rejection moves require an unblocked member of the hiring organisation with `application_manage` permission. | Candidate / Recruiter | Phase 1/2 (Steps 01–11) | ``application_guard()` + RLS `application_update`` |
| BR-16 | retention & lifecycle | Every application status change is recorded in `application_status_history` (append-only) with `from_status_id`, `to_status_id`, `changed_at`, and `created_by`. | Talentra (platform) | Phase 1/2 (Steps 01–11) | ``trg_application_record_history` + `forbid_change()`` |
| BR-17 | policy & eligibility | A sold `subscription` is an immutable licence snapshot (`max_seats`, `max_devices_per_user`, `starts_on`, `plan_id` cannot change; `ends_on` cannot be extended; `cancelled_at` is write-once); subscription periods of one organisation never overlap. | Talentra (billing) | Phase 1/2 (Steps 01–11) | ``subscription_guard()` + `ex_subscription_no_overlap`` |
| BR-18 | calculation & pricing | Every organisation has exactly one `wallet`. `wallet.balance_credits` equals `SUM(wallet_ledger_entry.credits)` and is never negative. Ledger entries are append-only; corrections are `reversal` entries (`ledger_entry_type_id = 6`) pointing once at the original entry. | Talentra (billing) | Phase 1/2 (Steps 01–11) | ``trg_organisation_ensure_wallet`, `wallet_post()` with wallet row lock, `forbid_change()`, `ck_wallet_balance_not_negative`` |
| BR-19 | calculation & pricing | Payment webhooks (`billing_apply_payment_event`) are idempotent on `gateway_event_ref`, verify `event.amount = order.amount`, advance `payment_order` strictly forward (`created -> authorised -> captured -> refunded` or `-> failed`), issue a sequential GST invoice (`18%` tax split) on capture, and reverse granted credits on refund. | Talentra (finance) | Phase 1/2 (Steps 01–11) | ``billing_apply_payment_event()`, `uq_payment_event_gateway_event_ref`, `ck_invoice_total`` |
| BR-20 | calculation & pricing | Downloading a candidate profile (`billing_download_profile`) costs 1 credit and grants the organisation 30 days of access to `candidate_contact()`. Repeat downloads within 30 days are free and return the existing download. Every download and contact reveal is audited. | Talentra (billing & privacy) | Phase 1/2 (Steps 01–11) | ``billing_download_profile()`, `candidate_contact()`, `audit_log()`` |
| BR-21 | state transition | Notifications are written in the same transaction as the business event (`dedupe_key` prevents duplicates), honour `notification_preference` opt-outs and `consent_current` (except category 3 `account_security`), never contain PII in `payload`, and move only `queued -> sent -> delivered/failed` with exponential backoff up to 5 attempts. | Talentra (messaging) | Phase 2/3 Workflow & V013 | ``notification_apply_preference()`, `application_notify()`, `notification_claim()`, `notification_record_result()`` |
| BR-22 | retention & lifecycle | Every sensitive action writes an append-only `audit_event` via `audit_log()` (actor taken from `app.user_id`, never forged by the caller); row-change triggers log changed column names, never personal values. | Talentra (compliance) | Phase 2/3 Workflow & V013 | ``audit_log()`, `audit_row_change()`, `forbid_change()`, RLS `audit_event_read`` |
| BR-23 | privacy & consent | Right to erasure (`candidate_erase`) deletes education, experience, skills, languages, job alerts, resumes (queuing object-storage deletion), and credentials; blanks name, headline, summary, city, salary, email, phone, `application_answer.answer_text`, and `user_device.device_label`; ends sessions; revokes devices; and retains applications, downloads, and ledgers anonymised. | Candidate / Compliance | Phase 2/3 Workflow & V013 | ``candidate_erase()`, `retention_erase_inactive()`` |
| BR-24 | policy & eligibility | Organisation parent hierarchy (`parent_organisation_id`) must remain a strict tree (no self-parenting or cycles), and a recruiter sees and acts only on their own organisation's jobs, applications, and funnel. | Talentra (organisation) | Phase 2/3 Workflow & V013 | ``ck_organisation_not_own_parent`, `organisation_prevent_cycle()`, RLS policies, `employer_hiring_funnel`` |
| BR-25 | policy & eligibility | Consultant-sourced applications (`application_source_id = 3`) are permitted only on job requirements where `is_open_to_consultants = true`. | Employer / Consultant | Phase 2/3 Workflow & V013 | ``application_guard()`` |
| BR-26 | domain & format | All UI strings resolve via `ui_text(ui_label_id, language_id)` with automatic fallback to English (`language_id = 1`); user-authored text is stored once in UTF-8 with its language tag. | Talentra (localisation) | Phase 2/3 Workflow & V013 | ``ui_text()`, `t01_standards.sql` fallback check` |
| BR-27 | retention & lifecycle | Scheduled retention and maintenance jobs keep high-volume tables bounded: `audit_event` partitions created monthly and dropped after 7 years; inactive profiles erased after 3 years; ended sessions purged after 1 year; final notifications after 180 days; system errors after 90 days; `agg_hiring_funnel_monthly` refreshed hourly `CONCURRENTLY`. | Talentra (operations) | Phase 2/3 Workflow & V013 | ``create_month_partitions()`, `retention_erase_inactive()`, `refresh_aggregates()`, `forbid_change()` (`app.retention_job = on`)` |
| BR-28 | policy & eligibility | Probable duplicate candidates (same `phone_e164` and `lower(full_name)`), profiles missing `current_city_id`, experience mismatches, over-seat lapsed orgs, unverified org open jobs, and 90-day stale `is_open_to_work` profiles are continuously detected by data-quality queries (`F-01`..`F-06`). | Talentra (data quality) | Phase 2/3 Workflow & V013 | `Index `idx_app_user_phone_e164` (AP-12) + DQ suite `t05_data_quality.sql`` |

## 1. Business and cross-table rules (DR-001..DR-067 — 67 Explicit Rows)

| ID | Rule | Table(s) | Enforcement point | Mechanism | Business rule |
|---|---|---|---|---|---|
| DR-001 | Candidates register themselves; a signed-in non-staff user cannot register a candidate | app_user, candidate_profile | Database | function auth_register_candidate() | BR-02 |
| DR-002 | Registration creates user, credential, candidate role, profile and the two required consents in one transaction | app_user, user_credential, user_access_role, candidate_profile, consent_record | Database | function auth_register_candidate() | BR-02 |
| DR-003 | Employer sign-up creates user, organisation (pending), wallet and account-admin membership together | organisation, wallet, organisation_member | Database | function auth_register_employer() |  |
| DR-004 | Every organisation has exactly one wallet | organisation, wallet | **Gap** | at most one: uq_wallet_organisation_id; at least one: only via sign-up (FND-13) |  |
| DR-005 | Permissions come from roles, and only active accounts have any | user_access_role, access_role_permission, app_user | Database | function app_has_permission() | BR-05 |
| DR-006 | Current consent per purpose is the latest record | consent_record | Database | view consent_current | BR-06 |
| DR-007 | A user cannot hold more active devices than the licence allows; the refusal is audited | user_session, user_device, subscription | Database | function auth_open_session() with a user-row lock | BR-07 |
| DR-008 | Expired sessions are closed before counting and do not count | user_session | Database | function auth_open_session() | BR-07 |
| DR-009 | A revoked device cannot open a session; the refusal is audited | user_device | Database | function auth_open_session() | BR-07 |
| DR-010 | Users end their own sessions, staff anyone's; revocations are audited | user_session | Database | function auth_end_session() |  |
| DR-011 | A device can be revoked by its owner or staff | user_device | **Gap** | no entry point (FND-04) |  |
| DR-012 | Account lockout after repeated failed logins | user_credential | Application | auth service using failed_attempt_count, locked_until (FND-14) |  |
| DR-013 | Passwords are hashed with argon2id before they reach the database | user_credential | Application | auth service; format checked by ck_user_credential_password_hash_argon2id |  |
| DR-014 | The organisation hierarchy is a tree: no organisation under its own descendant | organisation | Database | trigger organisation_prevent_cycle() |  |
| DR-015 | Current members never exceed the licence seats, even under concurrent additions | organisation_member, subscription | Database | trigger organisation_member_seat_limit() with an organisation-row lock | BR-09 |
| DR-016 | Staff verify organisations: pending → verified / rejected, with time | organisation | **Gap** | ck_organisation_verified_at holds the time; no entry point (FND-03) |  |
| DR-017 | Tax identifiers are validated per type (GSTIN 15 with checksum, PAN 10, CIN 21) and stored only as HMAC + last 4 | organisation_tax_identifier | Application | API validation; function pii_hmac() with the key outside the database | BR-10 |
| DR-018 | Publishing a job costs 5 credits, charged exactly once | job_requirement, wallet_ledger_entry | Database | trigger job_requirement_charge_posting() with idempotency key job_post:<id> | BR-11 |
| DR-019 | A published job never returns to draft; closed and filled are final | job_requirement | **Gap** | only ck_job_requirement_published (FND-01, FND-02) |  |
| DR-020 | Pending organisations may publish jobs (finding F-05) | job_requirement, organisation | **Gap** | open product decision |  |
| DR-021 | A join fills one position; the job becomes filled when all positions are joined | application, job_requirement | Database | trigger application_guard() | BR-12 |
| DR-022 | Applications only to open, published jobs before the closing date | application, job_requirement | Database | trigger application_guard() | BR-13 |
| DR-023 | A new application starts as applied | application | Database | trigger application_guard() | BR-13 |
| DR-024 | Consultant-sourced applications only on jobs open to consultants | application, job_requirement | Database | trigger application_guard() |  |
| DR-025 | An application belongs to its job's organisation | application, job_requirement | Database | trigger fills it; composite key fk_application_job_requirement pins it |  |
| DR-026 | Only the listed pipeline moves are allowed | application, application_status_transition | Database | trigger application_guard() reading the transition table | BR-14 |
| DR-027 | A candidate may only withdraw | application | Database | trigger application_guard() | BR-15 |
| DR-028 | Every status change is kept, append-only | application_status_history | Database | trigger application_record_history(); forbid_change() | BR-16 |
| DR-029 | Every status change notifies the candidate once | notification | Database | trigger application_notify() with dedupe_key | BR-21 |
| DR-030 | An application can attach only the applicant's own resume | application, resume | Database | composite key fk_application_resume |  |
| DR-031 | An answer can only be to a question of the job applied for | application_answer, screening_question, application | Database | composite keys on (id, job_requirement_id) |  |
| DR-032 | A sold licence never changes except cancellation, auto-renew and an earlier end | subscription | Database | trigger subscription_guard() | BR-17 |
| DR-033 | The wallet balance equals the ledger and never goes negative, under concurrent debits | wallet, wallet_ledger_entry | Database | function wallet_post() (single writer, wallet-row lock) + ck_wallet_balance_not_negative | BR-18 |
| DR-034 | Ledger rows are never changed; a correction is a reversal entry | wallet_ledger_entry | Database | forbid_change(); ck_wallet_ledger_entry_reversal | BR-18 |
| DR-035 | Each gateway event is applied at most once | payment_event, payment_order | Database | uq_payment_event_gateway_event_ref + function billing_apply_payment_event() | BR-19 |
| DR-036 | The event amount must equal the order amount | payment_event, payment_order | Database | function billing_apply_payment_event() | BR-19 |
| DR-037 | Payment status moves only forward: created → authorised → captured → refunded, or → failed | payment_order | Database | function billing_apply_payment_event() (allowed pairs) | BR-19 |
| DR-038 | Capture grants credits or a non-overlapping period plus plan credits, and one GST invoice | subscription, wallet_ledger_entry, invoice | Database | function billing_apply_payment_event() |  |
| DR-039 | A refund reverses the credits it granted, and is refused if they were spent | wallet_ledger_entry, subscription | Database | function billing_apply_payment_event() via wallet_post() |  |
| DR-040 | A profile download costs 1 credit; repeating it within 30 days is free | profile_download, wallet_ledger_entry | Database | function billing_download_profile() with a wallet-row lock | BR-20 |
| DR-041 | Contact details only through a download in the last 30 days, and every read is audited | app_user, profile_download | Database | function candidate_contact(); RLS app_user_self | BR-20 |
| DR-042 | Hidden profiles never appear to recruiters | candidate_profile | Database | RLS candidate_profile_read | BR-03 |
| DR-043 | A blocked company or person cannot see the candidate, their applications or contact details | candidate_profile, application | Database | RLS candidate_profile_read, application_read; app_candidates_blocking_viewer() | BR-04 |
| DR-044 | A recruiter sees and acts only on their own company's jobs and applications | job_requirement, application | Database | RLS job_requirement_read / _update, application_update |  |
| DR-045 | A notification is written in the same transaction as the change it reports | notification | Database | outbox triggers and functions (ADR-010) | BR-21 |
| DR-046 | Opt-outs are respected, except security notices | notification, notification_preference | Database | trigger notification_apply_preference() |  |
| DR-047 | Marketing and WhatsApp messages need the matching consent | notification, consent_record | **Gap** | not checked (FND-09) |  |
| DR-048 | Notification payloads hold template variables only, never contact details or message bodies | notification | Application | template variable whitelist in the API; size capped by a check |  |
| DR-049 | Delivery retries with exponential backoff up to 5 attempts; a dead worker's rows come back after 5 minutes | notification | Pipeline | worker via notification_claim() (SKIP LOCKED) and notification_record_result() |  |
| DR-050 | The audit trail is append-only and its actor cannot be forged | audit_event | Database | forbid_change(); audit_log() definer function; no INSERT grant | BR-22 |
| DR-051 | Audit details hold changed column names, never values | audit_event | Database | trigger audit_row_change() |  |
| DR-052 | Credentials are unreadable by every runtime role | user_credential | Database | grants: no SELECT for any runtime role |  |
| DR-053 | UI text falls back to English when a translation is missing | ui_translation | Database | function ui_text() |  |
| DR-054 | An employer reads only its own hiring funnel | agg_hiring_funnel_monthly | Database | view employer_hiring_funnel (security barrier) |  |
| DR-055 | Erasure on request removes or blanks personal data in one transaction and keeps others' records anonymised | candidate_profile and sections, app_user | Database | function candidate_erase() |  |
| DR-056 | Profiles inactive for 3 years are erased | candidate_profile | Pipeline | daily scheduler calls retention_erase_inactive() |  |
| DR-057 | Audit partitions are created ahead and dropped after 7 years | audit_event | Pipeline | monthly scheduler: create_month_partitions(), detach + drop |  |
| DR-058 | Ended sessions are deleted after 1 year | user_session | Pipeline | scheduled delete (to build) |  |
| DR-059 | Notifications are deleted 180 days after their final status | notification | Pipeline | scheduled delete (to build) |  |
| DR-060 | System errors are deleted after 90 days | system_error | Pipeline | scheduled delete (to build) |  |
| DR-061 | The hiring funnel is refreshed hourly without blocking readers | agg_hiring_funnel_monthly | Pipeline | scheduler calls refresh_aggregates() (CONCURRENTLY) |  |
| DR-062 | "Open to work" expires after 90 days of inactivity (finding F-06) | candidate_profile | Pipeline | scheduled job (backlog) |  |
| DR-063 | Organisations over their seats after a lapse get a grace period, then extra members end (finding F-04) | organisation_member | Pipeline | scheduled job (backlog) |  |
| DR-064 | Probable duplicate candidates (same phone and name) are flagged at registration (finding F-01) | app_user, candidate_profile | Application | duplicate check on idx_app_user_phone_e164 (AP-12) |  |
| DR-065 | Resume files: pdf or docx, size-limited, virus-scanned before the row is written | resume | Application | upload service; key format by a check |  |
| DR-066 | Test and seed data contain no real personal data: reserved .test domains, generated names | all personal tables | Pipeline | data generator (db/seed) |  |
| DR-067 | Legacy imports keep (source_system, source_record_id) unique | imported tables | Pipeline | ETL, when the migration lands |  |

## 2. Standard domains (DR-068..DR-080 — 13 Explicit Rows)

| ID | Domain | Base type | Rule |
|---|---|---|---|
| DR-068 | `person_name` | text | CHECK (char_length(VALUE) BETWEEN 1 AND 150 AND VALUE = btrim(VALUE)) |
| DR-069 | `short_text` | text | CHECK (char_length(VALUE) BETWEEN 1 AND 200) |
| DR-070 | `medium_text` | text | CHECK (char_length(VALUE) BETWEEN 1 AND 2000) |
| DR-071 | `long_text` | text | CHECK (char_length(VALUE) BETWEEN 1 AND 20000) |
| DR-072 | `email_address` | text | CHECK (char_length(VALUE) <= 254 AND VALUE = lower(VALUE) AND VALUE ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') |
| DR-073 | `phone_e164` | text | CHECK (VALUE ~ '^\+[1-9][0-9]{6,14}$') |
| DR-074 | `money_amount` | numeric(14,2) | CHECK (VALUE >= 0) |
| DR-075 | `credit_count` | integer | whole numbers, signed (ledger) |
| DR-076 | `percentage` | numeric(5,2) | CHECK (VALUE BETWEEN 0 AND 100) |
| DR-077 | `latitude` | numeric(8,6) | CHECK (VALUE BETWEEN -90 AND 90) |
| DR-078 | `longitude` | numeric(9,6) | CHECK (VALUE BETWEEN -180 AND 180) |
| DR-079 | `lookup_code` | text | CHECK (VALUE ~ '^[a-z][a-z0-9_]{0,49}$') |
| DR-080 | `sha256_digest` | bytea | CHECK (octet_length(VALUE) = 32) |

## 3. Single-table constraints on business & reference tables (DR-081..DR-210 — 130 Explicit Rows)

Keys, uniqueness, ranges, formats and cross-field rules declared on one table. Every one is enforced by the database. NOT NULL is in the [dictionary](10-data-dictionary-v1.md); foreign keys and their delete rules are in the [relationship register](09-logical-er-model-v0.md#2-relationship-register).

| ID | Table | Kind | Name | Rule (as declared) |
|---|---|---|---|---|
| DR-081 | `app_user` | unique | `uq_app_user_email` | `email` |
| DR-082 | `app_user` | check | `time_zone (inline)` | `time_zone ~ '^[A-Za-z_]+(/[A-Za-z0-9_+-]+)*$'` |
| DR-083 | `app_user` | check | `ck_app_user_erased_deleted` | `account_status_id <> 4 OR deleted_at IS NOT NULL` |
| DR-084 | `user_credential` | unique | `uq_user_credential_app_user_id` | `app_user_id` |
| DR-085 | `user_credential` | check | `ck_user_credential_password_hash_argon2id` | `password_hash ~ '^\$argon2id\$v=19\$m=[0-9]+,t=[0-9]+,p=[0-9]+\$[A-Za-z0-9+/]+\$[A-Za-z0-9+/]+$'` |
| DR-086 | `user_credential` | check | `failed_attempt_count (inline)` | `failed_attempt_count >= 0` |
| DR-087 | `access_role_permission` | unique | `uq_access_role_permission_access_role_id_access_permission_id` | `access_role_id, access_permission_id` |
| DR-088 | `user_access_role` | unique | `uq_user_access_role_app_user_id_access_role_id` | `app_user_id, access_role_id` |
| DR-089 | `consent_record` | check | `policy_version (inline)` | `policy_version ~ '^[0-9]{4}-[0-9]{2}(\.[0-9]+)?$'` |
| DR-090 | `user_device` | unique | `uq_user_device_app_user_id_device_fingerprint_hash` | `app_user_id, device_fingerprint_hash` |
| DR-091 | `user_device` | unique | `uq_user_device_id_app_user_id` | `id, app_user_id` |
| DR-092 | `user_device` | check | `ck_user_device_seen` | `last_seen_at >= first_seen_at` |
| DR-093 | `user_session` | unique | `uq_user_session_token_hash` | `token_hash` |
| DR-094 | `organisation` | check | `website_url (inline)` | `website_url ~ '^https?://[^\s]{3,250}$'` |
| DR-095 | `organisation` | check | `ck_organisation_not_own_parent` | `parent_organisation_id <> id` |
| DR-096 | `organisation_location` | check | `postal_code (inline)` | `postal_code ~ '^[A-Z0-9 -]{3,10}$'` |
| DR-097 | `organisation_location` | check | `ck_organisation_location_coordinates` | `latitude IS NULL) = (longitude IS NULL` |
| DR-098 | `organisation_location` | unique (index) | `uq_organisation_location_organisation_id_headquarters` | `(organisation_id) WHERE is_headquarters` |
| DR-099 | `organisation_tax_identifier` | check | `identifier_last4 (inline)` | `identifier_last4 ~ '^[A-Z0-9]{4}$'` |
| DR-100 | `organisation_tax_identifier` | unique | `uq_organisation_tax_identifier_country_id_type_hmac` | `country_id, tax_identifier_type_id, identifier_hmac` |
| DR-101 | `organisation_tax_identifier` | check | `ck_organisation_tax_identifier_verified_at` | `verification_status_id = 2) = (verified_at IS NOT NULL` |
| DR-102 | `organisation_member` | check | `ck_organisation_member_role` | `access_role_id IN (3, 4, 5)` |
| DR-103 | `organisation_member` | check | `ck_organisation_member_period` | `valid_to IS NULL OR valid_to > valid_from` |
| DR-104 | `organisation_member` | exclusion | `ex_organisation_member_one_organisation` | `EXCLUDE USING gist (app_user_id WITH =, tstzrange(valid_from, valid_to) WITH &&)` |
| DR-105 | `candidate_profile` | unique | `uq_candidate_profile_app_user_id` | `app_user_id` |
| DR-106 | `candidate_profile` | check | `total_experience_months (inline)` | `total_experience_months BETWEEN 0 AND 720` |
| DR-107 | `candidate_profile` | check | `notice_period_days (inline)` | `notice_period_days BETWEEN 0 AND 365` |
| DR-108 | `candidate_profile` | check | `ck_candidate_profile_salary` | ` (salary_disclosure_id = 1) = (expected_salary_amount IS NOT NULL) AND (expected_salary_amount IS NULL) = (expected_salary_currency_id IS NULL` |
| DR-109 | `candidate_education` | check | `ck_candidate_education_dates` | `end_date IS NULL OR end_date >= start_date` |
| DR-110 | `candidate_experience` | check | `ck_candidate_experience_dates` | `end_date IS NULL OR end_date >= start_date` |
| DR-111 | `candidate_experience` | unique (index) | `uq_candidate_experience_one_current` | `(candidate_profile_id) WHERE end_date IS NULL` |
| DR-112 | `candidate_skill` | check | `experience_months (inline)` | `experience_months BETWEEN 0 AND 720` |
| DR-113 | `candidate_skill` | unique | `uq_candidate_skill_candidate_profile_id_skill_id` | `candidate_profile_id, skill_id` |
| DR-114 | `candidate_language` | unique | `uq_candidate_language_candidate_profile_id_language_id` | `candidate_profile_id, language_id` |
| DR-115 | `resume` | check | `version_number (inline)` | `version_number > 0` |
| DR-116 | `resume` | check | `storage_key (inline)` | `storage_key ~ '^resumes/[0-9]+/[0-9a-f-]{36}\.(pdf\|docx)$'` |
| DR-117 | `resume` | unique | `uq_resume_storage_key` | `storage_key` |
| DR-118 | `resume` | unique | `uq_resume_candidate_profile_id_version_number` | `candidate_profile_id, version_number` |
| DR-119 | `resume` | unique | `uq_resume_id_candidate_profile_id` | `id, candidate_profile_id` |
| DR-120 | `resume` | unique (index) | `uq_resume_one_primary` | `(candidate_profile_id) WHERE is_primary` |
| DR-121 | `candidate_block` | check | `ck_candidate_block_one_target` | `num_nonnulls(blocked_organisation_id, blocked_app_user_id) = 1` |
| DR-122 | `candidate_block` | check | `ck_candidate_block_dates` | `unblocked_at IS NULL OR unblocked_at >= blocked_at` |
| DR-123 | `candidate_block` | unique (index) | `uq_candidate_block_active_organisation` | `(blocked_organisation_id, candidate_profile_id) WHERE unblocked_at IS NULL` |
| DR-124 | `candidate_block` | unique (index) | `uq_candidate_block_active_user` | `(blocked_app_user_id, candidate_profile_id) WHERE unblocked_at IS NULL` |
| DR-125 | `job_alert` | check | `ck_job_alert_salary_currency` | `min_salary_amount IS NULL) = (salary_currency_id IS NULL` |
| DR-126 | `job_requirement` | check | `min_experience_months (inline)` | `min_experience_months BETWEEN 0 AND 600` |
| DR-127 | `job_requirement` | check | `max_experience_months (inline)` | `max_experience_months BETWEEN 0 AND 600` |
| DR-128 | `job_requirement` | check | `ck_job_requirement_salary_disclosure` | `salary_disclosure_id IN (1, 2)` |
| DR-129 | `job_requirement` | check | `positions_total (inline)` | `positions_total BETWEEN 1 AND 10000` |
| DR-130 | `job_requirement` | check | `ck_job_requirement_experience` | `max_experience_months IS NULL OR max_experience_months >= min_experience_months` |
| DR-131 | `job_requirement` | check | `ck_job_requirement_salary` | ` salary_min_amount IS NULL OR salary_max_amount IS NULL OR salary_min_amount <= salary_max_amount` |
| DR-132 | `job_requirement` | check | `ck_job_requirement_salary_disclosed` | ` (salary_disclosure_id = 1) = (salary_min_amount IS NOT NULL) AND (salary_min_amount IS NULL) = (salary_currency_id IS NULL) AND (salary_max_amount IS NULL OR s`… |
| DR-133 | `job_requirement` | unique | `uq_job_requirement_id_organisation_id` | `id, organisation_id` |
| DR-134 | `job_requirement_location` | unique | `uq_job_requirement_location_job_requirement_id_city_id` | `job_requirement_id, city_id` |
| DR-135 | `job_requirement_skill` | unique | `uq_job_requirement_skill_job_requirement_id_skill_id` | `job_requirement_id, skill_id` |
| DR-136 | `screening_question` | check | `sort_order (inline)` | `sort_order > 0` |
| DR-137 | `screening_question` | unique | `uq_screening_question_job_requirement_id_sort_order` | `job_requirement_id, sort_order` |
| DR-138 | `screening_question` | unique | `uq_screening_question_id_job_requirement_id` | `id, job_requirement_id` |
| DR-139 | `application` | unique | `uq_application_job_requirement_id_candidate_profile_id` | `job_requirement_id, candidate_profile_id` |
| DR-140 | `application` | unique | `uq_application_id_job_requirement_id` | `id, job_requirement_id` |
| DR-141 | `application` | check | `ck_application_sourced_by` | `application_source_id IN (2, 3)) = (sourced_by_app_user_id IS NOT NULL` |
| DR-142 | `application` | check | `ck_application_status_changed_at` | `status_changed_at >= applied_at` |
| DR-143 | `application_answer` | unique | `uq_application_answer_application_id_screening_question_id` | `application_id, screening_question_id` |
| DR-144 | `application_status_history` | check | `ck_application_status_history_moves` | `from_status_id IS DISTINCT FROM to_status_id` |
| DR-145 | `application_status_transition` | unique | `uq_application_status_transition_from_to` | `from_status_id, to_status_id` |
| DR-146 | `application_status_transition` | check | `ck_application_status_transition_moves` | `from_status_id <> to_status_id` |
| DR-147 | `job_status_transition` | unique | `uq_job_status_transition_from_to` | `from_status_id, to_status_id` |
| DR-148 | `job_status_transition` | check | `ck_job_status_transition_moves` | `from_status_id <> to_status_id` |
| DR-149 | `plan` | unique | `uq_plan_code` | `code` |
| DR-150 | `plan` | check | `billing_period_months (inline)` | `billing_period_months IN (1, 3, 12)` |
| DR-151 | `plan` | check | `max_seats (inline)` | `max_seats > 0` |
| DR-152 | `plan` | check | `max_devices_per_user (inline)` | `max_devices_per_user > 0` |
| DR-153 | `plan` | check | `included_credits (inline)` | `included_credits >= 0` |
| DR-154 | `subscription` | check | `max_seats (inline)` | `max_seats > 0` |
| DR-155 | `subscription` | check | `max_devices_per_user (inline)` | `max_devices_per_user > 0` |
| DR-156 | `subscription` | unique | `uq_subscription_renewed_from_subscription_id` | `renewed_from_subscription_id` |
| DR-157 | `subscription` | check | `ck_subscription_period` | `ends_on > starts_on` |
| DR-158 | `subscription` | exclusion | `ex_subscription_no_overlap` | `EXCLUDE USING gist (organisation_id WITH =, daterange(starts_on, ends_on) WITH &&)` |
| DR-159 | `subscription` | unique (index) | `uq_subscription_payment_order_id` | `(payment_order_id) WHERE payment_order_id IS NOT NULL` |
| DR-160 | `wallet` | unique | `uq_wallet_organisation_id` | `organisation_id` |
| DR-161 | `wallet` | check | `ck_wallet_balance_not_negative` | `balance_credits >= 0` |
| DR-162 | `wallet_ledger_entry` | check | `balance_after (inline)` | `balance_after >= 0` |
| DR-163 | `wallet_ledger_entry` | unique | `uq_wallet_ledger_entry_reverses_ledger_entry_id` | `reverses_ledger_entry_id` |
| DR-164 | `wallet_ledger_entry` | check | `idempotency_key (inline)` | `char_length(idempotency_key) BETWEEN 8 AND 100` |
| DR-165 | `wallet_ledger_entry` | unique | `uq_wallet_ledger_entry_idempotency_key` | `idempotency_key` |
| DR-166 | `wallet_ledger_entry` | check | `ck_wallet_ledger_entry_sign` | `CASE WHEN ledger_entry_type_id IN (1, 2) THEN credits > 0 WHEN ledger_entry_type_id IN (3, 4, 5) THEN credits < 0 ELSE credits <> 0 END` |
| DR-167 | `wallet_ledger_entry` | check | `ck_wallet_ledger_entry_reversal` | `ledger_entry_type_id = 6) = (reverses_ledger_entry_id IS NOT NULL` |
| DR-168 | `payment_order` | check | `amount (inline)` | `amount > 0` |
| DR-169 | `payment_order` | check | `gateway_order_ref (inline)` | `gateway_order_ref ~ '^[A-Za-z0-9_-]{6,64}$'` |
| DR-170 | `payment_order` | unique | `uq_payment_order_gateway_order_ref` | `gateway_order_ref` |
| DR-171 | `payment_order` | check | `idempotency_key (inline)` | `char_length(idempotency_key) BETWEEN 8 AND 100` |
| DR-172 | `payment_order` | unique | `uq_payment_order_idempotency_key` | `idempotency_key` |
| DR-173 | `payment_order` | check | `ck_payment_order_purpose` | ` (payment_purpose_id = 1) = (credits_to_grant IS NOT NULL AND credits_to_grant > 0) AND (payment_purpose_id = 2) = (plan_id IS NOT NULL` |
| DR-174 | `payment_event` | check | `gateway_event_ref (inline)` | `gateway_event_ref ~ '^[A-Za-z0-9_-]{6,64}$'` |
| DR-175 | `payment_event` | unique | `uq_payment_event_gateway_event_ref` | `gateway_event_ref` |
| DR-176 | `invoice` | unique | `uq_invoice_payment_order_id` | `payment_order_id` |
| DR-177 | `invoice` | check | `invoice_number (inline)` | `invoice_number ~ '^TAL-[0-9]{4}-[0-9]{6,}$'` |
| DR-178 | `invoice` | unique | `uq_invoice_invoice_number` | `invoice_number` |
| DR-179 | `invoice` | check | `ck_invoice_total` | `total_amount = subtotal_amount + tax_amount` |
| DR-180 | `profile_download` | unique | `uq_profile_download_wallet_ledger_entry_id` | `wallet_ledger_entry_id` |
| DR-181 | `notification_preference` | unique | `uq_notification_preference_user_category_channel` | `app_user_id, notification_category_id, notification_channel_id` |
| DR-182 | `notification` | check | `template_key (inline)` | `template_key ~ '^[a-z_]+(\.[a-z_]+)+$'` |
| DR-183 | `notification` | check | `payload (inline)` | `pg_column_size(payload) <= 2048` |
| DR-184 | `notification` | check | `dedupe_key (inline)` | `char_length(dedupe_key) <= 200` |
| DR-185 | `notification` | unique | `uq_notification_dedupe_key` | `dedupe_key` |
| DR-186 | `notification` | check | `attempt_count (inline)` | `attempt_count BETWEEN 0 AND 10` |
| DR-187 | `notification` | check | `provider_message_ref (inline)` | `char_length(provider_message_ref) <= 128` |
| DR-188 | `notification` | unique | `uq_notification_provider_message_ref` | `provider_message_ref` |
| DR-189 | `notification` | check | `ck_notification_times` | `sent_at IS NULL OR sent_at >= queued_at` |
| DR-190 | `notification` | check | `ck_notification_delivered` | `delivered_at IS NULL OR (sent_at IS NOT NULL AND delivered_at >= sent_at` |
| DR-191 | `notification` | check | `ck_notification_failed` | `notification_status_id = 4) = (failure_reason IS NOT NULL` |
| DR-192 | `audit_event` | check | `action (inline)` | `action ~ '^[a-z_]+(\.[a-z_]+)+$'` |
| DR-193 | `audit_event` | check | `entity_table (inline)` | `entity_table ~ '^[a-z_]+$'` |
| DR-194 | `audit_event` | check | `details (inline)` | `pg_column_size(details) <= 4096` |
| DR-195 | `system_error` | check | `context (inline)` | `pg_column_size(context) <= 8192` |
| DR-196 | `language` | check | `code (inline)` | `code ~ '^[a-z]{2}$'` |
| DR-197 | `language` | unique | `uq_language_code` | `code` |
| DR-198 | `ui_label` | check | `label_key (inline)` | `label_key ~ '^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$'` |
| DR-199 | `ui_label` | unique | `uq_ui_label_label_key` | `label_key` |
| DR-200 | `ui_translation` | unique | `uq_ui_translation_ui_label_id_language_id` | `ui_label_id, language_id` |
| DR-201 | `currency` | check | `code (inline)` | `code ~ '^[A-Z]{3}$'` |
| DR-202 | `currency` | unique | `uq_currency_code` | `code` |
| DR-203 | `currency` | check | `minor_units (inline)` | `minor_units BETWEEN 0 AND 3` |
| DR-204 | `country` | check | `iso2 (inline)` | `iso2 ~ '^[A-Z]{2}$'` |
| DR-205 | `country` | unique | `uq_country_iso2` | `iso2` |
| DR-206 | `country` | check | `phone_country_code (inline)` | `phone_country_code ~ '^\+[1-9][0-9]{0,3}$'` |
| DR-207 | `state` | check | `code (inline)` | `code ~ '^[A-Z0-9]{1,5}$'` |
| DR-208 | `state` | unique | `uq_state_country_id_code` | `country_id, code` |
| DR-209 | `city` | unique | `uq_city_state_id_name` | `state_id, name` |
| DR-210 | `skill` | unique (index) | `uq_skill_name` | `(lower(name))` |

## 3.A Enumeration lookup table constraints (DR-211..DR-235 — 25 Explicit Rows)

| ID | Table | Kind | Name | Rule (as declared) |
|---|---|---|---|---|
| DR-211 | `access_permission` | lookup unique + FK | `uq_access_permission_code` + `fk_access_permission_ui_label` | `code UNIQUE (lookup_code: user_manage, organisation_verify, job_post, job_manage, application_manage, … (11 total)); ui_label_id REFERENCES ui_label(id) ON DELETE RESTRICT` |
| DR-212 | `access_role` | lookup unique + FK | `uq_access_role_code` + `fk_access_role_ui_label` | `code UNIQUE (lookup_code: super_admin, admin, account_admin, employer, recruiter, … (8 total)); ui_label_id REFERENCES ui_label(id) ON DELETE RESTRICT` |
| DR-213 | `account_status` | lookup unique + FK | `uq_account_status_code` + `fk_account_status_ui_label` | `code UNIQUE (lookup_code: active, suspended, deactivated, erased); ui_label_id REFERENCES ui_label(id) ON DELETE RESTRICT` |
| DR-214 | `alert_frequency` | lookup unique + FK | `uq_alert_frequency_code` + `fk_alert_frequency_ui_label` | `code UNIQUE (lookup_code: instant, daily, weekly); ui_label_id REFERENCES ui_label(id) ON DELETE RESTRICT` |
| DR-215 | `answer_type` | lookup unique + FK | `uq_answer_type_code` + `fk_answer_type_ui_label` | `code UNIQUE (lookup_code: yes_no, number, short_text); ui_label_id REFERENCES ui_label(id) ON DELETE RESTRICT` |
| DR-216 | `application_source` | lookup unique + FK | `uq_application_source_code` + `fk_application_source_ui_label` | `code UNIQUE (lookup_code: direct, recruiter_outreach, consultant, referral, campus); ui_label_id REFERENCES ui_label(id) ON DELETE RESTRICT` |
| DR-217 | `application_status` | lookup unique + FK | `uq_application_status_code` + `fk_application_status_ui_label` | `code UNIQUE (lookup_code: applied, shortlisted, interviewing, offered, joined, … (7 total)); ui_label_id REFERENCES ui_label(id) ON DELETE RESTRICT` |
| DR-218 | `consent_purpose` | lookup unique + FK | `uq_consent_purpose_code` + `fk_consent_purpose_ui_label` | `code UNIQUE (lookup_code: terms_of_service, privacy_policy, profile_visible_to_recruiters, marketing_email, whatsapp_alerts); ui_label_id REFERENCES ui_label(id) ON DELETE RESTRICT` |
| DR-219 | `employment_type` | lookup unique + FK | `uq_employment_type_code` + `fk_employment_type_ui_label` | `code UNIQUE (lookup_code: full_time, part_time, contract, internship, apprenticeship, … (6 total)); ui_label_id REFERENCES ui_label(id) ON DELETE RESTRICT` |
| DR-220 | `industry` | lookup unique + FK | `uq_industry_code` + `fk_industry_ui_label` | `code UNIQUE (lookup_code: information_technology, banking_financial_services, healthcare, manufacturing, retail, … (15 total)); ui_label_id REFERENCES ui_label(id) ON DELETE RESTRICT` |
| DR-221 | `job_status` | lookup unique + FK | `uq_job_status_code` + `fk_job_status_ui_label` | `code UNIQUE (lookup_code: draft, open, paused, closed, filled); ui_label_id REFERENCES ui_label(id) ON DELETE RESTRICT` |
| DR-222 | `ledger_entry_type` | lookup unique + FK | `uq_ledger_entry_type_code` + `fk_ledger_entry_type_ui_label` | `code UNIQUE (lookup_code: recharge, plan_grant, job_post_debit, profile_download_debit, outreach_debit, … (6 total)); ui_label_id REFERENCES ui_label(id) ON DELETE RESTRICT` |
| DR-223 | `notification_category` | lookup unique + FK | `uq_notification_category_code` + `fk_notification_category_ui_label` | `code UNIQUE (lookup_code: job_alert, application_update, account_security, billing, marketing); ui_label_id REFERENCES ui_label(id) ON DELETE RESTRICT` |
| DR-224 | `notification_channel` | lookup unique + FK | `uq_notification_channel_code` + `fk_notification_channel_ui_label` | `code UNIQUE (lookup_code: email, sms, whatsapp, in_app); ui_label_id REFERENCES ui_label(id) ON DELETE RESTRICT` |
| DR-225 | `notification_status` | lookup unique + FK | `uq_notification_status_code` + `fk_notification_status_ui_label` | `code UNIQUE (lookup_code: queued, sent, delivered, failed, suppressed); ui_label_id REFERENCES ui_label(id) ON DELETE RESTRICT` |
| DR-226 | `payment_purpose` | lookup unique + FK | `uq_payment_purpose_code` + `fk_payment_purpose_ui_label` | `code UNIQUE (lookup_code: wallet_recharge, subscription); ui_label_id REFERENCES ui_label(id) ON DELETE RESTRICT` |
| DR-227 | `payment_status` | lookup unique + FK | `uq_payment_status_code` + `fk_payment_status_ui_label` | `code UNIQUE (lookup_code: created, authorised, captured, failed, refunded); ui_label_id REFERENCES ui_label(id) ON DELETE RESTRICT` |
| DR-228 | `proficiency_level` | lookup unique + FK | `uq_proficiency_level_code` + `fk_proficiency_level_ui_label` | `code UNIQUE (lookup_code: beginner, intermediate, advanced, expert, native); ui_label_id REFERENCES ui_label(id) ON DELETE RESTRICT` |
| DR-229 | `profile_visibility` | lookup unique + FK | `uq_profile_visibility_code` + `fk_profile_visibility_ui_label` | `code UNIQUE (lookup_code: public, recruiters_only, hidden); ui_label_id REFERENCES ui_label(id) ON DELETE RESTRICT` |
| DR-230 | `qualification` | lookup unique + FK | `uq_qualification_code` + `fk_qualification_ui_label` | `code UNIQUE (lookup_code: below_secondary, secondary, higher_secondary, iti, diploma, … (8 total)); ui_label_id REFERENCES ui_label(id) ON DELETE RESTRICT` |
| DR-231 | `salary_disclosure` | lookup unique + FK | `uq_salary_disclosure_code` + `fk_salary_disclosure_ui_label` | `code UNIQUE (lookup_code: disclosed, not_disclosed, not_provided); ui_label_id REFERENCES ui_label(id) ON DELETE RESTRICT` |
| DR-232 | `session_end_reason` | lookup unique + FK | `uq_session_end_reason_code` + `fk_session_end_reason_ui_label` | `code UNIQUE (lookup_code: logout, idle_timeout, revoked_by_user, revoked_by_admin); ui_label_id REFERENCES ui_label(id) ON DELETE RESTRICT` |
| DR-233 | `tax_identifier_type` | lookup unique + FK | `uq_tax_identifier_type_code` + `fk_tax_identifier_type_ui_label` | `code UNIQUE (lookup_code: gstin, pan, cin, vat, ein); ui_label_id REFERENCES ui_label(id) ON DELETE RESTRICT` |
| DR-234 | `verification_status` | lookup unique + FK | `uq_verification_status_code` + `fk_verification_status_ui_label` | `code UNIQUE (lookup_code: pending, verified, rejected); ui_label_id REFERENCES ui_label(id) ON DELETE RESTRICT` |
| DR-235 | `work_mode` | lookup unique + FK | `uq_work_mode_code` + `fk_work_mode_ui_label` | `code UNIQUE (lookup_code: onsite, remote, hybrid); ui_label_id REFERENCES ui_label(id) ON DELETE RESTRICT` |

## 3.B Phase 3 (`V013`) refinement & catalog guard rules (DR-236..DR-247 — 12 Explicit Rows)

| ID | Table | Kind | Name | Rule (as declared in V013) |
|---|---|---|---|---|
| DR-236 | `job_requirement` | trigger guard | `trg_job_requirement_guard` | Enforces legal transitions via job_status_transition and blocks returning to draft (FND-01, FND-02) |
| DR-237 | `organisation` | security definer fn | `organisation_set_verification()` | Restricts pending -> verified/rejected transition to staff with organisation_verify permission (FND-03) |
| DR-238 | `user_device` | security definer fn + trigger | `auth_revoke_device() + trg_user_device_guard` | Blocks clearing revoked_at and closes active sessions on device revocation (FND-04) |
| DR-239 | `app_user` | security definer fn + trigger | `user_set_account_status() + trg_app_user_status_guard` | Enforces account_status state machine; blocks un-erasing accounts (FND-05) |
| DR-240 | `subscription` | trigger guard | `subscription_guard()` | Blocks all mutations once cancelled_at IS NOT NULL (FND-06) |
| DR-241 | `notification` | security definer fn | `notification_record_result()` | Enforces terminal delivery states delivered and suppressed (FND-07) |
| DR-242 | `candidate_experience` | trigger guard | `trg_candidate_experience_close_once` | Enforces one-way valid_to period closing via period_close_once_guard() (FND-08) |
| DR-243 | `organisation_member` | trigger guard | `trg_organisation_member_close_once` | Enforces one-way valid_to membership closing via period_close_once_guard() (FND-08) |
| DR-244 | `candidate_profile` | security definer helper + RLS | `app_users_without_recruiter_consent()` | Blocks recruiter discovery when profile_visible_to_recruiters consent is withdrawn (FND-09) |
| DR-245 | `notification` | trigger guard | `notification_apply_preference()` | Suppresses marketing notifications unless active marketing_email / whatsapp_alerts consent exists (FND-10) |
| DR-246 | `candidate_profile` | security definer fn | `candidate_erase()` | Clears candidate_education, experience, skill, language, job_alert, and notification_preference on GDPR erasure (FND-11) |
| DR-247 | `user_credential` | security definer fn | `auth_record_login_failure()` | Increments failed_attempt_count and sets 15-minute locked_until at 5 failures (FND-14) |

## 4. Cross-table rules (the playbook's "go deeper")

Rules that span tables, and how each holds even under concurrent writes:

| Rule | Mechanism | Why it cannot be a CHECK |
|---|---|---|
| wallet balance = sum of ledger | single writer `wallet_post()` + wallet-row lock | a CHECK sees one row; the sum spans many |
| invoice total = subtotal + tax, and = the payment amount | CHECK on the invoice + written by the capture function from the order | the second half spans two tables |
| joined applications ≤ positions | counter on the job, updated under the job-row lock by the pipeline trigger | counting rows of another table |
| current members ≤ licence seats | trigger with an organisation-row lock | two tables and a count |
| active devices ≤ licence devices | login function with a user-row lock | three tables and a count |
| answer belongs to a question of the applied job | composite foreign keys on (id, job_requirement_id) | expressed as keys, so no code at all |
| application organisation = job organisation | composite foreign key + trigger | same |

## 5. Summary & Step 11 → Step 18 Reconciliation

- **Total Catalogued Rules:** **275 Rules** = **28 Business Rules (`BR-01`..`BR-28`)** + **247 Data Rules (`DR-001`..`DR-247`)** (67 cross-table rules + 13 domains + 130 single-table business/ref constraints + 25 lookup table constraints + 12 V013 refinement guards).
- **By enforcement point (Phase 2 v1 snapshot prior to V013 closure):** database 224, application 6, pipeline 11, gap 6 (all 6 Phase 2 gaps closed in Step 17/18 `V013`).
- **Every rule states where it is enforced** (exit test). The gaps are open [findings](findings.md) in Phase 2 and closed in Phase 3 [Step 18](../phase3/18-business-rules-v2.md).
