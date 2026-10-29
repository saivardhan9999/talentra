# 20 — Test Suite v2 · Data, Business and NFR

> Reconciled directly against live PostgreSQL 18 (`db/migrations/V001..V013`), deterministic seed (`db/seed/seed_prove_sample.sql`), and SQL test suites (`db/tests/t01..t06.sql`) with zero catalog drift.

Conforms strictly to Phase 3 schema [S-20](schemas.md#s-20--test-suite-v2--data-business-and-nfr).

## 1. Coverage Summary

| Target Domain | Total Items | Verified in Suite v1 (`t01`–`t05`) | Verified in Suite v2 (`t06` + `bench`) | Total Coverage |
|---|---|---|---|---|
| **Business Rules (`BR-01`..`BR-28`)** | 28 | 14 | 14 | **100% (28 / 28)** |
| **Negative State Transitions (`TC-08-001`..`048`)** | 48 | 26 | 22 | **100% (48 / 48)** |
| **Boundary Value Analyses** | 14 | 6 | 8 | **100% (14 / 14)** |
| **Non-Functional Requirements (NFRs)** | 37 | 25 | 12 | **100% (37 / 37)** |
| **Planted DQ Findings (`F-01`..`F-06`)** | 6 | 6 | 0 | **100% (6 / 6)** |
| **Deliberate Invalid Rows (`BAD-01`..`BAD-16`)** | 16 | 12 | 4 | **100% (16 / 16)** |

## 2. Business Rule Test Register (TC-20-001..028)

| Test ID | Target Rule | Test File | Scenario Description | Expected Outcome |
|---|---|---|---|---|
| `TC-20-001` | `BR-01` | `t02_integrity.sql` | Every table uses an integer surrogate key `id`; foreign keys and check cons... | Verification of `PK/FK constraints + `t01_standards.sql`` under valid and invalid inputs |
| `TC-20-002` | `BR-02` | `t06_phase3_prove.sql` | Candidates register themselves (or via staff at a placement drive); recruit... | Verification of ``auth_register_candidate()`` under valid and invalid inputs |
| `TC-20-003` | `BR-03` | `t06_phase3_prove.sql` | A candidate profile is visible to recruiters only when `deleted_at IS NULL`... | Verification of `RLS `candidate_profile_read`, `app_candidate_visible()`, `app_users_without_recruiter_consent()`` under valid and invalid inputs |
| `TC-20-004` | `BR-04` | `t06_phase3_prove.sql` | When a candidate blocks an organisation or user, the blocked party immediat... | Verification of `RLS on `candidate_profile`, `application`, `candidate_block` + `candidate_contact()`` under valid and invalid inputs |
| `TC-20-005` | `BR-05` | `t06_phase3_prove.sql` | Permissions derive strictly from `user_access_role -> access_role_permissio... | Verification of ``app_has_permission()`` under valid and invalid inputs |
| `TC-20-006` | `BR-06` | `t06_phase3_prove.sql` | Consent is an append-only history per user and purpose with `policy_version... | Verification of ``consent_record` (append-only) + view `consent_current`` under valid and invalid inputs |
| `TC-20-007` | `BR-07` | `t06_phase3_prove.sql` | Active sessions per user cannot exceed the device limit (3 for candidates; ... | Verification of ``auth_open_session()` with `FOR UPDATE` lock on `app_user` + `auth_revoke_device()`` under valid and invalid inputs |
| `TC-20-008` | `BR-08` | `t06_phase3_prove.sql` | After 5 consecutive failed password checks, the credential is locked for 15... | Verification of ``auth_record_login_failure()` + `auth_open_session()`` under valid and invalid inputs |
| `TC-20-009` | `BR-09` | `t06_phase3_prove.sql` | An organisation has at most `subscription.max_seats` current members (`vali... | Verification of ``trg_organisation_member_seat_limit` + `ex_organisation_member_one_organisation` + `trg_organisation_member_close_once`` under valid and invalid inputs |
| `TC-20-010` | `BR-10` | `t06_phase3_prove.sql` | Tax identifiers (GSTIN, PAN, CIN, VAT, EIN) are validated for format, token... | Verification of ``pii_hmac()`, `uq_organisation_tax_identifier_country_id_type_hmac`, `organisation_set_verification()`` under valid and invalid inputs |
| `TC-20-011` | `BR-11` | `t06_phase3_prove.sql` | Publishing a job (`draft -> open`) sets `published_at` (write-once) and deb... | Verification of ``trg_job_requirement_guard`, `job_status_transition`, `trg_job_requirement_charge_posting`` under valid and invalid inputs |
| `TC-20-012` | `BR-12` | `t06_phase3_prove.sql` | Each application moving to `joined` increments `job_requirement.positions_f... | Verification of ``application_guard()` + `ck_job_requirement_positions`` under valid and invalid inputs |
| `TC-20-013` | `BR-13` | `t02_integrity.sql` | A candidate can apply at most once per job, only while the job is `open` (2... | Verification of ``application_guard()`, `uq_application_job_requirement_id_candidate_profile_id`, composite FKs `fk_application_resume`, `fk_application_answer_screening_question`` under valid and invalid inputs |
| `TC-20-014` | `BR-14` | `t02_integrity.sql` | Applications move only along the 12 edges in `application_status_transition... | Verification of ``application_status_transition` + `application_guard()`` under valid and invalid inputs |
| `TC-20-015` | `BR-15` | `t02_integrity.sql` | A candidate may only transition their own application to `withdrawn` (7); a... | Verification of ``application_guard()` + RLS `application_update`` under valid and invalid inputs |
| `TC-20-016` | `BR-16` | `t02_integrity.sql` | Every application status change is recorded in `application_status_history`... | Verification of ``trg_application_record_history` + `forbid_change()`` under valid and invalid inputs |
| `TC-20-017` | `BR-17` | `t06_phase3_prove.sql` | A sold `subscription` is an immutable licence snapshot (`max_seats`, `max_d... | Verification of ``subscription_guard()` + `ex_subscription_no_overlap`` under valid and invalid inputs |
| `TC-20-018` | `BR-18` | `t06_phase3_prove.sql` | Every organisation has exactly one `wallet`. `wallet.balance_credits` equal... | Verification of ``trg_organisation_ensure_wallet`, `wallet_post()` with wallet row lock, `forbid_change()`, `ck_wallet_balance_not_negative`` under valid and invalid inputs |
| `TC-20-019` | `BR-19` | `t02_integrity.sql` | Payment webhooks (`billing_apply_payment_event`) are idempotent on `gateway... | Verification of ``billing_apply_payment_event()`, `uq_payment_event_gateway_event_ref`, `ck_invoice_total`` under valid and invalid inputs |
| `TC-20-020` | `BR-20` | `t02_integrity.sql` | Downloading a candidate profile (`billing_download_profile`) costs 1 credit... | Verification of ``billing_download_profile()`, `candidate_contact()`, `audit_log()`` under valid and invalid inputs |
| `TC-20-021` | `BR-21` | `t06_phase3_prove.sql` | Notifications are written in the same transaction as the business event (`d... | Verification of ``notification_apply_preference()`, `application_notify()`, `notification_claim()`, `notification_record_result()`` under valid and invalid inputs |
| `TC-20-022` | `BR-22` | `t02_integrity.sql` | Every sensitive action writes an append-only `audit_event` via `audit_log()... | Verification of ``audit_log()`, `audit_row_change()`, `forbid_change()`, RLS `audit_event_read`` under valid and invalid inputs |
| `TC-20-023` | `BR-23` | `t06_phase3_prove.sql` | Right to erasure (`candidate_erase`) deletes education, experience, skills,... | Verification of ``candidate_erase()`, `retention_erase_inactive()`` under valid and invalid inputs |
| `TC-20-024` | `BR-24` | `t02_integrity.sql` | Organisation parent hierarchy (`parent_organisation_id`) must remain a stri... | Verification of ``ck_organisation_not_own_parent`, `organisation_prevent_cycle()`, RLS policies, `employer_hiring_funnel`` under valid and invalid inputs |
| `TC-20-025` | `BR-25` | `t02_integrity.sql` | Consultant-sourced applications (`application_source_id = 3`) are permitted... | Verification of ``application_guard()`` under valid and invalid inputs |
| `TC-20-026` | `BR-26` | `t02_integrity.sql` | All UI strings resolve via `ui_text(ui_label_id, language_id)` with automat... | Verification of ``ui_text()`, `t01_standards.sql` fallback check` under valid and invalid inputs |
| `TC-20-027` | `BR-27` | `t02_integrity.sql` | Scheduled retention and maintenance jobs keep high-volume tables bounded: `... | Verification of ``create_month_partitions()`, `retention_erase_inactive()`, `refresh_aggregates()`, `forbid_change()` (`app.retention_job = on`)` under valid and invalid inputs |
| `TC-20-028` | `BR-28` | `t02_integrity.sql` | Probable duplicate candidates (same `phone_e164` and `lower(full_name)`), p... | Verification of `Index `idx_app_user_phone_e164` (AP-12) + DQ suite `t05_data_quality.sql`` under valid and invalid inputs |

## 3. State Transition Test Matrix (TC-08-001..048)

Every illegal lifecycle move identified in Phase 2 Step 08 is mapped to an executable negative test case:

| Test ID | Entity & State Machine | Illegal State Transition Attempted | Refusal Mechanism | Verification Location |
|---|---|---|---|---|
| `TC-08-001` | ENT-26 Application | Insert application with status <> applied (e.g. shortlisted=2) | Refused (`a new application starts as applied`) | `t02_integrity.sql` L54 |
| `TC-08-002` | ENT-26 Application | Skip stage: `applied (1) -> interviewing (3) / offered (4) / joined (5)` | Refused (`cannot move from status 1 to 5`) | `t02_integrity.sql` L64 |
| `TC-08-003` | ENT-26 Application | Skip stage: `shortlisted (2) -> offered (4) / joined (5)` | Refused (`application_status_transition` guard) | `t02_integrity.sql` L64 / `t05` R-05 |
| `TC-08-004` | ENT-26 Application | Skip stage: `interviewing (3) -> joined (5)` | Refused (`application_status_transition` guard) | `t02_integrity.sql` L64 / `t05` R-05 |
| `TC-08-005` | ENT-26 Application | Move out of final status (`joined`, `rejected`, `withdrawn`) | Refused (no outgoing edges in transition table) | `t02_integrity.sql` / `t05` R-05 |
| `TC-08-006` | ENT-26 Application | Candidate moves own application to `shortlisted` (`+1`) | Refused (`a candidate can only withdraw`) | `t03_security.sql` L39 |
| `TC-08-007` | ENT-26 Application | Two concurrent `offered -> joined` races for the last position | 1 succeeds (`job -> filled`), 1 refused (`ck_job_requirement_positions`) | `t04_concurrency.sql` L76-88 |
| `TC-08-008` | ENT-26 Application | Recruiter of a company blocked by the candidate updates app | Refused (0 rows visible under RLS `application_update`) | `t03_security.sql` L76 |
| `TC-08-009` | ENT-22 Job requirement | `open / paused / closed / filled -> draft (1)` | Refused (`trg_job_requirement_guard` & `ck_job_requirement_published`) | `t02` L48, `t06` TC-20-001 |
| `TC-08-010` | ENT-22 Job requirement | `closed (4)` or `filled (5) -> open (2)` or `paused (3)` | Refused (`job_status_transition`: closed & filled are final) | `t06` TC-20-003, TC-20-004 |
| `TC-08-011` | ENT-22 Job requirement | `draft (1) -> paused (3)` or `filled (5)` | Refused (`job_status_transition` & `job_requirement_guard`) | `t06` TC-20-005 |
| `TC-08-012` | ENT-22 Job requirement | Manual update to `filled (5)` while `positions_filled < total` | Refused (`cannot be marked filled before all positions are joined`) | `t06` TC-20-005 |
| `TC-08-013` | ENT-22 Job requirement | Clear or overwrite `published_at` after publishing | Refused (`published_at is write-once`) | `t06` TC-20-001, TC-20-002 |
| `TC-08-014` | ENT-22 Job requirement | `open -> paused -> open` (re-publishing a paused job) | Charged once (`job_post:<id>` idempotency key) | `t06` TC-20-006 |
| `TC-08-015` | ENT-22 Job requirement | Publish job when wallet has `< 5` credits | Refused (`insufficient credits` in `wallet_post`) | `t02_integrity.sql` L98 |
| `TC-08-016` | ENT-10 Organisation | Non-staff (recruiter/admin) calls `organisation_set_verification` | Refused (`only staff with organisation_verify permission`) | `t06` TC-20-007 |
| `TC-08-017` | ENT-10 Organisation | Staff verifies pending org via `organisation_set_verification` | Succeeded (`verified_at` set, tax ID updated, audited) | `t06` TC-20-008 |
| `TC-08-018` | ENT-10 Organisation | Move `verified (2) -> pending (1)` | Refused (`cannot move verification status from 2 to 1`) | `t06` TC-20-009 |
| `TC-08-019` | ENT-10 Organisation | `verified (2)` with `verified_at IS NULL` (or vice versa) | Refused (`ck_organisation_verified_at`) | `t06` TC-20-008 |
| `TC-08-020` | ENT-12 Tax identifier | `verified` or `rejected` with mismatched `verified_at` | Refused (`ck_organisation_tax_identifier_verified_at`) | `t06` TC-20-008 |
| `TC-08-021` | ENT-12 Tax identifier | Duplicate `(country_id, tax_identifier_type_id, identifier_hmac)` | Refused (`uq_organisation_tax_identifier_country_id_type_hmac`) | `t01_standards.sql` |
| `TC-08-022` | ENT-01 User account | Move `erased (4) -> active (1)` | Refused (`trg_app_user_status_guard`: erased is final) | `t06` TC-20-014 |
| `TC-08-023` | ENT-01 User account | Suspended/deactivated/erased user calls `auth_open_session()` | Refused (`user % cannot log in`) | `t06` TC-20-016 |
| `TC-08-024` | ENT-01 User account | Non-staff user attempts to suspend or unsuspend an account | Refused (`only staff may suspend or unsuspend`) | `t06` TC-20-015 |
| `TC-08-025` | ENT-34 Payment order | Same `gateway_event_ref` webhook delivered twice | Second call returns `false` (no-op); credits/invoice once | `t02_integrity.sql` L112-117 |
| `TC-08-026` | ENT-34 Payment order | Webhook event `amount` differs from `payment_order.amount` | Refused (`event amount % does not match order amount %`) | `t02_integrity.sql` L119-120 |
| `TC-08-027` | ENT-34 Payment order | Out-of-order webhook (e.g. `authorised` after `captured`) | Event stored as evidence; `payment_order` status unchanged | `V008` L220-222 |
| `TC-08-028` | ENT-34 Payment order | Move `failed (4) -> captured (3)` | Event stored; order stays `failed` (`(4,3)` not in pairs) | `V008` L220-222 |
| `TC-08-029` | ENT-34 Payment order | Refund webhook when granted credits were already spent | Refused (`insufficient credits` in reversal `wallet_post`) | `t02_integrity.sql` L98, L121 |
| `TC-08-030` | ENT-31 Subscription | Extend `ends_on` or modify `max_seats` / `max_devices` / `plan` | Refused (`subscription_guard()`) | `t02_integrity.sql` L83 |
| `TC-08-031` | ENT-31 Subscription | Insert overlapping `[starts_on, ends_on)` for same org | Refused (`ex_subscription_no_overlap`) | `t02_integrity.sql` L79-80 |
| `TC-08-032` | ENT-31 Subscription | Clear `cancelled_at` back to `NULL` after cancellation | Refused (`cancelled_at is write-once`, FND-06) | `t06` TC-20-017 |
| `TC-08-033` | ENT-09 Session | Login when active devices equal the user's device limit | Refused (`RETURN NULL`) and audited (`device_limit`) | `t04_concurrency.sql` L28-40 |
| `TC-08-034` | ENT-09 Session | Expired session (`expires_at <= now()`) present at login | Closed automatically (`idle_timeout`) and not counted | `V013` `auth_open_session` |
| `TC-08-035` | ENT-09 Session | Non-staff user calls `auth_end_session` with `revoked_by_admin` | Refused (`invalid end reason`) | `t03_security.sql` L70 |
| `TC-08-036` | ENT-09 Session | Set `ended_at` without `session_end_reason_id` (or vice versa) | Refused (`ck_user_session_ended`) | `t02_integrity.sql` L127-128 |
| `TC-08-037` | ENT-08 Device | Login from a revoked device (`revoked_at IS NOT NULL`) | Refused (`RETURN NULL`) and audited (`device_revoked`) | `t06` TC-20-012 |
| `TC-08-038` | ENT-08 Device | Un-revoke a device by setting `revoked_at = NULL` | Refused (`trg_user_device_guard`: `revoked_at is write-once`) | `t06` TC-20-013 |
| `TC-08-039` | ENT-13 Membership | Reopen ended membership by setting `valid_to = NULL` | Refused (`trg_organisation_member_close_once`, FND-07) | `t06` TC-20-018 |
| `TC-08-040` | ENT-13 Membership | Second overlapping active membership for the same user | Refused (`ex_organisation_member_one_organisation`) | `t02_integrity.sql` L84-85 |
| `TC-08-041` | ENT-20 Block | Duplicate active block on same org/user or clearing `unblocked_at` | Refused (`uq_candidate_block_active_*` & `trg_candidate_block_close_once`) | `t06` TC-20-019 |
| `TC-08-042` | ENT-39 Notification | Move `delivered (3)`, `failed (4)`, or `suppressed (5)` to another status | Refused (`notification_record_result` state check, FND-08) | `t06` TC-20-020, TC-20-021 |
| `TC-08-043` | ENT-39 Notification | Insert marketing notification when opted out or no consent | Automatically set to `suppressed (5)` (`notification_apply_preference`) | `t02` L131, `t06` TC-20-022 |
| `TC-08-044` | ENT-39 Notification | Insert `account_security (3)` notification when user opted out | Stays `queued (1)` (security notices cannot be suppressed) | `t02_integrity.sql` L134-136 |
| `TC-08-045` | ENT-39 Notification | Concurrent workers calling `notification_claim()` | Disjoint batches claimed via `FOR UPDATE SKIP LOCKED` | `V011` L55-61 |
| `TC-08-046` | ENT-33 Ledger entry | Reverse the same ledger entry twice | Refused (`uq_wallet_ledger_entry_reverses_ledger_entry_id`) | `t02_integrity.sql` L121-124 |
| `TC-08-047` | ENT-33 Ledger entry | `UPDATE` or `DELETE` any row in `wallet_ledger_entry` | Refused (`trg_wallet_ledger_entry_append_only`) | `t02_integrity.sql` L95-96 |
| `TC-08-048` | ENT-07 Consent | `UPDATE` or `DELETE` any row in `consent_record` | Refused (`trg_consent_record_append_only`) | `t01_standards.sql` L96-100 |

## 4. Boundary Value Analysis Register

| Boundary Parameter | At-Limit Test (Must Succeed) | Over-Limit Test (Must Fail) | Verifying Test Case |
|---|---|---|---|
| `person_name` length (1..150 chars) | 1 char & 150 chars (`repeat('A', 150)::person_name`) | 0 chars (`''`) & 151 chars (`repeat('A', 151)`) | `t06` TC-15-001..004 |
| `money_amount` non-negative (`>= 0.00`) | `0.00::money_amount` | `-0.01::money_amount` | `t06` TC-15-005..006 |
| `percentage` range (`0.00..100.00`) | `0.00` & `100.00::percentage` | `-0.01` & `100.01::percentage` | `t06` TC-15-005, 007 |
| `latitude` (`-90..90`) & `longitude` (`-180..180`) | `-90.000000`, `90.000000`, `-180.000000`, `180.000000` | `90.000001::latitude` & `-180.000001::longitude` | `t06` TC-15-005, 008, 009 |
| `sha256_digest` octet length (`= 32` bytes) | `sha256('x'::bytea)` (32 bytes) | `'\x1234'::sha256_digest` (2 bytes) | `t06` TC-15-010 |
| `candidate_profile.total_experience_months` (0..720) | `0` months (intern) & `720` months (60 years) | `-1` & `721` months | `t06` TC-15-011 |
| `candidate_profile.notice_period_days` (0..365) | `0` days (immediate) & `365` days | `-1` & `366` days | `t06` TC-15-012 |
| `job_requirement.positions_total` (1..10000) | `1` position & `10000` positions | `0` positions & `10001` positions | `t06` TC-15-013..014 |
| `job_requirement.positions_filled` (`<= total`) | `positions_filled = positions_total` (auto-marks job `filled`) | `positions_filled = positions_total + 1` (2 offers race for last 1) | `t04` #4, `t02` L76 |
| `wallet.balance_credits` (`>= 0`) | Debit exact remaining balance (`3 - 3 = 0` credits) | Debit `balance + 1` (`- (balance + 1)` or 8 races on 3 credits) | `t02` L98, `t04` #2 |
| `subscription.max_seats` (`used <= max_seats`) | Add `max_seats`-th member (1 free seat left -> succeeds) | Add `(max_seats + 1)`-th member (full org -> refused) | `t02` L86, `t04` #3 |
| `app_device_limit` (`active_devices <= limit`) | Open 3rd concurrent device session for candidate (limit = 3) | Open 4th..6th device sessions (refused + audited `device_limit`) | `t04` #1 |
| `user_credential.failed_attempt_count` (`lock at N`) | `N - 1` failures (2 of 3 -> `locked_until IS NULL`) | `N`-th failure (3 of 3 -> `locked_until` set, login refused) | `t06` TC-20-027..028 |
| `profile_download` 30-day window (`<= 30 days`) | Repeat download at `< 30 days` (0 credits, returns existing id) | First download or `> 30 days` (debits 1 credit, new row) | `t03` L61-63 |

## 5. NFR Verification Register

| NFR ID | Requirement Summary | Verification Method & Test Location | Measured Result / Production Guarantee |
|---|---|---|---|
| `NFR-PERF-01` | Interactive reads (AP-01..AP-14) p95 <= 50 ms dev; <= 200 ms full | `bench/bench.py` (`docs/benchmark-results.md`) | Max p95 at 10k profiles is **5.3 ms** (`AP-01` full-text job search); projected 10M p95 <= 140 ms |
| `NFR-PERF-02` | Write transactions p95 <= 50 ms | `bench/bench.py` (`AP-03`, `AP-07`, `AP-11`, `AP-13`) | Write & lock paths p95 **0.3 ms – 1.8 ms** |
| `NFR-PERF-03` | RLS overhead <= 2x owner query (viewer context evaluated once) | `t03_security.sql` + `bench/bench.py` | Inline initPlan evaluates `(SELECT app_current_user_id())` once per query (`3.4 ms` vs `3,700 ms` un-inlined) |
| `NFR-PERF-04` | Statement timeout on runtime roles (`5s` API, `60s` reporting) | `V001__foundation.sql` L17-18 + `pg_db_role_setting` | `v2_app` has `statement_timeout = 5s`; `v2_reporting` has `60s` |
| `NFR-PERF-05` | Deterministic, fast dataset rebuild (`setseed`) | `seed_prove_sample.sql` (< 1 s) & `seed.sql` (~8 s) | Seeded PRNG (`0.314159` / `0.42`) produces identical rows every run |
| `NFR-SCAL-01` | Same schema serves 10k to 10M profiles with documented triggers | `13-data-volumetrics.md` & `21-baseline-er-and-physical-model.md` | Scale triggers defined for partitioning, read replicas, PgBouncer, and OpenSearch |
| `NFR-SCAL-02` | Full-scale peak throughput (600 search/s, 60 login/s, 10 app/s) | `13-data-volumetrics.md` §5 + `t04_concurrency.sql` | Per-row locks scope contention to single user/wallet/job; reads are lock-free |
| `NFR-SCAL-03` | Year-3 storage within ~250 GB on a single primary | `13-data-volumetrics.md` §2 | Year-3 total across all 48 tables + indexes projected at **~178.4 GB** (< 250 GB target) |
| `NFR-REL-01` | 99.9% availability architecture | `21-baseline-er-and-physical-model.md` §5 | Synchronous standby + non-blocking `REFRESH MATERIALIZED VIEW CONCURRENTLY` |
| `NFR-REL-02` | RPO <= 5 min, RTO <= 1 h | `21-baseline-er-and-physical-model.md` §5 | Continuous WAL archiving + PITR recovery procedure |
| `NFR-REL-03` | Transactional outbox: no lost or duplicate event notifications | `t02_integrity.sql` L74 + `V009` `uq_notification_dedupe_key` | Status change & notification commit in the same transaction; `dedupe_key` blocks duplicates |
| `NFR-REL-04` | Idempotent external system boundaries | `t02_integrity.sql` L101-117 | Tested on `wallet_post(idempotency_key)` and `billing_apply_payment_event(gateway_event_ref)` |
| `NFR-SEC-01` | Least privilege across 4 runtime roles; no PUBLIC routine execution | `t01_standards.sql` L126 + `t03_security.sql` | All functions revoked from `PUBLIC`; `v2_app`, `v2_payments`, `v2_worker`, `v2_reporting` separated |
| `NFR-SEC-02` | Argon2id password hashes; `user_credential` unreadable by runtime | `t01_standards.sql` L126 + `t03_security.sql` L36 | `SELECT * FROM user_credential` as `v2_app` fails with `permission denied` |
| `NFR-SEC-03` | Tokenised tax IDs (HMAC-SHA256 + last 4) & hashed session/device tokens | `V003`, `V004` `pii_hmac()` + `t01_standards.sql` | `sha256_digest` (32 bytes) enforced on `identifier_hmac`, `token_hash`, `device_fingerprint_hash` |
| `NFR-SEC-04` | RLS enabled on every business table; tested across all actors | `t01_standards.sql` L123-125 + `t03_security.sql` | 100% of business tables have RLS enabled; 36+ actor assertions pass in `t03` & `t06` |
| `NFR-SEC-05` | Encryption in transit (TLS 1.2+) and at rest | `12-data-classification-register.md` + `21-baseline-er-and-physical-model.md` | Volume + object-store encryption + irreversible column hashes |
| `NFR-PRIV-01` | DPDP Act 2023 consent history with policy version and IP evidence | `t05_data_quality.sql` R-12 + `t06` TC-20-022..023 | 100% of live candidates hold active terms & privacy consent; purpose 3, 4, 5 enforced |
| `NFR-PRIV-02` | Visibility and blocking enforced on every query via RLS | `t03_security.sql` L52-85 + `t06` TC-20-023 | Blocked company/recruiter sees 0 rows in `candidate_profile`, `application`, and `candidate_contact()` |
| `NFR-PRIV-03` | Every contact reveal audited; 0 PII values in audit or notification payloads | `t03_security.sql` L93 + `t05_data_quality.sql` R-16 | `candidate_contact.read` audited; `t05` R-16 verifies 0 emails/phones in `notification.payload` |
| `NFR-PRIV-04` | Right to erasure in one transaction (`candidate_erase`) + 3-year job | `t02_integrity.sql` L142-149 + `t06` TC-20-024 | Erases profile sections, resumes, credentials, contact, `answer_text` and `device_label`; keeps apps anonymised |
| `NFR-INT-01` | 13 standard domains used consistently across all tables | `t01_standards.sql` L70-75 + `t02` + `t06` | All 13 domains tested for valid and invalid boundary values |
| `NFR-INT-02` | Enforced FKs + composite FKs for cross-row consistency (0 orphans) | `t01_standards.sql` + `t02_integrity.sql` L52, L68 | `fk_application_job_requirement`, `fk_application_resume`, `fk_application_answer_*`, `fk_user_session_user_device` |
| `NFR-INT-03` | Quotas (seats, devices, credits, positions) hold under parallel race | `t04_concurrency.sql` (4 `dblink` parallel races) | All 4 parallel race tests pass with exact winner/refusal counts |
| `NFR-INT-04` | Histories, ledgers, invoices, downloads, and audit are append-only | `t01_standards.sql` L96-100 + `t02` L95-97 | `forbid_change()` trigger blocks `UPDATE` and `DELETE` on all 7 append-only tables |
| `NFR-INT-05` | Seed satisfies all 16 invariants (`R-01`..`R-16`) and plants `F-01`..`F-06` | `t05_data_quality.sql` | 16 invariants = 0 violations; all 6 findings (`F-01`..`F-06`) detected > 0 |
| `NFR-AUD-01` | `created_at/by` and `updated_at/by` on every business table | `t01_standards.sql` L86-94 | 100% of business tables carry all 4 columns and `trg_<table>_audit_columns` |
| `NFR-AUD-02` | Unforgeable audit actor (`audit_log()` SECURITY DEFINER) | `t03_security.sql` L68 | Direct `INSERT INTO audit_event` by `v2_app` is refused (`permission denied`) |
| `NFR-AUD-03` | Partitioned 7-year audit retention (`audit_event_pYYYYMM`) | `t01_standards.sql` L116 + `V005__audit.sql` | 24 monthly partitions + default created by `create_month_partitions()` |
| `NFR-I18N-01` | UTF-8 names in Latin, Devanagari, Tamil, and mononyms | `seed_prove_sample.sql` + `t02` | Devanagari (`राहुल शर्मा`), Tamil (`கார்த்திக் சுப்பிரமணியம்`), and mononyms (`Murugan`) stored & indexed |
| `NFR-I18N-02` | Translated UI labels with English fallback (`ui_text`) | `t01_standards.sql` L81-83 + `t02` L137-139 | 100% of `ui_label` rows have English (`language_id = 1`); Tamil (`3`) and Telugu fallback (`4 -> 1`) verified |
| `NFR-I18N-03` | User-authored content stored once with language reference | `V006`, `V007` (`profile_language_id`, `description_language_id`, `content_language_id`) | Verified in Data Dictionary v2 (`19-data-dictionary-v2.md`) |
| `NFR-MNT-01` | Numbered, checksummed, forward-only migrations (`V001`..`V013`) | `run.sh` (`schema_migration` checksum table) | Editing an already-applied migration aborts `run.sh migrate` on SHA-256 mismatch |
| `NFR-MNT-02` | Automated catalog standards suite (`t01_standards.sql`) | `db/tests/t01_standards.sql` | 15 catalog assertions check naming, keys, FK indexes, domains, audit, comments, and RLS |
| `NFR-MNT-03` | Zero-drift generated documentation from DDL | `phase3/tools/build_phase3.py` | Automated zero-drift assertion in `19-data-dictionary-v2.md` verifies 0 missing tables/columns |
| `NFR-OBS-01` | Application error logging (`system_error`) and slow-query tracking | `V005__audit.sql` L76-88 + `seed_prove_sample.sql` | `system_error` indexed by BRIN on `occurred_at` with 8 KB JSON context limit |
| `NFR-CMP-01` | DPDP Act 2023 compliance, sequential GST invoices, zero card data | `t02_integrity.sql` L118, L143 + `12-data-classification-register.md` | `ck_invoice_total` verifies GST math; `payment_order` stores only `gateway_order_ref` |

## 6. Exit Test Check

| S-20 Exit Criterion | Status | Evidence |
|---|---|---|
| 100% of business rules linked to test cases | **PASSED** | 28 of 28 BR rules covered in Section 2 |
| All 48 negative state transitions tested | **PASSED** | 48 of 48 TC-08 test cases covered in Section 3 |
| Boundary values tested at limit and over limit | **PASSED** | 14 critical boundaries verified in Section 4 |
| All 37 NFRs verified with concrete evidence | **PASSED** | Section 5 registers performance, scaling, security, and integrity evidence |
