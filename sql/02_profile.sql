-- =============================================================================
-- Talentra :: 02_profile.sql   (Module: Profile — common, Phase 1)
-- Candidate identity and contact, education, experience, skills, languages,
-- certifications, preferences, resumes, projects, assessments, courses,
-- completion scoring, profile view history, candidate activity log.
-- Talent lists (shortlist/bookmark history) and referrals reference job
-- requirements, so they are created in 03_jobs_applications.sql.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- candidate_profile: one per candidate user account. Soft-deleted.
-- -----------------------------------------------------------------------------
CREATE TABLE candidate_profile (
    id                              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_account_id                 bigint       NOT NULL REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    full_name                       varchar(150) NOT NULL,   -- as the candidate writes it; no script/order assumption
    given_name                      varchar(150),
    family_name                     varchar(150),
    preferred_name                  varchar(150),
    name_language_id                bigint REFERENCES language (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    date_of_birth                   date,
    gender_id                       bigint REFERENCES gender (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    marital_status_id               bigint REFERENCES marital_status (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    nationality_country_id          bigint REFERENCES country (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    headline                        varchar(250),
    summary                         varchar(4000),
    summary_language_id             bigint REFERENCES language (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    current_city_id                 bigint REFERENCES city (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    total_experience_months         integer,
    is_fresher                      boolean      NOT NULL DEFAULT false,
    current_job_role_id             bigint REFERENCES job_role (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    current_industry_id             bigint REFERENCES industry (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    -- Current salary: disclosure status separates "not disclosed" from "not applicable" (rule group 5)
    current_salary_disclosure_status_id  bigint NOT NULL DEFAULT 2 REFERENCES salary_disclosure_status (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    current_salary_amount           numeric(14,2),
    current_salary_currency_id      bigint REFERENCES currency (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    current_salary_period_id        bigint REFERENCES salary_period (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    expected_salary_disclosure_status_id bigint NOT NULL DEFAULT 2 REFERENCES salary_disclosure_status (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    expected_salary_amount          numeric(14,2),
    expected_salary_currency_id     bigint REFERENCES currency (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    expected_salary_period_id       bigint REFERENCES salary_period (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    notice_period_id                bigint REFERENCES notice_period (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    is_open_to_relocation           boolean      NOT NULL DEFAULT false,
    is_actively_looking             boolean      NOT NULL DEFAULT true,
    profile_visibility_id           bigint       NOT NULL REFERENCES profile_visibility (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    profile_completion_pct          numeric(5,2) NOT NULL DEFAULT 0,
    last_active_at                  timestamptz,
    duplicate_of_candidate_profile_id bigint REFERENCES candidate_profile (id) ON UPDATE RESTRICT ON DELETE SET NULL,
    legacy_source_system_id         bigint REFERENCES legacy_source_system (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    legacy_record_ref               varchar(100),
    deletion_requested_at           timestamptz,
    created_at                      timestamptz  NOT NULL DEFAULT now(),
    created_by                      bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at                      timestamptz  NOT NULL DEFAULT now(),
    updated_by                      bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    deleted_at                      timestamptz,
    -- Recruiters cannot register candidates: a profile is created by its own user or the system actor (migration).
    CONSTRAINT ck_candidate_profile_self_registered CHECK (created_by = user_account_id OR created_by = 1),
    CONSTRAINT ck_candidate_profile_full_name_not_blank CHECK (btrim(full_name) <> ''),
    CONSTRAINT ck_candidate_profile_date_of_birth CHECK (date_of_birth > DATE '1900-01-01'),
    CONSTRAINT ck_candidate_profile_total_experience_months CHECK (total_experience_months BETWEEN 0 AND 840),
    CONSTRAINT ck_candidate_profile_fresher_experience CHECK (NOT is_fresher OR coalesce(total_experience_months, 0) = 0),
    CONSTRAINT ck_candidate_profile_current_salary CHECK (
        CASE WHEN current_salary_disclosure_status_id = 1
             THEN current_salary_amount >= 0 AND current_salary_currency_id IS NOT NULL AND current_salary_period_id IS NOT NULL
             ELSE current_salary_amount IS NULL AND current_salary_currency_id IS NULL AND current_salary_period_id IS NULL END),
    CONSTRAINT ck_candidate_profile_expected_salary CHECK (
        CASE WHEN expected_salary_disclosure_status_id = 1
             THEN expected_salary_amount >= 0 AND expected_salary_currency_id IS NOT NULL AND expected_salary_period_id IS NOT NULL
             ELSE expected_salary_amount IS NULL AND expected_salary_currency_id IS NULL AND expected_salary_period_id IS NULL END),
    CONSTRAINT ck_candidate_profile_completion_pct CHECK (profile_completion_pct BETWEEN 0 AND 100),
    CONSTRAINT ck_candidate_profile_not_own_duplicate CHECK (duplicate_of_candidate_profile_id <> id),
    CONSTRAINT ck_candidate_profile_legacy_ref_pair CHECK ((legacy_source_system_id IS NULL) = (legacy_record_ref IS NULL))
);
CREATE UNIQUE INDEX uq_candidate_profile_user_account_id ON candidate_profile (user_account_id);
CREATE UNIQUE INDEX uq_candidate_profile_legacy_source_system_id_legacy_record_ref
    ON candidate_profile (legacy_source_system_id, legacy_record_ref) WHERE legacy_record_ref IS NOT NULL;
CREATE INDEX idx_candidate_profile_current_city_id ON candidate_profile (current_city_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_candidate_profile_current_job_role_id ON candidate_profile (current_job_role_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_candidate_profile_full_name_trgm ON candidate_profile USING gin (full_name gin_trgm_ops);
CREATE INDEX idx_candidate_profile_duplicate_of ON candidate_profile (duplicate_of_candidate_profile_id) WHERE duplicate_of_candidate_profile_id IS NOT NULL;

-- Default-query view: excludes soft-deleted rows (rule group 4).
CREATE VIEW v_candidate_profile AS
    SELECT * FROM candidate_profile WHERE deleted_at IS NULL;

-- -----------------------------------------------------------------------------
-- Contact points (multiple per candidate; login email lives on user_account)
-- -----------------------------------------------------------------------------
CREATE TABLE candidate_email (
    id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id bigint       NOT NULL REFERENCES candidate_profile (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    email                varchar(254) NOT NULL,
    is_primary           boolean      NOT NULL DEFAULT false,
    verified_at          timestamptz,
    created_at           timestamptz  NOT NULL DEFAULT now(),
    created_by           bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at           timestamptz  NOT NULL DEFAULT now(),
    updated_by           bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_candidate_email_lowercase CHECK (email = lower(email)),
    CONSTRAINT ck_candidate_email_format CHECK (email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$')
);
CREATE UNIQUE INDEX uq_candidate_email_candidate_profile_id_email ON candidate_email (candidate_profile_id, email);
CREATE UNIQUE INDEX uq_candidate_email_primary ON candidate_email (candidate_profile_id) WHERE is_primary;
CREATE INDEX idx_candidate_email_email ON candidate_email (email);   -- duplicate detection across profiles

CREATE TABLE candidate_phone (
    id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id bigint      NOT NULL REFERENCES candidate_profile (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    phone_e164           varchar(16) NOT NULL,
    country_id           bigint      NOT NULL REFERENCES country (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    phone_type_id        bigint      NOT NULL REFERENCES phone_type (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    is_primary           boolean     NOT NULL DEFAULT false,
    verified_at          timestamptz,
    created_at           timestamptz NOT NULL DEFAULT now(),
    created_by           bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at           timestamptz NOT NULL DEFAULT now(),
    updated_by           bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_candidate_phone_e164 CHECK (phone_e164 ~ '^\+[1-9][0-9]{6,14}$')
);
CREATE UNIQUE INDEX uq_candidate_phone_candidate_profile_id_phone_e164 ON candidate_phone (candidate_profile_id, phone_e164);
CREATE UNIQUE INDEX uq_candidate_phone_primary ON candidate_phone (candidate_profile_id) WHERE is_primary;
CREATE INDEX idx_candidate_phone_phone_e164 ON candidate_phone (phone_e164);

CREATE TABLE candidate_address (
    id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id bigint       NOT NULL REFERENCES candidate_profile (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    address_type_id      bigint       NOT NULL REFERENCES address_type (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    address_line_1       varchar(250) NOT NULL,
    address_line_2       varchar(250),
    city_id              bigint       NOT NULL REFERENCES city (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    postal_code          varchar(20),
    latitude             numeric(9,6),
    longitude            numeric(9,6),
    coordinate_source_id bigint REFERENCES coordinate_source (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    created_at           timestamptz  NOT NULL DEFAULT now(),
    created_by           bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at           timestamptz  NOT NULL DEFAULT now(),
    updated_by           bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_candidate_address_candidate_profile_id_address_type_id UNIQUE (candidate_profile_id, address_type_id),
    CONSTRAINT ck_candidate_address_latitude  CHECK (latitude  BETWEEN -90  AND 90),
    CONSTRAINT ck_candidate_address_longitude CHECK (longitude BETWEEN -180 AND 180),
    CONSTRAINT ck_candidate_address_coordinates_complete CHECK (
        (latitude IS NULL AND longitude IS NULL AND coordinate_source_id IS NULL)
        OR (latitude IS NOT NULL AND longitude IS NOT NULL AND coordinate_source_id IS NOT NULL))
);

CREATE TABLE candidate_social_link (
    id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id bigint       NOT NULL REFERENCES candidate_profile (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    social_link_type_id  bigint       NOT NULL REFERENCES social_link_type (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    url                  varchar(500) NOT NULL,
    created_at           timestamptz  NOT NULL DEFAULT now(),
    created_by           bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at           timestamptz  NOT NULL DEFAULT now(),
    updated_by           bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_candidate_social_link_candidate_profile_id_url UNIQUE (candidate_profile_id, url),
    CONSTRAINT ck_candidate_social_link_url CHECK (url ~* '^https?://')
);

-- -----------------------------------------------------------------------------
-- Education, experience, skills, languages, certifications
-- -----------------------------------------------------------------------------
CREATE TABLE candidate_education (
    id                    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id  bigint       NOT NULL REFERENCES candidate_profile (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    qualification_id      bigint       NOT NULL REFERENCES qualification (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    field_of_study_id     bigint REFERENCES field_of_study (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    institution_id        bigint REFERENCES institution (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    institution_name      varchar(250),
    education_mode_id     bigint REFERENCES education_mode (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    start_date            date,
    end_date              date,
    is_ongoing            boolean      NOT NULL DEFAULT false,
    grade_scale_id        bigint REFERENCES grade_scale (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    grade_value           varchar(20),
    is_highest            boolean      NOT NULL DEFAULT false,
    created_at            timestamptz  NOT NULL DEFAULT now(),
    created_by            bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at            timestamptz  NOT NULL DEFAULT now(),
    updated_by            bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_candidate_education_institution CHECK (institution_id IS NOT NULL OR institution_name IS NOT NULL),
    CONSTRAINT ck_candidate_education_date_range CHECK (end_date >= start_date),
    CONSTRAINT ck_candidate_education_ongoing CHECK (NOT is_ongoing OR end_date IS NULL),
    CONSTRAINT ck_candidate_education_grade_pair CHECK ((grade_scale_id IS NULL) = (grade_value IS NULL))
);
CREATE INDEX idx_candidate_education_candidate_profile_id ON candidate_education (candidate_profile_id);
CREATE INDEX idx_candidate_education_qualification_id ON candidate_education (qualification_id);
CREATE UNIQUE INDEX uq_candidate_education_highest ON candidate_education (candidate_profile_id) WHERE is_highest;

CREATE TABLE candidate_work_experience (
    id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id bigint       NOT NULL REFERENCES candidate_profile (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    employer_name        varchar(250) NOT NULL,
    organisation_id      bigint REFERENCES organisation (id) ON UPDATE RESTRICT ON DELETE SET NULL,
    job_title            varchar(150) NOT NULL,
    job_role_id          bigint REFERENCES job_role (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    industry_id          bigint REFERENCES industry (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    employment_type_id   bigint       NOT NULL REFERENCES employment_type (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    city_id              bigint REFERENCES city (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    start_date           date         NOT NULL,
    end_date             date,
    is_current           boolean      NOT NULL DEFAULT false,
    description          varchar(4000),
    created_at           timestamptz  NOT NULL DEFAULT now(),
    created_by           bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at           timestamptz  NOT NULL DEFAULT now(),
    updated_by           bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_candidate_work_experience_date_range CHECK (end_date >= start_date),
    CONSTRAINT ck_candidate_work_experience_current CHECK (is_current = (end_date IS NULL))
);
CREATE INDEX idx_candidate_work_experience_candidate_profile_id ON candidate_work_experience (candidate_profile_id);
CREATE INDEX idx_candidate_work_experience_organisation_id ON candidate_work_experience (organisation_id) WHERE organisation_id IS NOT NULL;

CREATE TABLE candidate_skill (
    id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id bigint       NOT NULL REFERENCES candidate_profile (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    skill_id             bigint       NOT NULL REFERENCES skill (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    proficiency_level_id bigint REFERENCES proficiency_level (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    experience_months    integer,
    last_used_year       smallint,
    is_primary           boolean      NOT NULL DEFAULT false,
    created_at           timestamptz  NOT NULL DEFAULT now(),
    created_by           bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at           timestamptz  NOT NULL DEFAULT now(),
    updated_by           bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_candidate_skill_candidate_profile_id_skill_id UNIQUE (candidate_profile_id, skill_id),
    CONSTRAINT ck_candidate_skill_experience_months CHECK (experience_months BETWEEN 0 AND 840),
    CONSTRAINT ck_candidate_skill_last_used_year CHECK (last_used_year BETWEEN 1950 AND 2100)
);
-- Candidate search by skill: skill -> candidates (covering).
CREATE INDEX idx_candidate_skill_skill_id ON candidate_skill (skill_id, candidate_profile_id) INCLUDE (experience_months);

CREATE TABLE candidate_language (
    id                            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id          bigint      NOT NULL REFERENCES candidate_profile (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    language_id                   bigint      NOT NULL REFERENCES language (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    language_proficiency_level_id bigint      NOT NULL REFERENCES language_proficiency_level (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    can_read                      boolean     NOT NULL DEFAULT false,
    can_write                     boolean     NOT NULL DEFAULT false,
    can_speak                     boolean     NOT NULL DEFAULT true,
    created_at                    timestamptz NOT NULL DEFAULT now(),
    created_by                    bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at                    timestamptz NOT NULL DEFAULT now(),
    updated_by                    bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_candidate_language_candidate_profile_id_language_id UNIQUE (candidate_profile_id, language_id),
    CONSTRAINT ck_candidate_language_some_ability CHECK (can_read OR can_write OR can_speak)
);

CREATE TABLE candidate_certification (
    id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id bigint       NOT NULL REFERENCES candidate_profile (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    certification_name   varchar(250) NOT NULL,
    issuing_body         varchar(250) NOT NULL,
    credential_ref       varchar(100),
    credential_url       varchar(500),
    issued_on            date,
    expires_on           date,
    created_at           timestamptz  NOT NULL DEFAULT now(),
    created_by           bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at           timestamptz  NOT NULL DEFAULT now(),
    updated_by           bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_candidate_certification_date_range CHECK (expires_on >= issued_on),
    CONSTRAINT ck_candidate_certification_url CHECK (credential_url ~* '^https?://')
);
CREATE INDEX idx_candidate_certification_candidate_profile_id ON candidate_certification (candidate_profile_id);

-- Career preferences (job alert preferences themselves belong to Notifications, Phase 3)
CREATE TABLE candidate_preferred_location (
    id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id bigint      NOT NULL REFERENCES candidate_profile (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    city_id              bigint      NOT NULL REFERENCES city (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    sort_order           integer     NOT NULL DEFAULT 0,
    created_at           timestamptz NOT NULL DEFAULT now(),
    created_by           bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at           timestamptz NOT NULL DEFAULT now(),
    updated_by           bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_candidate_preferred_location_candidate_profile_id_city_id UNIQUE (candidate_profile_id, city_id)
);
CREATE INDEX idx_candidate_preferred_location_city_id ON candidate_preferred_location (city_id);

CREATE TABLE candidate_preferred_job_role (
    id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id bigint      NOT NULL REFERENCES candidate_profile (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    job_role_id          bigint      NOT NULL REFERENCES job_role (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    employment_type_id   bigint REFERENCES employment_type (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    work_mode_id         bigint REFERENCES work_mode (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    created_at           timestamptz NOT NULL DEFAULT now(),
    created_by           bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at           timestamptz NOT NULL DEFAULT now(),
    updated_by           bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_candidate_preferred_job_role_profile_role UNIQUE NULLS NOT DISTINCT (candidate_profile_id, job_role_id, employment_type_id, work_mode_id)
);
CREATE INDEX idx_candidate_preferred_job_role_job_role_id ON candidate_preferred_job_role (job_role_id);

-- -----------------------------------------------------------------------------
-- Resumes: templates, logical resume, immutable versions
-- -----------------------------------------------------------------------------
CREATE TABLE resume_template (
    id              bigint GENERATED BY DEFAULT AS IDENTITY (START WITH 1000) PRIMARY KEY,
    code            varchar(50)  NOT NULL,
    ui_label_key_id bigint       NOT NULL REFERENCES ui_label_key (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    layout_definition jsonb      NOT NULL,          -- section order/styling consumed by the renderer
    sort_order      integer      NOT NULL DEFAULT 0,
    is_active       boolean      NOT NULL DEFAULT true,
    created_at      timestamptz  NOT NULL DEFAULT now(),
    created_by      bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at      timestamptz  NOT NULL DEFAULT now(),
    updated_by      bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_resume_template_code UNIQUE (code)
);

CREATE TABLE resume (
    id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id bigint       NOT NULL REFERENCES candidate_profile (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    title                varchar(150) NOT NULL,
    is_default           boolean      NOT NULL DEFAULT false,
    created_at           timestamptz  NOT NULL DEFAULT now(),
    created_by           bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at           timestamptz  NOT NULL DEFAULT now(),
    updated_by           bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    deleted_at           timestamptz
);
CREATE INDEX idx_resume_candidate_profile_id ON resume (candidate_profile_id);
CREATE UNIQUE INDEX uq_resume_default ON resume (candidate_profile_id) WHERE is_default AND deleted_at IS NULL;

-- A version is immutable once written (an application points at the exact version sent).
CREATE TABLE resume_version (
    id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    resume_id          bigint       NOT NULL REFERENCES resume (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    version_number     integer      NOT NULL,
    resume_template_id bigint REFERENCES resume_template (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    storage_uri        varchar(500),
    file_name          varchar(255),
    mime_type          varchar(100),
    file_size_bytes    bigint,
    content_sha256     char(64),
    body_text          text,
    body_language_id   bigint REFERENCES language (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    created_at         timestamptz  NOT NULL DEFAULT now(),
    created_by         bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_resume_version_resume_id_version_number UNIQUE (resume_id, version_number),
    CONSTRAINT ck_resume_version_version_number CHECK (version_number > 0),
    -- Either an uploaded file or a template-built resume.
    CONSTRAINT ck_resume_version_source CHECK (
        (storage_uri IS NOT NULL AND file_name IS NOT NULL AND mime_type IS NOT NULL AND file_size_bytes IS NOT NULL AND content_sha256 IS NOT NULL)
        OR resume_template_id IS NOT NULL),
    CONSTRAINT ck_resume_version_file_size_bytes CHECK (file_size_bytes BETWEEN 1 AND 10485760),
    CONSTRAINT ck_resume_version_body_text_length CHECK (length(body_text) <= 200000)
);
CALL make_append_only('resume_version');

-- -----------------------------------------------------------------------------
-- Profile projects (candidate projects now; gig projects attach in Phase 2)
-- -----------------------------------------------------------------------------
CREATE TABLE profile_project (
    id                           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    project_kind_id              bigint       NOT NULL REFERENCES project_kind (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    candidate_profile_id         bigint       NOT NULL REFERENCES candidate_profile (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    candidate_work_experience_id bigint REFERENCES candidate_work_experience (id) ON UPDATE RESTRICT ON DELETE SET NULL,
    title                        varchar(200) NOT NULL,
    role_name                    varchar(150) NOT NULL,
    start_date                   date         NOT NULL,
    end_date                     date,
    outcome                      varchar(2000),
    description                  varchar(4000),
    project_url                  varchar(500),
    created_at                   timestamptz  NOT NULL DEFAULT now(),
    created_by                   bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at                   timestamptz  NOT NULL DEFAULT now(),
    updated_by                   bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_profile_project_date_range CHECK (end_date >= start_date),
    CONSTRAINT ck_profile_project_url CHECK (project_url ~* '^https?://')
);
CREATE INDEX idx_profile_project_candidate_profile_id ON profile_project (candidate_profile_id);

CREATE TABLE profile_project_skill (
    id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    profile_project_id bigint      NOT NULL REFERENCES profile_project (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    skill_id           bigint      NOT NULL REFERENCES skill (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    created_at         timestamptz NOT NULL DEFAULT now(),
    created_by         bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at         timestamptz NOT NULL DEFAULT now(),
    updated_by         bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_profile_project_skill_profile_project_id_skill_id UNIQUE (profile_project_id, skill_id)
);

-- -----------------------------------------------------------------------------
-- Assessments, courses, completion scoring
-- -----------------------------------------------------------------------------
CREATE TABLE assessment (
    id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    assessment_type_id bigint       NOT NULL REFERENCES assessment_type (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    skill_id           bigint REFERENCES skill (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    title              varchar(200) NOT NULL,
    max_score          numeric(7,2) NOT NULL,
    pass_score         numeric(7,2),
    duration_minutes   integer,
    is_active          boolean      NOT NULL DEFAULT true,
    created_at         timestamptz  NOT NULL DEFAULT now(),
    created_by         bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at         timestamptz  NOT NULL DEFAULT now(),
    updated_by         bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_assessment_max_score CHECK (max_score > 0),
    CONSTRAINT ck_assessment_pass_score CHECK (pass_score BETWEEN 0 AND max_score),
    CONSTRAINT ck_assessment_duration_minutes CHECK (duration_minutes > 0)
);

CREATE TABLE candidate_assessment_result (
    id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id bigint       NOT NULL REFERENCES candidate_profile (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    assessment_id        bigint       NOT NULL REFERENCES assessment (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    attempt_number       integer      NOT NULL,
    started_at           timestamptz  NOT NULL,
    completed_at         timestamptz,
    score                numeric(7,2),
    score_pct            numeric(5,2),
    is_passed            boolean,
    created_at           timestamptz  NOT NULL DEFAULT now(),
    created_by           bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at           timestamptz  NOT NULL DEFAULT now(),
    updated_by           bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_candidate_assessment_result_attempt UNIQUE (candidate_profile_id, assessment_id, attempt_number),
    CONSTRAINT ck_candidate_assessment_result_attempt_number CHECK (attempt_number > 0),
    CONSTRAINT ck_candidate_assessment_result_time_range CHECK (completed_at >= started_at),
    CONSTRAINT ck_candidate_assessment_result_score_pct CHECK (score_pct BETWEEN 0 AND 100),
    CONSTRAINT ck_candidate_assessment_result_scored_when_complete CHECK (
        (completed_at IS NULL AND score IS NULL AND score_pct IS NULL AND is_passed IS NULL)
        OR (completed_at IS NOT NULL AND score IS NOT NULL AND score_pct IS NOT NULL))
);
CREATE INDEX idx_candidate_assessment_result_assessment_id ON candidate_assessment_result (assessment_id);

CREATE TABLE course (
    id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title             varchar(250) NOT NULL,
    provider_name     varchar(150) NOT NULL,
    course_url        varchar(500),
    duration_hours    numeric(6,1),
    is_active         boolean      NOT NULL DEFAULT true,
    created_at        timestamptz  NOT NULL DEFAULT now(),
    created_by        bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at        timestamptz  NOT NULL DEFAULT now(),
    updated_by        bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_course_provider_name_title UNIQUE (provider_name, title),
    CONSTRAINT ck_course_duration_hours CHECK (duration_hours > 0)
);

CREATE TABLE course_enrolment (
    id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id bigint       NOT NULL REFERENCES candidate_profile (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    course_id            bigint       NOT NULL REFERENCES course (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    enrolment_status_id  bigint       NOT NULL REFERENCES enrolment_status (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    enrolled_on          date         NOT NULL,
    completed_on         date,
    progress_pct         numeric(5,2) NOT NULL DEFAULT 0,
    certificate_url      varchar(500),
    created_at           timestamptz  NOT NULL DEFAULT now(),
    created_by           bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at           timestamptz  NOT NULL DEFAULT now(),
    updated_by           bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_course_enrolment_candidate_profile_id_course_id UNIQUE (candidate_profile_id, course_id),
    CONSTRAINT ck_course_enrolment_date_range CHECK (completed_on >= enrolled_on),
    CONSTRAINT ck_course_enrolment_progress_pct CHECK (progress_pct BETWEEN 0 AND 100)
);

-- Per-section completion; candidate_profile.profile_completion_pct is the
-- denormalised weighted sum, recomputed in the same transaction.
CREATE TABLE candidate_profile_section_score (
    id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id bigint       NOT NULL REFERENCES candidate_profile (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    profile_section_id   bigint       NOT NULL REFERENCES profile_section (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    completion_pct       numeric(5,2) NOT NULL,
    computed_at          timestamptz  NOT NULL DEFAULT now(),
    created_at           timestamptz  NOT NULL DEFAULT now(),
    created_by           bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at           timestamptz  NOT NULL DEFAULT now(),
    updated_by           bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_candidate_profile_section_score_profile_section UNIQUE (candidate_profile_id, profile_section_id),
    CONSTRAINT ck_candidate_profile_section_score_completion_pct CHECK (completion_pct BETWEEN 0 AND 100)
);

-- -----------------------------------------------------------------------------
-- Append-only history (rule group 10), monthly range partitions (rule group 8).
-- PK includes the partition key, as PostgreSQL requires. No updated_* columns:
-- rows are immutable (documented deviation from rule group 4).
-- -----------------------------------------------------------------------------
CREATE TABLE profile_view_event (
    id                       bigint GENERATED ALWAYS AS IDENTITY,
    candidate_profile_id     bigint      NOT NULL REFERENCES candidate_profile (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    viewer_user_account_id   bigint      NOT NULL REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    viewer_organisation_id   bigint REFERENCES organisation (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    view_context_id          bigint      NOT NULL REFERENCES view_context (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    job_requirement_id       bigint,     -- FK added in 03 (table created there)
    viewed_at                timestamptz NOT NULL DEFAULT now(),
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT pk_profile_view_event PRIMARY KEY (id, viewed_at)
) PARTITION BY RANGE (viewed_at);
CREATE INDEX idx_profile_view_event_candidate_profile_id ON profile_view_event (candidate_profile_id, viewed_at);
CREATE INDEX idx_profile_view_event_viewer_organisation_id ON profile_view_event (viewer_organisation_id, viewed_at);
CALL create_monthly_partitions('profile_view_event', DATE '2025-01-01', DATE '2027-01-01');
CALL make_append_only('profile_view_event');

CREATE TABLE candidate_activity_log (
    id                   bigint GENERATED ALWAYS AS IDENTITY,
    candidate_profile_id bigint      NOT NULL REFERENCES candidate_profile (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    activity_type_id     bigint      NOT NULL REFERENCES activity_type (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    occurred_at          timestamptz NOT NULL DEFAULT now(),
    source_ip            inet,
    user_agent           varchar(500),
    detail               jsonb,
    created_at           timestamptz NOT NULL DEFAULT now(),
    created_by           bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT pk_candidate_activity_log PRIMARY KEY (id, occurred_at),
    CONSTRAINT ck_candidate_activity_log_detail_size CHECK (pg_column_size(detail) <= 4096)
) PARTITION BY RANGE (occurred_at);
CREATE INDEX idx_candidate_activity_log_candidate_profile_id ON candidate_activity_log (candidate_profile_id, occurred_at);
CALL create_monthly_partitions('candidate_activity_log', DATE '2025-01-01', DATE '2027-01-01');
CALL make_append_only('candidate_activity_log');

-- -----------------------------------------------------------------------------
-- Classification and nullability justification (rule groups 5, 6)
-- -----------------------------------------------------------------------------
COMMENT ON COLUMN candidate_profile.full_name        IS 'class=Personal; name as entered, any script';
COMMENT ON COLUMN candidate_profile.given_name       IS 'class=Personal; null=mononym or candidate did not split the name';
COMMENT ON COLUMN candidate_profile.family_name      IS 'class=Personal; null=mononym or candidate did not split the name';
COMMENT ON COLUMN candidate_profile.preferred_name   IS 'class=Personal; null=no preferred name, full_name is used';
COMMENT ON COLUMN candidate_profile.name_language_id IS 'class=Internal; null=script/language of name not detected';
COMMENT ON COLUMN candidate_profile.date_of_birth    IS 'class=Personal; null=not provided (optional)';
COMMENT ON COLUMN candidate_profile.gender_id        IS 'class=Personal; null=never asked; prefer_not_to_say is an explicit answer';
COMMENT ON COLUMN candidate_profile.marital_status_id IS 'class=Personal; null=never asked; prefer_not_to_say is an explicit answer';
COMMENT ON COLUMN candidate_profile.nationality_country_id IS 'class=Personal; null=not provided';
COMMENT ON COLUMN candidate_profile.headline         IS 'class=Public; null=not written yet';
COMMENT ON COLUMN candidate_profile.summary          IS 'class=Public; null=not written yet';
COMMENT ON COLUMN candidate_profile.summary_language_id IS 'class=Internal; null=summary absent or language not detected';
COMMENT ON COLUMN candidate_profile.current_city_id  IS 'class=Personal; null=not provided';
COMMENT ON COLUMN candidate_profile.total_experience_months IS 'class=Public; null=not stated (0 is a real value for freshers)';
COMMENT ON COLUMN candidate_profile.current_job_role_id IS 'class=Public; null=fresher or not stated';
COMMENT ON COLUMN candidate_profile.current_industry_id IS 'class=Public; null=fresher or not stated';
COMMENT ON COLUMN candidate_profile.current_salary_amount IS 'class=Personal; null when disclosure status is not_disclosed/not_applicable (CHECK)';
COMMENT ON COLUMN candidate_profile.current_salary_currency_id IS 'class=Personal; null exactly when amount is null';
COMMENT ON COLUMN candidate_profile.current_salary_period_id IS 'class=Personal; null exactly when amount is null';
COMMENT ON COLUMN candidate_profile.expected_salary_amount IS 'class=Personal; null when disclosure status is not_disclosed/not_applicable (CHECK)';
COMMENT ON COLUMN candidate_profile.expected_salary_currency_id IS 'class=Personal; null exactly when amount is null';
COMMENT ON COLUMN candidate_profile.expected_salary_period_id IS 'class=Personal; null exactly when amount is null';
COMMENT ON COLUMN candidate_profile.notice_period_id IS 'class=Public; null=not stated';
COMMENT ON COLUMN candidate_profile.last_active_at   IS 'class=Internal; null=never logged in after registration (legacy import)';
COMMENT ON COLUMN candidate_profile.duplicate_of_candidate_profile_id IS 'class=Internal; null=not identified as a duplicate';
COMMENT ON COLUMN candidate_profile.legacy_source_system_id IS 'class=Internal; null=native Talentra registration';
COMMENT ON COLUMN candidate_profile.legacy_record_ref IS 'class=Internal; null=native Talentra registration';
COMMENT ON COLUMN candidate_profile.deletion_requested_at IS 'class=Internal; null=no erasure request; set starts the 30-day erasure job';
COMMENT ON COLUMN candidate_profile.deleted_at       IS 'class=Internal; null=active (soft delete)';
COMMENT ON COLUMN candidate_email.email              IS 'class=Personal';
COMMENT ON COLUMN candidate_email.verified_at        IS 'class=Internal; null=not verified yet';
COMMENT ON COLUMN candidate_phone.phone_e164         IS 'class=Personal; E.164 with country code';
COMMENT ON COLUMN candidate_phone.verified_at        IS 'class=Internal; null=not verified yet';
COMMENT ON COLUMN candidate_address.address_line_1   IS 'class=Personal';
COMMENT ON COLUMN candidate_address.address_line_2   IS 'class=Personal; null=address fits on one line';
COMMENT ON COLUMN candidate_address.postal_code      IS 'class=Personal; null=country without postal codes or not provided';
COMMENT ON COLUMN candidate_address.latitude         IS 'class=Personal; WGS84 6 dp; null=not geocoded (optional service)';
COMMENT ON COLUMN candidate_address.longitude        IS 'class=Personal; WGS84 6 dp; null=not geocoded';
COMMENT ON COLUMN candidate_address.coordinate_source_id IS 'class=Internal; null only when coordinates are null';
COMMENT ON COLUMN candidate_social_link.url          IS 'class=Personal';
COMMENT ON COLUMN candidate_education.field_of_study_id IS 'class=Public; null=qualification has no specialisation (e.g. 10th)';
COMMENT ON COLUMN candidate_education.institution_id IS 'class=Public; null=institution not in master, institution_name used';
COMMENT ON COLUMN candidate_education.institution_name IS 'class=Public; null=institution_id is set';
COMMENT ON COLUMN candidate_education.education_mode_id IS 'class=Public; null=not stated';
COMMENT ON COLUMN candidate_education.start_date     IS 'class=Public; null=not stated (common in legacy data)';
COMMENT ON COLUMN candidate_education.end_date       IS 'class=Public; null=ongoing or not stated';
COMMENT ON COLUMN candidate_education.grade_scale_id IS 'class=Personal; null=grade not disclosed';
COMMENT ON COLUMN candidate_education.grade_value    IS 'class=Personal; null=grade not disclosed';
COMMENT ON COLUMN candidate_work_experience.organisation_id IS 'class=Public; null=employer not matched to a platform organisation';
COMMENT ON COLUMN candidate_work_experience.job_role_id IS 'class=Public; null=title not mapped to master role';
COMMENT ON COLUMN candidate_work_experience.industry_id IS 'class=Public; null=not stated';
COMMENT ON COLUMN candidate_work_experience.city_id  IS 'class=Public; null=not stated';
COMMENT ON COLUMN candidate_work_experience.end_date IS 'class=Public; null=current job (CHECK with is_current)';
COMMENT ON COLUMN candidate_work_experience.description IS 'class=Public; null=not written';
COMMENT ON COLUMN candidate_skill.proficiency_level_id IS 'class=Public; null=not self-rated';
COMMENT ON COLUMN candidate_skill.experience_months  IS 'class=Public; null=not stated';
COMMENT ON COLUMN candidate_skill.last_used_year     IS 'class=Public; null=not stated';
COMMENT ON COLUMN candidate_certification.credential_ref IS 'class=Personal; null=certificate has no id';
COMMENT ON COLUMN candidate_certification.credential_url IS 'class=Personal; null=no online verification link';
COMMENT ON COLUMN candidate_certification.issued_on  IS 'class=Public; null=not stated';
COMMENT ON COLUMN candidate_certification.expires_on IS 'class=Public; null=does not expire';
COMMENT ON COLUMN candidate_preferred_job_role.employment_type_id IS 'class=Public; null=any employment type';
COMMENT ON COLUMN candidate_preferred_job_role.work_mode_id IS 'class=Public; null=any work mode';
COMMENT ON COLUMN resume.deleted_at                  IS 'class=Internal; null=active (soft delete)';
COMMENT ON COLUMN resume_version.resume_template_id  IS 'class=Internal; null=uploaded file, not template-built';
COMMENT ON COLUMN resume_version.storage_uri         IS 'class=Personal; object-store key; null=template-built, rendered on demand';
COMMENT ON COLUMN resume_version.file_name           IS 'class=Personal; null=template-built';
COMMENT ON COLUMN resume_version.mime_type           IS 'class=Internal; null=template-built';
COMMENT ON COLUMN resume_version.file_size_bytes     IS 'class=Internal; null=template-built';
COMMENT ON COLUMN resume_version.content_sha256      IS 'class=Internal; null=template-built';
COMMENT ON COLUMN resume_version.body_text           IS 'class=Personal; unbounded-by-type resume body (justified: full-text search), capped at 200k chars by CHECK; null=text extraction pending/failed';
COMMENT ON COLUMN resume_version.body_language_id    IS 'class=Internal; null=language not detected';
COMMENT ON COLUMN profile_project.candidate_work_experience_id IS 'class=Public; null=personal/academic project not tied to a job';
COMMENT ON COLUMN profile_project.end_date           IS 'class=Public; null=ongoing';
COMMENT ON COLUMN profile_project.outcome            IS 'class=Public; null=not written';
COMMENT ON COLUMN profile_project.description        IS 'class=Public; null=not written';
COMMENT ON COLUMN profile_project.project_url        IS 'class=Public; null=no public link';
COMMENT ON COLUMN assessment.skill_id                IS 'class=Public; null=assessment is not skill-specific (psychometric)';
COMMENT ON COLUMN assessment.pass_score              IS 'class=Public; null=no pass mark (self-assessment)';
COMMENT ON COLUMN assessment.duration_minutes        IS 'class=Public; null=untimed';
COMMENT ON COLUMN candidate_assessment_result.completed_at IS 'class=Personal; null=attempt in progress or abandoned';
COMMENT ON COLUMN candidate_assessment_result.score  IS 'class=Personal; null=not completed';
COMMENT ON COLUMN candidate_assessment_result.score_pct IS 'class=Personal; 0..100; null=not completed';
COMMENT ON COLUMN candidate_assessment_result.is_passed IS 'class=Personal; null=not completed or assessment has no pass mark';
COMMENT ON COLUMN course.course_url                  IS 'class=Public; null=offline course';
COMMENT ON COLUMN course.duration_hours              IS 'class=Public; null=self-paced, unknown duration';
COMMENT ON COLUMN course_enrolment.completed_on      IS 'class=Personal; null=not completed';
COMMENT ON COLUMN course_enrolment.certificate_url   IS 'class=Personal; null=no certificate issued';
COMMENT ON COLUMN profile_view_event.viewer_organisation_id IS 'class=Internal; null=viewer is a freelance consultant without organisation';
COMMENT ON COLUMN profile_view_event.job_requirement_id IS 'class=Internal; null=view not in the context of a job';
COMMENT ON COLUMN candidate_activity_log.source_ip   IS 'class=Personal; null=server-side event (scheduled job)';
COMMENT ON COLUMN candidate_activity_log.user_agent  IS 'class=Personal; null=server-side event';
COMMENT ON COLUMN candidate_activity_log.detail      IS 'class=Personal; bounded 4 KB; null=no extra detail for this activity type';

CALL attach_audit_triggers();
