-- V007 Job requirements, screening questions, applications and the status pipeline.
-- Requirements: FR-JOB-01..08, FR-APP-01..08, docket section 3 (consultant only on jobs open to consultants).

CREATE TABLE job_requirement (
    id                        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organisation_id           bigint NOT NULL REFERENCES organisation (id) ON DELETE RESTRICT,
    title                     short_text NOT NULL,
    description               long_text NOT NULL,
    description_language_id   smallint REFERENCES language (id) ON DELETE RESTRICT,
    employment_type_id        smallint NOT NULL REFERENCES employment_type (id) ON DELETE RESTRICT,
    work_mode_id              smallint NOT NULL REFERENCES work_mode (id) ON DELETE RESTRICT,
    industry_id               smallint NOT NULL REFERENCES industry (id) ON DELETE RESTRICT,
    min_experience_months     smallint NOT NULL DEFAULT 0 CHECK (min_experience_months BETWEEN 0 AND 600),
    max_experience_months     smallint CHECK (max_experience_months BETWEEN 0 AND 600),
    salary_min_amount         money_amount,
    salary_max_amount         money_amount,
    salary_currency_id        smallint REFERENCES currency (id) ON DELETE RESTRICT,
    salary_disclosure_id      smallint NOT NULL REFERENCES salary_disclosure (id) ON DELETE RESTRICT
                              CONSTRAINT ck_job_requirement_salary_disclosure CHECK (salary_disclosure_id IN (1, 2)),
    positions_total           smallint NOT NULL DEFAULT 1 CHECK (positions_total BETWEEN 1 AND 10000),
    positions_filled          smallint NOT NULL DEFAULT 0,
    job_status_id             smallint NOT NULL DEFAULT 1 REFERENCES job_status (id) ON DELETE RESTRICT,
    is_open_to_consultants    boolean NOT NULL DEFAULT false,
    published_at              timestamptz,
    closes_on                 date,
    search_vector             tsvector NOT NULL GENERATED ALWAYS AS
                              (setweight(to_tsvector('simple', title), 'A') || setweight(to_tsvector('simple', left(description, 5000)), 'B')) STORED,
    deleted_at                timestamptz,
    CONSTRAINT ck_job_requirement_experience CHECK (max_experience_months IS NULL OR max_experience_months >= min_experience_months),
    CONSTRAINT ck_job_requirement_salary CHECK (
        salary_min_amount IS NULL OR salary_max_amount IS NULL OR salary_min_amount <= salary_max_amount),
    CONSTRAINT ck_job_requirement_salary_disclosed CHECK (
        (salary_disclosure_id = 1) = (salary_min_amount IS NOT NULL)
        AND (salary_min_amount IS NULL) = (salary_currency_id IS NULL)
        AND (salary_max_amount IS NULL OR salary_min_amount IS NOT NULL)),
    CONSTRAINT ck_job_requirement_positions  CHECK (positions_filled BETWEEN 0 AND positions_total),
    CONSTRAINT ck_job_requirement_published  CHECK ((job_status_id = 1) = (published_at IS NULL)),
    CONSTRAINT ck_job_requirement_closes_on  CHECK (closes_on IS NULL OR published_at IS NULL OR closes_on >= published_at::date),
    CONSTRAINT uq_job_requirement_id_organisation_id UNIQUE (id, organisation_id)
);
CALL add_audit_columns('job_requirement');
CREATE INDEX idx_job_requirement_search_vector ON job_requirement USING gin (search_vector) WHERE job_status_id = 2 AND deleted_at IS NULL;  -- AP-01
CREATE INDEX idx_job_requirement_organisation_id ON job_requirement (organisation_id, job_status_id, published_at DESC);                 -- AP-06
CREATE INDEX idx_job_requirement_published_at ON job_requirement (published_at DESC) WHERE job_status_id = 2 AND deleted_at IS NULL;     -- AP-01 newest first
COMMENT ON COLUMN job_requirement.description IS 'Public. Unbounded-class text capped at 20,000 characters (ADR-008); stored once in the language entered.';
COMMENT ON COLUMN job_requirement.description_language_id IS 'Internal. NULL: language not detected.';
COMMENT ON COLUMN job_requirement.max_experience_months IS 'Public. NULL: no upper limit.';
COMMENT ON COLUMN job_requirement.salary_min_amount IS 'Public. Annual. NULL: salary not disclosed (salary_disclosure_id = not_disclosed).';
COMMENT ON COLUMN job_requirement.salary_max_amount IS 'Public. NULL: no upper figure given, or not disclosed.';
COMMENT ON COLUMN job_requirement.salary_currency_id IS 'Internal. NULL: exactly when no salary is given.';
COMMENT ON COLUMN job_requirement.published_at IS 'Public. NULL: exactly while the job is a draft (ck_job_requirement_published).';
COMMENT ON COLUMN job_requirement.closes_on IS 'Public. NULL: open until filled or closed by hand.';

CREATE TABLE job_requirement_location (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_requirement_id  bigint NOT NULL REFERENCES job_requirement (id) ON DELETE CASCADE,
    city_id             integer NOT NULL REFERENCES city (id) ON DELETE RESTRICT,
    CONSTRAINT uq_job_requirement_location_job_requirement_id_city_id UNIQUE (job_requirement_id, city_id)
);
CALL add_audit_columns('job_requirement_location');
CREATE INDEX idx_job_requirement_location_city_id ON job_requirement_location (city_id, job_requirement_id);   -- AP-01 city filter

CREATE TABLE job_requirement_skill (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_requirement_id  bigint NOT NULL REFERENCES job_requirement (id) ON DELETE CASCADE,
    skill_id            integer NOT NULL REFERENCES skill (id) ON DELETE RESTRICT,
    is_mandatory        boolean NOT NULL DEFAULT true,
    CONSTRAINT uq_job_requirement_skill_job_requirement_id_skill_id UNIQUE (job_requirement_id, skill_id)
);
CALL add_audit_columns('job_requirement_skill');
CREATE INDEX idx_job_requirement_skill_skill_id ON job_requirement_skill (skill_id);

CREATE TABLE screening_question (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_requirement_id  bigint NOT NULL REFERENCES job_requirement (id) ON DELETE CASCADE,
    question_text       short_text NOT NULL,
    answer_type_id      smallint NOT NULL REFERENCES answer_type (id) ON DELETE RESTRICT,
    is_required         boolean NOT NULL DEFAULT true,
    sort_order          smallint NOT NULL CHECK (sort_order > 0),
    CONSTRAINT uq_screening_question_job_requirement_id_sort_order UNIQUE (job_requirement_id, sort_order),
    CONSTRAINT uq_screening_question_id_job_requirement_id UNIQUE (id, job_requirement_id)
);
CALL add_audit_columns('screening_question');
COMMENT ON COLUMN screening_question.question_text IS 'Public. Shown to applicants in the language it was written.';

-- Allowed moves of the pipeline. The application trigger refuses anything not listed (FR-APP-04).
CREATE TABLE application_status_transition (
    id              smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    from_status_id  smallint NOT NULL REFERENCES application_status (id) ON DELETE CASCADE,
    to_status_id    smallint NOT NULL REFERENCES application_status (id) ON DELETE CASCADE,
    CONSTRAINT uq_application_status_transition_from_to UNIQUE (from_status_id, to_status_id),
    CONSTRAINT ck_application_status_transition_moves CHECK (from_status_id <> to_status_id)
);
INSERT INTO application_status_transition (from_status_id, to_status_id)
SELECT f.id, t.id FROM application_status f JOIN application_status t ON (f.code, t.code) IN (
  ('applied', 'shortlisted'), ('applied', 'rejected'), ('applied', 'withdrawn'),
  ('shortlisted', 'interviewing'), ('shortlisted', 'rejected'), ('shortlisted', 'withdrawn'),
  ('interviewing', 'offered'), ('interviewing', 'rejected'), ('interviewing', 'withdrawn'),
  ('offered', 'joined'), ('offered', 'rejected'), ('offered', 'withdrawn'));

CREATE TABLE application (
    id                     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_requirement_id     bigint NOT NULL,
    organisation_id        bigint NOT NULL REFERENCES organisation (id) ON DELETE RESTRICT,
    candidate_profile_id   bigint NOT NULL REFERENCES candidate_profile (id) ON DELETE RESTRICT,
    resume_id              bigint,
    application_status_id  smallint NOT NULL DEFAULT 1 REFERENCES application_status (id) ON DELETE RESTRICT,
    application_source_id  smallint NOT NULL DEFAULT 1 REFERENCES application_source (id) ON DELETE RESTRICT,
    sourced_by_app_user_id bigint REFERENCES app_user (id) ON DELETE RESTRICT,
    applied_at             timestamptz NOT NULL DEFAULT now(),
    status_changed_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_application_job_requirement_id_candidate_profile_id UNIQUE (job_requirement_id, candidate_profile_id),
    CONSTRAINT uq_application_id_job_requirement_id UNIQUE (id, job_requirement_id),
    -- organisation_id is copied from the job (by the guard trigger) and pinned to it by this key: row-level security
    -- and the employer pipeline filter on it without a join (ADR-011)
    CONSTRAINT fk_application_job_requirement FOREIGN KEY (job_requirement_id, organisation_id)
        REFERENCES job_requirement (id, organisation_id) ON DELETE RESTRICT,
    CONSTRAINT fk_application_resume FOREIGN KEY (resume_id, candidate_profile_id)
        REFERENCES resume (id, candidate_profile_id) ON DELETE RESTRICT,
    CONSTRAINT ck_application_sourced_by CHECK ((application_source_id IN (2, 3)) = (sourced_by_app_user_id IS NOT NULL)),
    CONSTRAINT ck_application_status_changed_at CHECK (status_changed_at >= applied_at)
);
CALL add_audit_columns('application');
CREATE INDEX idx_application_candidate_profile_id ON application (candidate_profile_id, applied_at DESC);              -- AP-02
CREATE INDEX idx_application_job_requirement_status ON application (job_requirement_id, application_status_id, status_changed_at DESC);  -- AP-03
CREATE INDEX idx_application_organisation_id ON application (organisation_id, application_status_id, status_changed_at DESC);    -- AP-06
CREATE INDEX idx_application_resume_id ON application (resume_id) WHERE resume_id IS NOT NULL;
CREATE INDEX idx_application_sourced_by_app_user_id ON application (sourced_by_app_user_id) WHERE sourced_by_app_user_id IS NOT NULL;
COMMENT ON COLUMN application.resume_id IS 'Personal. Resume version sent; must be the applicant''s own (fk_application_resume). NULL: quick apply without a resume (blue-collar roles).';
COMMENT ON COLUMN application.sourced_by_app_user_id IS 'Internal. Role-named key (D-03): recruiter or consultant who sourced the candidate. NULL: the candidate applied directly.';

CREATE TABLE application_answer (
    id                     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    application_id         bigint NOT NULL,
    job_requirement_id     bigint NOT NULL,
    screening_question_id  bigint NOT NULL,
    answer_text            short_text NOT NULL,
    CONSTRAINT uq_application_answer_application_id_screening_question_id UNIQUE (application_id, screening_question_id),
    -- both keys carry job_requirement_id, so an answer can only be to a question of the job applied for
    CONSTRAINT fk_application_answer_application FOREIGN KEY (application_id, job_requirement_id)
        REFERENCES application (id, job_requirement_id) ON DELETE CASCADE,
    CONSTRAINT fk_application_answer_screening_question FOREIGN KEY (screening_question_id, job_requirement_id)
        REFERENCES screening_question (id, job_requirement_id) ON DELETE CASCADE
);
CALL add_audit_columns('application_answer');
CREATE INDEX idx_application_answer_screening_question_id ON application_answer (screening_question_id, job_requirement_id);
COMMENT ON COLUMN application_answer.answer_text IS 'Personal. Answer as typed; yes_no answers are "yes" or "no".';

CREATE TABLE application_status_history (
    id                     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    application_id         bigint NOT NULL REFERENCES application (id) ON DELETE CASCADE,
    from_status_id         smallint REFERENCES application_status (id) ON DELETE RESTRICT,
    to_status_id           smallint NOT NULL REFERENCES application_status (id) ON DELETE RESTRICT,
    changed_at             timestamptz NOT NULL,
    CONSTRAINT ck_application_status_history_moves CHECK (from_status_id IS DISTINCT FROM to_status_id)
);
CALL add_audit_columns('application_status_history', append_only => true);
CREATE INDEX idx_application_status_history_application_id ON application_status_history (application_id, changed_at);
CREATE INDEX idx_application_status_history_changed_at ON application_status_history USING brin (changed_at);
COMMENT ON TABLE application_status_history IS 'Internal. Append-only, written only by trigger. Not partitioned at this scale (ADR-006).';
COMMENT ON COLUMN application_status_history.from_status_id IS 'Internal. NULL: the first entry, when the application was created.';

-- Pipeline rules, in one place for every caller (API, admin tools, seed).
CREATE FUNCTION application_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE j job_requirement;
BEGIN
  IF TG_OP = 'INSERT' THEN
    SELECT * INTO j FROM job_requirement WHERE id = NEW.job_requirement_id;
    IF NEW.application_status_id <> 1 THEN
      RAISE EXCEPTION 'a new application starts as applied' USING ERRCODE = 'check_violation';
    END IF;
    IF j.job_status_id <> 2 OR j.deleted_at IS NOT NULL OR NEW.applied_at < j.published_at
       OR (j.closes_on IS NOT NULL AND NEW.applied_at::date > j.closes_on) THEN
      RAISE EXCEPTION 'job requirement % is not open for applications', j.id USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.application_source_id = 3 AND NOT j.is_open_to_consultants THEN
      RAISE EXCEPTION 'job requirement % is not open to consultants', j.id USING ERRCODE = 'insufficient_privilege';
    END IF;
    NEW.organisation_id := j.organisation_id;
    NEW.status_changed_at := NEW.applied_at;
  ELSIF NEW.application_status_id IS DISTINCT FROM OLD.application_status_id THEN
    IF NOT EXISTS (SELECT 1 FROM application_status_transition
                   WHERE from_status_id = OLD.application_status_id AND to_status_id = NEW.application_status_id) THEN
      RAISE EXCEPTION 'application % cannot move from status % to %', OLD.id, OLD.application_status_id, NEW.application_status_id
        USING ERRCODE = 'check_violation';
    END IF;
    -- the candidate may only withdraw; every other move belongs to the employer side
    IF app_current_user_id() = (SELECT app_user_id FROM candidate_profile WHERE id = NEW.candidate_profile_id)
       AND NEW.application_status_id <> 7 THEN
      RAISE EXCEPTION 'a candidate can only withdraw an application' USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF NEW.status_changed_at = OLD.status_changed_at THEN NEW.status_changed_at := now(); END IF;
    IF NEW.application_status_id = 5 THEN      -- joined: one more position filled, the job closes when all are
      UPDATE job_requirement SET positions_filled = positions_filled + 1,
             job_status_id = CASE WHEN positions_filled + 1 = positions_total THEN 5 ELSE job_status_id END
      WHERE id = NEW.job_requirement_id;
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_application_guard BEFORE INSERT OR UPDATE ON application FOR EACH ROW EXECUTE FUNCTION application_guard();

CREATE FUNCTION application_record_history() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'INSERT' OR NEW.application_status_id IS DISTINCT FROM OLD.application_status_id THEN
    INSERT INTO application_status_history (application_id, from_status_id, to_status_id, changed_at, created_at)
    VALUES (NEW.id, CASE WHEN TG_OP = 'UPDATE' THEN OLD.application_status_id END, NEW.application_status_id,
            NEW.status_changed_at, NEW.status_changed_at);
  END IF;
  RETURN NULL;
END $$;
CREATE TRIGGER trg_application_record_history AFTER INSERT OR UPDATE OF application_status_id ON application
    FOR EACH ROW EXECUTE FUNCTION application_record_history();
