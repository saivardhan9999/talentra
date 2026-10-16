# Talentra — Phase 2 Data Dictionary

Generated from the live PostgreSQL 16 catalog by `sql/tests/data_dictionary.sql -v tables=...` for the Phase 2 tables (Administration, Organisation and account, Gig marketplace) and the Phase 1 tables they extend (`user_account`, `organisation`, `profile_project`). Class and null justification come from column comments; columns without a class tag are **Internal** (audit columns, surrogate/foreign keys, lookup references). Partitions are omitted.

### audit_event

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| audit_action_id | bigint | NOT NULL | Internal | audit_action |  |
| target_table | character varying(63) | NOT NULL | Internal |  | table the action touched |
| target_record_id | bigint | NULL | Internal |  | null=action not on a single row (bulk export, failed login for unknown user) |
| organisation_id | bigint | NULL | Internal | organisation | null=action outside an organisation context (candidate, platform admin) |
| occurred_at | timestamp with time zone | NOT NULL | Internal |  | UTC time of the action (partition key) |
| source_ip | inet | NULL | Personal |  | null=server-side action (scheduled job) |
| user_agent | character varying(500) | NULL | Personal |  | null=server-side action |
| detail | jsonb | NULL | Personal |  | changed fields, never secrets; bounded 8 KB; null=action needs no detail |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |

### gig_application

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| gig_request_id | bigint | NOT NULL | Internal | gig_request |  |
| gig_worker_profile_id | bigint | NOT NULL | Internal | gig_worker_profile |  |
| gig_worker_service_id | bigint | NULL | Internal | gig_worker_service | null=applied without choosing one of the worker's listed services |
| cover_note | character varying(2000) | NULL | Personal |  | null=no note written |
| gig_application_status_id | bigint | NOT NULL | Internal | gig_application_status |  |
| applied_at | timestamp with time zone | NOT NULL | Internal |  |  |
| decided_at | timestamp with time zone | NULL | Internal |  | null=requester has not decided yet |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### gig_assignment

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| gig_application_id | bigint | NOT NULL | Internal | gig_application |  |
| gig_worker_profile_id | bigint | NOT NULL | Internal | gig_application |  |
| window_start_at | timestamp with time zone | NOT NULL | Internal |  | copied from the request by trigger |
| window_end_at | timestamp with time zone | NOT NULL | Internal |  | copied from the request by trigger |
| handoff_ref | character varying(100) | NOT NULL | Internal |  | id of the job in the external fulfilment system |
| gig_assignment_status_id | bigint | NOT NULL | Internal | gig_assignment_status |  |
| last_reconciled_at | timestamp with time zone | NULL | Internal |  | null=not reconciled since handoff |
| completed_at | timestamp with time zone | NULL | Internal |  | null=not completed (per fulfilment system) |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### gig_earning_snapshot

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| gig_assignment_id | bigint | NOT NULL | Internal | gig_assignment |  |
| gig_earning_type_id | bigint | NOT NULL | Internal | gig_earning_type |  |
| earning_amount | numeric(14,2) | NOT NULL | Personal |  | figure as reported by the fulfilment system |
| earning_currency_id | bigint | NOT NULL | Internal | currency |  |
| external_event_ref | character varying(100) | NOT NULL | Internal |  | idempotency key from the fulfilment system |
| reported_at | timestamp with time zone | NOT NULL | Internal |  | as-of time in the fulfilment system |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |

### gig_rating

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| gig_assignment_id | bigint | NOT NULL | Internal | gig_assignment |  |
| rated_by_user_account_id | bigint | NOT NULL | Internal | user_account |  |
| rating_score | smallint | NOT NULL | Public |  | 1..5 |
| review_text | character varying(2000) | NULL | Public |  | null=score given without a review |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### gig_request

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| requester_user_account_id | bigint | NOT NULL | Internal | user_account |  |
| requester_organisation_id | bigint | NULL | Internal | organisation | null=individual requester, not acting for an organisation |
| title | character varying(200) | NOT NULL | Public |  |  |
| description | character varying(4000) | NOT NULL | Public |  | stored once in the language entered |
| description_language_id | bigint | NULL | Internal | language | null=language not detected |
| work_mode_id | bigint | NOT NULL | Internal | work_mode |  |
| city_id | bigint | NULL | Public | city | null=remote gig (work_mode remote) |
| window_start_at | timestamp with time zone | NOT NULL | Public |  |  |
| window_end_at | timestamp with time zone | NOT NULL | Public |  |  |
| gig_price_type_id | bigint | NOT NULL | Internal | gig_price_type |  |
| price_amount | numeric(14,2) | NOT NULL | Public |  | fixed price or rate per gig_price_type |
| price_currency_id | bigint | NOT NULL | Internal | currency |  |
| gig_request_status_id | bigint | NOT NULL | Internal | gig_request_status |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |
| deleted_at | timestamp with time zone | NULL | Internal |  | null=active (soft delete) |

### gig_request_skill

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| gig_request_id | bigint | NOT NULL | Internal | gig_request |  |
| skill_id | bigint | NOT NULL | Internal | skill |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### gig_worker_availability

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| gig_worker_profile_id | bigint | NOT NULL | Internal | gig_worker_profile |  |
| available_from | timestamp with time zone | NOT NULL | Personal |  | worker availability reveals their schedule |
| available_to | timestamp with time zone | NOT NULL | Personal |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### gig_worker_list_entry

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| owner_user_account_id | bigint | NOT NULL | Internal | user_account |  |
| owner_organisation_id | bigint | NULL | Internal | organisation | null=list kept by an individual requester |
| gig_worker_profile_id | bigint | NOT NULL | Internal | gig_worker_profile |  |
| gig_worker_list_type_id | bigint | NOT NULL | Internal | gig_worker_list_type |  |
| reason | character varying(500) | NULL | Internal |  | null=no reason recorded |
| added_at | timestamp with time zone | NOT NULL | Internal |  |  |
| removed_at | timestamp with time zone | NULL | Internal |  | null=entry is current |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### gig_worker_profile

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| user_account_id | bigint | NOT NULL | Internal | user_account |  |
| display_name | character varying(150) | NOT NULL | Personal |  | name shown to requesters, any script |
| headline | character varying(250) | NULL | Public |  | null=not written yet |
| bio | character varying(2000) | NULL | Public |  | null=not written yet |
| bio_language_id | bigint | NULL | Internal | language | null=bio absent or language not detected |
| base_city_id | bigint | NULL | Personal | city | null=remote-only worker or not stated |
| is_available | boolean | NOT NULL | Internal |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |
| deleted_at | timestamp with time zone | NULL | Internal |  | null=active (soft delete) |

### gig_worker_service

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| gig_worker_profile_id | bigint | NOT NULL | Internal | gig_worker_profile |  |
| skill_id | bigint | NOT NULL | Internal | skill |  |
| title | character varying(200) | NOT NULL | Public |  |  |
| description | character varying(2000) | NULL | Public |  | null=title is self-explanatory |
| gig_price_type_id | bigint | NOT NULL | Internal | gig_price_type |  |
| rate_amount | numeric(14,2) | NOT NULL | Public |  | charge rate per gig_price_type |
| rate_currency_id | bigint | NOT NULL | Internal | currency |  |
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
| organisation_type_id | bigint | NOT NULL | Internal | organisation_type |  |
| parent_organisation_id | bigint | NULL | Internal | organisation | null=root organisation (the account) |
| trade_name | character varying(250) | NULL | Public |  | null=trades under its legal name |
| description | character varying(4000) | NULL | Public |  | company profile text; null=not written yet |
| description_language_id | bigint | NULL | Internal | language | null=description absent or language not detected |
| industry_id | bigint | NULL | Public | industry | null=not stated |
| company_size_band_id | bigint | NULL | Public | company_size_band | null=not stated |
| founded_year | smallint | NULL | Public |  | null=not stated |
| website_url | character varying(500) | NULL | Public |  | null=no website |
| logo_uri | character varying(500) | NULL | Public |  | object-store key; null=no logo uploaded |
| contact_email | character varying(254) | NULL | Internal |  | company contact, not a login; null=not provided |
| contact_phone_e164 | character varying(16) | NULL | Internal |  | E.164; null=not provided |
| contact_phone_country_id | bigint | NULL | Internal | country | null exactly when contact_phone_e164 is null |
| organisation_account_status_id | bigint | NOT NULL | Internal | organisation_account_status |  |
| verification_status_id | bigint | NOT NULL | Internal | verification_status |  |

### organisation_location

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| organisation_id | bigint | NOT NULL | Internal | organisation |  |
| city_id | bigint | NOT NULL | Internal | city |  |
| address_line_1 | character varying(250) | NOT NULL | Public |  |  |
| address_line_2 | character varying(250) | NULL | Public |  | null=address fits on one line |
| postal_code | character varying(20) | NULL | Public |  | null=country without postal codes or not provided |
| latitude | numeric(9,6) | NULL | Public |  | WGS84 6 dp; null=not geocoded (optional service) |
| longitude | numeric(9,6) | NULL | Public |  | WGS84 6 dp; null=not geocoded |
| coordinate_source_id | bigint | NULL | Internal | coordinate_source | null only when coordinates are null |
| is_headquarters | boolean | NOT NULL | Internal |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### organisation_member

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| organisation_id | bigint | NOT NULL | Internal | organisation |  |
| user_account_id | bigint | NOT NULL | Internal | user_account |  |
| role_id | bigint | NOT NULL | Internal | role |  |
| valid_from | timestamp with time zone | NOT NULL | Internal |  | mapping takes effect |
| valid_to | timestamp with time zone | NULL | Internal |  | null=mapping is current |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### organisation_registration_identifier

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| organisation_id | bigint | NOT NULL | Internal | organisation |  |
| registration_identifier_type_id | bigint | NOT NULL | Internal | registration_identifier_type |  |
| issuing_country_id | bigint | NOT NULL | Internal | country |  |
| identifier_token | character varying(100) | NOT NULL | Sensitive |  | vault token, never the clear value |
| identifier_hmac | bytea | NOT NULL | Sensitive |  | HMAC-SHA256 of the normalised value, for lookup and uniqueness |
| identifier_masked | character varying(30) | NOT NULL | Internal |  | display form, e.g. ******1234 |
| verification_status_id | bigint | NOT NULL | Internal | verification_status |  |
| verified_at | timestamp with time zone | NULL | Internal |  | null=not verified (CHECK: required when status is verified) |
| verification_ref | character varying(100) | NULL | Internal |  | reference returned by the verification service; null=not submitted yet |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### permission

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(100) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
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
| candidate_profile_id | bigint | NULL | Internal | candidate_profile | null=gig project (gig_worker_profile_id set; CHECK exactly one owner) |
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
| gig_worker_profile_id | bigint | NULL | Internal | gig_worker_profile | null=candidate project (candidate_profile_id set; CHECK exactly one owner) |

### role

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| is_organisation_scoped | boolean | NOT NULL | Internal |  |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### role_permission

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| role_id | bigint | NOT NULL | Internal | role |  |
| permission_id | bigint | NOT NULL | Internal | permission |  |
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
| user_account_status_id | bigint | NOT NULL | Internal | user_account_status |  |

### user_account_role

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| user_account_id | bigint | NOT NULL | Internal | user_account |  |
| role_id | bigint | NOT NULL | Internal | role |  |
| granted_at | timestamp with time zone | NOT NULL | Internal |  | grant takes effect |
| revoked_at | timestamp with time zone | NULL | Internal |  | null=grant is live |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |
