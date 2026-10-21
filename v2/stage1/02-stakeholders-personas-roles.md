# Step 02 — Stakeholders, Personas and Roles

Output document for Stage 1, step 02. It conforms to the schema S-02 in [output-schemas.md](output-schemas.md#s-02-stakeholders-personas-and-roles).

## 1. Stakeholder map

| Stakeholder | Type | Interest | Influence | What they need from the data platform |
|---|---|---|---|---|
| Candidates (job seekers) | primary user | high | medium (they leave if the platform is poor) | find relevant jobs fast, privacy control, status transparency |
| Employers / clients | primary user, payer | high | high (revenue) | qualified candidates, a pipeline view, predictable cost |
| Recruiters (in-house) | primary user | high | medium | search, shortlist and contact candidates; move the pipeline |
| Consultants (freelance recruiters) | partner | medium | low | access to jobs open to consultants, credit for sourcing |
| Placement officers (colleges) | partner | medium | low | campus drives, student placement tracking |
| Talentra admins and support | internal operator | high | high | verify companies, resolve tickets, investigate with the audit trail |
| Northbridge leadership | sponsor | high | very high | single view of the pipeline, retention, revenue KPIs |
| Finance | internal | medium | medium | exact ledger, GST invoices, refunds |
| Legal / data protection officer | internal | medium | high (can block launch) | DPDP Act 2023 compliance: consent, erasure, audit |
| Payment gateway, SMS/email/WhatsApp providers, registries | external system | low | medium | idempotent, auditable integration |
| Legacy system owners | internal | medium | medium | a clean migration boundary |

## 2. Personas

**P1 — Priya, IT job seeker (Candidate)**
- **Who:** 27, Bengaluru, Java developer with 4 years of experience. Uses the mobile app in the evenings, prefers English.
- **Goals:** a better-paying product role within 60 days; does not want her current employer to see her profile.
- **Frustrations:** "applied" black holes with no status, recruiter spam, duplicate profiles on old portals.
- **Needs from the platform:** search by skill, city and salary; block her current company; status notifications; hide or show salary.
- **Requirements served:** FR-JOB-06, FR-PRO-07, FR-PRO-08, FR-APP-07, FR-APP-08, FR-NOT-01.

**P2 — Murugan, blue-collar worker (Candidate)**
- **Who:** 34, Coimbatore, forklift operator. Tamil-first, entry-level Android phone, no resume.
- **Goals:** a stable warehouse job near home, quickly.
- **Frustrations:** English-only forms, long applications.
- **Needs from the platform:** Tamil labels, quick apply without a resume, WhatsApp alerts.
- **Requirements served:** FR-REF-03, FR-APP-01 (resume optional), FR-NOT-01, NFR-I18N-01/02.

**P3 — Anil, HR head of a mid-size logistics firm (Employer / Account admin)**
- **Who:** 45, Pune. Buys the Growth plan, manages 4 recruiters.
- **Goals:** fill 25 delivery positions a month within budget.
- **Frustrations:** paying for profiles that are stale; not knowing what his team spends.
- **Needs from the platform:** seats and devices under control, a wallet statement, invoices, a hiring funnel by month.
- **Requirements served:** FR-ORG-05, FR-BIL-01..09, FR-ANA-01, FR-AUD-02.

**P4 — Sneha, recruiter (Recruiter)**
- **Who:** 29, works for Anil, about 40 candidates contacted a day, desktop.
- **Goals:** shortlist the right people fast and move them through interviews.
- **Frustrations:** contact details that are wrong, candidates who already rejected them, slow search.
- **Needs from the platform:** candidate search with filters, a pipeline per job, contact reveal after download, no re-charge for repeat downloads.
- **Requirements served:** FR-ORG-02, FR-APP-04, FR-BIL-05, FR-BIL-06, AP-03, AP-04.

**P5 — Rahul, freelance consultant (Consultant)**
- **Who:** 38, Delhi, sources niche tech talent for several clients.
- **Goals:** earn per successful placement.
- **Needs from the platform:** see only jobs open to consultants; candidate search; attribution of sourced applications.
- **Requirements served:** FR-JOB-05, FR-SRC-01..04 (deferred).

**P6 — Kavitha, college placement officer (TPO)**
- **Who:** 50, engineering college in Chennai, runs placement season.
- **Needs from the platform:** campus drives, bulk student lists, placement statistics (campus module deferred).

**P7 — Arjun, Talentra support admin (Admin)**
- **Who:** support and trust team.
- **Needs from the platform:** verify companies, revoke sessions, handle erasure requests, read the audit trail; cannot be bypassed and cannot edit history.
- **Requirements served:** FR-ORG-06, FR-IAM-06, NFR-PRIV-04, FR-AUD-01.

### Frequency of use and edge actors

| Persona / actor | Frequency of use | Peak usage |
|---|---|---|
| P1 Priya (candidate, white collar) | daily while job hunting, then monthly | evenings, mobile |
| P2 Murugan (candidate, blue collar) | weekly | WhatsApp alerts, mornings |
| P3 Anil (account admin) | weekly | month start (billing, funnel) |
| P4 Sneha (recruiter) | daily, many sessions | office hours, desktop |
| P5 Rahul (consultant) | daily | office hours |
| P6 Kavitha (TPO) | seasonal (placement season) | Aug–Dec |
| P7 Arjun (support admin) | daily | office hours |
| Edge: payment gateway webhook | continuous | after each payment |
| Edge: notification worker | continuous (every few seconds) | |
| Edge: scheduler (retention, partitions, aggregates) | hourly / daily / monthly | night |
| Edge: auditor or regulator (via staff) | on demand | investigations, erasure requests |

## 3. Roles and permissions

The 9 actors from the docket, mapped to database roles and permissions (source: `access_role_permission` in `v2/db/migrations/V003__identity.sql`).

| Permission ↓ / Role → | Super admin | Admin | Account admin | Employer | Recruiter | Consultant | TPO | Candidate | Guest |
|---|---|---|---|---|---|---|---|---|---|
| browse open jobs | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| manage own profile, apply, block | | | | | | | | ✔ | |
| user_manage | ✔ | ✔ | | | | | | | |
| organisation_verify | ✔ | ✔ | | | | | | | |
| job_post | ✔ | | ✔ | ✔ | | | | | |
| job_manage | ✔ | | ✔ | ✔ | ✔ | | | | |
| application_manage | ✔ | | ✔ | ✔ | ✔ | | | | |
| candidate_search | ✔ | | ✔ | ✔ | ✔ | ✔ | ✔ | | |
| candidate_download | ✔ | | ✔ | ✔ | ✔ | | | | |
| billing_manage | ✔ | | ✔ | | | | | | |
| member_manage | ✔ | | ✔ | | | | | | |
| audit_read | ✔ | ✔ | ✔ (own org) | | | | | | |
| consultant_source | ✔ | | | | | ✔ | | | |

**Hard rules from the docket, and where each is enforced:**

| Rule | Enforcement | Test |
|---|---|---|
| A recruiter sees only their own company's jobs | RLS policy `job_requirement_read` / `_update` | t03 |
| A consultant works only on jobs open to consultants | `application_guard` trigger | t02 |
| A blocked party cannot see the candidate | RLS on `candidate_profile` and `application`; `candidate_contact()` | t03 (5 checks) |
| Recruiters cannot register candidates | `auth_register_candidate()` refuses signed-in non-staff | t03 |
| Every sensitive action is audited | `audit_row_change` triggers, `audit_log()` | t02, t03 |

Out of scope (docket): sub-roles inside an employer. Extension: a `member_permission` table read by `app_has_permission()`.
