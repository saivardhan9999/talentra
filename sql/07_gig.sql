-- =============================================================================
-- Talentra :: 07_gig.sql   (Module: Gig marketplace — individual, Phase 2, Member C)
-- Separate subsystem (decision D3): gig worker profiles, service offerings and
-- availability, gig requests with windows and pricing, applications, assignments
-- with the external handoff reference, earnings references from the fulfilment
-- system, favourite/blacklist entries and ratings. Shares master data, identity
-- and organisation with the core; never references job_requirement/application.
-- =============================================================================
SET app.current_user_id = '1';

CALL create_lookup_table('gig_price_type',         'fixed, hourly, daily');
CALL create_lookup_table('gig_request_status',     'SYSTEM: 1=draft, 2=open; filled, closed, cancelled');
CALL create_lookup_table('gig_application_status', 'SYSTEM: 1=applied, 2=accepted, 3=rejected, 4=withdrawn');
CALL create_lookup_table('gig_assignment_status',  'SYSTEM (reconciled from the fulfilment system): 1=handed_off, 2=in_progress, 3=completed, 4=cancelled, 5=disputed');
CALL create_lookup_table('gig_worker_list_type',   'SYSTEM: 1=favourite, 2=blacklist');
CALL create_lookup_table('gig_earning_type',       'estimated, total, projected (as reported by the fulfilment system)');

CALL seed_lookups('gig_price_type', ARRAY['fixed|Fixed price', 'hourly|Hourly rate', 'daily|Daily rate']);
CALL seed_lookups('gig_request_status', ARRAY['draft|Draft', 'open|Open', 'filled|Filled', 'closed|Closed', 'cancelled|Cancelled']);
CALL seed_lookups('gig_application_status', ARRAY['applied|Applied', 'accepted|Accepted', 'rejected|Rejected', 'withdrawn|Withdrawn']);
CALL seed_lookups('gig_assignment_status', ARRAY['handed_off|Handed off', 'in_progress|In progress', 'completed|Completed',
                                                 'cancelled|Cancelled', 'disputed|Disputed']);
CALL seed_lookups('gig_worker_list_type', ARRAY['favourite|Favourite', 'blacklist|Blacklist']);
CALL seed_lookups('gig_earning_type', ARRAY['estimated|Estimated', 'total|Total', 'projected|Projected']);

-- -----------------------------------------------------------------------------
-- Gig worker side
-- -----------------------------------------------------------------------------
CREATE TABLE gig_worker_profile (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_account_id bigint       NOT NULL REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    display_name    varchar(150) NOT NULL,
    headline        varchar(250),
    bio             varchar(2000),
    bio_language_id bigint REFERENCES language (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    base_city_id    bigint REFERENCES city (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    is_available    boolean      NOT NULL DEFAULT true,
    created_at      timestamptz  NOT NULL DEFAULT now(),
    created_by      bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at      timestamptz  NOT NULL DEFAULT now(),
    updated_by      bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    deleted_at      timestamptz,
    CONSTRAINT ck_gig_worker_profile_display_name_not_blank CHECK (btrim(display_name) <> ''),
    -- like candidates (D9): a worker registers themselves, or the system actor migrates them
    CONSTRAINT ck_gig_worker_profile_self_registered CHECK (created_by = user_account_id OR created_by = 1)
);
CREATE UNIQUE INDEX uq_gig_worker_profile_user_account_id ON gig_worker_profile (user_account_id);

CREATE VIEW v_gig_worker_profile AS
    SELECT * FROM gig_worker_profile WHERE deleted_at IS NULL;

-- Service offerings with charge rates.
CREATE TABLE gig_worker_service (
    id                    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    gig_worker_profile_id bigint        NOT NULL REFERENCES gig_worker_profile (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    skill_id              bigint        NOT NULL REFERENCES skill (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    title                 varchar(200)  NOT NULL,
    description           varchar(2000),
    gig_price_type_id     bigint        NOT NULL REFERENCES gig_price_type (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    rate_amount           numeric(14,2) NOT NULL,
    rate_currency_id      bigint        NOT NULL REFERENCES currency (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    is_active             boolean       NOT NULL DEFAULT true,
    created_at            timestamptz   NOT NULL DEFAULT now(),
    created_by            bigint        NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at            timestamptz   NOT NULL DEFAULT now(),
    updated_by            bigint        NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_gig_worker_service_rate_amount CHECK (rate_amount > 0)
);
CREATE INDEX idx_gig_worker_service_gig_worker_profile_id ON gig_worker_service (gig_worker_profile_id);
CREATE INDEX idx_gig_worker_service_skill_id ON gig_worker_service (skill_id, gig_worker_profile_id) WHERE is_active;

CREATE TABLE gig_worker_availability (
    id                    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    gig_worker_profile_id bigint      NOT NULL REFERENCES gig_worker_profile (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    available_from        timestamptz NOT NULL,
    available_to          timestamptz NOT NULL,
    created_at            timestamptz NOT NULL DEFAULT now(),
    created_by            bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at            timestamptz NOT NULL DEFAULT now(),
    updated_by            bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_gig_worker_availability_date_range CHECK (available_to > available_from)
);
CREATE INDEX idx_gig_worker_availability_gig_worker_profile_id ON gig_worker_availability (gig_worker_profile_id, available_from);

-- -----------------------------------------------------------------------------
-- Requester side. A requester is a user, optionally acting for an organisation.
-- -----------------------------------------------------------------------------
CREATE TABLE gig_request (
    id                         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    requester_user_account_id  bigint        NOT NULL REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    requester_organisation_id  bigint REFERENCES organisation (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    title                      varchar(200)  NOT NULL,
    description                varchar(4000) NOT NULL,
    description_language_id    bigint REFERENCES language (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    work_mode_id               bigint        NOT NULL REFERENCES work_mode (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    city_id                    bigint REFERENCES city (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    window_start_at            timestamptz   NOT NULL,
    window_end_at              timestamptz   NOT NULL,
    gig_price_type_id          bigint        NOT NULL REFERENCES gig_price_type (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    price_amount               numeric(14,2) NOT NULL,
    price_currency_id          bigint        NOT NULL REFERENCES currency (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    gig_request_status_id      bigint        NOT NULL DEFAULT 1 REFERENCES gig_request_status (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    created_at                 timestamptz   NOT NULL DEFAULT now(),
    created_by                 bigint        NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at                 timestamptz   NOT NULL DEFAULT now(),
    updated_by                 bigint        NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    deleted_at                 timestamptz,
    CONSTRAINT ck_gig_request_date_range CHECK (window_end_at > window_start_at),
    CONSTRAINT ck_gig_request_price_amount CHECK (price_amount > 0),
    CONSTRAINT ck_gig_request_title_not_blank CHECK (btrim(title) <> ''),
    -- a requester posts their own gigs
    CONSTRAINT ck_gig_request_self_requested CHECK (created_by = requester_user_account_id OR created_by = 1)
);
CREATE INDEX idx_gig_request_requester_user_account_id ON gig_request (requester_user_account_id);
CREATE INDEX idx_gig_request_requester_organisation_id ON gig_request (requester_organisation_id) WHERE requester_organisation_id IS NOT NULL;
CREATE INDEX idx_gig_request_city_id ON gig_request (city_id, window_start_at) WHERE deleted_at IS NULL;

CREATE VIEW v_gig_request AS
    SELECT * FROM gig_request WHERE deleted_at IS NULL;

CREATE TABLE gig_request_skill (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    gig_request_id bigint      NOT NULL REFERENCES gig_request (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    skill_id       bigint      NOT NULL REFERENCES skill (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    created_at     timestamptz NOT NULL DEFAULT now(),
    created_by     bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at     timestamptz NOT NULL DEFAULT now(),
    updated_by     bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_gig_request_skill_gig_request_id_skill_id UNIQUE (gig_request_id, skill_id)
);
CREATE INDEX idx_gig_request_skill_skill_id ON gig_request_skill (skill_id, gig_request_id);

-- -----------------------------------------------------------------------------
-- Application -> assignment. Workers apply; the requester accepts or rejects.
-- -----------------------------------------------------------------------------
CREATE TABLE gig_application (
    id                        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    gig_request_id            bigint       NOT NULL REFERENCES gig_request (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    gig_worker_profile_id     bigint       NOT NULL REFERENCES gig_worker_profile (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    gig_worker_service_id     bigint REFERENCES gig_worker_service (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    cover_note                varchar(2000),
    gig_application_status_id bigint       NOT NULL DEFAULT 1 REFERENCES gig_application_status (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    applied_at                timestamptz  NOT NULL DEFAULT now(),
    decided_at                timestamptz,
    created_at                timestamptz  NOT NULL DEFAULT now(),
    created_by                bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at                timestamptz  NOT NULL DEFAULT now(),
    updated_by                bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_gig_application_gig_request_id_gig_worker_profile_id UNIQUE (gig_request_id, gig_worker_profile_id),
    -- target of gig_assignment's composite FK: the assigned worker is the applicant
    CONSTRAINT uq_gig_application_id_gig_worker_profile_id UNIQUE (id, gig_worker_profile_id),
    CONSTRAINT ck_gig_application_decided_after_applied CHECK (decided_at >= applied_at),
    CONSTRAINT ck_gig_application_decided CHECK ((gig_application_status_id = 1) = (decided_at IS NULL))
);
CREATE INDEX idx_gig_application_gig_worker_profile_id ON gig_application (gig_worker_profile_id, applied_at DESC);

-- Created when an application is accepted. Fulfilment runs in the external system;
-- this row keeps the handoff reference and the status reconciled from it.
-- gig_worker_profile_id and the window are copied so the no-overlap rule for a
-- worker (B35) can be an exclusion constraint on this table.
CREATE TABLE gig_assignment (
    id                       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    gig_application_id       bigint       NOT NULL,
    gig_worker_profile_id    bigint       NOT NULL,
    window_start_at          timestamptz  NOT NULL,
    window_end_at            timestamptz  NOT NULL,
    handoff_ref              varchar(100) NOT NULL,
    gig_assignment_status_id bigint       NOT NULL REFERENCES gig_assignment_status (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    last_reconciled_at       timestamptz,
    completed_at             timestamptz,
    created_at               timestamptz  NOT NULL DEFAULT now(),
    created_by               bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at               timestamptz  NOT NULL DEFAULT now(),
    updated_by               bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_gig_assignment_gig_application FOREIGN KEY (gig_application_id, gig_worker_profile_id)
        REFERENCES gig_application (id, gig_worker_profile_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_gig_assignment_handoff_ref UNIQUE (handoff_ref),
    CONSTRAINT ck_gig_assignment_date_range CHECK (window_end_at > window_start_at),
    CONSTRAINT ck_gig_assignment_completed CHECK ((gig_assignment_status_id = 3) = (completed_at IS NOT NULL)),
    -- B35: a worker's live assignments never overlap in time (cancelled ones do not count)
    CONSTRAINT uq_gig_assignment_no_overlap EXCLUDE USING gist (
        gig_worker_profile_id WITH =, tstzrange(window_start_at, window_end_at) WITH &&) WHERE (gig_assignment_status_id <> 4)
);
CREATE UNIQUE INDEX uq_gig_assignment_gig_application_id ON gig_assignment (gig_application_id);
CREATE INDEX idx_gig_assignment_gig_worker_profile_id ON gig_assignment (gig_worker_profile_id, window_start_at);

-- Earnings are owned by the fulfilment system; each reported figure is stored once
-- (external_event_ref makes redelivery idempotent) and never changed.
CREATE TABLE gig_earning_snapshot (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    gig_assignment_id   bigint        NOT NULL REFERENCES gig_assignment (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    gig_earning_type_id bigint        NOT NULL REFERENCES gig_earning_type (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    earning_amount      numeric(14,2) NOT NULL,
    earning_currency_id bigint        NOT NULL REFERENCES currency (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    external_event_ref  varchar(100)  NOT NULL,
    reported_at         timestamptz   NOT NULL,
    created_at          timestamptz   NOT NULL DEFAULT now(),
    created_by          bigint        NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_gig_earning_snapshot_external_event_ref UNIQUE (external_event_ref)
);
CREATE INDEX idx_gig_earning_snapshot_gig_assignment_id ON gig_earning_snapshot (gig_assignment_id, reported_at);
CALL make_append_only('gig_earning_snapshot');

-- One rating per assignment, given by the requester.
CREATE TABLE gig_rating (
    id                       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    gig_assignment_id        bigint      NOT NULL REFERENCES gig_assignment (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    rated_by_user_account_id bigint      NOT NULL REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    rating_score             smallint    NOT NULL,
    review_text              varchar(2000),
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_gig_rating_rating_score CHECK (rating_score BETWEEN 1 AND 5)
);
CREATE UNIQUE INDEX uq_gig_rating_gig_assignment_id ON gig_rating (gig_assignment_id);

-- Requester favourites and blacklist, with add/remove history (entries are closed, not deleted).
CREATE TABLE gig_worker_list_entry (
    id                      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    owner_user_account_id   bigint      NOT NULL REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    owner_organisation_id   bigint REFERENCES organisation (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    gig_worker_profile_id   bigint      NOT NULL REFERENCES gig_worker_profile (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    gig_worker_list_type_id bigint      NOT NULL REFERENCES gig_worker_list_type (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    reason                  varchar(500),
    added_at                timestamptz NOT NULL DEFAULT now(),
    removed_at              timestamptz,
    created_at              timestamptz NOT NULL DEFAULT now(),
    created_by              bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at              timestamptz NOT NULL DEFAULT now(),
    updated_by              bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_gig_worker_list_entry_date_range CHECK (removed_at >= added_at)
);
CREATE INDEX idx_gig_worker_list_entry_owner_user_account_id ON gig_worker_list_entry (owner_user_account_id, gig_worker_list_type_id);
CREATE INDEX idx_gig_worker_list_entry_gig_worker_profile_id ON gig_worker_list_entry (gig_worker_profile_id);
-- A worker is on at most one live list per owner (cannot be favourite and blacklisted at once).
CREATE UNIQUE INDEX uq_gig_worker_list_entry_owner_worker ON gig_worker_list_entry (owner_user_account_id, gig_worker_profile_id) WHERE removed_at IS NULL;
CREATE TRIGGER trg_gig_worker_list_entry_no_delete BEFORE DELETE ON gig_worker_list_entry
    FOR EACH ROW EXECUTE FUNCTION trg_forbid_modification();

-- -----------------------------------------------------------------------------
-- Workflow rules that span rows (M10). The actor is app.current_user_id; system
-- actor 1 (migration, reconciliation jobs) may act for anyone.
-- -----------------------------------------------------------------------------
-- A requester may post for an organisation only while mapped to it.
CREATE OR REPLACE FUNCTION trg_gig_request_rules() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.requester_organisation_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM organisation_member m
        WHERE m.organisation_id = NEW.requester_organisation_id AND m.user_account_id = NEW.requester_user_account_id
          AND m.valid_from <= now() AND (m.valid_to IS NULL OR m.valid_to > now()))
    THEN
        RAISE EXCEPTION 'user % is not a current member of organisation %', NEW.requester_user_account_id, NEW.requester_organisation_id
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_gig_request_rules BEFORE INSERT OR UPDATE OF requester_user_account_id, requester_organisation_id ON gig_request
    FOR EACH ROW EXECUTE FUNCTION trg_gig_request_rules();

-- Workers apply, requesters decide (bids do not flow both ways, docket §2).
CREATE OR REPLACE FUNCTION trg_gig_application_rules() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_req         gig_request%ROWTYPE;
    v_worker_user bigint;
    v_actor       bigint := app_current_user_id();
BEGIN
    SELECT * INTO v_req FROM gig_request WHERE id = NEW.gig_request_id;
    SELECT user_account_id INTO v_worker_user FROM gig_worker_profile WHERE id = NEW.gig_worker_profile_id;
    IF TG_OP = 'INSERT' THEN
        IF v_actor NOT IN (v_worker_user, 1) THEN
            RAISE EXCEPTION 'only the gig worker can apply (bids do not flow both ways)' USING ERRCODE = 'insufficient_privilege';
        END IF;
        IF NEW.gig_application_status_id <> 1 THEN
            RAISE EXCEPTION 'a gig application starts as applied' USING ERRCODE = 'check_violation';
        END IF;
        IF v_req.gig_request_status_id <> 2 THEN
            RAISE EXCEPTION 'gig request % is not open', NEW.gig_request_id USING ERRCODE = 'check_violation';
        END IF;
        IF v_worker_user = v_req.requester_user_account_id THEN
            RAISE EXCEPTION 'a requester cannot apply to their own gig request' USING ERRCODE = 'check_violation';
        END IF;
        IF EXISTS (SELECT 1 FROM gig_worker_list_entry e
                   WHERE e.gig_worker_profile_id = NEW.gig_worker_profile_id AND e.gig_worker_list_type_id = 2 AND e.removed_at IS NULL
                     AND (e.owner_user_account_id = v_req.requester_user_account_id OR e.owner_organisation_id = v_req.requester_organisation_id))
        THEN
            RAISE EXCEPTION 'gig worker % is blacklisted by this requester', NEW.gig_worker_profile_id USING ERRCODE = 'check_violation';
        END IF;
    ELSIF NEW.gig_application_status_id IS DISTINCT FROM OLD.gig_application_status_id THEN
        IF OLD.gig_application_status_id <> 1 THEN
            RAISE EXCEPTION 'gig application % is already decided', OLD.id USING ERRCODE = 'check_violation';
        END IF;
        IF NEW.gig_application_status_id IN (2, 3) AND v_actor NOT IN (v_req.requester_user_account_id, 1) THEN
            RAISE EXCEPTION 'only the requester can accept or reject an application' USING ERRCODE = 'insufficient_privilege';
        END IF;
        IF NEW.gig_application_status_id = 4 AND v_actor NOT IN (v_worker_user, 1) THEN
            RAISE EXCEPTION 'only the gig worker can withdraw an application' USING ERRCODE = 'insufficient_privilege';
        END IF;
        NEW.decided_at := now();
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_gig_application_rules BEFORE INSERT OR UPDATE ON gig_application
    FOR EACH ROW EXECUTE FUNCTION trg_gig_application_rules();

-- An assignment exists only for an accepted application and always carries the
-- request's window (the copy that the no-overlap exclusion reads).
CREATE OR REPLACE FUNCTION trg_gig_assignment_rules() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE v_status bigint;
BEGIN
    SELECT a.gig_application_status_id, r.window_start_at, r.window_end_at
    INTO v_status, NEW.window_start_at, NEW.window_end_at
    FROM gig_application a JOIN gig_request r ON r.id = a.gig_request_id
    WHERE a.id = NEW.gig_application_id;
    IF TG_OP = 'INSERT' AND v_status IS DISTINCT FROM 2 THEN
        RAISE EXCEPTION 'gig application % is not accepted', NEW.gig_application_id USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_gig_assignment_rules BEFORE INSERT OR UPDATE ON gig_assignment
    FOR EACH ROW EXECUTE FUNCTION trg_gig_assignment_rules();

-- Only the requester rates, and only a completed gig.
CREATE OR REPLACE FUNCTION trg_gig_rating_rules() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE v_requester bigint; v_status bigint;
BEGIN
    SELECT r.requester_user_account_id, s.gig_assignment_status_id INTO v_requester, v_status
    FROM gig_assignment s JOIN gig_application a ON a.id = s.gig_application_id JOIN gig_request r ON r.id = a.gig_request_id
    WHERE s.id = NEW.gig_assignment_id;
    IF NEW.rated_by_user_account_id <> v_requester OR app_current_user_id() NOT IN (v_requester, 1) THEN
        RAISE EXCEPTION 'only the requester can rate gig assignment %', NEW.gig_assignment_id USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF v_status <> 3 THEN
        RAISE EXCEPTION 'gig assignment % is not completed', NEW.gig_assignment_id USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_gig_rating_rules BEFORE INSERT OR UPDATE ON gig_rating
    FOR EACH ROW EXECUTE FUNCTION trg_gig_rating_rules();

-- -----------------------------------------------------------------------------
-- Gig projects on the profile (hand-off promised in Phase 1): a project belongs
-- to exactly one of a candidate profile or a gig worker profile.
-- -----------------------------------------------------------------------------
ALTER TABLE profile_project
    ALTER COLUMN candidate_profile_id DROP NOT NULL,
    ADD COLUMN gig_worker_profile_id bigint REFERENCES gig_worker_profile (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    ADD CONSTRAINT ck_profile_project_one_owner CHECK (num_nonnulls(candidate_profile_id, gig_worker_profile_id) = 1);
CREATE INDEX idx_profile_project_gig_worker_profile_id ON profile_project (gig_worker_profile_id) WHERE gig_worker_profile_id IS NOT NULL;

-- -----------------------------------------------------------------------------
-- Classification and nullability justification (rule groups 5, 6)
-- -----------------------------------------------------------------------------
COMMENT ON COLUMN gig_worker_profile.display_name    IS 'class=Personal; name shown to requesters, any script';
COMMENT ON COLUMN gig_worker_profile.headline        IS 'class=Public; null=not written yet';
COMMENT ON COLUMN gig_worker_profile.bio             IS 'class=Public; null=not written yet';
COMMENT ON COLUMN gig_worker_profile.bio_language_id IS 'class=Internal; null=bio absent or language not detected';
COMMENT ON COLUMN gig_worker_profile.base_city_id    IS 'class=Personal; null=remote-only worker or not stated';
COMMENT ON COLUMN gig_worker_profile.deleted_at      IS 'class=Internal; null=active (soft delete)';
COMMENT ON COLUMN gig_worker_service.description     IS 'class=Public; null=title is self-explanatory';
COMMENT ON COLUMN gig_worker_service.rate_amount     IS 'class=Public; charge rate per gig_price_type';
COMMENT ON COLUMN gig_request.requester_organisation_id IS 'class=Internal; null=individual requester, not acting for an organisation';
COMMENT ON COLUMN gig_request.description_language_id IS 'class=Internal; null=language not detected';
COMMENT ON COLUMN gig_request.city_id                IS 'class=Public; null=remote gig (work_mode remote)';
COMMENT ON COLUMN gig_request.deleted_at             IS 'class=Internal; null=active (soft delete)';
COMMENT ON COLUMN gig_application.gig_worker_service_id IS 'class=Internal; null=applied without choosing one of the worker''s listed services';
COMMENT ON COLUMN gig_application.cover_note         IS 'class=Personal; null=no note written';
COMMENT ON COLUMN gig_application.decided_at         IS 'class=Internal; null=requester has not decided yet';
COMMENT ON COLUMN gig_assignment.handoff_ref         IS 'class=Internal; id of the job in the external fulfilment system';
COMMENT ON COLUMN gig_assignment.last_reconciled_at  IS 'class=Internal; null=not reconciled since handoff';
COMMENT ON COLUMN gig_assignment.completed_at        IS 'class=Internal; null=not completed (per fulfilment system)';
COMMENT ON COLUMN gig_earning_snapshot.earning_amount IS 'class=Personal; figure as reported by the fulfilment system';
COMMENT ON COLUMN gig_earning_snapshot.external_event_ref IS 'class=Internal; idempotency key from the fulfilment system';
COMMENT ON COLUMN gig_rating.review_text             IS 'class=Public; null=score given without a review';
COMMENT ON COLUMN gig_worker_list_entry.owner_organisation_id IS 'class=Internal; null=list kept by an individual requester';
COMMENT ON COLUMN gig_worker_list_entry.reason       IS 'class=Internal; null=no reason recorded';
COMMENT ON COLUMN gig_worker_list_entry.removed_at   IS 'class=Internal; null=entry is current';
COMMENT ON COLUMN profile_project.candidate_profile_id IS 'class=Internal; null=gig project (gig_worker_profile_id set; CHECK exactly one owner)';
COMMENT ON COLUMN profile_project.gig_worker_profile_id IS 'class=Internal; null=candidate project (candidate_profile_id set; CHECK exactly one owner)';

COMMENT ON COLUMN gig_worker_service.title          IS 'class=Public';
COMMENT ON COLUMN gig_worker_availability.available_from IS 'class=Personal; worker availability reveals their schedule';
COMMENT ON COLUMN gig_worker_availability.available_to   IS 'class=Personal';
COMMENT ON COLUMN gig_request.title                 IS 'class=Public';
COMMENT ON COLUMN gig_request.description           IS 'class=Public; stored once in the language entered';
COMMENT ON COLUMN gig_request.window_start_at       IS 'class=Public';
COMMENT ON COLUMN gig_request.window_end_at         IS 'class=Public';
COMMENT ON COLUMN gig_request.price_amount          IS 'class=Public; fixed price or rate per gig_price_type';
COMMENT ON COLUMN gig_application.applied_at        IS 'class=Internal';
COMMENT ON COLUMN gig_assignment.window_start_at    IS 'class=Internal; copied from the request by trigger';
COMMENT ON COLUMN gig_assignment.window_end_at      IS 'class=Internal; copied from the request by trigger';
COMMENT ON COLUMN gig_earning_snapshot.reported_at  IS 'class=Internal; as-of time in the fulfilment system';
COMMENT ON COLUMN gig_rating.rating_score           IS 'class=Public; 1..5';
COMMENT ON COLUMN gig_worker_list_entry.added_at    IS 'class=Internal';
CALL attach_audit_triggers();
RESET app.current_user_id;
