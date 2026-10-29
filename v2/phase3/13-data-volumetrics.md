# 13 — Data Volumetrics and Distribution Profile

> Reconciled directly against live PostgreSQL 18 (`db/migrations/V001..V013`), deterministic seed (`db/seed/seed_prove_sample.sql`), and SQL test suites (`db/tests/t01..t06.sql`) with zero catalog drift.

Conforms strictly to Phase 3 schema [S-13](schemas.md#s-13--data-volumetrics-and-distribution-profile). Every scale tier and volumetric figure explicitly distinguishes **[DOCKET FACT — Hackathon Docket §6]**, **[DESIGN ASSUMPTION — Engineering Ramp / Verification Tier]**, and **[CALCULATED ESTIMATE — Physical Storage Formula]**.

## 1. Scale Tiers (Docket §6 Facts vs. Engineering Assumptions)

| Tier Code | Classification | Candidate Profiles | Job Requirements | Applications | Organisations | Horizon & Sizing Basis |
|---|---|---|---|---|---|---|
| `prove_sample` | **[DESIGN ASSUMPTION]** | 30 | 12 | 36 | 6 | Phase 3 minimal verification seed (`seed_prove_sample.sql`, < 1.0s execution) covering 100% of states & lookups |
| `dev_10k` | **[DESIGN ASSUMPTION]** | 10,000 | 1,050 | 56,000 | 200 | Local developer & CI latency benchmark tier (`db/seed/seed.sql` / `bench/bench.py`) |
| `launch_100k` | **[DESIGN ASSUMPTION]** | 100,000 | 10,000 | 600,000 | 2,000 | Day-1 MVP launch ramp assumption (10% of Docket Laptop Scale) |
| `docket_laptop_1m` | **[DOCKET FACT — §6]** | **1,000,000** | **100,000** | **5,000,000** | **20,000** | **Hackathon Docket §6 Laptop-Scale Target** (1M profiles, 100k jobs, 5M applications) |
| `year1_2_5m` | **[DESIGN ASSUMPTION]** | 2,500,000 | 250,000 | 20,000,000 | 50,000 | Intermediate 12-month production milestone assumption (25% of Full Scale) |
| `docket_full_10m` | **[DOCKET FACT — §6]** | **10,000,000** | **1,000,000** | **100,000,000** | **200,000** | **Hackathon Docket §6 Full-Scale 3-Year Target** (10M profiles, 1M jobs, 100M applications, **< 250 GB** budget) |

## 2. Table Volumetric Sheet (All 73 Physical Base Tables + 1 Materialized View)

**Storage Calculation Formula (`[CALCULATED ESTIMATE]`):** Full-scale storage is computed as `rows × (avg_payload_bytes + 40 B PostgreSQL HeapTupleHeaderData/item-pointer overhead) × 1.493 B-tree/GIN index amplification factor ÷ 1024³`. Docket Target: **< 250 GB** (`NFR-SCAL-03`, Docket §6).

| # | Table | Entity | Kind | Prove (30) [Measured] | Launch (100k) [Assumed] | Docket Laptop (1M) [Docket §6] | Year 1 (2.5M) [Assumed] | Docket Full (10M) [Docket §6] | Growth Pattern | Row (B) | Full Scale (GB) [Calc] | Sizing Basis & Note |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `access_role_permission` | ENT-05 | Business/Ref | 34 | 34 | **34** | 34 | **34** | static | 48 | 0.00 | [DERIVED RATIO] fixed role-permission matrix (8 roles x 11 permissions) |
| 2 | `agg_hiring_funnel_monthly` | ENT-42 | MatView | 5 | 6,000 | **240,000** | 300,000 | **2,400,000** | linear with orgs | 96 | 0.45 | [DERIVED RATIO] 1 row per active organisation per month |
| 3 | `app_user` | ENT-01 | Business/Ref | 41 | 106,500 | **1,065,000** | 2,660,000 | **10,650,000** | linear with users | 148 | 2.78 | [DERIVED RATIO] 1 per candidate + org members + staff/consultants |
| 4 | `application` | ENT-26 | Business/Ref | 36 | 600,000 | **5,000,000** | 20,000,000 | **100,000,000** | event-driven append | 128 | 23.36 | [DOCKET §6] docket 1:100 job-to-application ratio (100M at Y3) |
| 5 | `application_answer` | ENT-27 | Business/Ref | 72 | 420,000 | **3,500,000** | 14,000,000 | **70,000,000** | event-driven append | 116 | 15.18 | [DERIVED RATIO] ~0.7 answers per application across all jobs |
| 6 | `application_status_history` | ENT-28 | Business/Ref | 88 | 1,320,000 | **11,000,000** | 44,000,000 | **220,000,000** | event-driven append | 88 | 39.16 | [DERIVED RATIO] ~2.2 transitions per application (largest table at Y3) |
| 7 | `application_status_transition` | ENT-29 | Business/Ref | 12 | 12 | **12** | 12 | **12** | static | 48 | 0.00 | [DERIVED RATIO] 12 allowed application pipeline transitions |
| 8 | `audit_event` | ENT-40 | Business/Ref | 64 | 350,000 | **6,000,000** | 12,000,000 | **60,000,000** | bounded by retention | 210 | 20.86 | [DERIVED RATIO] monthly partitions; 7-year retention (84 partitions) |
| 9 | `candidate_block` | ENT-20 | Business/Ref | 3 | 2,500 | **25,000** | 62,500 | **250,000** | event-driven append | 96 | 0.05 | [DERIVED RATIO] ~2.5% of candidates block an employer or recruiter |
| 10 | `candidate_education` | ENT-15 | Business/Ref | 29 | 140,000 | **1,400,000** | 3,500,000 | **14,000,000** | linear with users | 140 | 3.50 | [DERIVED RATIO] ~1.4 qualifications per live profile |
| 11 | `candidate_experience` | ENT-16 | Business/Ref | 28 | 160,000 | **1,600,000** | 4,000,000 | **16,000,000** | linear with users | 210 | 5.56 | [DERIVED RATIO] ~1.6 work history rows per profile |
| 12 | `candidate_language` | ENT-18 | Business/Ref | 58 | 220,000 | **2,200,000** | 5,500,000 | **22,000,000** | linear with users | 64 | 3.18 | [DERIVED RATIO] ~2.2 languages per profile |
| 13 | `candidate_profile` | ENT-14 | Business/Ref | 30 | 100,000 | **1,000,000** | 2,500,000 | **10,000,000** | linear with users | 320 | 5.01 | [DOCKET §6] anchor entity (10k dev, 100k launch, 2.5M Y1, 10M Y3) |
| 14 | `candidate_skill` | ENT-17 | Business/Ref | 116 | 550,000 | **5,500,000** | 13,750,000 | **55,000,000** | linear with users | 72 | 8.57 | [DERIVED RATIO] ~5.5 skills per profile (heaviest profile child) |
| 15 | `city` | ENT-49 | Business/Ref | 36 | 300 | **300** | 800 | **1,500** | static | 96 | 0.00 | [DERIVED RATIO] Tier-1, Tier-2, Tier-3 cities with WGS 84 coordinates |
| 16 | `consent_record` | ENT-07 | Business/Ref | 152 | 420,000 | **4,200,000** | 10,500,000 | **42,000,000** | event-driven append | 104 | 8.41 | [DERIVED RATIO] ~4 records per user (sign-up + marketing/visibility changes) |
| 17 | `country` | ENT-47 | Business/Ref | 5 | 5 | **5** | 10 | **15** | static | 84 | 0.00 | [DERIVED RATIO] IN, US, GB, AE, SG |
| 18 | `currency` | ENT-46 | Business/Ref | 5 | 5 | **5** | 10 | **15** | static | 56 | 0.00 | [DERIVED RATIO] INR, USD, GBP, AED, SGD |
| 19 | `invoice` | ENT-36 | Business/Ref | 6 | 4,200 | **70,000** | 140,000 | **700,000** | event-driven append | 140 | 0.18 | [DERIVED RATIO] 1 GST invoice per captured payment order |
| 20 | `job_alert` | ENT-21 | Business/Ref | 3 | 35,000 | **350,000** | 875,000 | **3,500,000** | linear with users | 112 | 0.74 | [DERIVED RATIO] ~0.35 saved alerts per candidate |
| 21 | `job_requirement` | ENT-22 | Business/Ref | 12 | 10,000 | **100,000** | 250,000 | **1,000,000** | linear with orgs | 680 | 1.00 | [DOCKET §6] docket 10:1 profile-to-job ratio (1M jobs at Y3) |
| 22 | `job_requirement_location` | ENT-23 | Business/Ref | 12 | 14,000 | **140,000** | 350,000 | **1,400,000** | linear with orgs | 64 | 0.20 | [DERIVED RATIO] ~1.4 cities per job |
| 23 | `job_requirement_skill` | ENT-24 | Business/Ref | 24 | 32,000 | **320,000** | 800,000 | **3,200,000** | linear with orgs | 68 | 0.48 | [DERIVED RATIO] ~3.2 required/optional skills per job |
| 24 | `job_status_transition` | ENT-22 | Business/Ref | 7 | 7 | **7** | 7 | **7** | static | 48 | 0.00 | [DERIVED RATIO] 7 allowed job status transitions (added in V013) |
| 25 | `language` | ENT-43 | Business/Ref | 8 | 8 | **8** | 12 | **22** | static | 68 | 0.00 | [DERIVED RATIO] 8 Indian & international languages at launch |
| 26 | `notification` | ENT-39 | Business/Ref | 56 | 850,000 | **4,500,000** | 18,000,000 | **45,000,000** | bounded by retention | 220 | 16.27 | [DERIVED RATIO] 180-day retention window on delivered/failed/suppressed |
| 27 | `notification_preference` | ENT-38 | Business/Ref | 2 | 95,000 | **950,000** | 2,350,000 | **9,500,000** | linear with users | 68 | 1.43 | [DERIVED RATIO] explicit opt-outs only (~0.95 rows per user) |
| 28 | `organisation` | ENT-10 | Business/Ref | 6 | 2,000 | **20,000** | 50,000 | **200,000** | linear with orgs | 180 | 0.06 | [DERIVED RATIO] 1 org per ~50 candidate profiles |
| 29 | `organisation_location` | ENT-11 | Business/Ref | 6 | 2,600 | **26,000** | 65,000 | **260,000** | linear with orgs | 168 | 0.08 | [DERIVED RATIO] ~1.3 offices per organisation (1 HQ) |
| 30 | `organisation_member` | ENT-13 | Business/Ref | 12 | 6,500 | **65,000** | 162,500 | **650,000** | linear with orgs | 96 | 0.12 | [DERIVED RATIO] ~3.25 memberships (current + historical) per org |
| 31 | `organisation_tax_identifier` | ENT-12 | Business/Ref | 6 | 2,100 | **21,000** | 52,500 | **210,000** | linear with orgs | 128 | 0.05 | [DERIVED RATIO] ~1.05 tax identifiers per organisation |
| 32 | `payment_event` | ENT-35 | Business/Ref | 10 | 6,000 | **100,000** | 200,000 | **1,000,000** | event-driven append | 156 | 0.27 | [DERIVED RATIO] ~1.33 gateway webhook events per payment order |
| 33 | `payment_order` | ENT-34 | Business/Ref | 10 | 4,500 | **75,000** | 150,000 | **750,000** | event-driven append | 164 | 0.21 | [DERIVED RATIO] subscription and wallet recharge orders |
| 34 | `plan` | ENT-30 | Business/Ref | 3 | 3 | **3** | 5 | **8** | static | 120 | 0.00 | [DERIVED RATIO] Starter, Growth, Enterprise (+ future tiers) |
| 35 | `profile_download` | ENT-37 | Business/Ref | 2 | 35,000 | **500,000** | 1,100,000 | **5,000,000** | event-driven append | 104 | 1.00 | [DERIVED RATIO] paid contact unlocks (1 credit per 30-day window) |
| 36 | `resume` | ENT-19 | Business/Ref | 27 | 110,000 | **1,100,000** | 2,750,000 | **11,000,000** | linear with users | 168 | 3.18 | [DERIVED RATIO] ~1.1 resume versions per profile (files in object storage) |
| 37 | `screening_question` | ENT-25 | Business/Ref | 12 | 9,000 | **90,000** | 225,000 | **900,000** | linear with orgs | 148 | 0.24 | [DERIVED RATIO] ~40% of jobs attach 2-3 questions |
| 38 | `skill` | ENT-50 | Business/Ref | 96 | 1,200 | **1,200** | 3,000 | **5,000** | static | 72 | 0.00 | [DERIVED RATIO] controlled skill taxonomy |
| 39 | `state` | ENT-48 | Business/Ref | 20 | 36 | **36** | 50 | **75** | static | 72 | 0.00 | [DERIVED RATIO] Indian states/UTs + key international regions |
| 40 | `subscription` | ENT-31 | Business/Ref | 4 | 3,200 | **55,000** | 110,000 | **550,000** | event-driven append | 128 | 0.13 | [DERIVED RATIO] 1 row per paid period per subscribed organisation |
| 41 | `system_error` | ENT-41 | Business/Ref | 3 | 25,000 | **50,000** | 250,000 | **500,000** | bounded by retention | 260 | 0.21 | [DERIVED RATIO] 90-day sliding retention window |
| 42 | `ui_label` | ENT-44 | Business/Ref | 114 | 250 | **250** | 400 | **600** | static | 64 | 0.00 | [DERIVED RATIO] lookup & screen label keys |
| 43 | `ui_translation` | ENT-45 | Business/Ref | 128 | 1,500 | **1,500** | 3,600 | **7,200** | static | 96 | 0.00 | [DERIVED RATIO] labels x translated UI languages |
| 44 | `user_access_role` | ENT-06 | Business/Ref | 41 | 108,000 | **1,080,000** | 2,700,000 | **10,800,000** | linear with users | 64 | 1.56 | [DERIVED RATIO] ~1.01 roles per user |
| 45 | `user_credential` | ENT-02 | Business/Ref | 40 | 106,000 | **1,050,000** | 2,640,000 | **10,500,000** | linear with users | 164 | 2.98 | [DERIVED RATIO] 1 per active/non-erased user (deleted on erasure) |
| 46 | `user_device` | ENT-08 | Business/Ref | 41 | 160,000 | **1,600,000** | 4,000,000 | **16,000,000** | linear with users | 136 | 3.92 | [DERIVED RATIO] ~1.5 devices per user |
| 47 | `user_session` | ENT-09 | Business/Ref | 39 | 450,000 | **2,500,000** | 8,500,000 | **25,000,000** | bounded by retention | 144 | 6.40 | [DERIVED RATIO] active + ended in last 1 year (1-year retention job) |
| 48 | `wallet` | ENT-32 | Business/Ref | 6 | 2,000 | **20,000** | 50,000 | **200,000** | linear with orgs | 72 | 0.03 | [DERIVED RATIO] exactly 1 wallet per organisation (enforced by V013) |
| 49 | `wallet_ledger_entry` | ENT-33 | Business/Ref | 22 | 48,000 | **650,000** | 1,400,000 | **6,500,000** | event-driven append | 136 | 1.59 | [DERIVED RATIO] recharges, plan grants, job debits, download debits, reversals |
| 50 | `access_permission` | ENT-04 | Lookup (25) | 11 | 11 | **11** | 11 | **11** | static | 64 | 0.00 | [STATIC] Fixed lookup (11 enum codes) |
| 51 | `access_role` | ENT-03 | Lookup (25) | 8 | 8 | **8** | 8 | **8** | static | 64 | 0.00 | [STATIC] Fixed lookup (8 enum codes) |
| 52 | `account_status` | ENT-51 | Lookup (25) | 4 | 4 | **4** | 4 | **4** | static | 64 | 0.00 | [STATIC] Fixed lookup (4 enum codes) |
| 53 | `alert_frequency` | ENT-51 | Lookup (25) | 3 | 3 | **3** | 3 | **3** | static | 64 | 0.00 | [STATIC] Fixed lookup (3 enum codes) |
| 54 | `answer_type` | ENT-51 | Lookup (25) | 3 | 3 | **3** | 3 | **3** | static | 64 | 0.00 | [STATIC] Fixed lookup (3 enum codes) |
| 55 | `application_source` | ENT-51 | Lookup (25) | 5 | 5 | **5** | 5 | **5** | static | 64 | 0.00 | [STATIC] Fixed lookup (5 enum codes) |
| 56 | `application_status` | ENT-51 | Lookup (25) | 7 | 7 | **7** | 7 | **7** | static | 64 | 0.00 | [STATIC] Fixed lookup (7 enum codes) |
| 57 | `consent_purpose` | ENT-51 | Lookup (25) | 5 | 5 | **5** | 5 | **5** | static | 64 | 0.00 | [STATIC] Fixed lookup (5 enum codes) |
| 58 | `employment_type` | ENT-51 | Lookup (25) | 6 | 6 | **6** | 6 | **6** | static | 64 | 0.00 | [STATIC] Fixed lookup (6 enum codes) |
| 59 | `industry` | ENT-51 | Lookup (25) | 15 | 15 | **15** | 15 | **15** | static | 64 | 0.00 | [STATIC] Fixed lookup (15 enum codes) |
| 60 | `job_status` | ENT-51 | Lookup (25) | 5 | 5 | **5** | 5 | **5** | static | 64 | 0.00 | [STATIC] Fixed lookup (5 enum codes) |
| 61 | `ledger_entry_type` | ENT-51 | Lookup (25) | 6 | 6 | **6** | 6 | **6** | static | 64 | 0.00 | [STATIC] Fixed lookup (6 enum codes) |
| 62 | `notification_category` | ENT-51 | Lookup (25) | 5 | 5 | **5** | 5 | **5** | static | 64 | 0.00 | [STATIC] Fixed lookup (5 enum codes) |
| 63 | `notification_channel` | ENT-51 | Lookup (25) | 4 | 4 | **4** | 4 | **4** | static | 64 | 0.00 | [STATIC] Fixed lookup (4 enum codes) |
| 64 | `notification_status` | ENT-51 | Lookup (25) | 5 | 5 | **5** | 5 | **5** | static | 64 | 0.00 | [STATIC] Fixed lookup (5 enum codes) |
| 65 | `payment_purpose` | ENT-51 | Lookup (25) | 2 | 2 | **2** | 2 | **2** | static | 64 | 0.00 | [STATIC] Fixed lookup (2 enum codes) |
| 66 | `payment_status` | ENT-51 | Lookup (25) | 5 | 5 | **5** | 5 | **5** | static | 64 | 0.00 | [STATIC] Fixed lookup (5 enum codes) |
| 67 | `proficiency_level` | ENT-51 | Lookup (25) | 5 | 5 | **5** | 5 | **5** | static | 64 | 0.00 | [STATIC] Fixed lookup (5 enum codes) |
| 68 | `profile_visibility` | ENT-51 | Lookup (25) | 3 | 3 | **3** | 3 | **3** | static | 64 | 0.00 | [STATIC] Fixed lookup (3 enum codes) |
| 69 | `qualification` | ENT-51 | Lookup (25) | 8 | 8 | **8** | 8 | **8** | static | 64 | 0.00 | [STATIC] Fixed lookup (8 enum codes) |
| 70 | `salary_disclosure` | ENT-51 | Lookup (25) | 3 | 3 | **3** | 3 | **3** | static | 64 | 0.00 | [STATIC] Fixed lookup (3 enum codes) |
| 71 | `session_end_reason` | ENT-51 | Lookup (25) | 4 | 4 | **4** | 4 | **4** | static | 64 | 0.00 | [STATIC] Fixed lookup (4 enum codes) |
| 72 | `tax_identifier_type` | ENT-51 | Lookup (25) | 5 | 5 | **5** | 5 | **5** | static | 64 | 0.00 | [STATIC] Fixed lookup (5 enum codes) |
| 73 | `verification_status` | ENT-51 | Lookup (25) | 3 | 3 | **3** | 3 | **3** | static | 64 | 0.00 | [STATIC] Fixed lookup (3 enum codes) |
| 74 | `work_mode` | ENT-51 | Lookup (25) | 3 | 3 | **3** | 3 | **3** | static | 64 | 0.00 | [STATIC] Fixed lookup (3 enum codes) |

**Total Reconciled Relations:** **73 Physical Base Tables** (48 Business/Reference/Config + 25 Enumeration Lookups) + **1 Materialized View** (`agg_hiring_funnel_monthly`) = **74 Relations**.
**Total Calculated Full-Scale (10M) Storage:** **178.40 GB** (`[CALCULATED ESTIMATE]`, comfortably within the **< 250 GB** single-primary budget mandated by Docket §6 / `NFR-SCAL-03`).

## 3. Cardinality and Skew Distributions

| Relation | Parent → Child | Cardinality (min / med / p95 / max) | Skew & Distribution Profile |
|---|---|---|---|
| `R-01..05` | `app_user → consent_record` | 2 / 3 / 5 / 12 | Bimodal: 100% have 2 mandatory consents (terms, privacy); 85% have purpose 3; 40% grant marketing |
| `R-06..07` | `app_user → user_device / user_session` | 1 / 1 / 3 / 6 | Capped by licence: candidates max 3 active devices; org members 1–3 per plan |
| `R-08..11` | `organisation → organisation_member` | 1 / 2 / 5 / 15 | Plan-skewed: 60% Starter (≤2 seats), 30% Growth (≤5 seats), 10% Enterprise (≤15 seats) |
| `R-12..17` | `candidate_profile → candidate_skill` | 0 / 5 / 8 / 25 | Zipf s=1.7 on skill_id: top 15 skills (Java, Python, SQL, Sales, Excel) appear on 52% of profiles |
| `R-18..20` | `organisation → job_requirement` | 0 / 3 / 18 / 250 | Pareto 80/20: Enterprise & Growth orgs (40% of orgs) post 78% of all job requirements |
| `R-21..22` | `job_requirement → job_requirement_location` | 1 / 1 / 3 / 8 | Geographic concentration: top 8 Tier-1 cities (Bengaluru, Mumbai, Hyderabad, Chennai, Delhi, Pune, Gurugram, Noida) hold 68% of postings |
| `R-23..26` | `job_requirement → application` | 0 / 45 / 280 / 2,500 | Heavy right tail (Zipf s=1.6): entry-level IT and logistics roles receive 10× median applications |
| `R-27..28` | `application → application_status_history` | 1 / 2 / 4 / 5 | Funnel attrition: 100% applied → 28% shortlisted → 14% interviewing → 5% offered → 3% joined |
| `R-29..33` | `wallet → wallet_ledger_entry` | 1 / 14 / 65 / 1,200 | Append-only: 1 plan grant per period + 1 debit per published job (-5) + 1 debit per profile download (-1) |
| `R-34` | `organisation → profile_download` | 0 / 10 / 85 / 1,500 | Concentrated in active sourcing teams; 30-day deduplication window suppresses repeat debits |

## 4. Null-Rate Profile for Key Nullable Columns

| Table | Column | Expected Null % | Business Rationale & Index Strategy |
|---|---|---|---|
| `app_user` | `email` | 0.2% | NULL only after DPDP erasure (account_status = erased) |
| `app_user` | `phone_e164` | 8.0% | Phone optional at candidate sign-up; always paired with phone_country_id |
| `app_user` | `last_login_at` | 3.0% | Invited org members or migrated accounts that have not logged in yet |
| `user_credential` | `locked_until` | 99.4% | Only set during active 15-minute brute-force lockout window |
| `user_device` | `revoked_at` | 94.0% | Set only when a user or admin revokes a device |
| `user_session` | `ended_at` | 15.0% | NULL for currently active sessions; non-NULL for historical ended sessions |
| `organisation` | `parent_organisation_id` | 95.0% | Only subsidiary companies in a corporate group have a parent org |
| `organisation` | `website_url` | 20.0% | Small/medium employers without a website |
| `organisation` | `verified_at` | 15.0% | NULL while pending (10%) or rejected (5%) |
| `organisation_member` | `valid_to` | 85.0% | NULL for current active members; set when a recruiter leaves |
| `candidate_profile` | `headline` | 20.0% | Incomplete profiles at initial registration |
| `candidate_profile` | `current_city_id` | 5.0% | Planted finding F-02: candidates who skipped location (excluded from city search) |
| `candidate_profile` | `expected_salary_amount` | 40.0% | 25% not_disclosed + 15% not_provided (distinguished by salary_disclosure_id) |
| `candidate_profile` | `notice_period_days` | 20.0% | Not yet asked on quick-apply profiles |
| `candidate_experience` | `organisation_id` | 72.0% | Past employer is not a registered organisation on Talentra (company_name always kept) |
| `candidate_experience` | `end_date` | 40.0% | Current job held by the candidate (at most 1 per profile via partial unique index) |
| `candidate_block` | `unblocked_at` | 90.0% | Most blocks remain active permanently |
| `job_requirement` | `salary_min_amount` | 30.0% | Employers choosing salary_disclosure = not_disclosed (code 2) |
| `job_requirement` | `published_at` | 8.0% | Draft jobs not yet published |
| `job_requirement` | `closes_on` | 60.0% | Evergreen or open-until-filled postings |
| `application` | `resume_id` | 30.0% | Blue-collar / quick-apply candidates applying without a PDF/DOCX resume |
| `application` | `sourced_by_app_user_id` | 92.0% | Direct, referral, and campus applications (non-NULL only for recruiter_outreach and consultant) |
| `application_status_history` | `from_status_id` | 45.0% | First history row of every application (NULL -> applied) |
| `subscription` | `cancelled_at` | 93.0% | Only churned or refunded subscriptions carry cancelled_at |
| `wallet_ledger_entry` | `reverses_ledger_entry_id` | 98.5% | Set only on reversal entries (ledger_entry_type = reversal) |
| `notification` | `delivered_at` | 12.0% | Queued, sent-awaiting-receipt, failed, or suppressed notifications |
| `notification` | `failure_reason` | 98.0% | Non-NULL strictly when notification_status = failed (enforced by ck_notification_failed) |

## 5. Seasonality, Peak Days and Burst Traffic

| Workload | Avg RPS (Y3) | Peak Burst RPS | Peak Window & Multiplier | Architectural & Index Handling |
|---|---|---|---|---|
| `job_search (AP-01)` | 180.0 | 600.0 | Monday–Tuesday 10:00–13:00 IST & 19:00–22:00 IST; Jan–Mar appraisal/switch season (2.4×) | GIN index idx_job_requirement_search_vector + partial index on open jobs |
| `candidate_search (AP-04/05)` | 65.0 | 220.0 | Tuesday–Thursday 10:30–17:30 IST (recruiter working hours); Q1 hiring budgets (1.8×) | Composite index idx_candidate_profile_search + trigram GIN index + RLS initPlan |
| `login (WF-08 / AP-11)` | 18.0 | 60.0 | 9:30–10:30 IST weekday morning spike + push notification blast response (3.3×) | Per-user row lock in auth_open_session() + partial index idx_user_session_app_user_id_active |
| `application_submit (WF-04)` | 3.2 | 10.0 | Within 2 hours of instant/daily job-alert digests (3.1×) | Single-row lock on job_requirement only when status=joined; INSERT is lock-free across candidates |
| `job_alert_digest (WF-10)` | 4.5 | 15.0 | Daily 08:00 IST & Weekly Monday 07:30 IST cron batch bursts | Outbox pattern + notification_claim() FOR UPDATE SKIP LOCKED across worker pool |
| `webhook_burst (WF-07)` | 0.5 | 8.0 | Month-end subscription auto-renewal batch + gateway retry storms after network blip | Idempotent uq_payment_event_gateway_event_ref + per-order FOR UPDATE lock |
| `campus_drive (WF-01/04)` | 0.2 | 25.0 | Aug–Nov campus placement drives: 500–2,000 students registering & applying in 15 minutes | Stateless argon2id hashing in auth tier + short <10ms DB transactions |

## 6. Exit Test Check

| S-13 Exit Criterion | Status | Evidence |
|---|---|---|
| All 73 physical tables + 1 MatView modeled across Docket & ramp tiers | **PASSED** | 48 business/ref tables + 25 lookup tables + 1 MatView explicitly listed |
| Docket Laptop (1M/100k/5M) and Full (10M/1M/100M) scales separated from assumptions | **PASSED** | Every tier and table row tagged `[DOCKET FACT]` vs `[DESIGN ASSUMPTION]` |
| Full-scale storage complies with NFR-SCAL-03 (< 250 GB) | **PASSED** | Calculated total storage is 178.42 GB on a single PostgreSQL 18 primary |
| Skew profiles and burst traffic multipliers verified against concurrency model | **PASSED** | Zipf s=1.7 on skills; Pareto 80/20 on employers; 600 RPS search & 25 RPS campus peaks |
