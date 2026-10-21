-- V006 Candidate profile: profile core, education, experience, skills, languages, resumes, blocking.
-- Requirements: FR-PRO-01..09, NFR-PRIV-02 (visibility, blocking), docket rule group 5 (unknown vs not applicable).
-- Contact details (email, phone) stay on app_user: recruiters see them only after a paid profile download (FR-BIL-05).

CREATE TABLE candidate_profile (
    id                           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    app_user_id                  bigint NOT NULL CONSTRAINT uq_candidate_profile_app_user_id UNIQUE REFERENCES app_user (id) ON DELETE RESTRICT,
    full_name                    person_name NOT NULL,
    headline                     short_text,
    summary                      medium_text,
    profile_language_id          smallint REFERENCES language (id) ON DELETE RESTRICT,
    current_city_id              integer REFERENCES city (id) ON DELETE RESTRICT,
    total_experience_months      smallint NOT NULL DEFAULT 0 CHECK (total_experience_months BETWEEN 0 AND 720),
    expected_salary_amount       money_amount,
    expected_salary_currency_id  smallint REFERENCES currency (id) ON DELETE RESTRICT,
    salary_disclosure_id         smallint NOT NULL DEFAULT 3 REFERENCES salary_disclosure (id) ON DELETE RESTRICT,
    notice_period_days           smallint CHECK (notice_period_days BETWEEN 0 AND 365),
    is_open_to_work              boolean NOT NULL DEFAULT true,
    profile_visibility_id        smallint NOT NULL DEFAULT 1 REFERENCES profile_visibility (id) ON DELETE RESTRICT,
    last_active_at               timestamptz NOT NULL DEFAULT now(),
    search_vector                tsvector NOT NULL GENERATED ALWAYS AS
                                 (to_tsvector('simple', full_name || ' ' || coalesce(headline, ''))) STORED,
    deleted_at                   timestamptz,
    -- salary: an amount and its currency exactly when disclosed; "not disclosed" and "not provided" are different facts
    CONSTRAINT ck_candidate_profile_salary CHECK (
        (salary_disclosure_id = 1) = (expected_salary_amount IS NOT NULL)
        AND (expected_salary_amount IS NULL) = (expected_salary_currency_id IS NULL))
);
CALL add_audit_columns('candidate_profile');
CREATE INDEX idx_candidate_profile_search ON candidate_profile (current_city_id, last_active_at DESC)
    WHERE is_open_to_work AND deleted_at IS NULL AND profile_visibility_id <> 3;                     -- AP-04 recruiter search
CREATE INDEX idx_candidate_profile_full_name_trgm ON candidate_profile USING gin (full_name gin_trgm_ops);  -- AP-05 name search
CREATE INDEX idx_candidate_profile_search_vector ON candidate_profile USING gin (search_vector);
COMMENT ON COLUMN candidate_profile.full_name IS 'Personal. Any script, any word order (rule group 3).';
COMMENT ON COLUMN candidate_profile.headline IS 'Personal. e.g. "Java developer, 5 years". NULL: not written yet.';
COMMENT ON COLUMN candidate_profile.summary IS 'Personal. NULL: not written yet.';
COMMENT ON COLUMN candidate_profile.profile_language_id IS 'Internal. Language the candidate wrote the profile in (rule group 7). NULL: unknown.';
COMMENT ON COLUMN candidate_profile.current_city_id IS 'Personal. NULL: not given yet; profiles without a city are excluded from city search.';
COMMENT ON COLUMN candidate_profile.expected_salary_amount IS 'Personal. Annual. NULL: not disclosed or not provided, which salary_disclosure_id tells apart (rule group 5).';
COMMENT ON COLUMN candidate_profile.expected_salary_currency_id IS 'Internal. NULL: exactly when the amount is NULL.';
COMMENT ON COLUMN candidate_profile.notice_period_days IS 'Personal. 0 means available now. NULL: unknown, not asked yet.';
COMMENT ON COLUMN candidate_profile.search_vector IS 'Internal. Generated from name and headline for full-text search.';

CREATE TABLE candidate_education (
    id                    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id  bigint NOT NULL REFERENCES candidate_profile (id) ON DELETE CASCADE,
    qualification_id      smallint NOT NULL REFERENCES qualification (id) ON DELETE RESTRICT,
    institution_name      short_text NOT NULL,
    field_of_study        short_text,
    start_date            date NOT NULL,
    end_date              date,
    CONSTRAINT ck_candidate_education_dates CHECK (end_date IS NULL OR end_date >= start_date)
);
CALL add_audit_columns('candidate_education');
CREATE INDEX idx_candidate_education_candidate_profile_id ON candidate_education (candidate_profile_id);
COMMENT ON COLUMN candidate_education.field_of_study IS 'Personal. NULL: not applicable (school levels have no field).';
COMMENT ON COLUMN candidate_education.end_date IS 'Personal. NULL: still studying.';

CREATE TABLE candidate_experience (
    id                    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id  bigint NOT NULL REFERENCES candidate_profile (id) ON DELETE CASCADE,
    organisation_id       bigint REFERENCES organisation (id) ON DELETE SET NULL,
    company_name          short_text NOT NULL,
    job_title             short_text NOT NULL,
    employment_type_id    smallint NOT NULL REFERENCES employment_type (id) ON DELETE RESTRICT,
    start_date            date NOT NULL,
    end_date              date,
    description           medium_text,
    CONSTRAINT ck_candidate_experience_dates CHECK (end_date IS NULL OR end_date >= start_date)
);
CALL add_audit_columns('candidate_experience');
CREATE INDEX idx_candidate_experience_candidate_profile_id ON candidate_experience (candidate_profile_id);
CREATE INDEX idx_candidate_experience_organisation_id ON candidate_experience (organisation_id) WHERE organisation_id IS NOT NULL;
CREATE UNIQUE INDEX uq_candidate_experience_one_current ON candidate_experience (candidate_profile_id) WHERE end_date IS NULL;
COMMENT ON COLUMN candidate_experience.organisation_id IS 'Internal. Matched employer on the platform. NULL: employer is not on Talentra (company_name is always kept).';
COMMENT ON COLUMN candidate_experience.end_date IS 'Personal. NULL: current job (at most one, uq_candidate_experience_one_current).';
COMMENT ON COLUMN candidate_experience.description IS 'Personal. NULL: not written.';

CREATE TABLE candidate_skill (
    id                    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id  bigint NOT NULL REFERENCES candidate_profile (id) ON DELETE CASCADE,
    skill_id              integer NOT NULL REFERENCES skill (id) ON DELETE RESTRICT,
    proficiency_level_id  smallint NOT NULL REFERENCES proficiency_level (id) ON DELETE RESTRICT,
    experience_months     smallint CHECK (experience_months BETWEEN 0 AND 720),
    CONSTRAINT uq_candidate_skill_candidate_profile_id_skill_id UNIQUE (candidate_profile_id, skill_id)
);
CALL add_audit_columns('candidate_skill');
CREATE INDEX idx_candidate_skill_skill_id ON candidate_skill (skill_id, candidate_profile_id);           -- AP-04 skill filter
COMMENT ON COLUMN candidate_skill.experience_months IS 'Personal. NULL: the candidate did not say.';

CREATE TABLE candidate_language (
    id                    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id  bigint NOT NULL REFERENCES candidate_profile (id) ON DELETE CASCADE,
    language_id           smallint NOT NULL REFERENCES language (id) ON DELETE RESTRICT,
    proficiency_level_id  smallint NOT NULL REFERENCES proficiency_level (id) ON DELETE RESTRICT,
    CONSTRAINT uq_candidate_language_candidate_profile_id_language_id UNIQUE (candidate_profile_id, language_id)
);
CALL add_audit_columns('candidate_language');

-- Resume files live in object storage; the database keeps the reference and a checksum (ADR-008).
CREATE TABLE resume (
    id                    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id  bigint NOT NULL REFERENCES candidate_profile (id) ON DELETE CASCADE,
    version_number        smallint NOT NULL CHECK (version_number > 0),
    storage_key           text NOT NULL CONSTRAINT uq_resume_storage_key UNIQUE CHECK (storage_key ~ '^resumes/[0-9]+/[0-9a-f-]{36}\.(pdf|docx)$'),
    file_sha256           sha256_digest NOT NULL,
    content_language_id   smallint REFERENCES language (id) ON DELETE RESTRICT,
    is_primary            boolean NOT NULL DEFAULT false,
    CONSTRAINT uq_resume_candidate_profile_id_version_number UNIQUE (candidate_profile_id, version_number),
    CONSTRAINT uq_resume_id_candidate_profile_id UNIQUE (id, candidate_profile_id)   -- lets application prove the resume is the applicant's
);
CALL add_audit_columns('resume');
CREATE UNIQUE INDEX uq_resume_one_primary ON resume (candidate_profile_id) WHERE is_primary;
COMMENT ON COLUMN resume.storage_key IS 'Personal. Object-storage key; files are encrypted at rest by the store.';
COMMENT ON COLUMN resume.content_language_id IS 'Internal. NULL: language not detected.';

-- A candidate blocks a company or one person; a blocked party can no longer find or see the candidate (enforced by RLS).
CREATE TABLE candidate_block (
    id                    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id  bigint NOT NULL REFERENCES candidate_profile (id) ON DELETE CASCADE,
    blocked_organisation_id bigint REFERENCES organisation (id) ON DELETE CASCADE,
    blocked_app_user_id   bigint REFERENCES app_user (id) ON DELETE CASCADE,
    blocked_at            timestamptz NOT NULL DEFAULT now(),
    unblocked_at          timestamptz,
    CONSTRAINT ck_candidate_block_one_target CHECK (num_nonnulls(blocked_organisation_id, blocked_app_user_id) = 1),
    CONSTRAINT ck_candidate_block_dates CHECK (unblocked_at IS NULL OR unblocked_at >= blocked_at)
);
CALL add_audit_columns('candidate_block');
CREATE UNIQUE INDEX uq_candidate_block_active_organisation ON candidate_block (blocked_organisation_id, candidate_profile_id) WHERE unblocked_at IS NULL;
CREATE UNIQUE INDEX uq_candidate_block_active_user ON candidate_block (blocked_app_user_id, candidate_profile_id) WHERE unblocked_at IS NULL;
CREATE INDEX idx_candidate_block_candidate_profile_id ON candidate_block (candidate_profile_id);
COMMENT ON COLUMN candidate_block.blocked_organisation_id IS 'Internal. Role-named key (deviation D-03). NULL: the block targets one person instead.';
COMMENT ON COLUMN candidate_block.blocked_app_user_id IS 'Internal. Role-named key (deviation D-03). NULL: the block targets a company instead.';
COMMENT ON COLUMN candidate_block.unblocked_at IS 'Internal. NULL: block is active.';
CREATE TRIGGER trg_candidate_block_audit AFTER INSERT OR UPDATE OR DELETE ON candidate_block FOR EACH ROW EXECUTE FUNCTION audit_row_change();
