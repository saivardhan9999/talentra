# Talentra — Phase 3 Design (Individual modules)

**Scope so far:** Milestone 11, backlogs B36–B38. Modules: **Licences, seats, devices and sessions** (Member A), **Sourcing and consultant requests** (Member B), **Subscriptions, wallet, payments and download history** (Member C).
**Status:** M11 built and verified on PostgreSQL 16 (`./run_phase1.sh m11`). M12 (relationships), M13 (columns) and M14 (keys and constraints: device limit under concurrent logins, consultant-only-on-open requirements, non-overlapping subscription periods, ledger rules) are next.

| File | Contents |
|---|---|
| `sql/09_subscriptions.sql` | Plans, entitlements, subscriptions and periods, payment orders and events, invoices, refunds, wallet and ledger, profile download history |
| `sql/10_licences.sql` | Licences, seats, devices, sessions, login attempts, revocation events |
| `sql/11_sourcing.sql` | Sourcing requests, outreach batches and recipients; consultant shortlist link on `talent_list` |
| `sql/tests/m11_entities.sql` | Milestone check |

Build order follows dependencies, not the docket's module order: Subscriptions (09) before Licences (10), because a licence is granted by a subscription. Sourcing (11) goes last because outreach references the wallet ledger.

Like Phase 2, the tables are created with their columns and foreign keys so the schema-wide M4/M9 column rules keep passing. The M12–M14 deliverables (relationship model, column review, behavioural constraints) are still to do.

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

**Decision D15 — one session table.** The docket lists "sessions (identity only)" under Administration and the Phase 4 shared items (B50), and "active sessions" here. One login produces one session, so there is one `user_session` table. Users who need no licence (candidates, gig workers) have `licence_seat_id` NULL, and the device limit still applies through their devices. B50 reuses this table.

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
| `subscription_period` | First term and every renewal (`renewal_number`), with the paying order; non-overlap per subscription/licence comes in M14 |
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
| Registered devices, active sessions, login history, device-limit rule | `user_device`, `user_session`, `login_attempt` (rule enforced in M14) |
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

## Verification

```sh
MSYS_NO_PATHCONV=1 ./run_phase1.sh m11
```
Expected: `licences : 6`, `sourcing : 3`, `subscriptions : 11` entities present, Phase 1 hand-offs wired, no card/bank columns, licence limits stored as explicit columns. The m2 orphan check also covers the new tables.

**Review checklist**
- [ ] D15 (one session table, reused by B50) is agreed with whoever owns Phase 4 shared items.
- [ ] D16 (decision on the request) and D17 (credits vs money) are acceptable to the panel narrative.
- [ ] Every row of the coverage table maps to an entity.
