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

**M12:** not started.
