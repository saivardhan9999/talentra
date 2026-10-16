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
-- M18 (B59) the append-only audit trail, for every role and every partition.
-- A statement-level TRUNCATE trigger on a partitioned table does not fire for a
-- TRUNCATE of one partition, so each partition gets its own. Partitions added later
-- by create_monthly_partitions inherit the protection and the storage options.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE protect_partitions(p_table text)
LANGUAGE plpgsql AS $$
DECLARE r record;
BEGIN
    FOR r IN SELECT c.relname FROM pg_inherits i JOIN pg_class c ON c.oid = i.inhrelid WHERE i.inhparent = p_table::regclass LOOP
        EXECUTE format('CREATE OR REPLACE TRIGGER %I BEFORE TRUNCATE ON %I FOR EACH STATEMENT EXECUTE FUNCTION trg_forbid_modification()',
                       'trg_' || r.relname || '_no_truncate', r.relname);
    END LOOP;
END $$;

CREATE OR REPLACE PROCEDURE make_append_only(p_table text)
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION trg_forbid_modification()',
                   'trg_' || p_table || '_append_only', p_table);
    EXECUTE format('CREATE TRIGGER %I BEFORE TRUNCATE ON %I FOR EACH STATEMENT EXECUTE FUNCTION trg_forbid_modification()',
                   'trg_' || p_table || '_no_truncate', p_table);
    CALL revoke_append_only(p_table);
    IF (SELECT relkind FROM pg_class WHERE oid = p_table::regclass) = 'p' THEN CALL protect_partitions(p_table); END IF;
END $$;

CREATE OR REPLACE PROCEDURE create_monthly_partitions(p_table text, p_from date, p_to date)
LANGUAGE plpgsql AS $$
DECLARE d date := date_trunc('month', p_from); v_opts text[]; r record;
BEGIN
    WHILE d < p_to LOOP
        EXECUTE format('CREATE TABLE IF NOT EXISTS %I PARTITION OF %I FOR VALUES FROM (%L) TO (%L)',
                       p_table || '_p' || to_char(d, 'YYYYMM'), p_table, d, (d + interval '1 month')::date);
        d := (d + interval '1 month')::date;
    END LOOP;
    IF to_regclass(p_table || '_pdefault') IS NULL THEN
        EXECUTE format('CREATE TABLE %I PARTITION OF %I DEFAULT', p_table || '_pdefault', p_table);
    END IF;
    SELECT reloptions INTO v_opts FROM pg_class WHERE relname = p_table || '_pdefault';
    IF v_opts IS NOT NULL THEN
        FOR r IN SELECT c.relname FROM pg_inherits i JOIN pg_class c ON c.oid = i.inhrelid WHERE i.inhparent = p_table::regclass LOOP
            EXECUTE format('ALTER TABLE %I SET (%s)', r.relname, array_to_string(v_opts, ', '));
        END LOOP;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = p_table::regclass AND tgname = 'trg_' || p_table || '_no_truncate') THEN
        CALL protect_partitions(p_table);
    END IF;
END $$;

DO $$
DECLARE r record;
BEGIN
    FOR r IN SELECT c.relname FROM pg_class c JOIN pg_trigger t ON t.tgrelid = c.oid AND t.tgname = 'trg_' || c.relname || '_no_truncate'
             WHERE c.relkind = 'p' LOOP
        CALL protect_partitions(r.relname);
    END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- M18 (B59) credentials: one live credential per user and type, a social identity
-- linked to one user, a password only in argon2id form, and no in-place edits
-- (rotation = revoke + new row, so the history stays).
-- -----------------------------------------------------------------------------
CREATE UNIQUE INDEX uq_user_credential_user_account_id_credential_type_id ON user_credential (user_account_id, credential_type_id)
    WHERE revoked_at IS NULL;
CREATE UNIQUE INDEX uq_user_credential_credential_type_id_provider_subject_hmac ON user_credential (credential_type_id, provider_subject_hmac)
    WHERE revoked_at IS NULL AND provider_subject_hmac IS NOT NULL;
ALTER TABLE user_credential
    ADD CONSTRAINT ck_user_credential_password_hash_format
        CHECK (password_hash ~ '^\$argon2id\$v=19\$m=[0-9]+,t=[0-9]+,p=[0-9]+\$[A-Za-z0-9+/]+\$[A-Za-z0-9+/]+$'),
    ADD CONSTRAINT ck_user_credential_hmac_length CHECK (octet_length(provider_subject_hmac) = 32);

CREATE OR REPLACE FUNCTION trg_user_credential_rules() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.user_account_id <> OLD.user_account_id OR NEW.credential_type_id <> OLD.credential_type_id
       OR NEW.password_hash IS DISTINCT FROM OLD.password_hash OR NEW.provider_subject_hmac IS DISTINCT FROM OLD.provider_subject_hmac
       OR (OLD.revoked_at IS NOT NULL AND NEW.revoked_at IS DISTINCT FROM OLD.revoked_at) THEN
        RAISE EXCEPTION 'credential %: a secret is never edited in place; revoke it and add a new credential', OLD.id;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_user_credential_rules BEFORE UPDATE ON user_credential FOR EACH ROW EXECUTE FUNCTION trg_user_credential_rules();

-- -----------------------------------------------------------------------------
-- M18 (B59) blocking. A user blocks for themselves, once per target at a time; an
-- unblock is final (blocking again is a new entry).
-- -----------------------------------------------------------------------------
ALTER TABLE block_entry ADD CONSTRAINT ck_block_entry_self_blocked CHECK (blocker_user_account_id = created_by);
CREATE UNIQUE INDEX uq_block_entry_blocker_blocked_user_live ON block_entry (blocker_user_account_id, blocked_user_account_id)
    WHERE unblocked_at IS NULL AND blocked_user_account_id IS NOT NULL;
CREATE UNIQUE INDEX uq_block_entry_blocker_blocked_organisation_live ON block_entry (blocker_user_account_id, blocked_organisation_id)
    WHERE unblocked_at IS NULL AND blocked_organisation_id IS NOT NULL;

CREATE OR REPLACE FUNCTION trg_block_entry_rules() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.blocker_user_account_id <> OLD.blocker_user_account_id
       OR NEW.blocked_user_account_id IS DISTINCT FROM OLD.blocked_user_account_id
       OR NEW.blocked_organisation_id IS DISTINCT FROM OLD.blocked_organisation_id
       OR (OLD.unblocked_at IS NOT NULL AND NEW.unblocked_at IS DISTINCT FROM OLD.unblocked_at) THEN
        RAISE EXCEPTION 'block %: only unblocking a live block is allowed', OLD.id;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_block_entry_rules BEFORE UPDATE ON block_entry FOR EACH ROW EXECUTE FUNCTION trg_block_entry_rules();

-- -----------------------------------------------------------------------------
-- M18 (B59, docket §3) a blocked party cannot see the blocker's candidate.
-- Row-level security for talentra_app on the profile and on the profile content
-- tables (contact details, education, work, skills, resumes). A candidate is visible
-- to: themselves; platform admins; anyone else only if the profile is not hidden,
-- "employers only" profiles only to organisation members and consultants, and never
-- to a user the candidate blocked or to a member of an organisation they blocked.
-- The blocked party cannot read block_entry either, so the block itself stays private.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app_can_see_candidate(p_candidate_profile_id bigint) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    WITH me AS (SELECT app_current_user_id() AS uid),
    my_orgs AS (SELECT m.organisation_id FROM organisation_member m, me
                WHERE m.user_account_id = me.uid AND m.valid_from <= now() AND (m.valid_to IS NULL OR m.valid_to > now()))
    SELECT EXISTS (
        SELECT 1 FROM candidate_profile c, me
        WHERE c.id = p_candidate_profile_id AND c.deleted_at IS NULL
          AND (c.user_account_id = me.uid
               OR app_has_permission('platform.admin')
               OR (c.profile_visibility_id <> 3
                   AND (c.profile_visibility_id = 1
                        OR EXISTS (SELECT 1 FROM my_orgs)
                        OR EXISTS (SELECT 1 FROM user_account_role g WHERE g.user_account_id = me.uid AND g.role_id = 8 AND g.revoked_at IS NULL))
                   AND NOT EXISTS (SELECT 1 FROM block_entry b
                                   WHERE b.blocker_user_account_id = c.user_account_id AND b.unblocked_at IS NULL
                                     AND (b.blocked_user_account_id = me.uid
                                          OR b.blocked_organisation_id IN (SELECT organisation_id FROM my_orgs))))))
$$;
-- The profile table itself uses the same rule written inline: calling the function per row
-- cost a full lookup per profile and timed out a name search over 1M profiles (demo UI,
-- after M20). The viewer-side facts are computed once per query instead:
-- whether the viewer may see "employers only" profiles, and who has blocked the viewer.
CREATE OR REPLACE FUNCTION app_viewer_sees_employers_only() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT EXISTS (SELECT 1 FROM organisation_member m WHERE m.user_account_id = app_current_user_id()
                   AND m.valid_from <= now() AND (m.valid_to IS NULL OR m.valid_to > now()))
        OR EXISTS (SELECT 1 FROM user_account_role g WHERE g.user_account_id = app_current_user_id() AND g.role_id = 8 AND g.revoked_at IS NULL)
$$;
CREATE OR REPLACE FUNCTION app_candidates_blocking_viewer() RETURNS bigint[]
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT coalesce(array_agg(DISTINCT b.blocker_user_account_id), '{}')
    FROM block_entry b
    WHERE b.unblocked_at IS NULL
      AND (b.blocked_user_account_id = app_current_user_id()
           OR b.blocked_organisation_id IN (SELECT m.organisation_id FROM organisation_member m WHERE m.user_account_id = app_current_user_id()
                                            AND m.valid_from <= now() AND (m.valid_to IS NULL OR m.valid_to > now())))
$$;

ALTER TABLE candidate_profile ENABLE ROW LEVEL SECURITY;
CREATE POLICY candidate_profile_owner ON candidate_profile FOR ALL TO talentra_app
    USING (user_account_id = (SELECT app_current_user_id())) WITH CHECK (user_account_id = (SELECT app_current_user_id()));
CREATE POLICY candidate_profile_platform_admin ON candidate_profile FOR ALL TO talentra_app
    USING ((SELECT app_has_permission('platform.admin'))) WITH CHECK ((SELECT app_has_permission('platform.admin')));
CREATE POLICY candidate_profile_visible ON candidate_profile FOR SELECT TO talentra_app
    USING (deleted_at IS NULL AND profile_visibility_id <> 3
           AND (profile_visibility_id = 1 OR (SELECT app_viewer_sees_employers_only()))
           AND user_account_id <> ALL ((SELECT app_candidates_blocking_viewer())::bigint[]));

DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['candidate_email', 'candidate_phone', 'candidate_address', 'candidate_social_link', 'candidate_education',
                             'candidate_work_experience', 'candidate_skill', 'candidate_language', 'candidate_certification',
                             'candidate_preferred_location', 'candidate_preferred_job_role', 'resume'] LOOP
        EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
        EXECUTE format($p$CREATE POLICY %I ON %I FOR ALL TO talentra_app
            USING (candidate_profile_id IN (SELECT id FROM candidate_profile WHERE user_account_id = (SELECT app_current_user_id())))
            WITH CHECK (candidate_profile_id IN (SELECT id FROM candidate_profile WHERE user_account_id = (SELECT app_current_user_id())))$p$,
            t || '_owner', t);
        EXECUTE format($p$CREATE POLICY %I ON %I FOR ALL TO talentra_app
            USING ((SELECT app_has_permission('platform.admin'))) WITH CHECK ((SELECT app_has_permission('platform.admin')))$p$, t || '_platform_admin', t);
        EXECUTE format('CREATE POLICY %I ON %I FOR SELECT TO talentra_app USING (app_can_see_candidate(candidate_profile_id))',
            t || '_visible', t);
    END LOOP;
END $$;
ALTER TABLE resume_version ENABLE ROW LEVEL SECURITY;
CREATE POLICY resume_version_owner ON resume_version FOR ALL TO talentra_app
    USING (resume_id IN (SELECT r.id FROM resume r JOIN candidate_profile c ON c.id = r.candidate_profile_id WHERE c.user_account_id = (SELECT app_current_user_id())))
    WITH CHECK (resume_id IN (SELECT r.id FROM resume r JOIN candidate_profile c ON c.id = r.candidate_profile_id WHERE c.user_account_id = (SELECT app_current_user_id())));
CREATE POLICY resume_version_platform_admin ON resume_version FOR ALL TO talentra_app
    USING ((SELECT app_has_permission('platform.admin'))) WITH CHECK ((SELECT app_has_permission('platform.admin')));
CREATE POLICY resume_version_visible ON resume_version FOR SELECT TO talentra_app
    USING (resume_id IN (SELECT r.id FROM resume r WHERE app_can_see_candidate(r.candidate_profile_id)));

ALTER TABLE block_entry ENABLE ROW LEVEL SECURITY;
CREATE POLICY block_entry_blocker ON block_entry FOR ALL TO talentra_app
    USING (blocker_user_account_id = (SELECT app_current_user_id())) WITH CHECK (blocker_user_account_id = (SELECT app_current_user_id()));
CREATE POLICY block_entry_platform_admin ON block_entry FOR ALL TO talentra_app
    USING ((SELECT app_has_permission('platform.admin'))) WITH CHECK ((SELECT app_has_permission('platform.admin')));

-- Views run with the caller's rights, so row-level security applies through them too.
-- (Before M18 every v_ view ran as its owner and bypassed RLS: a recruiter could read
-- another company's drafts through v_job_requirement.) m18 asserts it for every view.
DO $$
DECLARE r record;
BEGIN
    FOR r IN SELECT c.relname FROM pg_class c JOIN pg_namespace s ON s.oid = c.relnamespace
             WHERE s.nspname = 'public' AND c.relkind = 'v' LOOP
        EXECUTE format('ALTER VIEW %I SET (security_invoker = true)', r.relname);
    END LOOP;
END $$;

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
