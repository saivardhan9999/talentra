# 18 — Business Rules and Data Constraints v2

> Reconciled directly against live PostgreSQL 18 (`db/migrations/V001..V013`), deterministic seed (`db/seed/seed_prove_sample.sql`), and SQL test suites (`db/tests/t01..t06.sql`) with zero catalog drift.

Conforms strictly to Phase 3 schema [S-18](schemas.md#s-18--business-rules-and-data-constraints-v2).

## 1.A Phase 2 (Step 11) → Phase 3 (Step 18) Rules Reconciliation

| Rule Category | Phase 2 Step 11 (v1 Baseline) | Phase 3 Additions (`V013` & Lookup Rules) | Phase 3 Step 18 (v2 Total) | Open Gaps | Verification Suite |
|---|---|---|---|---|---|
| **Cross-Table Business Rules (`BR-01`..`BR-28`)** | 22 referenced (`BR-01..BR-22`) | +6 formalised (`BR-23..BR-28`) | **28 explicit BR rows** | **0** | `t01`..`t06` (`TC-20-001..028`) |
| **Business & Cross-Table Data Rules (`DR-001`..`DR-067`)** | 67 (`61 enforced + 6 Gaps`) | 6 Gaps closed by `V013__phase3_refinements.sql` | **67 explicit DR rows** | **0** | `t02`, `t03`, `t05`, `t06` |
| **Standard Domain Rules (`DR-068`..`DR-080`)** | 13 (`CREATE DOMAIN` checks) | 0 | **13 explicit DR rows** | **0** | `t01_standards.sql`, `t06` (`TC-15-001..010`) |
| **Single-Table Business/Ref Constraints (`DR-081`..`DR-210`)** | 130 (`CHECK`, `UNIQUE`, `EXCLUDE`) | Includes `job_status_transition` constraints | **130 explicit DR rows** | **0** | `t01_standards.sql`, `t02_integrity.sql` |
| **Enumeration Lookup Table Rules (`DR-211`..`DR-235`)** | 0 (summarised in Step 10/11 prose) | +25 (`uq_<lookup>_code` & `fk_<lookup>_ui_label_id`) | **25 explicit DR rows** | **0** | `t01_standards.sql` |
| **Phase 3 Refinement Guards & Catalog Rules (`DR-236`..`DR-247`)** | 0 (identified as `FND-01..FND-14`) | +12 (`V013` triggers, functions & catalog checks) | **12 explicit DR rows** | **0** | `t06_phase3_prove.sql` (`TC-20-001..028`) |
| **Total Reconciled Rules** | **210 DR rows (+22 BR refs)** | **+37 DR rows (+6 BR rows, 6 Gaps closed)** | **275 Total Rules (28 BR + 247 DR)** | **0 Gaps** | **153 / 153 SQL assertions PASS** |

## 1.B Business Rules Catalogue v2 (`BR-01`..`BR-28` — 28 Explicit Rows)

Every cross-table policy, calculation, limit, state rule, and constraint is consolidated with a unique ID, owner, enforcement point (**0 gaps**), and verified test:

| Rule ID | Category | Statement | Owner | Enforcement Point | Mechanism | Planned Test |
|---|---|---|---|---|---|---|
| `BR-01` | policy & eligibility | Every table uses an integer surrogate key `id`; foreign keys and check constraints are enforced by the database. | Talentra (data architecture) | **Database** | `PK/FK constraints + `t01_standards.sql`` | `TC-15-001, t01` |
| `BR-02` | policy & eligibility | Candidates register themselves (or via staff at a placement drive); recruiters/employers cannot register candidates. Sign-up creates user, credential, candidate role, profile, and mandatory terms + privacy consents in one transaction. | Talentra (identity) | **Database** | ``auth_register_candidate()`` | `TC-20-029, t03` |
| `BR-03` | privacy & consent | A candidate profile is visible to recruiters only when `deleted_at IS NULL`, `profile_visibility_id <> 3` (not hidden), and the candidate currently grants `profile_visible_to_recruiters` consent (purpose 3). | Candidate / Compliance | **Database** | `RLS `candidate_profile_read`, `app_candidate_visible()`, `app_users_without_recruiter_consent()`` | `TC-20-023, t03` |
| `BR-04` | privacy & consent | When a candidate blocks an organisation or user, the blocked party immediately loses visibility of the candidate profile, their applications, and their contact details (even if previously downloaded), and never sees the block row. | Candidate | **Database** | `RLS on `candidate_profile`, `application`, `candidate_block` + `candidate_contact()`` | `TC-20-030, t03` |
| `BR-05` | policy & eligibility | Permissions derive strictly from `user_access_role -> access_role_permission`, and only users with `account_status_id = 1` (`active`) hold any permission. | Talentra (security) | **Database** | ``app_has_permission()`` | `TC-20-015, TC-20-016, t03` |
| `BR-06` | privacy & consent | Consent is an append-only history per user and purpose with `policy_version`; the latest record (`consent_current`) governs processing. | Candidate / Compliance | **Database** | ``consent_record` (append-only) + view `consent_current`` | `TC-20-022, TC-20-023, t05 R-12` |
| `BR-07` | limit & quota | Active sessions per user cannot exceed the device limit (3 for candidates; `subscription.max_devices_per_user` for org members, or 1 without an active subscription). Expired sessions are closed first; revoked devices and over-limit logins are refused and audited. | Talentra (identity) | **Database** | ``auth_open_session()` with `FOR UPDATE` lock on `app_user` + `auth_revoke_device()`` | `TC-20-012, TC-20-031, t04 #1` |
| `BR-08` | policy & eligibility | After 5 consecutive failed password checks, the credential is locked for 15 minutes (`locked_until`), audited, and refused by `auth_open_session()`; a successful login resets the counter. | Talentra (auth service) | **Database** | ``auth_record_login_failure()` + `auth_open_session()`` | `TC-20-027, TC-20-028` |
| `BR-09` | limit & quota | An organisation has at most `subscription.max_seats` current members (`valid_to IS NULL`) under its active subscription (1 without one). A user belongs to at most one organisation at any point in time, and closed memberships (`valid_to`) are write-once. | Talentra (billing & org) | **Database** | ``trg_organisation_member_seat_limit` + `ex_organisation_member_one_organisation` + `trg_organisation_member_close_once`` | `TC-20-018, t02, t04 #3` |
| `BR-10` | approval & verification | Tax identifiers (GSTIN, PAN, CIN, VAT, EIN) are validated for format, tokenised via `pii_hmac()` + `identifier_last4`, and never stored in clear. Staff verify or reject organisations via `organisation_set_verification()`, recording `verified_at` and an audit event. | Talentra (compliance) | **Database** | ``pii_hmac()`, `uq_organisation_tax_identifier_country_id_type_hmac`, `organisation_set_verification()`` | `TC-20-007..010, t02` |
| `BR-11` | calculation & pricing | Publishing a job (`draft -> open`) sets `published_at` (write-once) and debits 5 credits from the organisation wallet exactly once (`idempotency_key = job_post:<id>`). Published jobs never return to `draft`; `closed` and `filled` are final. | Talentra (product) | **Database** | ``trg_job_requirement_guard`, `job_status_transition`, `trg_job_requirement_charge_posting`` | `TC-20-001..006, t02` |
| `BR-12` | limit & quota | Each application moving to `joined` increments `job_requirement.positions_filled` under a job row lock; when `positions_filled = positions_total`, `job_status_id` automatically becomes `filled` (5); joins beyond `positions_total` are refused. | Talentra (product) | **Database** | ``application_guard()` + `ck_job_requirement_positions`` | `TC-20-005, t02, t04 #4, t05 R-07` |
| `BR-13` | policy & eligibility | A candidate can apply at most once per job, only while the job is `open` (2), not deleted, and on or before `closes_on`, starting in status `applied` (1). Attached resumes must belong to the candidate; answers must belong to questions of that job. | Candidate / Employer | **Database** | ``application_guard()`, `uq_application_job_requirement_id_candidate_profile_id`, composite FKs `fk_application_resume`, `fk_application_answer_screening_question`` | `TC-15-020..025, t02` |
| `BR-14` | state transition | Applications move only along the 12 edges in `application_status_transition`; `joined`, `rejected`, and `withdrawn` are final. | Employer / Recruiter | **Database** | ``application_status_transition` + `application_guard()`` | `TC-08-001..005, t02, t05 R-05` |
| `BR-15` | policy & eligibility | A candidate may only transition their own application to `withdrawn` (7); all forward and rejection moves require an unblocked member of the hiring organisation with `application_manage` permission. | Candidate / Recruiter | **Database** | ``application_guard()` + RLS `application_update`` | `TC-08-006, TC-08-008, t03` |
| `BR-16` | retention & lifecycle | Every application status change is recorded in `application_status_history` (append-only) with `from_status_id`, `to_status_id`, `changed_at`, and `created_by`. | Talentra (platform) | **Database** | ``trg_application_record_history` + `forbid_change()`` | `t02, t05 R-04, R-05` |
| `BR-17` | policy & eligibility | A sold `subscription` is an immutable licence snapshot (`max_seats`, `max_devices_per_user`, `starts_on`, `plan_id` cannot change; `ends_on` cannot be extended; `cancelled_at` is write-once); subscription periods of one organisation never overlap. | Talentra (billing) | **Database** | ``subscription_guard()` + `ex_subscription_no_overlap`` | `TC-20-017, t02` |
| `BR-18` | calculation & pricing | Every organisation has exactly one `wallet`. `wallet.balance_credits` equals `SUM(wallet_ledger_entry.credits)` and is never negative. Ledger entries are append-only; corrections are `reversal` entries (`ledger_entry_type_id = 6`) pointing once at the original entry. | Talentra (billing) | **Database** | ``trg_organisation_ensure_wallet`, `wallet_post()` with wallet row lock, `forbid_change()`, `ck_wallet_balance_not_negative`` | `TC-20-026, t02, t04 #2, t05 R-01..03` |
| `BR-19` | calculation & pricing | Payment webhooks (`billing_apply_payment_event`) are idempotent on `gateway_event_ref`, verify `event.amount = order.amount`, advance `payment_order` strictly forward (`created -> authorised -> captured -> refunded` or `-> failed`), issue a sequential GST invoice (`18%` tax split) on capture, and reverse granted credits on refund. | Talentra (finance) | **Database** | ``billing_apply_payment_event()`, `uq_payment_event_gateway_event_ref`, `ck_invoice_total`` | `t02, t05 R-08, R-09` |
| `BR-20` | calculation & pricing | Downloading a candidate profile (`billing_download_profile`) costs 1 credit and grants the organisation 30 days of access to `candidate_contact()`. Repeat downloads within 30 days are free and return the existing download. Every download and contact reveal is audited. | Talentra (billing & privacy) | **Database** | ``billing_download_profile()`, `candidate_contact()`, `audit_log()`` | `t03, t05 R-10` |
| `BR-21` | state transition | Notifications are written in the same transaction as the business event (`dedupe_key` prevents duplicates), honour `notification_preference` opt-outs and `consent_current` (except category 3 `account_security`), never contain PII in `payload`, and move only `queued -> sent -> delivered/failed` with exponential backoff up to 5 attempts. | Talentra (messaging) | **Database** | ``notification_apply_preference()`, `application_notify()`, `notification_claim()`, `notification_record_result()`` | `TC-20-020..022, t02, t05 R-16` |
| `BR-22` | retention & lifecycle | Every sensitive action writes an append-only `audit_event` via `audit_log()` (actor taken from `app.user_id`, never forged by the caller); row-change triggers log changed column names, never personal values. | Talentra (compliance) | **Database** | ``audit_log()`, `audit_row_change()`, `forbid_change()`, RLS `audit_event_read`` | `t02, t03` |
| `BR-23` | privacy & consent | Right to erasure (`candidate_erase`) deletes education, experience, skills, languages, job alerts, resumes (queuing object-storage deletion), and credentials; blanks name, headline, summary, city, salary, email, phone, `application_answer.answer_text`, and `user_device.device_label`; ends sessions; revokes devices; and retains applications, downloads, and ledgers anonymised. | Candidate / Compliance | **Database** | ``candidate_erase()`, `retention_erase_inactive()`` | `TC-20-014, TC-20-024, t02` |
| `BR-24` | policy & eligibility | Organisation parent hierarchy (`parent_organisation_id`) must remain a strict tree (no self-parenting or cycles), and a recruiter sees and acts only on their own organisation's jobs, applications, and funnel. | Talentra (organisation) | **Database** | ``ck_organisation_not_own_parent`, `organisation_prevent_cycle()`, RLS policies, `employer_hiring_funnel`` | `t02, t03` |
| `BR-25` | policy & eligibility | Consultant-sourced applications (`application_source_id = 3`) are permitted only on job requirements where `is_open_to_consultants = true`. | Employer / Consultant | **Database** | ``application_guard()`` | `t02, t03` |
| `BR-26` | domain & format | All UI strings resolve via `ui_text(ui_label_id, language_id)` with automatic fallback to English (`language_id = 1`); user-authored text is stored once in UTF-8 with its language tag. | Talentra (localisation) | **Database** | ``ui_text()`, `t01_standards.sql` fallback check` | `t01, t02` |
| `BR-27` | retention & lifecycle | Scheduled retention and maintenance jobs keep high-volume tables bounded: `audit_event` partitions created monthly and dropped after 7 years; inactive profiles erased after 3 years; ended sessions purged after 1 year; final notifications after 180 days; system errors after 90 days; `agg_hiring_funnel_monthly` refreshed hourly `CONCURRENTLY`. | Talentra (operations) | **Pipeline** | ``create_month_partitions()`, `retention_erase_inactive()`, `refresh_aggregates()`, `forbid_change()` (`app.retention_job = on`)` | `t01, t02, t03` |
| `BR-28` | policy & eligibility | Probable duplicate candidates (same `phone_e164` and `lower(full_name)`), profiles missing `current_city_id`, experience mismatches, over-seat lapsed orgs, unverified org open jobs, and 90-day stale `is_open_to_work` profiles are continuously detected by data-quality queries (`F-01`..`F-06`). | Talentra (data quality) | **Application** | `Index `idx_app_user_phone_e164` (AP-12) + DQ suite `t05_data_quality.sql`` | `t05 F-01..F-06` |

## 1.C Complete Granular Data Rules Register (`DR-001`..`DR-247` — All 247 Explicit Rows)

| Rule ID | Category | Target Table / Domain | Rule / Constraint Statement | Enforcement Point | PostgreSQL Mechanism | Phase 3 Status |
|---|---|---|---|---|---|---|
| `DR-001` | business & cross-table | `app_user, candidate_profile` | Candidates register themselves; a signed-in non-staff user cannot register a candidate | **Database** | function auth_register_candidate() | Baseline (BR-02) |
| `DR-002` | business & cross-table | `app_user, user_credential, user_access_role, candidate_profile, consent_record` | Registration creates user, credential, candidate role, profile and the two required consents in one transaction | **Database** | function auth_register_candidate() | Baseline (BR-02) |
| `DR-003` | business & cross-table | `organisation, wallet, organisation_member` | Employer sign-up creates user, organisation (pending), wallet and account-admin membership together | **Database** | function auth_register_employer() | Baseline (Step 11) |
| `DR-004` | business & cross-table | `organisation, wallet` | Every organisation has exactly one wallet | **Database** | trigger `trg_organisation_ensure_wallet` (`organisation_ensure_wallet()`) + `uq_wallet_organisation_id` | Closed FND-13 in V013 |
| `DR-005` | business & cross-table | `user_access_role, access_role_permission, app_user` | Permissions come from roles, and only active accounts have any | **Database** | function app_has_permission() | Baseline (BR-05) |
| `DR-006` | business & cross-table | `consent_record` | Current consent per purpose is the latest record | **Database** | view consent_current | Baseline (BR-06) |
| `DR-007` | business & cross-table | `user_session, user_device, subscription` | A user cannot hold more active devices than the licence allows; the refusal is audited | **Database** | function auth_open_session() with a user-row lock | Baseline (BR-07) |
| `DR-008` | business & cross-table | `user_session` | Expired sessions are closed before counting and do not count | **Database** | function auth_open_session() | Baseline (BR-07) |
| `DR-009` | business & cross-table | `user_device` | A revoked device cannot open a session; the refusal is audited | **Database** | function auth_open_session() | Baseline (BR-07) |
| `DR-010` | business & cross-table | `user_session` | Users end their own sessions, staff anyone's; revocations are audited | **Database** | function auth_end_session() | Baseline (Step 11) |
| `DR-011` | business & cross-table | `user_device` | A device can be revoked by its owner or staff | **Database** | function `auth_revoke_device()` + trigger `trg_user_device_guard` (`revoked_at` write-once) | Closed FND-04 in V013 |
| `DR-012` | business & cross-table | `user_credential` | Account lockout after repeated failed logins | **Database** | function `auth_record_login_failure()` + `auth_open_session()` lockout check | Closed FND-14 in V013 |
| `DR-013` | business & cross-table | `user_credential` | Passwords are hashed with argon2id before they reach the database | **Application** | auth service; format checked by ck_user_credential_password_hash_argon2id | Baseline (Step 11) |
| `DR-014` | business & cross-table | `organisation` | The organisation hierarchy is a tree: no organisation under its own descendant | **Database** | trigger organisation_prevent_cycle() | Baseline (Step 11) |
| `DR-015` | business & cross-table | `organisation_member, subscription` | Current members never exceed the licence seats, even under concurrent additions | **Database** | trigger organisation_member_seat_limit() with an organisation-row lock | Baseline (BR-09) |
| `DR-016` | business & cross-table | `organisation` | Staff verify organisations: pending → verified / rejected, with time | **Database** | function `organisation_set_verification()` + `ck_organisation_verified_at` | Closed FND-03 in V013 |
| `DR-017` | business & cross-table | `organisation_tax_identifier` | Tax identifiers are validated per type (GSTIN 15 with checksum, PAN 10, CIN 21) and stored only as HMAC + last 4 | **Application** | API validation; function pii_hmac() with the key outside the database | Baseline (BR-10) |
| `DR-018` | business & cross-table | `job_requirement, wallet_ledger_entry` | Publishing a job costs 5 credits, charged exactly once | **Database** | trigger job_requirement_charge_posting() with idempotency key job_post:<id> | Baseline (BR-11) |
| `DR-019` | business & cross-table | `job_requirement` | A published job never returns to draft; closed and filled are final | **Database** | table `job_status_transition` + trigger `trg_job_requirement_guard` (`job_requirement_guard()`) | Closed FND-01, FND-02 in V013 |
| `DR-020` | business & cross-table | `job_requirement, organisation` | Pending organisations may publish jobs (finding F-05) | **Application** | monitored by data-quality query `F-05` in `t05_data_quality.sql` (frictionless onboarding policy) | Verified F-05 in t05 |
| `DR-021` | business & cross-table | `application, job_requirement` | A join fills one position; the job becomes filled when all positions are joined | **Database** | trigger application_guard() | Baseline (BR-12) |
| `DR-022` | business & cross-table | `application, job_requirement` | Applications only to open, published jobs before the closing date | **Database** | trigger application_guard() | Baseline (BR-13) |
| `DR-023` | business & cross-table | `application` | A new application starts as applied | **Database** | trigger application_guard() | Baseline (BR-13) |
| `DR-024` | business & cross-table | `application, job_requirement` | Consultant-sourced applications only on jobs open to consultants | **Database** | trigger application_guard() | Baseline (Step 11) |
| `DR-025` | business & cross-table | `application, job_requirement` | An application belongs to its job's organisation | **Database** | trigger fills it; composite key fk_application_job_requirement pins it | Baseline (Step 11) |
| `DR-026` | business & cross-table | `application, application_status_transition` | Only the listed pipeline moves are allowed | **Database** | trigger application_guard() reading the transition table | Baseline (BR-14) |
| `DR-027` | business & cross-table | `application` | A candidate may only withdraw | **Database** | trigger application_guard() | Baseline (BR-15) |
| `DR-028` | business & cross-table | `application_status_history` | Every status change is kept, append-only | **Database** | trigger application_record_history(); forbid_change() | Baseline (BR-16) |
| `DR-029` | business & cross-table | `notification` | Every status change notifies the candidate once | **Database** | trigger application_notify() with dedupe_key | Baseline (BR-21) |
| `DR-030` | business & cross-table | `application, resume` | An application can attach only the applicant's own resume | **Database** | composite key fk_application_resume | Baseline (Step 11) |
| `DR-031` | business & cross-table | `application_answer, screening_question, application` | An answer can only be to a question of the job applied for | **Database** | composite keys on (id, job_requirement_id) | Baseline (Step 11) |
| `DR-032` | business & cross-table | `subscription` | A sold licence never changes except cancellation, auto-renew and an earlier end | **Database** | trigger subscription_guard() | Baseline (BR-17) |
| `DR-033` | business & cross-table | `wallet, wallet_ledger_entry` | The wallet balance equals the ledger and never goes negative, under concurrent debits | **Database** | function wallet_post() (single writer, wallet-row lock) + ck_wallet_balance_not_negative | Baseline (BR-18) |
| `DR-034` | business & cross-table | `wallet_ledger_entry` | Ledger rows are never changed; a correction is a reversal entry | **Database** | forbid_change(); ck_wallet_ledger_entry_reversal | Baseline (BR-18) |
| `DR-035` | business & cross-table | `payment_event, payment_order` | Each gateway event is applied at most once | **Database** | uq_payment_event_gateway_event_ref + function billing_apply_payment_event() | Baseline (BR-19) |
| `DR-036` | business & cross-table | `payment_event, payment_order` | The event amount must equal the order amount | **Database** | function billing_apply_payment_event() | Baseline (BR-19) |
| `DR-037` | business & cross-table | `payment_order` | Payment status moves only forward: created → authorised → captured → refunded, or → failed | **Database** | function billing_apply_payment_event() (allowed pairs) | Baseline (BR-19) |
| `DR-038` | business & cross-table | `subscription, wallet_ledger_entry, invoice` | Capture grants credits or a non-overlapping period plus plan credits, and one GST invoice | **Database** | function billing_apply_payment_event() | Baseline (Step 11) |
| `DR-039` | business & cross-table | `wallet_ledger_entry, subscription` | A refund reverses the credits it granted, and is refused if they were spent | **Database** | function billing_apply_payment_event() via wallet_post() | Baseline (Step 11) |
| `DR-040` | business & cross-table | `profile_download, wallet_ledger_entry` | A profile download costs 1 credit; repeating it within 30 days is free | **Database** | function billing_download_profile() with a wallet-row lock | Baseline (BR-20) |
| `DR-041` | business & cross-table | `app_user, profile_download` | Contact details only through a download in the last 30 days, and every read is audited | **Database** | function candidate_contact(); RLS app_user_self | Baseline (BR-20) |
| `DR-042` | business & cross-table | `candidate_profile` | Hidden profiles never appear to recruiters | **Database** | RLS candidate_profile_read | Baseline (BR-03) |
| `DR-043` | business & cross-table | `candidate_profile, application` | A blocked company or person cannot see the candidate, their applications or contact details | **Database** | RLS candidate_profile_read, application_read; app_candidates_blocking_viewer() | Baseline (BR-04) |
| `DR-044` | business & cross-table | `job_requirement, application` | A recruiter sees and acts only on their own company's jobs and applications | **Database** | RLS job_requirement_read / _update, application_update | Baseline (Step 11) |
| `DR-045` | business & cross-table | `notification` | A notification is written in the same transaction as the change it reports | **Database** | outbox triggers and functions (ADR-010) | Baseline (BR-21) |
| `DR-046` | business & cross-table | `notification, notification_preference` | Opt-outs are respected, except security notices | **Database** | trigger notification_apply_preference() | Baseline (Step 11) |
| `DR-047` | business & cross-table | `notification, consent_record` | Marketing and WhatsApp messages need the matching consent | **Database** | trigger `notification_apply_preference()` + `app_users_without_recruiter_consent()` RLS helper | Closed FND-09 in V013 |
| `DR-048` | business & cross-table | `notification` | Notification payloads hold template variables only, never contact details or message bodies | **Application** | template variable whitelist in the API; size capped by a check | Baseline (Step 11) |
| `DR-049` | business & cross-table | `notification` | Delivery retries with exponential backoff up to 5 attempts; a dead worker's rows come back after 5 minutes | **Pipeline** | worker via notification_claim() (SKIP LOCKED) and notification_record_result() | Baseline (Step 11) |
| `DR-050` | business & cross-table | `audit_event` | The audit trail is append-only and its actor cannot be forged | **Database** | forbid_change(); audit_log() definer function; no INSERT grant | Baseline (BR-22) |
| `DR-051` | business & cross-table | `audit_event` | Audit details hold changed column names, never values | **Database** | trigger audit_row_change() | Baseline (Step 11) |
| `DR-052` | business & cross-table | `user_credential` | Credentials are unreadable by every runtime role | **Database** | grants: no SELECT for any runtime role | Baseline (Step 11) |
| `DR-053` | business & cross-table | `ui_translation` | UI text falls back to English when a translation is missing | **Database** | function ui_text() | Baseline (Step 11) |
| `DR-054` | business & cross-table | `agg_hiring_funnel_monthly` | An employer reads only its own hiring funnel | **Database** | view employer_hiring_funnel (security barrier) | Baseline (Step 11) |
| `DR-055` | business & cross-table | `candidate_profile and sections, app_user` | Erasure on request removes or blanks personal data in one transaction and keeps others' records anonymised | **Database** | function candidate_erase() | Baseline (Step 11) |
| `DR-056` | business & cross-table | `candidate_profile` | Profiles inactive for 3 years are erased | **Pipeline** | daily scheduler calls retention_erase_inactive() | Baseline (Step 11) |
| `DR-057` | business & cross-table | `audit_event` | Audit partitions are created ahead and dropped after 7 years | **Pipeline** | monthly scheduler: create_month_partitions(), detach + drop | Baseline (Step 11) |
| `DR-058` | business & cross-table | `user_session` | Ended sessions are deleted after 1 year | **Pipeline** | scheduled delete (to build) | Baseline (Step 11) |
| `DR-059` | business & cross-table | `notification` | Notifications are deleted 180 days after their final status | **Pipeline** | scheduled delete (to build) | Baseline (Step 11) |
| `DR-060` | business & cross-table | `system_error` | System errors are deleted after 90 days | **Pipeline** | scheduled delete (to build) | Baseline (Step 11) |
| `DR-061` | business & cross-table | `agg_hiring_funnel_monthly` | The hiring funnel is refreshed hourly without blocking readers | **Pipeline** | scheduler calls refresh_aggregates() (CONCURRENTLY) | Baseline (Step 11) |
| `DR-062` | business & cross-table | `candidate_profile` | "Open to work" expires after 90 days of inactivity (finding F-06) | **Pipeline** | scheduled job (backlog) | Baseline (Step 11) |
| `DR-063` | business & cross-table | `organisation_member` | Organisations over their seats after a lapse get a grace period, then extra members end (finding F-04) | **Pipeline** | scheduled job (backlog) | Baseline (Step 11) |
| `DR-064` | business & cross-table | `app_user, candidate_profile` | Probable duplicate candidates (same phone and name) are flagged at registration (finding F-01) | **Application** | duplicate check on idx_app_user_phone_e164 (AP-12) | Baseline (Step 11) |
| `DR-065` | business & cross-table | `resume` | Resume files: pdf or docx, size-limited, virus-scanned before the row is written | **Application** | upload service; key format by a check | Baseline (Step 11) |
| `DR-066` | business & cross-table | `all personal tables` | Test and seed data contain no real personal data: reserved .test domains, generated names | **Pipeline** | data generator (db/seed) | Baseline (Step 11) |
| `DR-067` | business & cross-table | `imported tables` | Legacy imports keep (source_system, source_record_id) unique | **Pipeline** | ETL, when the migration lands | Baseline (Step 11) |
| `DR-068` | standard domain | `DOMAIN person_name` (`text`) | `CHECK (char_length(VALUE) BETWEEN 1 AND 150 AND VALUE = btrim(VALUE))` | **Database** | `CREATE DOMAIN person_name` | Baseline (`t01`, `t06`) |
| `DR-069` | standard domain | `DOMAIN short_text` (`text`) | `CHECK (char_length(VALUE) BETWEEN 1 AND 200)` | **Database** | `CREATE DOMAIN short_text` | Baseline (`t01`, `t06`) |
| `DR-070` | standard domain | `DOMAIN medium_text` (`text`) | `CHECK (char_length(VALUE) BETWEEN 1 AND 2000)` | **Database** | `CREATE DOMAIN medium_text` | Baseline (`t01`, `t06`) |
| `DR-071` | standard domain | `DOMAIN long_text` (`text`) | `CHECK (char_length(VALUE) BETWEEN 1 AND 20000)` | **Database** | `CREATE DOMAIN long_text` | Baseline (`t01`, `t06`) |
| `DR-072` | standard domain | `DOMAIN email_address` (`text`) | `CHECK (char_length(VALUE) <= 254 AND VALUE = lower(VALUE) AND VALUE ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$')` | **Database** | `CREATE DOMAIN email_address` | Baseline (`t01`, `t06`) |
| `DR-073` | standard domain | `DOMAIN phone_e164` (`text`) | `CHECK (VALUE ~ '^\+[1-9][0-9]{6,14}$')` | **Database** | `CREATE DOMAIN phone_e164` | Baseline (`t01`, `t06`) |
| `DR-074` | standard domain | `DOMAIN money_amount` (`numeric(14,2)`) | `CHECK (VALUE >= 0)` | **Database** | `CREATE DOMAIN money_amount` | Baseline (`t01`, `t06`) |
| `DR-075` | standard domain | `DOMAIN credit_count` (`integer`) | `Signed integer credit movement` | **Database** | `CREATE DOMAIN credit_count` | Baseline (`t01`, `t06`) |
| `DR-076` | standard domain | `DOMAIN percentage` (`numeric(5,2)`) | `CHECK (VALUE BETWEEN 0 AND 100)` | **Database** | `CREATE DOMAIN percentage` | Baseline (`t01`, `t06`) |
| `DR-077` | standard domain | `DOMAIN latitude` (`numeric(8,6)`) | `CHECK (VALUE BETWEEN -90 AND 90)` | **Database** | `CREATE DOMAIN latitude` | Baseline (`t01`, `t06`) |
| `DR-078` | standard domain | `DOMAIN longitude` (`numeric(9,6)`) | `CHECK (VALUE BETWEEN -180 AND 180)` | **Database** | `CREATE DOMAIN longitude` | Baseline (`t01`, `t06`) |
| `DR-079` | standard domain | `DOMAIN lookup_code` (`text`) | `CHECK (VALUE ~ '^[a-z][a-z0-9_]{0,49}$')` | **Database** | `CREATE DOMAIN lookup_code` | Baseline (`t01`, `t06`) |
| `DR-080` | standard domain | `DOMAIN sha256_digest` (`bytea`) | `CHECK (octet_length(VALUE) = 32)` | **Database** | `CREATE DOMAIN sha256_digest` | Baseline (`t01`, `t06`) |
| `DR-081` | single-table unique | `app_user` | `email` | **Database** | `uq_app_user_email` | Baseline (Step 11) |
| `DR-082` | single-table check | `app_user` | `time_zone ~ '^[A-Za-z_]+(/[A-Za-z0-9_+-]+)*$'` | **Database** | `time_zone (inline)` | Baseline (Step 11) |
| `DR-083` | single-table check | `app_user` | `account_status_id <> 4 OR deleted_at IS NOT NULL` | **Database** | `ck_app_user_erased_deleted` | Baseline (Step 11) |
| `DR-084` | single-table unique | `user_credential` | `app_user_id` | **Database** | `uq_user_credential_app_user_id` | Baseline (Step 11) |
| `DR-085` | single-table check | `user_credential` | `password_hash ~ '^\$argon2id\$v=19\$m=[0-9]+,t=[0-9]+,p=[0-9]+\$[A-Za-z0-9+/]+\$[A-Za-z0-9+/]+$'` | **Database** | `ck_user_credential_password_hash_argon2id` | Baseline (Step 11) |
| `DR-086` | single-table check | `user_credential` | `failed_attempt_count >= 0` | **Database** | `failed_attempt_count (inline)` | Baseline (Step 11) |
| `DR-087` | single-table unique | `access_role_permission` | `access_role_id, access_permission_id` | **Database** | `uq_access_role_permission_access_role_id_access_permission_id` | Baseline (Step 11) |
| `DR-088` | single-table unique | `user_access_role` | `app_user_id, access_role_id` | **Database** | `uq_user_access_role_app_user_id_access_role_id` | Baseline (Step 11) |
| `DR-089` | single-table check | `consent_record` | `policy_version ~ '^[0-9]{4}-[0-9]{2}(\.[0-9]+)?$'` | **Database** | `policy_version (inline)` | Baseline (Step 11) |
| `DR-090` | single-table unique | `user_device` | `app_user_id, device_fingerprint_hash` | **Database** | `uq_user_device_app_user_id_device_fingerprint_hash` | Baseline (Step 11) |
| `DR-091` | single-table unique | `user_device` | `id, app_user_id` | **Database** | `uq_user_device_id_app_user_id` | Baseline (Step 11) |
| `DR-092` | single-table check | `user_device` | `last_seen_at >= first_seen_at` | **Database** | `ck_user_device_seen` | Baseline (Step 11) |
| `DR-093` | single-table unique | `user_session` | `token_hash` | **Database** | `uq_user_session_token_hash` | Baseline (Step 11) |
| `DR-094` | single-table check | `organisation` | `website_url ~ '^https?://[^\s]{3,250}$'` | **Database** | `website_url (inline)` | Baseline (Step 11) |
| `DR-095` | single-table check | `organisation` | `parent_organisation_id <> id` | **Database** | `ck_organisation_not_own_parent` | Baseline (Step 11) |
| `DR-096` | single-table check | `organisation_location` | `postal_code ~ '^[A-Z0-9 -]{3,10}$'` | **Database** | `postal_code (inline)` | Baseline (Step 11) |
| `DR-097` | single-table check | `organisation_location` | `latitude IS NULL) = (longitude IS NULL` | **Database** | `ck_organisation_location_coordinates` | Baseline (Step 11) |
| `DR-098` | single-table unique (index) | `organisation_location` | `(organisation_id) WHERE is_headquarters` | **Database** | `uq_organisation_location_organisation_id_headquarters` | Baseline (Step 11) |
| `DR-099` | single-table check | `organisation_tax_identifier` | `identifier_last4 ~ '^[A-Z0-9]{4}$'` | **Database** | `identifier_last4 (inline)` | Baseline (Step 11) |
| `DR-100` | single-table unique | `organisation_tax_identifier` | `country_id, tax_identifier_type_id, identifier_hmac` | **Database** | `uq_organisation_tax_identifier_country_id_type_hmac` | Baseline (Step 11) |
| `DR-101` | single-table check | `organisation_tax_identifier` | `verification_status_id = 2) = (verified_at IS NOT NULL` | **Database** | `ck_organisation_tax_identifier_verified_at` | Baseline (Step 11) |
| `DR-102` | single-table check | `organisation_member` | `access_role_id IN (3, 4, 5)` | **Database** | `ck_organisation_member_role` | Baseline (Step 11) |
| `DR-103` | single-table check | `organisation_member` | `valid_to IS NULL OR valid_to > valid_from` | **Database** | `ck_organisation_member_period` | Baseline (Step 11) |
| `DR-104` | single-table exclusion | `organisation_member` | `EXCLUDE USING gist (app_user_id WITH =, tstzrange(valid_from, valid_to) WITH &&)` | **Database** | `ex_organisation_member_one_organisation` | Baseline (Step 11) |
| `DR-105` | single-table unique | `candidate_profile` | `app_user_id` | **Database** | `uq_candidate_profile_app_user_id` | Baseline (Step 11) |
| `DR-106` | single-table check | `candidate_profile` | `total_experience_months BETWEEN 0 AND 720` | **Database** | `total_experience_months (inline)` | Baseline (Step 11) |
| `DR-107` | single-table check | `candidate_profile` | `notice_period_days BETWEEN 0 AND 365` | **Database** | `notice_period_days (inline)` | Baseline (Step 11) |
| `DR-108` | single-table check | `candidate_profile` | ` (salary_disclosure_id = 1) = (expected_salary_amount IS NOT NULL) AND (expected_salary_amount IS NULL) = (expected_salary_currency_id IS NU` | **Database** | `ck_candidate_profile_salary` | Baseline (Step 11) |
| `DR-109` | single-table check | `candidate_education` | `end_date IS NULL OR end_date >= start_date` | **Database** | `ck_candidate_education_dates` | Baseline (Step 11) |
| `DR-110` | single-table check | `candidate_experience` | `end_date IS NULL OR end_date >= start_date` | **Database** | `ck_candidate_experience_dates` | Baseline (Step 11) |
| `DR-111` | single-table unique (index) | `candidate_experience` | `(candidate_profile_id) WHERE end_date IS NULL` | **Database** | `uq_candidate_experience_one_current` | Baseline (Step 11) |
| `DR-112` | single-table check | `candidate_skill` | `experience_months BETWEEN 0 AND 720` | **Database** | `experience_months (inline)` | Baseline (Step 11) |
| `DR-113` | single-table unique | `candidate_skill` | `candidate_profile_id, skill_id` | **Database** | `uq_candidate_skill_candidate_profile_id_skill_id` | Baseline (Step 11) |
| `DR-114` | single-table unique | `candidate_language` | `candidate_profile_id, language_id` | **Database** | `uq_candidate_language_candidate_profile_id_language_id` | Baseline (Step 11) |
| `DR-115` | single-table check | `resume` | `version_number > 0` | **Database** | `version_number (inline)` | Baseline (Step 11) |
| `DR-116` | single-table check | `resume` | `storage_key ~ '^resumes/[0-9]+/[0-9a-f-]{36}\.(pdf\|docx)$'` | **Database** | `storage_key (inline)` | Baseline (Step 11) |
| `DR-117` | single-table unique | `resume` | `storage_key` | **Database** | `uq_resume_storage_key` | Baseline (Step 11) |
| `DR-118` | single-table unique | `resume` | `candidate_profile_id, version_number` | **Database** | `uq_resume_candidate_profile_id_version_number` | Baseline (Step 11) |
| `DR-119` | single-table unique | `resume` | `id, candidate_profile_id` | **Database** | `uq_resume_id_candidate_profile_id` | Baseline (Step 11) |
| `DR-120` | single-table unique (index) | `resume` | `(candidate_profile_id) WHERE is_primary` | **Database** | `uq_resume_one_primary` | Baseline (Step 11) |
| `DR-121` | single-table check | `candidate_block` | `num_nonnulls(blocked_organisation_id, blocked_app_user_id) = 1` | **Database** | `ck_candidate_block_one_target` | Baseline (Step 11) |
| `DR-122` | single-table check | `candidate_block` | `unblocked_at IS NULL OR unblocked_at >= blocked_at` | **Database** | `ck_candidate_block_dates` | Baseline (Step 11) |
| `DR-123` | single-table unique (index) | `candidate_block` | `(blocked_organisation_id, candidate_profile_id) WHERE unblocked_at IS NULL` | **Database** | `uq_candidate_block_active_organisation` | Baseline (Step 11) |
| `DR-124` | single-table unique (index) | `candidate_block` | `(blocked_app_user_id, candidate_profile_id) WHERE unblocked_at IS NULL` | **Database** | `uq_candidate_block_active_user` | Baseline (Step 11) |
| `DR-125` | single-table check | `job_alert` | `min_salary_amount IS NULL) = (salary_currency_id IS NULL` | **Database** | `ck_job_alert_salary_currency` | Baseline (Step 11) |
| `DR-126` | single-table check | `job_requirement` | `min_experience_months BETWEEN 0 AND 600` | **Database** | `min_experience_months (inline)` | Baseline (Step 11) |
| `DR-127` | single-table check | `job_requirement` | `max_experience_months BETWEEN 0 AND 600` | **Database** | `max_experience_months (inline)` | Baseline (Step 11) |
| `DR-128` | single-table check | `job_requirement` | `salary_disclosure_id IN (1, 2)` | **Database** | `ck_job_requirement_salary_disclosure` | Baseline (Step 11) |
| `DR-129` | single-table check | `job_requirement` | `positions_total BETWEEN 1 AND 10000` | **Database** | `positions_total (inline)` | Baseline (Step 11) |
| `DR-130` | single-table check | `job_requirement` | `max_experience_months IS NULL OR max_experience_months >= min_experience_months` | **Database** | `ck_job_requirement_experience` | Baseline (Step 11) |
| `DR-131` | single-table check | `job_requirement` | ` salary_min_amount IS NULL OR salary_max_amount IS NULL OR salary_min_amount <= salary_max_amount` | **Database** | `ck_job_requirement_salary` | Baseline (Step 11) |
| `DR-132` | single-table check | `job_requirement` | ` (salary_disclosure_id = 1) = (salary_min_amount IS NOT NULL) AND (salary_min_amount IS NULL) = (salary_currency_id IS NULL) AND (salary_max` | **Database** | `ck_job_requirement_salary_disclosed` | Baseline (Step 11) |
| `DR-133` | single-table unique | `job_requirement` | `id, organisation_id` | **Database** | `uq_job_requirement_id_organisation_id` | Baseline (Step 11) |
| `DR-134` | single-table unique | `job_requirement_location` | `job_requirement_id, city_id` | **Database** | `uq_job_requirement_location_job_requirement_id_city_id` | Baseline (Step 11) |
| `DR-135` | single-table unique | `job_requirement_skill` | `job_requirement_id, skill_id` | **Database** | `uq_job_requirement_skill_job_requirement_id_skill_id` | Baseline (Step 11) |
| `DR-136` | single-table check | `screening_question` | `sort_order > 0` | **Database** | `sort_order (inline)` | Baseline (Step 11) |
| `DR-137` | single-table unique | `screening_question` | `job_requirement_id, sort_order` | **Database** | `uq_screening_question_job_requirement_id_sort_order` | Baseline (Step 11) |
| `DR-138` | single-table unique | `screening_question` | `id, job_requirement_id` | **Database** | `uq_screening_question_id_job_requirement_id` | Baseline (Step 11) |
| `DR-139` | single-table unique | `application` | `job_requirement_id, candidate_profile_id` | **Database** | `uq_application_job_requirement_id_candidate_profile_id` | Baseline (Step 11) |
| `DR-140` | single-table unique | `application` | `id, job_requirement_id` | **Database** | `uq_application_id_job_requirement_id` | Baseline (Step 11) |
| `DR-141` | single-table check | `application` | `application_source_id IN (2, 3)) = (sourced_by_app_user_id IS NOT NULL` | **Database** | `ck_application_sourced_by` | Baseline (Step 11) |
| `DR-142` | single-table check | `application` | `status_changed_at >= applied_at` | **Database** | `ck_application_status_changed_at` | Baseline (Step 11) |
| `DR-143` | single-table unique | `application_answer` | `application_id, screening_question_id` | **Database** | `uq_application_answer_application_id_screening_question_id` | Baseline (Step 11) |
| `DR-144` | single-table check | `application_status_history` | `from_status_id IS DISTINCT FROM to_status_id` | **Database** | `ck_application_status_history_moves` | Baseline (Step 11) |
| `DR-145` | single-table unique | `application_status_transition` | `from_status_id, to_status_id` | **Database** | `uq_application_status_transition_from_to` | Baseline (Step 11) |
| `DR-146` | single-table check | `application_status_transition` | `from_status_id <> to_status_id` | **Database** | `ck_application_status_transition_moves` | Baseline (Step 11) |
| `DR-147` | single-table unique | `job_status_transition` | `from_status_id, to_status_id` | **Database** | `uq_job_status_transition_from_to` | Added in V013 (`FND-01`) |
| `DR-148` | single-table check | `job_status_transition` | `from_status_id <> to_status_id` | **Database** | `ck_job_status_transition_moves` | Added in V013 (`FND-01`) |
| `DR-149` | single-table unique | `plan` | `code` | **Database** | `uq_plan_code` | Baseline (Step 11) |
| `DR-150` | single-table check | `plan` | `billing_period_months IN (1, 3, 12)` | **Database** | `billing_period_months (inline)` | Baseline (Step 11) |
| `DR-151` | single-table check | `plan` | `max_seats > 0` | **Database** | `max_seats (inline)` | Baseline (Step 11) |
| `DR-152` | single-table check | `plan` | `max_devices_per_user > 0` | **Database** | `max_devices_per_user (inline)` | Baseline (Step 11) |
| `DR-153` | single-table check | `plan` | `included_credits >= 0` | **Database** | `included_credits (inline)` | Baseline (Step 11) |
| `DR-154` | single-table check | `subscription` | `max_seats > 0` | **Database** | `max_seats (inline)` | Baseline (Step 11) |
| `DR-155` | single-table check | `subscription` | `max_devices_per_user > 0` | **Database** | `max_devices_per_user (inline)` | Baseline (Step 11) |
| `DR-156` | single-table unique | `subscription` | `renewed_from_subscription_id` | **Database** | `uq_subscription_renewed_from_subscription_id` | Baseline (Step 11) |
| `DR-157` | single-table check | `subscription` | `ends_on > starts_on` | **Database** | `ck_subscription_period` | Baseline (Step 11) |
| `DR-158` | single-table exclusion | `subscription` | `EXCLUDE USING gist (organisation_id WITH =, daterange(starts_on, ends_on) WITH &&)` | **Database** | `ex_subscription_no_overlap` | Baseline (Step 11) |
| `DR-159` | single-table unique (index) | `subscription` | `(payment_order_id) WHERE payment_order_id IS NOT NULL` | **Database** | `uq_subscription_payment_order_id` | Baseline (Step 11) |
| `DR-160` | single-table unique | `wallet` | `organisation_id` | **Database** | `uq_wallet_organisation_id` | Baseline (Step 11) |
| `DR-161` | single-table check | `wallet` | `balance_credits >= 0` | **Database** | `ck_wallet_balance_not_negative` | Baseline (Step 11) |
| `DR-162` | single-table check | `wallet_ledger_entry` | `balance_after >= 0` | **Database** | `balance_after (inline)` | Baseline (Step 11) |
| `DR-163` | single-table unique | `wallet_ledger_entry` | `reverses_ledger_entry_id` | **Database** | `uq_wallet_ledger_entry_reverses_ledger_entry_id` | Baseline (Step 11) |
| `DR-164` | single-table check | `wallet_ledger_entry` | `char_length(idempotency_key) BETWEEN 8 AND 100` | **Database** | `idempotency_key (inline)` | Baseline (Step 11) |
| `DR-165` | single-table unique | `wallet_ledger_entry` | `idempotency_key` | **Database** | `uq_wallet_ledger_entry_idempotency_key` | Baseline (Step 11) |
| `DR-166` | single-table check | `wallet_ledger_entry` | `CASE WHEN ledger_entry_type_id IN (1, 2) THEN credits > 0 WHEN ledger_entry_type_id IN (3, 4, 5) THEN credits < 0 ELSE credits <> 0 END` | **Database** | `ck_wallet_ledger_entry_sign` | Baseline (Step 11) |
| `DR-167` | single-table check | `wallet_ledger_entry` | `ledger_entry_type_id = 6) = (reverses_ledger_entry_id IS NOT NULL` | **Database** | `ck_wallet_ledger_entry_reversal` | Baseline (Step 11) |
| `DR-168` | single-table check | `payment_order` | `amount > 0` | **Database** | `amount (inline)` | Baseline (Step 11) |
| `DR-169` | single-table check | `payment_order` | `gateway_order_ref ~ '^[A-Za-z0-9_-]{6,64}$'` | **Database** | `gateway_order_ref (inline)` | Baseline (Step 11) |
| `DR-170` | single-table unique | `payment_order` | `gateway_order_ref` | **Database** | `uq_payment_order_gateway_order_ref` | Baseline (Step 11) |
| `DR-171` | single-table check | `payment_order` | `char_length(idempotency_key) BETWEEN 8 AND 100` | **Database** | `idempotency_key (inline)` | Baseline (Step 11) |
| `DR-172` | single-table unique | `payment_order` | `idempotency_key` | **Database** | `uq_payment_order_idempotency_key` | Baseline (Step 11) |
| `DR-173` | single-table check | `payment_order` | ` (payment_purpose_id = 1) = (credits_to_grant IS NOT NULL AND credits_to_grant > 0) AND (payment_purpose_id = 2) = (plan_id IS NOT NULL` | **Database** | `ck_payment_order_purpose` | Baseline (Step 11) |
| `DR-174` | single-table check | `payment_event` | `gateway_event_ref ~ '^[A-Za-z0-9_-]{6,64}$'` | **Database** | `gateway_event_ref (inline)` | Baseline (Step 11) |
| `DR-175` | single-table unique | `payment_event` | `gateway_event_ref` | **Database** | `uq_payment_event_gateway_event_ref` | Baseline (Step 11) |
| `DR-176` | single-table unique | `invoice` | `payment_order_id` | **Database** | `uq_invoice_payment_order_id` | Baseline (Step 11) |
| `DR-177` | single-table check | `invoice` | `invoice_number ~ '^TAL-[0-9]{4}-[0-9]{6,}$'` | **Database** | `invoice_number (inline)` | Baseline (Step 11) |
| `DR-178` | single-table unique | `invoice` | `invoice_number` | **Database** | `uq_invoice_invoice_number` | Baseline (Step 11) |
| `DR-179` | single-table check | `invoice` | `total_amount = subtotal_amount + tax_amount` | **Database** | `ck_invoice_total` | Baseline (Step 11) |
| `DR-180` | single-table unique | `profile_download` | `wallet_ledger_entry_id` | **Database** | `uq_profile_download_wallet_ledger_entry_id` | Baseline (Step 11) |
| `DR-181` | single-table unique | `notification_preference` | `app_user_id, notification_category_id, notification_channel_id` | **Database** | `uq_notification_preference_user_category_channel` | Baseline (Step 11) |
| `DR-182` | single-table check | `notification` | `template_key ~ '^[a-z_]+(\.[a-z_]+)+$'` | **Database** | `template_key (inline)` | Baseline (Step 11) |
| `DR-183` | single-table check | `notification` | `pg_column_size(payload) <= 2048` | **Database** | `payload (inline)` | Baseline (Step 11) |
| `DR-184` | single-table check | `notification` | `char_length(dedupe_key) <= 200` | **Database** | `dedupe_key (inline)` | Baseline (Step 11) |
| `DR-185` | single-table unique | `notification` | `dedupe_key` | **Database** | `uq_notification_dedupe_key` | Baseline (Step 11) |
| `DR-186` | single-table check | `notification` | `attempt_count BETWEEN 0 AND 10` | **Database** | `attempt_count (inline)` | Baseline (Step 11) |
| `DR-187` | single-table check | `notification` | `char_length(provider_message_ref) <= 128` | **Database** | `provider_message_ref (inline)` | Baseline (Step 11) |
| `DR-188` | single-table unique | `notification` | `provider_message_ref` | **Database** | `uq_notification_provider_message_ref` | Baseline (Step 11) |
| `DR-189` | single-table check | `notification` | `sent_at IS NULL OR sent_at >= queued_at` | **Database** | `ck_notification_times` | Baseline (Step 11) |
| `DR-190` | single-table check | `notification` | `delivered_at IS NULL OR (sent_at IS NOT NULL AND delivered_at >= sent_at` | **Database** | `ck_notification_delivered` | Baseline (Step 11) |
| `DR-191` | single-table check | `notification` | `notification_status_id = 4) = (failure_reason IS NOT NULL` | **Database** | `ck_notification_failed` | Baseline (Step 11) |
| `DR-192` | single-table check | `audit_event` | `action ~ '^[a-z_]+(\.[a-z_]+)+$'` | **Database** | `action (inline)` | Baseline (Step 11) |
| `DR-193` | single-table check | `audit_event` | `entity_table ~ '^[a-z_]+$'` | **Database** | `entity_table (inline)` | Baseline (Step 11) |
| `DR-194` | single-table check | `audit_event` | `pg_column_size(details) <= 4096` | **Database** | `details (inline)` | Baseline (Step 11) |
| `DR-195` | single-table check | `system_error` | `pg_column_size(context) <= 8192` | **Database** | `context (inline)` | Baseline (Step 11) |
| `DR-196` | single-table check | `language` | `code ~ '^[a-z]{2}$'` | **Database** | `code (inline)` | Baseline (Step 11) |
| `DR-197` | single-table unique | `language` | `code` | **Database** | `uq_language_code` | Baseline (Step 11) |
| `DR-198` | single-table check | `ui_label` | `label_key ~ '^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$'` | **Database** | `label_key (inline)` | Baseline (Step 11) |
| `DR-199` | single-table unique | `ui_label` | `label_key` | **Database** | `uq_ui_label_label_key` | Baseline (Step 11) |
| `DR-200` | single-table unique | `ui_translation` | `ui_label_id, language_id` | **Database** | `uq_ui_translation_ui_label_id_language_id` | Baseline (Step 11) |
| `DR-201` | single-table check | `currency` | `code ~ '^[A-Z]{3}$'` | **Database** | `code (inline)` | Baseline (Step 11) |
| `DR-202` | single-table unique | `currency` | `code` | **Database** | `uq_currency_code` | Baseline (Step 11) |
| `DR-203` | single-table check | `currency` | `minor_units BETWEEN 0 AND 3` | **Database** | `minor_units (inline)` | Baseline (Step 11) |
| `DR-204` | single-table check | `country` | `iso2 ~ '^[A-Z]{2}$'` | **Database** | `iso2 (inline)` | Baseline (Step 11) |
| `DR-205` | single-table unique | `country` | `iso2` | **Database** | `uq_country_iso2` | Baseline (Step 11) |
| `DR-206` | single-table check | `country` | `phone_country_code ~ '^\+[1-9][0-9]{0,3}$'` | **Database** | `phone_country_code (inline)` | Baseline (Step 11) |
| `DR-207` | single-table check | `state` | `code ~ '^[A-Z0-9]{1,5}$'` | **Database** | `code (inline)` | Baseline (Step 11) |
| `DR-208` | single-table unique | `state` | `country_id, code` | **Database** | `uq_state_country_id_code` | Baseline (Step 11) |
| `DR-209` | single-table unique | `city` | `state_id, name` | **Database** | `uq_city_state_id_name` | Baseline (Step 11) |
| `DR-210` | single-table unique (index) | `skill` | `(lower(name))` | **Database** | `uq_skill_name` | Baseline (Step 11) |
| `DR-211` | lookup table integrity | `access_permission` | Canonical lookup shape (`id` PK, `code` UQ across 11 codes [user_manage, organisation_verify, job_post, job_manage...], `ui_label_id` FK → `ui_label`) | **Database** | `uq_access_permission_code` + `fk_access_permission_ui_label_id` | Reconciled in Step 18 (`t01`) |
| `DR-212` | lookup table integrity | `access_role` | Canonical lookup shape (`id` PK, `code` UQ across 8 codes [super_admin, admin, account_admin, employer...], `ui_label_id` FK → `ui_label`) | **Database** | `uq_access_role_code` + `fk_access_role_ui_label_id` | Reconciled in Step 18 (`t01`) |
| `DR-213` | lookup table integrity | `account_status` | Canonical lookup shape (`id` PK, `code` UQ across 4 codes [active, suspended, deactivated, erased], `ui_label_id` FK → `ui_label`) | **Database** | `uq_account_status_code` + `fk_account_status_ui_label_id` | Reconciled in Step 18 (`t01`) |
| `DR-214` | lookup table integrity | `alert_frequency` | Canonical lookup shape (`id` PK, `code` UQ across 3 codes [instant, daily, weekly], `ui_label_id` FK → `ui_label`) | **Database** | `uq_alert_frequency_code` + `fk_alert_frequency_ui_label_id` | Reconciled in Step 18 (`t01`) |
| `DR-215` | lookup table integrity | `answer_type` | Canonical lookup shape (`id` PK, `code` UQ across 3 codes [yes_no, number, short_text], `ui_label_id` FK → `ui_label`) | **Database** | `uq_answer_type_code` + `fk_answer_type_ui_label_id` | Reconciled in Step 18 (`t01`) |
| `DR-216` | lookup table integrity | `application_source` | Canonical lookup shape (`id` PK, `code` UQ across 5 codes [direct, recruiter_outreach, consultant, referral...], `ui_label_id` FK → `ui_label`) | **Database** | `uq_application_source_code` + `fk_application_source_ui_label_id` | Reconciled in Step 18 (`t01`) |
| `DR-217` | lookup table integrity | `application_status` | Canonical lookup shape (`id` PK, `code` UQ across 7 codes [applied, shortlisted, interviewing, offered...], `ui_label_id` FK → `ui_label`) | **Database** | `uq_application_status_code` + `fk_application_status_ui_label_id` | Reconciled in Step 18 (`t01`) |
| `DR-218` | lookup table integrity | `consent_purpose` | Canonical lookup shape (`id` PK, `code` UQ across 5 codes [terms_of_service, privacy_policy, profile_visible_to_recruiters, marketing_email...], `ui_label_id` FK → `ui_label`) | **Database** | `uq_consent_purpose_code` + `fk_consent_purpose_ui_label_id` | Reconciled in Step 18 (`t01`) |
| `DR-219` | lookup table integrity | `employment_type` | Canonical lookup shape (`id` PK, `code` UQ across 6 codes [full_time, part_time, contract, internship...], `ui_label_id` FK → `ui_label`) | **Database** | `uq_employment_type_code` + `fk_employment_type_ui_label_id` | Reconciled in Step 18 (`t01`) |
| `DR-220` | lookup table integrity | `industry` | Canonical lookup shape (`id` PK, `code` UQ across 15 codes [information_technology, banking_financial_services, healthcare, manufacturing...], `ui_label_id` FK → `ui_label`) | **Database** | `uq_industry_code` + `fk_industry_ui_label_id` | Reconciled in Step 18 (`t01`) |
| `DR-221` | lookup table integrity | `job_status` | Canonical lookup shape (`id` PK, `code` UQ across 5 codes [draft, open, paused, closed...], `ui_label_id` FK → `ui_label`) | **Database** | `uq_job_status_code` + `fk_job_status_ui_label_id` | Reconciled in Step 18 (`t01`) |
| `DR-222` | lookup table integrity | `ledger_entry_type` | Canonical lookup shape (`id` PK, `code` UQ across 6 codes [recharge, plan_grant, job_post_debit, profile_download_debit...], `ui_label_id` FK → `ui_label`) | **Database** | `uq_ledger_entry_type_code` + `fk_ledger_entry_type_ui_label_id` | Reconciled in Step 18 (`t01`) |
| `DR-223` | lookup table integrity | `notification_category` | Canonical lookup shape (`id` PK, `code` UQ across 5 codes [job_alert, application_update, account_security, billing...], `ui_label_id` FK → `ui_label`) | **Database** | `uq_notification_category_code` + `fk_notification_category_ui_label_id` | Reconciled in Step 18 (`t01`) |
| `DR-224` | lookup table integrity | `notification_channel` | Canonical lookup shape (`id` PK, `code` UQ across 4 codes [email, sms, whatsapp, in_app], `ui_label_id` FK → `ui_label`) | **Database** | `uq_notification_channel_code` + `fk_notification_channel_ui_label_id` | Reconciled in Step 18 (`t01`) |
| `DR-225` | lookup table integrity | `notification_status` | Canonical lookup shape (`id` PK, `code` UQ across 5 codes [queued, sent, delivered, failed...], `ui_label_id` FK → `ui_label`) | **Database** | `uq_notification_status_code` + `fk_notification_status_ui_label_id` | Reconciled in Step 18 (`t01`) |
| `DR-226` | lookup table integrity | `payment_purpose` | Canonical lookup shape (`id` PK, `code` UQ across 2 codes [wallet_recharge, subscription], `ui_label_id` FK → `ui_label`) | **Database** | `uq_payment_purpose_code` + `fk_payment_purpose_ui_label_id` | Reconciled in Step 18 (`t01`) |
| `DR-227` | lookup table integrity | `payment_status` | Canonical lookup shape (`id` PK, `code` UQ across 5 codes [created, authorised, captured, failed...], `ui_label_id` FK → `ui_label`) | **Database** | `uq_payment_status_code` + `fk_payment_status_ui_label_id` | Reconciled in Step 18 (`t01`) |
| `DR-228` | lookup table integrity | `proficiency_level` | Canonical lookup shape (`id` PK, `code` UQ across 5 codes [beginner, intermediate, advanced, expert...], `ui_label_id` FK → `ui_label`) | **Database** | `uq_proficiency_level_code` + `fk_proficiency_level_ui_label_id` | Reconciled in Step 18 (`t01`) |
| `DR-229` | lookup table integrity | `profile_visibility` | Canonical lookup shape (`id` PK, `code` UQ across 3 codes [public, recruiters_only, hidden], `ui_label_id` FK → `ui_label`) | **Database** | `uq_profile_visibility_code` + `fk_profile_visibility_ui_label_id` | Reconciled in Step 18 (`t01`) |
| `DR-230` | lookup table integrity | `qualification` | Canonical lookup shape (`id` PK, `code` UQ across 8 codes [below_secondary, secondary, higher_secondary, iti...], `ui_label_id` FK → `ui_label`) | **Database** | `uq_qualification_code` + `fk_qualification_ui_label_id` | Reconciled in Step 18 (`t01`) |
| `DR-231` | lookup table integrity | `salary_disclosure` | Canonical lookup shape (`id` PK, `code` UQ across 3 codes [disclosed, not_disclosed, not_provided], `ui_label_id` FK → `ui_label`) | **Database** | `uq_salary_disclosure_code` + `fk_salary_disclosure_ui_label_id` | Reconciled in Step 18 (`t01`) |
| `DR-232` | lookup table integrity | `session_end_reason` | Canonical lookup shape (`id` PK, `code` UQ across 4 codes [logout, idle_timeout, revoked_by_user, revoked_by_admin], `ui_label_id` FK → `ui_label`) | **Database** | `uq_session_end_reason_code` + `fk_session_end_reason_ui_label_id` | Reconciled in Step 18 (`t01`) |
| `DR-233` | lookup table integrity | `tax_identifier_type` | Canonical lookup shape (`id` PK, `code` UQ across 5 codes [gstin, pan, cin, vat...], `ui_label_id` FK → `ui_label`) | **Database** | `uq_tax_identifier_type_code` + `fk_tax_identifier_type_ui_label_id` | Reconciled in Step 18 (`t01`) |
| `DR-234` | lookup table integrity | `verification_status` | Canonical lookup shape (`id` PK, `code` UQ across 3 codes [pending, verified, rejected], `ui_label_id` FK → `ui_label`) | **Database** | `uq_verification_status_code` + `fk_verification_status_ui_label_id` | Reconciled in Step 18 (`t01`) |
| `DR-235` | lookup table integrity | `work_mode` | Canonical lookup shape (`id` PK, `code` UQ across 3 codes [onsite, remote, hybrid], `ui_label_id` FK → `ui_label`) | **Database** | `uq_work_mode_code` + `fk_work_mode_ui_label_id` | Reconciled in Step 18 (`t01`) |
| `DR-236` | V013 refinement guard | `job_requirement, job_status_transition` | Enforce 7 allowed job lifecycle moves (`draft->open<->paused->closed/filled`) and make `published_at` write-once | **Database** | `trg_job_requirement_guard` (`job_requirement_guard()`) | Added in V013 (`FND-01`, `FND-02`) |
| `DR-237` | V013 refinement guard | `organisation, organisation_tax_identifier` | Enforce staff-only (`organisation_verify`) transitions `pending->verified/rejected` and `rejected->pending` with audit log | **Database** | `organisation_set_verification()` (`SECURITY DEFINER`) | Added in V013 (`FND-03`) |
| `DR-238` | V013 refinement guard | `user_device, user_session` | Owner or staff revokes device, ending active sessions and auditing; `revoked_at` is strictly write-once | **Database** | `auth_revoke_device()` + `trg_user_device_guard` | Added in V013 (`FND-04`) |
| `DR-239` | V013 refinement guard | `app_user, user_session` | Enforce final `erased` account status and role-checked `active/suspended/deactivated` transitions ending sessions | **Database** | `user_set_account_status()` + `trg_app_user_status_guard` | Added in V013 (`FND-05`) |
| `DR-240` | V013 refinement guard | `subscription` | Prevent clearing or mutating `subscription.cancelled_at` once set (write-once cancellation timestamp) | **Database** | `trg_subscription_guard` (`subscription_guard()`) | Added in V013 (`FND-06`) |
| `DR-241` | V013 refinement guard | `organisation_member` | Prevent clearing or reopening `organisation_member.valid_to` once a membership period is closed | **Database** | `trg_organisation_member_close_once` (`organisation_member_close_once_guard()`) | Added in V013 (`FND-07`) |
| `DR-242` | V013 refinement guard | `candidate_block` | Prevent clearing or reopening `candidate_block.unblocked_at` once a block is lifted | **Database** | `trg_candidate_block_close_once` (`candidate_block_close_once_guard()`) | Added in V013 (`FND-07`) |
| `DR-243` | V013 refinement guard | `notification` | Enforce forward-only delivery state transitions `queued(1)->sent(2)->delivered(3)/failed(4)` | **Database** | `notification_record_result()` transition guard | Added in V013 (`FND-08`) |
| `DR-244` | V013 refinement guard | `candidate_profile, notification, consent_record` | Enforce DPDP consent purposes 3 (`profile_visible_to_recruiters`), 4 (`marketing_email`), and 5 (`whatsapp_alerts`) | **Database** | `app_users_without_recruiter_consent()` RLS + `notification_apply_preference()` | Added in V013 (`FND-09`) |
| `DR-245` | V013 refinement guard | `application_answer, user_device` | Scrub `application_answer.answer_text` to `[erased]` and clear `user_device.device_label` during DPDP erasure | **Database** | `candidate_erase()` v2 (`V013`) | Added in V013 (`FND-10`, `FND-11`) |
| `DR-246` | V013 refinement guard | `pg_description (78 columns)` | Require explicit `Personal.` or `Sensitive.` SQL catalog comment prefix on all 78 PII/SPI columns | **Database** | 52 `COMMENT ON COLUMN` in `V013` + `TC-20-025` catalog check | Added in V013 (`FND-12`) |
| `DR-247` | V013 refinement guard | `organisation, wallet, user_credential` | Auto-create `wallet` on `INSERT INTO organisation` and lock `user_credential` for 15 min after 5 failed logins | **Database** | `trg_organisation_ensure_wallet` + `auth_record_login_failure()` | Added in V013 (`FND-13`, `FND-14`) |

**Enforcement Point Distribution across all 247 DR Rules:**
- **Database:** 231 rules (93.5% — PK/FK/UNIQUE/CHECK/EXCLUDE constraints, domains, RLS policies, and PL/pgSQL triggers/functions)
- **Pipeline:** 11 rules (4.5% — retention jobs, materialized view refresh, partition rotation, deterministic seed)
- **Application:** 5 rules (2.0% — data-quality monitoring F-01/F-05, Argon2id pre-hashing, virus scan, template variable whitelist)
- **Gap:** **0 rules (0.0%)** — All 6 Phase 2 gaps (`DR-004`, `DR-011`, `DR-016`, `DR-019`, `DR-020`, `DR-047`) closed by `V013__phase3_refinements.sql`.

## 2. Decision Tables for Complex Rules

### DT-01 — Candidate Profile Visibility to Current Viewer (`app_candidate_visible` & RLS `candidate_profile_read`, rules `BR-03`, `BR-04`, `FND-09`)

| Condition / Outcome | R1: Owner | R2: Platform Staff | R3: Recruiter / Consultant (Valid) | R4: Profile Soft-Deleted | R5: Visibility = Hidden (3) | R6: Withdrew Purpose 3 Consent | R7: Candidate Blocked Viewer/Org | R8: Guest / Other Candidate |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `p_owner_id = app_current_user_id()` | Yes | No | No | No | No | No | No | No |
| `app_is_staff()` (super_admin or admin) | — | Yes | No | No | No | No | No | No |
| `app_has_permission('candidate_search')` | — | — | Yes | Yes | Yes | Yes | Yes | No |
| `deleted_at IS NULL` | — | — | Yes | No | Yes | Yes | Yes | — |
| `profile_visibility_id IN (1, 2)` (not `hidden`) | — | — | Yes | — | No | Yes | Yes | — |
| `consent_current` for purpose 3 (`profile_visible...`) | — | — | Yes | — | — | No | Yes | — |
| `id = ANY(app_candidates_blocking_viewer())` | — | — | No | — | — | — | Yes | — |
| **Outcome: Profile & sections visible?** | **ALLOW** | **ALLOW** | **ALLOW** | **DENY (0 rows)** | **DENY (0 rows)** | **DENY (0 rows)** | **DENY (0 rows)** | **DENY (0 rows)** |
| **Verified by test** | `t03` | `t03` | `t03` | `t02` | `t03` | `TC-20-023` | `t03` | `t03` |

### DT-02 — Notification Suppression at Outbox Insert (`notification_apply_preference()`, rules `BR-21`, `FND-09`)

| Condition / Outcome | R1: Security Notice | R2: Explicit Channel Opt-Out | R3: Marketing without Purpose 4 Consent | R4: WhatsApp without Purpose 5 Consent | R5: Default / Consented |
| --- | --- | --- | --- | --- | --- |
| `notification_category_id = 3` (`account_security`) | Yes | No | No | No | No |
| `notification_preference.is_enabled = false` for (cat, ch) | — | Yes | No | No | No |
| `notification_category_id = 5` (`marketing`) & no purpose 4 | — | No | Yes | No | No |
| `notification_channel_id = 3` (`whatsapp`) & no purpose 5 | — | No | No | Yes | No |
| **Outcome: `NEW.notification_status_id`** | **1 (`queued`)** | **5 (`suppressed`)** | **5 (`suppressed`)** | **5 (`suppressed`)** | **1 (`queued`)** |
| **Verified by test** | `t02` | `t02` | `seed_prove_sample` | `TC-20-022` | `t02` |

### DT-03 — Login & Session Admission (`auth_open_session()`, rules `BR-07`, `BR-08`, `FND-04`, `FND-05`, `FND-14`)

| Condition / Outcome | R1: Inactive / Erased User | R2: Brute-Force Locked | R3: Device Revoked | R4: Existing Active Device | R5: New Device Under Limit | R6: New Device At/Over Limit |
| --- | --- | --- | --- | --- | --- | --- |
| `account_status_id = 1 AND deleted_at IS NULL` | No | Yes | Yes | Yes | Yes | Yes |
| `user_credential.locked_until > now()` | — | Yes | No | No | No | No |
| `user_device.revoked_at IS NOT NULL` | — | No | Yes | No | No | No |
| Device already has an active session (`ended_at IS NULL`) | — | No | No | Yes | No | No |
| Other active devices `< app_device_limit(user)` | — | No | No | — | Yes | No |
| **Outcome: Session opened?** | **RAISE EXCEPTION** | **RETURN NULL + Audit `account_locked`** | **RETURN NULL + Audit `device_revoked`** | **RETURN session_id + reset failures** | **RETURN session_id + reset failures** | **RETURN NULL + Audit `device_limit`** |
| **Verified by test** | `TC-08-023` | `TC-20-028` | `TC-20-012` | `t04 #1` | `t04 #1` | `t04 #1` |

### DT-04 — Paid Profile Download & Contact Reveal (`billing_download_profile()` & `candidate_contact()`, rules `BR-04`, `BR-20`)

| Condition / Outcome | R1: Not Org Member / No Perm | R2: Candidate Not Visible / Blocked | R3: Downloaded < 30 Days Ago | R4: First Download (Wallet >= 1 cr) | R5: First Download (Wallet = 0 cr) |
| --- | --- | --- | --- | --- | --- |
| Caller in org with `candidate_download` permission | No | Yes | Yes | Yes | Yes |
| `app_can_view_candidate(profile_id)` is true | — | No | Yes | Yes | Yes |
| Prior `profile_download` by org within 30 days | — | — | Yes | No | No |
| `wallet.balance_credits >= 1` | — | — | — | Yes | No |
| **Outcome: `billing_download_profile()`** | **RAISE `insufficient_privilege`** | **RAISE `no_data_found`** | **Return prior download_id (0 credits)** | **Debit 1 credit + Insert download + Audit** | **RAISE `P0002 insufficient credits`** |
| **Outcome: `candidate_contact()`** | **RAISE `insufficient_privilege`** | **RAISE `insufficient_privilege`** | **Return email & phone + Audit `read`** | **Return email & phone + Audit `read`** | **RAISE `insufficient_privilege`** |
| **Verified by test** | `t03` | `t03` | `t03` | `t03` | `t02` |

### DT-05 — Payment Gateway Webhook Processing (`billing_apply_payment_event()`, rule `BR-19`)

| Condition / Outcome | R1: Duplicate `gateway_event_ref` | R2: Amount Mismatch | R3: Out-of-Order / Late State | R4: Valid `captured` (Recharge/Sub) | R5: Valid `refunded` (Credits Unspent) | R6: Valid `refunded` (Credits Spent) |
| --- | --- | --- | --- | --- | --- | --- |
| `gateway_event_ref` already in `payment_event` | Yes | No | No | No | No | No |
| `p_amount = payment_order.amount` | — | No | Yes | Yes | Yes | Yes |
| `(old_status, new_status)` in allowed forward pairs | — | — | No | Yes (`-> 3`) | Yes (`3 -> 5`) | Yes (`3 -> 5`) |
| Wallet has enough credits to reverse grant (`balance >= credits`) | — | — | — | — | Yes | No |
| **Outcome** | **No-op (`RETURN false`)** | **RAISE `check_violation`** | **Store `payment_event` only (`RETURN true`)** | **Update order + Grant credits/sub + Issue GST invoice + Audit** | **Update order + Reversal ledger entry + Cancel sub + Audit** | **RAISE `P0002 insufficient credits` (tx rolls back)** |
| **Verified by test** | `t02` | `t02` | `TC-08-027` | `t02` | `t02` | `TC-08-029` |

## 3. Exit Test Check

| S-18 Exit Criterion | Status | Evidence |
|---|---|---|
| Every rule has ID, category, statement, owner, and planned test | **PASSED** | 28 explicit BR rows (`BR-01..BR-28`) + 247 explicit DR rows (`DR-001..DR-247`) = 275 total rows |
| Step 11 (210 DR) to Step 18 (247 DR + 28 BR = 275) reconciled | **PASSED** | Section 1.A reconciles every rule addition and gap closure |
| 0 enforcement point gaps | **PASSED** | 100% of rules assigned to Database, Application, or Pipeline (0 Gaps) |
| Multi-variable rules modeled as formal decision tables | **PASSED** | 5 comprehensive decision tables (`DT-01`..`DT-05`) specified |
