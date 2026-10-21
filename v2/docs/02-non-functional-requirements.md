# 02 — Non-functional requirements

Every NFR is measurable and says how it is verified. "Dev" means the 10k-profile build on a laptop; "full" means the docket's target of 10M profiles, 1M jobs and 100M applications. Full-scale figures are projections from the measured model in [06 §7](06-physical-model.md#7-performance).

## Performance (PERF)

| ID | Requirement | Target | Verified by | Status |
|---|---|---|---|---|
| NFR-PERF-01 | Interactive reads (AP-01..AP-10, AP-12, AP-14) answer quickly, through row-level security, as the real actor | p95 ≤ 50 ms dev; ≤ 200 ms projected full | `./run.sh bench` ([results](benchmark-results.md)) | **Met dev** (worst p95: 23 ms). Full: met except AP-05 name search (projected seconds), which has a planned fix |
| NFR-PERF-02 | Write transactions (login, apply, download, webhook, outbox claim) are short | p95 ≤ 50 ms | bench AP-07, AP-11, AP-13 | **Met** (≤ 2 ms) |
| NFR-PERF-03 | Row-level security adds little cost: viewer context computed once per query, never per row | RLS query ≤ 2× the owner query | plans show init plans; regression found and fixed (AP-05 3.7 s → 17.6 ms) | **Met** |
| NFR-PERF-04 | No runaway statement from the API | `statement_timeout` 5 s (`v2_app`), 60 s (`v2_reporting`) | V001 | **Met** |
| NFR-PERF-05 | The dataset rebuilds quickly and deterministically | dev seed < 2 min, same data every run (`setseed`) | `./run.sh reset` | **Met** (48 s) |

## Scalability (SCAL)

| ID | Requirement | Target | Verified by | Status |
|---|---|---|---|---|
| NFR-SCAL-01 | The same schema serves 10k to 10M profiles; scale steps are known in advance | documented trigger for each scale step (partitioning, search engine, replica, pooling) | [06 §6–7](06-physical-model.md#6-partitioning) | **Met** (design) |
| NFR-SCAL-02 | Full-scale peak throughput | 600 searches/s, 60 logins/s, 10 applications/s, 15 notifications/s | capacity model in [03 §3](03-data-requirements.md#3-volumetrics-and-capacity) | Projected; load test in backlog |
| NFR-SCAL-03 | Storage stays within a single primary at full scale | ~250 GB including indexes | capacity model | Projected |

## Reliability and recovery (REL)

| ID | Requirement | Target | Verified by | Status |
|---|---|---|---|---|
| NFR-REL-01 | Availability | 99.9% monthly (managed PostgreSQL with synchronous standby) | operations | Production concern |
| NFR-REL-02 | Recovery objectives | RPO ≤ 5 min (WAL archiving, point-in-time recovery); RTO ≤ 1 h | restore drill | **Dev drill done**: `pg_dump` 2.2 s / 17.7 MB, parallel restore 2.8 s, all 16 data rules pass on the copy ([06 §9](06-physical-model.md#9-backup-and-recovery)) |
| NFR-REL-03 | No notification is lost or sent twice for one event | outbox in the same transaction; at-least-once delivery; dedupe key per event | V009, t02 | **Met** |
| NFR-REL-04 | Every interaction with an external system is idempotent | webhook: unique gateway event id; ledger: idempotency key; notifications: dedupe key | t02 (redelivered webhook, replayed key) | **Met** |

## Security (SEC)

| ID | Requirement | Target | Verified by | Status |
|---|---|---|---|---|
| NFR-SEC-01 | Least privilege | 4 runtime roles; no function executable by PUBLIC; column-level update grants; guarded writes only through definer functions with a pinned `search_path` | V011, t01, t03 | **Met** |
| NFR-SEC-02 | Credentials | argon2id hashes only (format-checked); unreadable by every runtime role | t01, t03 | **Met** |
| NFR-SEC-03 | Sensitive identifiers | tax ids as HMAC-SHA256 (key held outside the database) plus last 4; session tokens and device ids as SHA-256 | V003, V004 | **Met** |
| NFR-SEC-04 | Privileges enforced in the database | RLS on every business table; 36 access checks across all actors | t01, t03 | **Met** |
| NFR-SEC-05 | Encryption in transit and at rest | TLS 1.2+ to the database; volume encryption; object storage with server-side encryption | operations | Production concern |

## Privacy (PRIV)

| ID | Requirement | Target | Verified by | Status |
|---|---|---|---|---|
| NFR-PRIV-01 | Consent recorded per purpose with policy version and evidence (DPDP Act 2023) | 100% of candidates have current terms and privacy consent | t05 R-12 | **Met** |
| NFR-PRIV-02 | Visibility and blocking apply to every query, not only to screens | the blocked party sees 0 rows | t03 | **Met** |
| NFR-PRIV-03 | Access to personal data is audited; no personal values in audit details or notification payloads | every contact reveal audited; 0 payloads with contact data | t03, t05 R-16 | **Met** |
| NFR-PRIV-04 | Erasure on request, and after 3 years of inactivity | personal data removed in one transaction; others' records kept anonymised | `candidate_erase`, `retention_erase_inactive`, t02 | **Met** (scheduler runs it) |

## Data integrity (INT)

| ID | Requirement | Target | Verified by | Status |
|---|---|---|---|---|
| NFR-INT-01 | One standard domain per kind of data (name, email, phone, money, text sizes, coordinates, hashes) | every matching column uses the domain | V001, t01 | **Met** |
| NFR-INT-02 | Every relationship is a declared foreign key with a stated delete rule; cross-row consistency through composite keys | 0 orphan rows possible | catalogue, t02 | **Met** |
| NFR-INT-03 | Limits and concurrency rules are enforced by constraints or row locks, never only by the application | seats, devices, credits and positions hold under parallel load | t04 (4 races) | **Met** |
| NFR-INT-04 | Histories, ledgers and the audit trail are append-only | UPDATE / DELETE refused for everyone | t01, t02 | **Met** |
| NFR-INT-05 | The seed respects every invariant and plants the documented data-quality issues | 16 rules at 0 violations; 6 findings detected | t05 | **Met** |

## Auditability (AUD)

| ID | Requirement | Target | Verified by | Status |
|---|---|---|---|---|
| NFR-AUD-01 | Who and when for every business row | `created_at/by`, `updated_at/by` on every business table, set by trigger | t01 | **Met** |
| NFR-AUD-02 | The actor of an audit event cannot be forged | only `audit_log()` writes, taking the actor from the transaction | t03 | **Met** |
| NFR-AUD-03 | Retention | audit 7 years (monthly partitions dropped whole); errors 90 days; ended sessions 1 year; notifications 180 days | V005, [03 §5](03-data-requirements.md#5-retention-and-lifecycle) | Designed; scheduler jobs listed in [06 §11](06-physical-model.md#11-operations) |

## Internationalisation (I18N)

| ID | Requirement | Target | Verified by | Status |
|---|---|---|---|---|
| NFR-I18N-01 | UTF-8 end to end; names in any script and word order | Devanagari, Tamil and mononyms stored and searched | seed, `person_name` | **Met** |
| NFR-I18N-02 | UI labels translated, with fallback to English | every label has English; `ui_text()` falls back | t01, t02 | **Met** |
| NFR-I18N-03 | User content stored once, with its language when known | language columns on profile, job description, resume | V006, V007 | **Met** |

## Maintainability and operations (MNT, OBS, CMP)

| ID | Requirement | Target | Verified by | Status |
|---|---|---|---|---|
| NFR-MNT-01 | Versioned schema changes | numbered, checksummed, forward-only migrations; an edited applied migration is refused | `run.sh migrate` | **Met** |
| NFR-MNT-02 | The data standards are enforced by tests, not by review alone | 15 catalogue checks | t01 | **Met** |
| NFR-MNT-03 | Documentation cannot drift from the schema | dictionary and logical ERD generated from the catalogue | `./run.sh dictionary` | **Met** |
| NFR-OBS-01 | Query observability | `pg_stat_statements`, `auto_explain` over 200 ms, `system_error` table | [06 §11](06-physical-model.md#11-operations) | Production concern |
| NFR-CMP-01 | Compliance | DPDP Act 2023 (consent, erasure); GST invoices; no card data | NFR-PRIV-*, FR-BIL-07, C-06 | **Met** in schema |
