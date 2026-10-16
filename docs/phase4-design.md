# Talentra — Phase 4 Design (Notifications, Analytics and shared team items)

**Scope:** Milestones 15–18, backlogs B48–B59 (Phase 4 complete; the schema is complete). Modules: **Notifications, preferences and community**, **Analytics layer and reporting marts**, **Shared team items** (all team-owned).
**Status:** M15–M18 built and verified on PostgreSQL 16 (`./run_phase1.sh m15` … `m18`).

| File | Contents |
|---|---|
| `sql/12_notifications.sql` | Preferences (language, privacy, notification, job alerts), notifications and deliveries, community posts and reactions, support tickets, FAQs, referral events |
| `sql/13_shared.sql` | Credentials, consent records, blocking lists, system error log |
| `sql/14_analytics.sql` | Star schema: 5 dimensions, 11 facts, 4 aggregates |
| `sql/tests/m15_entities.sql` … `m18_constraints.sql` | Milestone checks (m17 shares `check_columns.sql` with m9 and m13) |
| `docs/phase4-data-dictionary.md` | Generated column list |

As in Phases 2–3, tables are created with their columns, foreign keys and structural CHECKs, so the schema-wide column rules (m4, m9/m13) keep passing. The M18 rules are triggers, constraints and row-level security policies in the same files.

---

## Milestone 15 — Entities (B48–B50)

### B48 Notifications, preferences and community

| Entity | Purpose |
|---|---|
| `user_preference` | One row per user (1 : 0..1): **language preference** (`preferred_language_id`), time zone, and **privacy settings**: searchable by employers, show contact details, allow recruiter outreach, allow profile download |
| `notification_preference` | Per user × notification type × channel: on or off. No row means the type's default |
| `job_alert` | A candidate's saved search (keywords, city, role, industry, employment type, work mode, salary floor) with a frequency; at least one criterion |
| `notification` | One per event per recipient: type, template reference, short summary for the in-app list, what it is about (`target_table` / `target_record_id`), read time |
| `notification_delivery` | One per channel tried: provider message reference, status, sent / delivered / failed times. The high-volume write path, partitioned monthly |
| `community_post` | Post or reply (`parent_community_post_id`), text stored once in its language, moderation status, soft delete |
| `community_reaction` | One reaction per user per post |
| `support_ticket` / `support_ticket_message` | Ticket with category, priority, status, assignee and resolution times; append-only conversation, with internal notes flagged |
| `faq` | Question and answer as UI label keys (rule group 7: platform text is translated by key), by category |
| `referral_event` | History of a Phase 1 `referral` (invited → registered → applied → hired → rewarded), append-only |

**Decision D20 — one preference row per user; channels reuse `outreach_channel`.** Language and privacy are per-user settings with defaults, so they share one 1 : 0..1 row instead of four key/value tables. Notification channels are the same four channels outreach uses (email, SMS, WhatsApp, in-app), so `outreach_channel` serves both and no second channel list exists.

**Decision D22 — notification and delivery are split; only deliveries are partitioned.** A notification can go out on several channels, and each channel has its own provider status, so `delivery → notification` is N : 1. Deliveries carry the callback traffic, so they are partitioned monthly by `queued_at`. `notification` stays unpartitioned so it can be a plain FK target: a partitioned parent would force a composite FK containing a timestamp column, which the FK naming rule (m4: FK columns end in `_id`) does not allow.

### B50 Shared team items

| Item | Entity |
|---|---|
| Credentials | `user_credential`: password as an argon2id hash or a social sign-in as an HMAC of the provider subject. Revoked credentials are kept |
| Consent records | `consent_record`: every grant or withdrawal is a new row with policy version and evidence (IP, user agent). Append-only; the current state is the latest row |
| Identity sessions | `user_session` (Phase 3, **D15**), reused |
| Audit trail | `audit_event` (Phase 2), reused |
| Blocking lists for candidates, employers, recruiters and consultants | `block_entry`: a user blocks exactly one user or one organisation; unblocking closes the entry |
| System errors (Tier 1 "audit and error logging") | `system_error_event`: append-only, monthly partitions. This closes a Tier 1 gap left open since Phase 1 |

**Decision D21 — shared items are reused where they already exist.** Sessions and the audit trail were built in Phases 2–3 and are used across modules, so Phase 4 adds no second copy. m15 asserts that each B50 item maps to an entity.

The gig marketplace keeps its own `gig_worker_list_entry` (favourite / blacklist of workers by requesters, Phase 2). That list decides which gigs a worker can apply for. `block_entry` controls profile visibility. They have different purposes and different rules.

### B49 Analytics layer and reporting marts

**KPIs.** B49 and the module table refer to "the KPIs in Section 8", but the docket as issued has no Section 8: it ends at Section 7, the delivery plan. **This gap should be raised with the organisers.** The KPI set below is derived from the core workflows in §2 and the Tier 1 domains in §4, and m15 asserts that every KPI has a fact.

| # | KPI | Fact (grain) | Aggregate |
|---|---|---|---|
| 1 | Applications and stage conversion (applied → shortlisted → interviewed → offered → joined) | `fact_application` (application, accumulating snapshot) | `agg_hiring_funnel_monthly` |
| 2 | Time to shortlist, time to hire | `fact_application` | `agg_hiring_funnel_monthly` |
| 3 | Requirements posted, fill rate, time to fill | `fact_job_posting` (requirement, accumulating) | `agg_job_posting_monthly` |
| 4 | Profile views, downloads, credits used | `fact_profile_engagement` (event) | `agg_sourcing_monthly` |
| 5 | Outreach delivery and response rate | `fact_outreach` (recipient) | `agg_sourcing_monthly` |
| 6 | Consultant request acceptance rate and decision time | `fact_sourcing_request` (request) | — |
| 7 | Revenue, refunds, credits sold | `fact_payment` (order) | `agg_revenue_monthly` |
| 8 | Credits consumed by purpose | `fact_wallet_transaction` (ledger entry) | — |
| 9 | Gig fill, earnings, average rating | `fact_gig_assignment` (assignment) | — |
| 10 | Logins and device-limit refusals | `fact_login_daily` (day × organisation × outcome) | — |
| 11 | Notification delivery rate | `fact_notification_daily` (day × type × channel × status) | — |
| 12 | Support volume and resolution time | `fact_support_ticket` (ticket) | — |
| 13 | Candidate supply and profile completeness | `dim_candidate` (versions by registration date) | — |

**Dimensions.**

| Dimension | Type | Notes |
|---|---|---|
| `dim_date` | static | `id` = yyyymmdd smart key (CHECK); 2015–2035 generated in the DDL |
| `dim_location` | SCD 1 | City, state, country code |
| `dim_organisation` | **SCD 2** | A new version on a change of industry, size band, verification status or headquarters: `valid_from`, `valid_to`, `is_current` |
| `dim_candidate` | **SCD 2** | Banded only (experience band, highest qualification, fresher, completion %, location). No name, contact or exact salary |
| `dim_job_requirement` | SCD 1 | Role, industry, employment type, work mode, salary band, consultant openness |

**Decision D19 — the marts live in the same database, prefixed, decoupled from the transactional rows.**
- **Prefixed objects.** Analytical objects are `dim_`, `fact_` and `agg_` (rule group 8). m15 asserts that only analytical objects use those prefixes.
- **Enforced keys.** Facts reference dimensions by enforced FKs (rule group 2).
- **Degenerate source keys.** The source row id (`application_id`, `payment_order_id`, …) is kept as a degenerate key without an FK. The marts can then be loaded from a read replica, and erasing or anonymising a source row never blocks or rewrites reporting history.
- **Copied codes.** Dimensions hold lookup codes copied at load time (not free text), so a report needs no join back to the transactional side.
- **Aggregates.** Aggregates are materialised views over the facts; their refresh rule is part of M18.
- **No personal data in the marts.** Dimensions carry no direct identifiers, so the analytical layer can be opened to analysts without exposing Personal data.

---

## Milestone 16 — Relationships (B51–B53)

### Notifications, preferences, community and shared items

```mermaid
erDiagram
    user_account ||--o| user_preference : "prefers"
    language ||--o{ user_preference : "preferred language"
    user_account ||--o{ notification_preference : "sets"
    notification_type ||--o{ notification_preference : "for type"
    candidate_profile ||--o{ job_alert : "saves"
    user_account ||--o{ notification : receives
    job_alert |o--o{ notification : "produces"
    notification ||--o{ notification_delivery : "delivered via"
    user_account ||--o{ community_post : writes
    community_post |o--o{ community_post : "reply to"
    community_post ||--o{ community_reaction : "reacted to"
    user_account ||--o{ community_reaction : reacts
    user_account ||--o{ support_ticket : raises
    support_ticket ||--o{ support_ticket_message : "conversation"
    ui_label_key ||--o| faq : "question"
    referral ||--o{ referral_event : "history"
    application |o--o{ referral_event : "applied / hired"
    user_account ||--o{ user_credential : "signs in with"
    user_account ||--o{ consent_record : "consents"
    user_account ||--o{ user_session : "session (D15)"
    user_account ||--o{ audit_event : "actor"
    user_account ||--o{ block_entry : "blocker"
    user_account |o--o{ block_entry : "blocked user"
    organisation |o--o{ block_entry : "blocked organisation"
```

| Relationship | Card. | ON DELETE | Reason |
|---|---|---|---|
| user_account → user_preference | 1 : 0..1 | CASCADE | Owned settings (users are soft-deleted; erasure removes settings) |
| user_account → notification_preference | 1 : N | CASCADE | Owned settings, unique per type and channel |
| candidate_profile → job_alert | 1 : N | CASCADE | Owned saved searches |
| user_account → notification | 1 : N | RESTRICT | Notifications are history (in-app list, audit) |
| job_alert → notification | 0..1 : N | SET NULL | A deleted alert keeps the notifications it sent |
| notification → notification_delivery | 1 : N | RESTRICT | One delivery per channel attempt; delivery history kept |
| community_post → community_post (reply) | 0..1 : N | RESTRICT | Thread structure; posts are soft-deleted |
| community_post / user → community_reaction | 1 : N | CASCADE | A reaction has no meaning without its post or reactor; unique per user and post |
| support_ticket → support_ticket_message | 1 : N | RESTRICT | Conversation is append-only history |
| ui_label_key → faq | 1 : 0..1 (question), 1 : N (answer) | RESTRICT | Platform text by key |
| referral → referral_event | 1 : N | RESTRICT | Append-only history |
| user_account → user_credential / consent_record | 1 : N | RESTRICT | Revoked credentials and withdrawn consents are evidence |
| user_account → user_session / audit_event | 1 : N | RESTRICT | Reused shared items |
| user_account → block_entry (blocker) | 1 : N | RESTRICT | Block history |
| user_account / organisation → block_entry (blocked) | 0..1 : N | RESTRICT | Exactly one target per entry (CHECK) |

### Star schema (fact → dimension, aggregate → fact)

```mermaid
erDiagram
    dim_date ||--o{ fact_application : "applied / stage dates"
    dim_job_requirement ||--o{ fact_application : ""
    dim_candidate ||--o{ fact_application : ""
    dim_organisation ||--o{ fact_application : ""
    dim_organisation ||--o{ dim_job_requirement : ""
    dim_location |o--o{ dim_job_requirement : ""
    dim_location |o--o{ dim_organisation : "HQ"
    dim_location |o--o{ dim_candidate : ""
    dim_date ||--o{ dim_candidate : "registered"
    dim_job_requirement ||--o{ fact_job_posting : ""
    dim_job_requirement ||--o{ fact_sourcing_request : ""
    dim_candidate ||--o{ fact_profile_engagement : ""
    dim_candidate ||--o{ fact_outreach : ""
    dim_organisation ||--o{ fact_payment : ""
    dim_organisation ||--o{ fact_wallet_transaction : ""
    dim_organisation |o--o{ fact_gig_assignment : ""
    dim_organisation |o--o{ fact_login_daily : ""
    dim_organisation |o--o{ fact_support_ticket : ""
    dim_date ||--o{ fact_notification_daily : ""
```

Aggregates and the facts they read (materialised-view dependencies, asserted by m16):

| Aggregate | Reads |
|---|---|
| `agg_hiring_funnel_monthly` | `fact_application`, `dim_organisation`, `dim_date` |
| `agg_job_posting_monthly` | `fact_job_posting`, `dim_organisation`, `dim_date` |
| `agg_sourcing_monthly` | `fact_profile_engagement`, `fact_outreach`, `dim_organisation`, `dim_date` |
| `agg_revenue_monthly` | `fact_payment`, `dim_organisation`, `dim_date` |

**Star-schema rules, checked automatically in m16** (not just for the listed sample of FKs):
- Every `*_date_id` column of a `dim_` / `fact_` table is an enforced FK to `dim_date`, and every `dim_<x>_id` column an FK to `dim_<x>`. There are 38 fact → dimension FKs.
- Analytical tables reference only analytical tables, `currency` and the audit actor (D19).
- Each aggregate is derived from its facts.
- Facts point at a specific dimension **version** (SCD 2 surrogate), so a report shows the organisation as it was when the event happened.

---

## Milestone 17 — Columns (B54–B56)

Full column list with type, nullability, class, FK and null justification: **[`docs/phase4-data-dictionary.md`](phase4-data-dictionary.md)** (32 tables, generated from the catalog).

The same column rules as Phases 2 and 3 run for Phase 4 through the shared `check_columns.sql`. Every data column states its class (374 columns checked), every date range has a CHECK, and the email, phone, money and free-text domains are checked schema-wide. Phase 4 adds:

| Rule | Implementation (checked in `m17_columns.sql`) |
|---|---|
| **Credentials are Sensitive** (B56) | `user_credential.password_hash` (argon2id encoded string: algorithm, cost, salt and hash, never the password) and `provider_subject_hmac` (HMAC-SHA256 of the social provider's subject id) are `class=Sensitive`. Schema-wide, no column that looks like a secret (`password`, `secret`, `otp`, `pin_code`, `api_key`) exists except as `_hash` / `_hmac` |
| Analytical layer holds no personal data (D19) | No `dim_` / `fact_` / `agg_` column is Personal or Sensitive, and none is named like an identifier (email, phone, name, address, birth) |
| Consent evidence | `consent_record` states purpose, policy version, grant or withdrawal and time (all NOT NULL); IP and user agent as Personal evidence |
| Messaging boundary | `notification.summary` is `varchar(300)`: enough for the in-app list and audit, never a message body |
| Multilingual user text (rule group 7) | `community_post.body_language_id` records the language where known; FAQ text is UI label keys |
| Date ranges | Detection extended to `unblocked_at`, `resolved_at`, `closed_at`, `read_at` |

**Sensitive data in Phase 4:** the two credential columns. **Personal data:** time zone, job-alert criteria (city, salary floor), notification summaries, support ticket subjects and messages, block entries (who blocks whom is itself personal), consent evidence (IP, user agent).

---

## Milestone 18 — Keys and constraints (B57–B59)

### B57 Notifications: the high-volume write path for deliveries

| Rule | Mechanism |
|---|---|
| Insert once, update rarely | One `notification_delivery` row per channel attempt, written at enqueue; provider callbacks update status in place |
| Preferences honoured on the write path | `trg_notification_delivery_rules`: a channel the recipient switched off for that type is stored as `suppressed` at enqueue (never sent, decision visible). Uses the unique `(user, type, channel)` preference index |
| **Idempotent callbacks without a lookup table** | Status only moves forward: queued < sent < delivered < read, failed only before delivery, and read / failed / suppressed are final. A replayed or late callback is a no-op, and the first reported time of each step wins. Deliveries start as `queued` |
| Cheap updates at volume | Callback-updated columns are not indexed and every partition has `fillfactor = 70`, so callback updates are HOT updates (no index writes). `create_monthly_partitions` copies the storage options to partitions added later |
| Cheap retention | Monthly partitions by `queued_at`; expired months are dropped whole, never deleted row by row |

### B58 Analytics: slowly changing dimension keys and aggregate refresh rules

| Rule | Mechanism |
|---|---|
| SCD 2 versions never overlap | `uq_dim_organisation_no_overlap` / `uq_dim_candidate_no_overlap`: `EXCLUDE USING gist (source id =, tstzrange(valid_from, valid_to) &&)` |
| Exactly the open version is current | `CHECK (is_current = (valid_to IS NULL))` + partial unique current version per source id (also the load-time lookup path) |
| Facts attach the version valid at the event | `dim_organisation_version(id, at)` / `dim_candidate_version(id, at)` |
| Type 2 load step | `dim_organisation_apply(...)`: a change of a tracked attribute (type, industry, size band, verification, HQ) closes the current version at `p_at` and opens a new one; the display name is type 1 (corrected in place) |
| SCD 1 dimensions | One row per source id: unique `city_id`, `job_requirement_id` |
| **Aggregate refresh rule** | After every fact load the job calls `refresh_aggregates()`: every `agg_` view is refreshed `CONCURRENTLY` (readers keep the previous contents; uses the unique index each aggregate has), and each refresh is written to the append-only `agg_refresh_log`. Dashboards show the last `finished_at` as "data as of" |

### B59 Shared items

| Rule | Mechanism |
|---|---|
| **Append-only audit trail, for every role and every partition** | `audit_event` was already append-only through a trigger and revoked privileges (M10). M18 closes a gap: a `TRUNCATE` trigger on a partitioned table does not fire for a `TRUNCATE` of one partition. `protect_partitions()` now gives every partition of every append-only table its own trigger, and `make_append_only` / `create_monthly_partitions` apply it to partitions created later. The same applies to the Phase 1 history tables, login attempts, downloads and the error log |
| Consent is history | `consent_record` append-only: a withdrawal is a new row |
| **Unique constraint on credentials** | One live credential per user and type (`uq_user_credential_user_account_id_credential_type_id`); one social identity linked to one user (`uq_user_credential_credential_type_id_provider_subject_hmac`) |
| A password is never stored in clear | CHECK: `password_hash` must be an argon2id encoded string; the subject HMAC must be 32 bytes |
| No in-place secret edits | Trigger: rotation is revoke + new row; a revoked credential stays revoked |
| Blocks belong to the blocker | `CHECK (blocker = created_by)`; one live block per blocker and target; an unblock is final (blocking again is a new entry) |
| **A blocked party cannot see the blocker's candidate** (docket §3) | Row-level security for `talentra_app` on `candidate_profile` and its content tables (email, phone, address, social links, education, work, skills, languages, certifications, preferences, resumes and resume versions). `app_can_see_candidate()` lets through the owner, platform admins, and otherwise only non-hidden profiles, with employers-only profiles limited to organisation members and consultants. It always excludes a user the candidate blocked and every current member of an organisation the candidate blocked. `block_entry` is readable only by the blocker, so the block itself stays private. **Measured after M20:** calling `app_can_see_candidate()` per row timed out a name search over 1M profiles, so `candidate_profile` now states the same rule inline. Two definer-rights helpers, `app_viewer_sees_employers_only()` and `app_candidates_blocking_viewer()`, run once per query, leaving a few comparisons per row; the content tables keep the function, since they are read by profile id |
| **Row-level security applies through views** | Every `v_` view is now `security_invoker`. Before M18 the views ran with their owner's rights: a recruiter could read another company's draft requirements through `v_job_requirement`. That was a Phase 2 hole, found while designing the candidate rule. m18 asserts `security_invoker` for every view, so a new view cannot reopen it |

**Scope note — existing applications.** A candidate who blocks an employer they have already applied to stays in that employer's application pipeline (the candidate applied; the employer must be able to close the application). The profile, contact details and resumes are hidden. Withdrawing the application is the candidate's way out.

### Validation evidence (B57–B59)
`m18_constraints.sql` runs 48 checks in one rolled-back transaction; the visibility part runs as `talentra_app`. Mutation-tested, one at a time, with each breakage making the matching check fail:
- removing the Sensitive class from `password_hash` (m17);
- disabling RLS on `candidate_profile`;
- turning `security_invoker` off on `v_job_requirement`;
- dropping one audit partition's `TRUNCATE` trigger;
- dropping the delivery trigger.

### Deviation register (Phase 4)

| Rule | Deviation | Reason | Risk / mitigation |
|---|---|---|---|
| 2 — surrogate key | `dim_date.id` is the yyyymmdd smart key | Standard for date dimensions; readable partition and filter keys | CHECK ties it to `calendar_date` |
| 2 — FK for every relationship | Facts keep source ids as degenerate keys without FKs (D19) | Marts can load from a replica; erasure never blocks reporting | Load job validates them (M20) |
| 3 — no free-text enumerations | Dimensions hold lookup **codes** copied at load | Reports need no join back to the transactional side | Codes come from lookups, not user input |
| 2 — unique constraints | No unique "one delivery per notification and channel": retries are new rows | Each attempt has its own provider status | Status trigger keeps each row consistent |
| 2 — CHECK with lookup values | Delivery, credential and ticket rules use SYSTEM lookup ids (marked `SYSTEM:` in the lookup comment) | A CHECK cannot look up a code | Ids < 1000 reserved; system codes immutable |
| 1 — PK named `id` | `notification_delivery`, `system_error_event` PK `(id, time)` | Partition key must be in the PK | Same as earlier history tables |
| Performance | Candidate visibility is a function call per row | Correctness first; one place to change | `ponytail:` comment; measured in M21 at 1M profiles |

### Rule compliance (Phase 4 scope)

| Rule group | Complies | Notes |
|---|---|---|
| 1 Naming | Yes | Automated (m4) |
| 2 Keys and constraints | Yes, with deviations above | Exclusion constraints for SCD 2, partial uniques for credentials and blocks |
| 3 Standard domains | Yes | Automated (m17) |
| 4 Audit and lifecycle | Yes | Audit trail append-only per partition; consent, ticket messages, referral events, error log, refresh log append-only; credentials and blocks audited |
| 5 Nullability | Yes | Automated (m4) |
| 6 Classification | Yes | Credentials Sensitive as hashes; no personal data in the marts |
| 7 Multilingual | Yes | FAQ by label key; community text records its language |
| 8 Physical naming | Yes | `dim_` / `fact_` / `agg_` prefixes (m15), `<table>_pYYYYMM` partitions, `v_` views |
| 9 Licensing | N/A | Phase 3 |
| 10 Money / history | Yes | Marts mirror the append-only ledger (`fact_wallet_transaction` append-only) |

---

## Verification

```sh
MSYS_NO_PATHCONV=1 ./run_phase1.sh m15
MSYS_NO_PATHCONV=1 ./run_phase1.sh m16
MSYS_NO_PATHCONV=1 ./run_phase1.sh m17
MSYS_NO_PATHCONV=1 ./run_phase1.sh m18
```

m15 expected output:
- `analytics : 16`, `notifications : 11`, `shared : 4` entities present;
- all 16 docket entries mapped to an entity;
- prefix rule, 4 aggregates reading only facts and dimensions, 13 KPIs covered, no message bodies.

m16 expected output: `PASS 40 documented relationships …`, `894 foreign keys` explicit, the dimension-key rule (38 fact → dimension FKs), the D19 isolation rule, and aggregate → fact lineage.

Mutation-tested:
- An aggregate reading `job_requirement` makes m15 fail.
- Dropping a listed fact → `dim_date` FK makes m16 fail (listed-relationship check).
- Dropping an unlisted one (`fact_outreach.sent_date_id`) also makes m16 fail (general dimension-key rule).
- Adding an FK from `fact_payment` to `payment_order` makes m16 fail (D19).

**Review checklist**
- [ ] Missing Section 8 raised with the organisers; derived KPI set accepted.
- [ ] D19 (marts in the same database, degenerate keys), D20 (one preference row; shared channel list), D21 (reuse of sessions and audit trail), D22 (only deliveries partitioned) agreed.
- [ ] `block_entry` vs the gig worker blacklist split accepted.
- [ ] Existing-application scope note for blocks accepted.
- [ ] Phase 4 deviation register accepted.
