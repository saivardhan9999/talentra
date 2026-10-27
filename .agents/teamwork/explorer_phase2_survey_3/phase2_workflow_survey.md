# Phase 2 Deliverables and Workflow Survey for Phase 3 (Prove)

**Author:** Phase 2 & Workflow Explorer (Phase 3 Discovery)  
**Target Workspace:** `C:\Users\gsjit\OneDrive\Documents\talentra\v2`  
**Reference Deliverables:** `v2/phase2/` (Deliverables 06–12, `findings.md`, `schemas.md`, `README.md`, `scorecards.md`), `v2/phase3/schemas.md`, `v2/phase3/tools/notes_phase3.py`, `v2/phase3/tools/notes_phase3_ext.py`, `v2/db/migrations/V001..V013`, `v2/db/tests/t01..t06`.  
**Generated:** 2026-10-27  

---

## Executive Summary

Phase 2 (*Model*, Steps 06–12, Gate G2) transformed the Stage 1 requirements and business workflows into a formal relational model: 51 entities (16 deferred), 334 attributes, 14 state machines, 80 relationships, a 334-column Data Dictionary v1, a 208-rule Data Rules Catalogue, and a 78-column Data Classification Register.

During Phase 2 modeling and validation against PostgreSQL 16 migrations (`V001`–`V012`), **14 findings** (`FND-01` through `FND-14`: 3 high, 7 medium, 4 low) were identified where the database schema did not yet enforce or protect required business constraints.

In Phase 3 (*Prove*, Steps 13–21, Gate G3), these findings are formally closed in forward-only migration `V013__phase3_refinements.sql` (Step 17: *Design-Based Refinement*). Phase 3 also refines the workflow coverage into an executable CRUD/audit matrix across all 49 lifecycle steps (Step 16), unifies business policies into an expanded 28-rule and 247-data-rule catalog with 5 decision tables and zero gaps (Step 18), updates the Data Dictionary with zero drift and embedded volumetrics (Step 19), binds all 48 negative state machine tests into an end-to-end data/business/NFR test suite (Steps 15 and 20), and establishes the baseline physical ER model (Step 21).

---

## 1. Investigation of the 14 Phase 2 Findings (FND-01..FND-14)

### 1.1 Master Findings Traceability Matrix

| ID | Step | Sev | Entity / Table | Verbatim Phase 2 Finding | Proposed Fix in Phase 2 | Phase 3 Step 17 / V013 Implementation | Verification Test in `t06_phase3_prove.sql` |
|---|---|---|---|---|---|---|---|
| **FND-01** | 08 | High | `job_requirement` | A published job can return to draft: `job_status_id` and `published_at` are both updatable by the API role, and `ck_job_requirement_published` only ties draft to `published_at IS NULL`. FR-JOB-02 forbids it. | `job_status_transition` table + guard trigger (like the application pipeline); `published_at` immutable once set. | Created `job_status_transition` table (7 valid moves) and `trg_job_requirement_guard` executing `job_requirement_guard()`. Enforces write-once `published_at` and blocks `open -> draft`. | `TC-20-001`, `TC-20-002` |
| **FND-02** | 08 | Med | `job_requirement` | `closed` and `filled` jobs can be reopened by any status update; no transition rule exists for jobs. Manual update to `filled` possible while positions open. | Same transition table: `closed` and `filled` are final; `paused ↔ open` only. `filled` settable only when `positions_filled = positions_total`. | `job_status_transition` has no transitions out of `closed` (4) or `filled` (5). Guard trigger blocks premature `filled` status unless `positions_filled = positions_total`. | `TC-20-003`, `TC-20-004`, `TC-20-005`, `TC-20-006` |
| **FND-03** | 08 | High | `organisation` | No entry point lets staff verify or reject an organisation (FR-ORG-06); only the schema owner can change `verification_status_id`. | `organisation_set_verification()` definer function, staff only, transitions `pending → verified / rejected`, `rejected → pending`; audited. | Added `SECURITY DEFINER` function `organisation_set_verification(org_id, status_code, note)` restricted to staff (`organisation_verify`), enforcing allowed state transitions, setting `verified_at` and updating tax IDs, with `audit_event` logging. | `TC-20-007`, `TC-20-008`, `TC-20-009`, `TC-20-010` |
| **FND-04** | 08 | Med | `user_device` | No entry point revokes a device (FR-IAM-06); `revoked_at` exists but no role can set it, and not write-once. | `auth_revoke_device()`: owner or staff, ends the device sessions, audited; write-once guard. | Added `auth_revoke_device(device_id)` (owner or staff), setting `revoked_at`, ending active device sessions (reason 3 or 4), and logging `user_device.revoked`; added `trg_user_device_guard` enforcing write-once `revoked_at`. | `TC-20-011`, `TC-20-012`, `TC-20-013` |
| **FND-05** | 08 | Med | `app_user` | Account status has no transition rule: suspend and deactivate have no entry point, and nothing stops `erased → active` except the email check. | `account_status` transitions in a guard: erased is final; staff-only suspend and reactivate; owner/staff deactivate. | Added `trg_app_user_status_guard` (`app_user_status_guard()`) making `erased` (4) final; added `user_set_account_status(user_id, status_code)` (staff for `suspended`, owner/staff for `deactivated`/`active`), ending sessions and auditing. | `TC-20-014`, `TC-20-015`, `TC-20-016` |
| **FND-06** | 08 | Low | `subscription` | `subscription_guard` does not stop `cancelled_at` being cleared, so a cancellation can be undone silently. | Guard: `cancelled_at` may go from NULL to a value only (write-once). | Updated `subscription_guard()`: raises `check_violation` if `OLD.cancelled_at IS NOT NULL AND NEW.cancelled_at IS DISTINCT FROM OLD.cancelled_at`. | `TC-20-017` |
| **FND-07** | 08 | Low | `organisation_member`, `candidate_block` | `valid_to` and `unblocked_at` can be set back to NULL, reopening a closed period instead of starting a new row. | Guard: closing timestamps are write-once; reopening inserts a new row. | Added `period_close_once_guard()` trigger `trg_organisation_member_close_once` and `trg_candidate_block_close_once` making `valid_to` and `unblocked_at` write-once. | `TC-20-018`, `TC-20-019` |
| **FND-08** | 08 | Low | `notification` | `notification_record_result` accepts any status code without checking the current status (`delivered → queued` is possible). | Check the move against notification status transitions inside the function; `delivered`, `failed`, `suppressed` final. | Updated `notification_record_result()`: checks `(OLD.status, NEW.status) IN ((1,2), (1,3), (1,4), (2,3), (2,4))`; terminal states cannot transition. | `TC-20-020`, `TC-20-021` |
| **FND-09** | 12 | High | `consent_record`, `notification`, `candidate_profile` | Consent purposes `marketing_email` (4), `whatsapp_alerts` (5) and `profile_visible_to_recruiters` (3) exist but nothing reads them: marketing notifications and recruiter visibility do not check consent. | `notification_apply_preference` checks `consent_current` for marketing and WhatsApp; profile visibility requires consent. | Updated `notification_apply_preference()` to suppress category 5 without purpose 4 consent and channel 3 without purpose 5 consent; added `app_users_without_recruiter_consent()` initPlan helper to `app_candidate_visible()` and rewritten `candidate_profile_read` RLS policy. | `TC-20-022`, `TC-20-023` |
| **FND-10** | 12 | Med | `application_answer` | Erasure keeps `answer_text` (personal free text) on applications it keeps. | `candidate_erase` blanks `answer_text` to `[erased]`. | Updated `candidate_erase()`: executes `UPDATE application_answer SET answer_text = '[erased]' WHERE application_id IN (SELECT id FROM application WHERE candidate_profile_id = p.id)`. | `TC-20-024` |
| **FND-11** | 12 | Low | `user_device` | Erasure keeps `device_label` (e.g. "Priya's iPhone"). | `candidate_erase` blanks `device_label`. | Updated `candidate_erase()`: sets `device_label = NULL` and `revoked_at = coalesce(revoked_at, now())` for all user devices. | `TC-20-024` |
| **FND-12** | 12 | Med | Profile sections (13 tables, 52 columns) | Columns without a class comment default to `Internal`, so profile content such as institution, company and job title is labelled `Internal` although it is personal data. | Apply the classification rule of Step 12 in the column comments (reclassification list in the register). | Added 52 explicit `COMMENT ON COLUMN` statements in `V013__phase3_refinements.sql` across all 13 tables tagging each as `Personal.` or `Sensitive.`. | `TC-20-025` |
| **FND-13** | 11 | Med | `organisation`, `wallet` | "Every organisation has exactly one wallet": at most one is a constraint (`uq_wallet_organisation_id`), at least one only holds when the organisation is created through `auth_register_employer()`. Direct `INSERT` leaves org walletless. | Deferred constraint trigger, or create the wallet in an organisation `AFTER INSERT` trigger. | Added `AFTER INSERT ON organisation` trigger `trg_organisation_ensure_wallet` calling `organisation_ensure_wallet()` with `ON CONFLICT (organisation_id) DO NOTHING`. | `TC-20-026` |
| **FND-14** | 11 | Med | `user_credential` | Account lockout after repeated failures relies on the auth service alone; the columns exist but no database rule uses them. | `auth_record_login_failure()` function that increments, locks and audits in one transaction; checked by `auth_open_session()`. | Added `auth_record_login_failure()` setting `locked_until` after 5 failures and logging `user_credential.locked`; updated `auth_open_session()` to refuse locked accounts (`user_session.refused.account_locked`) and clear failed count on success. | `TC-20-027`, `TC-20-028` |

### 1.2 Detailed Finding Breakdown & Mechanics

#### FND-01 & FND-02: Job Status Transitions and Published Immutability
- **Root Cause in Phase 2:** `job_requirement` relied on check constraint `ck_job_requirement_published CHECK ((job_status_id = 1) = (published_at IS NULL))`. Because `v2_app` held direct `UPDATE` privileges on `job_requirement`, a query could execute `UPDATE job_requirement SET job_status_id = 1, published_at = NULL WHERE id = ...`, returning a live or filled job to draft. Furthermore, `closed` (4) and `filled` (5) had no transition guards, allowing closed jobs to be reopened.
- **Phase 3 Refinement (`V013`):**
  1. Created table `job_status_transition (id, from_status_id, to_status_id)` seeded with the 7 legal moves:
     - `draft (1) -> open (2)`
     - `draft (1) -> closed (4)`
     - `open (2) -> paused (3)`
     - `open (2) -> closed (4)`
     - `open (2) -> filled (5)`
     - `paused (3) -> open (2)`
     - `paused (3) -> closed (4)`
  2. Implemented `job_requirement_guard()` before `INSERT OR UPDATE`:
     - Checks `OLD.published_at IS NOT NULL AND NEW.published_at IS DISTINCT FROM OLD.published_at` -> raises `check_violation`.
     - Validates that `(OLD.job_status_id, NEW.job_status_id)` exists in `job_status_transition`.
     - Ensures `NEW.job_status_id = 5` (`filled`) is permitted **only** when `NEW.positions_filled = NEW.positions_total`.

#### FND-03: Staff Organisation Verification Entry Point
- **Root Cause in Phase 2:** FR-ORG-06 mandates that platform staff verify or reject employer organisations based on corporate registry documents. In `V004`, `verification_status_id` was protected by check constraint `ck_organisation_verified_at`, but `v2_app` had no update access to verification columns, and no stored procedure existed for staff.
- **Phase 3 Refinement (`V013`):**
  - Implemented `organisation_set_verification(p_organisation_id bigint, p_status_code text, p_note text)` with `SECURITY DEFINER SET search_path = public`.
  - Enforces authorization: `app_is_staff() OR app_has_permission('organisation_verify')`.
  - Enforces transition state machine: `(pending -> verified), (pending -> rejected), (rejected -> pending)`. Verified is final (unless de-verification assumption SA-01 is approved).
  - Synchronizes `organisation.verified_at` and cascade-updates `organisation_tax_identifier.verification_status_id` and `verified_at`.
  - Writes audit event `organisation.verification_verified` or `organisation.verification_rejected`.

#### FND-04: Device Revocation and Write-Once Guard
- **Root Cause in Phase 2:** `user_device.revoked_at` was defined in `V003`, but no SQL routine or role grant allowed a user or admin to revoke a stolen or decommissioned device (FR-IAM-06).
- **Phase 3 Refinement (`V013`):**
  - Added `trg_user_device_guard` (`user_device_guard()`): `revoked_at` cannot be cleared back to NULL once set.
  - Added `auth_revoke_device(p_device_id bigint)`:
    - Verifies caller is device owner (`app_user_id = app_current_user_id()`) or staff (`app_is_staff()`).
    - Sets `user_device.revoked_at = now()`.
    - Closes all active sessions on that device: `ended_at = now()`, `session_end_reason_id` = 3 (revoked by user) or 4 (revoked by admin).
    - Emits audit event `user_device.revoked`.

#### FND-05: Account Status Lifecycle Enforcement
- **Root Cause in Phase 2:** `app_user.account_status_id` (1=active, 2=suspended, 3=deactivated, 4=erased) lacked transition guards. Only `candidate_erase()` set status 4, but nothing stopped an account moving from erased back to active if an email was provided.
- **Phase 3 Refinement (`V013`):**
  - Added `trg_app_user_status_guard`: raises `check_violation` if `OLD.account_status_id = 4` (`erased account status is final`).
  - Restricts account status transitions to valid pairs: `(1, 2), (2, 1), (1, 3), (3, 1), (1, 4), (2, 4), (3, 4)`.
  - Added `user_set_account_status(p_app_user_id, p_status_code)`:
    - Suspend / Unsuspend requires staff (`user_manage` permission).
    - Deactivate / Reactivate permitted for owner or staff.
    - Terminating an account automatically closes active sessions with reason 3 or 4 and audits.

#### FND-06 & FND-07: Write-Once Closing Timestamps
- **Root Cause in Phase 2:** `subscription_guard()` prevented extending `ends_on`, but permitted setting `cancelled_at` back to NULL. In `organisation_member` and `candidate_block`, setting `valid_to` or `unblocked_at` back to NULL allowed reopening historical rows instead of creating new periods.
- **Phase 3 Refinement (`V013`):**
  - Modified `subscription_guard()`: `OLD.cancelled_at IS NOT NULL AND NEW.cancelled_at IS DISTINCT FROM OLD.cancelled_at` raises exception.
  - Created `period_close_once_guard()` and triggers `trg_organisation_member_close_once` and `trg_candidate_block_close_once`.
  - Rejoining an organisation or re-blocking a user/company requires inserting a new row, preserving historical audit integrity.

#### FND-08: Notification Outbox Delivery State Machine
- **Root Cause in Phase 2:** `notification_record_result()` in `V011` updated delivery status without verifying the prior state, permitting illegitimate regressions (e.g. `delivered -> sent` or `delivered -> queued`).
- **Phase 3 Refinement (`V013`):**
  - Rewrote `notification_record_result(p_notification_id, p_status_code, p_provider_message_ref, p_failure_reason)`.
  - Enforces valid transition pairs: `(1, 2), (1, 3), (1, 4), (2, 3), (2, 4)`.
  - Terminal statuses (`delivered = 3`, `failed = 4`, `suppressed = 5`) reject all subsequent status modifications.

#### FND-09: Privacy and Consent Enforcement on Notifications & Search
- **Root Cause in Phase 2:** Phase 2 Step 12 identified that consent purposes 3 (`profile_visible_to_recruiters`), 4 (`marketing_email`), and 5 (`whatsapp_alerts`) were recorded in `consent_record`, but never evaluated by business queries. Marketing emails were sent regardless of purpose 4 consent; recruiters could view profiles even if purpose 3 consent was withdrawn.
- **Phase 3 Refinement (`V013`):**
  - Updated `notification_apply_preference()` trigger:
    - If `notification_category_id = 5` (marketing) and no active consent exists in `consent_current` for purpose 4 -> sets status to 5 (`suppressed`).
    - If `notification_channel_id = 3` (WhatsApp) and no active consent exists for purpose 5 -> sets status to 5 (`suppressed`).
  - Candidate Recruiter Search Visibility:
    - Created helper `app_users_without_recruiter_consent() RETURNS bigint[]` evaluated as an initPlan array.
    - Updated `app_candidate_visible()` and recreated RLS policy `candidate_profile_read` on `candidate_profile`:
      `AND NOT app_user_id = ANY ((SELECT app_users_without_recruiter_consent())::bigint[])`.

#### FND-10 & FND-11: DPDP Act 2023 Complete Erasure Scrubbing
- **Root Cause in Phase 2:** Under DPDP Act 2023, right to erasure requires scrubbing all personal identifiers while retaining anonymized contractual/financial records. `candidate_erase()` in `V011` left free-text answers in `application_answer.answer_text` and custom device names in `user_device.device_label`.
- **Phase 3 Refinement (`V013`):**
  - Updated `candidate_erase(p_candidate_profile_id)`:
    - Updates all answers on candidate applications: `UPDATE application_answer SET answer_text = '[erased]'`.
    - Clears device labels: `UPDATE user_device SET device_label = NULL, revoked_at = coalesce(revoked_at, now())`.
    - Deletes resumes, education, experience, skills, languages, job alerts, credentials.
    - Anonymizes profile name to `'Erased candidate ' || p.id` and sets `account_status_id = 4`.

#### FND-12: SQL Column Classification Alignment
- **Root Cause in Phase 2:** Data Dictionary v1 defaulted any column lacking a SQL comment to `Internal`. In Step 12, a privacy review discovered 52 columns on personal entities (e.g., candidate education, work experience, device timestamps, profile metrics) that contained personal data but lacked explicit SQL comments.
- **Phase 3 Refinement (`V013`):**
  - Executed 52 `COMMENT ON COLUMN` DDL statements across 13 tables (`app_user`, `consent_record`, `user_device`, `user_session`, `candidate_profile`, `candidate_education`, `candidate_experience`, `candidate_skill`, `candidate_language`, `resume`, `candidate_block`, `job_alert`, `organisation_tax_identifier`).
  - Result: 100% of the 78 Personal and Sensitive columns are explicitly tagged directly in PostgreSQL catalog `pg_description`.

#### FND-13: Guaranteed Wallet per Organisation
- **Root Cause in Phase 2:** Business rule stated "Every organisation has exactly one wallet". In `V004`/`V008`, this was enforced during employer self-registration (`auth_register_employer()`), but a direct `INSERT INTO organisation` (e.g., via admin script or data migration) bypassed wallet creation.
- **Phase 3 Refinement (`V013`):**
  - Added trigger `trg_organisation_ensure_wallet AFTER INSERT ON organisation FOR EACH ROW EXECUTE FUNCTION organisation_ensure_wallet()`.
  - Automatically provisions a wallet with 0 credits and `ON CONFLICT (organisation_id) DO NOTHING`.

#### FND-14: Database-Enforced Credential Lockout
- **Root Cause in Phase 2:** `user_credential` defined columns `failed_attempt_count` and `locked_until`, but lockout enforcement relied entirely on external application-tier logic.
- **Phase 3 Refinement (`V013`):**
  - Implemented `auth_record_login_failure(p_app_user_id, p_max_attempts DEFAULT 5, p_lockout_duration DEFAULT '15 minutes')`.
    - Increments `failed_attempt_count`.
    - On reaching threshold, sets `locked_until = now() + p_lockout_duration` and writes audit event `user_credential.locked`.
  - Updated `auth_open_session()`:
    - Checks `locked_until > now()` -> logs `user_session.refused.account_locked` and returns NULL.
    - On successful authentication, automatically clears `failed_attempt_count = 0` and `locked_until = NULL`.

---

## 2. Business Rules Catalog Evolution (Phase 2 v1 vs Phase 3 Step 18 v2)

### 2.1 Definition in Phase 2 (Step 11)
In Phase 2 Step 11 (`11-data-rules-catalogue.md`), rules were catalogued into three distinct groups totaling **208 rules**:
1. **Business and cross-table rules (DR-001..DR-067):** 67 rules covering candidate registration, memberships, wallet accounting, pipeline guard, consent, and retention jobs.
2. **Standard domains (DR-068..DR-080):** 13 PostgreSQL domains enforcing string length, trimming, regex formatting, and range boundaries (`person_name`, `email_address`, `phone_e164`, `money_amount`, `credit_count`, `percentage`, `latitude`, `longitude`, `lookup_code`, `sha256_digest`, etc.).
3. **Single-table constraints (DR-081..DR-208):** 128 table-level constraints (primary keys, unique constraints, check constraints, exclusion constraints, append-only triggers).

#### Phase 2 Gaps
Phase 2 explicitly classified enforcement points into four values: `Database` (185), `Application` (6), `Pipeline` (11), and **`Gap` (6)**. The six gap rules were:
- `DR-004`: Every organisation has exactly one wallet (FND-13).
- `DR-011`: A device can be revoked by its owner or staff (FND-04).
- `DR-016`: Staff verify organisations: pending → verified / rejected (FND-03).
- `DR-019`: A published job never returns to draft; closed and filled are final (FND-01, FND-02).
- `DR-020`: Pending organisations may publish jobs (open product decision SA-04).
- `DR-047`: Marketing and WhatsApp messages need matching consent (FND-09).

### 2.2 Requirements for Phase 3 Step 18 (`18-business-rules-v2.md`)

Step 18 produces the unified, authoritative specification of all business policies and technical constraints conforming to schema `S-18`:

1. **Expansion and Formalization of Conceptual Rules (`BR-01`..`BR-28`):**
   - In Phase 2, `BR-` identifiers only reached `BR-22` and left कई cross-table policies unassigned. Step 18 expands the canonical register to 28 rules (`BR-01` through `BR-28`):
     - `BR-01`: Standard Surrogate Keys and Foreign Key Constraints.
     - `BR-02`: Candidate Self-Registration Transaction.
     - `BR-03`: Recruiter Candidate Profile Visibility & Consent Filter.
     - `BR-04`: Instant Bilateral Blocking & Contact Masking.
     - `BR-05`: Role-Based Permission Derivation & Active Status Requirement.
     - `BR-06`: Append-Only Consent History & Current Consent View.
     - `BR-07`: User Device Limits & Session Admission.
     - `BR-08`: Brute-Force Password Lockout & Counter Reset.
     - `BR-09`: Subscription Licence Seat Caps & Non-Overlapping Memberships.
     - `BR-10`: Tax Identifier Tokenization & Staff Organisation Verification.
     - `BR-11`: Job Requirement Posting Fee & Published Immutability.
     - `BR-12`: Position Quota Enforcement & Automatic Job Completion.
     - `BR-13`: Single Application per Candidate & Job Eligibility Rules.
     - `BR-14`: Application Pipeline 12-Move State Machine.
     - `BR-15`: Candidate Withdrawal & Recruiter Pipeline Authority.
     - `BR-16`: Append-Only Application Status History.
     - `BR-17`: Subscription Licence Snapshot & Non-Overlapping Periods.
     - `BR-18`: Wallet Credit Ledger Accounting & Reversal Entries.
     - `BR-19`: Idempotent Payment Webhooks, GST Invoices & Reversals.
     - `BR-20`: Profile Download Sourcing Credits & 30-Day Window.
     - `BR-21`: Transactional Outbox Notifications, Deduplication & Suppression.
     - `BR-22`: Immutable Audit Log & Protected Audit Actor.
     - `BR-23`: DPDP Act 2023 Comprehensive Right-to-Erasure.
     - `BR-24`: Strict Organisation Hierarchy & Tenant Isolation.
     - `BR-25`: Consultant Sourcing Restrictions.
     - `BR-26`: Multi-Lingual UI Fallback Architecture.
     - `BR-27`: Scheduled Lifecycle Retention & Partition Management.
     - `BR-28`: Automated Data Quality Anomaly Detection (`F-01`..`F-06`).

2. **Expansion of Data Rules (`DR-001`..`DR-247`):**
   - The granular data rules catalog expands from 208 to 247 entries to incorporate the new table `job_status_transition`, new triggers (`trg_job_requirement_guard`, `trg_user_device_guard`, `trg_app_user_status_guard`, `trg_organisation_member_close_once`, `trg_candidate_block_close_once`, `trg_organisation_ensure_wallet`), and new functions introduced in `V013`.

3. **Complete Elimination of Rule Gaps (0 Open Gaps):**
   - Allowed values for `enforcement_point` in Step 18 are strictly: `Database`, `Application`, `Pipeline`. The value `Gap` is dropped because `V013` closed all 6 Phase 2 rule gaps.

4. **Five Formal Decision Tables (`DT-01`..`DT-05`):**
   To eliminate ambiguity in branching logic, Step 18 introduces 5 comprehensive decision tables:
   - **`DT-01` (Candidate Visibility):** Evaluates owner, staff, recruiter permissions, deletion status, hidden visibility, purpose 3 consent, and bilateral blocks.
   - **`DT-02` (Notification Suppression):** Evaluates category 3 security exemptions, channel opt-outs, category 5 / purpose 4 marketing consent, and channel 3 / purpose 5 WhatsApp consent.
   - **`DT-03` (Login & Session Admission):** Evaluates account status, brute-force lockout, revoked devices, active device counts vs licence limits.
   - **`DT-04` (Profile Download & Contact Reveal):** Evaluates caller permissions, candidate visibility, 30-day prior download deduplication, and wallet credit balance.
   - **`DT-05` (Payment Gateway Webhook Processing):** Evaluates duplicate webhook references, payment order amount matching, allowed state transitions, and credit reversal solvency.

---

## 3. Data Dictionary Evolution (Phase 2 Step 10 v1 vs Phase 3 Step 19 v2)

### 3.1 Comparison Matrix

| Aspect | Phase 2 Step 10 (`10-data-dictionary-v1.md`) | Phase 3 Step 19 (`19-data-dictionary-v2.md`) |
|---|---|---|
| **Underlying Schema Scope** | Migrations `V001`–`V012` | Migrations `V001`–`V013` (includes `job_status_transition` and refinements) |
| **Total Physical Tables Covered** | 48 tables | 49 tables (48 base + `job_status_transition`) + materialized/security-barrier views |
| **Total Columns Documented** | 334 columns | 338 columns (added `job_status_transition` columns) |
| **Automated Drift Check** | None (static markdown file) | Section 1: Automated zero-drift header verifying 1:1 parity with PostgreSQL catalog |
| **Volumetrics Integration** | None (no row counts or growth patterns) | Section 2.1: Embedded volumetrics per table (Prove sample, Launch, Year 1, Year 3, growth pattern) from Step 13 |
| **Governing Rule Linkages** | Generic constraint names only | Section 2.6: Every column and table lists governing `DR-nnn` and `BR-nn` identifiers |
| **Sensitivity Classification Drift** | 52 columns defaulted to `Internal` due to missing comments in DDL | Section 2.9: 100% zero-drift alignment with Step 12; all 78 personal/sensitive columns classified |
| **Exit Test Criteria** | Dictionary v1 complete (334 columns) | Zero drift between DDL and documentation; 0 unclassified personal columns |

### 3.2 Key Changes Required for Step 19
1. **Regeneration directly from DDL (`V001`..`V013`):** To guarantee that manual copy-paste drift cannot occur, Step 19 must parse the live schema or migration scripts.
2. **Inclusion of `job_status_transition`:** Document table `job_status_transition` (columns `id`, `from_status_id`, `to_status_id`, foreign keys, and unique constraint).
3. **Traceability to Step 18 Rules:** Every column with a constraint or foreign key must cite its explicit `DR-nnn` and `BR-nn` ID.
4. **Scale Tiers per Table:** Each table entry must display its row counts across the four lifecycle tiers:
   - `rows_prove_sample`: Exact rows in `seed_prove_sample.sql`
   - `rows_launch`: Projected rows at launch (100k candidate profiles)
   - `rows_year1`: Projected rows at Year 1 (2.5M candidate profiles)
   - `rows_year3`: Projected rows at Year 3 (10M candidate profiles)

---

## 4. Comprehensive Workflow Coverage (49 Steps for Step 16)

### 4.1 Master 49-Step Workflow Coverage Matrix

The 49 workflow and platform steps defined in Phase 2 Step 06 (`06-entity-catalogue.md`) are expanded in Step 16 (`16-schema-coverage-workflow.md`) into their physical database operations (*Stored*, *Retrieved*, *Audited*, *Entry Point*):

| Step ID | Workflow & Action | Actor | Tables Stored (`C`, `U`, `D`) | Tables Retrieved (`R`) | Audited Mechanism | Entry Point (DDL Routine / View / Policy) |
|---|---|---|---|---|---|---|
| **01.1** | Guest signs up with email, phone, password | Candidate | `app_user` (C), `user_credential` (C), `user_access_role` (C), `candidate_profile` (C) | `country` (R), `language` (R) | `trg_app_user_audit`, `trg_user_credential_audit` | `auth_register_candidate()` |
| **01.2** | Terms & privacy consent recorded | Candidate | `consent_record` (C) | `consent_purpose` (R) | Append-only history (`trg_consent_record_append_only`) | `auth_register_candidate()` / `consent_record` INSERT |
| **01.3** | Adds education, experience, skills, languages | Candidate | `candidate_education` (CUD), `candidate_experience` (CUD), `candidate_skill` (CUD), `candidate_language` (CUD) | `skill` (R), `language` (R), `qualification` (R) | `trg_*_audit_columns` | RLS table policies (`candidate_*_write`) |
| **01.4** | Uploads resume, designates primary | Candidate | `resume` (CU) | `candidate_profile` (R) | `trg_resume_audit` | RLS `resume_write`, `candidate_resume_upload()` |
| **01.5** | Sets visibility, salary disclosure, open-to-work | Candidate | `candidate_profile` (U) | `profile_visibility` (R), `salary_disclosure` (R) | `trg_candidate_profile_audit` | RLS `candidate_profile_update` |
| **01.6** | Saves job search alert | Candidate | `job_alert` (CUD) | `city` (R), `currency` (R), `alert_frequency` (R) | `trg_job_alert_audit_columns` | RLS `job_alert_manage` |
| **02.1** | Employer registers organisation, wallet, admin | Employer | `app_user` (C), `user_credential` (C), `user_access_role` (C), `organisation` (C), `wallet` (C), `organisation_member` (C), `consent_record` (C) | `industry` (R), `country` (R) | `trg_organisation_ensure_wallet`, `audit_log()` | `auth_register_employer()` |
| **02.2** | Adds office locations | Account Admin | `organisation_location` (CUD) | `city` (R) | `trg_organisation_location_audit_columns` | RLS `organisation_location_manage` |
| **02.3** | Submits tax identifier (HMAC + last 4) | Account Admin | `organisation_tax_identifier` (C) | `country` (R), `tax_identifier_type` (R) | `trg_organisation_tax_identifier_audit` | `pii_hmac()`, RLS `organisation_tax_id_insert` |
| **02.4** | Staff marks organisation verified/rejected | Admin | `organisation` (U), `organisation_tax_identifier` (U) | `verification_status` (R) | `audit_event` (`organisation.verification_*`) | `organisation_set_verification()` (FND-03) |
| **02.5** | Admin manages recruiter seats (seat cap) | Account Admin | `organisation_member` (CU), `user_access_role` (C) | `subscription` (R), `plan` (R) | `audit_event` (`organisation_member.add/remove`) | `trg_organisation_member_seat_limit`, RLS |
| **03.1** | Drafts job requirement with locations & skills | Recruiter | `job_requirement` (C), `job_requirement_location` (C), `job_requirement_skill` (C) | `skill` (R), `city` (R), `employment_type` (R) | `trg_job_requirement_audit_columns` | RLS `job_requirement_insert` |
| **03.2** | Attaches screening questions | Recruiter | `screening_question` (CUD) | `job_requirement` (R) | `trg_screening_question_audit_columns` | RLS `screening_question_manage` |
| **03.3** | Publishes job: debits 5 credits once | Employer | `job_requirement` (U), `wallet` (U), `wallet_ledger_entry` (C) | `wallet` (R), `job_status_transition` (R) | `trg_job_requirement_charge_posting` | `trg_job_requirement_guard`, `wallet_post()` |
| **03.4** | Pauses or closes job posting | Recruiter | `job_requirement` (U) | `job_status_transition` (R) | `trg_job_requirement_guard` | `trg_job_requirement_guard`, RLS |
| **04.1** | Searches open jobs by keyword, city, salary | Candidate / Guest | (None) | `job_requirement` (R), `job_requirement_location` (R), `organisation` (R) | Lock-free interactive read | `AP-01` GIN search vector query |
| **04.2** | Applies with resume version & screening answers | Candidate | `application` (C), `application_answer` (C), `application_status_history` (C) | `job_requirement` (R), `resume` (R), `screening_question` (R) | `trg_application_record_history`, `forbid_change()` | `application_guard()` trigger |
| **05.1** | Recruiter lists applicants by pipeline stage | Recruiter | (None) | `application` (R), `candidate_profile` (R), `application_status` (R), `ui_translation` (R) | Filtered by tenant RLS | `AP-07` / `employer_hiring_funnel`, `ui_text()` |
| **05.2** | Recruiter advances applicant; notifies candidate | Recruiter | `application` (U), `application_status_history` (C), `notification` (C) | `application_status_transition` (R) | Append-only history + outbox trigger | `application_guard()`, `application_notify()` |
| **05.3** | Hire increments positions; job auto-filled | Recruiter | `job_requirement` (U), `application` (U) | `job_requirement` (R FOR UPDATE) | Row-lock serialisation | `application_guard()` -> `ck_job_requirement_positions` |
| **05.4** | Candidate withdraws application | Candidate | `application` (U), `application_status_history` (C) | `application` (R) | `trg_application_record_history` | `application_guard()` (candidate withdrawal only) |
| **06.1** | Recruiter searches visible candidates by skill/city | Recruiter | (None) | `candidate_profile` (R), `candidate_skill` (R), `candidate_block` (R), `consent_current` (R) | Block & consent filtering | `AP-04/05`, `candidate_profile_read` RLS policy |
| **06.2** | Downloads candidate profile (1 credit, 30d free) | Recruiter | `profile_download` (C), `wallet` (U), `wallet_ledger_entry` (C) | `wallet` (R), `profile_download` (R) | `audit_event` (`profile_download.created`) | `billing_download_profile()` |
| **06.3** | Contact details revealed | Recruiter | (None) | `app_user` (R), `profile_download` (R) | `audit_event` (`candidate_contact.read`) | `candidate_contact()` SECURITY DEFINER function |
| **07.1** | Account admin orders plan or credit recharge | Account Admin | `payment_order` (C) | `plan` (R), `organisation` (R) | `trg_payment_order_audit_columns` | RLS `payment_order_create` |
| **07.2** | Gateway webhook event received and verified | Payment Gateway | `payment_event` (C), `payment_order` (U) | `payment_order` (R FOR UPDATE) | Append-only `payment_event` | `billing_apply_payment_event()` |
| **07.3** | Webhook capture grants credits/licence & invoice | Payment Gateway | `subscription` (C), `wallet` (U), `wallet_ledger_entry` (C), `invoice` (C) | `payment_order` (R), `plan` (R) | `audit_event` (`billing.payment_captured`) | `billing_apply_payment_event()` |
| **07.4** | Gateway refund reverses credits & cancels licence | Payment Gateway | `wallet_ledger_entry` (C), `wallet` (U), `subscription` (U) | `wallet` (R FOR UPDATE) | Reversal entry + audit | `billing_apply_payment_event()` -> `wallet_post()` |
| **07.5** | Admin turns off auto-renew or cancels subscription | Account Admin | `subscription` (U) | `subscription` (R) | Write-once `cancelled_at` guard | `subscription_guard()` |
| **08.1** | Auth service checks credentials & failed count | User | `user_credential` (U) | `user_credential` (R FOR UPDATE) | `audit_event` (`user_credential.locked`) | `auth_record_login_failure()` (FND-14) |
| **08.2** | Expired sessions closed; device fingerprint registered | User | `user_session` (U), `user_device` (CU) | `user_device` (R) | `trg_user_session_audit_columns` | `auth_open_session()` |
| **08.3** | Device limit checked against active sessions | User | (None) | `user_session` (R), `subscription` (R), `app_user` (R FOR UPDATE) | `audit_event` (`user_session.refused.device_limit`) | `auth_open_session()`, `app_device_limit()` |
| **08.4** | Session token hashed & session opened | User | `user_session` (C), `app_user` (U) | `user_session` (R) | `trg_user_session_audit_columns` | `auth_open_session()` |
| **08.5** | Logout or revocation of session/device | User / Admin | `user_session` (U), `user_device` (U) | `user_device` (R FOR UPDATE) | `audit_event` (`user_device.revoked`) | `auth_end_session()`, `auth_revoke_device()` (FND-04) |
| **09.1** | Candidate blocks company or recruiter | Candidate | `candidate_block` (C) | `organisation` (R), `app_user` (R) | `audit_event` (`candidate_block.created`) | `candidate_block` INSERT via RLS |
| **09.2** | Candidate lifts active block | Candidate | `candidate_block` (U) | `candidate_block` (R) | Write-once `unblocked_at` guard | `period_close_once_guard()` (FND-07) |
| **10.1** | Business event writes notification; outbox evaluated | System | `notification` (C) | `notification_preference` (R), `consent_current` (R) | Outbox pattern (`dedupe_key`) | `notification_apply_preference()` (FND-09) |
| **10.2** | Background worker leases due notification batch | Worker | `notification` (U) | `notification` (R FOR UPDATE SKIP LOCKED) | Worker lease timeout | `notification_claim()` |
| **10.3** | Worker records delivery receipt, failure, or retry | Worker | `notification` (U), `system_error` (C) | `notification` (R) | Status transition validation | `notification_record_result()` (FND-08) |
| **10.4** | Scheduled job alert digest matches new jobs | Scheduler | `notification` (C), `job_alert` (U) | `job_alert` (R), `job_requirement` (R) | Batch outbox queuing | Scheduled SQL runner (`AP-10`) |
| **10.5** | User updates category/channel preferences | User | `notification_preference` (CUD) | `notification_category` (R), `notification_channel` (R) | `trg_notification_pref_audit` | RLS `notification_preference_manage` |
| **14.1** | Candidate erasure: sections deleted, PII blanked | Candidate / Admin | `candidate_profile` (U), `candidate_education` (D), `candidate_experience` (D), `candidate_skill` (D), `candidate_language` (D), `resume` (D), `job_alert` (D), `application` (U), `application_answer` (U), `user_device` (U), `user_session` (U), `user_credential` (D), `app_user` (U), `notification` (C) | `candidate_profile` (R FOR UPDATE) | Complete audit log (`candidate_profile.erased`) | `candidate_erase()` (FND-10, FND-11) |
| **14.2** | Scheduler erases accounts inactive for 3 years | Scheduler | Same as 14.1 | `candidate_profile` (R) | Automated compliance audit | `retention_erase_inactive()` |
| **P.1** | Role & permission check on every query | System | (None) | `user_access_role` (R), `access_role_permission` (R), `app_user` (R) | RLS context validation | `app_has_permission()`, `app_is_staff()` |
| **P.2** | Screen labels rendered with English fallback | System | (None) | `ui_label` (R), `ui_translation` (R), `language` (R) | Static cached translation lookup | `ui_text(ui_label_id, language_id)` |
| **P.3** | Forms populate countries, states, cities, currencies | System | (None) | `country` (R), `state` (R), `city` (R), `currency` (R) | Static reference reads | Direct SELECT on reference tables |
| **P.4** | Hourly refresh of hiring funnel aggregate view | Scheduler / Employer | `agg_hiring_funnel_monthly` (C/U) | `application` (R), `application_status_history` (R) | Non-blocking concurrent refresh | `refresh_aggregates()`, `employer_hiring_funnel` |
| **P.5** | Staff and Account Admins review audit trail | Admin / Account Admin | (None) | `audit_event` (R) | RLS restricted audit viewing | RLS `audit_event_read` |
| **P.6** | System errors logged; retention job purges old logs | System | `system_error` (CD) | (None) | Operational diagnostics | `system_error` INSERT / sliding retention job |

---

## 5. Test Suite and ER Model Mappings (Steps 15, 20, 21)

### 5.1 Test Suite v1 Data Architecture (Step 15)
Step 15 (`15-test-suite-v1-data.md`) produces the pure data-layer test harness executing directly against PostgreSQL via `psql`:
- **Domain Enforcement (`TC-15-001`..`010`):** Derived from Phase 2 Step 07 and Step 11 (`DR-068`..`DR-080`). Tests min/max boundaries and invalid values on `person_name`, `email_address`, `phone_e164`, `money_amount`, `percentage`, `latitude`, `longitude`, `sha256_digest`.
- **Constraint & Table Range Checks (`TC-15-011`..`014`):** Tests limits on `total_experience_months` (0..720), `notice_period_days` (0..365), and `positions_total` (1..10,000).
- **Deliberate Invalid Rows (`BAD-01`..`BAD-16`):** Paired negative tests ensuring that bad data rows attempting to violate foreign keys, domains, check constraints, composite keys, and exclusion constraints are refused by the database engine without application intervention.
- **Whole-Database Quality Invariants (`R-01`..`R-16`):** Whole-dataset assertions in `t05_data_quality.sql` proving zero orphaned records, 100% wallet ledger mathematical reconciliation, zero duplicate active blocks, and perfect consistency across all 49 tables.
- **Planted Anomalies Detection (`F-01`..`F-06`):** Verification that the test suite detects the 6 planted migration anomalies in the sample dataset (duplicate candidate group, missing city, experience mismatch, over-seat lapsed org, unverified org open job, stale open-to-work profile).

### 5.2 Test Suite v2 Business Rules, State Transitions & NFRs (Step 20)
Step 20 (`20-test-suite-v2.md`) bridges the relational model to business requirements and NFRs:
- **Phase 2 State Machine Negative Tests (`TC-08-001` through `TC-08-048`):** All 48 negative state transition tests formulated in Phase 2 Step 08 are directly verified in Step 20 across `t02_integrity.sql`, `t03_security.sql`, `t04_concurrency.sql`, `t05_data_quality.sql`, and `t06_phase3_prove.sql`.
- **Phase 2 Findings Closure Verification (`TC-20-001`..`TC-20-028`):** 28 dedicated automated assertions proving that all 14 Phase 2 findings (`FND-01` through `FND-14`) are permanently closed in `V013`.
- **Boundary Value Analysis Register:** 14 exact boundary conditions stressed at `N - 1`, `N`, and `N + 1` (e.g., exact 3-device candidate limit, exact subscription seat limit, 5th consecutive failed login lockout, 30-day profile download deduplication window).
- **Comprehensive NFR Verification Register:** 38 non-functional requirements verified across 11 disciplines:
  - `PERF-01`..`05`: Latency benchmarks, write transaction speed, RLS initPlan efficiency, statement timeouts, deterministic seed generation.
  - `SCAL-01`..`03`: Scale tiers from 10k to 10M, peak burst handling (600 RPS search, 60 RPS login), Year-3 storage budget (< 250 GB target).
  - `REL-01`..`04`: High availability, PITR recovery, transactional outbox deduplication, idempotent webhook boundaries.
  - `SEC-01`..`05`: 4 runtime roles, Argon2id credentials, HMAC tokenized tax IDs, RLS on 100% of business tables, TLS/volume encryption.
  - `PRIV-01`..`04`: DPDP Act 2023 consent tracking, RLS visibility & bilateral blocking, contact reveal audits, single-transaction erasure.
  - `INT-01`..`05`: 13 standard domains, composite foreign keys, concurrency quota locks, append-only history tables, data quality invariants.
  - `AUD-01`..`03`: Audit column triggers, unforgeable audit actor, monthly range partitioning for 7-year audit retention.
  - `I18N-01`..`03`: Multi-script UTF-8 support (Devanagari, Tamil, Latin, mononyms), translated UI strings with English fallback.
  - `MNT-01`..`03`: Checksummed forward-only migrations (`V001`..`V013`), automated catalog standards suite (`t01`), zero-drift DDL documentation.
  - `OBS-01`: Application error logging in `system_error` with BRIN indexing and 8 KB payload cap.
  - `CMP-01`: Indian regulatory compliance (DPDP Act 2023, 18% GST invoice generation, zero raw PAN/GSTIN/card storage).

### 5.3 Baseline ER and Physical Model v1 (Step 21)
Step 21 (`21-baseline-er-and-physical-model.md`) establishes the frozen production baseline:
- **Mermaid ER Diagrams v1:** Upgraded from Step 09 to incorporate `job_status_transition` and Phase 3 refinements.
- **Physical Table & Storage Architecture:** Complete specification of data types, surrogate keys, fillfactors, TOAST storage, and RLS policies across all 49 tables.
- **Index Catalogue & Access Pattern Mapping:** Every B-tree, GIN (full-text search on `job_requirement` and trigram search on `candidate_profile`), GiST (`btree_gist` exclusion constraints on `subscription` and `organisation_member`), BRIN (`audit_event`, `system_error`), partial, and composite index mapped to access patterns `AP-01` through `AP-14`.
- **Concurrency & Locking Hierarchy:** Strict lock ordering (`app_user` -> `organisation` -> `wallet` -> `job_requirement` -> `application`) preventing deadlocks during parallel transactions.
- **Migration Baseline Inventory:** Checksummed repository of `V001` through `V013` with strict change-control policy requiring post-baseline modifications to land as `V014+` with change-log justification.
- **Documented Standard Deviations (`D-01`..`D-04`):**
  - `D-01`: Reference and configuration tables omit `created_by` / `updated_by` (immutable, versioned via git).
  - `D-02`: Composite primary key `(id, occurred_at)` on `audit_event` required for declarative PostgreSQL range partitioning; log tables omit update audit columns.
  - `D-03`: Role-qualified foreign key column naming (`parent_organisation_id`, `blocked_app_user_id`, `sourced_by_app_user_id`, `reverses_ledger_entry_id`) to resolve multiple relationships to the same entity.
  - `D-04`: FKs to static reference lookups and audit columns omit dedicated B-tree indexes because parent tables are never hard-deleted, saving ~35% index overhead.

---

## Conclusion and Handoff Readiness

This survey confirms that the Phase 2 deliverables provide an exceptionally rigorous foundation for Phase 3. The 14 findings (`FND-01`..`FND-14`), 48 negative state machine tests (`TC-08-001`..`TC-08-048`), 49 workflow coverage steps, and privacy classification rules are fully accounted for, cleanly resolved in migration `V013__phase3_refinements.sql`, and systematically verified by test suite `t06_phase3_prove.sql`.

Phase 3 execution agents have complete structural and relational context to generate deliverables 13 through 21 and produce honest Quad Model scorecards and Gate G3 review artifacts.
