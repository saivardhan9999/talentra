# Talentra — Build Notes

A note is added after every two milestones: what was built, what went wrong and how it was fixed.
Full design detail lives in `docs/phase2-design.md` and `docs/phase3-design.md`; this file is the short log.

Milestones 1–6 (Phase 1) were finished before this log started; see `docs/phase1-verification-guide.md`.

---

## Milestones 7–8 — Phase 2 entities and relationships

**What happened**
- M7 (entities): added `sql/05_administration.sql`, `06_organisation.sql` and `07_gig.sql`. Administration has roles, permissions, role grants and a partitioned, append-only `audit_event`. Organisation has locations, registration identifiers and members. The gig marketplace has 10 tables, from worker profiles to ratings and favourite/blacklist lists.
- `user_account` and `organisation`, which Phase 1 created as bare shells, are now extended by their Phase 2 owners.
- The agreed entity list moved into one shared file (`sql/tests/expected_entity.sql`), used by m2 and m7, so a new table that isn't listed fails the orphan check.
- M8 (relationships): 33 foreign keys checked with each one's ON DELETE rule, through a shared `check_expected_fk.sql`, which m3 now uses too.
- `run_phase1.sh` now finds SQL files and milestone tests automatically instead of using a fixed list.

**Errors and fixes**
| Problem | Cause | Fix |
|---|---|---|
| m2's PASS count dropped after the entity list was shared | `user_account` / `organisation` had been relabelled phase 2, so m2's Phase 1 check lost them | Kept both shells listed as phase 1 (created in Phase 1, extended in Phase 2) |
| Docker was not running at the start of the session | Docker Desktop was stopped | User started it; no code change |

**Proof the checks fail when they should:** dropping `gig_rating` made m7 fail with "expected entity missing", and changing an FK's ON DELETE rule made m8 fail with "missing FK … ON DELETE". Both were restored, and the run ended with `VERIFIED: m1 … m8`.

---

## Milestones 9–10 — Phase 2 columns, keys and constraints

**What happened**
- M9 (columns): `organisation` gained company-profile columns (description, size band, founded year, logo, contact email/phone). `m9_columns.sql` checks across the whole schema that:
  - every Phase 2 column states a data class;
  - Sensitive columns are only tokens or hashes;
  - email, phone, money, free-text and date-range columns follow the standard formats.
- `docs/phase2-data-dictionary.md` is generated from the database. `data_dictionary.sql` now takes a `tables` filter.
- M10 (constraints): `sql/08_access_control.sql` adds:
  - the `talentra_app` role, so row-level security always applies to the app;
  - RLS on `job_requirement` and `application`, so recruiters see only their own company;
  - append-only privileges on every audit and history table;
  - automatic audit logging of sensitive changes (changed column names only, never values).
- Organisation rules: no overlapping memberships, no hierarchy loops, one headquarters per company, each tax id registered only once.
- Gig rules: one worker's gig windows can't overlap; only workers apply; only the requester decides and rates; blacklisted workers can't apply; earnings can't be edited.
- `m10_constraints.sql`: 60 behavioural tests in one rolled-back transaction.

**Errors and fixes**
| Problem | Cause | Fix |
|---|---|---|
| Docker stopped mid-session; `docker` commands failed | Docker Desktop had quit. Its exe was not in `C:\Program Files\Docker` but in `%LOCALAPPDATA%\Programs\DockerDesktop` | Started it from there with PowerShell `Start-Process`, then `docker start talentra-pg` |
| The first m9 run failed: "16 data column(s) without an explicit class" | Titles, availability windows and timestamps in 05/07 had no `class=` comment | Added class comments. This was the new check doing its job |
| A Python patch script for `07_gig.sql` failed: "unexpected EOF while looking for matching `'`" | The bash heredoc contained `'''`, which broke shell quoting | Wrote the script to a scratchpad file and ran it from there |
| A doc patch script failed: `FileNotFoundError: /tmp/m910.md` | The script read a text file that was never written | Wrote the text to the scratchpad and reran |
| A composite FK from `organisation_member` to `role` would break the m4 naming rule (every FK column must end in `_id`) | The composite key would need a non-`_id` column | Used `CHECK (role_id IN (3, 6, 7))` with reserved system role ids instead; recorded in the deviation register |

**Proof the checks fail when they should:** each change below broke the matching check, then everything was restored.
- Disabling RLS on `job_requirement`: m10 failed with "recruiter sees 2 requirements of another company".
- Dropping the gig overlap exclusion: m10 failed with "overlapping gig windows … accepted".
- Removing one class comment: m9 failed with "1 data column without an explicit class".

**Known cosmetic issue:** m5's message still says "4 history tables", but it actually counts all partitions (now 175).

---

## Milestones 11–12 — Phase 3 entities and relationships

**M11 (done)**
- `sql/09_subscriptions.sql` (11 tables): plans, entitlements, subscriptions and periods, payment orders and events, invoices, refunds, wallet and credit ledger, profile download history.
- `sql/10_licences.sql` (6 tables): licences, seats, devices, sessions, login attempts, revocation events.
- `sql/11_sourcing.sql` (3 tables): sourcing requests, outreach batches and recipients.
- Links to earlier phases: `profile_view_event.wallet_ledger_entry_id` (a view can point at the credit charge that paid for it) and `talent_list.sourcing_request_id` (consultant shortlists).
- `m11_entities.sql` checks that the Phase 3 tables and hand-off columns exist, that no card or bank columns exist, and that licence limits are NOT NULL columns.
- Decisions D15–D17 in `docs/phase3-design.md`.
- **Errors:** none. The first run passed, and the full rebuild ended with `VERIFIED: m1 … m11`.

**M12 (done)**
- Every Phase 3 relationship (40) is listed in `m12_relationships.sql` with its delete rule and cardinality, checked by the same shared checker as m3/m8.
- **Composite FKs (decision D18)** turn ownership rules into constraints:
  - a session runs only on a device of its own user, and uses only that user's seat;
  - a licence belongs to the organisation that subscribed;
  - outreach sent under a sourcing request is for that request's requirement;
  - a revocation naming both a session and a device must match.
- One-to-one rules added as partial unique indexes:
  - an order pays for at most one subscription period;
  - a recharge order is credited once and a refund is debited once;
  - an outreach batch is charged once.
- m12 also inserts bad rows in a rolled-back transaction to prove three of the composite FKs reject them.
- Deviation recorded: download and view history are partitioned tables, so "one ledger entry pays for one download" can't be a unique index there. M14 decides how to handle it.

**Errors and fixes (M12).** No runtime errors; the first full run passed. Two problems were caught while writing, before anything ran:
| Problem | Cause | Fix |
|---|---|---|
| A composite FK on its own would let a half-filled pair through | PostgreSQL skips a composite FK when any of its columns is NULL (MATCH SIMPLE) | Added a CHECK where a column can be NULL alone (`ck_login_attempt_device_needs_user`, `ck_outreach_batch_sourcing_request`), and kept a single-column FK on `session_revocation_event.user_session_id` |
| The first draft of m12's rejection tests would have failed for the wrong reason | It relied on existing plan and job rows, but no plans are seeded, so a missing plan would raise a NOT NULL error instead of the FK error being tested | The test creates its own plan, organisations and job requirements inside the rolled-back transaction |

**Proof the checks fail when they should:** replacing the session/device composite FK with a plain FK made m12 fail with "missing FK user_session(user_device_id,user_account_id)". The run ended with `VERIFIED: m1 … m12`.

---

## Milestones 13–14 — Phase 3 columns, keys and constraints

**M13 (done)**
- The M9 column checks moved into a shared `sql/tests/check_columns.sql` that takes the phase number. m9 runs it for Phase 2 and m13 for Phase 3, so the rules can't drift apart.
- Date-range detection now also recognises `released_at`, `ended_at`, `cancelled_at`, `processed_at`, `delivered_at` and `responded_at`.
- New column: `payment_order.credit_quantity`, the number of credits a wallet recharge buys. A CHECK makes it required for recharges and forbidden for subscription orders.
- m13 also checks:
  - sessions store device, start, last activity and end (rule group 9);
  - download and view history store actor, subject, time and credit charge (rule group 10);
  - credits are integers;
  - gateway and provider references are `varchar(100)`.
- `docs/phase3-data-dictionary.md` is generated: 22 tables.
- The verification guide has its M12/M13 rows. Its M7–M11 rows had been placed below a paragraph, outside the table, so GitHub wouldn't render them as table rows; they're now back inside it.

**Errors and fixes (M13)**
| Problem | Cause | Fix |
|---|---|---|
| The data dictionary command failed: `C:/Program Files/Git/sql/tests/data_dictionary.sql: No such file` | Git Bash rewrote the container path `/sql/...` into a Windows path | Reran with `MSYS_NO_PATHCONV=1` |
| The script that adds the M12/M13 sections to the design doc failed: "unexpected EOF while looking for matching `'`" | The same heredoc quoting problem as in M10: apostrophes in the text inside a bash heredoc | Wrote the text to a scratchpad file and inserted it with Edit and a short Python call |

The first m13 run passed: every Phase 3 column had already been classified in M11.

**Proof the checks fail when they should:** removing the class comment on `licence_seat.released_at` made m13 fail with "1 data column without an explicit class", and changing `wallet_ledger_entry.balance_after` to `bigint` made it fail with "credit column not an integer". A clean rebuild then ended with `VERIFIED: m1 … m13`.

**M14:** not started.
