# Talentra — Phase 1 Data Dictionary

Generated from the live PostgreSQL 16 catalog by `sql/tests/data_dictionary.sql`. Class and null justification come from column comments; columns without a class tag are **Internal** (audit columns, surrogate/foreign keys). Partitions are omitted (they inherit the parent's columns).

### activity_type
lookup; login, logout, profile_update, resume_upload, resume_download, ...

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |
| is_sensitive | boolean | NOT NULL | Internal |  |  |

### address_type
lookup; current, permanent, correspondence

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### application

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| job_requirement_id | bigint | NOT NULL | Internal | job_requirement |  |
| candidate_profile_id | bigint | NOT NULL | Internal | candidate_profile |  |
| application_status_id | bigint | NOT NULL | Internal | application_status |  |
| status_changed_at | timestamp with time zone | NOT NULL | Internal |  |  |
| application_source_id | bigint | NOT NULL | Internal | application_source |  |
| applied_at | timestamp with time zone | NOT NULL | Internal |  |  |
| resume_version_id | bigint | NULL | Personal | resume_version | null=legacy import or quick-apply without resume |
| cover_note | character varying(4000) | NULL | Personal |  | null=no cover note |
| sourced_by_user_account_id | bigint | NULL | Internal | user_account | null=candidate applied directly |
| rejection_reason_id | bigint | NULL | Internal | rejection_reason | null=not rejected or reason not given |
| status_note | character varying(1000) | NULL | Internal |  | null=no note on last status change |
| legacy_source_system_id | bigint | NULL | Internal | legacy_source_system | null=created natively |
| legacy_record_ref | character varying(100) | NULL | Internal |  | null=created natively |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### application_answer

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| application_id | bigint | NOT NULL | Internal | application |  |
| questionnaire_question_id | bigint | NOT NULL | Internal | questionnaire_question |  |
| questionnaire_question_option_id | bigint | NULL | Personal | questionnaire_question_option | null=answer given as text or number instead (exactly one set, CHECK) |
| answer_text | character varying(2000) | NULL | Personal |  | null=answer given as option or number instead |
| answer_number | numeric(14,2) | NULL | Personal |  | null=answer given as option or text instead |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### application_source
lookup; direct, sourced, consultant, referral, campus_drive, bulk_outreach, legacy_import

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### application_status
lookup; pipeline stage; transitions governed by application_status_transition

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |
| is_initial | boolean | NOT NULL | Internal |  |  |
| is_terminal | boolean | NOT NULL | Internal |  |  |

### application_status_history

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| application_id | bigint | NOT NULL | Internal | application |  |
| from_application_status_id | bigint | NULL | Internal | application_status | null=first status (application created) |
| to_application_status_id | bigint | NOT NULL | Internal | application_status |  |
| rejection_reason_id | bigint | NULL | Internal | rejection_reason | null=not a rejection |
| status_note | character varying(1000) | NULL | Internal |  | null=no note |
| changed_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |

### application_status_transition

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| from_application_status_id | bigint | NOT NULL | Internal | application_status |  |
| to_application_status_id | bigint | NOT NULL | Internal | application_status |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### assessment

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| assessment_type_id | bigint | NOT NULL | Internal | assessment_type |  |
| skill_id | bigint | NULL | Public | skill | null=assessment is not skill-specific (psychometric) |
| title | character varying(200) | NOT NULL | Internal |  |  |
| max_score | numeric(7,2) | NOT NULL | Internal |  |  |
| pass_score | numeric(7,2) | NULL | Public |  | null=no pass mark (self-assessment) |
| duration_minutes | integer | NULL | Public |  | null=untimed |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### assessment_type
lookup; self_assessment, skill_test, psychometric, language_test

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### candidate_activity_log

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| candidate_profile_id | bigint | NOT NULL | Internal | candidate_profile |  |
| activity_type_id | bigint | NOT NULL | Internal | activity_type |  |
| occurred_at | timestamp with time zone | NOT NULL | Internal |  |  |
| source_ip | inet | NULL | Personal |  | null=server-side event (scheduled job) |
| user_agent | character varying(500) | NULL | Personal |  | null=server-side event |
| detail | jsonb | NULL | Personal |  | bounded 4 KB; null=no extra detail for this activity type |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |

### candidate_address

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| candidate_profile_id | bigint | NOT NULL | Internal | candidate_profile |  |
| address_type_id | bigint | NOT NULL | Internal | address_type |  |
| address_line_1 | character varying(250) | NOT NULL | Personal |  |  |
| address_line_2 | character varying(250) | NULL | Personal |  | null=address fits on one line |
| city_id | bigint | NOT NULL | Internal | city |  |
| postal_code | character varying(20) | NULL | Personal |  | null=country without postal codes or not provided |
| latitude | numeric(9,6) | NULL | Personal |  | WGS84 6 dp; null=not geocoded (optional service) |
| longitude | numeric(9,6) | NULL | Personal |  | WGS84 6 dp; null=not geocoded |
| coordinate_source_id | bigint | NULL | Internal | coordinate_source | null only when coordinates are null |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### candidate_assessment_result

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| candidate_profile_id | bigint | NOT NULL | Internal | candidate_profile |  |
| assessment_id | bigint | NOT NULL | Internal | assessment |  |
| attempt_number | integer | NOT NULL | Internal |  |  |
| started_at | timestamp with time zone | NOT NULL | Internal |  |  |
| completed_at | timestamp with time zone | NULL | Personal |  | null=attempt in progress or abandoned |
| score | numeric(7,2) | NULL | Personal |  | null=not completed |
| score_pct | numeric(5,2) | NULL | Personal |  | 0..100; null=not completed |
| is_passed | boolean | NULL | Personal |  | null=not completed or assessment has no pass mark |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### candidate_certification

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| candidate_profile_id | bigint | NOT NULL | Internal | candidate_profile |  |
| certification_name | character varying(250) | NOT NULL | Internal |  |  |
| issuing_body | character varying(250) | NOT NULL | Internal |  |  |
| credential_ref | character varying(100) | NULL | Personal |  | null=certificate has no id |
| credential_url | character varying(500) | NULL | Personal |  | null=no online verification link |
| issued_on | date | NULL | Public |  | null=not stated |
| expires_on | date | NULL | Public |  | null=does not expire |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### candidate_education

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| candidate_profile_id | bigint | NOT NULL | Internal | candidate_profile |  |
| qualification_id | bigint | NOT NULL | Internal | qualification |  |
| field_of_study_id | bigint | NULL | Public | field_of_study | null=qualification has no specialisation (e.g. 10th) |
| institution_id | bigint | NULL | Public | institution | null=institution not in master, institution_name used |
| institution_name | character varying(250) | NULL | Public |  | null=institution_id is set |
| education_mode_id | bigint | NULL | Public | education_mode | null=not stated |
| start_date | date | NULL | Public |  | null=not stated (common in legacy data) |
| end_date | date | NULL | Public |  | null=ongoing or not stated |
| is_ongoing | boolean | NOT NULL | Internal |  |  |
| grade_scale_id | bigint | NULL | Personal | grade_scale | null=grade not disclosed |
| grade_value | character varying(20) | NULL | Personal |  | null=grade not disclosed |
| is_highest | boolean | NOT NULL | Internal |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### candidate_email

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| candidate_profile_id | bigint | NOT NULL | Internal | candidate_profile |  |
| email | character varying(254) | NOT NULL | Personal |  |  |
| is_primary | boolean | NOT NULL | Internal |  |  |
| verified_at | timestamp with time zone | NULL | Internal |  | null=not verified yet |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### candidate_language

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| candidate_profile_id | bigint | NOT NULL | Internal | candidate_profile |  |
| language_id | bigint | NOT NULL | Internal | language |  |
| language_proficiency_level_id | bigint | NOT NULL | Internal | language_proficiency_level |  |
| can_read | boolean | NOT NULL | Internal |  |  |
| can_write | boolean | NOT NULL | Internal |  |  |
| can_speak | boolean | NOT NULL | Internal |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### candidate_phone

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| candidate_profile_id | bigint | NOT NULL | Internal | candidate_profile |  |
| phone_e164 | character varying(16) | NOT NULL | Personal |  | E.164 with country code |
| country_id | bigint | NOT NULL | Internal | country |  |
| phone_type_id | bigint | NOT NULL | Internal | phone_type |  |
| is_primary | boolean | NOT NULL | Internal |  |  |
| verified_at | timestamp with time zone | NULL | Internal |  | null=not verified yet |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### candidate_preferred_job_role

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| candidate_profile_id | bigint | NOT NULL | Internal | candidate_profile |  |
| job_role_id | bigint | NOT NULL | Internal | job_role |  |
| employment_type_id | bigint | NULL | Public | employment_type | null=any employment type |
| work_mode_id | bigint | NULL | Public | work_mode | null=any work mode |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### candidate_preferred_location

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| candidate_profile_id | bigint | NOT NULL | Internal | candidate_profile |  |
| city_id | bigint | NOT NULL | Internal | city |  |
| sort_order | integer | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### candidate_profile

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| user_account_id | bigint | NOT NULL | Internal | user_account |  |
| full_name | character varying(150) | NOT NULL | Personal |  | name as entered, any script |
| given_name | character varying(150) | NULL | Personal |  | null=mononym or candidate did not split the name |
| family_name | character varying(150) | NULL | Personal |  | null=mononym or candidate did not split the name |
| preferred_name | character varying(150) | NULL | Personal |  | null=no preferred name, full_name is used |
| name_language_id | bigint | NULL | Internal | language | null=script/language of name not detected |
| date_of_birth | date | NULL | Personal |  | null=not provided (optional) |
| gender_id | bigint | NULL | Personal | gender | null=never asked; prefer_not_to_say is an explicit answer |
| marital_status_id | bigint | NULL | Personal | marital_status | null=never asked; prefer_not_to_say is an explicit answer |
| nationality_country_id | bigint | NULL | Personal | country | null=not provided |
| headline | character varying(250) | NULL | Public |  | null=not written yet |
| summary | character varying(4000) | NULL | Public |  | null=not written yet |
| summary_language_id | bigint | NULL | Internal | language | null=summary absent or language not detected |
| current_city_id | bigint | NULL | Personal | city | null=not provided |
| total_experience_months | integer | NULL | Public |  | null=not stated (0 is a real value for freshers) |
| is_fresher | boolean | NOT NULL | Internal |  |  |
| current_job_role_id | bigint | NULL | Public | job_role | null=fresher or not stated |
| current_industry_id | bigint | NULL | Public | industry | null=fresher or not stated |
| current_salary_disclosure_status_id | bigint | NOT NULL | Internal | salary_disclosure_status |  |
| current_salary_amount | numeric(14,2) | NULL | Personal |  | null when disclosure status is not_disclosed/not_applicable (CHECK) |
| current_salary_currency_id | bigint | NULL | Personal | currency | null exactly when amount is null |
| current_salary_period_id | bigint | NULL | Personal | salary_period | null exactly when amount is null |
| expected_salary_disclosure_status_id | bigint | NOT NULL | Internal | salary_disclosure_status |  |
| expected_salary_amount | numeric(14,2) | NULL | Personal |  | null when disclosure status is not_disclosed/not_applicable (CHECK) |
| expected_salary_currency_id | bigint | NULL | Personal | currency | null exactly when amount is null |
| expected_salary_period_id | bigint | NULL | Personal | salary_period | null exactly when amount is null |
| notice_period_id | bigint | NULL | Public | notice_period | null=not stated |
| is_open_to_relocation | boolean | NOT NULL | Internal |  |  |
| is_actively_looking | boolean | NOT NULL | Internal |  |  |
| profile_visibility_id | bigint | NOT NULL | Internal | profile_visibility |  |
| profile_completion_pct | numeric(5,2) | NOT NULL | Internal |  |  |
| last_active_at | timestamp with time zone | NULL | Internal |  | null=never logged in after registration (legacy import) |
| duplicate_of_candidate_profile_id | bigint | NULL | Internal | candidate_profile | null=not identified as a duplicate |
| legacy_source_system_id | bigint | NULL | Internal | legacy_source_system | null=native Talentra registration |
| legacy_record_ref | character varying(100) | NULL | Internal |  | null=native Talentra registration |
| deletion_requested_at | timestamp with time zone | NULL | Internal |  | null=no erasure request; set starts the 30-day erasure job |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |
| deleted_at | timestamp with time zone | NULL | Internal |  | null=active (soft delete) |

### candidate_profile_section_score

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| candidate_profile_id | bigint | NOT NULL | Internal | candidate_profile |  |
| profile_section_id | bigint | NOT NULL | Internal | profile_section |  |
| completion_pct | numeric(5,2) | NOT NULL | Internal |  |  |
| computed_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### candidate_skill

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| candidate_profile_id | bigint | NOT NULL | Internal | candidate_profile |  |
| skill_id | bigint | NOT NULL | Internal | skill |  |
| proficiency_level_id | bigint | NULL | Public | proficiency_level | null=not self-rated |
| experience_months | integer | NULL | Public |  | null=not stated |
| last_used_year | smallint | NULL | Public |  | null=not stated |
| is_primary | boolean | NOT NULL | Internal |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### candidate_social_link

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| candidate_profile_id | bigint | NOT NULL | Internal | candidate_profile |  |
| social_link_type_id | bigint | NOT NULL | Internal | social_link_type |  |
| url | character varying(500) | NOT NULL | Personal |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### candidate_work_experience

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| candidate_profile_id | bigint | NOT NULL | Internal | candidate_profile |  |
| employer_name | character varying(250) | NOT NULL | Internal |  |  |
| organisation_id | bigint | NULL | Public | organisation | null=employer not matched to a platform organisation |
| job_title | character varying(150) | NOT NULL | Internal |  |  |
| job_role_id | bigint | NULL | Public | job_role | null=title not mapped to master role |
| industry_id | bigint | NULL | Public | industry | null=not stated |
| employment_type_id | bigint | NOT NULL | Internal | employment_type |  |
| city_id | bigint | NULL | Public | city | null=not stated |
| start_date | date | NOT NULL | Internal |  |  |
| end_date | date | NULL | Public |  | null=current job (CHECK with is_current) |
| is_current | boolean | NOT NULL | Internal |  |  |
| description | character varying(4000) | NULL | Public |  | null=not written |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### city

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| country_id | bigint | NOT NULL | Internal | country |  |
| state_id | bigint | NULL | Public | state | null=country has no first-level subdivision in our reference data |
| name | character varying(150) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NULL | Public | ui_label_key | null=name shown as-is (proper noun, no translation) |
| latitude | numeric(9,6) | NULL | Public |  | WGS84 decimal degrees, 6 dp (~0.11 m); null=not geocoded (mapping is optional) |
| longitude | numeric(9,6) | NULL | Public |  | WGS84 decimal degrees, 6 dp; null=not geocoded |
| coordinate_source_id | bigint | NULL | Public | coordinate_source | null only when coordinates are null |
| place_ref | character varying(100) | NULL | Public |  | null=not matched to the mapping provider |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### coordinate_source
lookup; origin of latitude/longitude values

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### country

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| iso_alpha2 | character(2) | NOT NULL | Internal |  |  |
| iso_alpha3 | character(3) | NOT NULL | Internal |  |  |
| name | character varying(150) | NOT NULL | Public |  |  |
| phone_country_code | character varying(4) | NOT NULL | Internal |  |  |
| currency_id | bigint | NOT NULL | Internal | currency |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### course

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| title | character varying(250) | NOT NULL | Internal |  |  |
| provider_name | character varying(150) | NOT NULL | Internal |  |  |
| course_url | character varying(500) | NULL | Public |  | null=offline course |
| duration_hours | numeric(6,1) | NULL | Public |  | null=self-paced, unknown duration |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### course_enrolment

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| candidate_profile_id | bigint | NOT NULL | Internal | candidate_profile |  |
| course_id | bigint | NOT NULL | Internal | course |  |
| enrolment_status_id | bigint | NOT NULL | Internal | enrolment_status |  |
| enrolled_on | date | NOT NULL | Internal |  |  |
| completed_on | date | NULL | Personal |  | null=not completed |
| progress_pct | numeric(5,2) | NOT NULL | Internal |  |  |
| certificate_url | character varying(500) | NULL | Personal |  | null=no certificate issued |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### currency

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character(3) | NOT NULL | Public |  |  |
| name | character varying(100) | NOT NULL | Public |  |  |
| minor_unit | smallint | NOT NULL | Internal |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### education_mode
lookup; full_time, part_time, distance, online

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### employment_type
lookup; full_time, part_time, contract, temporary, apprentice, internship, freelance

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### enrolment_status
lookup; enrolled, in_progress, completed, dropped

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### field_of_study

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| name | character varying(150) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NULL | Public | ui_label_key | null=no translations yet, canonical name shown |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### functional_area
lookup; engineering, sales, operations, finance, hr, ...

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### gender
lookup; includes prefer_not_to_say (explicit refusal, distinct from NULL = not asked)

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### grade_scale
lookup; percentage, cgpa_10, cgpa_4, letter, pass_fail

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### industry

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| parent_industry_id | bigint | NULL | Public | industry | null=top-level industry |
| code | character varying(50) | NOT NULL | Public |  |  |
| name | character varying(150) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NULL | Public | ui_label_key | null=no translations yet, canonical name shown |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### institution

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| name | character varying(250) | NOT NULL | Public |  |  |
| city_id | bigint | NULL | Public | city | null=institution city unknown (legacy import) |
| country_id | bigint | NOT NULL | Internal | country |  |
| external_ref | character varying(50) | NULL | Public |  | null=no official registry code |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### interview

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| application_id | bigint | NOT NULL | Internal | application |  |
| round_number | integer | NOT NULL | Internal |  |  |
| interview_round_type_id | bigint | NOT NULL | Internal | interview_round_type |  |
| interview_mode_id | bigint | NOT NULL | Internal | interview_mode |  |
| scheduled_start_at | timestamp with time zone | NOT NULL | Internal |  |  |
| scheduled_end_at | timestamp with time zone | NOT NULL | Internal |  |  |
| display_time_zone | character varying(64) | NOT NULL | Internal |  |  |
| interviewer_user_account_id | bigint | NULL | Internal | user_account | null=panel not assigned yet |
| venue_or_meeting_link | character varying(500) | NULL | Internal |  | null=to be shared later |
| interview_outcome_id | bigint | NULL | Internal | interview_outcome | null=interview not yet held (pending) |
| rating | numeric(3,1) | NULL | Internal |  | 0..5; null=not rated |
| feedback | character varying(4000) | NULL | Internal |  | null=no written feedback |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### interview_mode
lookup; in_person, video, phone

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### interview_outcome
lookup; selected, rejected, on_hold, no_show, rescheduled

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### interview_round_type
lookup; screening, technical, managerial, hr, assignment

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### job_category
lookup; SYSTEM: 1=gig (gig requests live in the Gig subsystem, never in job_requirement)

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### job_position

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| job_requirement_id | bigint | NOT NULL | Internal | job_requirement |  |
| position_number | integer | NOT NULL | Internal |  |  |
| city_id | bigint | NULL | Public | city | null=position not tied to a location (remote) |
| job_position_status_id | bigint | NOT NULL | Internal | job_position_status |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### job_position_status
lookup; open, filled, cancelled

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### job_requirement

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| organisation_id | bigint | NOT NULL | Internal | organisation |  |
| client_organisation_id | bigint | NULL | Internal | organisation | null=direct hire, the poster is the employer (staffing agencies set the client) |
| posted_by_user_account_id | bigint | NOT NULL | Internal | user_account |  |
| requirement_code | character varying(50) | NULL | Internal |  | null=organisation does not use internal requisition codes |
| title | character varying(200) | NOT NULL | Public |  |  |
| description | text | NOT NULL | Public |  | unbounded type justified (rich job description), capped at 50k chars by CHECK |
| description_language_id | bigint | NULL | Internal | language | null=language not detected |
| job_category_id | bigint | NOT NULL | Internal | job_category |  |
| employment_type_id | bigint | NOT NULL | Internal | employment_type |  |
| work_mode_id | bigint | NOT NULL | Internal | work_mode |  |
| job_role_id | bigint | NULL | Public | job_role | null=title not mapped to master role yet |
| industry_id | bigint | NULL | Public | industry | null=inherits organisation industry |
| number_of_positions | integer | NOT NULL | Internal |  |  |
| min_experience_months | integer | NOT NULL | Internal |  |  |
| max_experience_months | integer | NULL | Public |  | null=no upper limit |
| salary_disclosure_status_id | bigint | NOT NULL | Internal | salary_disclosure_status |  |
| salary_min_amount | numeric(14,2) | NULL | Public |  | null when salary_disclosure_status is not_disclosed/not_applicable (CHECK) |
| salary_max_amount | numeric(14,2) | NULL | Public |  | null when salary not disclosed (CHECK) |
| salary_currency_id | bigint | NULL | Public | currency | null exactly when amounts are null |
| salary_period_id | bigint | NULL | Public | salary_period | null exactly when amounts are null |
| job_requirement_status_id | bigint | NOT NULL | Internal | job_requirement_status |  |
| publish_state_id | bigint | NOT NULL | Internal | publish_state |  |
| published_at | timestamp with time zone | NULL | Public |  | null=never published (draft) |
| expires_at | timestamp with time zone | NULL | Public |  | null=no expiry set (closes manually) |
| application_deadline | date | NULL | Public |  | null=open until filled |
| is_open_to_consultants | boolean | NOT NULL | Internal |  |  |
| consultant_fee_pct | numeric(5,2) | NULL | Internal |  | 0<x<=100; null=not open to consultants or fee negotiated per request |
| legacy_source_system_id | bigint | NULL | Internal | legacy_source_system | null=created natively |
| legacy_record_ref | character varying(100) | NULL | Internal |  | null=created natively |
| search_document | tsvector | NULL | Internal |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |
| deleted_at | timestamp with time zone | NULL | Internal |  | null=active (soft delete) |

### job_requirement_location

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| job_requirement_id | bigint | NOT NULL | Internal | job_requirement |  |
| city_id | bigint | NOT NULL | Internal | city |  |
| positions_at_location | integer | NULL | Public |  | null=positions not split by location |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### job_requirement_qualification

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| job_requirement_id | bigint | NOT NULL | Internal | job_requirement |  |
| qualification_id | bigint | NOT NULL | Internal | qualification |  |
| field_of_study_id | bigint | NULL | Public | field_of_study | null=any specialisation |
| is_mandatory | boolean | NOT NULL | Internal |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### job_requirement_questionnaire

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| job_requirement_id | bigint | NOT NULL | Internal | job_requirement |  |
| questionnaire_id | bigint | NOT NULL | Internal | questionnaire |  |
| sort_order | integer | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### job_requirement_skill

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| job_requirement_id | bigint | NOT NULL | Internal | job_requirement |  |
| skill_id | bigint | NOT NULL | Internal | skill |  |
| is_mandatory | boolean | NOT NULL | Internal |  |  |
| min_experience_months | integer | NULL | Public |  | null=no minimum |
| proficiency_level_id | bigint | NULL | Public | proficiency_level | null=any level |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### job_requirement_status
lookup; draft, pending_approval, open, on_hold, closed, filled, cancelled

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### job_role

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| functional_area_id | bigint | NOT NULL | Internal | functional_area |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| name | character varying(150) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NULL | Public | ui_label_key | null=no translations yet, canonical name shown |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### job_search_event

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| user_account_id | bigint | NULL | Personal | user_account | null=guest search (anonymous_session_ref set) |
| anonymous_session_ref | character varying(64) | NULL | Internal |  | null=logged-in search |
| searched_at | timestamp with time zone | NOT NULL | Internal |  |  |
| keyword_text | character varying(500) | NULL | Personal |  | null=filter-only search |
| city_id | bigint | NULL | Internal | city | null=no location filter |
| filter_criteria | jsonb | NULL | Internal |  | bounded 4 KB; null=no extra filters |
| result_count | integer | NOT NULL | Internal |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |

### language

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(15) | NOT NULL | Public |  |  |
| native_name | character varying(100) | NOT NULL | Internal |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| is_ui_supported | boolean | NOT NULL | Internal |  |  |
| is_default | boolean | NOT NULL | Internal |  |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### language_proficiency_level
lookup; elementary, limited_working, professional, full_professional, native

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### legacy_source_system
lookup; legacy systems that migrated or sync records

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### marital_status
lookup; optional profile attribute; includes prefer_not_to_say

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### notice_period
lookup; immediate, 15_days, 30_days, 60_days, 90_days, more_than_90_days

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### offer

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| application_id | bigint | NOT NULL | Internal | application |  |
| offer_status_id | bigint | NOT NULL | Internal | offer_status |  |
| offered_at | timestamp with time zone | NOT NULL | Internal |  |  |
| salary_amount | numeric(14,2) | NOT NULL | Personal |  |  |
| salary_currency_id | bigint | NOT NULL | Internal | currency |  |
| salary_period_id | bigint | NOT NULL | Internal | salary_period |  |
| proposed_joining_date | date | NOT NULL | Internal |  |  |
| valid_until | date | NOT NULL | Internal |  |  |
| responded_at | timestamp with time zone | NULL | Internal |  | null=candidate has not responded |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### offer_status
lookup; extended, accepted, declined, revoked, expired

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### organisation

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| legal_name | character varying(250) | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |
| deleted_at | timestamp with time zone | NULL | Internal |  | null=organisation not deleted (soft delete) |

### phone_type
lookup; mobile, landline, whatsapp

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### placement

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| application_id | bigint | NOT NULL | Internal | application |  |
| job_position_id | bigint | NOT NULL | Internal | job_position |  |
| job_requirement_id | bigint | NOT NULL | Internal | application,job_position |  |
| offer_id | bigint | NOT NULL | Internal | offer |  |
| joined_on | date | NOT NULL | Internal |  |  |
| employee_ref | character varying(50) | NULL | Personal |  | null=employer has not issued an employee id yet |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### proficiency_level
lookup; beginner, intermediate, advanced, expert

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### profile_project

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| project_kind_id | bigint | NOT NULL | Internal | project_kind |  |
| candidate_profile_id | bigint | NOT NULL | Internal | candidate_profile |  |
| candidate_work_experience_id | bigint | NULL | Public | candidate_work_experience | null=personal/academic project not tied to a job |
| title | character varying(200) | NOT NULL | Internal |  |  |
| role_name | character varying(150) | NOT NULL | Internal |  |  |
| start_date | date | NOT NULL | Internal |  |  |
| end_date | date | NULL | Public |  | null=ongoing |
| outcome | character varying(2000) | NULL | Public |  | null=not written |
| description | character varying(4000) | NULL | Public |  | null=not written |
| project_url | character varying(500) | NULL | Public |  | null=no public link |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### profile_project_skill

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| profile_project_id | bigint | NOT NULL | Internal | profile_project |  |
| skill_id | bigint | NOT NULL | Internal | skill |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### profile_section
lookup; sections that contribute to profile completion scoring

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |
| weight_pct | numeric(5,2) | NOT NULL | Internal |  |  |

### profile_view_event

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| candidate_profile_id | bigint | NOT NULL | Internal | candidate_profile |  |
| viewer_user_account_id | bigint | NOT NULL | Internal | user_account |  |
| viewer_organisation_id | bigint | NULL | Internal | organisation | null=viewer is a freelance consultant without organisation |
| view_context_id | bigint | NOT NULL | Internal | view_context |  |
| job_requirement_id | bigint | NULL | Internal | job_requirement | null=view not in the context of a job |
| viewed_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |

### profile_visibility
lookup; public, employers_only, hidden

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### project_kind
lookup; candidate_project, gig_project

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### publish_state
lookup; unpublished, scheduled, published, expired, withdrawn

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### qualification

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| qualification_level_id | bigint | NOT NULL | Internal | qualification_level |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| name | character varying(150) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NULL | Public | ui_label_key | null=no translations yet, canonical name shown |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### qualification_level
lookup; below_10th, 10th, 12th, iti, diploma, graduate, post_graduate, doctorate, certificate

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### question_type
lookup; single_choice, multi_choice, short_text, long_text, number, yes_no

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### questionnaire

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| organisation_id | bigint | NOT NULL | Internal | organisation |  |
| title | character varying(200) | NOT NULL | Internal |  |  |
| language_id | bigint | NOT NULL | Internal | language |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |
| deleted_at | timestamp with time zone | NULL | Internal |  | null=active (soft delete) |

### questionnaire_question

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| questionnaire_id | bigint | NOT NULL | Internal | questionnaire |  |
| question_order | integer | NOT NULL | Internal |  |  |
| question_text | character varying(1000) | NOT NULL | Internal |  |  |
| question_type_id | bigint | NOT NULL | Internal | question_type |  |
| is_mandatory | boolean | NOT NULL | Internal |  |  |
| is_knockout | boolean | NOT NULL | Internal |  |  |
| min_number_value | numeric(14,2) | NULL | Internal |  | null=not a numeric question or no lower bound |
| max_number_value | numeric(14,2) | NULL | Internal |  | null=not a numeric question or no upper bound |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### questionnaire_question_option

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| questionnaire_question_id | bigint | NOT NULL | Internal | questionnaire_question |  |
| option_order | integer | NOT NULL | Internal |  |  |
| option_text | character varying(500) | NOT NULL | Internal |  |  |
| is_knockout_pass | boolean | NOT NULL | Internal |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### referral

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| referrer_user_account_id | bigint | NOT NULL | Internal | user_account |  |
| referral_code | character varying(32) | NOT NULL | Internal |  |  |
| referred_email | character varying(254) | NULL | Personal |  | null=referral of an existing candidate |
| referred_candidate_profile_id | bigint | NULL | Personal | candidate_profile | null=referred person not registered yet |
| job_requirement_id | bigint | NULL | Internal | job_requirement | null=platform referral, not job-specific |
| referral_status_id | bigint | NOT NULL | Internal | referral_status |  |
| referred_at | timestamp with time zone | NOT NULL | Internal |  |  |
| converted_at | timestamp with time zone | NULL | Internal |  | null=not converted |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### referral_status
lookup; invited, registered, applied, hired, expired

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### rejection_reason
lookup; skills_mismatch, experience_mismatch, salary_mismatch, position_filled, no_show, other

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### resume

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| candidate_profile_id | bigint | NOT NULL | Internal | candidate_profile |  |
| title | character varying(150) | NOT NULL | Internal |  |  |
| is_default | boolean | NOT NULL | Internal |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |
| deleted_at | timestamp with time zone | NULL | Internal |  | null=active (soft delete) |

### resume_template

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| layout_definition | jsonb | NOT NULL | Internal |  |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### resume_version

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| resume_id | bigint | NOT NULL | Internal | resume |  |
| version_number | integer | NOT NULL | Internal |  |  |
| resume_template_id | bigint | NULL | Internal | resume_template | null=uploaded file, not template-built |
| storage_uri | character varying(500) | NULL | Personal |  | object-store key; null=template-built, rendered on demand |
| file_name | character varying(255) | NULL | Personal |  | null=template-built |
| mime_type | character varying(100) | NULL | Internal |  | null=template-built |
| file_size_bytes | bigint | NULL | Internal |  | null=template-built |
| content_sha256 | character(64) | NULL | Internal |  | null=template-built |
| body_text | text | NULL | Personal |  | unbounded-by-type resume body (justified: full-text search), capped at 200k chars by CHECK; null=text extraction pending/failed |
| body_language_id | bigint | NULL | Internal | language | null=language not detected |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |

### salary_disclosure_status
lookup; SYSTEM: 1=disclosed, 2=not_disclosed, 3=not_applicable

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### salary_period
lookup; annual, monthly, daily, hourly

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### saved_job

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| candidate_profile_id | bigint | NOT NULL | Internal | candidate_profile |  |
| job_requirement_id | bigint | NOT NULL | Internal | job_requirement |  |
| saved_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### skill

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| skill_category_id | bigint | NOT NULL | Internal | skill_category |  |
| code | character varying(80) | NOT NULL | Public |  |  |
| name | character varying(150) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NULL | Public | ui_label_key | null=no translations yet, canonical name shown |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### skill_alias

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| skill_id | bigint | NOT NULL | Internal | skill |  |
| alias_name | character varying(150) | NOT NULL | Internal |  |  |
| language_id | bigint | NULL | Public | language | null=alias is language-neutral (brand/technology name) |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### skill_category
lookup; technical, functional, soft, trade, language, tool

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### social_link_type
lookup; linkedin, github, portfolio, other

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### state

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| country_id | bigint | NOT NULL | Internal | country |  |
| code | character varying(10) | NOT NULL | Public |  |  |
| name | character varying(150) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NULL | Public | ui_label_key | null=name shown as-is (proper noun, no translation) |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### talent_list

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| owner_user_account_id | bigint | NOT NULL | Internal | user_account |  |
| organisation_id | bigint | NULL | Internal | job_requirement,organisation | null=freelance consultant list without organisation |
| talent_list_type_id | bigint | NOT NULL | Internal | talent_list_type |  |
| job_requirement_id | bigint | NULL | Internal | job_requirement | null=general pool, not tied to one job |
| name | character varying(150) | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |
| deleted_at | timestamp with time zone | NULL | Internal |  | null=active (soft delete) |

### talent_list_entry

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| talent_list_id | bigint | NOT NULL | Internal | talent_list |  |
| candidate_profile_id | bigint | NOT NULL | Internal | candidate_profile |  |
| added_at | timestamp with time zone | NOT NULL | Internal |  |  |
| added_by_user_account_id | bigint | NOT NULL | Internal | user_account |  |
| removed_at | timestamp with time zone | NULL | Internal |  | null=still on the list |
| removed_by_user_account_id | bigint | NULL | Internal | user_account | null=still on the list |
| note | character varying(1000) | NULL | Internal |  | null=no note |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### talent_list_type
lookup; shortlist, bookmark

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### ui_label_key

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| label_key | character varying(150) | NOT NULL | Internal |  |  |
| module_code | character varying(50) | NOT NULL | Internal |  |  |
| description | character varying(500) | NULL | Internal |  | null=self-explanatory key, no translator note needed |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### ui_label_translation

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| language_id | bigint | NOT NULL | Internal | language |  |
| label_text | character varying(1000) | NOT NULL | Internal |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### user_account

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| email | character varying(254) | NOT NULL | Personal |  | login identity, lowercase |
| is_system | boolean | NOT NULL | Internal |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |
| deleted_at | timestamp with time zone | NULL | Internal |  | null=account not deleted (soft delete) |

### view_context
lookup; search_result, application, sourcing, talent_list, direct_link

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### work_mode
lookup; onsite, remote, hybrid

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |
