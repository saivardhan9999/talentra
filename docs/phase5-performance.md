# Talentra — Performance Report (Milestone 21)

B70 baseline latency · B71–B73 one index per module group with before / after, and the partitioning strategy · B74 extrapolation to full scale.
Raw numbers: `perf/results/*.json` · harness: `perf/benchmark.py` · experiment queries: `perf/queries/` · automated check: `sql/tests/m21_performance.sql`.

## Method (B70)

The method follows what B70 lists: hardware, dataset size, query text, number of runs, p50 / p95 / p99.

| Item | Value |
|---|---|
| Hardware | Intel Core i5-12450H (8 cores / 12 threads), 15.7 GB RAM, Intel NVMe SSD, Windows 11 |
| Database host | Docker Desktop 29.8, PostgreSQL 16.15 in a container limited to **4 CPUs and 5 GB RAM**, `--shm-size=1g` |
| PostgreSQL settings | `shared_buffers` 1 GB (on a 5 GB container), `work_mem` 64 MB, `maintenance_work_mem` 512 MB, `effective_cache_size` 3 GB, `max_parallel_workers_per_gather` 2, `max_wal_size` 4 GB, `random_page_cost` 4, JIT on |
| Dataset | laptop scale: 1,000,000 profiles, 100,000 requirements, 4,999,885 applications, 10.5M status-history rows; database 14 GB. Second point: the same generator at 1% (10k profiles, 49,890 applications) |
| Query text | the fixed query set `sql/queries/fixed/` (the ten non-transactional queries), parameters resolved from the data by `sql/queries/params.sql` |
| Runs | 3 warm-up runs discarded, then **50 measured runs** per query (30 for the index experiments) |
| Measure | psql `\timing` per execution, inside the container over the local socket: server execution plus protocol, results discarded. Reported min / p50 / p95 / p99 / max in ms |
| Cache state | warm: the warm-up brings the query's pages into shared buffers or the OS cache. Cache hit ratio during the runs: 99.2%. Cold behaviour is covered in the extrapolation |
| Role | owner (pure query cost). Row-level security overhead was measured separately (below) |

## Baseline: top ten queries at laptop scale (B70)

Final figures, with the M21 changes in place. Q12 changed (454 → 173 ms p50); the others are unaffected by them.

| Query | Rows | p50 | p95 | p99 | max |
|---|---|---|---|---|---|
| Q1 job search (full text + city + salary) | 20 | 4.3 | 7.0 | 7.2 | 7.3 |
| Q2 candidate search (skill + city + experience) | 50 | 55.9 | 63.9 | 83.3 | 87.4 |
| Q3 a candidate's applications, Tamil labels with fallback | 5 | 0.9 | 1.5 | 2.0 | 2.1 |
| Q4 recruiter pipeline for the busiest requirement | 11 | 0.6 | 1.0 | 1.2 | 1.2 |
| Q8 status lookup with translation fallback | 12 | 0.5 | 0.7 | 0.8 | 0.8 |
| Q9 skill lookup from typed aliases | 3 | 0.5 | 1.0 | 1.3 | 1.4 |
| Q10 hiring funnel from the aggregate | 7 | 0.2 | 0.4 | 0.4 | 0.5 |
| Q11 duplicate candidate detection | 25 | **1,979** | 2,123 | 2,274 | 2,393 |
| Q12 time to hire by industry | 30 | 173 | 194 | 221 | 222 |
| Q13 profile download history with the charge | 1 | 1.3 | 2.0 | 2.5 | 2.6 |

All interactive queries except Q2 answer in **under 8 ms at p99**. The two outliers are reporting queries over whole tables.

## Row-level security cost (found by the demo UI, fixed before M21)

The application role reads through row-level security, so its cost counts as performance. Measured as `talentra_app` at laptop scale:

| Change | Before | After |
|---|---|---|
| Policy helper calls ran once per row; now wrapped in `(SELECT …)` and evaluated once per query (all 53 policies) | job search 3.7 s | 0.15 s |
| Candidate visibility per row via `app_can_see_candidate(id)`; now inline, with two once-per-query helpers | name search timed out at 15 s | see I5 below |

Access results are unchanged (M10 and M18 re-run and passing).

## One index per module group (B71–B73)

The same harness was run before the index (or change) existed and after it. Queries are in `perf/queries/`.

| Module | Change | Query it serves | Before p50 / p95 | After p50 / p95 | Gain |
|---|---|---|---|---|---|
| **Administration** (B71) | `idx_audit_event_organisation_id (organisation_id, occurred_at) WHERE organisation_id IS NOT NULL` | I1: an account admin's last 30 days of sensitive changes | 80.8 / 90.8 ms | 1.2 / 1.5 ms | **67×** |
| **Licences** (B72) | `idx_login_attempt_attempted_identifier_hmac (attempted_identifier_hmac, attempted_at)` | I2: brute-force check, failures for the identifier just typed in the last 15 minutes, **on every login** | 2.7 / 3.4 ms | 0.8 / 1.7 ms | 3.4× today, flat at any volume |
| **Notifications** (B73) | `idx_notification_delivery_provider_message_ref (provider_message_ref) WHERE NOT NULL` | I3: a provider callback finds its delivery by message id | 25.4 / 28.5 ms | 0.8 / 1.0 ms | **31×** |
| **Analytics** (B73) | `idx_fact_application_joined_date_id (joined_date_id) WHERE NOT NULL` | Q12: time to hire by industry | 458.8 / 493.9 ms | 162.1 / 176.9 ms | 2.8× |
| **Profile** (extra) | ranked name search through `app_search_candidates_by_name()` (definer rights, the same visibility function per match, best matches first, stops at the limit) | I5: a recruiter searches a common name, best matches first | 1,654 / 1,719 ms | 30.2 / 33.3 ms | **55×** |

**Why each one.**
- **I1:** without the index, every recent audit partition is read in full: 3.7M events, the current month holding most of them. The partial index covers only events with an organisation.
- **I2:** the old plan read the whole current month of the *user* index (923 pages) to find nothing; the new one reads a handful of pages. It runs on every login, and login traffic grows linearly with users, which is why it's justified even at 2.7 ms today.
- **I3:** a callback carries no date, so partition pruning can't help; without the index all 26 partitions are scanned. Write cost: the reference is set once, when the message is handed to the provider. Later status callbacks don't change it, so they stay HOT updates (M18's write path is kept).
- **Q12:** hires are 1.5% of applications. The remaining 162 ms is joining 75k hires to their job dimension and computing medians, which is real work. The full-scale fix is a pre-computed aggregate (see B74).
- **I5:** under row-level security, PostgreSQL may not run the trigram filter (not leakproof) before the policy checks, so a ranked search scanned all 1M profiles. The function walks matches best first through the trigram index and applies `app_can_see_candidate()` to each before returning it. **Correctness is checked by m21:** at laptop scale, 100 results; none hidden from the recruiter; no better visible match skipped, of 4,229 visible matches.

**Write cost of the new indexes.**
- **Audit:** one more index entry per audited change, only for events that have an organisation.
- **Login attempts:** one entry per attempt. The table is append-only, and partitions are dropped whole when retention ends.
- **Delivery reference:** one entry per delivery, written once.
- **Fact table:** one entry per hire, written by the load job.

## Partitioning strategy (B73)

| Table | Strategy | Measured at laptop scale |
|---|---|---|
| `application_status_history` (10.5M rows, 1.6 GB) | **monthly range on `changed_at`** (Phase 1) | status changes in the last 7 days: **317 ms / 31k pages** pruned (21 of 25 partitions removed) vs 655 ms / 116k pages without pruning. Retention drops a month instantly instead of deleting millions of rows; append-only protection per partition (M18) |
| `notification_delivery` (800k rows, 287 MB) | **monthly range on `queued_at`** (Phase 4) | deliveries in the last 24 hours by status: **44 ms** pruned vs 122 ms without pruning. Callbacks by message id use the new index across partitions (0.8 ms) |
| `notification` | **not partitioned** (D22) | it is the foreign-key target for deliveries. A partitioned parent would force a timestamp column into the FK, which the naming rule (FK columns end in `_id`) forbids |
| `application` (5M rows, 1.5 GB) | **not partitioned**, by decision | every access path is a direct index lookup: by requirement 26 ms (cold, 768 rows), by candidate 2.1 ms, by id 1 ms. Range-partitioning by date would make "this candidate's applications" probe every partition. Six tables reference `application(id)` (history, interviews, offers, placements, answers, referral events), and all would need composite FKs including the partition key. **Revisit:** hash partitioning on `job_requirement_id` if maintenance (vacuum, index rebuild) of a single 100M-row table becomes the bottleneck, not query latency |
| other history (`profile_view_event`, `candidate_activity_log`, `job_search_event`, `audit_event`, `login_attempt`, `profile_download_event`, `system_error_event`) | monthly range, append-only | same pattern: recent-window reports prune, retention drops partitions |

## Extrapolation to full scale (B74)

Target: **10M profiles (×10), 1M requirements (×10), 100M applications (×20)** over laptop scale. The model rests on two measured points, 1% and 100% of laptop scale (×100 apart), using the same generator, schema, settings and queries:

| Query | 1% p50 | laptop p50 | Measured growth for ×100 data | Behaviour | Projected at full scale |
|---|---|---|---|---|---|
| Q3, Q4, Q8, Q10, Q13, I1, I2, I3 (point lookups) | 0.3–1.1 ms | 0.2–1.3 ms | **flat** | B-tree lookups; depth grows by about one level per ×100–×300 | 1–5 ms (extra random reads once indexes outgrow RAM, see below) |
| Q1 job search | 0.6 ms | 4.3 ms | ~linear in matching postings (GIN posting lists, sort of matches) | linear in requirements | **~20–50 ms** |
| I5 ranked name search | 4.9 ms | 30.2 ms | ×6 (sublinear: matches grow, the visibility walk stops at the limit) | linear in name matches | **~150–300 ms** for very common names |
| Q2 candidate search | 1.0 ms | 55.9 ms | ×56 (linear: sorts every matching candidate in the most popular city) | linear in profiles | **~0.6 s** |
| Q12 time to hire | 1.9 ms | 173 ms | ×91 (linear in hires) | linear in applications (×20) | **~3.5 s** |
| **Q11 duplicate detection** | 22 ms | **1,979 ms** | **×90 (linear)** | full scan of all primary phones + hash aggregate over every (phone, name) group | **~30–60 s** (see below) |

**Size and cache.**
- **Size:** laptop scale is 14 GB, made of 8.3 GB growing with profiles and activity, 4.4 GB with applications, and 1.8 GB of reference, organisation and job data. That projects to **~180 GB** (8.3 × 10 + 4.4 × 20 + 1.8 × ~5).
- **Cache:** today the working set of the interactive queries fits in memory (cache hit ratio 99.2%). At full scale the application indexes alone are about 16 GB, larger than the RAM of a laptop-class server, so point lookups will read leaf and heap pages from NVMe (~0.1 ms each). Hence 1–5 ms, not sub-millisecond; still interactive.

**The query that degrades first: Q11, duplicate candidate detection.**
1. It is the only query that must read every primary phone and every profile name. No index can avoid that for a "find all groups" question, so its cost is linear in profiles: measured ×90 for ×100 data.
2. It groups by (phone, normalised name). At 10M profiles the hash table holds ~10M groups, far beyond `work_mem` (64 MB), so PostgreSQL switches to multi-batch hashing that spills to disk. That adds I/O on top of the ×10 scan, which is why the projection is 30–60 s rather than a plain ×10 (~20 s).
3. **What to do at full scale:** stop running it as a sweep. Keep a dedupe key (primary phone + normalised name) on each profile with a b-tree index. Check it at registration, a single index probe in milliseconds, and report duplicates from that key incrementally.

**Next to degrade:**
- **Q12, about 3.5 s:** move to a pre-computed monthly aggregate refreshed with the others (`refresh_aggregates()`, M18).
- **Q2, about 0.6 s:** add a partial composite index on (`current_city_id`, `last_active_at DESC`) for actively looking, visible profiles, so the top 50 are read in order instead of sorting every match.

Neither blocks the laptop-scale deliverable, so both are recorded here rather than built.
