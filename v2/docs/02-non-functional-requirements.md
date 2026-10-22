# 02 — Non-functional requirements

Every NFR is measurable; how it is verified and its status are added after the rebuild. "Dev" means the 10k-profile build on a laptop; "full" means the docket's target of 10M profiles, 1M jobs and 100M applications. Full-scale figures are projections from the measured model in [06 §7](06-physical-model.md#7-performance).

## Performance (PERF)

| ID | Requirement | Target |
|---|---|---|
| NFR-PERF-01 | Interactive reads (AP-01..AP-10, AP-12, AP-14) answer quickly, through row-level security, as the real actor | p95 ≤ 50 ms dev; ≤ 200 ms projected full |
| NFR-PERF-02 | Write transactions (login, apply, download, webhook, outbox claim) are short | p95 ≤ 50 ms |
| NFR-PERF-03 | Row-level security adds little cost: viewer context computed once per query, never per row | RLS query ≤ 2× the owner query |
| NFR-PERF-04 | No runaway statement from the API | `statement_timeout` 5 s (`v2_app`), 60 s (`v2_reporting`) |
| NFR-PERF-05 | The dataset rebuilds quickly and deterministically | dev seed < 2 min, same data every run (`setseed`) |

## Scalability (SCAL)

| ID | Requirement | Target |
|---|---|---|
| NFR-SCAL-01 | The same schema serves 10k to 10M profiles; scale steps are known in advance | documented trigger for each scale step (partitioning, search engine, replica, pooling) |
| NFR-SCAL-02 | Full-scale peak throughput | 600 searches/s, 60 logins/s, 10 applications/s, 15 notifications/s |
| NFR-SCAL-03 | Storage stays within a single primary at full scale | ~250 GB including indexes |

## Reliability and recovery (REL)

| ID | Requirement | Target |
|---|---|---|
| NFR-REL-01 | Availability | 99.9% monthly (managed PostgreSQL with synchronous standby) |
| NFR-REL-02 | Recovery objectives | RPO ≤ 5 min (WAL archiving, point-in-time recovery); RTO ≤ 1 h |
| NFR-REL-03 | No notification is lost or sent twice for one event | outbox in the same transaction; at-least-once delivery; dedupe key per event |
| NFR-REL-04 | Every interaction with an external system is idempotent | webhook: unique gateway event id; ledger: idempotency key; notifications: dedupe key |

## Security (SEC)

| ID | Requirement | Target |
|---|---|---|
| NFR-SEC-01 | Least privilege | 4 runtime roles; no function executable by PUBLIC; column-level update grants; guarded writes only through definer functions with a pinned `search_path` |
| NFR-SEC-02 | Credentials | argon2id hashes only (format-checked); unreadable by every runtime role |
| NFR-SEC-03 | Sensitive identifiers | tax ids as HMAC-SHA256 (key held outside the database) plus last 4; session tokens and device ids as SHA-256 |
| NFR-SEC-04 | Privileges enforced in the database | RLS on every business table; 36 access checks across all actors |
| NFR-SEC-05 | Encryption in transit and at rest | TLS 1.2+ to the database; volume encryption; object storage with server-side encryption |

## Privacy (PRIV)

| ID | Requirement | Target |
|---|---|---|
| NFR-PRIV-01 | Consent recorded per purpose with policy version and evidence (DPDP Act 2023) | 100% of candidates have current terms and privacy consent |
| NFR-PRIV-02 | Visibility and blocking apply to every query, not only to screens | the blocked party sees 0 rows |
| NFR-PRIV-03 | Access to personal data is audited; no personal values in audit details or notification payloads | every contact reveal audited; 0 payloads with contact data |
| NFR-PRIV-04 | Erasure on request, and after 3 years of inactivity | personal data removed in one transaction; others' records kept anonymised |

## Data integrity (INT)

| ID | Requirement | Target |
|---|---|---|
| NFR-INT-01 | One standard domain per kind of data (name, email, phone, money, text sizes, coordinates, hashes) | every matching column uses the domain |
| NFR-INT-02 | Every relationship is a declared foreign key with a stated delete rule; cross-row consistency through composite keys | 0 orphan rows possible |
| NFR-INT-03 | Limits and concurrency rules are enforced by constraints or row locks, never only by the application | seats, devices, credits and positions hold under parallel load |
| NFR-INT-04 | Histories, ledgers and the audit trail are append-only | UPDATE / DELETE refused for everyone |
| NFR-INT-05 | The seed respects every invariant and plants the documented data-quality issues | 16 rules at 0 violations; 6 findings detected |

## Auditability (AUD)

| ID | Requirement | Target |
|---|---|---|
| NFR-AUD-01 | Who and when for every business row | `created_at/by`, `updated_at/by` on every business table, set by trigger |
| NFR-AUD-02 | The actor of an audit event cannot be forged | only `audit_log()` writes, taking the actor from the transaction |
| NFR-AUD-03 | Retention | audit 7 years (monthly partitions dropped whole); errors 90 days; ended sessions 1 year; notifications 180 days |

## Internationalisation (I18N)

| ID | Requirement | Target |
|---|---|---|
| NFR-I18N-01 | UTF-8 end to end; names in any script and word order | Devanagari, Tamil and mononyms stored and searched |
| NFR-I18N-02 | UI labels translated, with fallback to English | every label has English; `ui_text()` falls back |
| NFR-I18N-03 | User content stored once, with its language when known | language columns on profile, job description, resume |

## Maintainability and operations (MNT, OBS, CMP)

| ID | Requirement | Target |
|---|---|---|
| NFR-MNT-01 | Versioned schema changes | numbered, checksummed, forward-only migrations; an edited applied migration is refused |
| NFR-MNT-02 | The data standards are enforced by tests, not by review alone | 15 catalogue checks |
| NFR-MNT-03 | Documentation cannot drift from the schema | dictionary and logical ERD generated from the catalogue |
| NFR-OBS-01 | Query observability | `pg_stat_statements`, `auto_explain` over 200 ms, `system_error` table |
| NFR-CMP-01 | Compliance | DPDP Act 2023 (consent, erasure); GST invoices; no card data |
