# Architecture decision records

Short records of the decisions that shape the schema: context, decision, consequences, alternatives rejected. IDs are cited in the migrations.

### ADR-001 PostgreSQL 16
- **Context:** the docket allows PostgreSQL or MySQL; the design needs row-level security, exclusion constraints, partial and GIN indexes, generated columns, domains and transactional DDL.
- **Decision:** PostgreSQL 16 (kept from v1).
- **Consequences:** privileges, non-overlap and limits are enforced natively, and a migration is all-or-nothing. MySQL portability is given up.
- **Alternatives:** MySQL 8 has no RLS, no exclusion constraints and no transactional DDL.

### ADR-002 64-bit identity surrogate keys
- **Decision:** `bigint GENERATED ALWAYS AS IDENTITY` for business tables; `smallint` for lookups and small reference tables. Natural keys are unique constraints.
- **Consequences:** compact, ordered B-tree keys (good insert locality, smaller indexes than UUID); no key reuse. Ids are guessable, so the API must authorise every id it receives. RLS does this in the database too.
- **Alternatives:** UUIDv4 (random inserts, 2× key size); UUIDv7 (reasonable; revisit if ids are generated outside the database or shards merge).

### ADR-003 One lookup table per enumeration, labels translated by key
- **Decision:** 25 lookup tables of one shape (`id, code, ui_label_id, is_active, sort_order`), created by one procedure; display text in `ui_translation` per language, with fallback to English through `ui_text()`.
- **Consequences:** real foreign keys per enumeration (a job status can't hold an application status); labels in any language; values can be deactivated without deletion.
- **Alternatives:** PostgreSQL `ENUM` (no translations, painful to change); a single "one true lookup table" (no type safety, a known anti-pattern).

### ADR-004 Business rules live in the database
- **Decision:** constraints first. Then triggers for multi-row rules (pipeline, positions, seats, append-only, audit). Then `SECURITY DEFINER` functions for guarded writes (ledger, payments, downloads, sessions, registration). Row-level security on every business table.
- **Consequences:** every client and every bug in the API is held to the same rules, which docket section 3 requires; rules are tested in SQL (t02–t04). Logic is split between the API and the database, mitigated by keeping database functions small and tested.
- **Alternatives:** application-only checks (bypassable; race-prone for limits).

### ADR-005 The licence is the subscription period
- **Decision:** no separate licence table. A `subscription` row is one paid period and carries `max_seats` and `max_devices_per_user`, copied from the plan at purchase.
- **Consequences:** one place for limits; a repriced plan never changes a sold licence; non-overlap is a single exclusion constraint. Multiple concurrent licences per organisation (e.g. per department) would need a `licence` parent table.
- **Alternatives:** licence and subscription tables (v1); more joins for no current need.

### ADR-006 Partition only what needs it at this scale
- **Decision:** `audit_event` is range-partitioned by month (7-year retention by dropping partitions). `application`, `application_status_history` and `notification` are not partitioned in v2.
- **Consequences:** simple keys and foreign keys on the hottest tables; every access path is an index lookup (measured). **Revisit:** history beyond ~100M rows or when retention deletes hurt (monthly range on `changed_at`); notification beyond ~10M live rows (monthly, drop after 180 days); application only if vacuum or reindex of one table becomes the bottleneck (hash on `job_requirement_id`).
- **Alternatives:** partition everything up front (v1 did for history): composite keys everywhere, little gain at 10k–1M rows.

### ADR-007 Non-overlap by exclusion constraints
- **Decision:** `EXCLUDE USING gist` (with `btree_gist`) for subscription periods per organisation and memberships per user.
- **Consequences:** overlap is impossible even under concurrent inserts, with no trigger or lock code.

### ADR-008 Files outside, text bounded
- **Decision:** resumes in object storage (key and SHA-256 in `resume`); only job descriptions use the long-text domain (20,000 characters); everything else is ≤ 2,000.
- **Consequences:** a small database and cheap backups; file deletion on erasure goes through the outbox. The full-text vector covers the first 5,000 characters of a description.

### ADR-009 Credentials and identifiers never in clear
- **Decision:** password hashes in their own table (no runtime-role access; argon2id format checked). Tax identifiers as HMAC-SHA256 with a key supplied per session from the secret store, plus the last 4 characters. Session tokens and device ids as SHA-256.
- **Consequences:** a database dump leaks no usable secret; duplicates are still detectable. Key rotation requires re-hashing: add a `key_version` column when rotation is scheduled.
- **Alternatives:** `pgcrypto` encryption with the key in the database (key lives next to the data); vault tokenisation (better at scale, adds a dependency).

### ADR-010 Transactional outbox for notifications
- **Decision:** business transactions insert `notification` rows; workers claim them with `FOR UPDATE SKIP LOCKED` and a 5-minute lease, retry with exponential backoff, and record provider status.
- **Consequences:** no lost or phantom notifications (no dual write to a queue); at-least-once delivery, made effectively once by `dedupe_key`. The outbox table needs retention and, at scale, partitions.
- **Alternatives:** publish to a broker from the API after commit (lost on crash); CDC (Debezium) from the outbox, the natural next step when a broker is introduced.

### ADR-011 Denormalised organisation on application
- **Decision:** `application.organisation_id`, pinned to the job's organisation by a composite foreign key and filled by trigger.
- **Consequences:** the employer RLS policy and pipeline queries filter on one indexed column, with no join per row. It costs 8 bytes per application.

### ADR-012 Search: PostgreSQL now, search engine at scale
- **Decision:** full-text (`tsvector`, `simple` config for multilingual text) and trigram indexes in PostgreSQL for v2. Move candidate name and keyword search to OpenSearch, fed from the outbox by CDC, when AP-05 misses its target (projected near 1M profiles, [06 §7](06-physical-model.md#7-performance)).
- **Consequences:** no second system now. Under RLS, non-leakproof operators like trigram `%` cannot use their index before the policy runs (measured), which caps in-database name search at scale.
- **Alternatives:** a `SECURITY DEFINER` ranked search that walks the trigram index and checks visibility per match (v1 measured 55× faster); the interim step before a search engine.

### ADR-013 Gig marketplace as a separate subsystem
- **Decision:** gig requests, workers, applications, assignments and ratings get their own tables. They share users, organisations, reference data, the wallet and the audit trail; they do not reuse `job_requirement` / `application`.
- **Consequences:** clean constraints on both sides (windows and prices vs positions and salaries). Cross-category reporting unions two facts in analytics. Deferred in v2.

### ADR-014 Versioned, checksummed, forward-only migrations
- **Decision:** `db/migrations/V###__name.sql`, each applied in one transaction and recorded in `schema_migration` with a SHA-256. The runner refuses an applied migration that was edited. A fix is a new migration.
- **Consequences:** every environment reaches the same schema by the same steps. Production changes follow expand / contract with `lock_timeout` and `CREATE INDEX CONCURRENTLY` (outside the transaction wrapper).
- **Alternatives:** ORM auto-migration (opaque DDL); drop-and-rebuild scripts (v1; fine before production, not after).

### ADR-015 Identity per transaction, not per database role
- **Decision:** one runtime role per service (`v2_app`, `v2_payments`, `v2_worker`, `v2_reporting`); the end user is passed per transaction with `set_config('app.user_id', …, true)`. Policies read it through helpers evaluated once per statement.
- **Consequences:** works with PgBouncer transaction pooling (the setting dies with the transaction); millions of users need no database roles. The API must set it in every transaction: assumption A-01.
