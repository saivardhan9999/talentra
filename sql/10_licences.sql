-- =============================================================================
-- Talentra :: 10_licences.sql
-- Module: Licences, seats, devices and sessions — individual, Phase 3, Member A
-- A subscription grants one licence with a maximum number of users (seats) and a
-- maximum number of devices per user. Users register devices; every login opens a
-- session on a device; every attempt (including one refused at the device limit)
-- is recorded; revocations are events. user_session is also the identity session
-- the docket lists under the Phase 4 shared items (B50): one table, not two.
-- =============================================================================
SET app.current_user_id = '1';

CALL create_lookup_table('licence_status',     'active, suspended, expired, cancelled');
CALL create_lookup_table('device_platform',    'web, android, ios, windows, macos, linux');
CALL create_lookup_table('session_end_reason', 'logout, idle_timeout, expired, revoked');
CALL create_lookup_table('login_outcome',      'success, invalid_credentials, account_locked, device_limit_reached, seat_unavailable, licence_inactive');
CALL create_lookup_table('revocation_reason',  'user_request, admin_action, device_lost, security_incident, seat_released');

CALL seed_lookups('licence_status', ARRAY['active|Active', 'suspended|Suspended', 'expired|Expired', 'cancelled|Cancelled']);
CALL seed_lookups('device_platform', ARRAY['web|Web browser', 'android|Android', 'ios|iOS', 'windows|Windows', 'macos|macOS', 'linux|Linux']);
CALL seed_lookups('session_end_reason', ARRAY['logout|Logged out', 'idle_timeout|Idle timeout', 'expired|Expired', 'revoked|Revoked']);
CALL seed_lookups('login_outcome', ARRAY['success|Success', 'invalid_credentials|Invalid credentials', 'account_locked|Account locked',
                                         'device_limit_reached|Device limit reached', 'seat_unavailable|No seat available',
                                         'licence_inactive|Licence inactive']);
CALL seed_lookups('revocation_reason', ARRAY['user_request|User request', 'admin_action|Administrator action', 'device_lost|Device lost',
                                             'security_incident|Security incident', 'seat_released|Seat released']);

-- Limits are copied from the plan at purchase and stored as explicit, positive columns (rule group 9).
CREATE TABLE licence (
    id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organisation_id      bigint      NOT NULL REFERENCES organisation (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    subscription_id      bigint      NOT NULL,
    licence_status_id    bigint      NOT NULL REFERENCES licence_status (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    max_users            integer     NOT NULL,
    max_devices_per_user integer     NOT NULL,
    created_at           timestamptz NOT NULL DEFAULT now(),
    created_by           bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at           timestamptz NOT NULL DEFAULT now(),
    updated_by           bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    -- the licence's organisation is always the subscribing organisation
    CONSTRAINT fk_licence_subscription FOREIGN KEY (subscription_id, organisation_id)
        REFERENCES subscription (id, organisation_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_licence_max_users CHECK (max_users > 0),
    CONSTRAINT ck_licence_max_devices_per_user CHECK (max_devices_per_user > 0)
);
CREATE UNIQUE INDEX uq_licence_subscription_id ON licence (subscription_id);
CREATE INDEX idx_licence_organisation_id ON licence (organisation_id);

-- Seat allocation; a seat is released, never deleted.
CREATE TABLE licence_seat (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    licence_id      bigint      NOT NULL REFERENCES licence (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    user_account_id bigint      NOT NULL REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    assigned_at     timestamptz NOT NULL DEFAULT now(),
    released_at     timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now(),
    created_by      bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at      timestamptz NOT NULL DEFAULT now(),
    updated_by      bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    -- target of user_session's composite FK: a session uses a seat of its own user
    CONSTRAINT uq_licence_seat_id_user_account_id UNIQUE (id, user_account_id),
    CONSTRAINT ck_licence_seat_date_range CHECK (released_at >= assigned_at)
);
CREATE UNIQUE INDEX uq_licence_seat_licence_id_user_account_id ON licence_seat (licence_id, user_account_id) WHERE released_at IS NULL;
CREATE INDEX idx_licence_seat_user_account_id ON licence_seat (user_account_id);

-- Registered devices. The fingerprint is stored only as a keyed hash.
CREATE TABLE user_device (
    id                      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_account_id         bigint       NOT NULL REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    device_platform_id      bigint       NOT NULL REFERENCES device_platform (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    device_fingerprint_hmac bytea        NOT NULL,
    device_label            varchar(100),
    first_seen_at           timestamptz  NOT NULL DEFAULT now(),
    last_seen_at            timestamptz  NOT NULL DEFAULT now(),
    revoked_at              timestamptz,
    created_at              timestamptz  NOT NULL DEFAULT now(),
    created_by              bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at              timestamptz  NOT NULL DEFAULT now(),
    updated_by              bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_user_device_user_account_id_fingerprint UNIQUE (user_account_id, device_fingerprint_hmac),
    -- target of the session / login composite FKs: a session runs on a device of its own user
    CONSTRAINT uq_user_device_id_user_account_id UNIQUE (id, user_account_id),
    CONSTRAINT ck_user_device_date_range CHECK (last_seen_at >= first_seen_at AND revoked_at >= first_seen_at)
);

-- One row per login. Expired or revoked sessions (ended_at set) do not count
-- against the device limit (rule group 9).
CREATE TABLE user_session (
    id                    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_account_id       bigint      NOT NULL REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    user_device_id        bigint      NOT NULL,
    licence_seat_id       bigint,
    session_token_hash    bytea       NOT NULL,
    started_at            timestamptz NOT NULL DEFAULT now(),
    last_activity_at      timestamptz NOT NULL DEFAULT now(),
    expires_at            timestamptz NOT NULL,
    ended_at              timestamptz,
    session_end_reason_id bigint REFERENCES session_end_reason (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    created_at            timestamptz NOT NULL DEFAULT now(),
    created_by            bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at            timestamptz NOT NULL DEFAULT now(),
    updated_by            bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_user_session_user_device FOREIGN KEY (user_device_id, user_account_id)
        REFERENCES user_device (id, user_account_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_user_session_licence_seat FOREIGN KEY (licence_seat_id, user_account_id)
        REFERENCES licence_seat (id, user_account_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_user_session_session_token_hash UNIQUE (session_token_hash),
    -- target of session_revocation_event's composite FK
    CONSTRAINT uq_user_session_id_user_device_id UNIQUE (id, user_device_id),
    CONSTRAINT ck_user_session_date_range CHECK (expires_at > started_at AND last_activity_at >= started_at AND ended_at >= started_at),
    CONSTRAINT ck_user_session_end CHECK ((ended_at IS NULL) = (session_end_reason_id IS NULL))
);
-- Live sessions per user: the device-limit check reads this.
CREATE INDEX idx_user_session_user_account_id_live ON user_session (user_account_id, user_device_id) WHERE ended_at IS NULL;
CREATE INDEX idx_user_session_user_device_id ON user_session (user_device_id);
CREATE INDEX idx_user_session_licence_seat_id ON user_session (licence_seat_id) WHERE licence_seat_id IS NOT NULL;

-- Login history, including refused attempts. Append-only, monthly partitions.
CREATE TABLE login_attempt (
    id                         bigint GENERATED ALWAYS AS IDENTITY,
    user_account_id            bigint REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    attempted_identifier_hmac  bytea       NOT NULL,
    user_device_id             bigint,
    login_outcome_id           bigint      NOT NULL REFERENCES login_outcome (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    source_ip                  inet,
    user_agent                 varchar(500),
    attempted_at               timestamptz NOT NULL DEFAULT now(),
    created_at                 timestamptz NOT NULL DEFAULT now(),
    created_by                 bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT pk_login_attempt PRIMARY KEY (id, attempted_at),
    CONSTRAINT fk_login_attempt_user_device FOREIGN KEY (user_device_id, user_account_id)
        REFERENCES user_device (id, user_account_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_login_attempt_device_needs_user CHECK (user_device_id IS NULL OR user_account_id IS NOT NULL)
) PARTITION BY RANGE (attempted_at);
CREATE INDEX idx_login_attempt_user_account_id ON login_attempt (user_account_id, attempted_at);
CALL create_monthly_partitions('login_attempt', DATE '2025-01-01', DATE '2027-01-01');
CALL make_append_only('login_attempt');

-- Revoking a device or a session is an auditable event (rule group 9); created_by is who revoked.
CREATE TABLE session_revocation_event (
    id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_session_id      bigint,
    user_device_id       bigint REFERENCES user_device (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    revocation_reason_id bigint      NOT NULL REFERENCES revocation_reason (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    occurred_at          timestamptz NOT NULL DEFAULT now(),
    created_at           timestamptz NOT NULL DEFAULT now(),
    created_by           bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    -- with both set, the session must be one on that device; with only a session, it is checked alone
    CONSTRAINT fk_session_revocation_event_user_session FOREIGN KEY (user_session_id, user_device_id)
        REFERENCES user_session (id, user_device_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_session_revocation_event_user_session_only FOREIGN KEY (user_session_id)
        REFERENCES user_session (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_session_revocation_event_target CHECK (num_nonnulls(user_session_id, user_device_id) >= 1)
);
CREATE INDEX idx_session_revocation_event_user_device_id ON session_revocation_event (user_device_id) WHERE user_device_id IS NOT NULL;
CALL make_append_only('session_revocation_event');

-- -----------------------------------------------------------------------------
-- Classification and nullability justification (rule groups 5, 6)
-- -----------------------------------------------------------------------------
COMMENT ON COLUMN licence.max_users                  IS 'class=Internal; users allowed (> 0), copied from the plan';
COMMENT ON COLUMN licence.max_devices_per_user       IS 'class=Internal; devices allowed per user (> 0), copied from the plan';
COMMENT ON COLUMN licence_seat.assigned_at           IS 'class=Internal';
COMMENT ON COLUMN licence_seat.released_at           IS 'class=Internal; null=seat in use';
COMMENT ON COLUMN user_device.device_fingerprint_hmac IS 'class=Sensitive; HMAC of the device fingerprint, never the raw value';
COMMENT ON COLUMN user_device.device_label           IS 'class=Personal; user-given name; null=not named';
COMMENT ON COLUMN user_device.first_seen_at          IS 'class=Internal';
COMMENT ON COLUMN user_device.last_seen_at           IS 'class=Internal';
COMMENT ON COLUMN user_device.revoked_at             IS 'class=Internal; null=device allowed';
COMMENT ON COLUMN user_session.licence_seat_id       IS 'class=Internal; null=user needs no licence (candidate, gig worker)';
COMMENT ON COLUMN user_session.session_token_hash    IS 'class=Sensitive; SHA-256 of the session token, never the token';
COMMENT ON COLUMN user_session.started_at            IS 'class=Internal';
COMMENT ON COLUMN user_session.last_activity_at      IS 'class=Internal';
COMMENT ON COLUMN user_session.expires_at            IS 'class=Internal';
COMMENT ON COLUMN user_session.ended_at              IS 'class=Internal; null=session live (counts against the device limit)';
COMMENT ON COLUMN user_session.session_end_reason_id IS 'class=Internal; null exactly when the session is live';
COMMENT ON COLUMN login_attempt.user_account_id      IS 'class=Internal; null=identifier matched no account';
COMMENT ON COLUMN login_attempt.attempted_identifier_hmac IS 'class=Sensitive; HMAC of the identifier typed, for brute-force detection';
COMMENT ON COLUMN login_attempt.user_device_id       IS 'class=Internal; null=attempt from an unregistered device';
COMMENT ON COLUMN login_attempt.source_ip            IS 'class=Personal; null=not captured';
COMMENT ON COLUMN login_attempt.user_agent           IS 'class=Personal; null=not captured';
COMMENT ON COLUMN login_attempt.attempted_at         IS 'class=Internal; partition key';
COMMENT ON COLUMN session_revocation_event.user_session_id IS 'class=Internal; null=whole device revoked (user_device_id set)';
COMMENT ON COLUMN session_revocation_event.user_device_id  IS 'class=Internal; null=single session revoked (user_session_id set)';
COMMENT ON COLUMN session_revocation_event.occurred_at IS 'class=Internal';

CALL attach_audit_triggers();
RESET app.current_user_id;
