-- V003 Identity and access: users, credentials, roles and permissions, consent, devices and sessions.
-- Requirements: FR-IAM-01..08, NFR-SEC-02 (credentials), NFR-PRIV-01 (consent), docket rule group 9 (devices, sessions).

CREATE TABLE app_user (                      -- "user" is reserved in PostgreSQL
    id                     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email                  email_address CONSTRAINT uq_app_user_email UNIQUE,
    phone_e164             phone_e164,
    phone_country_id       smallint REFERENCES country (id) ON DELETE RESTRICT,
    account_status_id      smallint NOT NULL DEFAULT 1 REFERENCES account_status (id) ON DELETE RESTRICT,
    preferred_language_id  smallint NOT NULL DEFAULT 1 REFERENCES language (id) ON DELETE RESTRICT,
    time_zone              text NOT NULL DEFAULT 'Asia/Kolkata' CHECK (time_zone ~ '^[A-Za-z_]+(/[A-Za-z0-9_+-]+)*$'),
    last_login_at          timestamptz,
    deleted_at             timestamptz,
    CONSTRAINT ck_app_user_email_erased   CHECK ((email IS NULL) = (account_status_id = 4)),
    CONSTRAINT ck_app_user_phone_country  CHECK ((phone_e164 IS NULL) = (phone_country_id IS NULL)),
    CONSTRAINT ck_app_user_erased_deleted CHECK (account_status_id <> 4 OR deleted_at IS NOT NULL)
);
CALL add_audit_columns('app_user');
CREATE INDEX idx_app_user_phone_e164 ON app_user (phone_e164) WHERE phone_e164 IS NOT NULL;   -- AP-12 duplicate check
COMMENT ON COLUMN app_user.email IS 'Personal. Login identifier, unique. NULL: only after erasure (account_status erased), enforced by ck_app_user_email_erased.';
COMMENT ON COLUMN app_user.phone_e164 IS 'Personal. E.164 with country code; not unique (shared family phones are common). NULL: phone is optional at sign-up.';
COMMENT ON COLUMN app_user.phone_country_id IS 'Internal. Country of the phone number. NULL: exactly when phone_e164 is NULL.';
COMMENT ON COLUMN app_user.last_login_at IS 'Internal. NULL: the user has never logged in (invited or migrated account).';
COMMENT ON COLUMN app_user.time_zone IS 'Internal. IANA zone of the user, used to display UTC timestamps.';

CREATE TABLE user_credential (
    id                    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    app_user_id           bigint NOT NULL CONSTRAINT uq_user_credential_app_user_id UNIQUE REFERENCES app_user (id) ON DELETE CASCADE,
    password_hash         text NOT NULL CONSTRAINT ck_user_credential_password_hash_argon2id
                          CHECK (password_hash ~ '^\$argon2id\$v=19\$m=[0-9]+,t=[0-9]+,p=[0-9]+\$[A-Za-z0-9+/]+\$[A-Za-z0-9+/]+$'),
    password_changed_at   timestamptz NOT NULL DEFAULT now(),
    failed_attempt_count  smallint NOT NULL DEFAULT 0 CHECK (failed_attempt_count >= 0),
    locked_until          timestamptz
);
CALL add_audit_columns('user_credential');
COMMENT ON TABLE user_credential IS 'Sensitive. Separate from app_user so the runtime role has no access to it at all (ADR-009).';
COMMENT ON COLUMN user_credential.password_hash IS 'Sensitive. argon2id PHC string, hashed by the API; the plain password never reaches the database.';
COMMENT ON COLUMN user_credential.locked_until IS 'Internal. NULL: not locked out.';

-- Permissions per role are configuration, versioned like reference data.
CREATE TABLE access_role_permission (
    id                    smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    access_role_id        smallint NOT NULL REFERENCES access_role (id) ON DELETE CASCADE,
    access_permission_id  smallint NOT NULL REFERENCES access_permission (id) ON DELETE CASCADE,
    CONSTRAINT uq_access_role_permission_access_role_id_access_permission_id UNIQUE (access_role_id, access_permission_id)
);
CREATE INDEX idx_access_role_permission_access_permission_id ON access_role_permission (access_permission_id);
INSERT INTO access_role_permission (access_role_id, access_permission_id)
SELECT r.id, p.id FROM access_role r JOIN access_permission p ON
     r.code = 'super_admin'
  OR (r.code = 'admin' AND p.code IN ('user_manage', 'organisation_verify', 'audit_read'))
  OR (r.code = 'account_admin' AND p.code IN ('job_post', 'job_manage', 'application_manage', 'candidate_search', 'candidate_download', 'billing_manage', 'audit_read', 'member_manage'))
  OR (r.code = 'employer' AND p.code IN ('job_post', 'job_manage', 'application_manage', 'candidate_search', 'candidate_download'))
  OR (r.code = 'recruiter' AND p.code IN ('job_manage', 'application_manage', 'candidate_search', 'candidate_download'))
  OR (r.code = 'consultant' AND p.code IN ('candidate_search', 'consultant_source'))
  OR (r.code = 'placement_officer' AND p.code IN ('candidate_search'));

CREATE TABLE user_access_role (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    app_user_id     bigint NOT NULL REFERENCES app_user (id) ON DELETE CASCADE,
    access_role_id  smallint NOT NULL REFERENCES access_role (id) ON DELETE RESTRICT,
    CONSTRAINT uq_user_access_role_app_user_id_access_role_id UNIQUE (app_user_id, access_role_id)
);
CALL add_audit_columns('user_access_role');

-- Consent is a history: the current consent per purpose is the latest record (view consent_current).
CREATE TABLE consent_record (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    app_user_id         bigint NOT NULL REFERENCES app_user (id) ON DELETE CASCADE,
    consent_purpose_id  smallint NOT NULL REFERENCES consent_purpose (id) ON DELETE RESTRICT,
    is_granted          boolean NOT NULL,
    policy_version      text NOT NULL CHECK (policy_version ~ '^[0-9]{4}-[0-9]{2}(\.[0-9]+)?$'),
    recorded_at         timestamptz NOT NULL DEFAULT now(),
    ip_address          inet
);
CALL add_audit_columns('consent_record', append_only => true);
CREATE INDEX idx_consent_record_app_user_id ON consent_record (app_user_id, consent_purpose_id, recorded_at DESC);
COMMENT ON COLUMN consent_record.ip_address IS 'Personal. Evidence of where consent was given. NULL: recorded by a back-office or migration process.';

CREATE VIEW consent_current WITH (security_invoker = true) AS
SELECT DISTINCT ON (app_user_id, consent_purpose_id) app_user_id, consent_purpose_id, is_granted, policy_version, recorded_at
FROM consent_record ORDER BY app_user_id, consent_purpose_id, recorded_at DESC, id DESC;

CREATE TABLE user_device (
    id                       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    app_user_id              bigint NOT NULL REFERENCES app_user (id) ON DELETE CASCADE,
    device_fingerprint_hash  sha256_digest NOT NULL,
    device_label             short_text,
    first_seen_at            timestamptz NOT NULL DEFAULT now(),
    last_seen_at             timestamptz NOT NULL DEFAULT now(),
    revoked_at               timestamptz,
    CONSTRAINT uq_user_device_app_user_id_device_fingerprint_hash UNIQUE (app_user_id, device_fingerprint_hash),
    CONSTRAINT uq_user_device_id_app_user_id UNIQUE (id, app_user_id),            -- target of the session's composite key
    CONSTRAINT ck_user_device_seen CHECK (last_seen_at >= first_seen_at)
);
CALL add_audit_columns('user_device');
COMMENT ON COLUMN user_device.device_fingerprint_hash IS 'Internal. SHA-256 of the client device identifier; the raw identifier is not stored.';
COMMENT ON COLUMN user_device.device_label IS 'Internal. Name shown in "your devices", e.g. "Chrome on Windows". NULL: client did not send one.';
COMMENT ON COLUMN user_device.revoked_at IS 'Internal. NULL: the device is trusted. Revoking ends its sessions (auditable, rule group 9).';

-- An active session: ended_at IS NULL and expires_at in the future. Only active sessions count against the device limit.
CREATE TABLE user_session (
    id                     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    app_user_id            bigint NOT NULL REFERENCES app_user (id) ON DELETE CASCADE,
    user_device_id         bigint NOT NULL,
    token_hash             sha256_digest NOT NULL CONSTRAINT uq_user_session_token_hash UNIQUE,
    started_at             timestamptz NOT NULL DEFAULT now(),
    last_activity_at       timestamptz NOT NULL DEFAULT now(),
    expires_at             timestamptz NOT NULL,
    ended_at               timestamptz,
    session_end_reason_id  smallint REFERENCES session_end_reason (id) ON DELETE RESTRICT,
    CONSTRAINT fk_user_session_user_device FOREIGN KEY (user_device_id, app_user_id)
        REFERENCES user_device (id, app_user_id) ON DELETE CASCADE,
    CONSTRAINT ck_user_session_times  CHECK (last_activity_at >= started_at AND expires_at > started_at AND (ended_at IS NULL OR ended_at >= started_at)),
    CONSTRAINT ck_user_session_ended  CHECK ((ended_at IS NULL) = (session_end_reason_id IS NULL))
);
CALL add_audit_columns('user_session');
CREATE INDEX idx_user_session_app_user_id_active ON user_session (app_user_id) WHERE ended_at IS NULL;    -- AP-11 device-limit count
CREATE INDEX idx_user_session_user_device_id ON user_session (user_device_id, app_user_id);
COMMENT ON COLUMN user_session.token_hash IS 'Sensitive. SHA-256 of the session token; the token itself is only in the client.';
COMMENT ON COLUMN user_session.ended_at IS 'Internal. NULL: session not ended (still active until expires_at).';
COMMENT ON COLUMN user_session.session_end_reason_id IS 'Internal. Why the session ended. NULL: exactly when ended_at is NULL.';
