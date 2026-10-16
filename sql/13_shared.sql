-- =============================================================================
-- Talentra :: 13_shared.sql
-- Module: Shared team items — team, Phase 4 (B50)
-- Credentials, consent records, blocking lists and the system error log.
-- Identity sessions are user_session (10_licences.sql, decision D15) and the audit
-- trail is audit_event (05_administration.sql); both are reused, not duplicated.
-- =============================================================================
SET app.current_user_id = '1';

CALL create_lookup_table('credential_type', 'SYSTEM: 1=password; google, linkedin, microsoft');
CALL create_lookup_table('consent_purpose', 'terms_of_service, privacy_policy, marketing_email, marketing_sms, marketing_whatsapp, profile_sharing, data_processing');
CALL create_lookup_table('block_reason',    'spam, harassment, not_interested, privacy, other');
CALL create_lookup_table('error_severity',  'warning, error, critical');

CALL seed_lookups('credential_type', ARRAY['password|Password', 'google|Google sign-in', 'linkedin|LinkedIn sign-in', 'microsoft|Microsoft sign-in']);
CALL seed_lookups('consent_purpose', ARRAY['terms_of_service|Terms of service', 'privacy_policy|Privacy policy', 'marketing_email|Marketing email',
    'marketing_sms|Marketing SMS', 'marketing_whatsapp|Marketing WhatsApp', 'profile_sharing|Profile sharing with employers', 'data_processing|Data processing']);
CALL seed_lookups('block_reason', ARRAY['spam|Spam', 'harassment|Harassment', 'not_interested|Not interested', 'privacy|Privacy', 'other|Other']);
CALL seed_lookups('error_severity', ARRAY['warning|Warning', 'error|Error', 'critical|Critical']);

-- Credentials (Sensitive): a password is stored only as an adaptive hash (argon2id,
-- encoded string incl. salt and parameters); a social sign-in only as a keyed hash
-- of the provider's subject id. Revoked credentials are kept for audit.
CREATE TABLE user_credential (
    id                    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_account_id       bigint       NOT NULL REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    credential_type_id    bigint       NOT NULL REFERENCES credential_type (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    password_hash         varchar(255),
    provider_subject_hmac bytea,
    last_used_at          timestamptz,
    revoked_at            timestamptz,
    created_at            timestamptz  NOT NULL DEFAULT now(),
    created_by            bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at            timestamptz  NOT NULL DEFAULT now(),
    updated_by            bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    -- a password row carries a hash and nothing else; a social row carries the subject hash
    CONSTRAINT ck_user_credential_secret CHECK ((credential_type_id = 1) = (password_hash IS NOT NULL)
                                                AND (credential_type_id = 1) = (provider_subject_hmac IS NULL)),
    CONSTRAINT ck_user_credential_date_range CHECK (revoked_at >= created_at)
);
CREATE INDEX idx_user_credential_user_account_id ON user_credential (user_account_id);

-- Consent is a history: every grant or withdrawal is a new row (append-only); the
-- current state is the latest row per user and purpose.
CREATE TABLE consent_record (
    id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_account_id    bigint       NOT NULL REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    consent_purpose_id bigint       NOT NULL REFERENCES consent_purpose (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    policy_version     varchar(20)  NOT NULL,
    is_granted         boolean      NOT NULL,
    recorded_at        timestamptz  NOT NULL DEFAULT now(),
    source_ip          inet,
    user_agent         varchar(500),
    created_at         timestamptz  NOT NULL DEFAULT now(),
    created_by         bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
CREATE INDEX idx_consent_record_user_account_id ON consent_record (user_account_id, consent_purpose_id, recorded_at DESC);
CALL make_append_only('consent_record');

-- Blocking lists for candidates, employers, recruiters and consultants: a user blocks
-- one user or one organisation. Unblocking closes the entry; history is kept.
CREATE TABLE block_entry (
    id                      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    blocker_user_account_id bigint       NOT NULL REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    blocked_user_account_id bigint REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    blocked_organisation_id bigint REFERENCES organisation (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    block_reason_id         bigint REFERENCES block_reason (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    blocked_at              timestamptz  NOT NULL DEFAULT now(),
    unblocked_at            timestamptz,
    created_at              timestamptz  NOT NULL DEFAULT now(),
    created_by              bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at              timestamptz  NOT NULL DEFAULT now(),
    updated_by              bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_block_entry_one_target CHECK (num_nonnulls(blocked_user_account_id, blocked_organisation_id) = 1),
    CONSTRAINT ck_block_entry_not_self CHECK (blocked_user_account_id <> blocker_user_account_id),
    CONSTRAINT ck_block_entry_date_range CHECK (unblocked_at >= blocked_at)
);
CREATE INDEX idx_block_entry_blocker_user_account_id ON block_entry (blocker_user_account_id) WHERE unblocked_at IS NULL;
CREATE INDEX idx_block_entry_blocked_user_account_id ON block_entry (blocked_user_account_id) WHERE unblocked_at IS NULL AND blocked_user_account_id IS NOT NULL;
CREATE INDEX idx_block_entry_blocked_organisation_id ON block_entry (blocked_organisation_id) WHERE unblocked_at IS NULL AND blocked_organisation_id IS NOT NULL;

-- System errors (Tier 1 "audit and error logging"): append-only, monthly partitions.
-- created_by is the actor when one was set, else the system user.
CREATE TABLE system_error_event (
    id                bigint GENERATED ALWAYS AS IDENTITY,
    error_severity_id bigint        NOT NULL REFERENCES error_severity (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    source_component  varchar(100)  NOT NULL,
    error_code        varchar(50)   NOT NULL,
    message           varchar(1000) NOT NULL,
    correlation_ref   varchar(100),
    occurred_at       timestamptz   NOT NULL DEFAULT now(),
    created_at        timestamptz   NOT NULL DEFAULT now(),
    created_by        bigint        NOT NULL DEFAULT coalesce(app_current_user_id(), 1) REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT pk_system_error_event PRIMARY KEY (id, occurred_at)
) PARTITION BY RANGE (occurred_at);
CREATE INDEX idx_system_error_event_error_code ON system_error_event (error_code, occurred_at);
CALL create_monthly_partitions('system_error_event', DATE '2025-01-01', DATE '2027-01-01');
CALL make_append_only('system_error_event');

-- -----------------------------------------------------------------------------
-- Classification and nullability justification (rule groups 5, 6)
-- -----------------------------------------------------------------------------
COMMENT ON COLUMN user_credential.password_hash         IS 'class=Sensitive; argon2id encoded hash (salt and cost inside), never the password; null=social sign-in credential';
COMMENT ON COLUMN user_credential.provider_subject_hmac IS 'class=Sensitive; HMAC of the provider subject id; null=password credential';
COMMENT ON COLUMN user_credential.last_used_at          IS 'class=Internal; null=never used';
COMMENT ON COLUMN user_credential.revoked_at            IS 'class=Internal; null=credential live';
COMMENT ON COLUMN consent_record.policy_version         IS 'class=Internal; version of the policy text the user saw';
COMMENT ON COLUMN consent_record.recorded_at            IS 'class=Internal';
COMMENT ON COLUMN consent_record.source_ip              IS 'class=Personal; evidence of the consent; null=recorded offline or by import';
COMMENT ON COLUMN consent_record.user_agent             IS 'class=Personal; null=recorded offline or by import';
COMMENT ON COLUMN block_entry.blocked_user_account_id   IS 'class=Personal; null=an organisation is blocked';
COMMENT ON COLUMN block_entry.blocked_organisation_id   IS 'class=Personal; null=a user is blocked';
COMMENT ON COLUMN block_entry.block_reason_id           IS 'class=Personal; null=no reason given';
COMMENT ON COLUMN block_entry.blocked_at                IS 'class=Personal';
COMMENT ON COLUMN block_entry.unblocked_at              IS 'class=Personal; null=block in force';
COMMENT ON COLUMN system_error_event.source_component   IS 'class=Internal; service or job that failed';
COMMENT ON COLUMN system_error_event.error_code         IS 'class=Internal';
COMMENT ON COLUMN system_error_event.message            IS 'class=Internal; must not contain personal data (logging rule)';
COMMENT ON COLUMN system_error_event.correlation_ref    IS 'class=Internal; request or trace id; null=not from a request';
COMMENT ON COLUMN system_error_event.occurred_at        IS 'class=Internal; partition key';

CALL make_audited('user_credential');
CALL make_audited('block_entry');
CALL attach_audit_triggers();
RESET app.current_user_id;
