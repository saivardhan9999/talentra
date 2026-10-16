# Talentra — Phase 3 Data Dictionary

Generated from the live PostgreSQL 16 catalog by `sql/tests/data_dictionary.sql -v tables=...` for the Phase 3 tables (Licences, seats, devices and sessions; Sourcing and consultant requests; Subscriptions, wallet, payments and download history) and the Phase 1 tables they extend (`profile_view_event`, `talent_list`). Class and null justification come from column comments; columns without a class tag are **Internal** (audit columns, surrogate/foreign keys, lookup references). Partitions are omitted.


### invoice

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| payment_order_id | bigint | NOT NULL | Internal | payment_order |  |
| invoice_number | character varying(30) | NOT NULL | Internal |  |  |
| issued_at | timestamp with time zone | NOT NULL | Internal |  |  |
| billing_name | character varying(250) | NOT NULL | Internal |  | legal name at issue time |
| billing_tax_identifier_masked | character varying(30) | NULL | Internal |  | masked tax id printed on the invoice; null=buyer without a tax registration |
| subtotal_amount | numeric(14,2) | NOT NULL | Internal |  |  |
| tax_amount | numeric(14,2) | NOT NULL | Internal |  |  |
| total_amount | numeric(14,2) | NOT NULL | Internal |  | = subtotal + tax (CHECK) |
| invoice_currency_id | bigint | NOT NULL | Internal | currency |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |

### licence

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| organisation_id | bigint | NOT NULL | Internal | organisation,subscription |  |
| subscription_id | bigint | NOT NULL | Internal | subscription |  |
| licence_status_id | bigint | NOT NULL | Internal | licence_status |  |
| max_users | integer | NOT NULL | Internal |  | users allowed (> 0), copied from the plan |
| max_devices_per_user | integer | NOT NULL | Internal |  | devices allowed per user (> 0), copied from the plan |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### licence_seat

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| licence_id | bigint | NOT NULL | Internal | licence |  |
| user_account_id | bigint | NOT NULL | Internal | user_account |  |
| assigned_at | timestamp with time zone | NOT NULL | Internal |  |  |
| released_at | timestamp with time zone | NULL | Internal |  | null=seat in use |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### login_attempt

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| user_account_id | bigint | NULL | Internal | user_account,user_device | null=identifier matched no account |
| attempted_identifier_hmac | bytea | NOT NULL | Sensitive |  | HMAC of the identifier typed, for brute-force detection |
| user_device_id | bigint | NULL | Internal | user_device | null=attempt from an unregistered device |
| login_outcome_id | bigint | NOT NULL | Internal | login_outcome |  |
| source_ip | inet | NULL | Personal |  | null=not captured |
| user_agent | character varying(500) | NULL | Personal |  | null=not captured |
| attempted_at | timestamp with time zone | NOT NULL | Internal |  | partition key |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |

### outreach_batch

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| sender_user_account_id | bigint | NOT NULL | Internal | user_account |  |
| organisation_id | bigint | NULL | Internal | organisation | null=freelance consultant without organisation |
| job_requirement_id | bigint | NULL | Internal | job_requirement,sourcing_request | null=general outreach, not for one requirement |
| sourcing_request_id | bigint | NULL | Internal | sourcing_request | null=not sent under a consultant sourcing request |
| outreach_channel_id | bigint | NOT NULL | Internal | outreach_channel |  |
| message_template_ref | character varying(100) | NOT NULL | Internal |  | template id at the messaging provider (body not stored) |
| outreach_batch_status_id | bigint | NOT NULL | Internal | outreach_batch_status |  |
| scheduled_at | timestamp with time zone | NULL | Internal |  | null=send immediately |
| wallet_ledger_entry_id | bigint | NULL | Internal | wallet_ledger_entry | null=covered by plan entitlement or not yet charged |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### outreach_recipient

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| outreach_batch_id | bigint | NOT NULL | Internal | outreach_batch |  |
| candidate_profile_id | bigint | NOT NULL | Internal | candidate_profile |  |
| outreach_recipient_status_id | bigint | NOT NULL | Internal | outreach_recipient_status |  |
| provider_message_ref | character varying(100) | NULL | Internal |  | provider message id, idempotency for delivery callbacks; null=not sent yet |
| sent_at | timestamp with time zone | NULL | Internal |  | null=not sent yet |
| delivered_at | timestamp with time zone | NULL | Internal |  | null=not delivered (yet) |
| responded_at | timestamp with time zone | NULL | Internal |  | null=no response |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### payment_event

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| payment_order_id | bigint | NOT NULL | Internal | payment_order |  |
| payment_order_status_id | bigint | NOT NULL | Internal | payment_order_status |  |
| gateway_event_ref | character varying(100) | NOT NULL | Internal |  | webhook id, idempotency key |
| gateway_payment_ref | character varying(100) | NULL | Internal |  | gateway transaction id (no card or bank data); null=event before a transaction exists |
| occurred_at | timestamp with time zone | NOT NULL | Internal |  | time reported by the gateway |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |

### payment_order

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| organisation_id | bigint | NOT NULL | Internal | organisation |  |
| placed_by_user_account_id | bigint | NOT NULL | Internal | user_account |  |
| payment_purpose_id | bigint | NOT NULL | Internal | payment_purpose |  |
| order_amount | numeric(14,2) | NOT NULL | Internal |  |  |
| order_currency_id | bigint | NOT NULL | Internal | currency |  |
| credit_quantity | integer | NULL | Internal |  | credits bought (price fixed at order time); null=subscription order |
| payment_order_status_id | bigint | NOT NULL | Internal | payment_order_status |  |
| gateway_order_ref | character varying(100) | NULL | Internal |  | idempotency key at the gateway; null=order not yet sent to the gateway |
| paid_at | timestamp with time zone | NULL | Internal |  | null=not paid |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### plan

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| code | character varying(50) | NOT NULL | Public |  |  |
| ui_label_key_id | bigint | NOT NULL | Internal | ui_label_key |  |
| billing_period_id | bigint | NOT NULL | Internal | billing_period |  |
| price_amount | numeric(14,2) | NOT NULL | Public |  | price per billing period |
| price_currency_id | bigint | NOT NULL | Internal | currency |  |
| max_users | integer | NOT NULL | Public |  | users allowed per licence (> 0) |
| max_devices_per_user | integer | NOT NULL | Public |  | devices allowed per user (> 0) |
| sort_order | integer | NOT NULL | Public |  |  |
| is_active | boolean | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### plan_entitlement

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| plan_id | bigint | NOT NULL | Internal | plan |  |
| entitlement_type_id | bigint | NOT NULL | Internal | entitlement_type |  |
| quantity_per_period | integer | NULL | Public |  | null=unlimited within the period |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### profile_download_event

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| candidate_profile_id | bigint | NOT NULL | Internal | candidate_profile |  |
| downloader_user_account_id | bigint | NOT NULL | Internal | user_account |  |
| downloader_organisation_id | bigint | NULL | Internal | organisation | null=freelance consultant without organisation |
| resume_version_id | bigint | NULL | Internal | resume_version | null=profile export without a resume file |
| wallet_ledger_entry_id | bigint | NULL | Internal | wallet_ledger_entry | null=download covered by a plan entitlement, no credit used |
| downloaded_at | timestamp with time zone | NOT NULL | Internal |  | partition key |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |

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
| wallet_ledger_entry_id | bigint | NULL | Internal | wallet_ledger_entry | null=view consumed no credit |

### refund

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| payment_order_id | bigint | NOT NULL | Internal | payment_order |  |
| refund_amount | numeric(14,2) | NOT NULL | Internal |  |  |
| refund_currency_id | bigint | NOT NULL | Internal | currency |  |
| refund_status_id | bigint | NOT NULL | Internal | refund_status |  |
| reason | character varying(500) | NOT NULL | Internal |  |  |
| gateway_refund_ref | character varying(100) | NULL | Internal |  | null=not yet submitted to the gateway |
| requested_at | timestamp with time zone | NOT NULL | Internal |  |  |
| processed_at | timestamp with time zone | NULL | Internal |  | null=not processed yet |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### session_revocation_event

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| user_session_id | bigint | NULL | Internal | user_session,user_session | null=whole device revoked (user_device_id set) |
| user_device_id | bigint | NULL | Internal | user_device,user_session | null=single session revoked (user_session_id set) |
| revocation_reason_id | bigint | NOT NULL | Internal | revocation_reason |  |
| occurred_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |

### sourcing_request

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| job_requirement_id | bigint | NOT NULL | Internal | job_requirement |  |
| consultant_user_account_id | bigint | NOT NULL | Internal | user_account |  |
| request_note | character varying(2000) | NULL | Internal |  | null=no note |
| proposed_fee_pct | numeric(5,2) | NULL | Internal |  | 0..100; null=accepts the fee on the requirement |
| sourcing_request_status_id | bigint | NOT NULL | Internal | sourcing_request_status |  |
| requested_at | timestamp with time zone | NOT NULL | Internal |  |  |
| decided_at | timestamp with time zone | NULL | Internal |  | null=employer has not decided |
| decided_by_user_account_id | bigint | NULL | Internal | user_account | null exactly when not decided |
| decision_note | character varying(1000) | NULL | Internal |  | null=no reason given |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### subscription

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| organisation_id | bigint | NOT NULL | Internal | organisation |  |
| plan_id | bigint | NOT NULL | Internal | plan |  |
| subscription_status_id | bigint | NOT NULL | Internal | subscription_status |  |
| is_auto_renew | boolean | NOT NULL | Internal |  |  |
| started_at | timestamp with time zone | NOT NULL | Internal |  |  |
| cancelled_at | timestamp with time zone | NULL | Internal |  | null=not cancelled |
| cancellation_reason | character varying(500) | NULL | Internal |  | null=not cancelled or no reason given |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### subscription_period

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| subscription_id | bigint | NOT NULL | Internal | subscription |  |
| renewal_number | integer | NOT NULL | Internal |  | 0 = first term |
| period_start_at | timestamp with time zone | NOT NULL | Internal |  |  |
| period_end_at | timestamp with time zone | NOT NULL | Internal |  |  |
| payment_order_id | bigint | NULL | Internal | payment_order | null=trial or complimentary period |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### talent_list

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| owner_user_account_id | bigint | NOT NULL | Internal | user_account |  |
| organisation_id | bigint | NULL | Internal | organisation,job_requirement | null=freelance consultant list without organisation |
| talent_list_type_id | bigint | NOT NULL | Internal | talent_list_type |  |
| job_requirement_id | bigint | NULL | Internal | job_requirement | null=general pool, not tied to one job |
| name | character varying(150) | NOT NULL | Public |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |
| deleted_at | timestamp with time zone | NULL | Internal |  | null=active (soft delete) |
| sourcing_request_id | bigint | NULL | Internal | sourcing_request | null=employer/recruiter list, not a consultant shortlist |

### user_device

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| user_account_id | bigint | NOT NULL | Internal | user_account |  |
| device_platform_id | bigint | NOT NULL | Internal | device_platform |  |
| device_fingerprint_hmac | bytea | NOT NULL | Sensitive |  | HMAC of the device fingerprint, never the raw value |
| device_label | character varying(100) | NULL | Personal |  | user-given name; null=not named |
| first_seen_at | timestamp with time zone | NOT NULL | Internal |  |  |
| last_seen_at | timestamp with time zone | NOT NULL | Internal |  |  |
| revoked_at | timestamp with time zone | NULL | Internal |  | null=device allowed |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### user_session

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| user_account_id | bigint | NOT NULL | Internal | user_account,user_device,licence_seat |  |
| user_device_id | bigint | NOT NULL | Internal | user_device |  |
| licence_seat_id | bigint | NULL | Internal | licence_seat | null=user needs no licence (candidate, gig worker) |
| session_token_hash | bytea | NOT NULL | Sensitive |  | SHA-256 of the session token, never the token |
| started_at | timestamp with time zone | NOT NULL | Internal |  |  |
| last_activity_at | timestamp with time zone | NOT NULL | Internal |  |  |
| expires_at | timestamp with time zone | NOT NULL | Internal |  |  |
| ended_at | timestamp with time zone | NULL | Internal |  | null=session live (counts against the device limit) |
| session_end_reason_id | bigint | NULL | Internal | session_end_reason | null exactly when the session is live |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### wallet

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| organisation_id | bigint | NOT NULL | Internal | organisation |  |
| credit_balance | integer | NOT NULL | Internal |  | running total of the ledger |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
| updated_at | timestamp with time zone | NOT NULL | Internal |  |  |
| updated_by | bigint | NOT NULL | Internal | user_account |  |

### wallet_ledger_entry

| Column | Type | Null | Class | FK → | Note |
|---|---|---|---|---|---|
| id | bigint | NOT NULL | Internal |  |  |
| wallet_id | bigint | NOT NULL | Internal | wallet |  |
| wallet_entry_type_id | bigint | NOT NULL | Internal | wallet_entry_type |  |
| credit_delta | integer | NOT NULL | Internal |  | + credit, - debit, never 0 |
| balance_after | integer | NOT NULL | Internal |  |  |
| payment_order_id | bigint | NULL | Internal | payment_order | null=entry not funded by a payment (consumption, adjustment) |
| refund_id | bigint | NULL | Internal | refund | null=entry not caused by a refund |
| reverses_wallet_ledger_entry_id | bigint | NULL | Internal | wallet_ledger_entry | null=not a correction of an earlier entry |
| note | character varying(250) | NULL | Internal |  | null=no note |
| occurred_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_at | timestamp with time zone | NOT NULL | Internal |  |  |
| created_by | bigint | NOT NULL | Internal | user_account |  |
