# Talentra — Phase 1 Verification Guide

How to verify each Phase 1 milestone yourself. Every milestone has two parts:

* **Automated:** a script that fails loudly if the milestone is not met.
* **Review:** what a team member who did *not* write the module reads and agrees to (the docket's "validate" backlogs).

A milestone is verified when its script passes **and** a reviewer ticks its checklist.

---

## Step 0 — One-time setup

1. Start Docker Desktop.
2. From the repo root, start PostgreSQL 16 with the `sql` folder mounted (skip if `docker ps` already shows `talentra-pg`):
   ```sh
   docker run -d --name talentra-pg --shm-size=1g -e POSTGRES_PASSWORD=talentra -p 5432:5432 -v "$PWD/sql:/sql" postgres:16
   ```
3. Run everything once to confirm the environment works:
   ```sh
   MSYS_NO_PATHCONV=1 ./run_phase1.sh
   ```
   **Expected:** the last line is `VERIFIED: m1 m2 m3 m4 m5 m6 m7 m8 m9 m10 m11 m12 m13 m14 m15 m16 m17 m18 m19 m20` and `echo $?` prints `0`. Any `ERROR` / `FAIL` line stops the run with a non-zero exit code.

> `MSYS_NO_PATHCONV=1` is only needed in Git Bash on Windows. It stops `/sql/...` being rewritten to a Windows path.
> `./run_phase1.sh m3` rebuilds the database and verifies one milestone; several can be named (`./run_phase1.sh m19 m20`). `./run_phase1.sh --no-build m3` verifies against the existing database. A plain `./run_phase1.sh` (all milestones) also seeds at laptop scale before M19, so it takes well over an hour; use `SEED_SCALE=0.01` for a quick full pass.

Optional: to browse the schema yourself, open a SQL prompt with
`docker exec -it talentra-pg psql -U postgres -d talentra`.

---

## Milestone 1 — DB provider, module list, assignment (B1–B3)

**Automated**
```sh
MSYS_NO_PATHCONV=1 ./run_phase1.sh m1
```
Expected:
```
PASS engine is PostgreSQL 16.x
PASS database and client encoding are UTF8
PASS extensions pg_trgm (search) and btree_gist (exclusion constraints) installed
```

**Review** — open [phase1-design.md § Milestone 1](phase1-design.md#milestone-1--provider-modules-assignment)
- [ ] B1: the provider comparison names a concrete docket requirement for each row (exclusion constraints, RLS, partition FKs, partial indexes, full-text). Ask: "could MySQL meet the non-overlap rule without triggers?" The doc answers it.
- [ ] B2: all 11 modules from docket §7 are listed with type and phase, plus the Tier 3 stretch line.
- [ ] B3: each common module has an owner (Team), and the "central vs secondary workflows" table exists (docket §2 asks you to justify this).

---

## Milestone 2 — Entities for Profile and Jobs and Applications (B4–B7)

**Automated**
```sh
MSYS_NO_PATHCONV=1 ./run_phase1.sh m2
```
Expected: one `PASS <module> : N entities present` per module (profile 27, jobs_applications 18, master_data 14, lookups 83 incl. 13 added in Phase 2, 16 in Phase 3 and 14 in Phase 4, plus the user_account and organisation shells), then
`PASS no orphan tables; gig entities kept out of the core pipeline (D3)`.

What it proves: every entity on the agreed list exists, **and** no table exists that isn't on the list. A new table therefore has to be added to `m2_entities.sql` with an owning module.

**Review** — [phase1-design.md § Milestone 2](phase1-design.md#milestone-2--entities-b4b7)
- [ ] Walk the "Section 4 item → Entity" table against the docket's Tier 1 and Tier 2 lists for Profile and Jobs. Every item maps to an entity.
- [ ] Decision D3 (gigs separate) has a trade-off table covering reporting, integrity and future change, as §2 requires.
- [ ] Nothing in Phase 1 duplicates a later module (no wallet, notification or audit-trail tables).

---

## Milestone 3 — Relationships (B8–B11)

**Automated**
```sh
MSYS_NO_PATHCONV=1 ./run_phase1.sh m3
```
Expected:
```
PASS 33 documented relationships exist with the stated cardinality and ON DELETE rule
PASS all 895 foreign keys state explicit ON UPDATE and ON DELETE rules
```
followed by a summary of FKs per delete rule (`r` restrict, `c` cascade, `n` set null).

What it proves: every relationship in the design doc's cardinality table exists in the database, with that exact delete rule. 1 : 0..1 relationships have a unique index. No FK falls back to the engine default.

**Review** — [phase1-design.md § Milestone 3](phase1-design.md#milestone-3--relationships-b8b11)
- [ ] Read the ER diagram. Each line has a business reason (for example, "one application per candidate per job").
- [ ] For each CASCADE row, ask whether deleting the parent should really delete the child. Only owned detail cascades, never history.
- [ ] Spot-check one relationship by hand at the SQL prompt:
  ```sql
  \d placement      -- shows the two composite FKs that tie slot and application to the same job
  ```

---

## Milestone 4 — Columns (B12–B15)

**Automated**
```sh
MSYS_NO_PATHCONV=1 ./run_phase1.sh m4
```
Expected: 10 PASS lines, covering reserved words, snake_case, `id` PKs, `_id` FKs, index naming, numeric money and `timestamptz`, currency companions, audit columns, **nullable-column justification**, hot-FK indexes, and UI-key translations.

To see the check catch a defect, make a deliberate mistake and re-run:
```sh
docker exec talentra-pg psql -U postgres -d talentra -c "ALTER TABLE candidate_profile ADD COLUMN nickname varchar(50)"
MSYS_NO_PATHCONV=1 ./run_phase1.sh --no-build m4
# -> ERROR: nullable column without justification: candidate_profile.nickname
MSYS_NO_PATHCONV=1 ./run_phase1.sh m4     # rebuild to undo
```

**Review** — [phase1-data-dictionary.md](phase1-data-dictionary.md) and [phase1-design.md § Milestone 4](phase1-design.md#milestone-4--columns-b12b15)
- [ ] Pick 10 random columns in the data dictionary. Each has a sensible type, class (Public/Internal/Personal) and, if nullable, a justification that names what NULL means.
- [ ] Contact columns (email, phone, address, date of birth) are all classed **Personal**.
- [ ] The standard-domains table covers every domain in docket rule group 3.
- [ ] Regenerate the dictionary and confirm nothing changed (proves it matches the live schema):
  ```sh
  docker exec talentra-pg psql -U postgres -d talentra -q -f /sql/tests/data_dictionary.sql > /tmp/dd.md
  ```

---

## Milestone 5 — Combined design (B16–B19)

**Automated**
```sh
MSYS_NO_PATHCONV=1 ./run_phase1.sh m5
```
This loads 20,000 candidates, 2,000 jobs and 40,000 applications inside a transaction, runs `ANALYZE`, checks the plans, then rolls everything back. It takes about 30 seconds.

Expected: 9 `PASS idx_… serves …` lines, then
```
PASS v_candidate_profile hides soft-deleted rows (19000 of 20000 visible)
PASS the 4 Phase 1 history tables are partitioned monthly; 9 partitioned tables in all, 225 partitions ...
PASS pipeline trigger wrote 39990 history rows for 39990 sample applications
MILESTONE 5 CHECKS PASSED
```
Read the tags. `[chosen by planner]` means PostgreSQL picked the index by itself. `[forced: …]` (trigram name search and job full-text) means the index *matches* the query, but at this small size a sequential scan is cheaper. Phase 5 must show those two being chosen at 1M rows.

**Review** — [phase1-design.md § Milestone 5](phase1-design.md#milestone-5--design-b16b19)
- [ ] Each access path in the index table corresponds to a real workflow (candidate search, job search, recruiter pipeline, "my applications", consultant jobs).
- [ ] Decision D7 (application not partitioned) gives a reason and says when it will be re-measured.

---

## Milestone 6 — Keys and constraints, sign-off (B20–B23)

**Automated**
```sh
MSYS_NO_PATHCONV=1 ./run_phase1.sh m6
```
Expected: 45 PASS lines ending in `MILESTONE 6 CHECKS PASSED`. Each `PASS rejected: …` line shows the bad action and the constraint that blocked it, for example:
```
PASS rejected: recruiter registering a candidate (... violates check constraint "ck_candidate_profile_self_registered")
PASS rejected: skip from applied straight to joined (application status transition 1 -> 8 is not allowed)
PASS rejected: placement into a slot of a different job (... violates foreign key constraint "placement_job_position_fkey")
```
Every test runs inside a transaction that is rolled back, so the database is unchanged afterwards.

**Review** — [phase1-design.md § Milestone 6](phase1-design.md#milestone-6--keys-and-constraints-b20b23)
- [ ] Every row in the "Business rules enforced" table has a matching `PASS` line. Check the reason in brackets as well as the PASS: a test that fails for the wrong constraint does not prove the rule.
- [ ] Try one rule by hand at the SQL prompt:
  ```sql
  BEGIN;
  SET LOCAL app.current_user_id = '1';
  UPDATE application_status_history SET status_note = 'tamper';   -- must fail: append-only
  ROLLBACK;
  ```
- [ ] The deviation register lists every place the design departs from docket §5, with reason and risk.
- [ ] The rule-compliance table is filled in for all 10 rule groups plus the reserved-keyword check.
- [ ] **B23 sign-off:** once all six milestones pass and every checklist above is ticked, the team signs the block at the end of `phase1-design.md`.

---

## Quick reference

| Milestone | Command | Pass signal |
|---|---|---|
| All | `./run_phase1.sh` | `VERIFIED: m1 m2 m3 m4 m5 m6 m7 m8 m9 m10 m11 m12 m13 m14 m15 m16 m17 m18 m19 m20`, exit 0 |
| M1 Provider | `./run_phase1.sh m1` | 3 PASS |
| M2 Entities | `./run_phase1.sh m2` | 7 PASS, no orphan tables |
| M3 Relationships | `./run_phase1.sh m3` | 33 relationships, 895 FKs explicit |
| M4 Columns | `./run_phase1.sh m4` | 10 PASS |
| M5 Design | `./run_phase1.sh m5` | 12 PASS, `MILESTONE 5 CHECKS PASSED` |
| M6 Constraints | `./run_phase1.sh m6` | 45 PASS, `MILESTONE 6 CHECKS PASSED` |
| M7 Entities (Phase 2) | `./run_phase1.sh m7` | 5 PASS — see [phase2-design.md](phase2-design.md#verification) |
| M8 Relationships (Phase 2) | `./run_phase1.sh m8` | 33 relationships, 895 FKs explicit |
| M9 Columns (Phase 2) | `./run_phase1.sh m9` | 7 PASS |
| M10 Constraints (Phase 2) | `./run_phase1.sh m10` | 60 PASS, `MILESTONE 10 CHECKS PASSED` |
| M11 Entities (Phase 3) | `./run_phase1.sh m11` | 6 PASS — see [phase3-design.md](phase3-design.md#verification) |
| M12 Relationships (Phase 3) | `./run_phase1.sh m12` | 40 relationships, 895 FKs explicit, 3 composite-FK rejections |
| M13 Columns (Phase 3) | `./run_phase1.sh m13` | 11 PASS |
| M14 Constraints (Phase 3) | `./run_phase1.sh m14` | 75 PASS incl. the concurrent-login test, `MILESTONE 14 CHECKS PASSED` |
| M15 Entities (Phase 4) | `./run_phase1.sh m15` | 8 PASS — see [phase4-design.md](phase4-design.md#verification) |
| M16 Relationships (Phase 4) | `./run_phase1.sh m16` | 40 relationships, 895 FKs explicit, star-schema rules |
| M17 Columns (Phase 4) | `./run_phase1.sh m17` | 12 PASS |
| M18 Constraints (Phase 4) | `./run_phase1.sh m18` | 48 PASS, `MILESTONE 18 CHECKS PASSED` |
| M19 Seed data (Phase 5) | `SEED_SCALE=1 ./run_phase1.sh m19` (rebuilds and seeds, ~1 h 40 min; `SEED_SCALE=0.01` for a 1-minute check) | 12 PASS, `MILESTONE 19 CHECKS PASSED` — see [phase5-design.md](phase5-design.md) |
| M20 Queries and validation (Phase 5) | `./run_phase1.sh --no-build m20` on the seeded database; `./run_report.sh` writes the reports | 26 queries return rows, 26 validation rules at 0, `MILESTONE 20 CHECKS PASSED` |

If a check fails: the line before the error names the table, column or rule. Fix the DDL in `sql/0x_*.sql`, then re-run that milestone. A plain `./run_phase1.sh mN` always rebuilds from scratch.

> Counts above reflect the full build (Phases 1–5 so far; schema complete). The runner builds every `sql/NN_*.sql` and runs every `sql/tests/mN_*.sql`.
