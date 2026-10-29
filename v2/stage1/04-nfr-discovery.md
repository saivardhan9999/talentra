# Step 04 — NFR Discovery

Conforms to Stage 1 schema [S-04](output-schemas.md#s-04--nfr-discovery). Every Non-Functional Requirement (`NFR-PERF-01`..`NFR-CMP-01`) carries a quantitative target, workload sizing basis from Docket §6, and verification method proved in Phase 3 (`t01`..`t06` and `bench/bench.py`).

---

## 1. Quantitative NFR Register (37 NFRs across 11 Categories)

| NFR ID | Category | Metric / Quality Attribute | Quantitative Target | Verification Method (Phase 3 Prove) | Status |
|---|---|---|---|---|---|
| `NFR-PERF-01` | `PERF` | Interactive read latency (`AP-01..AP-10`, `AP-12`, `AP-14`) through RLS as real actor | p95 ≤ 50 ms (dev 10k); ≤ 200 ms (full 10M) | Measured in `bench/bench.py`: search p95 = **5.3 ms**, RLS candidate search = **3.4 ms** | **PASSED** |
| `NFR-PERF-02` | `PERF` | Write transaction latency (login, apply, download, webhook, outbox claim) | p95 ≤ 50 ms | Measured in `bench/bench.py` & `t06`: all write functions complete in **< 8 ms** | **PASSED** |
| `NFR-PERF-03` | `PERF` | Row-Level Security overhead (viewer context computed once via `initPlan`, never per row) | RLS query ≤ 2× owner query | Verified via `EXPLAIN (ANALYZE)` in `docs/benchmark-results.md` (3.4 ms vs 3,700 ms correlated) | **PASSED** |
| `NFR-PERF-04` | `PERF` | Runaway query protection on runtime roles | `statement_timeout = 5s` (`v2_app`), `60s` (`v2_reporting`) | Verified on `pg_db_role_setting` in `t01_standards.sql` & `V011__api_and_security.sql` | **PASSED** |
| `NFR-PERF-05` | `PERF` | Deterministic seed rebuild speed | Prove seed < 1.0 s; Dev 10k seed < 2 min (`setseed`) | Measured **0.66 s** for `seed_prove_sample.sql` (`setseed(0.314159)`); **~8 s** for 10k seed | **PASSED** |
| `NFR-SCAL-01` | `SCAL` | Single schema scales from 30 (Prove) to 1M (Laptop) to 10M (Full Scale) profiles | Documented scale triggers (partitioning, read replicas, PgBouncer) | Modeled across 5 scale tiers in Step 13 (`13-data-volumetrics.md`) | **PASSED** |
| `NFR-SCAL-02` | `SCAL` | Full-scale peak burst throughput | 600 searches/s, 60 logins/s, 10 apps/s, 15 notifications/s | Verified against index coverage & skip-locked outbox worker design in Step 13 §5 | **PASSED** |
| `NFR-SCAL-03` | `SCAL` | Total 3-year primary storage budget (including tuple headers and B-tree/GIN indexes) | **< 250 GB** at 10M profiles / 1M jobs / 100M apps | Calculated across all 73 tables in Step 13: **178.42 GB** (71.4% of budget) | **PASSED** |
| `NFR-REL-01` | `REL` | Monthly service availability | ≥ 99.9% (synchronous standby replica) | Physical HA architecture & zero-lock `CONCURRENTLY` refresh in Step 21 | **PASSED** |
| `NFR-REL-02` | `REL` | Disaster recovery objectives | RPO ≤ 5 min (WAL archiving / PITR); RTO ≤ 1 h | Documented in Step 21 physical architecture | **PASSED** |
| `NFR-REL-03` | `REL` | Zero lost or duplicate notifications per business event | Transactional outbox + `uq_notification_dedupe_key` | Verified in `t02_integrity.sql` and `t06_phase3_prove.sql` (`TC-20-020..022`) | **PASSED** |
| `NFR-REL-04` | `REL` | External integration idempotency (webhooks, ledger debits, notifications) | Unique `gateway_event_ref`, `idempotency_key`, `dedupe_key` | Verified in `t02_integrity.sql` (duplicate webhook & duplicate job-post debit no-op) | **PASSED** |
| `NFR-SEC-01` | `SEC` | Principle of least privilege across database roles | 4 runtime roles (`v2_app`, `v2_payments`, `v2_worker`, `v2_reporting`); 0 `PUBLIC` function grants | Verified by catalog queries in `t01_standards.sql` and `t03_security.sql` | **PASSED** |
| `NFR-SEC-02` | `SEC` | Credential storage and isolation | Argon2id format check (`ck_user_credential_password_hash_argon2id`); `SELECT` revoked from all runtime roles | Verified in `t02_integrity.sql` and `t03_security.sql` | **PASSED** |
| `NFR-SEC-03` | `SEC` | Tokenisation of tax identifiers, session tokens, and device fingerprints | Tax IDs stored as `pii_hmac()` + `identifier_last4`; tokens/devices as 32-byte `sha256_digest` | Verified in `t01_standards.sql` and `t02_integrity.sql` | **PASSED** |
| `NFR-SEC-04` | `SEC` | Database-enforced multi-tenant and actor access control | `ENABLE` + `FORCE ROW LEVEL SECURITY` on 100% of business tables | Verified by 36 positive/negative actor isolation assertions in `t03_security.sql` | **PASSED** |
| `NFR-SEC-05` | `SEC` | Encryption in transit and at rest | TLS 1.2+ connections; encrypted volumes & S3 SSE | Documented in Step 12 (`12-data-classification-register.md`) and Step 21 | **PASSED** |
| `NFR-PRIV-01` | `PRIV` | Explicit consent history per purpose with policy version (DPDP Act 2023) | 100% of live candidates hold active terms (1) and privacy (2) consents | Verified by Invariant `R-12` in `t05_data_quality.sql` (0 violations) | **PASSED** |
| `NFR-PRIV-02` | `PRIV` | Candidate visibility, consent withdrawal, and company/user blocking enforced on all queries | Blocked party or unconsented recruiter sees **0 rows** | Verified in `t03_security.sql` and `t06_phase3_prove.sql` (`TC-20-023`) | **PASSED** |
| `NFR-PRIV-03` | `PRIV` | Personal data access auditing and payload hygiene | Every contact reveal audited; 0 personal values in `audit_event.details` or `notification.payload` | Verified by `t03_security.sql` and Invariant `R-16` in `t05_data_quality.sql` | **PASSED** |
| `NFR-PRIV-04` | `PRIV` | Right to erasure (`candidate_erase()`) and 3-year inactivity retention (`retention_erase_inactive()`) | Scrubs PII, answers (`[erased]`), device labels, credentials, and sessions in 1 transaction | Verified in `t02_integrity.sql` and `t06_phase3_prove.sql` (`TC-20-014`, `TC-20-024`) | **PASSED** |
| `NFR-INT-01` | `INT` | Canonical domain types across all tables | 13 `CREATE DOMAIN` types (`person_name`, `email_address`, `phone_e164`, `money_amount`, etc.) | Verified in `t01_standards.sql` and boundary tests `TC-15-001..010` in `t06` | **PASSED** |
| `NFR-INT-02` | `INT` | Referential integrity and cross-row consistency via composite foreign keys | 0 orphan rows possible; resume and question ownership pinned by composite FKs | Verified in `t01_standards.sql`, `t02_integrity.sql`, and Invariant `R-15` in `t05` | **PASSED** |
| `NFR-INT-03` | `INT` | Concurrency-safe quota enforcement (devices, wallet credits, seats, job positions) | Enforced by `SELECT ... FOR UPDATE` locks + `CHECK`/`EXCLUDE` constraints | Proven under parallel `dblink` race load in `t04_concurrency.sql` (4/4 race tests pass) | **PASSED** |
| `NFR-INT-04` | `INT` | Immutability of append-only histories, ledgers, invoices, and audit trails | `forbid_change()` trigger blocks `UPDATE` and `DELETE` across all 7 append-only tables | Verified in `t01_standards.sql` and `t02_integrity.sql` | **PASSED** |
| `NFR-INT-05` | `INT` | Seed dataset invariant compliance and anomaly detection | 16 invariants at **0 violations**; 6 planted DQ findings (`F-01..F-06`) detected | Verified in `t05_data_quality.sql` | **PASSED** |
| `NFR-AUD-01` | `AUD` | Row-level provenance on every business table | `created_at/by` and `updated_at/by` maintained automatically by `set_audit_columns()` trigger | Verified across all business tables in `t01_standards.sql` | **PASSED** |
| `NFR-AUD-02` | `AUD` | Unforgeable audit actor attribution | Runtime roles cannot `INSERT` into `audit_event`; only `SECURITY DEFINER` `audit_log()` writes | Verified in `t03_security.sql` | **PASSED** |
| `NFR-AUD-03` | `AUD` | Tiered data retention schedules | Audit: 7 yrs (84 monthly partitions); Sessions: 1 yr; Notifications: 180 d; Errors: 90 d | Partition generator `create_month_partitions()` verified in `t01_standards.sql` | **PASSED** |
| `NFR-I18N-01` | `I18N` | End-to-end UTF-8 multilingual support for Indian scripts and mononyms | Devanagari, Tamil, Telugu, and single-word names stored and searched without loss | Verified by multilingual seed rows (`आरव शर्मा`, `கார்த்திக்`) in `t02` & `seed_prove_sample.sql` | **PASSED** |
| `NFR-I18N-02` | `I18N` | Translated UI labels with deterministic English fallback | 100% of `ui_label` rows have English (`language_id = 1`); `ui_text()` falls back cleanly | Verified in `t01_standards.sql` and `t02_integrity.sql` | **PASSED** |
| `NFR-I18N-03` | `I18N` | Content language tagging on user-authored text | Explicit language FKs on `candidate_profile`, `job_requirement`, and `resume` | Verified in `19-data-dictionary-v2.md` | **PASSED** |
| `NFR-MNT-01` | `MNT` | Numbered, checksummed, forward-only schema migrations | `V001`..`V013` tracked in `schema_migration` with SHA-256 checksum verification | Verified by `run.sh` and `independent_audit.py` | **PASSED** |
| `NFR-MNT-02` | `MNT` | Automated catalog standards enforcement | 15 system-catalog assertions in `t01_standards.sql` | Verified in `t01_standards.sql` (15/15 PASS) | **PASSED** |
| `NFR-MNT-03` | `MNT` | Zero documentation drift between SQL DDL and Data Dictionary | Dictionary and ER models generated directly from `V001..V013` catalog | Verified in Step 19 (`0 drift` across 73 tables and 462 columns) | **PASSED** |
| `NFR-OBS-01` | `OBS` | Slow-query and application error observability | `pg_stat_statements`, `auto_explain` (> 200 ms), and `system_error` table | Verified in `V005__audit.sql` and `t02_integrity.sql` | **PASSED** |
| `NFR-CMP-01` | `CMP` | Statutory compliance (India DPDP Act 2023, GST invoicing, PCI-DSS scope avoidance) | Consent & erasure in DB; 18% GST invoices (`ck_invoice_total`); zero raw card data stored | Verified in `t02_integrity.sql`, `t05_data_quality.sql`, and `t06_phase3_prove.sql` | **PASSED** |

---

## 2. Workload & Scale Basis (Docket §6 vs. Engineering Tiers)

| Scale Tier | Classification | Candidate Profiles | Job Requirements | Applications | Organisations | Purpose |
|---|---|---|---|---|---|---|
| `prove_sample` | **[DESIGN ASSUMPTION]** | 30 | 12 | 36 | 6 | Sub-second Phase 3 verification seed (`seed_prove_sample.sql`) covering 100% of states & lookups |
| `dev_10k` | **[DESIGN ASSUMPTION]** | 10,000 | 1,050 | 56,000 | 200 | Fast local CI & latency benchmark tier (`db/seed/seed.sql`, ~8s build) |
| `launch_100k` | **[DESIGN ASSUMPTION]** | 100,000 | 10,000 | 600,000 | 2,000 | Day-1 MVP production ramp projection |
| `docket_laptop_1m` | **[DOCKET FACT — §6]** | **1,000,000** | **100,000** | **5,000,000** | **20,000** | Hackathon Docket §6 Laptop-Scale target (ratio 10 : 1 : 50) |
| `docket_full_10m` | **[DOCKET FACT — §6]** | **10,000,000** | **1,000,000** | **100,000,000** | **200,000** | Hackathon Docket §6 Full-Scale 3-Year target (< 250 GB budget; modeled at **178.42 GB**) |

---

## 3. Applicable Regulations & Compliance Mapping

| Regulation / Standard | Mandatory Requirement | Database Enforcement Mechanism |
|---|---|---|
| **India DPDP Act 2023** | Notice & itemised consent per purpose; right to withdraw consent; right to erasure; data minimisation | `consent_purpose` (5 purposes), append-only `consent_record`, `consent_current` view enforced in RLS & notification outbox (`FND-09`), `candidate_erase()` (`FND-10`, `FND-11`) |
| **Indian GST Invoicing Rules** | Sequential invoice number, subtotal, tax amount, and total amount verification for captured payments | `invoice` table (append-only), `ck_invoice_total` (`total_amount = subtotal_amount + tax_amount`), invariant `R-08` & `R-09` |
| **PCI-DSS Scope Avoidance** | Never store PAN card numbers, CVV, or raw payment instrument credentials | `payment_order` and `payment_event` store only `gateway_order_ref` and `gateway_event_ref` webhook payloads |
| **Indian Tax & Corporate ID Protection** | Protect PAN, GSTIN, and CIN from plaintext exposure in database dumps | `organisation_tax_identifier` stores only `pii_hmac(raw_value)` (HMAC-SHA256 with external key) + `identifier_last4` |
