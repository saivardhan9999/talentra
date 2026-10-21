# 05 — Logical model

Level 2: **what data each entity holds.** Every conceptual entity becomes a relation with attributes, logical domains, keys and nullability, still free of PostgreSQL specifics. Full attribute lists are generated from the database in [logical-erd.md](logical-erd.md) (diagrams per subject area) and [data-dictionary.md](data-dictionary.md) (every column, class and NULL reason). This page records the **decisions** that produced them.

## 1. From entities to relations

| Conceptual | Logical relation(s) | Note |
|---|---|---|
| User, Role grant | `app_user`, `user_access_role`, `access_role` (lookup), `access_permission` (lookup), `access_role_permission` | many-to-many role ↔ permission resolved |
| Credential | `user_credential` (1 : 0..1 with app_user) | split off so the runtime role can be denied the whole relation |
| Consent | `consent_record` (event history) + `consent_current` (derived view) | current state derived, never stored twice |
| Device / Session | `user_device`, `user_session` | session → device by a composite key (device of the same user) |
| Candidate | `candidate_profile` (1 : 0..1 with app_user) | subtype of user by role; contact details stay on app_user |
| Profile sections | `candidate_education`, `candidate_experience`, `candidate_skill`, `candidate_language`, `resume` | skill and language: many-to-many resolved with attributes (proficiency) |
| Block | `candidate_block` | exactly one target: organisation **or** user (exclusive arc, checked) |
| Organisation, Office, Tax id, Membership | `organisation` (self-reference), `organisation_location`, `organisation_tax_identifier`, `organisation_member` | membership is effective-dated |
| Job requirement | `job_requirement`, `job_requirement_location`, `job_requirement_skill`, `screening_question` | two many-to-many resolved |
| Application, Answer, Status change | `application`, `application_answer`, `application_status_history`, `application_status_transition` | allowed moves are data, not code |
| Plan, Subscription, Wallet, Ledger, Payments, Invoice, Download | `plan`, `subscription`, `wallet`, `wallet_ledger_entry`, `payment_order`, `payment_event`, `invoice`, `profile_download` | ledger reversal is a self-reference |
| Notification, Preference, Job alert | `notification`, `notification_preference`, `job_alert` | |
| Audit event | `audit_event`, `system_error` | |
| every enumeration | one lookup relation each (25), sharing one shape | ADR-003 |

## 2. Logical domains

Every attribute takes one of these domains (docket rule group 3). The physical column is a PostgreSQL `DOMAIN` of the same name, so the rule is written once ([06 §2](06-physical-model.md#2-logical-to-physical-mapping)).

| Logical domain | Rule | Used for |
|---|---|---|
| Identifier | 64-bit surrogate (16-bit for lookups and small reference data), never reused | every `id` and `*_id` |
| Person name | 1–150 characters, any script, trimmed, no word-order assumption | `full_name` |
| Short text / Medium text / Long text | 1–200 / 1–2,000 / 1–20,000 characters | titles, summaries, job descriptions (only long text is "unbounded", ADR-008) |
| Email | ≤ 254 characters, lower case, one `@` | `app_user.email` |
| Phone | E.164 with country code, plus the country as a separate attribute | `phone_e164` + `phone_country_id` |
| Money | fixed point, 2 decimals, ≥ 0, always with a currency attribute | prices, salaries, amounts |
| Credits | whole number, signed in the ledger | wallet and ledger |
| Percentage | 0–100, 2 decimals | (reserved for analytics) |
| Date / Timestamp | calendar date; instant in UTC (the user's time zone is an attribute of the user) | |
| Date range | start and end with end ≥ start (or end > start for periods) | education, work, subscriptions, memberships |
| Coordinates | latitude ±90, longitude ±180, 6 decimals, WGS 84 | city, office |
| Code | `[a-z][a-z0-9_]*`, the stable key of an enumeration value | lookup `code` |
| Digest | exactly 32 bytes (SHA-256 / HMAC-SHA256) | token, device, tax-id and payload hashes |
| Flag | true / false, never unknown, with a default | `is_*` |

## 3. Keys

- **Primary keys:** surrogate `id` everywhere (ADR-002).
- **Natural and alternate keys are unique constraints**, never primary keys: email; (country, type, identifier hash); gateway order and event ids; idempotency keys; invoice number; resume storage key; (candidate, job) for applications; (wallet entry) for downloads.
- **Composite alternate keys exist to be referenced**, which proves cross-row consistency:
  - `resume (id, candidate_profile_id)` → an application can only attach the applicant's own resume
  - `screening_question (id, job_requirement_id)` and `application (id, job_requirement_id)` → an answer can only be to a question of the job applied for
  - `job_requirement (id, organisation_id)` → `application.organisation_id` always equals its job's organisation
  - `user_device (id, app_user_id)` → a session's device belongs to the session's user

## 4. Nullability and "unknown" versus "not applicable"

Every nullable attribute states why in the dictionary (rule group 5, enforced by test t01). Where unknown and not-applicable differ, the model stores the difference:

| Case | Model |
|---|---|
| Expected salary | `salary_disclosure` = disclosed / not disclosed / not provided; amount and currency present exactly when disclosed (checked) |
| Job salary | disclosed (minimum required, maximum optional = no upper figure) / not disclosed |
| End dates | NULL means "still ongoing" (current job, still studying, current membership); never a far-future sentinel |
| Notice period | 0 = available now; NULL = not asked yet |
| Email | NULL only for erased users (checked against the status) |
| Phone country | present exactly when the phone is present |
| Sentinels | none: no 0, "NA", empty string or 9999-12-31 to mean missing (domains reject empty strings) |

## 5. Normalisation

The relations are in **third normal form**: every non-key attribute depends on the key, the whole key, and nothing but the key. Repeating groups (skills, locations, questions, roles) are separate relations, and lookups replace repeated text.

**Deliberate denormalisations**, each with what keeps it consistent:

| Redundancy | Why | Kept consistent by |
|---|---|---|
| `wallet.balance_credits` (= sum of ledger) | balance checks on every debit must not scan the ledger | written only by `wallet_post()` in the same transaction as the entry; t05 R-01..R-03 |
| `application.organisation_id` (= the job's organisation) | RLS and the employer pipeline filter without a join (ADR-011) | composite FK to `job_requirement (id, organisation_id)`; filled by trigger |
| `application_answer.job_requirement_id` | lets the two composite keys prove the question belongs to the job | the composite FKs themselves |
| `subscription.max_seats`, `max_devices_per_user` (copied from the plan) | a sold licence must not change when the plan is repriced; this is history, not redundancy | update guard trigger: only cancellation fields change |
| `job_requirement.positions_filled` (= count of joins) | the limit check must be one row update under a lock | maintained by the pipeline trigger; t05 R-07 |
| `search_vector` columns | full-text search | generated columns (cannot drift) |
| `agg_hiring_funnel_monthly` | dashboard speed | materialized view, refreshed by `refresh_aggregates()` |

## 6. Modelling patterns used

- **Subtype by role:** a user is a candidate (profile 1 : 0..1), an organisation member (effective-dated membership) or staff (role only). There are no duplicated person tables: login, contact and consent are modelled once.
- **Effective dating:** `organisation_member (valid_from, valid_to)` with "no overlap per user". The current row is the one with `valid_to` NULL.
- **Event history:** `application_status_history`, `consent_record`, `payment_event` and `audit_event` record facts, never change, and the current state is derived or cached.
- **Ledger with reversals:** a correction is a new entry pointing at the one it reverses (each entry can be reversed once).
- **State machine as data:** `application_status_transition` lists the allowed moves; a trigger refuses the rest.
- **Exclusive arc:** `candidate_block` points to an organisation or a user, never both (a check on the count of non-null targets).
- **Outbox:** `notification` rows are written with the business change and delivered asynchronously (ADR-010).
