-- =============================================================================
-- Talentra :: 03_jobs_applications.sql   (Module: Jobs and Applications — common, Phase 1)
-- Job requirements, locations, skills, qualifications, positions,
-- questionnaires, applications + enforced status pipeline, interviews,
-- offers, placements (joins), saved jobs, job search history, talent lists
-- (shortlist/bookmark history) and referrals.
-- Gig requests are NOT here: see the gig decision in docs/phase1-design.md (D3).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- job_requirement. Soft-deleted.
-- -----------------------------------------------------------------------------
CREATE TABLE job_requirement (
    id                          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organisation_id             bigint       NOT NULL REFERENCES organisation (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    client_organisation_id      bigint REFERENCES organisation (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    posted_by_user_account_id   bigint       NOT NULL REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    requirement_code            varchar(50),
    title                       varchar(200) NOT NULL,
    description                 text         NOT NULL,
    description_language_id     bigint REFERENCES language (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    job_category_id             bigint       NOT NULL REFERENCES job_category (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    employment_type_id          bigint       NOT NULL REFERENCES employment_type (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    work_mode_id                bigint       NOT NULL REFERENCES work_mode (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    job_role_id                 bigint REFERENCES job_role (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    industry_id                 bigint REFERENCES industry (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    number_of_positions         integer      NOT NULL DEFAULT 1,
    min_experience_months       integer      NOT NULL DEFAULT 0,
    max_experience_months       integer,
    salary_disclosure_status_id bigint       NOT NULL DEFAULT 2 REFERENCES salary_disclosure_status (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    salary_min_amount           numeric(14,2),
    salary_max_amount           numeric(14,2),
    salary_currency_id          bigint REFERENCES currency (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    salary_period_id            bigint REFERENCES salary_period (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    job_requirement_status_id   bigint       NOT NULL REFERENCES job_requirement_status (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    publish_state_id            bigint       NOT NULL REFERENCES publish_state (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    published_at                timestamptz,
    expires_at                  timestamptz,
    application_deadline        date,
    is_open_to_consultants      boolean      NOT NULL DEFAULT false,
    consultant_fee_pct          numeric(5,2),
    legacy_source_system_id     bigint REFERENCES legacy_source_system (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    legacy_record_ref           varchar(100),
    search_document             tsvector GENERATED ALWAYS AS (
                                    setweight(to_tsvector('simple'::regconfig, title), 'A') ||
                                    setweight(to_tsvector('simple'::regconfig, left(description, 20000)), 'B')) STORED,
    created_at                  timestamptz  NOT NULL DEFAULT now(),
    created_by                  bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at                  timestamptz  NOT NULL DEFAULT now(),
    updated_by                  bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    deleted_at                  timestamptz,
    CONSTRAINT uq_job_requirement_id_organisation_id UNIQUE (id, organisation_id),
    CONSTRAINT ck_job_requirement_not_gig CHECK (job_category_id <> 1),
    CONSTRAINT ck_job_requirement_client_differs CHECK (client_organisation_id <> organisation_id),
    CONSTRAINT ck_job_requirement_title_not_blank CHECK (btrim(title) <> ''),
    CONSTRAINT ck_job_requirement_description_length CHECK (length(description) BETWEEN 1 AND 50000),
    CONSTRAINT ck_job_requirement_number_of_positions CHECK (number_of_positions BETWEEN 1 AND 10000),
    CONSTRAINT ck_job_requirement_experience_range CHECK (
        min_experience_months >= 0 AND (max_experience_months IS NULL OR max_experience_months >= min_experience_months)),
    CONSTRAINT ck_job_requirement_salary CHECK (
        CASE WHEN salary_disclosure_status_id = 1
             THEN salary_min_amount >= 0 AND salary_max_amount >= salary_min_amount
                  AND salary_currency_id IS NOT NULL AND salary_period_id IS NOT NULL
             ELSE salary_min_amount IS NULL AND salary_max_amount IS NULL
                  AND salary_currency_id IS NULL AND salary_period_id IS NULL END),
    CONSTRAINT ck_job_requirement_publish_window CHECK (expires_at > published_at),
    CONSTRAINT ck_job_requirement_expiry_needs_publish CHECK (expires_at IS NULL OR published_at IS NOT NULL),
    CONSTRAINT ck_job_requirement_consultant_fee CHECK (
        consultant_fee_pct IS NULL OR (is_open_to_consultants AND consultant_fee_pct > 0 AND consultant_fee_pct <= 100)),
    CONSTRAINT ck_job_requirement_legacy_ref_pair CHECK ((legacy_source_system_id IS NULL) = (legacy_record_ref IS NULL))
);
CREATE UNIQUE INDEX uq_job_requirement_organisation_id_requirement_code
    ON job_requirement (organisation_id, requirement_code) WHERE requirement_code IS NOT NULL;
CREATE UNIQUE INDEX uq_job_requirement_legacy_source_system_id_legacy_record_ref
    ON job_requirement (legacy_source_system_id, legacy_record_ref) WHERE legacy_record_ref IS NOT NULL;
CREATE INDEX idx_job_requirement_organisation_id_status ON job_requirement (organisation_id, job_requirement_status_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_job_requirement_client_organisation_id ON job_requirement (client_organisation_id) WHERE client_organisation_id IS NOT NULL;
CREATE INDEX idx_job_requirement_published_at ON job_requirement (published_at DESC) WHERE deleted_at IS NULL AND published_at IS NOT NULL;
CREATE INDEX idx_job_requirement_job_role_id ON job_requirement (job_role_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_job_requirement_consultant_open ON job_requirement (organisation_id) WHERE is_open_to_consultants AND deleted_at IS NULL;
CREATE INDEX idx_job_requirement_search_document ON job_requirement USING gin (search_document);
CREATE INDEX idx_job_requirement_title_trgm ON job_requirement USING gin (title gin_trgm_ops);

CREATE VIEW v_job_requirement AS
    SELECT * FROM job_requirement WHERE deleted_at IS NULL;

ALTER TABLE profile_view_event ADD CONSTRAINT profile_view_event_job_requirement_id_fkey
    FOREIGN KEY (job_requirement_id) REFERENCES job_requirement (id) ON UPDATE RESTRICT ON DELETE RESTRICT;

-- -----------------------------------------------------------------------------
-- Requirement details
-- -----------------------------------------------------------------------------
CREATE TABLE job_requirement_location (
    id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_requirement_id   bigint      NOT NULL REFERENCES job_requirement (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    city_id              bigint      NOT NULL REFERENCES city (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    positions_at_location integer,
    created_at           timestamptz NOT NULL DEFAULT now(),
    created_by           bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at           timestamptz NOT NULL DEFAULT now(),
    updated_by           bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_job_requirement_location_job_requirement_id_city_id UNIQUE (job_requirement_id, city_id),
    CONSTRAINT ck_job_requirement_location_positions CHECK (positions_at_location > 0)
);
-- Job search by city: city -> jobs.
CREATE INDEX idx_job_requirement_location_city_id ON job_requirement_location (city_id, job_requirement_id);

CREATE TABLE job_requirement_skill (
    id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_requirement_id   bigint      NOT NULL REFERENCES job_requirement (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    skill_id             bigint      NOT NULL REFERENCES skill (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    is_mandatory         boolean     NOT NULL DEFAULT true,
    min_experience_months integer,
    proficiency_level_id bigint REFERENCES proficiency_level (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    created_at           timestamptz NOT NULL DEFAULT now(),
    created_by           bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at           timestamptz NOT NULL DEFAULT now(),
    updated_by           bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_job_requirement_skill_job_requirement_id_skill_id UNIQUE (job_requirement_id, skill_id),
    CONSTRAINT ck_job_requirement_skill_min_experience_months CHECK (min_experience_months BETWEEN 0 AND 840)
);
CREATE INDEX idx_job_requirement_skill_skill_id ON job_requirement_skill (skill_id, job_requirement_id);

CREATE TABLE job_requirement_qualification (
    id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_requirement_id bigint      NOT NULL REFERENCES job_requirement (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    qualification_id   bigint      NOT NULL REFERENCES qualification (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    field_of_study_id  bigint REFERENCES field_of_study (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    is_mandatory       boolean     NOT NULL DEFAULT true,
    created_at         timestamptz NOT NULL DEFAULT now(),
    created_by         bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at         timestamptz NOT NULL DEFAULT now(),
    updated_by         bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_job_requirement_qualification_req_qual_field UNIQUE NULLS NOT DISTINCT (job_requirement_id, qualification_id, field_of_study_id)
);

-- One row per headcount slot; a placement fills exactly one slot.
CREATE TABLE job_position (
    id                     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_requirement_id     bigint      NOT NULL REFERENCES job_requirement (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    position_number        integer     NOT NULL,
    city_id                bigint REFERENCES city (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    job_position_status_id bigint      NOT NULL REFERENCES job_position_status (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    created_at             timestamptz NOT NULL DEFAULT now(),
    created_by             bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at             timestamptz NOT NULL DEFAULT now(),
    updated_by             bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_job_position_job_requirement_id_position_number UNIQUE (job_requirement_id, position_number),
    CONSTRAINT uq_job_position_id_job_requirement_id UNIQUE (id, job_requirement_id),
    CONSTRAINT ck_job_position_position_number CHECK (position_number > 0)
);

-- -----------------------------------------------------------------------------
-- Questionnaires (reusable per organisation, attached to requirements)
-- -----------------------------------------------------------------------------
CREATE TABLE questionnaire (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organisation_id bigint       NOT NULL REFERENCES organisation (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    title           varchar(200) NOT NULL,
    language_id     bigint       NOT NULL REFERENCES language (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    is_active       boolean      NOT NULL DEFAULT true,
    created_at      timestamptz  NOT NULL DEFAULT now(),
    created_by      bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at      timestamptz  NOT NULL DEFAULT now(),
    updated_by      bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    deleted_at      timestamptz
);
CREATE INDEX idx_questionnaire_organisation_id ON questionnaire (organisation_id);

CREATE TABLE questionnaire_question (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    questionnaire_id bigint        NOT NULL REFERENCES questionnaire (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    question_order   integer       NOT NULL,
    question_text    varchar(1000) NOT NULL,
    question_type_id bigint        NOT NULL REFERENCES question_type (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    is_mandatory     boolean       NOT NULL DEFAULT true,
    is_knockout      boolean       NOT NULL DEFAULT false,
    min_number_value numeric(14,2),
    max_number_value numeric(14,2),
    created_at       timestamptz   NOT NULL DEFAULT now(),
    created_by       bigint        NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at       timestamptz   NOT NULL DEFAULT now(),
    updated_by       bigint        NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_questionnaire_question_questionnaire_id_question_order UNIQUE (questionnaire_id, question_order),
    CONSTRAINT ck_questionnaire_question_number_range CHECK (max_number_value >= min_number_value)
);

CREATE TABLE questionnaire_question_option (
    id                        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    questionnaire_question_id bigint       NOT NULL REFERENCES questionnaire_question (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    option_order              integer      NOT NULL,
    option_text               varchar(500) NOT NULL,
    is_knockout_pass          boolean      NOT NULL DEFAULT true,
    created_at                timestamptz  NOT NULL DEFAULT now(),
    created_by                bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at                timestamptz  NOT NULL DEFAULT now(),
    updated_by                bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_questionnaire_question_option_question_order UNIQUE (questionnaire_question_id, option_order)
);

CREATE TABLE job_requirement_questionnaire (
    id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_requirement_id bigint      NOT NULL REFERENCES job_requirement (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    questionnaire_id   bigint      NOT NULL REFERENCES questionnaire (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    sort_order         integer     NOT NULL DEFAULT 0,
    created_at         timestamptz NOT NULL DEFAULT now(),
    created_by         bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at         timestamptz NOT NULL DEFAULT now(),
    updated_by         bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_job_requirement_questionnaire_req_questionnaire UNIQUE (job_requirement_id, questionnaire_id)
);

-- -----------------------------------------------------------------------------
-- Applications and pipeline
-- -----------------------------------------------------------------------------
-- Allowed pipeline moves; the trigger below rejects anything not listed.
CREATE TABLE application_status_transition (
    id                    bigint GENERATED BY DEFAULT AS IDENTITY (START WITH 1000) PRIMARY KEY,
    from_application_status_id bigint  NOT NULL REFERENCES application_status (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    to_application_status_id   bigint  NOT NULL REFERENCES application_status (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    created_at            timestamptz NOT NULL DEFAULT now(),
    created_by            bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at            timestamptz NOT NULL DEFAULT now(),
    updated_by            bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_application_status_transition_from_to UNIQUE (from_application_status_id, to_application_status_id),
    CONSTRAINT ck_application_status_transition_not_self CHECK (from_application_status_id <> to_application_status_id)
);

CREATE TABLE application (
    id                          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_requirement_id          bigint        NOT NULL REFERENCES job_requirement (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    candidate_profile_id        bigint        NOT NULL REFERENCES candidate_profile (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    application_status_id       bigint        NOT NULL REFERENCES application_status (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    status_changed_at           timestamptz   NOT NULL DEFAULT now(),
    application_source_id       bigint        NOT NULL REFERENCES application_source (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    applied_at                  timestamptz   NOT NULL DEFAULT now(),
    resume_version_id           bigint REFERENCES resume_version (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    cover_note                  varchar(4000),
    sourced_by_user_account_id  bigint REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    rejection_reason_id         bigint REFERENCES rejection_reason (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    status_note                 varchar(1000),
    legacy_source_system_id     bigint REFERENCES legacy_source_system (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    legacy_record_ref           varchar(100),
    created_at                  timestamptz   NOT NULL DEFAULT now(),
    created_by                  bigint        NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at                  timestamptz   NOT NULL DEFAULT now(),
    updated_by                  bigint        NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_application_job_requirement_id_candidate_profile_id UNIQUE (job_requirement_id, candidate_profile_id),
    CONSTRAINT uq_application_id_job_requirement_id UNIQUE (id, job_requirement_id),
    CONSTRAINT ck_application_status_after_apply CHECK (status_changed_at >= applied_at),
    CONSTRAINT ck_application_legacy_ref_pair CHECK ((legacy_source_system_id IS NULL) = (legacy_record_ref IS NULL))
);
CREATE INDEX idx_application_candidate_profile_id ON application (candidate_profile_id, applied_at DESC);
CREATE INDEX idx_application_job_requirement_id_status ON application (job_requirement_id, application_status_id, status_changed_at DESC);
CREATE INDEX idx_application_sourced_by_user_account_id ON application (sourced_by_user_account_id) WHERE sourced_by_user_account_id IS NOT NULL;
CREATE UNIQUE INDEX uq_application_legacy_source_system_id_legacy_record_ref
    ON application (legacy_source_system_id, legacy_record_ref) WHERE legacy_record_ref IS NOT NULL;

-- Append-only pipeline history; written ONLY by trigger, so it cannot be skipped.
CREATE TABLE application_status_history (
    id                         bigint GENERATED ALWAYS AS IDENTITY,
    application_id             bigint      NOT NULL REFERENCES application (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    from_application_status_id bigint REFERENCES application_status (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    to_application_status_id   bigint      NOT NULL REFERENCES application_status (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    rejection_reason_id        bigint REFERENCES rejection_reason (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    status_note                varchar(1000),
    changed_at                 timestamptz NOT NULL DEFAULT now(),
    created_at                 timestamptz NOT NULL DEFAULT now(),
    created_by                 bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT pk_application_status_history PRIMARY KEY (id, changed_at)
) PARTITION BY RANGE (changed_at);
CREATE INDEX idx_application_status_history_application_id ON application_status_history (application_id, changed_at);
CALL create_monthly_partitions('application_status_history', DATE '2025-01-01', DATE '2027-01-01');
CALL make_append_only('application_status_history');

CREATE OR REPLACE FUNCTION trg_application_status_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NOT EXISTS (SELECT 1 FROM application_status s WHERE s.id = NEW.application_status_id AND s.is_initial) THEN
            RAISE EXCEPTION 'application must start in an initial status (got %)', NEW.application_status_id
                USING ERRCODE = 'check_violation';
        END IF;
        NEW.status_changed_at := NEW.applied_at;
    ELSIF NEW.application_status_id IS DISTINCT FROM OLD.application_status_id THEN
        IF NOT EXISTS (SELECT 1 FROM application_status_transition t
                       WHERE t.from_application_status_id = OLD.application_status_id
                         AND t.to_application_status_id = NEW.application_status_id) THEN
            RAISE EXCEPTION 'application status transition % -> % is not allowed',
                OLD.application_status_id, NEW.application_status_id USING ERRCODE = 'check_violation';
        END IF;
        NEW.status_changed_at := now();
    END IF;
    RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION trg_application_status_history() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' OR NEW.application_status_id IS DISTINCT FROM OLD.application_status_id THEN
        INSERT INTO application_status_history
            (application_id, from_application_status_id, to_application_status_id,
             rejection_reason_id, status_note, changed_at, created_by)
        VALUES
            (NEW.id, CASE WHEN TG_OP = 'UPDATE' THEN OLD.application_status_id END, NEW.application_status_id,
             NEW.rejection_reason_id, NEW.status_note, NEW.status_changed_at,
             CASE WHEN TG_OP = 'INSERT' THEN NEW.created_by ELSE NEW.updated_by END);
    END IF;
    RETURN NULL;
END $$;

CREATE TRIGGER trg_application_status_guard BEFORE INSERT OR UPDATE OF application_status_id ON application
    FOR EACH ROW EXECUTE FUNCTION trg_application_status_guard();
CREATE TRIGGER trg_application_status_history AFTER INSERT OR UPDATE OF application_status_id ON application
    FOR EACH ROW EXECUTE FUNCTION trg_application_status_history();

CREATE TABLE application_answer (
    id                               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    application_id                   bigint        NOT NULL REFERENCES application (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    questionnaire_question_id        bigint        NOT NULL REFERENCES questionnaire_question (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    questionnaire_question_option_id bigint REFERENCES questionnaire_question_option (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    answer_text                      varchar(2000),
    answer_number                    numeric(14,2),
    created_at                       timestamptz   NOT NULL DEFAULT now(),
    created_by                       bigint        NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at                       timestamptz   NOT NULL DEFAULT now(),
    updated_by                       bigint        NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_application_answer_app_question_option UNIQUE NULLS NOT DISTINCT (application_id, questionnaire_question_id, questionnaire_question_option_id),
    CONSTRAINT ck_application_answer_one_value CHECK (num_nonnulls(questionnaire_question_option_id, answer_text, answer_number) = 1)
);

CREATE TABLE interview (
    id                        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    application_id            bigint       NOT NULL REFERENCES application (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    round_number              integer      NOT NULL,
    interview_round_type_id   bigint       NOT NULL REFERENCES interview_round_type (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    interview_mode_id         bigint       NOT NULL REFERENCES interview_mode (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    scheduled_start_at        timestamptz  NOT NULL,
    scheduled_end_at          timestamptz  NOT NULL,
    display_time_zone         varchar(64)  NOT NULL,   -- IANA zone for display, e.g. Asia/Kolkata
    interviewer_user_account_id bigint REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    venue_or_meeting_link     varchar(500),
    interview_outcome_id      bigint REFERENCES interview_outcome (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    rating                    numeric(3,1),
    feedback                  varchar(4000),
    created_at                timestamptz  NOT NULL DEFAULT now(),
    created_by                bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at                timestamptz  NOT NULL DEFAULT now(),
    updated_by                bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_interview_application_id_round_number UNIQUE (application_id, round_number),
    CONSTRAINT ck_interview_round_number CHECK (round_number > 0),
    CONSTRAINT ck_interview_time_range CHECK (scheduled_end_at > scheduled_start_at),
    CONSTRAINT ck_interview_rating CHECK (rating BETWEEN 0 AND 5),
    CONSTRAINT ck_interview_rating_needs_outcome CHECK (rating IS NULL OR interview_outcome_id IS NOT NULL)
);
CREATE INDEX idx_interview_interviewer_user_account_id ON interview (interviewer_user_account_id, scheduled_start_at);

CREATE TABLE offer (
    id                     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    application_id         bigint        NOT NULL REFERENCES application (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    offer_status_id        bigint        NOT NULL REFERENCES offer_status (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    offered_at             timestamptz   NOT NULL DEFAULT now(),
    salary_amount          numeric(14,2) NOT NULL,
    salary_currency_id     bigint        NOT NULL REFERENCES currency (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    salary_period_id       bigint        NOT NULL REFERENCES salary_period (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    proposed_joining_date  date          NOT NULL,
    valid_until            date          NOT NULL,
    responded_at           timestamptz,
    created_at             timestamptz   NOT NULL DEFAULT now(),
    created_by             bigint        NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at             timestamptz   NOT NULL DEFAULT now(),
    updated_by             bigint        NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_offer_salary_amount CHECK (salary_amount >= 0),
    CONSTRAINT ck_offer_valid_until CHECK (valid_until >= offered_at::date),
    CONSTRAINT ck_offer_responded_at CHECK (responded_at >= offered_at)
);
CREATE INDEX idx_offer_application_id ON offer (application_id);

-- "Joined": the hire. Composite FKs guarantee the slot and the application belong to the same requirement.
CREATE TABLE placement (
    id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    application_id     bigint      NOT NULL,
    job_position_id    bigint      NOT NULL,
    job_requirement_id bigint      NOT NULL,
    offer_id           bigint      NOT NULL REFERENCES offer (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    joined_on          date        NOT NULL,
    employee_ref       varchar(50),
    created_at         timestamptz NOT NULL DEFAULT now(),
    created_by         bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at         timestamptz NOT NULL DEFAULT now(),
    updated_by         bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT placement_application_fkey FOREIGN KEY (application_id, job_requirement_id)
        REFERENCES application (id, job_requirement_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT placement_job_position_fkey FOREIGN KEY (job_position_id, job_requirement_id)
        REFERENCES job_position (id, job_requirement_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_placement_application_id UNIQUE (application_id),
    CONSTRAINT uq_placement_job_position_id UNIQUE (job_position_id),
    CONSTRAINT uq_placement_offer_id UNIQUE (offer_id)
);

-- -----------------------------------------------------------------------------
-- Candidate-side history: saved jobs and job search events
-- -----------------------------------------------------------------------------
CREATE TABLE saved_job (
    id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id bigint      NOT NULL REFERENCES candidate_profile (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    job_requirement_id   bigint      NOT NULL REFERENCES job_requirement (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    saved_at             timestamptz NOT NULL DEFAULT now(),
    created_at           timestamptz NOT NULL DEFAULT now(),
    created_by           bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at           timestamptz NOT NULL DEFAULT now(),
    updated_by           bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_saved_job_candidate_profile_id_job_requirement_id UNIQUE (candidate_profile_id, job_requirement_id)
);

CREATE TABLE job_search_event (
    id                   bigint GENERATED ALWAYS AS IDENTITY,
    user_account_id      bigint REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    anonymous_session_ref varchar(64),
    searched_at          timestamptz  NOT NULL DEFAULT now(),
    keyword_text         varchar(500),
    city_id              bigint REFERENCES city (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    filter_criteria      jsonb,
    result_count         integer      NOT NULL,
    created_at           timestamptz  NOT NULL DEFAULT now(),
    created_by           bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT pk_job_search_event PRIMARY KEY (id, searched_at),
    CONSTRAINT ck_job_search_event_actor CHECK (num_nonnulls(user_account_id, anonymous_session_ref) = 1),
    CONSTRAINT ck_job_search_event_result_count CHECK (result_count >= 0),
    CONSTRAINT ck_job_search_event_filter_size CHECK (pg_column_size(filter_criteria) <= 4096)
) PARTITION BY RANGE (searched_at);
CREATE INDEX idx_job_search_event_user_account_id ON job_search_event (user_account_id, searched_at) WHERE user_account_id IS NOT NULL;
CALL create_monthly_partitions('job_search_event', DATE '2025-01-01', DATE '2027-01-01');
CALL make_append_only('job_search_event');

-- -----------------------------------------------------------------------------
-- Employer/recruiter talent lists: shortlists and bookmarks with history
-- (Sourcing, Phase 3, references talent_list for sourcing shortlists)
-- -----------------------------------------------------------------------------
CREATE TABLE talent_list (
    id                    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    owner_user_account_id bigint       NOT NULL REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    organisation_id       bigint REFERENCES organisation (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    talent_list_type_id   bigint       NOT NULL REFERENCES talent_list_type (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    job_requirement_id    bigint,
    name                  varchar(150) NOT NULL,
    created_at            timestamptz  NOT NULL DEFAULT now(),
    created_by            bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at            timestamptz  NOT NULL DEFAULT now(),
    updated_by            bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    deleted_at            timestamptz,
    -- A job-specific list must belong to the job's own organisation (recruiter isolation).
    CONSTRAINT talent_list_job_requirement_fkey FOREIGN KEY (job_requirement_id, organisation_id)
        REFERENCES job_requirement (id, organisation_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_talent_list_job_needs_organisation CHECK (job_requirement_id IS NULL OR organisation_id IS NOT NULL)
);
CREATE INDEX idx_talent_list_owner_user_account_id ON talent_list (owner_user_account_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_talent_list_job_requirement_id ON talent_list (job_requirement_id) WHERE job_requirement_id IS NOT NULL;

-- Entries are never deleted: removal sets removed_at, preserving history.
CREATE TABLE talent_list_entry (
    id                         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    talent_list_id             bigint        NOT NULL REFERENCES talent_list (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    candidate_profile_id       bigint        NOT NULL REFERENCES candidate_profile (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    added_at                   timestamptz   NOT NULL DEFAULT now(),
    added_by_user_account_id   bigint        NOT NULL REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    removed_at                 timestamptz,
    removed_by_user_account_id bigint REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    note                       varchar(1000),
    created_at                 timestamptz   NOT NULL DEFAULT now(),
    created_by                 bigint        NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at                 timestamptz   NOT NULL DEFAULT now(),
    updated_by                 bigint        NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_talent_list_entry_removal CHECK ((removed_at IS NULL) = (removed_by_user_account_id IS NULL)),
    CONSTRAINT ck_talent_list_entry_time_range CHECK (removed_at >= added_at)
);
CREATE UNIQUE INDEX uq_talent_list_entry_active ON talent_list_entry (talent_list_id, candidate_profile_id) WHERE removed_at IS NULL;
CREATE INDEX idx_talent_list_entry_candidate_profile_id ON talent_list_entry (candidate_profile_id);
CREATE TRIGGER trg_talent_list_entry_no_delete BEFORE DELETE ON talent_list_entry
    FOR EACH ROW EXECUTE FUNCTION trg_forbid_modification();

-- -----------------------------------------------------------------------------
-- Referral tracking (referral *events* for notifications are Phase 3)
-- -----------------------------------------------------------------------------
CREATE TABLE referral (
    id                            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    referrer_user_account_id      bigint       NOT NULL REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    referral_code                 varchar(32)  NOT NULL,
    referred_email                varchar(254),
    referred_candidate_profile_id bigint REFERENCES candidate_profile (id) ON UPDATE RESTRICT ON DELETE SET NULL,
    job_requirement_id            bigint REFERENCES job_requirement (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    referral_status_id            bigint       NOT NULL REFERENCES referral_status (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    referred_at                   timestamptz  NOT NULL DEFAULT now(),
    converted_at                  timestamptz,
    created_at                    timestamptz  NOT NULL DEFAULT now(),
    created_by                    bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at                    timestamptz  NOT NULL DEFAULT now(),
    updated_by                    bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_referral_referral_code UNIQUE (referral_code),
    CONSTRAINT ck_referral_target CHECK (referred_email IS NOT NULL OR referred_candidate_profile_id IS NOT NULL),
    CONSTRAINT ck_referral_email_lowercase CHECK (referred_email = lower(referred_email)),
    CONSTRAINT ck_referral_converted_at CHECK (converted_at >= referred_at)
);
CREATE INDEX idx_referral_referrer_user_account_id ON referral (referrer_user_account_id);
CREATE INDEX idx_referral_referred_candidate_profile_id ON referral (referred_candidate_profile_id) WHERE referred_candidate_profile_id IS NOT NULL;

-- -----------------------------------------------------------------------------
-- Classification and nullability justification
-- -----------------------------------------------------------------------------
COMMENT ON COLUMN job_requirement.client_organisation_id IS 'class=Internal; null=direct hire, the poster is the employer (staffing agencies set the client)';
COMMENT ON COLUMN job_requirement.requirement_code   IS 'class=Internal; null=organisation does not use internal requisition codes';
COMMENT ON COLUMN job_requirement.title              IS 'class=Public';
COMMENT ON COLUMN job_requirement.description        IS 'class=Public; unbounded type justified (rich job description), capped at 50k chars by CHECK';
COMMENT ON COLUMN job_requirement.description_language_id IS 'class=Internal; null=language not detected';
COMMENT ON COLUMN job_requirement.job_role_id        IS 'class=Public; null=title not mapped to master role yet';
COMMENT ON COLUMN job_requirement.industry_id        IS 'class=Public; null=inherits organisation industry';
COMMENT ON COLUMN job_requirement.max_experience_months IS 'class=Public; null=no upper limit';
COMMENT ON COLUMN job_requirement.salary_min_amount  IS 'class=Public; null when salary_disclosure_status is not_disclosed/not_applicable (CHECK)';
COMMENT ON COLUMN job_requirement.salary_max_amount  IS 'class=Public; null when salary not disclosed (CHECK)';
COMMENT ON COLUMN job_requirement.salary_currency_id IS 'class=Public; null exactly when amounts are null';
COMMENT ON COLUMN job_requirement.salary_period_id   IS 'class=Public; null exactly when amounts are null';
COMMENT ON COLUMN job_requirement.published_at       IS 'class=Public; null=never published (draft)';
COMMENT ON COLUMN job_requirement.expires_at         IS 'class=Public; null=no expiry set (closes manually)';
COMMENT ON COLUMN job_requirement.application_deadline IS 'class=Public; null=open until filled';
COMMENT ON COLUMN job_requirement.consultant_fee_pct IS 'class=Internal; 0<x<=100; null=not open to consultants or fee negotiated per request';
COMMENT ON COLUMN job_requirement.legacy_source_system_id IS 'class=Internal; null=created natively';
COMMENT ON COLUMN job_requirement.legacy_record_ref  IS 'class=Internal; null=created natively';
COMMENT ON COLUMN job_requirement.deleted_at         IS 'class=Internal; null=active (soft delete)';
COMMENT ON COLUMN job_requirement_location.positions_at_location IS 'class=Public; null=positions not split by location';
COMMENT ON COLUMN job_requirement_skill.min_experience_months IS 'class=Public; null=no minimum';
COMMENT ON COLUMN job_requirement_skill.proficiency_level_id IS 'class=Public; null=any level';
COMMENT ON COLUMN job_requirement_qualification.field_of_study_id IS 'class=Public; null=any specialisation';
COMMENT ON COLUMN job_position.city_id               IS 'class=Public; null=position not tied to a location (remote)';
COMMENT ON COLUMN questionnaire.deleted_at           IS 'class=Internal; null=active (soft delete)';
COMMENT ON COLUMN questionnaire_question.min_number_value IS 'class=Internal; null=not a numeric question or no lower bound';
COMMENT ON COLUMN questionnaire_question.max_number_value IS 'class=Internal; null=not a numeric question or no upper bound';
COMMENT ON COLUMN application.resume_version_id      IS 'class=Personal; null=legacy import or quick-apply without resume';
COMMENT ON COLUMN application.cover_note             IS 'class=Personal; null=no cover note';
COMMENT ON COLUMN application.sourced_by_user_account_id IS 'class=Internal; null=candidate applied directly';
COMMENT ON COLUMN application.rejection_reason_id    IS 'class=Internal; null=not rejected or reason not given';
COMMENT ON COLUMN application.status_note            IS 'class=Internal; null=no note on last status change';
COMMENT ON COLUMN application.legacy_source_system_id IS 'class=Internal; null=created natively';
COMMENT ON COLUMN application.legacy_record_ref      IS 'class=Internal; null=created natively';
COMMENT ON COLUMN application_status_history.from_application_status_id IS 'class=Internal; null=first status (application created)';
COMMENT ON COLUMN application_status_history.rejection_reason_id IS 'class=Internal; null=not a rejection';
COMMENT ON COLUMN application_status_history.status_note IS 'class=Internal; null=no note';
COMMENT ON COLUMN application_answer.questionnaire_question_option_id IS 'class=Personal; null=answer given as text or number instead (exactly one set, CHECK)';
COMMENT ON COLUMN application_answer.answer_text     IS 'class=Personal; null=answer given as option or number instead';
COMMENT ON COLUMN application_answer.answer_number   IS 'class=Personal; null=answer given as option or text instead';
COMMENT ON COLUMN interview.interviewer_user_account_id IS 'class=Internal; null=panel not assigned yet';
COMMENT ON COLUMN interview.venue_or_meeting_link    IS 'class=Internal; null=to be shared later';
COMMENT ON COLUMN interview.interview_outcome_id     IS 'class=Internal; null=interview not yet held (pending)';
COMMENT ON COLUMN interview.rating                   IS 'class=Internal; 0..5; null=not rated';
COMMENT ON COLUMN interview.feedback                 IS 'class=Internal; null=no written feedback';
COMMENT ON COLUMN offer.salary_amount                IS 'class=Personal';
COMMENT ON COLUMN offer.responded_at                 IS 'class=Internal; null=candidate has not responded';
COMMENT ON COLUMN placement.employee_ref             IS 'class=Personal; null=employer has not issued an employee id yet';
COMMENT ON COLUMN job_search_event.user_account_id   IS 'class=Personal; null=guest search (anonymous_session_ref set)';
COMMENT ON COLUMN job_search_event.anonymous_session_ref IS 'class=Internal; null=logged-in search';
COMMENT ON COLUMN job_search_event.keyword_text      IS 'class=Personal; null=filter-only search';
COMMENT ON COLUMN job_search_event.city_id           IS 'class=Internal; null=no location filter';
COMMENT ON COLUMN job_search_event.filter_criteria   IS 'class=Internal; bounded 4 KB; null=no extra filters';
COMMENT ON COLUMN talent_list.organisation_id        IS 'class=Internal; null=freelance consultant list without organisation';
COMMENT ON COLUMN talent_list.job_requirement_id     IS 'class=Internal; null=general pool, not tied to one job';
COMMENT ON COLUMN talent_list.deleted_at             IS 'class=Internal; null=active (soft delete)';
COMMENT ON COLUMN talent_list_entry.removed_at       IS 'class=Internal; null=still on the list';
COMMENT ON COLUMN talent_list_entry.removed_by_user_account_id IS 'class=Internal; null=still on the list';
COMMENT ON COLUMN talent_list_entry.note             IS 'class=Internal; null=no note';
COMMENT ON COLUMN referral.referred_email            IS 'class=Personal; null=referral of an existing candidate';
COMMENT ON COLUMN referral.referred_candidate_profile_id IS 'class=Personal; null=referred person not registered yet';
COMMENT ON COLUMN referral.job_requirement_id        IS 'class=Internal; null=platform referral, not job-specific';
COMMENT ON COLUMN referral.converted_at              IS 'class=Internal; null=not converted';

CALL attach_audit_triggers();
