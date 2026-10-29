# Step 03 — Feature Discovery

Conforms to Stage 1 schema [S-03](output-schemas.md#s-03--feature-discovery). Combines the complete functional feature inventory (`FR-REF-01`..`FR-COM-04`) traced to Stage 1 requirements (`REQ-001`..`REQ-039`) with the competitive coverage benchmark across Naukri, Monster (foundit), and LinkedIn (Docket §4) and the formal Coverage Gap Register (`G1`..`G12`, `Q1`..`Q4`).

---

## 1. Feature Inventory (MoSCoW Prioritised & Traced to S-01 Requirements)

Priority codes follow MoSCoW: **Must** (mandatory v2 baseline), **Should** (high-value v2 inclusion), **Could** (nice-to-have / backlog), **Won't** (explicitly excluded or deferred per ADR-013).

### 1.1 Reference Data (`REF`)

| Feature ID | Module | Actor + Capability Statement | Priority | Differentiator | Traces To (S-01) |
|---|---|---|---|---|---|
| `FR-REF-01` | `REF` | Maintain countries, states, cities (with WGS 84 coordinates), currencies, languages, skills, industries, qualifications, employment types and work modes | Must | No | `REQ-026`, `REQ-027` |
| `FR-REF-02` | `REF` | Every fixed set of values is a lookup table with a stable `code`, a translated label (`ui_label_id`), an `is_active` flag and a `sort_order`; no free-text enumerations | Must | Yes | `REQ-026`, `REQ-031` |
| `FR-REF-03` | `REF` | UI strings are stored by key and translated per language; a missing translation falls back automatically to English (`ui_text()`) | Must | Yes | `REQ-031` |
| `FR-REF-04` | `REF` | Skill type-ahead from two typed letters, tolerant of typos via trigram GIN index (`AP-09`) | Should | Yes | `REQ-004`, `REQ-011` |

### 1.2 Identity and Access (`IAM`)

| Feature ID | Module | Actor + Capability Statement | Priority | Differentiator | Traces To (S-01) |
|---|---|---|---|---|---|
| `FR-IAM-01` | `IAM` | A candidate registers themselves with email (optional E.164 phone) and password, accepting terms and privacy policy; consent is recorded with its policy version | Must | Yes | `REQ-001`, `REQ-028` |
| `FR-IAM-02` | `IAM` | Recruiters, employers and consultants cannot register a candidate; they can only contact or source one | Must | No | `REQ-002` |
| `FR-IAM-03` | `IAM` | An employer registers their organisation; this creates the organisation (`pending`), its wallet, and the user as account admin in one transaction | Must | No | `REQ-007`, `REQ-018` |
| `FR-IAM-04` | `IAM` | Nine docket actors with role-based permissions, enforced inside the database via `app_has_permission()` and RLS | Must | Yes | `REQ-025` |
| `FR-IAM-05` | `IAM` | Login opens a session on a registered device; past the licence's device limit the login is refused under a user-row lock and the refusal is audited | Must | Yes | `REQ-020`, `REQ-030` |
| `FR-IAM-06` | `IAM` | A user can log out and revoke their sessions and devices (`auth_revoke_device()`); staff can revoke anyone's; revocations are audited | Must | Yes | `REQ-020`, `REQ-030` |
| `FR-IAM-07` | `IAM` | Consent per purpose is an append-only history; withdrawing inserts a new record; current state is queryable via `consent_current` | Must | Yes | `REQ-028` |
| `FR-IAM-08` | `IAM` | Lock an account for 15 minutes after 5 consecutive failed logins (`auth_record_login_failure()`) and audit the lockout | Should | Yes | `REQ-025`, `REQ-030` |
| `FR-IAM-09` | `IAM` | OTP and federated social login | Could | No | New insight (backlog) |

### 1.3 Organisation and Account (`ORG`)

| Feature ID | Module | Actor + Capability Statement | Priority | Differentiator | Traces To (S-01) |
|---|---|---|---|---|---|
| `FR-ORG-01` | `ORG` | Organisation profile: legal and display name, industry, country, website, office locations (at most one headquarters), and corporate group hierarchy (cycle-free) | Must | Yes | `REQ-007`, `REQ-008` |
| `FR-ORG-02` | `ORG` | A recruiter sees and acts only on their own company's job requirements, applications, and hiring funnel | Must | Yes | `REQ-010`, `REQ-025` |
| `FR-ORG-03` | `ORG` | Tax and registration identifiers (GSTIN, PAN, CIN, VAT, EIN) kept with country, type and verification status, stored only as keyed HMAC-SHA256 + last 4 characters | Must | Yes | `REQ-009`, `REQ-029` |
| `FR-ORG-04` | `ORG` | Membership is effective-dated (`valid_from`, `valid_to`); a user belongs to at most one organisation at a time (`EXCLUDE USING gist`); history is kept | Must | Yes | `REQ-010` |
| `FR-ORG-05` | `ORG` | The number of current members cannot exceed the `max_seats` of the active subscription licence, enforced under concurrent additions | Must | Yes | `REQ-019` |
| `FR-ORG-06` | `ORG` | Staff verify or reject organisations (`pending → verified / rejected`) via `organisation_set_verification()`, recording `verified_at` and an audit event | Must | Yes | `REQ-009`, `REQ-030` |
| `FR-ORG-07` | `ORG` | Granular custom sub-roles inside an employer beyond account admin, employer, and recruiter | Won't | No | `REQ-010` (out of scope) |

### 1.4 Candidate Profile (`PRO`)

| Feature ID | Module | Actor + Capability Statement | Priority | Differentiator | Traces To (S-01) |
|---|---|---|---|---|---|
| `FR-PRO-01` | `PRO` | Profile core: name in any script, headline, summary, city, total experience, expected salary (`disclosed` / `not_disclosed` / `not_provided`), notice period, `is_open_to_work` | Must | Yes | `REQ-003`, `REQ-031` |
| `FR-PRO-02` | `PRO` | Education history with qualification lookup, institution, field of study, start/end years, and grade percentage | Must | No | `REQ-004` |
| `FR-PRO-03` | `PRO` | Work experience history; at most one current job (`end_date IS NULL`) enforced by partial unique index | Must | No | `REQ-004` |
| `FR-PRO-04` | `PRO` | Candidate skills with proficiency level and experience months | Must | No | `REQ-004` |
| `FR-PRO-05` | `PRO` | Spoken/written languages with proficiency level | Must | No | `REQ-004`, `REQ-031` |
| `FR-PRO-06` | `PRO` | Resume versions stored as object-storage references with SHA-256 checksum; at most one primary resume per candidate | Must | Yes | `REQ-005` |
| `FR-PRO-07` | `PRO` | Profile visibility (`public`, `recruiters_only`, `hidden`) combined with `profile_visible_to_recruiters` consent enforced in RLS | Must | Yes | `REQ-006`, `REQ-028` |
| `FR-PRO-08` | `PRO` | A candidate blocks a company or a person; the blocked party immediately loses visibility of the candidate, their applications and contact details, and never sees the block row | Must | Yes | `REQ-006`, `REQ-028` |
| `FR-PRO-09` | `PRO` | Saved job alerts with keywords, city, minimum salary, and digest frequency | Should | No | `REQ-023` |
| `FR-PRO-10` | `PRO` | Profile completion score calculation | Could | No | New insight |
| `FR-PRO-11` | `PRO` | Profile view history, activity log, bookmarks (Docket Tier 2) | Should | No | `REQ-021` |
| `FR-PRO-12` | `PRO` | Candidate assessments, courses, and portfolio projects | Could | No | Deferred (Tier 2/3) |

### 1.5 Job Requirements (`JOB`)

| Feature ID | Module | Actor + Capability Statement | Priority | Differentiator | Traces To (S-01) |
|---|---|---|---|---|---|
| `FR-JOB-01` | `JOB` | Post a job: title, description (language recorded), employment type, work mode, industry, experience range, salary range or `not_disclosed`, positions, locations, skills | Must | No | `REQ-011`, `REQ-031` |
| `FR-JOB-02` | `JOB` | Job lifecycle: `draft → open ↔ paused → closed / filled`; a published job never returns to `draft`, and `closed`/`filled` are terminal (`job_status_transition`) | Must | Yes | `REQ-012` |
| `FR-JOB-03` | `JOB` | Publishing a job (`draft → open`) costs 5 credits, debited from the organisation wallet exactly once via idempotency key `job_post:<id>` | Must | Yes | `REQ-012`, `REQ-018` |
| `FR-JOB-04` | `JOB` | Screening questionnaire attached to a job with typed questions (`boolean`, `numeric`, `single_choice`, `free_text`) and mandatory flag | Must | No | `REQ-011` |
| `FR-JOB-05` | `JOB` | A job can be opened to external recruitment consultants (`is_open_to_consultants`) | Must | Yes | `REQ-016` |
| `FR-JOB-06` | `JOB` | Full-text job search by keywords, city and salary, ordered newest first (`AP-01`) | Must | No | `REQ-013` |
| `FR-JOB-07` | `JOB` | A closing date (`closes_on`) stops new applications after that date | Should | No | `REQ-012`, `REQ-014` |
| `FR-JOB-08` | `JOB` | Each `joined` application increments `positions_filled`; when `positions_filled = positions_total` the job automatically transitions to `filled`, refusing excess joins | Should | Yes | `REQ-015` |

### 1.6 Applications and Pipeline (`APP`)

| Feature ID | Module | Actor + Capability Statement | Priority | Differentiator | Traces To (S-01) |
|---|---|---|---|---|---|
| `FR-APP-01` | `APP` | A candidate applies at most once per job, optionally attaching one of their own resume versions (enforced by composite FK `fk_application_resume`) | Must | Yes | `REQ-014` |
| `FR-APP-02` | `APP` | Screening answers can only reference questions belonging to the job applied for (enforced by composite FKs on `(id, job_requirement_id)`) | Must | Yes | `REQ-014` |
| `FR-APP-03` | `APP` | Applications are accepted only on `open`, published jobs on or before `closes_on` | Must | Yes | `REQ-014` |
| `FR-APP-04` | `APP` | The hiring pipeline permits only the 12 transitions in `application_status_transition`; illegal jumps are refused by trigger | Must | Yes | `REQ-015` |
| `FR-APP-05` | `APP` | A candidate can only transition their own application to `withdrawn`; recruiters/employers execute hiring stage moves | Must | Yes | `REQ-015`, `REQ-025` |
| `FR-APP-06` | `APP` | Every status change is recorded in append-only `application_status_history` with timestamp, actor, and note | Must | Yes | `REQ-015`, `REQ-030` |
| `FR-APP-07` | `APP` | Recruiter pipeline view per job (`AP-03`); candidate's application list with status labels in their preferred language (`AP-02`) | Must | Yes | `REQ-015`, `REQ-031` |
| `FR-APP-08` | `APP` | Every pipeline status change queues a candidate notification in the same transaction | Should | Yes | `REQ-022` |
| `FR-APP-09` | `APP` | Interview scheduling slots and formal offer letter documents | Could | No | Deferred |

### 1.7 Subscriptions, Wallet and Payments (`BIL`)

| Feature ID | Module | Actor + Capability Statement | Priority | Differentiator | Traces To (S-01) |
|---|---|---|---|---|---|
| `FR-BIL-01` | `BIL` | Product plans (`starter`, `growth`, `enterprise`) with price, duration, `max_seats`, `max_devices_per_user`, and `included_credits` | Must | No | `REQ-017` |
| `FR-BIL-02` | `BIL` | A subscription is an immutable licence snapshot: active periods never overlap per organisation (`ex_subscription_no_overlap`); `cancelled_at` is write-once | Must | Yes | `REQ-017`, `REQ-019` |
| `FR-BIL-03` | `BIL` | Exactly one wallet per organisation (`trg_organisation_ensure_wallet`); append-only ledger; `balance_credits` equals ledger sum and never goes negative | Must | Yes | `REQ-018` |
| `FR-BIL-04` | `BIL` | Payment orders with idempotent gateway webhooks (`billing_apply_payment_event()`): amount-checked, forward-only status moves | Must | Yes | `REQ-017`, `REQ-018` |
| `FR-BIL-05` | `BIL` | A profile download costs 1 credit (`billing_download_profile()`); repeat downloads by the same organisation within 30 days are free | Must | Yes | `REQ-021` |
| `FR-BIL-06` | `BIL` | Candidate contact details (`email`, `phone_e164`) are released only via `candidate_contact()` when an active 30-day download exists, and every reveal is audited | Must | Yes | `REQ-021`, `REQ-030` |
| `FR-BIL-07` | `BIL` | A GST invoice is generated for every captured payment; a refund reverses the credits it granted (and is refused if those credits were already spent) | Must | Yes | `REQ-017`, `REQ-018` |
| `FR-BIL-08` | `BIL` | Recruiter outreach debits credits from the organisation wallet | Should | No | `REQ-018` |
| `FR-BIL-09` | `BIL` | Chronological wallet ledger statement (`AP-08`) | Must | No | `REQ-018` |

### 1.8 Notifications, Audit, and Analytics (`NOT`, `AUD`, `ANA`)

| Feature ID | Module | Actor + Capability Statement | Priority | Differentiator | Traces To (S-01) |
|---|---|---|---|---|---|
| `FR-NOT-01` | `NOT` | Notification preferences per category and channel; opt-outs and marketing/WhatsApp consent (`consent_current`) are respected except for `account_security` | Must | Yes | `REQ-022`, `REQ-028` |
| `FR-NOT-02` | `NOT` | Transactional outbox: written in the same transaction, claimed via `FOR UPDATE SKIP LOCKED`, retried with backoff up to 5 attempts, forward-only status guard | Must | Yes | `REQ-022` |
| `FR-NOT-03` | `NOT` | In-app notification inbox (`AP-10`) | Should | No | `REQ-022` |
| `FR-NOT-04` | `NOT` | User's `preferred_language_id` drives UI label translation with English fallback | Must | Yes | `REQ-031` |
| `FR-NOT-05` | `NOT` | Scheduled job alert digests (`instant`, `daily`, `weekly`) | Should | No | `REQ-023` |
| `FR-AUD-01` | `AUD` | Every sensitive action is recorded in monthly-partitioned append-only `audit_event` via `audit_log()`; actor is taken from transaction context and cannot be forged | Must | Yes | `REQ-030` |
| `FR-AUD-02` | `AUD` | Account admins read their own organisation's audit trail; Talentra staff read all (`audit_event_read` RLS policy) | Must | Yes | `REQ-025`, `REQ-030` |
| `FR-AUD-03` | `AUD` | Application/system errors logged in append-only `system_error` with 90-day retention | Should | No | `REQ-030` |
| `FR-ANA-01` | `ANA` | Employer monthly hiring funnel (`agg_hiring_funnel_monthly` + security-barrier view `employer_hiring_funnel`): stage counts and median days to join | Should | Yes | `REQ-024` |
| `FR-ANA-02` | `ANA` | KPI analytical aggregations derived directly from operational histories | Should | No | `REQ-024` |

### 1.9 Deferred Subsystem Features (`GIG`, `SRC`, `COM` — Conceptual Only per ADR-013)

| Feature ID | Module | Actor + Capability Statement | Priority | Scope Status | Traces To (S-01) |
|---|---|---|---|---|---|
| `FR-GIG-01..07` | `GIG` | Gig marketplace: requests with window/pricing, gig worker availability, assignments, ratings, earnings references (`ENT-D01`..`ENT-D09`) | Won't (Deferred) | Deferred to Gig Subsystem (ADR-013) | `REQ-032`..`REQ-035` |
| `FR-SRC-01..04` | `SRC` | Consultant sourcing requests, bulk outreach batches and recipients (`ENT-D10`..`ENT-D12`) | Won't (Deferred) | Deferred to Sourcing Subsystem | `REQ-016`, `REQ-036` |
| `FR-COM-01..04` | `COM` | Community posts/reactions, support tickets, FAQs, referral events | Won't (Deferred) | Deferred (Tier 3) | `REQ-037`..`REQ-039` |

---

## 2. Competitor Coverage Matrix (Docket §4: Naukri vs. Monster/foundit vs. LinkedIn vs. Talentra)

**Legend:** `✔` Captured · `◐` Partly / free-text only · `✘` Not captured · `—` Not applicable.

| Domain | Data Element | Naukri | Monster / foundit | LinkedIn | Talentra Position | Where in Talentra v2 |
|---|---|---|---|---|---|---|
| Candidate | Name in any script, language recorded | ◐ | ◐ | ◐ | **Exceeds** (`✔`) | `candidate_profile.full_name` (UTF-8, any script), `preferred_language_id` |
| Candidate | Headline & summary with language tag | ✔ | ✔ | ✔ | **Matches** (`✔`) | `headline`, `summary`, `summary_language_id` |
| Candidate | Contact: email & E.164 phone with country | ◐ | ◐ | ◐ | **Exceeds** (`✔`) | `app_user.email`, `phone_e164`, `phone_country_id` |
| Candidate | Expected salary with explicit disclosure state | ✔ | ✔ | ✘ | **Exceeds** (`✔`) | `salary_disclosure_id` (`disclosed`, `not_disclosed`, `not_provided`), `expected_salary_amount` |
| Candidate | Total experience & notice period days | ✔ | ✔ | ◐ | **Matches** (`✔`) | `total_experience_months`, `notice_period_days` |
| Candidate | Work history (at most 1 current job enforced) | ✔ | ✔ | ✔ | **Exceeds** (`✔`) | `candidate_experience` + `uq_candidate_experience_current` |
| Candidate | Education with qualification & percentage | ✔ | ✔ | ✔ | **Matches** (`✔`) | `candidate_education` (`qualification_id`, `grade_percentage`) |
| Candidate | Skills with proficiency & experience months | ✔ | ✔ | ◐ | **Exceeds** (`✔`) | `candidate_skill` (`proficiency_level_id`, `experience_months`) |
| Candidate | Skill endorsements by peers | ✘ | ✘ | ✔ | **Gap G1** (`✘`) | Out of scope (social network feature) |
| Candidate | Languages with proficiency | ✔ | ✔ | ◐ | **Matches** (`✔`) | `candidate_language` |
| Candidate | Resume versions with SHA-256 & 1 primary | ✔ | ✔ | ◐ | **Exceeds** (`✔`) | `resume` + `uq_resume_candidate_profile_id_primary` |
| Candidate | Privacy: visibility + company/user blocking | ✔ | ◐ | ◐ | **Exceeds** (`✔`) | `profile_visibility_id`, `candidate_block` enforced in PostgreSQL RLS |
| Candidate | Append-only DPDP consent history per purpose | ✘ | ✘ | ◐ | **Exceeds** (`✔`) | `consent_record` + `consent_current` enforced in RLS & outbox |
| Candidate | Job alerts / saved searches | ✔ | ✔ | ✔ | **Matches** (`✔`) | `job_alert` |
| Candidate | Who downloaded my profile (with credit debit) | ✔ | ◐ | ✔ | **Exceeds** (`✔`) | `profile_download` linked to `wallet_ledger_entry` |
| Employer | Company profile, HQ location, cycle-free tree | ◐ | ◐ | ✔ | **Exceeds** (`✔`) | `organisation`, `organisation_location`, `organisation_prevent_cycle()` |
| Employer | Tokenised tax IDs (HMAC-SHA256 + last 4) | ◐ | ◐ | ✘ | **Exceeds** (`✔`) | `organisation_tax_identifier` + `pii_hmac()` |
| Employer | Effective-dated recruiter membership (no overlap) | ◐ | ◐ | ◐ | **Exceeds** (`✔`) | `organisation_member` + GiST exclusion constraint |
| Hiring & Billing | Job lifecycle + transition table + position cap | ◐ | ◐ | ◐ | **Exceeds** (`✔`) | `job_requirement`, `job_status_transition`, `application_guard()` |
| Hiring & Billing | Screening questionnaires bound by composite FK | ✔ | ✔ | ✔ | **Exceeds** (`✔`) | `screening_question`, `application_answer` |
| Hiring & Billing | Full pipeline history + transition table | ◐ | ◐ | ◐ | **Exceeds** (`✔`) | `application_status_history`, `application_status_transition` |
| Hiring & Billing | Licence seats & device limits under concurrency | ◐ | ◐ | ◐ | **Exceeds** (`✔`) | `subscription`, `user_device`, `user_session` (row-lock enforced) |
| Hiring & Billing | Append-only credit wallet ledger & GST invoices | ✔ | ◐ | ✘ | **Exceeds** (`✔`) | `wallet`, `wallet_ledger_entry`, `payment_order`, `invoice` |

---

## 3. Coverage Gap Register (`G1`..`G12`, `Q1`..`Q4`)

| Gap ID | Gap Description | Priority | Architectural Decision | Phase 3 Prove Validation |
|---|---|---|---|---|
| `G1` | Peer skill endorsements | Low | Excluded: social feature with weak hiring signal | None (out of scope) |
| `G2` | Candidate references / recommendations | Medium | Deferred: requires referee consent workflow | None (deferred) |
| `G3` | Volunteer work, awards, publications, patents | Low | Deferred: covered by free-text `summary` in v2 | None (deferred) |
| `G4` | Explicit career break flag | Medium | Inferable from gaps between `candidate_experience` dates | Verified via experience date queries |
| `G5` | Disability / diversity self-identification | Medium | Deliberately omitted in v2: Sensitive data requiring dedicated consent | None (privacy by design) |
| `G6` | Work authorisation / visa status | Low | Deferred (India-first launch; covered by screening questions) | Covered via `screening_question` |
| `G7` | Preferred shift | Medium | Covered per job via `screening_question` | Covered via `screening_question` |
| `G8` | Social network connections / followers | Out of scope | Excluded per Docket §1 | None (out of scope) |
| `G9–G12` | Culture pages, reviews, salary benchmarks, trending flags | Tier 3 | Optional Tier 3 features; deferred | None (deferred) |
| `Q1` | Probable duplicate candidate registrations | High (DQ) | Detected on `(phone_e164, lower(full_name))` via `idx_app_user_phone_e164` | **Verified in `t05_data_quality.sql` (`F-01`)** |
| `Q2` | Profiles with missing current city (`NULL`) | Medium (DQ) | Allowed at sign-up; flagged for profile completion campaigns | **Verified in `t05_data_quality.sql` (`F-02`)** |
| `Q3` | Total experience header vs. work history mismatch | Medium (DQ) | Detected by comparing `total_experience_months` against non-overlapping history | **Verified in `t05_data_quality.sql` (`F-03`)** |
| `Q4` | Stale `is_open_to_work` flags (> 90 days inactive) | Medium (DQ) | Detected and expired by retention/data-quality query | **Verified in `t05_data_quality.sql` (`F-06`)** |
