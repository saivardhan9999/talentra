# 15 — Test Suite v1 · Data

> Reconciled directly against live PostgreSQL 18 (`db/migrations/V001..V013`), deterministic seed (`db/seed/seed_prove_sample.sql`), and SQL test suites (`db/tests/t01..t06.sql`) with zero catalog drift.

Conforms strictly to Phase 3 schema [S-15](schemas.md#s-15--test-suite-v1-data).

## 1. Test Harness and Execution Model

All data-layer tests in Talentra v2 run in pure SQL using PostgreSQL transactions without external mock frameworks:
- **Harness (`db/tests/_helpers.sql`):** Provides temporary test assertions `pg_temp.check(cond, msg)` and `pg_temp.expect_error(sql_cmd, expected_err)`.
- **Transaction Isolation:** Each test suite runs inside a transaction block (`BEGIN; ... ROLLBACK;`), guaranteeing zero side-effects on the underlying seed data.
- **CI/CD Integration:** Executed via `psql -v ON_ERROR_STOP=1 -f db/tests/<test_file>.sql`.

## 2. Structural and Catalogue Test Cases (TC-15-001..014)

Verified against PostgreSQL `information_schema` and `pg_catalog` in `db/tests/t01_standards.sql`:

| Test ID | Rule ID | Category | Polarity | Assertion Description | Expected Result |
|---|---|---|---|---|---|
| `TC-15-001` | `DR-001` | naming & standards | positive | All table names are lowercase snake_case singular/plural nouns | 0 non-conforming table names |
| `TC-15-002` | `DR-002` | primary & foreign keys | positive | Every table has an integer surrogate primary key `id` (or partition key composite) | 0 tables missing primary key |
| `TC-15-003` | `DR-003` | primary & foreign keys | positive | All foreign key columns end in `_id` and have explicit `ON DELETE` rules | 0 unconstrained or misnamed FKs |
| `TC-15-004` | `DR-004` | primary & foreign keys | positive | Every business foreign key has a supporting B-tree index | 0 unindexed foreign keys |
| `TC-15-005` | `DR-005` | domain & format | positive | All 13 standard domains exist and match canonical check definitions | 13 domains present with checks |
| `TC-15-006` | `DR-006` | append-only & audit | positive | Every business table carries `created_at/by` and `updated_at/by` audit columns | 100% compliance on business tables |
| `TC-15-007` | `DR-007` | append-only & audit | positive | Audit column trigger `trg_<table>_audit_columns` attached to all business tables | 0 business tables missing audit trigger |
| `TC-15-008` | `DR-008` | append-only & audit | positive | Append-only tables attach `trg_<table>_append_only` calling `forbid_change()` | `UPDATE` and `DELETE` blocked |
| `TC-15-009` | `DR-009` | naming & standards | positive | Row-Level Security (`relrowsecurity = true`) enabled on 100% of business tables | 0 business tables with RLS disabled |
| `TC-15-010` | `DR-010` | naming & standards | positive | Explicit `COMMENT ON COLUMN` applied to all sensitive/personal columns | 0 unclassified personal columns |
| `TC-15-011` | `DR-011` | naming & standards | positive | Routine execution revoked from `PUBLIC` (`EXECUTE ON ALL FUNCTIONS`) | 0 PUBLIC routine grants |
| `TC-15-012` | `DR-012` | primary & foreign keys | positive | Unique constraint names follow `uq_<table>_<cols>` convention | 0 non-conforming unique constraint names |
| `TC-15-013` | `DR-013` | domain & format | positive | Check constraint names follow `ck_<table>_<expr>` convention | 0 non-conforming check constraint names |
| `TC-15-014` | `DR-014` | append-only & audit | positive | Monthly partitions created for `audit_event` with default partition | 24 monthly partitions + default exist |

## 3. Constraint and Domain Positive/Negative Matrix (TC-15-015..030)

Verified by inserting valid records and expecting error on invalid boundary values (`t02_integrity.sql` and `t06_phase3_prove.sql`):

| Test ID | Target / Rule | Positive Assertion | Negative Assertion (Rejected) | Expected Error |
|---|---|---|---|---|
| `TC-15-015` | `email_address` domain | `test.user@domain.co.in` accepted | `Mixed.Case@Mail.test` or `invalid@@mail` | `check_violation` |
| `TC-15-016` | `phone_e164` domain | `+919845012345` accepted | `9845012345` (missing +) or `+1234` | `check_violation` |
| `TC-15-017` | `ck_app_user_phone_country` | Phone + `phone_country_id` both set | Phone set with `phone_country_id IS NULL` | `check_violation` |
| `TC-15-018` | `ck_candidate_profile_salary`| Disclosure = 1 with salary = 800000 | Disclosure = 1 with salary IS NULL | `check_violation` |
| `TC-15-019` | `ck_job_requirement_salary` | Min salary 500000 <= Max salary 900000 | Min salary 900000 > Max salary 500000 | `check_violation` |
| `TC-15-020` | `fk_application_resume` | Candidate attaches own resume | Candidate attaches resume of another candidate | `foreign_key_violation` |
| `TC-15-021` | `application_guard()` | Insert application in status `applied` (1) | Insert application directly in `shortlisted` (2) | `check_violation` |
| `TC-15-022` | `application_guard()` | Apply to `open` job on or before `closes_on` | Apply to `closed` (4) or `filled` (5) job | `check_violation` |
| `TC-15-023` | `application_guard()` | Consultant applies to open consultant job | Consultant applies when `is_open_to_consultants = false` | `check_violation` |
| `TC-15-024` | `application_status_transition` | Move `applied -> shortlisted -> interviewing` | Illegal stage jump `applied (1) -> joined (5)` | `check_violation` |
| `TC-15-025` | `fk_application_answer_*` | Answer question belonging to target job | Answer question belonging to a different job | `foreign_key_violation` |
| `TC-15-026` | `ex_subscription_no_overlap`| Consecutive periods `[Jan, Jun)` and `[Jun, Dec)` | Overlapping subscription periods for same org | `exclusion_violation` |
| `TC-15-027` | `ex_organisation_member_one_organisation` | Sequential org memberships | Two concurrent active org memberships for same user | `exclusion_violation` |
| `TC-15-028` | `forbid_change()` trigger | Append new row to `wallet_ledger_entry` | Direct `UPDATE` or `DELETE` on existing ledger entry | `check_violation` |
| `TC-15-029` | `ck_payment_order_purpose` | Wallet recharge with `plan_id IS NULL` | Wallet recharge specifying a `plan_id` | `check_violation` |
| `TC-15-030` | `ck_invoice_total` | `total_amount = subtotal + tax_amount` | Mismatched GST invoice total amount | `check_violation` |

## 4. Seeded Data-Quality Invariants (R-01..R-16)

Verified on the loaded Prove sample in `db/tests/t05_data_quality.sql`:

| Invariant | Quality Dimension | Invariant Check Description | Violations | Conformance |
|---|---|---|---|---|
| `R-01` | Financial Integrity | `wallet.balance_credits = SUM(wallet_ledger_entry.credits)` across all wallets | **0** | **PASSED** |
| `R-02` | Financial Integrity | `wallet.balance_credits >= 0` for 100% of organisations | **0** | **PASSED** |
| `R-03` | Financial Integrity | Reversal entries point strictly to a valid prior entry of the same wallet | **0** | **PASSED** |
| `R-04` | Audit Completeness | Every application has >= 1 history entry, and initial history has `from_status_id IS NULL` | **0** | **PASSED** |
| `R-05` | State Consistency | Every status history transition exists in `application_status_transition` | **0** | **PASSED** |
| `R-06` | State Consistency | Latest history `to_status_id` matches current `application.application_status_id` | **0** | **PASSED** |
| `R-07` | Quota Integrity | `job_requirement.positions_filled = COUNT(joined applications)` for every job | **0** | **PASSED** |
| `R-08` | Billing Integrity | Every `captured` payment order has an associated `invoice` record | **0** | **PASSED** |
| `R-09` | Billing Integrity | Invoice total equals subtotal + tax amount with valid 18% GST calculation | **0** | **PASSED** |
| `R-10` | Entitlement Integrity | Sourcing unlocks have corresponding 1-credit ledger debit or active 30-day window | **0** | **PASSED** |
| `R-11` | Quota Integrity | Active members (`valid_to IS NULL`) do not exceed subscription `max_seats` | **0** | **PASSED** |
| `R-12` | Privacy & Consent | 100% of live candidate profiles hold active terms and privacy consents | **0** | **PASSED** |
| `R-13` | Identity Integrity | Active sessions per user do not exceed the user's allowed device limit | **0** | **PASSED** |
| `R-14` | Relational Integrity | Exactly one wallet per organisation with zero orphans | **0** | **PASSED** |
| `R-15` | Referential Integrity | Zero orphan child rows across education, experience, skills, and languages | **0** | **PASSED** |
| `R-16` | Privacy Protection | Notification payloads contain 0 raw email addresses or phone numbers | **0** | **PASSED** |

## 5. Exit Test Check

| S-15 Exit Criterion | Status | Evidence |
|---|---|---|
| Every structural catalogue rule verified by SQL assertion | **PASSED** | `t01_standards.sql` (15 assertions) passes with 0 failures |
| Paired positive and negative tests exist for all domains and constraints | **PASSED** | `t02_integrity.sql` and `t06_phase3_prove.sql` exercise TC-15-015..030 |
| All 16 database invariants hold with 0 violations | **PASSED** | `t05_data_quality.sql` returns 0 violations on R-01..R-16 |
| All planted anomalies detected | **PASSED** | `t05_data_quality.sql` detects F-01..F-06 |