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

CALL create_lookup_table('licence_status',     'SYSTEM: 1=active; suspended, expired, cancelled');
CALL create_lookup_table('device_platform',    'web, android, ios, windows, macos, linux');
CALL create_lookup_table('session_end_reason', 'SYSTEM: 1=logout, 2=idle_timeout, 3=expired, 4=revoked');
CALL create_lookup_table('login_outcome',      'SYSTEM: 1=success, 2=invalid_credentials, 3=account_locked, 4=device_limit_reached, 5=seat_unavailable, 6=licence_inactive');
CALL create_lookup_table('revocation_reason',  'SYSTEM: 1=user_request, 2=admin_action, 3=device_lost, 4=security_incident, 5=seat_released');

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
    -- target of the session / login composite FKs: a session runs on a device of its own user
    CONSTRAINT uq_user_device_id_user_account_id UNIQUE (id, user_account_id),
    CONSTRAINT ck_user_device_date_range CHECK (last_seen_at >= first_seen_at AND revoked_at >= first_seen_at)
);
-- One live registration per fingerprint and user; a revoked device can be registered again.
CREATE UNIQUE INDEX uq_user_device_user_account_id_fingerprint ON user_device (user_account_id, device_fingerprint_hmac) WHERE revoked_at IS NULL;

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
-- M14 (B45) rules (rule groups 2 and 9).
-- Seat limit: assigning a seat locks the licence row, so concurrent assignments
--   queue and live seats never exceed max_users.
-- Device limit, enforced at login: opening a session locks the user's seat row, so
--   two concurrent logins of one user queue and the second counts the first.
--   A session counts while ended_at IS NULL and expires_at > now(). It is released
--   by logout or revocation (ended_at set) or by passing expires_at. Users without a
--   seat (candidates, gig workers) hold no licence and have no device limit.
-- ponytail: correct at READ COMMITTED (default) and SERIALIZABLE; REPEATABLE READ
--   would need the seat row updated, not just locked.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_licence_seat_rules() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE l licence; v_live int;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.licence_id <> OLD.licence_id OR NEW.user_account_id <> OLD.user_account_id
           OR (OLD.released_at IS NOT NULL AND NEW.released_at IS DISTINCT FROM OLD.released_at) THEN
            RAISE EXCEPTION 'seat % is history: only releasing a live seat is allowed', OLD.id;
        END IF;
        RETURN NEW;
    END IF;
    SELECT * INTO l FROM licence WHERE id = NEW.licence_id FOR UPDATE;
    IF l.licence_status_id <> 1 THEN RAISE EXCEPTION 'licence % is not active', l.id; END IF;
    IF NOT EXISTS (SELECT 1 FROM organisation_member m WHERE m.organisation_id = l.organisation_id
                   AND m.user_account_id = NEW.user_account_id AND m.valid_from <= now() AND (m.valid_to IS NULL OR m.valid_to > now())) THEN
        RAISE EXCEPTION 'user % is not a current member of the organisation of licence %', NEW.user_account_id, l.id;
    END IF;
    SELECT count(*) INTO v_live FROM licence_seat WHERE licence_id = l.id AND released_at IS NULL;
    IF NEW.released_at IS NULL AND v_live >= l.max_users THEN
        RAISE EXCEPTION 'licence % has no free seat (% of % in use)', l.id, v_live, l.max_users;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_licence_seat_rules BEFORE INSERT OR UPDATE ON licence_seat
    FOR EACH ROW EXECUTE FUNCTION trg_licence_seat_rules();

-- Releasing a seat ends its sessions; each is an auditable revocation.
CREATE OR REPLACE FUNCTION trg_licence_seat_released() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    WITH ended AS (
        UPDATE user_session SET ended_at = now(), session_end_reason_id = 4
        WHERE licence_seat_id = NEW.id AND ended_at IS NULL RETURNING id, user_device_id)
    INSERT INTO session_revocation_event (user_session_id, user_device_id, revocation_reason_id)
    SELECT id, user_device_id, 5 FROM ended;
    RETURN NULL;
END $$;
CREATE TRIGGER trg_licence_seat_released AFTER UPDATE OF released_at ON licence_seat
    FOR EACH ROW WHEN (OLD.released_at IS NULL AND NEW.released_at IS NOT NULL) EXECUTE FUNCTION trg_licence_seat_released();

CREATE OR REPLACE FUNCTION trg_user_session_rules() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE l licence; v_live int;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.user_account_id <> OLD.user_account_id OR NEW.user_device_id <> OLD.user_device_id
           OR NEW.licence_seat_id IS DISTINCT FROM OLD.licence_seat_id OR NEW.started_at <> OLD.started_at
           OR (OLD.ended_at IS NOT NULL AND NEW.ended_at IS DISTINCT FROM OLD.ended_at) THEN
            RAISE EXCEPTION 'session %: only activity, expiry and ending may change; an ended session stays ended', OLD.id;
        END IF;
        RETURN NEW;
    END IF;
    IF EXISTS (SELECT 1 FROM user_device WHERE id = NEW.user_device_id AND revoked_at IS NOT NULL) THEN
        RAISE EXCEPTION 'device % is revoked', NEW.user_device_id;
    END IF;
    -- a licensed user always logs in on a seat, so leaving the seat out cannot bypass the limit
    -- ponytail: a user with live seats on two licences is placed on the lowest seat id
    IF NEW.licence_seat_id IS NULL THEN
        SELECT id INTO NEW.licence_seat_id FROM licence_seat
        WHERE user_account_id = NEW.user_account_id AND released_at IS NULL ORDER BY id LIMIT 1;
    END IF;
    IF NEW.licence_seat_id IS NOT NULL THEN
        PERFORM 1 FROM licence_seat WHERE id = NEW.licence_seat_id AND released_at IS NULL FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'seat % is released', NEW.licence_seat_id; END IF;
        SELECT l2.* INTO l FROM licence l2 JOIN licence_seat s ON s.licence_id = l2.id WHERE s.id = NEW.licence_seat_id;
        IF l.licence_status_id <> 1 THEN RAISE EXCEPTION 'licence % is not active', l.id; END IF;
        SELECT count(*) INTO v_live FROM user_session
        WHERE licence_seat_id = NEW.licence_seat_id AND ended_at IS NULL AND expires_at > now();
        IF v_live >= l.max_devices_per_user THEN
            RAISE EXCEPTION 'device limit reached: user % has % active session(s), licence % allows %',
                NEW.user_account_id, v_live, l.id, l.max_devices_per_user;
        END IF;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_user_session_rules BEFORE INSERT OR UPDATE ON user_session
    FOR EACH ROW EXECUTE FUNCTION trg_user_session_rules();

-- A revoked device stays revoked (register it again) and its live sessions end at once.
CREATE OR REPLACE FUNCTION trg_user_device_rules() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.user_account_id <> OLD.user_account_id OR NEW.device_fingerprint_hmac <> OLD.device_fingerprint_hmac
       OR (OLD.revoked_at IS NOT NULL AND NEW.revoked_at IS DISTINCT FROM OLD.revoked_at) THEN
        RAISE EXCEPTION 'device %: identity cannot change and a revoked device stays revoked', OLD.id;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_user_device_rules BEFORE UPDATE ON user_device
    FOR EACH ROW EXECUTE FUNCTION trg_user_device_rules();
CREATE OR REPLACE FUNCTION trg_user_device_revoked() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE user_session SET ended_at = now(), session_end_reason_id = 4 WHERE user_device_id = NEW.id AND ended_at IS NULL;
    RETURN NULL;
END $$;
CREATE TRIGGER trg_user_device_revoked AFTER UPDATE OF revoked_at ON user_device
    FOR EACH ROW WHEN (OLD.revoked_at IS NULL AND NEW.revoked_at IS NOT NULL) EXECUTE FUNCTION trg_user_device_revoked();

-- Login entry point. Opens a session, or records the refused attempt in the login
-- history and the audit trail and returns NULL (no exception, so the record survives).
-- The direct-insert trigger above stays as the backstop.
CREATE OR REPLACE FUNCTION app_open_session(p_user_account_id bigint, p_user_device_id bigint, p_identifier_hmac bytea,
    p_session_token_hash bytea, p_expires_at timestamptz, p_source_ip inet DEFAULT NULL, p_user_agent varchar DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v_seat bigint; l licence; v_live int := 0; v_outcome bigint; v_session bigint;
BEGIN
    SELECT id INTO v_seat FROM licence_seat WHERE user_account_id = p_user_account_id AND released_at IS NULL
    ORDER BY id LIMIT 1 FOR UPDATE;
    IF v_seat IS NOT NULL THEN
        SELECT l2.* INTO l FROM licence l2 JOIN licence_seat s ON s.licence_id = l2.id WHERE s.id = v_seat;
        SELECT count(*) INTO v_live FROM user_session WHERE licence_seat_id = v_seat AND ended_at IS NULL AND expires_at > now();
        v_outcome := CASE WHEN l.licence_status_id <> 1 THEN 6 WHEN v_live >= l.max_devices_per_user THEN 4 END;
    END IF;
    IF v_outcome IS NULL THEN
        INSERT INTO user_session (user_account_id, user_device_id, licence_seat_id, session_token_hash, expires_at, created_by, updated_by)
        VALUES (p_user_account_id, p_user_device_id, v_seat, p_session_token_hash, p_expires_at, p_user_account_id, p_user_account_id)
        RETURNING id INTO v_session;
    ELSE
        INSERT INTO audit_event (audit_action_id, target_table, organisation_id, source_ip, user_agent, detail, created_by)
        SELECT a.id, 'user_session', l.organisation_id, p_source_ip, p_user_agent,
               jsonb_build_object('reason', o.code, 'active_sessions', v_live, 'max_devices_per_user', l.max_devices_per_user),
               p_user_account_id
        FROM audit_action a, login_outcome o WHERE a.code = 'login_failed' AND o.id = v_outcome;
    END IF;
    INSERT INTO login_attempt (user_account_id, attempted_identifier_hmac, user_device_id, login_outcome_id, source_ip, user_agent, created_by)
    VALUES (p_user_account_id, p_identifier_hmac, p_user_device_id, coalesce(v_outcome, 1), p_source_ip, p_user_agent, p_user_account_id);
    RETURN v_session;
END $$;

-- Revocation is always an event (rule group 9); created_by is who revoked.
CREATE OR REPLACE FUNCTION app_revoke_session(p_user_session_id bigint, p_revocation_reason_id bigint) RETURNS void
LANGUAGE sql AS $$
    WITH ended AS (UPDATE user_session SET ended_at = now(), session_end_reason_id = 4
                   WHERE id = p_user_session_id AND ended_at IS NULL RETURNING id, user_device_id)
    INSERT INTO session_revocation_event (user_session_id, user_device_id, revocation_reason_id)
    SELECT id, user_device_id, p_revocation_reason_id FROM ended
$$;
CREATE OR REPLACE FUNCTION app_revoke_device(p_user_device_id bigint, p_revocation_reason_id bigint) RETURNS void
LANGUAGE sql AS $$
    WITH revoked AS (UPDATE user_device SET revoked_at = now() WHERE id = p_user_device_id AND revoked_at IS NULL RETURNING id)
    INSERT INTO session_revocation_event (user_device_id, revocation_reason_id)
    SELECT id, p_revocation_reason_id FROM revoked
$$;

CALL make_audited('licence');
CALL make_audited('licence_seat');
CALL make_audited('user_device');

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
