# Step 07 — Attributes Discovery (attribute list per entity)

Reconciled directly against the PostgreSQL physical DDL (`db/migrations/V001..V013`) with zero catalog drift.

Conforms to schema [S-07](schemas.md#s-07--attributes-discovery). Logical level: each attribute has a logical type from the standard domains (docket rule group 3, [logical model §2](../docs/05-logical-model.md#2-logical-domains)), a length, a mandatory flag (with the reason when optional, rule group 5), a unit, an example value, and whether it is stored or derived. The physical types are in [step 10](10-data-dictionary-v1.md).

**Every business entity also has** `created_at`, `created_by`, `updated_at`, `updated_by` (rule group 4), not repeated below. **Enumeration values (ENT-51)** share one shape, listed once at the end.

## ENT-01 User — `app_user`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| User id | `id` | Identifier | 64-bit | yes |  | 7041 | stored |
| Email address | `email` | Email | ≤ 254 chars | no — only after erasure (account_status erased), enforced by ck_app_user_email_erased |  | priya.sharma@mail.test | stored |
| Mobile number | `phone_e164` | Phone (E.164) | 8–16 chars (+ and up to 15 digits) | no — phone is optional at sign-up |  | +919876543210 | stored |
| Phone country | `phone_country_id` | Reference → Country | 16-bit | no — exactly when phone_e164 is NULL |  | 1 (IN) | stored |
| Account status | `account_status_id` | Code → account_status | 16-bit | yes |  | 1 (active) | stored |
| Preferred language | `preferred_language_id` | Reference → Language | 16-bit | yes |  | 1 (en) | stored |
| Time zone | `time_zone` | Formatted text | bounded by its pattern | yes |  | Asia/Kolkata | stored |
| Last login | `last_login_at` | Timestamp | µs, UTC | no — the user has never logged in (invited or migrated account) | UTC | 2026-10-24 08:41:07+00 | derived at write · latest session start |
| Deleted at | `deleted_at` | Timestamp | µs, UTC | no — the row is live | UTC | 2026-10-12 09:30:15+00 | stored |

**Multi-valued attributes, moved out:** roles → user_access_role; consents → consent_record; devices → user_device.

## ENT-02 Credential — `user_credential`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Credential id | `id` | Identifier | 64-bit | yes |  | 3151 | stored |
| User | `app_user_id` | Reference → User | 64-bit | yes |  | 7041 | stored |
| Password hash | `password_hash` | Formatted text | bounded by its pattern | yes |  | $argon2id$v=19$m=65536,t=3,p=4$c2FsdHNhbHQ$aGFzaGhhc2g | stored |
| Password changed | `password_changed_at` | Timestamp | µs, UTC | yes | UTC | 2026-03-02 10:15:00+00 | stored |
| Failed attempts | `failed_attempt_count` | Integer | 16-bit | yes | attempts | 0 | stored |
| Locked until | `locked_until` | Timestamp | µs, UTC | no — not locked out | UTC | 2026-10-24 09:00:00+00 | stored |

## ENT-05 Role permission — `access_role_permission`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Role permission id | `id` | Identifier | 16-bit | yes |  | 8429 | stored |
| Access role | `access_role_id` | Code → access_role | 16-bit | yes |  | 1 (super_admin) | stored |
| Access permission | `access_permission_id` | Code → access_permission | 16-bit | yes |  | 1 (user_manage) | stored |

## ENT-06 Role grant — `user_access_role`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Role grant id | `id` | Identifier | 64-bit | yes |  | 3879 | stored |
| User | `app_user_id` | Reference → User | 64-bit | yes |  | 7041 | stored |
| Access role | `access_role_id` | Code → access_role | 16-bit | yes |  | 1 (super_admin) | stored |

## ENT-07 Consent record — `consent_record`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Consent record id | `id` | Identifier | 64-bit | yes |  | 2472 | stored |
| User | `app_user_id` | Reference → User | 64-bit | yes |  | 7041 | stored |
| Consent purpose | `consent_purpose_id` | Code → consent_purpose | 16-bit | yes |  | 1 (terms_of_service) | stored |
| Granted | `is_granted` | Flag |  | yes |  | true | stored |
| Policy version | `policy_version` | Formatted text | bounded by its pattern | yes |  | 2026-01 | stored |
| Recorded at | `recorded_at` | Timestamp | µs, UTC | yes | UTC | 2026-01-14 11:02:33+00 | stored |
| IP address | `ip_address` | IP address | IPv4/IPv6 | no — recorded by a back-office or migration process |  | 203.0.113.24 | stored |

## ENT-08 Device — `user_device`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Device id | `id` | Identifier | 64-bit | yes |  | 9162 | stored |
| User | `app_user_id` | Reference → User | 64-bit | yes |  | 7041 | stored |
| Device fingerprint hash | `device_fingerprint_hash` | Digest | 32 bytes | yes |  | \x9f2c…e1 (32 bytes) | stored |
| Device name | `device_label` | Short text | 1–200 chars | no — client did not send one or erased |  | Chrome on Windows | stored |
| First seen | `first_seen_at` | Timestamp | µs, UTC | yes | UTC | 2026-02-01 07:30:00+00 | stored |
| Last seen | `last_seen_at` | Timestamp | µs, UTC | yes | UTC | 2026-10-24 08:41:07+00 | stored |
| Revoked at | `revoked_at` | Timestamp | µs, UTC | no — the device is trusted | UTC | 2026-09-30 18:00:00+00 | stored |

## ENT-09 Session — `user_session`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Session id | `id` | Identifier | 64-bit | yes |  | 1198 | stored |
| User | `app_user_id` | Reference → User | 64-bit | yes |  | 7041 | stored |
| Device | `user_device_id` | Reference → Device | 64-bit | yes |  | 9162 | stored |
| Session token hash | `token_hash` | Digest | 32 bytes | yes |  | \x41d0…7a (32 bytes) | stored |
| Started | `started_at` | Timestamp | µs, UTC | yes | UTC | 2026-10-24 08:41:07+00 | stored |
| Last activity | `last_activity_at` | Timestamp | µs, UTC | yes | UTC | 2026-10-24 09:12:40+00 | stored |
| Expires | `expires_at` | Timestamp | µs, UTC | yes | UTC | 2026-11-23 08:41:07+00 | stored |
| Ended | `ended_at` | Timestamp | µs, UTC | no — session not ended (still active until expires_at) | UTC | 2026-10-24 18:05:00+00 | stored |
| Session end reason | `session_end_reason_id` | Code → session_end_reason | 16-bit | no — exactly when ended_at is NULL |  | 1 (logout) | stored |

## ENT-10 Organisation — `organisation`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Organisation id | `id` | Identifier | 64-bit | yes |  | 1058 | stored |
| Legal name | `legal_name` | Short text | 1–200 chars | yes |  | Ashok Logistics Private Limited | stored |
| Brand name | `display_name` | Short text | 1–200 chars | yes |  | Ashok Logistics | stored |
| Industry | `industry_id` | Code → industry | 16-bit | yes |  | 1 (information_technology) | stored |
| Country | `country_id` | Reference → Country | 16-bit | yes |  | 1 (IN) | stored |
| Parent company | `parent_organisation_id` | Reference → Organisation | 64-bit | no — top of its hierarchy |  | 1058 | stored |
| Website | `website_url` | Formatted text | ≤ 250 chars | no — the company has no website (common for small employers) |  | https://ashoklogistics.test | stored |
| Verification status | `verification_status_id` | Code → verification_status | 16-bit | yes |  | 1 (pending) | stored |
| Verified at | `verified_at` | Timestamp | µs, UTC | no — exactly when not verified (ck_organisation_verified_at) | UTC | 2026-04-03 12:00:00+00 | stored |
| Account status | `account_status_id` | Code → account_status | 16-bit | yes |  | 1 (active) | stored |
| Deleted at | `deleted_at` | Timestamp | µs, UTC | no — the row is live | UTC | 2026-10-12 09:30:15+00 | stored |

**Multi-valued attributes, moved out:** offices → organisation_location; tax identifiers → organisation_tax_identifier; members → organisation_member.

## ENT-11 Office location — `organisation_location`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Office location id | `id` | Identifier | 64-bit | yes |  | 7722 | stored |
| Organisation | `organisation_id` | Reference → Organisation | 64-bit | yes |  | 1058 | stored |
| City | `city_id` | Reference → City | 32-bit | yes |  | 1 (Bengaluru) | stored |
| Address | `address_line` | Medium text | 1–2,000 chars | yes |  | 4th Floor, Prestige Tower, MG Road | stored |
| PIN / postal code | `postal_code` | Formatted text | ≤ 10 chars | no — not provided (optional for small towns) |  | 560001 | stored |
| Latitude | `latitude` | Coordinate | 8 digits, 6 decimals | no — not geocoded yet | degrees | 12.975512 | stored |
| Longitude | `longitude` | Coordinate | 9 digits, 6 decimals | no — not geocoded yet, always together with latitude | degrees | 77.606850 | stored |
| Headquarters | `is_headquarters` | Flag |  | yes |  | true | stored |

## ENT-12 Tax identifier — `organisation_tax_identifier`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Tax identifier id | `id` | Identifier | 64-bit | yes |  | 3132 | stored |
| Organisation | `organisation_id` | Reference → Organisation | 64-bit | yes |  | 1058 | stored |
| Country | `country_id` | Reference → Country | 16-bit | yes |  | 1 (IN) | stored |
| Tax identifier type | `tax_identifier_type_id` | Code → tax_identifier_type | 16-bit | yes |  | 1 (gstin) | stored |
| Identifier hash | `identifier_hmac` | Digest | 32 bytes | yes |  | \x7c11…0b (32 bytes) | stored |
| Last four characters | `identifier_last4` | Formatted text | bounded by its pattern | yes |  | 1Z5A | stored |
| Verification status | `verification_status_id` | Code → verification_status | 16-bit | yes |  | 1 (pending) | stored |
| Verified at | `verified_at` | Timestamp | µs, UTC | no — exactly when not verified | UTC | 2026-04-02 16:20:00+00 | stored |

## ENT-13 Membership — `organisation_member`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Membership id | `id` | Identifier | 64-bit | yes |  | 6147 | stored |
| Organisation | `organisation_id` | Reference → Organisation | 64-bit | yes |  | 1058 | stored |
| User | `app_user_id` | Reference → User | 64-bit | yes |  | 7041 | stored |
| Access role | `access_role_id` | Code → access_role | 16-bit | yes |  | 1 (super_admin) | stored |
| Member from | `valid_from` | Timestamp | µs, UTC | yes | UTC | 2026-04-05 09:00:00+00 | stored |
| Member until | `valid_to` | Timestamp | µs, UTC | no — the membership is current | UTC | 2026-09-30 18:00:00+00 | stored |

## ENT-14 Candidate profile — `candidate_profile`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Candidate profile id | `id` | Identifier | 64-bit | yes |  | 4411 | stored |
| User | `app_user_id` | Reference → User | 64-bit | yes |  | 7041 | stored |
| Full name | `full_name` | Person name | 1–150 chars | yes |  | Priya Sharma | stored |
| Headline | `headline` | Short text | 1–200 chars | no — not written yet |  | Java developer, 5 years | stored |
| Summary | `summary` | Medium text | 1–2,000 chars | no — not written yet |  | Backend engineer building payment systems… | stored |
| Profile language | `profile_language_id` | Reference → Language | 16-bit | no — unknown |  | 1 (en) | stored |
| Current city | `current_city_id` | Reference → City | 32-bit | no — not given yet; profiles without a city are excluded from city search |  | 1 (Bengaluru) | stored |
| Total experience | `total_experience_months` | Integer | 16-bit | yes | months | 62 | stored · stated by the candidate (finding F-03: can disagree with the work history) |
| Expected salary | `expected_salary_amount` | Money | 14 digits, 2 decimals | no — not disclosed or not provided, which salary_disclosure_id tells apart (rule group 5) | currency in the companion column | 1800000.00 | stored |
| Expected salary currency | `expected_salary_currency_id` | Reference → Currency | 16-bit | no — exactly when the expected salary amount is NULL |  | 1 (INR) | stored |
| Salary disclosure | `salary_disclosure_id` | Code → salary_disclosure | 16-bit | yes |  | 3 (not_provided) | stored |
| Notice period | `notice_period_days` | Integer | 16-bit | no — unknown, not asked yet | days | 30 | stored |
| Open to work | `is_open_to_work` | Flag |  | yes |  | true | stored |
| Profile visibility | `profile_visibility_id` | Code → profile_visibility | 16-bit | yes |  | 1 (public) | stored |
| Last active | `last_active_at` | Timestamp | µs, UTC | yes | UTC | 2026-10-23 19:44:00+00 | stored |
| Search vector | `search_vector` | Search vector |  | yes |  | 'developer':3 'java':2 'priya':1 | derived · generated column |
| Deleted at | `deleted_at` | Timestamp | µs, UTC | no — the row is live | UTC | 2026-10-12 09:30:15+00 | stored |

**Multi-valued attributes, moved out:** education → candidate_education; work history → candidate_experience; skills → candidate_skill; languages → candidate_language; resumes → resume; blocks → candidate_block; job alerts → job_alert.

## ENT-15 Education — `candidate_education`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Education id | `id` | Identifier | 64-bit | yes |  | 5832 | stored |
| Candidate profile | `candidate_profile_id` | Reference → Candidate profile | 64-bit | yes |  | 4411 | stored |
| Qualification | `qualification_id` | Code → qualification | 16-bit | yes |  | 1 (below_secondary) | stored |
| Institution | `institution_name` | Short text | 1–200 chars | yes |  | Anna University | stored |
| Field of study | `field_of_study` | Short text | 1–200 chars | no — not applicable (school levels have no field) |  | Computer Science | stored |
| Start date | `start_date` | Date |  | yes |  | 2016-07-01 | stored |
| End date | `end_date` | Date |  | no — still studying |  | 2020-05-31 | stored |

## ENT-16 Work experience — `candidate_experience`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Work experience id | `id` | Identifier | 64-bit | yes |  | 6588 | stored |
| Candidate profile | `candidate_profile_id` | Reference → Candidate profile | 64-bit | yes |  | 4411 | stored |
| Matched employer | `organisation_id` | Reference → Organisation | 64-bit | no — employer is not on Talentra (company_name is always kept) |  | 1058 | stored |
| Company | `company_name` | Short text | 1–200 chars | yes |  | Infosys | stored |
| Job title | `job_title` | Short text | 1–200 chars | yes |  | Senior Software Engineer | stored |
| Employment type | `employment_type_id` | Code → employment_type | 16-bit | yes |  | 1 (full_time) | stored |
| Start date | `start_date` | Date |  | yes |  | 2021-01-04 | stored |
| End date | `end_date` | Date |  | no — current job (at most one, uq_candidate_experience_one_current) |  | 2023-12-29 | stored |
| Description | `description` | Medium text | 1–2,000 chars | no — not written |  | Built the settlement service in Spring Boot. | stored |

## ENT-17 Candidate skill — `candidate_skill`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Candidate skill id | `id` | Identifier | 64-bit | yes |  | 2941 | stored |
| Candidate profile | `candidate_profile_id` | Reference → Candidate profile | 64-bit | yes |  | 4411 | stored |
| Skill | `skill_id` | Reference → Skill | 32-bit | yes |  | 6 (PostgreSQL) | stored |
| Proficiency level | `proficiency_level_id` | Code → proficiency_level | 16-bit | yes |  | 1 (beginner) | stored |
| Skill experience | `experience_months` | Integer | 16-bit | no — the candidate did not say | months | 48 | stored |

## ENT-18 Candidate language — `candidate_language`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Candidate language id | `id` | Identifier | 64-bit | yes |  | 4992 | stored |
| Candidate profile | `candidate_profile_id` | Reference → Candidate profile | 64-bit | yes |  | 4411 | stored |
| Language | `language_id` | Reference → Language | 16-bit | yes |  | 1 (en) | stored |
| Proficiency level | `proficiency_level_id` | Code → proficiency_level | 16-bit | yes |  | 1 (beginner) | stored |

## ENT-19 Resume — `resume`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Resume id | `id` | Identifier | 64-bit | yes |  | 5599 | stored |
| Candidate profile | `candidate_profile_id` | Reference → Candidate profile | 64-bit | yes |  | 4411 | stored |
| Version | `version_number` | Integer | 16-bit | yes | version | 3 | stored |
| File key | `storage_key` | Formatted text | bounded by its pattern | yes |  | resumes/1042/3f6c2b9e-8f4a-4d7e-9a51-2c0e6b7d1f90.pdf | stored |
| File checksum | `file_sha256` | Digest | 32 bytes | yes |  | \x5be2…c9 (32 bytes) | stored |
| Content language | `content_language_id` | Reference → Language | 16-bit | no — language not detected |  | 1 (en) | stored |
| Primary resume | `is_primary` | Flag |  | yes |  | true | stored |

## ENT-20 Block — `candidate_block`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Block id | `id` | Identifier | 64-bit | yes |  | 2801 | stored |
| Candidate profile | `candidate_profile_id` | Reference → Candidate profile | 64-bit | yes |  | 4411 | stored |
| Blocked company | `blocked_organisation_id` | Reference → Organisation | 64-bit | no — the block targets one person instead |  | 1058 | stored |
| Blocked person | `blocked_app_user_id` | Reference → User | 64-bit | no — the block targets a company instead |  | 7041 | stored |
| Blocked at | `blocked_at` | Timestamp | µs, UTC | yes | UTC | 2026-08-11 13:05:00+00 | stored |
| Unblocked at | `unblocked_at` | Timestamp | µs, UTC | no — block is active | UTC | 2026-09-01 10:00:00+00 | stored |

## ENT-21 Job alert — `job_alert`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Job alert id | `id` | Identifier | 64-bit | yes |  | 7622 | stored |
| Candidate profile | `candidate_profile_id` | Reference → Candidate profile | 64-bit | yes |  | 4411 | stored |
| Keywords | `keywords` | Short text | 1–200 chars | yes |  | java spring boot | stored |
| City | `city_id` | Reference → City | 32-bit | no — any city |  | 1 (Bengaluru) | stored |
| Minimum salary | `min_salary_amount` | Money | 14 digits, 2 decimals | no — no salary filter | currency in the companion column | 1000000.00 | stored |
| Salary currency | `salary_currency_id` | Reference → Currency | 16-bit | no — exactly when there is no salary filter |  | 1 (INR) | stored |
| Alert frequency | `alert_frequency_id` | Code → alert_frequency | 16-bit | yes |  | 2 (daily) | stored |
| Active | `is_active` | Flag |  | yes |  | true | stored |
| Last sent | `last_sent_at` | Timestamp | µs, UTC | no — never sent yet | UTC | 2026-10-24 03:30:00+00 | stored |

## ENT-22 Job requirement — `job_requirement`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Job requirement id | `id` | Identifier | 64-bit | yes |  | 3277 | stored |
| Organisation | `organisation_id` | Reference → Organisation | 64-bit | yes |  | 1058 | stored |
| Job title | `title` | Short text | 1–200 chars | yes |  | Java Developer (Spring Boot) | stored |
| Description | `description` | Long text | 1–20,000 chars | yes |  | We are hiring… | stored |
| Description language | `description_language_id` | Reference → Language | 16-bit | no — language not detected |  | 1 (en) | stored |
| Employment type | `employment_type_id` | Code → employment_type | 16-bit | yes |  | 1 (full_time) | stored |
| Work mode | `work_mode_id` | Code → work_mode | 16-bit | yes |  | 1 (onsite) | stored |
| Industry | `industry_id` | Code → industry | 16-bit | yes |  | 1 (information_technology) | stored |
| Minimum experience | `min_experience_months` | Integer | 16-bit | yes | months | 24 | stored |
| Maximum experience | `max_experience_months` | Integer | 16-bit | no — no upper limit | months | 60 | stored |
| Salary from | `salary_min_amount` | Money | 14 digits, 2 decimals | no — salary not disclosed (salary_disclosure_id = not_disclosed) | currency in the companion column | 1200000.00 | stored |
| Salary to | `salary_max_amount` | Money | 14 digits, 2 decimals | no — no upper figure given, or not disclosed | currency in the companion column | 1800000.00 | stored |
| Salary currency | `salary_currency_id` | Reference → Currency | 16-bit | no — exactly when no salary is given |  | 1 (INR) | stored |
| Salary disclosure | `salary_disclosure_id` | Code → salary_disclosure | 16-bit | yes |  | 1 (disclosed) | stored |
| Positions | `positions_total` | Integer | 16-bit | yes | people | 3 | stored |
| Positions filled | `positions_filled` | Integer | 16-bit | yes | people | 1 | derived · count of joined applications, kept by the pipeline trigger |
| Job status | `job_status_id` | Code → job_status | 16-bit | yes |  | 1 (draft) | stored |
| Open to consultants | `is_open_to_consultants` | Flag |  | yes |  | false | stored |
| Published at | `published_at` | Timestamp | µs, UTC | no — exactly while the job is a draft (ck_job_requirement_published) | UTC | 2026-10-01 05:30:00+00 | stored |
| Closing date | `closes_on` | Date |  | no — open until filled or closed by hand |  | 2026-11-15 | stored |
| Search vector | `search_vector` | Search vector |  | yes |  | 'developer':2 'java':1 | derived · generated column |
| Deleted at | `deleted_at` | Timestamp | µs, UTC | no — the row is live | UTC | 2026-10-12 09:30:15+00 | stored |

**Multi-valued attributes, moved out:** cities → job_requirement_location; skills → job_requirement_skill; questions → screening_question.

## ENT-23 Job location — `job_requirement_location`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Job location id | `id` | Identifier | 64-bit | yes |  | 9941 | stored |
| Job requirement | `job_requirement_id` | Reference → Job requirement | 64-bit | yes |  | 3277 | stored |
| City | `city_id` | Reference → City | 32-bit | yes |  | 1 (Bengaluru) | stored |

## ENT-24 Required skill — `job_requirement_skill`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Required skill id | `id` | Identifier | 64-bit | yes |  | 7743 | stored |
| Job requirement | `job_requirement_id` | Reference → Job requirement | 64-bit | yes |  | 3277 | stored |
| Skill | `skill_id` | Reference → Skill | 32-bit | yes |  | 6 (PostgreSQL) | stored |
| Mandatory skill | `is_mandatory` | Flag |  | yes |  | true | stored |

## ENT-25 Screening question — `screening_question`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Screening question id | `id` | Identifier | 64-bit | yes |  | 5587 | stored |
| Job requirement | `job_requirement_id` | Reference → Job requirement | 64-bit | yes |  | 3277 | stored |
| Question | `question_text` | Short text | 1–200 chars | yes |  | Are you willing to relocate to Pune? | stored |
| Answer type | `answer_type_id` | Code → answer_type | 16-bit | yes |  | 1 (yes_no) | stored |
| Required | `is_required` | Flag |  | yes |  | true | stored |
| Order | `sort_order` | Integer | 16-bit | yes | rank | 1 | stored |

## ENT-26 Application — `application`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Application id | `id` | Identifier | 64-bit | yes |  | 9204 | stored |
| Job requirement | `job_requirement_id` | Reference → Job requirement | 64-bit | yes |  | 3277 | stored |
| Organisation | `organisation_id` | Reference → Organisation | 64-bit | yes |  | 1058 | derived · copied from the job, pinned by a composite key |
| Candidate profile | `candidate_profile_id` | Reference → Candidate profile | 64-bit | yes |  | 4411 | stored |
| Resume | `resume_id` | Reference → Resume | 64-bit | no — quick apply without a resume (blue-collar roles) |  | 5599 | stored |
| Application status | `application_status_id` | Code → application_status | 16-bit | yes |  | 1 (applied) | stored |
| Application source | `application_source_id` | Code → application_source | 16-bit | yes |  | 1 (direct) | stored |
| Sourced by | `sourced_by_app_user_id` | Reference → User | 64-bit | no — the candidate applied directly |  | 7041 | stored |
| Applied at | `applied_at` | Timestamp | µs, UTC | yes | UTC | 2026-10-03 14:22:10+00 | stored |
| Status changed at | `status_changed_at` | Timestamp | µs, UTC | yes | UTC | 2026-10-09 11:00:00+00 | derived at write · time of the latest move |

**Multi-valued attributes, moved out:** answers → application_answer; status history → application_status_history.

## ENT-27 Answer — `application_answer`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Answer id | `id` | Identifier | 64-bit | yes |  | 5461 | stored |
| Application | `application_id` | Reference → Application | 64-bit | yes |  | 9204 | stored |
| Job requirement | `job_requirement_id` | Integer | 64-bit | yes |  | 3277 | derived · copied so two composite keys prove the question is the job's |
| Screening question | `screening_question_id` | Reference → Screening question | 64-bit | yes |  | 5587 | stored |
| Answer | `answer_text` | Short text | 1–200 chars | yes |  | yes | stored |

## ENT-28 Status change — `application_status_history`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Status change id | `id` | Identifier | 64-bit | yes |  | 2768 | stored |
| Application | `application_id` | Reference → Application | 64-bit | yes |  | 9204 | stored |
| From status | `from_status_id` | Code → application_status | 16-bit | no — the first entry, when the application was created |  | 1 (applied) | stored |
| To status | `to_status_id` | Code → application_status | 16-bit | yes |  | 1 (applied) | stored |
| Changed at | `changed_at` | Timestamp | µs, UTC | yes | UTC | 2026-10-09 11:00:00+00 | stored |

## ENT-29 Allowed transition — `application_status_transition`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Allowed transition id | `id` | Identifier | 16-bit | yes |  | 4959 | stored |
| From status | `from_status_id` | Code → application_status | 16-bit | yes |  | 1 (applied) | stored |
| To status | `to_status_id` | Code → application_status | 16-bit | yes |  | 1 (applied) | stored |

## ENT-29 Allowed transition — `job_status_transition`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Allowed transition id | `id` | Identifier | 16-bit | yes |  | 7960 | stored |
| From status | `from_status_id` | Code → job_status | 16-bit | yes |  | 1 (draft) | stored |
| To status | `to_status_id` | Code → job_status | 16-bit | yes |  | 1 (draft) | stored |

## ENT-30 Plan — `plan`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Plan id | `id` | Identifier | 16-bit | yes |  | 2 | stored |
| Plan code | `code` | Code | 1–50 chars | yes |  | growth | stored |
| Plan name | `name` | Short text | 1–200 chars | yes |  | Growth | stored |
| Price | `price_amount` | Money | 14 digits, 2 decimals | yes | currency in the companion column | 24999.00 | stored |
| Price currency | `price_currency_id` | Reference → Currency | 16-bit | yes |  | 1 (INR) | stored |
| Billing period | `billing_period_months` | Integer | 16-bit | yes | months | 3 | stored |
| Seats | `max_seats` | Integer | 32-bit | yes | users | 5 | stored |
| Devices per user | `max_devices_per_user` | Integer | 32-bit | yes | devices | 2 | stored |
| Included credits | `included_credits` | Credits | 32-bit integer | yes | credits | 300 | stored |
| Is active | `is_active` | Flag |  | yes |  | true | stored |

## ENT-31 Subscription (licence) — `subscription`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Subscription (licence) id | `id` | Identifier | 64-bit | yes |  | 1219 | stored |
| Organisation | `organisation_id` | Reference → Organisation | 64-bit | yes |  | 1058 | stored |
| Plan | `plan_id` | Reference → Plan | 16-bit | yes |  | 2 (growth) | stored |
| Seats (licence) | `max_seats` | Integer | 32-bit | yes | users | 5 | snapshot · copied from the plan at purchase (history, not redundancy) |
| Devices per user (licence) | `max_devices_per_user` | Integer | 32-bit | yes | devices | 2 | snapshot · copied from the plan at purchase |
| Starts on | `starts_on` | Date |  | yes |  | 2026-10-01 | stored |
| Ends on | `ends_on` | Date |  | yes |  | 2027-01-01 | stored |
| Auto-renew | `auto_renew` | Flag |  | yes |  | true | stored |
| Cancelled at | `cancelled_at` | Timestamp | µs, UTC | no — not cancelled | UTC | 2026-11-20 10:00:00+00 | stored |
| Renews | `renewed_from_subscription_id` | Reference → Subscription (licence) | 64-bit | no — first subscription of the organisation |  | 1219 | stored |
| Payment order | `payment_order_id` | Reference → Payment order | 64-bit | no — complimentary or migrated period |  | 1807 | stored |

## ENT-32 Wallet — `wallet`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Wallet id | `id` | Identifier | 64-bit | yes |  | 5543 | stored |
| Organisation | `organisation_id` | Reference → Organisation | 64-bit | yes |  | 1058 | stored |
| Balance | `balance_credits` | Credits | 32-bit integer | yes | credits | 245 | derived · sum of the ledger, written only with each entry |

**Multi-valued attributes, moved out:** movements → wallet_ledger_entry.

## ENT-33 Ledger entry — `wallet_ledger_entry`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Ledger entry id | `id` | Identifier | 64-bit | yes |  | 6196 | stored |
| Wallet | `wallet_id` | Reference → Wallet | 64-bit | yes |  | 5543 | stored |
| Ledger entry type | `ledger_entry_type_id` | Code → ledger_entry_type | 16-bit | yes |  | 1 (recharge) | stored |
| Credits | `credits` | Credits | 32-bit integer | yes | credits | -1 | stored |
| Balance after | `balance_after` | Credits | 32-bit integer | yes | credits | 244 | derived at write · running balance |
| Reverses | `reverses_ledger_entry_id` | Reference → Ledger entry | 64-bit | no — not a reversal |  | 6196 | stored |
| Payment order | `payment_order_id` | Reference → Payment order | 64-bit | no — a debit for platform usage |  | 1807 | stored |
| Idempotency key | `idempotency_key` | Formatted text | ≤ 100 chars | yes |  | download:17:1042:20261012093015123456 | stored |
| Occurred at | `occurred_at` | Timestamp | µs, UTC | yes | UTC | 2026-10-12 09:30:15+00 | stored |

## ENT-34 Payment order — `payment_order`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Payment order id | `id` | Identifier | 64-bit | yes |  | 1807 | stored |
| Organisation | `organisation_id` | Reference → Organisation | 64-bit | yes |  | 1058 | stored |
| Payment purpose | `payment_purpose_id` | Code → payment_purpose | 16-bit | yes |  | 1 (wallet_recharge) | stored |
| Amount | `amount` | Money | 14 digits, 2 decimals | yes | currency in the companion column | 24999.00 | stored |
| Currency | `currency_id` | Reference → Currency | 16-bit | yes |  | 1 (INR) | stored |
| Credits to grant | `credits_to_grant` | Credits | 32-bit integer | no — exactly when the order is for a subscription | credits | 100 | stored |
| Plan | `plan_id` | Reference → Plan | 16-bit | no — exactly when the order is a wallet recharge |  | 2 (growth) | stored |
| Payment status | `payment_status_id` | Code → payment_status | 16-bit | yes |  | 1 (created) | stored |
| Gateway order id | `gateway_order_ref` | Formatted text | ≤ 64 chars | no — the gateway has not created the order yet |  | order_N8x2Kq7LmP | stored |
| Idempotency key | `idempotency_key` | Formatted text | ≤ 100 chars | yes |  | po-7f3a9c2e-recharge | stored |

**Multi-valued attributes, moved out:** gateway events → payment_event.

## ENT-35 Payment event — `payment_event`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Payment event id | `id` | Identifier | 64-bit | yes |  | 1849 | stored |
| Payment order | `payment_order_id` | Reference → Payment order | 64-bit | yes |  | 1807 | stored |
| Payment status | `payment_status_id` | Code → payment_status | 16-bit | yes |  | 1 (created) | stored |
| Gateway event id | `gateway_event_ref` | Formatted text | ≤ 64 chars | yes |  | evt_Qm81Lx0aZ3 | stored |
| Amount | `amount` | Money | 14 digits, 2 decimals | yes | currency in the companion column | 24999.00 | stored |
| Currency | `currency_id` | Reference → Currency | 16-bit | yes |  | 1 (INR) | stored |
| Occurred at | `occurred_at` | Timestamp | µs, UTC | yes | UTC | 2026-10-01 05:31:12+00 | stored |
| Payload hash | `payload_sha256` | Digest | 32 bytes | yes |  | \xa3f9…44 (32 bytes) | stored |

## ENT-36 Invoice — `invoice`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Invoice id | `id` | Identifier | 64-bit | yes |  | 6243 | stored |
| Payment order | `payment_order_id` | Reference → Payment order | 64-bit | yes |  | 1807 | stored |
| Invoice number | `invoice_number` | Formatted text | bounded by its pattern | yes |  | TAL-2026-000418 | stored |
| Issued on | `issued_on` | Date |  | yes |  | 2026-10-01 | stored |
| Taxable value | `subtotal_amount` | Money | 14 digits, 2 decimals | yes | currency in the companion column | 21185.59 | derived at write · amount ÷ 1.18 |
| GST | `tax_amount` | Money | 14 digits, 2 decimals | yes | currency in the companion column | 3813.41 | derived at write · amount - subtotal |
| Total | `total_amount` | Money | 14 digits, 2 decimals | yes | currency in the companion column | 24999.00 | derived at write · = payment amount |
| Currency | `currency_id` | Reference → Currency | 16-bit | yes |  | 1 (INR) | stored |

## ENT-37 Profile download — `profile_download`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Profile download id | `id` | Identifier | 64-bit | yes |  | 3928 | stored |
| Organisation | `organisation_id` | Reference → Organisation | 64-bit | yes |  | 1058 | stored |
| User | `app_user_id` | Reference → User | 64-bit | yes |  | 7041 | stored |
| Candidate profile | `candidate_profile_id` | Reference → Candidate profile | 64-bit | yes |  | 4411 | stored |
| Ledger entry | `wallet_ledger_entry_id` | Reference → Ledger entry | 64-bit | yes |  | 6196 | stored |
| Downloaded at | `downloaded_at` | Timestamp | µs, UTC | yes | UTC | 2026-10-12 09:30:15+00 | stored |

## ENT-38 Notification preference — `notification_preference`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Notification preference id | `id` | Identifier | 64-bit | yes |  | 9059 | stored |
| User | `app_user_id` | Reference → User | 64-bit | yes |  | 7041 | stored |
| Notification category | `notification_category_id` | Code → notification_category | 16-bit | yes |  | 1 (job_alert) | stored |
| Notification channel | `notification_channel_id` | Code → notification_channel | 16-bit | yes |  | 1 (email) | stored |
| Enabled | `is_enabled` | Flag |  | yes |  | false | stored |

## ENT-39 Notification — `notification`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Notification id | `id` | Identifier | 64-bit | yes |  | 1009 | stored |
| User | `app_user_id` | Reference → User | 64-bit | yes |  | 7041 | stored |
| Notification category | `notification_category_id` | Code → notification_category | 16-bit | yes |  | 1 (job_alert) | stored |
| Notification channel | `notification_channel_id` | Code → notification_channel | 16-bit | yes |  | 1 (email) | stored |
| Template | `template_key` | Formatted text | bounded by its pattern | yes |  | application.status_changed | stored |
| Template variables | `payload` | Document (JSON) | ≤ 2048 bytes | yes |  | {"application_id": 88213, "status": 2} | stored |
| Notification status | `notification_status_id` | Code → notification_status | 16-bit | yes |  | 1 (queued) | stored |
| Dedupe key | `dedupe_key` | Formatted text | ≤ 200 chars | no — no dedupe needed |  | application_status:88213:2 | stored |
| Attempts | `attempt_count` | Integer | 16-bit | yes | attempts | 1 | stored |
| Queued at | `queued_at` | Timestamp | µs, UTC | yes | UTC | 2026-10-09 11:00:00+00 | stored |
| Next attempt | `next_attempt_at` | Timestamp | µs, UTC | yes | UTC | 2026-10-09 11:00:00+00 | stored |
| Sent at | `sent_at` | Timestamp | µs, UTC | no — not handed to the provider yet | UTC | 2026-10-09 11:00:04+00 | stored |
| Delivered at | `delivered_at` | Timestamp | µs, UTC | no — no delivery receipt (yet, or channel gives none) | UTC | 2026-10-09 11:00:09+00 | stored |
| Provider message id | `provider_message_ref` | Formatted text | ≤ 128 chars | no — not sent yet |  | msg_7Hq2LmZ81 | stored |
| Failure reason | `failure_reason` | Short text | 1–200 chars | no — exactly when not failed |  | mailbox full | stored |

**Multi-valued attributes, moved out:** payload: composite JSON of template variables, bounded to 2 KB.

## ENT-40 Audit event — `audit_event`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Audit event id | `id` | Identifier | 64-bit | yes |  | 9232 | stored |
| Occurred at | `occurred_at` | Timestamp | µs, UTC | yes | UTC | 2026-10-12 09:30:15+00 | stored |
| Actor | `actor_app_user_id` | Reference → User | 64-bit | no — a system process (scheduler, payment webhook, migration) |  | 7041 | stored |
| Organisation | `organisation_id` | Reference → Organisation | 64-bit | no — not organisation-scoped |  | 1058 | stored |
| Action | `action` | Formatted text | bounded by its pattern | yes |  | payment_order.captured | stored |
| Table | `entity_table` | Formatted text | bounded by its pattern | yes |  | payment_order | stored |
| Row id | `entity_id` | Integer | 64-bit | no — the action has no single row (e.g |  | 5531 | stored |
| Details | `details` | Document (JSON) | ≤ 4096 bytes | yes |  | {"changed": ["valid_to"]} | stored |

**Multi-valued attributes, moved out:** details: composite JSON (changed column names), bounded to 4 KB, never queried by field.

## ENT-41 System error — `system_error`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| System error id | `id` | Identifier | 64-bit | yes |  | 1282 | stored |
| Occurred at | `occurred_at` | Timestamp | µs, UTC | yes | UTC | 2026-10-24 02:10:44+00 | stored |
| Service | `service_name` | Short text | 1–200 chars | yes |  | notification-worker | stored |
| Error code | `error_code` | Short text | 1–200 chars | yes |  | SMTP_TIMEOUT | stored |
| Message | `message` | Medium text | 1–2,000 chars | yes |  | connection to smtp provider timed out after 10s | stored |
| User | `app_user_id` | Reference → User | 64-bit | no — background job or anonymous request |  | 7041 | stored |
| Context | `context` | Document (JSON) | ≤ 8192 bytes | yes |  | {"notification_id": 90112, "attempt": 3} | stored |

**Multi-valued attributes, moved out:** context: composite JSON, bounded to 8 KB.

## ENT-43 Language — `language`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Language id | `id` | Identifier | 16-bit | yes |  | 1 | stored |
| Language code | `code` | Formatted text | bounded by its pattern | yes |  | hi | stored |
| Native name | `native_name` | Short text | 1–200 chars | yes |  | हिन्दी | stored |
| Offered as UI language | `is_ui_language` | Flag |  | yes |  | true | stored |
| Is active | `is_active` | Flag |  | yes |  | true | stored |
| Sort order | `sort_order` | Integer | 16-bit | yes | rank | 1 | stored |

## ENT-44 UI label — `ui_label`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| UI label id | `id` | Identifier | 32-bit | yes |  | 57 | stored |
| Label key | `label_key` | Formatted text | bounded by its pattern | yes |  | application_status.shortlisted | stored |

## ENT-45 UI translation — `ui_translation`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| UI translation id | `id` | Identifier | 32-bit | yes |  | 2612 | stored |
| UI label | `ui_label_id` | Reference → UI label | 32-bit | yes |  | 57 | stored |
| Language | `language_id` | Reference → Language | 16-bit | yes |  | 1 (en) | stored |
| Label text | `label_text` | Short text | 1–200 chars | yes |  | शॉर्टलिस्ट | stored |

## ENT-46 Currency — `currency`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Currency id | `id` | Identifier | 16-bit | yes |  | 1 | stored |
| Currency code | `code` | Formatted text | 3 chars | yes |  | INR | stored |
| Decimal places | `minor_units` | Integer | 16-bit | yes | digits | 2 | stored |
| Is active | `is_active` | Flag |  | yes |  | true | stored |

## ENT-47 Country — `country`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Country id | `id` | Identifier | 16-bit | yes |  | 1 | stored |
| Country code | `iso2` | Formatted text | 2 chars | yes |  | IN | stored |
| Country name | `name` | Short text | 1–200 chars | yes |  | India | stored |
| Phone country code | `phone_country_code` | Formatted text | ≤ 3 chars | yes |  | +91 | stored |
| Currency | `currency_id` | Reference → Currency | 16-bit | yes |  | 1 (INR) | stored |
| Is active | `is_active` | Flag |  | yes |  | true | stored |

## ENT-48 State — `state`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| State id | `id` | Identifier | 16-bit | yes |  | 1 | stored |
| Country | `country_id` | Reference → Country | 16-bit | yes |  | 1 (IN) | stored |
| State code | `code` | Formatted text | ≤ 5 chars | yes |  | KA | stored |
| State name | `name` | Short text | 1–200 chars | yes |  | Karnataka | stored |

## ENT-49 City — `city`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| City id | `id` | Identifier | 32-bit | yes |  | 1 | stored |
| State | `state_id` | Reference → State | 16-bit | yes |  | 1 (KA) | stored |
| City name | `name` | Short text | 1–200 chars | yes |  | Bengaluru | stored |
| Latitude | `latitude` | Coordinate | 8 digits, 6 decimals | yes | degrees | 12.971599 | stored |
| Longitude | `longitude` | Coordinate | 9 digits, 6 decimals | yes | degrees | 77.594566 | stored |
| Is active | `is_active` | Flag |  | yes |  | true | stored |

## ENT-50 Skill — `skill`

| Attribute | Column | Logical type | Length | Mandatory | Unit | Example | Stored / derived |
|---|---|---|---|---|---|---|---|
| Skill id | `id` | Identifier | 32-bit | yes |  | 6 | stored |
| Skill name | `name` | Short text | 1–200 chars | yes |  | PostgreSQL | stored |
| Is active | `is_active` | Flag |  | yes |  | true | stored |

## ENT-51 Enumeration value — 23 lookup tables, one shape

| Attribute | Column | Logical type | Length | Mandatory | Example |
|---|---|---|---|---|---|
| Value id | `id` | Identifier (position in the list) | 16-bit | yes | 2 |
| Code | `code` | Code `[a-z][a-z0-9_]*` | 1–50 chars | yes | shortlisted |
| Label | `ui_label_id` | Reference → UI label (translated) | 32-bit | yes | 57 |
| Active | `is_active` | Flag | | yes, default true | true |
| Order | `sort_order` | Integer | 16-bit | yes, default 0 | 2 |

| Lookup | Values |
|---|---|
| `account_status` | active · suspended · deactivated · erased |
| `verification_status` | pending · verified · rejected |
| `access_role` | super_admin · admin · account_admin · employer · recruiter · consultant · placement_officer · candidate |
| `access_permission` | user_manage · organisation_verify · job_post · job_manage · application_manage · candidate_search · candidate_download · billing_manage · audit_read · consultant_source · member_manage |
| `employment_type` | full_time · part_time · contract · internship · apprenticeship · temporary |
| `work_mode` | onsite · remote · hybrid |
| `industry` | information_technology · banking_financial_services · healthcare · manufacturing · retail · ecommerce · logistics · education · telecom · construction · hospitality · automotive · pharmaceuticals · media · consulting |
| `qualification` | below_secondary · secondary · higher_secondary · iti · diploma · bachelors · masters · doctorate |
| `proficiency_level` | beginner · intermediate · advanced · expert · native |
| `salary_disclosure` | disclosed · not_disclosed · not_provided |
| `profile_visibility` | public · recruiters_only · hidden |
| `consent_purpose` | terms_of_service · privacy_policy · profile_visible_to_recruiters · marketing_email · whatsapp_alerts |
| `tax_identifier_type` | gstin · pan · cin · vat · ein |
| `job_status` | draft · open · paused · closed · filled |
| `application_status` | applied · shortlisted · interviewing · offered · joined · rejected · withdrawn |
| `application_source` | direct · recruiter_outreach · consultant · referral · campus |
| `answer_type` | yes_no · number · short_text |
| `ledger_entry_type` | recharge · plan_grant · job_post_debit · profile_download_debit · outreach_debit · reversal |
| `payment_purpose` | wallet_recharge · subscription |
| `payment_status` | created · authorised · captured · failed · refunded |
| `notification_channel` | email · sms · whatsapp · in_app |
| `notification_category` | job_alert · application_update · account_security · billing · marketing |
| `notification_status` | queued · sent · delivered · failed · suppressed |
| `alert_frequency` | instant · daily · weekly |
| `session_end_reason` | logout · idle_timeout · revoked_by_user · revoked_by_admin |

## Check

- **Attributes listed:** 337 (plus 4 audit attributes on each business entity, and the shared lookup shape).
- **Missing a type:** 0. **Missing an example:** 0. (Exit test: both 0.)
- **Derived or snapshot attributes:** 15, each saying what it is derived from and what keeps it consistent.
