# Talentra — Phase 5 Design (Seeding, queries and validation)

**Scope so far:** Milestones 19–20, backlogs B60–B69.
**Status:** M19–M20 built and verified on PostgreSQL 16 at laptop scale (1M profiles, 5M applications, 16 GB): `SEED_SCALE=1 ./run_phase1.sh m19 m20`. M21 (performance), M22 (security) and M23 (backup, restore, sign-off) are next.

| File | Contents |
|---|---|
| `sql/seed/00_setup.sql` … `99_finish.sql` | The data generator (the docket counts it as a deliverable) |
| `sql/queries/fixed/q01…q13` | Fixed query set (B65) |
| `sql/queries/module/a*, b*, c*` | Module queries (B67–B69) |
| `sql/queries/validation.sql` | Seed validation against docket Section 5 (B66) |
| `sql/tests/m19_seed.sql`, `m20_queries.sql` | Milestone checks |
| `run_report.sh` | Writes `docs/phase5-query-report.md` and `docs/phase5-seed-validation.md` from the seeded database |
| `docs/coverage-gap-register.md` | Competitive coverage benchmark (Naukri, Monster, LinkedIn) and the gap register |

---

## Milestone 19 — Seed data (B60–B64)

### How the generator works

- **Inside PostgreSQL, set-based.** Every step is `INSERT … SELECT … FROM generate_series(…)`, so millions of rows are written without a client round trip per row. That keeps a laptop-scale load within the hour while every constraint, foreign key and trigger stays switched on.
- **Deterministic.** Every value is derived from a row number through `seed.r(row, salt)`, a hash mapped to [0, 1). The same scale always produces the same data, so query plans, findings and reports are reproducible.
- **Scalable.** `SEED_SCALE` multiplies every volume. Scale 1 is laptop scale; 0.01 is used while developing. The scale is stored on the database (`talentra.seed_scale`) and M19 checks the volumes against it.
- **Skewed like real data.** `seed.skew()` favours low ranks: metros over small towns, common skills over rare ones, large employers over small ones, popular requirements over the long tail.
- **Rules stay on.** The seed is just another writer. Seats respect `max_users`. Logins go through `app_open_session()`, so the device limit refuses some of them and records it. Sourcing decisions are taken as the requirement's employer, because the rule checks who acts. Gig assignments go through the exclusion constraint one by one, so overlap attempts are rejected and logged. The wallet ledger trigger computes every balance.
- **One documented exception.** The two application-pipeline triggers stamp `now()` on every status change. Walking 5M applications through the pipeline would put all their history at the seed's instant. For the bulk load only, those two triggers are paused and each application's history is written directly with real dates (`seed.path`). M20 then proves every seeded history is a legal path through `application_status_transition`, starts in an initial status and ends at the current one.
- **Helpers are temporary.** They live in schema `seed`, which `99_finish.sql` drops after a final `ANALYZE`.

### Stated distributions (laptop scale)

| Area | Volume | Distribution |
|---|---|---|
| Master data | 36 states, 106 cities with coordinates, 30 industries, 46 job roles, 90 skills + multilingual aliases, 32 qualifications, 25 fields, 300 institutions | real Indian geography in population order |
| Candidates | 1,000,000 profiles | names 72% Latin script, 28% in seven Indian scripts (Devanagari Hindi and Marathi, Tamil, Telugu, Kannada, Malayalam, Bengali); 80% "given family", 10% "given initial", 10% single name; 20% freshers; 40% disclose salary; 85% public / 12% employers only / 3% hidden; 0.5% soft-deleted; 10% legacy imports |
| Duplicates | 2% of profiles | second registrations of an earlier person: same name and phone, plus-addressed email; half flagged, half left for detection |
| Profile detail | ~4M skills, ~2.5M education + work rows, ~3M languages + locations, 700k resumes | 2–6 skills, 1–2 education rows, 0–3 jobs, 70% with a resume |
| Organisations | 20,000 (+ locations, GSTINs, ~84k employer / recruiter / admin users) | 85% direct employers; size skewed small; 60% verified; 5% subsidiaries; 2% of recruiters moved company |
| Requirements | 100,000 | 45% open, 20% closed, 15% filled, 5% each on hold / draft / pending / cancelled; 15% open to consultants; 5% in Hindi |
| Applications | ~5,000,000 (+ ~10M history rows) | popularity skewed; 15 pipeline paths: 30.5% still applied, 38% rejected at some stage, 6% withdrawn, 1.5% joined …; interviews, offers and placements for the stages reached |
| Activity | 1M saved jobs, 2M searches, 3M activity events, 2M+ profile views, talent lists, 20k referrals | spread over 18 months |
| Gig | 50k workers, 20k requests, ~60k applications, ~9k assignments | popular workers win overlapping gigs; overlaps rejected by the database and logged |
| Money | ~6k subscriptions with monthly / annual periods, orders, gateway events, invoices, wallets, ledger, refunds, 250k downloads and charged views | 5% failed payments; 2% of recharges partly refunded; every charge within the wallet's credits |
| Licences | seats up to `max_users`, 1–3 devices per seat holder, 10 past sessions each, live logins | users with more devices than allowed are refused at the limit |
| Sourcing | 10k consultant requests, outreach batches with 20–80 recipients | 50% accepted, 20% declined, 10% withdrawn, 20% pending |
| Notifications and shared | 500k notifications, ~800k deliveries, 20k community posts, 10k tickets, a credential per user, ~2.7M consent records, 20k blocks, audit events from every audited table | switched-off channels stored as suppressed by the write-path rule |
| Analytics | dimensions, 11 facts, 4 aggregates | loaded from the source tables; 5% of organisations carry an earlier SCD 2 version |

### Data-quality issues planted on purpose

Real data migrated from legacy systems is messy, and the queries and validation have to cope with it. The seed carries these issues deliberately. Each is detected and reported in M20 and listed in the coverage gap register (Q1–Q4):

| Issue | Share |
|---|---|
| Duplicate registrations (same person, same phone, second account) | 2% of profiles, half unflagged |
| Names with stray whitespace from an import | 1 in 3 duplicates |
| Single-word names (valid; breaks naive first / last parsing) | 10% |
| Joined applications without a placement (no open position left) | wherever hires exceeded positions |
| Late applications (after the posting expired) | where a candidate registered after the window |
| Unverified primary phones | 40% |
| Legacy-imported profiles and applications | 10% / 5% |

### Full-scale run (laptop: 4 CPUs and 5 GB RAM for Docker)

| Step | Time | Rows (main) |
|---|---|---|
| 02 candidates | 18 min | 1M profiles, 4M skills, 3M education + work, 3.1M languages + locations, 1.6M resumes + versions |
| 03 organisations | 1.5 min | 20k organisations, 85k mappings, 1M role grants |
| 04 jobs and applications | 32 min | 100k requirements, 4,999,885 applications, 10.5M history rows, ~1M interviews / offers / placements, 9.6M activity rows |
| 05 gig | 0.5 min | 50k workers, 20k requests, 8,289 assignments, 657 overlap attempts rejected |
| 06 money, licences, sourcing | 25 min | 748k sessions, 759k login attempts (7,366 refused at the device limit), 198k ledger entries, 200k downloads, 363k outreach recipients |
| 07 notifications and shared | 6 min | 1.29M credentials, 2.66M consent records, 3.7M audit events |
| 08 extras | 3.5 min | 2.5M section scores, 700k addresses / links / certifications |
| 09 analytics | 11 min | 1.1M dimension rows, 5M fact_application, 3M other fact rows |
| **Total** | **about 1 h 40 min** | **database 16 GB** |

**What full scale found that 1% did not.** Each of these stopped the load. The rule involved rejected the bad rows, the failed statement rolled back, the cause was fixed, and the load resumed from that statement:

| Found | Cause | Fix |
|---|---|---|
| "out of shared memory" while loading 175k paid downloads | **Schema design flaw (M14):** the one-charge-per-entry rule took an advisory lock per row, each holding a shared lock-table slot until commit | Row lock on the ledger entry instead (`SELECT … FOR UPDATE` with definer rights): same guarantee, no lock-table use. M14 re-verified, including the concurrent-login test |
| "could not resize shared memory segment" | Docker's 64 MB `/dev/shm` too small for parallel hash joins | Container recreated with `--shm-size=1g` (same data volume) |
| outreach rejected: "needs membership of its organisation" | Generator picked recruiters who had moved company; the M14 rule refused them | Generator picks current members only |
| block rejected by `ck_block_entry_date_range` | Generator could unblock before the block | Unblock time derived from the block time |
| validation: 655 applications before their job was published | Generator capped application time at "an hour ago", earlier than jobs published in the last hour | Generator fixed; the 12 affected jobs' `published_at` moved to an hour before their first application (a normal update) |
| validation finding: 27% late applications | Generator spread applications over 90 days while postings expire after 30–90 days | Generator now keeps applications inside the posting window; the current dataset keeps the inflated finding, reported as such |

### Running it

```sh
SEED_SCALE=1 MSYS_NO_PATHCONV=1 ./run_phase1.sh m19 m20   # rebuild, seed at laptop scale, verify
SEED_SCALE=0.01 MSYS_NO_PATHCONV=1 ./run_phase1.sh m19    # 1% for a quick check
./run_report.sh                                           # regenerate the M20 reports
```

**Container settings for laptop scale** (the database lives in Docker):
- **Shared memory.** Run the container with `--shm-size=1g`. Docker's 64 MB default is too small for parallel hash joins on the seeded tables, and the seed's first full run failed on it ("could not resize shared memory segment").
- **PostgreSQL tuning** (set with `ALTER SYSTEM`, stored on the data volume): `shared_buffers = 1GB`, `work_mem = 64MB`, `maintenance_work_mem = 512MB`, `max_wal_size = 4GB`, `effective_cache_size = 3GB`, for a container with 5 GB of RAM and 4 CPUs. M21 measures and justifies these.

---

## Milestone 20 — Queries and validation (B65–B69)

**Fixed query set (B65), 13 queries.** The ten non-transactional ones carry execution plans in the report:

| # | Query | Kind |
|---|---|---|
| Q1 | Job search: full text + city + salary floor | functional, performance |
| Q2 | Candidate search by skill, city, experience | functional, performance |
| Q3 | A candidate's application tracker, status labels in Tamil with fallback | functional, multilingual |
| Q4 | Recruiter pipeline per stage for the busiest requirement | functional, performance |
| Q5 | Shortlist an application (trigger checks the transition, writes history) | transactional |
| Q6 | Login at the device limit (refused, recorded, audited) | transactional |
| Q7 | Profile download paid with a credit (ledger + download in one transaction) | transactional |
| Q8 | Status lookup with translation fallback | lookup |
| Q9 | Skill lookup from typed aliases in English and Hindi | lookup, multilingual |
| Q10 | Hiring funnel from the aggregate | reporting |
| Q11 | Duplicate candidate detection | data quality, performance |
| Q12 | Time to hire by industry from the star schema | reporting, performance |
| Q13 | Profile download history with the credit deduction | rule group 10 |

**Module queries (B67–B69).**
- **Administration, Organisation and Gig:** recruiter mapping history, corporate hierarchy, gig worker leaderboard, overlap rejections.
- **Licences, Sourcing and Subscriptions:** seat utilisation, login outcomes including device-limit refusals, consultant acceptance, monthly revenue, wallet reconciliation.
- **Notifications, Analytics and shared items:** delivery rate per channel, current consent state, blocking lists, aggregate reconciliation.

**Results at full scale.** M20 passes: every query returns results. The seed validation shows **0 violations across 26 rules**, and all 7 findings are detected:

| Finding | Count |
|---|---|
| duplicate registrations not yet flagged | 9,833 |
| names with stray whitespace | 6,792 |
| joined without a placement | 7,692 |
| single-word names | 100,212 |
| unverified primary phones | 399,510 |
| legacy imports | 99,868 |
| late applications (inflated by the generator, see above) | 1,370,167 |

Execution times (from the report's `EXPLAIN ANALYZE`):

| Query | Time |
|---|---|
| Q1 job search | 8 ms |
| Q2 candidate search | 31 ms |
| Q3, Q4, Q8–Q10, Q13 | under 1 ms |
| Q12 time to hire by industry (star schema, 5M facts) | 0.8 s |
| Q11 duplicate detection (full scan of 1M phones) | 2.2 s |

Q11 and Q12 are the starting points for M21.

**Seed validation (B66).** `sql/queries/validation.sql` checks the data against docket Section 5 rule groups 2–5, the pipeline, temporal consistency, money and history (rule group 10) and the analytics layer. Rules must show 0 violations; findings are the planted issues above, each detected and counted. The results are in **[`docs/phase5-seed-validation.md`](phase5-seed-validation.md)**, and the queries with outputs and plans in **[`docs/phase5-query-report.md`](phase5-query-report.md)**.

**Coverage gap register.** **[`docs/coverage-gap-register.md`](coverage-gap-register.md)** compares Talentra with Naukri, Monster and LinkedIn element by element and lists the gaps (G1–G12) and data-quality items (Q1–Q4) with a decision for each. This benchmark is a docket §4 requirement that had not been produced in Phases 1–4; it was written for M20 because B66 validates against it.
