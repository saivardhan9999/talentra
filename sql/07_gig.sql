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
CALL create_lookup_table('gig_request_status',     'SYSTEM: 1=draft; open, filled, closed, cancelled');
CALL create_lookup_table('gig_application_status', 'SYSTEM: 1=applied; accepted, rejected, withdrawn');
CALL create_lookup_table('gig_assignment_status',  'reconciled from the fulfilment system: handed_off, in_progress, completed, cancelled, disputed');
CALL create_lookup_table('gig_worker_list_type',   'favourite, blacklist');
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
    CONSTRAINT ck_gig_worker_profile_display_name_not_blank CHECK (btrim(display_name) <> '')
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
    CONSTRAINT ck_gig_request_price_amount CHECK (price_amount > 0)
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
    CONSTRAINT ck_gig_application_decided_after_applied CHECK (decided_at >= applied_at)
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
    CONSTRAINT ck_gig_assignment_date_range CHECK (window_end_at > window_start_at)
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

CALL attach_audit_triggers();
RESET app.current_user_id;
