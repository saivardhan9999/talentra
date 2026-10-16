# Talentra — Phase 3 Design (Individual modules)

**Scope:** Milestones 11–14, backlogs B36–B47 (Phase 3 complete). Modules: **Licences, seats, devices and sessions** (Member A), **Sourcing and consultant requests** (Member B), **Subscriptions, wallet, payments and download history** (Member C).
**Status:** M11–M14 built and verified on PostgreSQL 16 (`./run_phase1.sh m11` … `m14`).

| File | Contents |
|---|---|
| `sql/09_subscriptions.sql` | Plans, entitlements, subscriptions and periods, payment orders and events, invoices, refunds, wallet and ledger, profile download history |
| `sql/10_licences.sql` | Licences, seats, devices, sessions, login attempts, revocation events |
| `sql/11_sourcing.sql` | Sourcing requests, outreach batches and recipients; consultant shortlist link on `talent_list` |
| `sql/tests/m11_entities.sql`, `m12_relationships.sql`, `m13_columns.sql` | Milestone checks (m13 shares `check_columns.sql` with m9) |
| `docs/phase3-data-dictionary.md` | Generated column list |

Build order follows dependencies, not the docket's module order: Subscriptions (09) before Licences (10), because a licence is granted by a subscription. Sourcing (11) goes last because outreach references the wallet ledger.

Like Phase 2, the tables are created with their columns and foreign keys so the schema-wide M4/M9 column rules keep passing. The M14 rules are triggers, exclusion constraints and CHECKs added in the same files.

---

## Milestone 11 — Entities (B36–B38)

### B36 Licences, seats, devices and sessions (Member A)
| Entity | Purpose |
|---|---|
| `licence` | Granted by one subscription; `max_users` and `max_devices_per_user` stored as explicit positive columns (rule group 9), copied from the plan at purchase |
| `licence_seat` | Seat allocation: user ↔ licence, `assigned_at` / `released_at` (one live seat per user per licence) |
| `user_device` | Registered devices per user; fingerprint stored only as an HMAC; `revoked_at` |
| `user_session` | One row per login, bound to a device and (for licensed users) a seat; start, last activity, expiry, end + reason. Ended sessions do not count against the limit; the session token is stored as a hash |
| `login_attempt` | Login history incl. refused attempts (`device_limit_reached`, `seat_unavailable` …); append-only, monthly partitions |
| `session_revocation_event` | Revoking a session or a device is an auditable event (rule group 9); append-only |

**Decision D15 — one session table.** The docket lists "sessions (identity only)" under Administration and the Phase 4 shared items (B50), and "active sessions" here. One login produces one session, so there is one `user_session` table. Users who need no licence (candidates, gig workers) have `licence_seat_id` NULL and no device limit (the limit is per licence); revocation and login history still apply. B50 reuses this table.

### B37 Sourcing and consultant requests (Member B)
| Entity | Purpose |
|---|---|
| `sourcing_request` | A consultant asks to source for a requirement; status, the employer's accept/decline decision (who, when, note), proposed fee |
| `outreach_batch` | Bulk outreach by an employer, recruiter or consultant: channel, provider template reference, schedule, optional requirement / sourcing request, credit charge |
| `outreach_recipient` | One row per candidate in a batch: delivery status and times reported by the messaging provider (idempotent by provider message id) |
| *Consultant openness* | Already modelled in Phase 1: `job_requirement.is_open_to_consultants` + `consultant_fee_pct` |
| *Candidate sourcing shortlist* | `talent_list.sourcing_request_id`: the consultant's shortlist is a Jobs and Applications talent list scoped to the request (as the docket requires) |

**Decision D16 — the decision lives on the request.** The docket names "acceptance or decline decisions" as an entity. Each request gets exactly one decision, and status changes are audited, so the decision is `decided_at`, `decided_by_user_account_id` and `decision_note` on `sourcing_request`. A separate table would be 1 : 0..1 with nothing else in it.

### B38 Subscriptions, wallet, payments and download history (Member C)
| Entity | Purpose |
|---|---|
| `plan` | Sellable plan: billing period, price, licence limits |
| `plan_entitlement` | Quantity per period of each entitlement (job postings, profile downloads, outreach messages, featured jobs); NULL = unlimited |
| `subscription` | An account's purchase of a plan: status, auto-renew, cancellation (time, reason) |
| `subscription_period` | First term and every renewal (`renewal_number`), with the paying order; periods never overlap (M14) |
| `payment_order` | What the platform asked the gateway to collect: purpose (subscription / wallet recharge), amount, status, gateway order reference (idempotency) |
| `payment_event` | Gateway callbacks as received: status history, idempotent by gateway event id; append-only |
| `invoice` | One per paid order; immutable (append-only), total = subtotal + tax |
| `refund` | Refund against an order: amount, status, gateway refund reference |
| `wallet` | One credit wallet per account; balance cached from the ledger |
| `wallet_ledger_entry` | Append-only credit ledger: recharges, consumption, refunds, reversals; a correction references the entry it reverses (rule group 10) |
| `profile_download_event` | Who downloaded which profile, when, and the ledger entry charged; append-only, monthly partitions |
| *Profile view credit* | `profile_view_event.wallet_ledger_entry_id` (Phase 1 hand-off) |

**Decision D17 — ledger in credits, payments in money.** Money changes hands only on `payment_order`, `invoice` and `refund` (`numeric(14,2)` + currency). The wallet holds **credits** (integers), which recharges buy and downloads, views and outreach consume. Rounding never touches money that has already been paid, and a credit price change never rewrites history.

### Validation (§4 coverage for these modules)
| Section 4 item | Entity |
|---|---|
| Subscription licences, users allowed per licence, devices allowed per user, seat allocation | `licence`, `licence_seat` |
| Registered devices, active sessions, login history, device-limit rule | `user_device`, `user_session`, `login_attempt` (rule enforced in M14 under concurrency) |
| Revocation | `session_revocation_event`, `user_device.revoked_at`, `user_session.ended_at` |
| Sourcing requests, acceptance or decline, candidate shortlists | `sourcing_request`, `talent_list.sourcing_request_id` |
| Bulk outreach (§2 workflow) | `outreach_batch`, `outreach_recipient` |
| Plans, periods, renewals, cancellations, entitlements | `plan`, `plan_entitlement`, `subscription`, `subscription_period` |
| Payment orders, payment status, invoices, refunds | `payment_order`, `payment_event`, `invoice`, `refund` |
| Wallet balances, recharges, credit consumption, wallet ledger entries | `wallet`, `wallet_ledger_entry` |
| Profile download history (who, which profile, when, under which credit deduction) | `profile_download_event` |

16 new lookup tables (Master data): `billing_period`, `entitlement_type`, `subscription_status`, `payment_purpose`, `payment_order_status`, `refund_status`, `wallet_entry_type`, `licence_status`, `device_platform`, `session_end_reason`, `login_outcome`, `revocation_reason`, `sourcing_request_status`, `outreach_channel`, `outreach_batch_status`, `outreach_recipient_status`.

### Integration boundaries touched (docket §6)
| Boundary | Stored | Idempotency |
|---|---|---|
| Payment gateway | order and transaction references, status, amounts. **No card or bank data** (asserted by m11) | `gateway_order_ref`, `gateway_event_ref`, `gateway_refund_ref` unique |
| Messaging providers | template reference and delivery status per recipient; message bodies stay with the provider | `provider_message_ref` unique |

---

## Milestone 12 — Relationships (B39–B41)

```mermaid
erDiagram
    organisation ||--o{ subscription : buys
    plan ||--o{ subscription : "sold as"
    plan ||--o{ plan_entitlement : includes
    subscription ||--o{ subscription_period : "first term + renewals"
    payment_order |o--o| subscription_period : "pays for"
    subscription ||--o| licence : grants
    licence ||--o{ licence_seat : seats
    user_account ||--o{ licence_seat : holds
    user_account ||--o{ user_device : registers
    user_device ||--o{ user_session : runs
    licence_seat |o--o{ user_session : "counted against"
    user_device |o--o{ login_attempt : "attempted from"
    user_session |o--o{ session_revocation_event : "revoked by"
    user_device |o--o{ session_revocation_event : "revoked by"
    organisation ||--o{ payment_order : places
    payment_order ||--o{ payment_event : "gateway callbacks"
    payment_order ||--o| invoice : "invoiced as"
    payment_order ||--o{ refund : "refunded by"
    organisation ||--o| wallet : owns
    wallet ||--o{ wallet_ledger_entry : records
    payment_order |o--o| wallet_ledger_entry : "recharge credited"
    refund |o--o| wallet_ledger_entry : "refund debited"
    wallet_ledger_entry |o--o| wallet_ledger_entry : reverses
    wallet_ledger_entry |o--o{ profile_download_event : charged
    wallet_ledger_entry |o--o{ profile_view_event : charged
    candidate_profile ||--o{ profile_download_event : downloaded
    job_requirement ||--o{ sourcing_request : "sourced for"
    user_account ||--o{ sourcing_request : "consultant asks"
    sourcing_request |o--o{ talent_list : shortlist
    sourcing_request |o--o{ outreach_batch : "outreach under"
    wallet_ledger_entry |o--o| outreach_batch : charged
    outreach_batch ||--o{ outreach_recipient : "sent to"
    candidate_profile ||--o{ outreach_recipient : receives
```

**Cardinality and delete rules.** Every FK is `ON UPDATE RESTRICT`. As in Phases 1–2, lookup → referencing table is 1 : N RESTRICT.

| Relationship | Card. | ON DELETE | Reason |
|---|---|---|---|
| plan → plan_entitlement | 1 : N | CASCADE | Owned detail of the plan |
| organisation / plan → subscription | 1 : N | RESTRICT | Subscriptions are billing history |
| subscription → subscription_period | 1 : N | RESTRICT | Unique `(subscription_id, renewal_number)` |
| payment_order → subscription_period | 1 : 0..1 | RESTRICT | An order pays for at most one period (partial unique) |
| subscription → licence | 1 : 0..1 | RESTRICT | **Composite FK `(subscription_id, organisation_id)`**: the licence belongs to the subscriber |
| licence → licence_seat → user_account | 1 : N | RESTRICT | Seats are released, never deleted |
| user_account → user_device | 1 : N | RESTRICT | Devices are revoked, never deleted |
| user_device → user_session | 1 : N | RESTRICT | **Composite FK `(user_device_id, user_account_id)`**: a session runs on a device of its own user |
| licence_seat → user_session | 0..1 : N | RESTRICT | **Composite FK `(licence_seat_id, user_account_id)`**: a session uses its own user's seat |
| user_device → login_attempt | 0..1 : N | RESTRICT | Composite FK as for sessions; a device implies an account (CHECK) |
| user_session / user_device → session_revocation_event | 0..1 : N | RESTRICT | At least one target (CHECK). With both set, composite FK `(user_session_id, user_device_id)`: the session was on that device |
| organisation → payment_order | 1 : N | RESTRICT | Payment history |
| payment_order → payment_event / refund | 1 : N | RESTRICT | Append-only gateway history; refunds against the order |
| payment_order → invoice | 1 : 0..1 | RESTRICT | One invoice per paid order |
| organisation → wallet | 1 : 0..1 | RESTRICT | One wallet per account |
| wallet → wallet_ledger_entry | 1 : N | RESTRICT | Append-only ledger |
| payment_order / refund → wallet_ledger_entry | 1 : 0..1 | RESTRICT | A recharge is credited once, a refund debited once (partial unique) |
| wallet_ledger_entry → wallet_ledger_entry (reverses) | 1 : 0..1 | RESTRICT | An entry is corrected at most once |
| wallet_ledger_entry → outreach_batch | 1 : 0..1 | RESTRICT | A batch is charged once |
| wallet_ledger_entry → profile_download_event / profile_view_event | 1 : N (intended 1 : 0..1) | RESTRICT | See the deviation below |
| candidate_profile / user_account → profile_download_event | 1 : N | RESTRICT | Append-only history (actor, subject) |
| job_requirement / consultant → sourcing_request | 1 : N | RESTRICT | Requests are history |
| sourcing_request → talent_list | 0..1 : N | RESTRICT | The consultant's shortlist |
| sourcing_request → outreach_batch | 0..1 : N | RESTRICT | **Composite FK `(sourcing_request_id, job_requirement_id)`**: outreach under a request targets the request's requirement. CHECK: a request implies a requirement |
| outreach_batch → outreach_recipient → candidate_profile | 1 : N | RESTRICT | Unique `(batch, candidate)` |

**Decision D18 — composite FKs pin ownership.** Some rows name both a parent and an owner: session → device + user, licence → subscription + organisation, outreach → request + requirement. In each case the pair is one composite FK to a `UNIQUE (id, owner)` key on the parent. It is the same technique as `placement` (D8) and `gig_assignment` (D14). "A user cannot log in on someone else's device" becomes a constraint instead of an application rule.

PostgreSQL checks a composite FK only when every column is set (MATCH SIMPLE). Where one column can be NULL on its own, a CHECK closes the gap (`ck_login_attempt_device_needs_user`, `ck_outreach_batch_sourcing_request`), or a single-column FK keeps the lone column checked (`session_revocation_event.user_session_id`).

**Deviation — credit link on partitioned history.** `profile_download_event` and `profile_view_event` are partitioned. PostgreSQL requires a unique index on a partitioned table to include the partition key, so "one ledger entry pays for one download" cannot be a unique constraint. M14 enforces it with a trigger and a row lock on the ledger entry instead (see B47).

## Milestone 13 — Columns (B42–B44)

Full column list with type, nullability, class, FK and null justification: **[`docs/phase3-data-dictionary.md`](phase3-data-dictionary.md)** (22 tables, generated from the catalog).

**Column added in this milestone.** `payment_order.credit_quantity`: a wallet recharge states how many credits it buys, fixed at order time. M14 can then check the ledger credit against what was paid for. CHECK: set and positive exactly for `wallet_recharge` orders.

**Domains applied (rule group 3), checked automatically in `m13_columns.sql`:**

| Domain | Phase 3 implementation |
|---|---|
| Money | `price_amount`, `order_amount`, `refund_amount`, `subtotal/tax/total_amount`: `numeric(14,2)` + currency FK; invoice total = subtotal + tax (CHECK) |
| Credits (D17) | `credit_balance`, `credit_delta`, `balance_after`, `credit_quantity`: `integer`; balance ≥ 0, delta ≠ 0 |
| Limits | `max_users`, `max_devices_per_user`: `integer NOT NULL CHECK > 0` (rule group 9) |
| Percentage | `proposed_fee_pct numeric(5,2)` CHECK 0–100, same as Phase 1 `consultant_fee_pct` |
| Integration reference | `gateway_*_ref`, `provider_message_ref`: `varchar(100)`, unique where it keys a callback |
| Free text | all bounded (`varchar(n)`) |
| Date range | seat, device, session, subscription, period, refund, sourcing decision, outreach delivery: each has a CHECK |
| IP address | `login_attempt.source_ip inet` (Personal) |

**Sensitive data (rule group 6).** Phase 3 adds three Sensitive columns, all keyed hashes: `user_device.device_fingerprint_hmac`, `user_session.session_token_hash` and `login_attempt.attempted_identifier_hmac`. A stolen copy of the database therefore holds no usable session token, no device fingerprint and no list of the login names people typed. Payment data stops at gateway references; m11 asserts there are no card or bank columns.

**Personal data in Phase 3:** device label, login IP and user agent, session and login timing (they reveal when a person works), outreach delivery and response, and download history (who looked at whom).

**Column contents required by rule groups 9 and 10** (asserted by m13): sessions store device, start, last activity and end. Download and view history store actor, subject, timestamp and the credit deduction.

## Milestone 14 — Keys and constraints (B45–B47)

### B45 Licences: seat and device limits under concurrency (rule groups 2 and 9)

**Mechanism (the design statement rule group 2 asks for): row locks taken inside the database, not application checks.**

| Rule | Mechanism |
|---|---|
| Live seats ≤ `max_users` | `trg_licence_seat_rules`: `SELECT … FROM licence … FOR UPDATE`, then count live seats. Concurrent seat assignments on one licence queue behind the lock |
| Seat holders belong to the licensed organisation; seats only on an active licence | same trigger (live `organisation_member`, `licence_status` 1) |
| **Live sessions ≤ `max_devices_per_user`, enforced at login** | `trg_user_session_rules`: `SELECT … FROM licence_seat … FOR UPDATE`, then count live sessions on the seat. Two simultaneous logins by one user queue, and the second counts the first one's committed session |
| A licensed user cannot dodge the limit by leaving the seat out | the trigger fills `licence_seat_id` with the user's live seat |
| **How an active session is counted** | `ended_at IS NULL AND expires_at > now()`, served by `idx_user_session_user_account_id_live` |
| **How a session is released** | logout (`ended_at` + reason `logout`), revocation (`app_revoke_session`, `app_revoke_device`, seat release), or passing `expires_at`. An ended session cannot be reopened (trigger) |
| **Exceeding the limit is recorded in the audit trail** | Login goes through `app_open_session()`. At the limit it does not raise: it writes `login_attempt` (outcome `device_limit_reached`) and an `audit_event` (`login_failed`, detail: reason, active sessions, limit), then returns NULL. A raised error would roll the record back. The insert trigger stays as the backstop for any direct insert |
| Revoking a device or session is auditable | `session_revocation_event` (append-only; `created_by` = who revoked). Revoking a device ends its live sessions (trigger), and releasing a seat ends its sessions as `seat_released` revocations. `licence`, `licence_seat` and `user_device` changes also go to `audit_event` |
| A revoked device stays revoked | trigger; the same fingerprint can register again (partial unique on live devices) |

**Users without a licence** (candidates, gig workers) have no seat and therefore no device limit; D15 is corrected accordingly.

**Isolation level.** The locks make this correct at READ COMMITTED (the PostgreSQL default, used by the application) and at SERIALIZABLE. Under REPEATABLE READ the second login would count with its old snapshot; the seat row would then have to be updated, not just locked. This is marked `ponytail:` in `10_licences.sql`.

**Proof under real concurrency.** Part 2 of `m14_constraints.sql` opens two dblink connections against a licence with `max_devices_per_user = 1`:
1. Connection 1 logs in inside an open transaction.
2. Connection 2 logs the same user in on another device at the same time.
3. The test asserts that connection 2 is still blocked after one second, and that after connection 1 commits, connection 2 returns no session.
4. It ends with exactly one live session and one `device_limit_reached` attempt recorded.

With the `FOR UPDATE` removed, the test fails with "second concurrent login did not wait".

### B46 Sourcing: a consultant acts only on a requirement open to consultants

"Open to consultants" means `is_open_to_consultants`, status `open` and not deleted. `app_job_open_to_consultants()` reads it with definer rights, so the rule does not depend on what row-level security shows the actor.

| Rule | Mechanism |
|---|---|
| Only consultants request, only for themselves, only on open requirements | `trg_sourcing_request_rules` (live `consultant` role grant) + `ck_sourcing_request_self_requested` |
| One live request per consultant and requirement | partial unique on status `requested`/`accepted` |
| Only the requirement's employer accepts or declines; the decision is final | trigger checks `app_organisation_ids_with('job_requirement.manage')` (so recruiters and the consultant cannot) and records `decided_at` / `decided_by` itself. Transitions: requested → accepted / declined / withdrawn / expired; accepted → withdrawn |
| **Acting** (shortlist, shortlist entries, outreach) needs an accepted request, by its consultant, on a requirement that is **still** open | `app_assert_sourcing_request_actor()` from triggers on `talent_list`, `talent_list_entry` and `outreach_batch`. Closing the requirement to consultants stops further work at once |
| Outreach for a requirement without a request comes from a current member of its organisation | `trg_outreach_batch_rules` |

### B47 Subscriptions, wallet, payments and download history

| Rule | Mechanism |
|---|---|
| **Subscription periods never overlap for the same licence** (rule group 10) | `uq_subscription_period_no_overlap EXCLUDE USING gist (subscription_id =, tstzrange(period_start_at, period_end_at) &&)`. A licence is 1 : 1 with its subscription (unique `licence.subscription_id`), so per subscription is per licence. Back-to-back terms are allowed (half-open ranges) |
| A paid period is paid by a paid subscription order of the subscriber | trigger |
| **Ledger is append-only; a correction is a new entry referencing the original** | append-only trigger + privileges (M10). A reversal must negate exactly one non-reversal entry of the same wallet, at most once (unique `reverses_…`) |
| Balance moves only through the ledger and never goes negative | the ledger trigger locks the wallet row (`FOR UPDATE`), computes `balance_after` and updates the cached balance. A wallet starts at 0, and a direct balance edit is rejected (`pg_trigger_depth()` guard). Concurrent debits queue, so no overdraft |
| Entry type fixes sign and reference | CHECKs: recharge > 0 with a payment order; consumption, refund and expiry < 0; refund ⇔ `refund_id`; reversal ⇔ `reverses_…` |
| A recharge credits exactly what was bought | trigger: paid wallet-recharge order of the wallet's organisation, `credit_delta = credit_quantity` (M13 column), at most once (unique) |
| Refunds never exceed the payment | `trg_refund_rules` locks the order row and sums non-failed refunds; paid orders only; same currency |
| Invoices bill a paid order exactly | trigger: total and currency equal the order's |
| Download/view history carries the credit deduction, **one deduction per charge** | `trg_credit_charge_rules` on downloads, views and outreach: the entry must be a consumption from the acting organisation's wallet and not already used. A row lock on the ledger entry (`SELECT … FOR UPDATE`, taken with definer rights because the application role may not update ledger rows) serialises two charges of the same entry. The first design used an advisory lock per charge; full-scale seeding (M19) showed it takes a shared lock-table slot per row until commit and runs out of shared memory on bulk loads, so it was replaced. This resolves the M12 deviation without a unique index on the partitioned tables |

**Bug found by the M14 tests.** The M13 CHECK on `payment_order.credit_quantity` let a wallet recharge with no quantity through. The expression evaluated to NULL, and a NULL CHECK result counts as a pass. It is now written to evaluate to false in that case: `(purpose = 2) = (credit_quantity IS NOT NULL) AND credit_quantity > 0`.

### Validation evidence (B45–B47)
`m14_constraints.sql` runs 73 behavioural checks in one rolled-back transaction, plus the two-connection concurrency test (2 more; 75 PASS lines in total). Each `PASS rejected:` line names the constraint or trigger message that blocked the action. Mutation-tested: removing the seat `FOR UPDATE` locks fails the concurrency test; dropping `uq_subscription_period_no_overlap` fails the overlap test; making `app_job_open_to_consultants()` always true fails the consultant test.

### Deviation register (Phase 3)

| Rule | Deviation | Reason | Risk / mitigation |
|---|---|---|---|
| 2 — CHECK with lookup values | Ledger, order and sourcing rules use SYSTEM lookup ids (marked `SYSTEM:` in each lookup comment) | A CHECK cannot look up a code | Ids < 1000 reserved; system codes immutable (Phase 1 trigger) |
| 1 — PK named `id` | `login_attempt`, `profile_download_event` PK `(id, time)` | Partition key must be in the PK | Same as Phase 1 history tables |
| 2 — unique constraints | "One deduction per charge" on partitioned history is a trigger + row lock on the ledger entry, not a unique index | PostgreSQL unique indexes on partitioned tables must include the partition key | Trigger tested; lock serialises concurrent charges |
| 9 — device limit | Users without a licence have no device limit | The limit is defined per licence | Revocation and login history still apply to them |
| Concurrency | Seat and device locks assume READ COMMITTED or SERIALIZABLE | Updating the seat row on every login would also audit every login | `ponytail:` comment names the upgrade path |
| 10 — refunds | A refund's ledger debit is not tied to the refunded amount in credits | Credit price can change between recharge and refund (D17) | The debit references the refund; finance reconciles by the refund id |

### Rule compliance (Phase 3 scope)

| Rule group | Complies | Notes |
|---|---|---|
| 1 Naming | Yes | Automated (m4) |
| 2 Keys and constraints | Yes, with deviations above | Composite FKs (D18), exclusion constraint, row locks for limits; mechanism stated above |
| 3 Standard domains | Yes | Automated (m13) |
| 4 Audit and lifecycle | Yes | Ledger, payment events, invoices, login attempts, revocations and downloads are append-only; licence, seat and device changes audited |
| 5 Nullability | Yes | Automated (m4) |
| 6 Classification | Yes | Sensitive = hashes only (m13) |
| 7 Multilingual | Yes | Plan and lookup labels are keys |
| 8 Physical naming | Yes | `<table>_pYYYYMM` partitions |
| 9 Licensing | Yes | Explicit positive limits; device limit at login under concurrency; refused attempts audited; revocation auditable |
| 10 Money / history | Yes | Append-only ledgers with reversals; non-overlapping periods by exclusion; history carries actor, subject, time, deduction |

---

## Verification

```sh
MSYS_NO_PATHCONV=1 ./run_phase1.sh m11
```
Expected: `licences : 6`, `sourcing : 3`, `subscriptions : 11` entities present, Phase 1 hand-offs wired, no card/bank columns, licence limits stored as explicit columns. The m2 orphan check also covers the new tables.

```sh
MSYS_NO_PATHCONV=1 ./run_phase1.sh m12
MSYS_NO_PATHCONV=1 ./run_phase1.sh m13
MSYS_NO_PATHCONV=1 ./run_phase1.sh m14
```
m12 expected output:
- `PASS 40 documented relationships …`;
- three `PASS rejected:` lines for the composite FKs: a session on another user's device, a licence for another organisation's subscription, and outreach for a different requirement.

m13 expected output: class and date-range checks for the Phase 3 tables, the column contents rule groups 9 and 10 require, credits stored as integers, and bounded integration references.

Mutation-tested: replacing the session/device composite FK with a plain FK makes m12 fail. Removing a class comment, or changing a credit column to `bigint`, makes m13 fail.

**Review checklist**
- [ ] D15 (one session table, reused by B50) is agreed with whoever owns Phase 4 shared items.
- [ ] D16 (decision on the request) and D17 (credits vs money) are acceptable to the panel narrative.
- [ ] Every row of the coverage table maps to an entity.
- [ ] D18 (composite FKs) and the partitioned-history credit-link deviation are agreed.
- [ ] The application connects at READ COMMITTED and logs in through `app_open_session()`.
- [ ] Phase 3 deviation register accepted.
