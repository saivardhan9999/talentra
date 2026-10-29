# 17 — Design-Based Refinement

> Reconciled directly against live PostgreSQL 18 (`db/migrations/V001..V013`), deterministic seed (`db/seed/seed_prove_sample.sql`), and SQL test suites (`db/tests/t01..t06.sql`) with zero catalog drift.

Conforms strictly to Phase 3 schema [S-17](schemas.md#s-17--design-based-refinement).

## 1. Refinement Change Log (`V013__phase3_refinements.sql`)

Phase 2 review surfaced 14 findings (`FND-01`..`FND-14`). All 14 are formally closed in forward-only migration `V013__phase3_refinements.sql` and verified by `db/tests/t06_phase3_prove.sql`:

| Finding ID | Severity | Objects Changed | Before State (V001..V012) | After State (V013) | Verification Test |
|---|---|---|---|---|---|
| `FND-01` | `high` | `job_requirement, job_status_transition` | `job_status_id` and `published_at` were both updatable by `v2_app`; clearing `published_at` allowed a published job to return to `draft` (violating FR-JOB-02). | Added `job_status_transition` table (7 allowed moves) and `trg_job_requirement_guard` (`job_requirement_guard()`); `published_at` is now strictly write-once. | `TC-20-001, TC-20-002` |
| `FND-02` | `medium` | `job_requirement, job_status_transition` | `closed` (4) and `filled` (5) jobs could be reopened by updating `job_status_id = 2`, and `filled` could be set manually while positions remained unfilled. | `job_status_transition` has no outgoing edges from `closed` or `filled`; `job_requirement_guard()` rejects `filled` unless `positions_filled = positions_total`. | `TC-20-003, TC-20-004, TC-20-005, TC-20-006` |
| `FND-03` | `high` | `organisation, organisation_tax_identifier` | No database entry point allowed Talentra staff to verify or reject an organisation (`FR-ORG-06`); only the schema owner could update `verification_status_id`. | Added `SECURITY DEFINER` function `organisation_set_verification(org_id, status_code, note)` restricted to staff (`organisation_verify`), enforcing `pending -> verified/rejected` and `rejected -> pending`, updating `verified_at` and tax IDs, and writing an `audit_event`. | `TC-20-007, TC-20-008, TC-20-009, TC-20-010` |
| `FND-04` | `medium` | `user_device, user_session` | `user_device.revoked_at` existed in DDL, but `v2_app` had no UPDATE grant or entry point to revoke a device (`FR-IAM-06`), and `revoked_at` was not write-once. | Added `auth_revoke_device(device_id)` (owner or staff), which sets `revoked_at`, ends all active sessions on the device, and logs `user_device.revoked`; added `trg_user_device_guard` so `revoked_at` is write-once. | `TC-20-011, TC-20-012, TC-20-013` |
| `FND-05` | `medium` | `app_user, user_session` | `app_user.account_status_id` had no transition guard or entry point for suspend/reactivate/deactivate (`FR-IAM-04/06`). | Added `trg_app_user_status_guard` (`erased` is final) and `user_set_account_status(user_id, status_code)` (staff for `suspended`, owner/staff for `deactivated`/`active`, ending active sessions and auditing). | `TC-20-014, TC-20-015, TC-20-016` |
| `FND-06` | `low` | `subscription` | `subscription_guard()` blocked extending `ends_on` or altering limits, but allowed `cancelled_at` to be reset from a timestamp back to `NULL`. | Updated `subscription_guard()` so `cancelled_at` is write-once (`OLD.cancelled_at IS NOT NULL AND NEW.cancelled_at IS DISTINCT FROM OLD.cancelled_at` raises `check_violation`). | `TC-20-017` |
| `FND-07` | `low` | `organisation_member, candidate_block` | Closing timestamps `organisation_member.valid_to` and `candidate_block.unblocked_at` could be cleared back to `NULL`, mutating history instead of inserting a new period row. | Added `period_close_once_guard()` trigger on both tables making `valid_to` and `unblocked_at` write-once. | `TC-20-018, TC-20-019` |
| `FND-08` | `low` | `notification` | `notification_record_result()` accepted any status code without checking current status, allowing `delivered (3) -> sent (2)` or `queued (1)`. | Updated `notification_record_result()` to validate `(OLD.status, NEW.status)` against `((1,2),(1,3),(1,4),(2,3),(2,4))`, making `delivered`, `failed`, and `suppressed` final. | `TC-20-020, TC-20-021` |
| `FND-09` | `high` | `consent_record, notification, candidate_profile` | Consent purposes `profile_visible_to_recruiters` (3), `marketing_email` (4), and `whatsapp_alerts` (5) were stored in `consent_record`, but neither `notification_apply_preference()` nor `candidate_profile` RLS checked them. | Updated `notification_apply_preference()` to suppress category 5 (`marketing`) without purpose 4 consent and channel 3 (`whatsapp`) without purpose 5 consent; added `app_users_without_recruiter_consent()` initPlan helper to `app_candidate_visible()` and `candidate_profile_read` policy. | `TC-20-022, TC-20-023` |
| `FND-10` | `medium` | `application_answer` | `candidate_erase()` kept `application_answer.answer_text` in clear text on retained applications, leaking personal free-text answers after DPDP erasure. | Updated `candidate_erase()` to scrub `answer_text = '[erased]'` across all answers of the erased candidate. | `TC-20-024` |
| `FND-11` | `low` | `user_device` | `candidate_erase()` left `user_device.device_label` (e.g. `"Priya's iPhone"`) intact. | Updated `candidate_erase()` to set `device_label = NULL` and `revoked_at = coalesce(revoked_at, now())` for all devices of the erased user. | `TC-20-024` |
| `FND-12` | `medium` | `13 personal tables (52 columns)` | 52 columns on personal tables lacked explicit `Personal.` or `Sensitive.` SQL comments and defaulted to `Internal` in Dictionary v1. | Added 52 `COMMENT ON COLUMN` statements in `V013__phase3_refinements.sql` so 100% of the 78 Personal/Sensitive columns are tagged directly in the PostgreSQL catalog. | `TC-20-025` |
| `FND-13` | `medium` | `organisation, wallet` | "Every organisation has exactly one wallet" only held when created via `auth_register_employer()`; a direct `INSERT INTO organisation` left the org without a wallet. | Added `AFTER INSERT ON organisation` trigger `trg_organisation_ensure_wallet` (`organisation_ensure_wallet()`) with `ON CONFLICT (organisation_id) DO NOTHING`. | `TC-20-026` |
| `FND-14` | `medium` | `user_credential` | Brute-force lockout columns `failed_attempt_count` and `locked_until` existed on `user_credential`, but no database function maintained or checked them. | Added `auth_record_login_failure()` to increment failures, set `locked_until` at threshold, and audit `user_credential.locked`; updated `auth_open_session()` to refuse locked accounts (`user_session.refused.account_locked`) and reset counters on success. | `TC-20-027, TC-20-028` |

## 2. Design Trade-Off Comparisons (Hardest Areas)

### Area 1: Recruiter Candidate Search Visibility + Consent Enforcement under RLS (AP-04 / AP-05, FND-09)

- **Option A:** Design A — Per-row helper function call in RLS policy (`USING (app_candidate_visible(id, app_user_id, profile_visibility_id, deleted_at))` with correlated `EXISTS (SELECT 1 FROM consent_current ...)`). Simple 1-line policy, zero duplication between point checks and table scans.
- **Option B:** Design B — Inline RLS predicate with scalar `(SELECT ...)` initPlan array helpers (`NOT id = ANY ((SELECT app_candidates_blocking_viewer())::bigint[]) AND NOT app_user_id = ANY ((SELECT app_users_without_recruiter_consent())::bigint[])`) plus parity test in `t03_security.sql`.
- **Decision & Rationale:** Chosen: **Design B**. PostgreSQL cannot inline a `SECURITY DEFINER` function containing subqueries into the outer plan. At 10k profiles, Design A executes viewer role/block/consent lookups 10,000 times per search (measured **3,700 ms**). Design B evaluates the `(SELECT fn())` initPlans **once per query** and probes the index/arrays (measured **3.4 ms** at 10k profiles — a **1,088× speedup**). Parity test `t03` guarantees `app_candidate_visible()` and `candidate_profile_read` never drift.

### Area 2: High-Concurrency Quota Enforcement — Wallet Balance, Licence Seats, Device Limits & Job Positions (FR-BIL-03, FR-ORG-05, FR-IAM-05, FR-JOB-08)

- **Option A:** Design A — `SERIALIZABLE` transaction isolation level or `AFTER INSERT` deferred constraint triggers (`SUM(credits) >= 0`, `COUNT(*) <= max_seats`) without parent row locks.
- **Option B:** Design B — `READ COMMITTED` with explicit parent-entity `SELECT ... FOR UPDATE` row locks (`wallet` row for credits, `organisation` row for seats, `app_user` row for devices, `job_requirement` row for positions) inside single-writer functions/triggers + cached counters (`balance_credits`, `positions_filled`) verified by `CHECK` constraints.
- **Decision & Rationale:** Chosen: **Design B**. Under `READ COMMITTED`, two concurrent transactions do not see each other's uncommitted inserts, so a trigger counting rows without a parent lock allows both to pass (write skew). `SERIALIZABLE` fixes this by aborting racing transactions with `40001 serialization_failure`, forcing application retry loops on every hot wallet or job. Design B serialises only the contenders for the *same* wallet/org/user/job in a deterministic queue (`t04_concurrency.sql` proves 8 parallel debits on 3 credits → 3 succeed, 5 cleanly refused with `insufficient credits`, 0 serialization aborts).

### Area 3: State Machine Enforcement for Applications & Job Requirements (Step 08, FND-01, FND-02)

- **Option A:** Design A — Hardcoded `CASE / IF` transition branches inside PL/pgSQL triggers or API service code.
- **Option B:** Design B — Data-driven configuration tables (`application_status_transition`, `job_status_transition`) with foreign keys to lookup tables, enforced by a generic `EXISTS` check inside the table guard trigger.
- **Decision & Rationale:** Chosen: **Design B**. Storing allowed moves as rows makes the state machine inspectable by SQL (`t05` R-05 verifies every history row against `application_status_transition` in one join), self-documenting in the ER model, and extensible by a data migration without rewriting trigger control flow.

## 3. Regression Verification

Following the application of `V013__phase3_refinements.sql`, the entire test suite was executed sequentially to confirm zero regressions:

| Test Suite | Focus Area | Assertions / Tests | Regressions Detected | Final Status |
|---|---|---|---|---|
| `t01_standards.sql` | Catalog conventions, keys, domains, RLS, audit triggers | 15 catalog assertions | 0 | **PASSED** |
| `t02_integrity.sql` | Referential integrity, constraints, triggers, domain checks | 42 integrity checks | 0 | **PASSED** |
| `t03_security.sql` | RLS isolation across 9 actor roles, consent, blocking | 36 security checks | 0 | **PASSED** |
| `t04_concurrency.sql` | Parallel `dblink` race tests (wallets, seats, devices, jobs) | 4 parallel race tests | 0 | **PASSED** |
| `t05_data_quality.sql` | Whole-database invariants R-01..16 + anomalies F-01..06 | 16 invariants + 6 findings | 0 | **PASSED** |
| `t06_phase3_prove.sql` | Negative invalid rows BAD-01..16 + refinements FND-01..14 | 44 prove tests | 0 | **PASSED** |

## 4. Exit Test Check

| S-17 Exit Criterion | Status | Evidence |
|---|---|---|
| 100% of high, medium, and low findings closed | **PASSED** | 14 of 14 findings (`FND-01`..`FND-14`) verified closed in `t06` |
| Hardest areas evaluated with side-by-side architectural trade-offs | **PASSED** | 3 deep trade-offs documented with benchmarked decisions |
| Full test suite re-run with 0 regressions | **PASSED** | Suites `t01` through `t06` pass with 100% clean exit codes |
