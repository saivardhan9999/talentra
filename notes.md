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

**M14 (done)**
- **Device limit at login, safe under concurrency (B45).**
  - Opening a session locks the user's seat row (`FOR UPDATE`), then counts live sessions. Two simultaneous logins queue, and the second one sees the first.
  - A session counts while `ended_at` is NULL and `expires_at` is in the future. Logout, revocation or expiry releases it.
  - Login goes through `app_open_session()`. At the limit it records the refusal in `login_attempt` and `audit_event` and returns NULL instead of raising, so the record isn't rolled back.
  - The seat limit works the same way, by locking the licence row.
  - Releasing a seat or revoking a device ends its sessions, and each revocation is an event.
- **Consultants (B46):** only users with the consultant role, only for themselves, only on requirements open to consultants. Only the employer (with `job_requirement.manage`) accepts or declines, and the decision is final. Shortlisting and outreach need an accepted request, and stop the moment the requirement closes to consultants.
- **Money (B47):**
  - Subscription periods can't overlap (exclusion constraint).
  - The ledger trigger locks the wallet, computes the balance and blocks overdrafts. The wallet balance can't be edited directly.
  - Entry types fix sign and references; reversals must negate the original exactly, once.
  - A recharge credits exactly the credits bought.
  - Refunds never exceed the payment; invoices bill exactly the order amount.
  - A credit deduction pays for one download, view or outreach only. This is a trigger plus an advisory lock, which settles the M12 limitation without a unique index.
- `m14_constraints.sql`: 73 behavioural checks in a rolled-back transaction, plus a **real two-connection concurrency test** through `dblink`. Connection 2 must still be waiting after one second while connection 1 holds the lock, and must get no session once connection 1 commits.
- Lookup comments now mark the SYSTEM ids that CHECKs and triggers rely on.

**Errors and fixes (M14)**
| Problem | Cause | Fix |
|---|---|---|
| **Real bug, found by the test:** a wallet-recharge order with no credit quantity was accepted | The M13 CHECK `credit_quantity > 0 AND purpose = 2 OR credit_quantity IS NULL AND purpose <> 2` evaluates to NULL in that case, and PostgreSQL treats a NULL CHECK result as a pass | Rewrote it as `(purpose = 2) = (credit_quantity IS NOT NULL) AND credit_quantity > 0`, which is false in that case. Checked every other new CHECK for the same trap |
| m12 test broke after the M14 rules were added | Its sourcing request came from a non-consultant on a closed requirement. The new BEFORE triggers rejected it before the FK under test was ever checked | m12 now sets up a real consultant, an employer and an accepted request on an open requirement, so only the composite FK can reject the outreach |
| m14 stopped with "null value in column candidate_profile_id" | Running `./run_phase1.sh m14` alone skips M5's sample data, so there were no candidate profiles | The test registers its own two candidates |
| The first draft of the concurrency fixture used `INSERT … RETURNING` inside a subquery | PostgreSQL doesn't allow that | Spotted before running; replaced with two plain inserts into variables |
| The device-limit test needed a session that had already expired | `ck_user_session_date_range` requires `expires_at > started_at`, and `started_at` defaults to the transaction time | Test sessions start two hours in the past, so one can be expired by moving `expires_at` back |
| Break-test commands failed: `C:/Users/.../Temp/fn.sql: No such file`, and "cannot change name of input parameter" | Git Bash rewrote the container path; the replacement function used a different parameter name | Piped the SQL through stdin with `MSYS_NO_PATHCONV=1` and kept the original parameter name |

**Proof the checks fail when they should:**
- Removing the seat `FOR UPDATE` locks: "second concurrent login did not wait for the first".
- Dropping the period exclusion: "overlapping subscription periods … accepted".
- Making `app_job_open_to_consultants()` always true: "consultant requesting a requirement closed to consultants … accepted".
- A clean rebuild then ended with `VERIFIED: m1 … m14`. **Phase 3 is complete.**

---

## Milestones 15–16 — Phase 4 entities and relationships

**M15 (done)**
- `sql/12_notifications.sql` (11 tables): user preferences (language + privacy in one row per user), notification preferences, job alerts, notifications, deliveries (partitioned monthly, the high-volume path), community posts and reactions, support tickets and messages, FAQs (as UI label keys), referral events.
- `sql/13_shared.sql` (4 tables): credentials (argon2id hash or HMAC of the social sign-in id), consent records (append-only history), block entries (a user blocks one user or one organisation), system error log (closes the Tier 1 "system errors" gap). Sessions and the audit trail are reused from Phases 2–3, not duplicated (D21).
- `sql/14_analytics.sql`: star schema.
  - 5 dimensions; `dim_organisation` and `dim_candidate` keep version history (SCD type 2).
  - 11 facts and 4 aggregates (materialised views).
  - Every object is prefixed `dim_`, `fact_` or `agg_` (rule group 8).
  - Facts keep the source id as a plain value with no FK, so the marts are decoupled from transactional rows (D19).
- `m15_entities.sql` checks:
  - all 16 docket items map to an entity, and the prefix rule holds;
  - aggregates read only facts and dimensions;
  - every KPI has a fact, and notifications store no message body.
- **Docket gap found:** B49 says "the KPIs in Section 8", but the 12-page docket has no Section 8 (it ends at Section 7). I derived 13 KPIs from the §2 workflows and recorded the gap in `docs/phase4-design.md` for you to raise with the organisers.

**M16 (done)**
- `m16_relationships.sql` lists 40 Phase 4 relationships with their delete rules, covering every pair the docket names: preference → user, delivery → notification, post → reaction, fact → dimension, aggregate → fact, credential / consent / session → user, audit event → actor, block → blocker and blocked.
- Star-schema rules are checked across all analytical tables, not just a sample:
  - every date key points at `dim_date`, and every `dim_x_id` points at `dim_x` (38 fact → dimension FKs);
  - analytical tables point only at other analytical tables, currency and the audit actor;
  - each aggregate reads from its facts.
- ER diagrams and cardinality tables are in `docs/phase4-design.md`.
- The M5 message "4 history tables partitioned", stale since Phase 2, now reports the real count (9 partitioned tables, 225 partitions).

**Errors and fixes (M15–M16)**
| Problem | Cause | Fix |
|---|---|---|
| The first full run stopped in m4: "reserved word used as identifier: status_code" | `fact_gig_assignment.status_code` is on the MySQL reserved-word list that m4 enforces | Renamed it to `assignment_status_code` |
| Partitioning `notification` would break the FK naming rule | An FK to a partitioned table must include its timestamp partition key, and m4 requires every FK column to end in `_id` | Spotted before building: only `notification_delivery` (the high-volume table) is partitioned, and `notification` stays a plain FK target (D22) |
| The KPI list the docket refers to doesn't exist | The docket references Section 8, which is missing from the PDF | Derived the KPIs from the workflows; the gap is recorded for the organisers |
| A break test on M16 failed at the listed-FK check, not the general rule I meant to test | The dropped FK (`fact_application.applied_date_id`) is also in the hand-written list | Repeated it with an unlisted FK (`fact_outreach.sent_date_id`): the general rule caught it ("dimension key without its FK") |

M16 passed on its first run.

**Proof the checks fail when they should:**
- An aggregate reading `job_requirement`: m15 failed with "aggregate reads a transactional table".
- A dropped fact → `dim_date` FK: m16 failed.
- An FK from `fact_payment` to `payment_order`: m16 failed with "analytical table references a transactional table".
- A clean rebuild then ended with `VERIFIED: m1 … m16`.

---

## Milestones 17–18 — Phase 4 columns, keys and constraints (schema complete)

**M17 (done)**
- The shared column checker now runs for Phase 4: 374 columns checked, every one classified, every date range with a CHECK. Date-range detection also covers `unblocked_at`, `resolved_at`, `closed_at` and `read_at`.
- m17 also checks:
  - credentials are Sensitive, and nothing secret-looking exists anywhere except as a hash (B56);
  - the analytics layer holds no personal data;
  - consent records carry full evidence;
  - notification text is a short summary, not a message body;
  - community text records its language.
- `docs/phase4-data-dictionary.md` is generated: 32 tables.

**M18 (done)**
- **Deliveries (B57).**
  - Preferences are applied on the way in: a channel switched off is stored as suppressed.
  - Provider callbacks only move status forward, so replays and late callbacks are harmless.
  - Status columns aren't indexed and partitions keep 30% free space, so callback updates stay cheap (HOT updates). New partitions inherit that setting.
- **Analytics (B58).**
  - Version history can't overlap and only the open version is current (exclusion constraint + CHECK).
  - Version lookup functions, and a load step that opens a new version when a tracked attribute changes.
  - `refresh_aggregates()` refreshes every summary view without blocking readers, and logs each refresh.
- **Shared items (B59).**
  - **Audit trail append-only for every partition.**
  - Unique live credential per user and type; one social identity per user; argon2id format required; no in-place edits.
  - Blocks belong to the blocker, one live block per target, and unblocking is final.
  - **A blocked user or company can't see the candidate's profile, contact details or resumes** (row-level security on 14 tables), and can't see the block itself.

**Two security holes found and fixed**
| Problem | Cause | Fix |
|---|---|---|
| **A recruiter could read another company's draft requirements through `v_job_requirement`** (a Phase 2 hole, in place since M10) | PostgreSQL views run with their owner's rights by default, and the owner skips row-level security. RLS was on the table, but not applied through the view. Found while designing the candidate-visibility rule, and confirmed with a probe: 0 rows through the table, 1 through the view | Every view is now `security_invoker`. m18 checks the probe case and asserts the setting on **every** view, so a future view can't reopen it. Phase 2 doc carries a correction note |
| **One month of the audit trail could be truncated directly** (`TRUNCATE audit_event_p202610` succeeded) | A statement-level `TRUNCATE` trigger on a partitioned table doesn't fire for a single partition. The app role never had TRUNCATE, but owners could do it, so "append-only for every role" wasn't true | `protect_partitions()` puts the trigger on every partition of every append-only table. `make_append_only` and `create_monthly_partitions` apply it to future partitions, and m18 tests one created later |

**Other errors and fixes (M17–M18)**
| Problem | Cause | Fix |
|---|---|---|
| A test expecting "another user editing the profile" to fail would itself have failed | Under row-level security, an update to a row you can't see touches 0 rows and raises no error | Caught before running. The test runs the update as a recruiter who can see the profile, then checks nothing changed. The first draft also used a recruiter whose company was blocked, so 0 rows would have proved nothing; switched to an unblocked one |
| The first probe for the view hole showed 0 rows both ways | Running one milestone alone skips M5's sample data, so there were no jobs to leak | Probe rerun with another company's draft inserted: table 0, view 1 |
| "relation … already exists, skipping" notices in m18 output | `create_monthly_partitions` used `CREATE TABLE IF NOT EXISTS` for the default partition | It now checks first with `to_regclass` |

The M17 and M18 code both passed on the first run.

**Proof the checks fail when they should:**
- Removing the Sensitive class from `password_hash`: m17 failed.
- Disabling RLS on `candidate_profile`: "blocked recruiter no longer sees the candidate" failed.
- Turning `security_invoker` off on `v_job_requirement`: the view test failed.
- Dropping one audit partition's TRUNCATE trigger: "truncating one month … accepted".
- Dropping the delivery trigger: the suppression test failed.
- A clean rebuild then ended with `VERIFIED: m1 … m18`. **Phase 4 and the database schema are complete.**

---

## Milestones 19–20 — Seed data, queries and validation (laptop scale)

**M19 (done)**
- A data generator in `sql/seed/` (11 steps). It's set-based SQL inside PostgreSQL and deterministic, and `SEED_SCALE` scales it. It ran at laptop scale with every rule switched on: **1,000,000 profiles, 100,000 requirements, 4,999,885 applications with 10.5M history rows**, and every one of the 214 tables seeded. Database: 16 GB; load time about 1 h 40 min.
- Realism:
  - names in English and seven Indian scripts (28% non-Latin);
  - skew towards metros, popular skills and big employers;
  - 2% duplicate registrations, half unflagged;
  - planted import defects.
- The seed goes through the real rules:
  - logins via `app_open_session()`: 7,366 refused at the device limit;
  - gig assignments one by one through the exclusion constraint: 657 overlaps rejected and logged;
  - sourcing decisions taken as the employer.
- One documented exception: the two pipeline triggers are paused for the bulk load, so application history gets real dates instead of "now". M20 proves every history is a legal path.
- `m19_seed.sql` checks volumes against the scale, every table populated, duplicates, multilingual names, all 12 pipeline statuses with history, the rules exercised, and the marts matching the source rows.
- The runner seeds automatically before the first M19+ check after a rebuild, so M1–M18 still run on the empty schema.

**M20 (done)**
- 13 fixed queries (functional, transactional, lookup, performance) and 13 module queries in `sql/queries/`, plus `validation.sql` (26 Section 5 / design rules, 7 data-quality findings).
- `run_report.sh` writes `docs/phase5-query-report.md` (SQL, real output and `EXPLAIN ANALYZE` plans for the top ten) and `docs/phase5-seed-validation.md`.
- Full scale: every query returns results; **0 violations across 26 rules**; all findings detected.
- Query times: job search 8 ms, candidate search 31 ms, most lookups under 1 ms. Duplicate detection takes 2.2 s and time-to-hire by industry 0.8 s, the first targets for M21.
- `docs/coverage-gap-register.md`: the competitor benchmark against Naukri, Monster and LinkedIn that docket §4 requires but no earlier phase had produced, with gaps G1–G12 and data-quality items Q1–Q4.

**Errors and fixes (M19–M20)**
| Problem | Cause | Fix |
|---|---|---|
| **Schema design flaw: "out of shared memory"** loading 175k paid downloads | The M14 one-charge-per-entry rule took an advisory lock per charged row, and each one holds a shared lock-table slot until commit. Fine one at a time; fails on any bulk load | Lock the ledger row instead (`SELECT … FOR UPDATE`, definer rights since the app role can't update ledger rows). Same guarantee, no lock-table use. Phase 3 doc updated; M14 re-run and passing, including the concurrent-login test |
| "could not resize shared memory segment … No space left on device" (the disk wasn't full) | Docker gives containers 64 MB of `/dev/shm`; parallel hash joins with `work_mem = 64MB` outgrew it | Recreated the container with `--shm-size=1g` on the same data volume; docs updated |
| Outreach rejected: "needs membership of its organisation" | The generator used recruiters who had moved company; the M14 rule refused them | The generator picks current members only |
| Block rejected by `ck_block_entry_date_range` | The generator could unblock before the block | The unblock time is derived from the block time |
| Validation: 655 applications before their job was published | The generator capped application time at "an hour ago", earlier than jobs published in the last hour | Generator fixed. Repaired in place: 12 jobs' `published_at` moved before their first application (a normal update; history untouched) |
| Finding inflated: 1.37M late applications (27%) | The generator spread applications over 90 days while postings expire after 30–90 days | Generator fixed for future seeds; the current dataset reports the inflated finding honestly |
| 10 applications missing from the facts (found by M19 at 1%) | Candidates registered in the last hour got an application time before their registration | Registrations end two days before the seed's "now" |
| Fact load stuck for 10 minutes at 1% scale | The new dimension tables had no statistics, so the planner nested loops | `ANALYZE` before loading the facts |
| Questionnaires had 0 rows at 1% scale | "2% of organisations" selected none of 200 | The 3 largest employers always screen |
| `ON CONFLICT`-free uniqueness and NULL-knockout errors, and `g` column clashes, while writing the generator | Small generator mistakes | Fixed as found |
| **Runner bug:** `./run_phase1.sh m19 m20 m14` ran only `m19` | The runner read only `$1`, so every multi-milestone command since M1 ran only its first milestone | The runner takes every argument (`LIST="${*:-$ALL}"`) |
| Q7 failed: "app.current_user_id is not set" | Debiting the wallet updates its audit columns, and the schema refuses anonymous updates | Q7 runs as the company's recruiter |
| The M20 test's `CREATE TEMP TABLE … AS` + `\ir file` didn't join | A psql quirk | Query files loaded into a variable (without the final semicolon) |
| `run_report.sh` stopped after A2 | `grep` with no matches exits 1 under `set -eo pipefail` | Those filters tolerate empty input |
| PowerShell `powercfg` failed from Git Bash ("Invalid Parameters") | Git Bash rewrote `/change` into a path | Ran it through PowerShell |

**Also done:** a `/doctor` health check. Unused GSD commands and agents were moved to `~/.claude/disabled/`, and auto mode is now the default permission mode.

**Disk:** the seeded database is 16 GB, and C: had 12 GB free afterwards.

---

## After M20 — demo UI and CI (outside the milestone list)

**Demo UI (`ui/`).** A small Node.js app with two dependencies (Express, pg) and one page in plain JavaScript:
- **Six tabs:** job search, candidate search, my applications (English / Tamil / Hindi labels), pipeline, hiring funnel, privacy and blocking.
- **"Viewing as" switch:** six people resolved from the seed. Every request runs as `talentra_app` with that person's identity, so row-level security decides what each person sees.
- **`ui/smoke-test.js`:** checks every screen plus the blocking walkthrough (block → hidden from that company's recruiter → still visible to another company's → the block itself invisible → unblock), and leaves the data unchanged.
- **Speed at laptop scale:** 0.1–0.3 s per screen; name search with a city about 1 s.

**CI (`.github/workflows/verify.yml`).**
- On every push and pull request: start `postgres:16`, rebuild, run M1–M18, seed at 1%, run M19–M20, keep the log, post the result to Discord.
- The webhook URL lives in the `DISCORD_WEBHOOK_URL` repository secret.
- `ci/notify_discord.py` builds the message from environment variables only (no shell splicing), disables @mentions, and never fails the build.
- ChatOps was deliberately skipped (an always-on bot with a token, for no real gain).
- Setup steps are in `docs/ci.md`.
- **It hasn't run yet:** it starts when you commit and push, and the Discord secret has to be added on GitHub.

**Errors and fixes**
| Problem | Cause | Fix |
|---|---|---|
| **Job search 3.7 s, candidate name search timing out** (as the app role, at laptop scale) | **Row-level security cost:** helper calls in policies (`app_has_permission`, `app_current_user_is_recruiter`, `app_current_user_id`) ran once per row, and `app_can_see_candidate(id)` re-read the profile, memberships and blocks for every row. RLS applies its checks before full-text or name-similarity filters, so a search paid that cost across 100k jobs or 1M profiles. M18's code comment had predicted this ("measure in M21") | Every helper call in a policy is wrapped in `(SELECT …)`, so PostgreSQL evaluates it once per query. `candidate_profile` states its visibility rule inline, with two definer-rights helpers run once per query (can the viewer see employers-only profiles; who has blocked the viewer). Same rules: M10 and M18 re-run and passing. Job search is now ~0.15 s |
| Name-only candidate search still slow (several seconds) | Under RLS, PostgreSQL won't run a non-leakproof filter such as trigram similarity before the security checks, so the name index can't be used first | Recorded for M21. The UI pre-fills the candidate's city, so the city index narrows the search (~1 s) |
| **The UI couldn't log in** ("password authentication failed") | A native **PostgreSQL 18 Windows service** also listens on port 5432 over IPv4, and `localhost` reached it instead of Docker. The scripts never noticed because they use `docker exec` | Recreated the container mapping host port **5433** (same data volume, nothing lost); the UI defaults to 5433; docs updated. The other PostgreSQL was left untouched |
| Tests would wipe the seeded database | `run_phase1.sh` always rebuilt the database named `talentra` | `TALENTRA_DB` chooses the database: `TALENTRA_DB=talentra_ci` rebuilds and tests a scratch copy. The M14 concurrency test connects to `current_database()` instead of a hard-coded name |
| `operator does not exist: bigint <> bigint[]` | `<> ALL ((SELECT f()))` is read as "against each row of a subquery", not an array | Cast to `::bigint[]` |
| The full run with seed failed in step 06 (twice): "no free seat", then "device limit reached" | In a full run M14 runs before the seed and leaves a committed one-seat licence fixture; the seed added seats and sessions to *all* licences and devices | The seed touches only the licences, seats and devices it created |
| M20 Q1 returned no rows at 1% scale | Hard-coded "Java developer in Bengaluru" had no matching open posting among 1,000 jobs | Q1 and Q2 pick the city with the most matching openings / candidates, so they return rows at any scale (CI runs at 1%) |
| The smoke test's block check "failed" | It looked for any "Divya Kumar"; a namesake was still visible | The test checks the exact profile id. A leftover block from the failed run was undone, as that candidate |
| The background server started in the wrong folder | A background shell ignored `cd` | Start it with an absolute path |
| The dry-run notifier crashed printing ✅ / ❌ | Windows console code page | The dry-run prints ASCII-escaped JSON |
| CI would hit "Permission denied" on `./run_phase1.sh` | Committed from Windows without the executable bit (`100644`) | The workflow calls `bash ./run_phase1.sh` |

**Verified:** a full M1–M20 run in the scratch database at 1% scale passes (what CI will run). The seeded database got the identical 53 policies, matching fingerprints, without a reseed.

---

## Milestones 21–22 — Performance and security

**M21 (done).** The full report is in `docs/phase5-performance.md`.
- **Harness:** `perf/benchmark.py` runs each query 3 times to warm up, then 50 measured runs inside the container, and reports min / p50 / p95 / p99 / max. The method, hardware, settings and dataset are stated in the report. The docket's "Section 10" doesn't exist, the same gap as Section 8.
- **Baseline (B70):** the interactive queries are under 8 ms at p99 (Q2 at 83 ms). The outliers are Q11 duplicate detection (p50 1.98 s) and Q12 time to hire (454 ms, 173 ms after the index).
- **Indexes with before/after (B71–B73):**

  | Module | Change | Before p50 | After p50 |
  |---|---|---|---|
  | Administration | `audit_event (organisation_id, occurred_at)` | 81 ms | **1.2 ms** |
  | Licences | `login_attempt (attempted_identifier_hmac, attempted_at)`, brute-force check on every login | 2.7 ms | 0.8 ms (923 pages read → a handful) |
  | Notifications | `notification_delivery (provider_message_ref)`, callbacks | 25 ms | **0.8 ms** |
  | Analytics | partial `fact_application (joined_date_id)` | 459 ms | 162 ms |
  | Profile (extra) | ranked name search `app_search_candidates_by_name()`: definer rights, same visibility function per match, best first, stops at the limit | 1,654 ms | **30 ms** |

- **Partitioning (B73), measured:**
  - history, recent week: 317 ms pruned against 655 ms unpruned, and 31k against 116k pages;
  - deliveries, last day: 44 ms against 122 ms;
  - `application` deliberately not partitioned: all access paths are 1–26 ms index lookups, and six tables have foreign keys to it.
- **Extrapolation (B74):** two measured points, 1% and 100% of laptop scale.
  - Point lookups are flat.
  - Q11 and Q12 grow linearly (×90 for ×100 data).
  - Full scale projects to ~180 GB, past RAM, so point lookups become 1–5 ms.
  - **Q11 degrades first:** a full scan plus hash aggregation of 10M groups, beyond `work_mem`, spills to disk, for ~30–60 s. Fix: a dedupe key checked at registration.
  - Next: Q12 at ~3.5 s (move to an aggregate), then Q2 at ~0.6 s (composite index).
- `sql/tests/m21_performance.sql`: the indexes serve their queries (plans checked, with sequential scans off so it holds at 1%); partitions prune; the name search equals row-level security (none hidden, none better missed). It passes at 1% and full scale. A fresh build plus M1–M21 passes in the scratch database.

**Errors and fixes (M21)**
| Problem | Cause | Fix |
|---|---|---|
| Name search measured only 15 ms "before" | The test query had no `ORDER BY`, so it stopped at the first 25 matches. Real searches rank best first, which forces reading all matches | The query ranks by similarity (1,654 ms before), matching the UI |
| The first search function was only 2.7× faster (611 ms) | It checked visibility on all 4,369 matches before ranking | It walks matches best first and stops once enough visible ones are found (30 ms). Correctness re-checked: none hidden, none better missed |
| The function's result hash differed from the RLS query's | Tie order (the function adds `id` as a tie-breaker) | Compared as sets: identical up to the cut-off |
| M21 check: "idx_audit_event_organisation_id not used" | On a partitioned table each partition's index has a generated name, so the parent name never appears in plans | Match on the column part of the name |
| A Python one-liner patch stopped halfway | The verified-milestones line appears twice in the guide, so the single-match check failed | Replace all occurrences, then re-check |

**M22:** not started.
