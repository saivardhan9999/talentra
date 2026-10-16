# Talentra — Phase 4 Data Dictionary

Generated from the live PostgreSQL 16 catalog by `sql/tests/data_dictionary.sql -v tables=...` for the Phase 4 tables (Notifications, preferences and community; Shared team items; Analytics layer). Class and null justification come from column comments; columns without a class tag are **Internal** (audit columns, surrogate/foreign keys, lookup references). Partitions are omitted. The four `agg_` aggregates are materialised views over the facts (see phase4-design.md) and are not listed.


### agg_refresh_log

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| aggregate_name | character varying(63) | NOT NULL | Internal |  |  |
| started_at | timestamp with time zone | NOT NULL | Internal |  |  |
| finished_at | timestamp with time zone | NOT NULL | Internal |  | shown on dashboards as data as of |
| row_count | bigint | NOT NULL | Internal |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |

### block_entry

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| blocker_user_account_id | bigint | NOT NULL | Internal | user_account |  |
| blocked_user_account_id | bigint | NULL | Personal | user_account | null=an organisation is blocked |
| blocked_organisation_id | bigint | NULL | Personal | organisation | null=a user is blocked |
| block_reason_id | bigint | NULL | Personal | block_reason | null=no reason given |
| blocked_at | timestamp with time zone | NOT NULL | Personal |  |  |
| unblocked_at | timestamp with time zone | NULL | Personal |  | null=block in force |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### community_post

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| author_user_account_id | bigint | NOT NULL | Internal | user_account |  |
| parent_community_post_id | bigint | NULL | Public | community_post | null=top-level post |
| title | character varying(200) | NULL | Public |  | null=reply (replies have no title) |
| body | character varying(4000) | NOT NULL | Public |  | stored once in the language written |
| body_language_id | bigint | NULL | Public | language | null=language not detected |
| community_post_status_id | bigint | NOT NULL | Internal | community_post_status |  |
| published_at | timestamp with time zone | NOT NULL | Public |  |  |
| deleted_at | timestamp with time zone | NULL | Internal |  | null=not deleted |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### community_reaction

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| community_post_id | bigint | NOT NULL | Internal | community_post |  |
| user_account_id | bigint | NOT NULL | Internal | user_account |  |
| reaction_type_id | bigint | NOT NULL | Internal | reaction_type |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### consent_record

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| user_account_id | bigint | NOT NULL | Internal | user_account |  |
| consent_purpose_id | bigint | NOT NULL | Internal | consent_purpose |  |
| policy_version | character varying(20) | NOT NULL | Internal |  | version of the policy text the user saw |
| is_granted | boolean | NOT NULL | Internal |  |  |
| recorded_at | timestamp with time zone | NOT NULL | Internal |  |  |
| source_ip | inet | NULL | Personal |  | evidence of the consent; null=recorded offline or by import |
| user_agent | character varying(500) | NULL | Personal |  | null=recorded offline or by import |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |

### dim_candidate

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| candidate_profile_id | bigint | NOT NULL | Internal |  |  |
| dim_location_id | bigint | NULL | Internal | dim_location | null=candidate city unknown |
| experience_band_code | character varying(20) | NOT NULL | Internal |  | banded years of experience (0_1, 1_3, 3_5, 5_10, 10_plus) |
| highest_qualification_code | character varying(50) | NULL | Internal |  | null=no education recorded |
| is_fresher | boolean | NOT NULL | Internal |  |  |
| profile_completion_pct | numeric(5,2) | NOT NULL | Internal |  | 0..100 |
| registered_date_id | bigint | NOT NULL | Internal | dim_date |  |
| valid_from | timestamp with time zone | NOT NULL | Internal |  | SCD type 2 version start |
| valid_to | timestamp with time zone | NULL | Internal |  | null=current version |
| is_current | boolean | NOT NULL | Internal |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### dim_date

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| calendar_date | date | NOT NULL | Public |  |  |
| year_number | smallint | NOT NULL | Public |  |  |
| quarter_number | smallint | NOT NULL | Public |  |  |
| month_number | smallint | NOT NULL | Public |  |  |
| month_start | date | NOT NULL | Public |  |  |
| iso_week | smallint | NOT NULL | Public |  |  |
| day_of_week | smallint | NOT NULL | Public |  | ISO 1=Monday..7=Sunday |
| is_weekend | boolean | NOT NULL | Internal |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |

### dim_job_requirement

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| job_requirement_id | bigint | NOT NULL | Internal |  |  |
| dim_organisation_id | bigint | NOT NULL | Internal | dim_organisation |  |
| dim_location_id | bigint | NULL | Internal | dim_location | null=remote or no primary location |
| job_role_code | character varying(50) | NULL | Internal |  | null=role not mapped |
| industry_code | character varying(50) | NULL | Internal |  | null=industry not stated |
| employment_type_code | character varying(50) | NOT NULL | Internal |  |  |
| work_mode_code | character varying(50) | NOT NULL | Internal |  |  |
| salary_band_code | character varying(20) | NULL | Internal |  | null=salary not disclosed |
| is_open_to_consultants | boolean | NOT NULL | Internal |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### dim_location

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| city_id | bigint | NOT NULL | Internal |  |  |
| city_name | character varying(150) | NOT NULL | Public |  | copied from city at load |
| state_name | character varying(150) | NOT NULL | Public |  |  |
| country_code | character varying(2) | NOT NULL | Public |  | ISO 3166-1 alpha-2 |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### dim_organisation

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| organisation_id | bigint | NOT NULL | Internal |  |  |
| display_name | character varying(250) | NOT NULL | Internal |  | trade name, else legal name, at load |
| organisation_type_code | character varying(50) | NOT NULL | Internal |  | lookup code copied at load |
| industry_code | character varying(50) | NULL | Internal |  | null=industry not stated |
| company_size_band_code | character varying(50) | NULL | Internal |  | null=size not stated |
| verification_status_code | character varying(50) | NOT NULL | Internal |  |  |
| hq_dim_location_id | bigint | NULL | Internal | dim_location | null=no headquarters recorded |
| valid_from | timestamp with time zone | NOT NULL | Internal |  | SCD type 2 version start |
| valid_to | timestamp with time zone | NULL | Internal |  | null=current version |
| is_current | boolean | NOT NULL | Internal |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### fact_application

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| application_id | bigint | NOT NULL | Internal |  | degenerate key: source application id (no FK, see header) |
| dim_job_requirement_id | bigint | NOT NULL | Internal | dim_job_requirement |  |
| dim_candidate_id | bigint | NOT NULL | Internal | dim_candidate |  |
| dim_organisation_id | bigint | NOT NULL | Internal | dim_organisation |  |
| applied_date_id | bigint | NOT NULL | Internal | dim_date |  |
| shortlisted_date_id | bigint | NULL | Internal | dim_date | null=not shortlisted (yet) |
| interviewed_date_id | bigint | NULL | Internal | dim_date | null=not interviewed (yet) |
| offered_date_id | bigint | NULL | Internal | dim_date | null=no offer (yet) |
| joined_date_id | bigint | NULL | Internal | dim_date | null=not joined (yet) |
| rejected_date_id | bigint | NULL | Internal | dim_date | null=not rejected |
| current_stage_code | character varying(50) | NOT NULL | Internal |  |  |
| application_source_code | character varying(50) | NOT NULL | Internal |  |  |
| days_to_shortlist | integer | NULL | Internal |  | null=not shortlisted |
| days_to_hire | integer | NULL | Internal |  | applied to joined; null=not joined |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### fact_gig_assignment

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| gig_assignment_id | bigint | NOT NULL | Internal |  | degenerate key: source assignment id |
| dim_organisation_id | bigint | NULL | Internal | dim_organisation | null=individual requester |
| dim_location_id | bigint | NULL | Internal | dim_location | null=remote gig |
| window_start_date_id | bigint | NOT NULL | Internal | dim_date |  |
| completed_date_id | bigint | NULL | Internal | dim_date | null=not completed |
| assignment_status_code | character varying(50) | NOT NULL | Internal |  |  |
| price_amount | numeric(14,2) | NOT NULL | Internal |  |  |
| earning_amount | numeric(14,2) | NOT NULL | Internal |  | reconciled earnings reported so far |
| amount_currency_id | bigint | NOT NULL | Internal | currency |  |
| rating_score | smallint | NULL | Internal |  | null=not rated |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### fact_job_posting

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| job_requirement_id | bigint | NOT NULL | Internal |  | degenerate key: source requirement id |
| dim_job_requirement_id | bigint | NOT NULL | Internal | dim_job_requirement |  |
| dim_organisation_id | bigint | NOT NULL | Internal | dim_organisation |  |
| posted_date_id | bigint | NOT NULL | Internal | dim_date |  |
| published_date_id | bigint | NULL | Internal | dim_date | null=never published |
| filled_date_id | bigint | NULL | Internal | dim_date | null=not filled |
| closed_date_id | bigint | NULL | Internal | dim_date | null=still open |
| positions_opened | integer | NOT NULL | Internal |  |  |
| positions_filled | integer | NOT NULL | Internal |  |  |
| application_count | integer | NOT NULL | Internal |  |  |
| days_to_fill | integer | NULL | Internal |  | published to filled; null=not filled |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### fact_login_daily

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| event_date_id | bigint | NOT NULL | Internal | dim_date |  |
| dim_organisation_id | bigint | NULL | Internal | dim_organisation | null=users without organisation |
| login_outcome_code | character varying(50) | NOT NULL | Internal |  |  |
| attempt_count | integer | NOT NULL | Internal |  |  |
| distinct_user_count | integer | NOT NULL | Internal |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### fact_notification_daily

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| event_date_id | bigint | NOT NULL | Internal | dim_date |  |
| notification_type_code | character varying(50) | NOT NULL | Internal |  |  |
| channel_code | character varying(50) | NOT NULL | Internal |  |  |
| delivery_status_code | character varying(50) | NOT NULL | Internal |  |  |
| delivery_count | integer | NOT NULL | Internal |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### fact_outreach

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| outreach_recipient_id | bigint | NOT NULL | Internal |  | degenerate key: source recipient id |
| dim_candidate_id | bigint | NOT NULL | Internal | dim_candidate |  |
| dim_organisation_id | bigint | NULL | Internal | dim_organisation | null=sender without organisation (freelance consultant) |
| sent_date_id | bigint | NULL | Internal | dim_date | null=not sent yet |
| channel_code | character varying(50) | NOT NULL | Internal |  |  |
| is_delivered | boolean | NOT NULL | Internal |  |  |
| is_responded | boolean | NOT NULL | Internal |  |  |
| is_via_consultant | boolean | NOT NULL | Internal |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### fact_payment

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| payment_order_id | bigint | NOT NULL | Internal |  | degenerate key: source order id |
| dim_organisation_id | bigint | NOT NULL | Internal | dim_organisation |  |
| paid_date_id | bigint | NOT NULL | Internal | dim_date |  |
| purpose_code | character varying(50) | NOT NULL | Internal |  |  |
| paid_amount | numeric(14,2) | NOT NULL | Internal |  |  |
| refunded_amount | numeric(14,2) | NOT NULL | Internal |  |  |
| amount_currency_id | bigint | NOT NULL | Internal | currency |  |
| credits_purchased | integer | NOT NULL | Internal |  | 0 for subscription orders |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### fact_profile_engagement

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| engagement_kind | character varying(10) | NOT NULL | Internal |  | view or download |
| dim_candidate_id | bigint | NOT NULL | Internal | dim_candidate |  |
| dim_organisation_id | bigint | NULL | Internal | dim_organisation | null=viewer without organisation (freelance consultant) |
| event_date_id | bigint | NOT NULL | Internal | dim_date |  |
| credits_charged | integer | NOT NULL | Internal |  | 0=covered by plan entitlement |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |

### fact_sourcing_request

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| sourcing_request_id | bigint | NOT NULL | Internal |  | degenerate key: source request id |
| dim_job_requirement_id | bigint | NOT NULL | Internal | dim_job_requirement |  |
| requested_date_id | bigint | NOT NULL | Internal | dim_date |  |
| decided_date_id | bigint | NULL | Internal | dim_date | null=undecided |
| outcome_code | character varying(50) | NOT NULL | Internal |  | sourcing_request_status code |
| hours_to_decision | numeric(10,2) | NULL | Internal |  | null=undecided |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### fact_support_ticket

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| support_ticket_id | bigint | NOT NULL | Internal |  | degenerate key: source ticket id |
| dim_organisation_id | bigint | NULL | Internal | dim_organisation | null=raised by an individual |
| opened_date_id | bigint | NOT NULL | Internal | dim_date |  |
| resolved_date_id | bigint | NULL | Internal | dim_date | null=unresolved |
| category_code | character varying(50) | NOT NULL | Internal |  |  |
| priority_code | character varying(50) | NOT NULL | Internal |  |  |
| hours_to_resolve | numeric(10,2) | NULL | Internal |  | null=unresolved |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### fact_wallet_transaction

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| wallet_ledger_entry_id | bigint | NOT NULL | Internal |  | degenerate key: source ledger entry id |
| dim_organisation_id | bigint | NOT NULL | Internal | dim_organisation |  |
| entry_date_id | bigint | NOT NULL | Internal | dim_date |  |
| entry_type_code | character varying(50) | NOT NULL | Internal |  |  |
| credit_delta | integer | NOT NULL | Internal |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |

### faq

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| faq_category_id | bigint | NOT NULL | Internal | faq_category |  |
| question_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| answer_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### job_alert

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| candidate_profile_id | bigint | NOT NULL | Internal | candidate_profile |  |
| name | character varying(100) | NOT NULL | Personal |  | candidate's label for the alert |
| keywords | character varying(200) | NULL | Personal |  | null=no keyword filter |
| city_id | bigint | NULL | Personal | city | null=any city |
| job_role_id | bigint | NULL | Internal | job_role | null=any role |
| industry_id | bigint | NULL | Internal | industry | null=any industry |
| employment_type_id | bigint | NULL | Internal | employment_type | null=any employment type |
| work_mode_id | bigint | NULL | Internal | work_mode | null=any work mode |
| min_salary_amount | numeric(14,2) | NULL | Personal |  | null=no salary floor (never 0 as a sentinel) |
| min_salary_currency_id | bigint | NULL | Personal | currency | null exactly when no salary floor |
| alert_frequency_id | bigint | NOT NULL | Internal | alert_frequency |  |
| is_active | boolean | NOT NULL | Public |  |  |
| last_sent_at | timestamp with time zone | NULL | Internal |  | null=never sent |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### notification

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| recipient_user_account_id | bigint | NOT NULL | Internal | user_account |  |
| notification_type_id | bigint | NOT NULL | Internal | notification_type |  |
| job_alert_id | bigint | NULL | Internal | job_alert | null=not produced by a job alert |
| template_ref | character varying(100) | NOT NULL | Internal |  | provider / in-app template id (body not stored) |
| summary | character varying(300) | NOT NULL | Personal |  | short rendered line shown in the in-app list, kept for audit |
| target_table | character varying(63) | NULL | Internal |  | what the notification is about; null=general notice |
| target_record_id | bigint | NULL | Internal |  | id in target_table; null exactly when target_table is null |
| read_at | timestamp with time zone | NULL | Internal |  | null=unread |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### notification_delivery

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| notification_id | bigint | NOT NULL | Internal | notification |  |
| outreach_channel_id | bigint | NOT NULL | Internal | outreach_channel |  |
| notification_delivery_status_id | bigint | NOT NULL | Internal | notification_delivery_status |  |
| provider_message_ref | character varying(100) | NULL | Internal |  | provider message id, keys delivery callbacks; null=not handed to the provider yet |
| queued_at | timestamp with time zone | NOT NULL | Internal |  | partition key |
| sent_at | timestamp with time zone | NULL | Internal |  | null=not sent yet |
| delivered_at | timestamp with time zone | NULL | Internal |  | null=not delivered (yet) |
| failed_at | timestamp with time zone | NULL | Internal |  | null=not failed |
| failure_code | character varying(50) | NULL | Internal |  | provider error code; null=not failed |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### notification_preference

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| user_account_id | bigint | NOT NULL | Internal | user_account |  |
| notification_type_id | bigint | NOT NULL | Internal | notification_type |  |
| outreach_channel_id | bigint | NOT NULL | Internal | outreach_channel |  |
| is_enabled | boolean | NOT NULL | Internal |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### referral_event

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| referral_id | bigint | NOT NULL | Internal | referral |  |
| referral_event_type_id | bigint | NOT NULL | Internal | referral_event_type |  |
| application_id | bigint | NULL | Internal | application | null=event not tied to an application (invited, registered, rewarded) |
| occurred_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |

### support_ticket

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| ticket_number | character varying(20) | NOT NULL | Internal |  | human-readable reference quoted to the user |
| raised_by_user_account_id | bigint | NOT NULL | Internal | user_account |  |
| organisation_id | bigint | NULL | Internal | organisation | null=raised by an individual, not for an organisation |
| support_ticket_category_id | bigint | NOT NULL | Internal | support_ticket_category |  |
| support_ticket_priority_id | bigint | NOT NULL | Internal | support_ticket_priority |  |
| support_ticket_status_id | bigint | NOT NULL | Internal | support_ticket_status |  |
| subject | character varying(200) | NOT NULL | Personal |  | may name people or accounts |
| assigned_to_user_account_id | bigint | NULL | Internal | user_account | null=not assigned yet |
| opened_at | timestamp with time zone | NOT NULL | Internal |  |  |
| resolved_at | timestamp with time zone | NULL | Internal |  | null=not resolved |
| closed_at | timestamp with time zone | NULL | Internal |  | null=not closed |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### support_ticket_message

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| support_ticket_id | bigint | NOT NULL | Internal | support_ticket |  |
| author_user_account_id | bigint | NOT NULL | Internal | user_account |  |
| body | character varying(4000) | NOT NULL | Personal |  | conversation text |
| is_internal_note | boolean | NOT NULL | Internal |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |

### system_error_event

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| error_severity_id | bigint | NOT NULL | Internal | error_severity |  |
| source_component | character varying(100) | NOT NULL | Internal |  | service or job that failed |
| error_code | character varying(50) | NOT NULL | Internal |  |  |
| message | character varying(1000) | NOT NULL | Internal |  | must not contain personal data (logging rule) |
| correlation_ref | character varying(100) | NULL | Internal |  | request or trace id; null=not from a request |
| occurred_at | timestamp with time zone | NOT NULL | Internal |  | partition key |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |

### user_credential

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| user_account_id | bigint | NOT NULL | Internal | user_account |  |
| credential_type_id | bigint | NOT NULL | Internal | credential_type |  |
| password_hash | character varying(255) | NULL | Sensitive |  | argon2id encoded hash (salt and cost inside), never the password; null=social sign-in credential |
| provider_subject_hmac | bytea | NULL | Sensitive |  | HMAC of the provider subject id; null=password credential |
| last_used_at | timestamp with time zone | NULL | Internal |  | null=never used |
| revoked_at | timestamp with time zone | NULL | Internal |  | null=credential live |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### user_preference

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| user_account_id | bigint | NOT NULL | Internal | user_account |  |
| preferred_language_id | bigint | NOT NULL | Internal | language |  |
| timezone_name | character varying(64) | NOT NULL | Personal |  | IANA zone name, used for alert and digest times |
| is_searchable_by_employers | boolean | NOT NULL | Internal |  |  |
| show_contact_to_employers | boolean | NOT NULL | Internal |  |  |
| allow_recruiter_outreach | boolean | NOT NULL | Internal |  |  |
| allow_profile_download | boolean | NOT NULL | Internal |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |
