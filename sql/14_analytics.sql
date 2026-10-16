-- =============================================================================
-- Talentra :: 14_analytics.sql
-- Module: Analytics layer and reporting marts — team, Phase 4 (B49)
-- Star schema loaded from the transactional tables by a scheduled job (owner role).
-- Analytical objects are prefixed (rule group 8): dim_ dimensions, fact_ facts,
-- agg_ aggregates (materialised views over the facts).
-- Facts reference dimensions by enforced FKs (rule group 2). The source row id is
-- kept as a degenerate key without an FK, so the marts can be loaded from a replica
-- and an erased source row never blocks or rewrites history. Dimensions carry
-- lookup codes copied from the source (not free text) and no direct identifiers.
-- =============================================================================
SET app.current_user_id = '1';

-- Calendar dimension; id is the yyyymmdd smart key (the one non-identity surrogate).
CREATE TABLE dim_date (
    id            bigint      PRIMARY KEY,
    calendar_date date        NOT NULL,
    year_number   smallint    NOT NULL,
    quarter_number smallint   NOT NULL,
    month_number  smallint    NOT NULL,
    month_start   date        NOT NULL,
    iso_week      smallint    NOT NULL,
    day_of_week   smallint    NOT NULL,
    is_weekend    boolean     NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    created_by    bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_dim_date_calendar_date UNIQUE (calendar_date),
    CONSTRAINT ck_dim_date_smart_key CHECK (id = to_char(calendar_date, 'YYYYMMDD')::bigint)
);
INSERT INTO dim_date (id, calendar_date, year_number, quarter_number, month_number, month_start, iso_week, day_of_week, is_weekend)
SELECT to_char(d, 'YYYYMMDD')::bigint, d, extract(year FROM d), extract(quarter FROM d), extract(month FROM d),
       date_trunc('month', d)::date, extract(week FROM d), extract(isodow FROM d), extract(isodow FROM d) IN (6, 7)
FROM generate_series(DATE '2015-01-01', DATE '2035-12-31', interval '1 day') g(d);
CALL make_append_only('dim_date');

-- Location (type 1: corrected in place).
CREATE TABLE dim_location (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    city_id        bigint       NOT NULL,
    city_name      varchar(150) NOT NULL,
    state_name     varchar(150) NOT NULL,
    country_code   varchar(2)   NOT NULL,
    created_at     timestamptz  NOT NULL DEFAULT now(),
    created_by     bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at     timestamptz  NOT NULL DEFAULT now(),
    updated_by     bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_dim_location_city_id UNIQUE (city_id)
);

-- Organisation (type 2: a new version per change of industry, size, verification or HQ).
CREATE TABLE dim_organisation (
    id                       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organisation_id          bigint       NOT NULL,
    display_name             varchar(250) NOT NULL,
    organisation_type_code   varchar(50)  NOT NULL,
    industry_code            varchar(50),
    company_size_band_code   varchar(50),
    verification_status_code varchar(50)  NOT NULL,
    hq_dim_location_id       bigint REFERENCES dim_location (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    valid_from               timestamptz  NOT NULL,
    valid_to                 timestamptz,
    is_current               boolean      NOT NULL,
    created_at               timestamptz  NOT NULL DEFAULT now(),
    created_by               bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at               timestamptz  NOT NULL DEFAULT now(),
    updated_by               bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_dim_organisation_date_range CHECK (valid_to > valid_from)
);
CREATE INDEX idx_dim_organisation_organisation_id ON dim_organisation (organisation_id, valid_from);

-- Candidate (type 2), banded: no name, contact or exact salary leaves the transactional side.
CREATE TABLE dim_candidate (
    id                       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id     bigint       NOT NULL,
    dim_location_id          bigint REFERENCES dim_location (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    experience_band_code     varchar(20)  NOT NULL,
    highest_qualification_code varchar(50),
    is_fresher               boolean      NOT NULL,
    profile_completion_pct   numeric(5,2) NOT NULL,
    registered_date_id       bigint       NOT NULL REFERENCES dim_date (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    valid_from               timestamptz  NOT NULL,
    valid_to                 timestamptz,
    is_current               boolean      NOT NULL,
    created_at               timestamptz  NOT NULL DEFAULT now(),
    created_by               bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at               timestamptz  NOT NULL DEFAULT now(),
    updated_by               bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_dim_candidate_profile_completion_pct CHECK (profile_completion_pct BETWEEN 0 AND 100),
    CONSTRAINT ck_dim_candidate_date_range CHECK (valid_to > valid_from)
);
CREATE INDEX idx_dim_candidate_candidate_profile_id ON dim_candidate (candidate_profile_id, valid_from);

-- Job requirement (type 1: attributes as last loaded).
CREATE TABLE dim_job_requirement (
    id                     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_requirement_id     bigint      NOT NULL,
    dim_organisation_id    bigint      NOT NULL REFERENCES dim_organisation (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    dim_location_id        bigint REFERENCES dim_location (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    job_role_code          varchar(50),
    industry_code          varchar(50),
    employment_type_code   varchar(50) NOT NULL,
    work_mode_code         varchar(50) NOT NULL,
    salary_band_code       varchar(20),
    is_open_to_consultants boolean     NOT NULL,
    created_at             timestamptz NOT NULL DEFAULT now(),
    created_by             bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at             timestamptz NOT NULL DEFAULT now(),
    updated_by             bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_dim_job_requirement_job_requirement_id UNIQUE (job_requirement_id)
);

-- -----------------------------------------------------------------------------
-- Facts
-- -----------------------------------------------------------------------------
-- Hiring funnel, accumulating snapshot: one row per application, milestone dates filled as it moves.
CREATE TABLE fact_application (
    id                      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    application_id          bigint      NOT NULL,
    dim_job_requirement_id  bigint      NOT NULL REFERENCES dim_job_requirement (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    dim_candidate_id        bigint      NOT NULL REFERENCES dim_candidate (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    dim_organisation_id     bigint      NOT NULL REFERENCES dim_organisation (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    applied_date_id         bigint      NOT NULL REFERENCES dim_date (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    shortlisted_date_id     bigint REFERENCES dim_date (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    interviewed_date_id     bigint REFERENCES dim_date (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    offered_date_id         bigint REFERENCES dim_date (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    joined_date_id          bigint REFERENCES dim_date (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    rejected_date_id        bigint REFERENCES dim_date (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    current_stage_code      varchar(50) NOT NULL,
    application_source_code varchar(50) NOT NULL,
    days_to_shortlist       integer,
    days_to_hire            integer,
    created_at              timestamptz NOT NULL DEFAULT now(),
    created_by              bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at              timestamptz NOT NULL DEFAULT now(),
    updated_by              bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_fact_application_application_id UNIQUE (application_id),
    CONSTRAINT ck_fact_application_durations CHECK (days_to_shortlist >= 0 AND days_to_hire >= 0)
);
CREATE INDEX idx_fact_application_dim_organisation_id ON fact_application (dim_organisation_id, applied_date_id);
CREATE INDEX idx_fact_application_dim_job_requirement_id ON fact_application (dim_job_requirement_id);

-- Posting and fill, accumulating snapshot: one row per job requirement.
CREATE TABLE fact_job_posting (
    id                     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_requirement_id     bigint      NOT NULL,
    dim_job_requirement_id bigint      NOT NULL REFERENCES dim_job_requirement (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    dim_organisation_id    bigint      NOT NULL REFERENCES dim_organisation (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    posted_date_id         bigint      NOT NULL REFERENCES dim_date (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    published_date_id      bigint REFERENCES dim_date (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    filled_date_id         bigint REFERENCES dim_date (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    closed_date_id         bigint REFERENCES dim_date (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    positions_opened       integer     NOT NULL,
    positions_filled       integer     NOT NULL DEFAULT 0,
    application_count      integer     NOT NULL DEFAULT 0,
    days_to_fill           integer,
    created_at             timestamptz NOT NULL DEFAULT now(),
    created_by             bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at             timestamptz NOT NULL DEFAULT now(),
    updated_by             bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_fact_job_posting_job_requirement_id UNIQUE (job_requirement_id),
    CONSTRAINT ck_fact_job_posting_counts CHECK (positions_opened > 0 AND positions_filled BETWEEN 0 AND positions_opened
                                                 AND application_count >= 0 AND days_to_fill >= 0)
);
CREATE INDEX idx_fact_job_posting_dim_organisation_id ON fact_job_posting (dim_organisation_id, posted_date_id);

-- Profile views and downloads (transaction grain, append-only).
CREATE TABLE fact_profile_engagement (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    engagement_kind     varchar(10) NOT NULL,
    dim_candidate_id    bigint      NOT NULL REFERENCES dim_candidate (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    dim_organisation_id bigint REFERENCES dim_organisation (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    event_date_id       bigint      NOT NULL REFERENCES dim_date (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    credits_charged     integer     NOT NULL DEFAULT 0,
    created_at          timestamptz NOT NULL DEFAULT now(),
    created_by          bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_fact_profile_engagement_engagement_kind CHECK (engagement_kind IN ('view', 'download')),
    CONSTRAINT ck_fact_profile_engagement_credits_charged CHECK (credits_charged >= 0)
);
CREATE INDEX idx_fact_profile_engagement_dim_organisation_id ON fact_profile_engagement (dim_organisation_id, event_date_id);
CALL make_append_only('fact_profile_engagement');

-- Outreach, one row per recipient.
CREATE TABLE fact_outreach (
    id                    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    outreach_recipient_id bigint      NOT NULL,
    dim_candidate_id      bigint      NOT NULL REFERENCES dim_candidate (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    dim_organisation_id   bigint REFERENCES dim_organisation (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    sent_date_id          bigint REFERENCES dim_date (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    channel_code          varchar(50) NOT NULL,
    is_delivered          boolean     NOT NULL DEFAULT false,
    is_responded          boolean     NOT NULL DEFAULT false,
    is_via_consultant     boolean     NOT NULL,
    created_at            timestamptz NOT NULL DEFAULT now(),
    created_by            bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at            timestamptz NOT NULL DEFAULT now(),
    updated_by            bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_fact_outreach_outreach_recipient_id UNIQUE (outreach_recipient_id)
);
CREATE INDEX idx_fact_outreach_dim_organisation_id ON fact_outreach (dim_organisation_id, sent_date_id);

-- Consultant sourcing requests and their outcome.
CREATE TABLE fact_sourcing_request (
    id                     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sourcing_request_id    bigint       NOT NULL,
    dim_job_requirement_id bigint       NOT NULL REFERENCES dim_job_requirement (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    requested_date_id      bigint       NOT NULL REFERENCES dim_date (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    decided_date_id        bigint REFERENCES dim_date (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    outcome_code           varchar(50)  NOT NULL,
    hours_to_decision      numeric(10,2),
    created_at             timestamptz  NOT NULL DEFAULT now(),
    created_by             bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at             timestamptz  NOT NULL DEFAULT now(),
    updated_by             bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_fact_sourcing_request_sourcing_request_id UNIQUE (sourcing_request_id),
    CONSTRAINT ck_fact_sourcing_request_hours_to_decision CHECK (hours_to_decision >= 0)
);

-- Money in: one row per payment order (net of refunds).
CREATE TABLE fact_payment (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    payment_order_id    bigint        NOT NULL,
    dim_organisation_id bigint        NOT NULL REFERENCES dim_organisation (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    paid_date_id        bigint        NOT NULL REFERENCES dim_date (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    purpose_code        varchar(50)   NOT NULL,
    paid_amount         numeric(14,2) NOT NULL,
    refunded_amount     numeric(14,2) NOT NULL DEFAULT 0,
    amount_currency_id  bigint        NOT NULL REFERENCES currency (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    credits_purchased   integer       NOT NULL DEFAULT 0,
    created_at          timestamptz   NOT NULL DEFAULT now(),
    created_by          bigint        NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at          timestamptz   NOT NULL DEFAULT now(),
    updated_by          bigint        NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_fact_payment_payment_order_id UNIQUE (payment_order_id),
    CONSTRAINT ck_fact_payment_amounts CHECK (paid_amount > 0 AND refunded_amount BETWEEN 0 AND paid_amount AND credits_purchased >= 0)
);
CREATE INDEX idx_fact_payment_dim_organisation_id ON fact_payment (dim_organisation_id, paid_date_id);

-- Credit movements: one row per wallet ledger entry (append-only like the ledger).
CREATE TABLE fact_wallet_transaction (
    id                     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    wallet_ledger_entry_id bigint      NOT NULL,
    dim_organisation_id    bigint      NOT NULL REFERENCES dim_organisation (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    entry_date_id          bigint      NOT NULL REFERENCES dim_date (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    entry_type_code        varchar(50) NOT NULL,
    credit_delta           integer     NOT NULL,
    created_at             timestamptz NOT NULL DEFAULT now(),
    created_by             bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_fact_wallet_transaction_wallet_ledger_entry_id UNIQUE (wallet_ledger_entry_id),
    CONSTRAINT ck_fact_wallet_transaction_credit_delta CHECK (credit_delta <> 0)
);
CREATE INDEX idx_fact_wallet_transaction_dim_organisation_id ON fact_wallet_transaction (dim_organisation_id, entry_date_id);
CALL make_append_only('fact_wallet_transaction');

-- Gig assignments: fill, earnings and rating.
CREATE TABLE fact_gig_assignment (
    id                     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    gig_assignment_id      bigint        NOT NULL,
    dim_organisation_id    bigint REFERENCES dim_organisation (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    dim_location_id        bigint REFERENCES dim_location (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    window_start_date_id   bigint        NOT NULL REFERENCES dim_date (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    completed_date_id      bigint REFERENCES dim_date (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    assignment_status_code varchar(50)   NOT NULL,
    price_amount           numeric(14,2) NOT NULL,
    earning_amount         numeric(14,2) NOT NULL DEFAULT 0,
    amount_currency_id     bigint        NOT NULL REFERENCES currency (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    rating_score           smallint,
    created_at             timestamptz   NOT NULL DEFAULT now(),
    created_by             bigint        NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at             timestamptz   NOT NULL DEFAULT now(),
    updated_by             bigint        NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_fact_gig_assignment_gig_assignment_id UNIQUE (gig_assignment_id),
    CONSTRAINT ck_fact_gig_assignment_amounts CHECK (price_amount >= 0 AND earning_amount >= 0),
    CONSTRAINT ck_fact_gig_assignment_rating_score CHECK (rating_score BETWEEN 1 AND 5)
);

-- Daily snapshots for the high-volume event streams (one row per day and dimension combination).
CREATE TABLE fact_login_daily (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    event_date_id       bigint      NOT NULL REFERENCES dim_date (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    dim_organisation_id bigint REFERENCES dim_organisation (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    login_outcome_code  varchar(50) NOT NULL,
    attempt_count       integer     NOT NULL,
    distinct_user_count integer     NOT NULL,
    created_at          timestamptz NOT NULL DEFAULT now(),
    created_by          bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at          timestamptz NOT NULL DEFAULT now(),
    updated_by          bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_fact_login_daily_counts CHECK (attempt_count > 0 AND distinct_user_count BETWEEN 0 AND attempt_count)
);

CREATE TABLE fact_notification_daily (
    id                     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    event_date_id          bigint      NOT NULL REFERENCES dim_date (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    notification_type_code varchar(50) NOT NULL,
    channel_code           varchar(50) NOT NULL,
    delivery_status_code   varchar(50) NOT NULL,
    delivery_count         integer     NOT NULL,
    created_at             timestamptz NOT NULL DEFAULT now(),
    created_by             bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at             timestamptz NOT NULL DEFAULT now(),
    updated_by             bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_fact_notification_daily_delivery_count CHECK (delivery_count > 0)
);

CREATE TABLE fact_support_ticket (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    support_ticket_id   bigint        NOT NULL,
    dim_organisation_id bigint REFERENCES dim_organisation (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    opened_date_id      bigint        NOT NULL REFERENCES dim_date (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    resolved_date_id    bigint REFERENCES dim_date (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    category_code       varchar(50)   NOT NULL,
    priority_code       varchar(50)   NOT NULL,
    hours_to_resolve    numeric(10,2),
    created_at          timestamptz   NOT NULL DEFAULT now(),
    created_by          bigint        NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at          timestamptz   NOT NULL DEFAULT now(),
    updated_by          bigint        NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_fact_support_ticket_support_ticket_id UNIQUE (support_ticket_id),
    CONSTRAINT ck_fact_support_ticket_hours_to_resolve CHECK (hours_to_resolve >= 0)
);

-- -----------------------------------------------------------------------------
-- Aggregates: materialised views over the facts, refreshed by the load job.
-- -----------------------------------------------------------------------------
CREATE MATERIALIZED VIEW agg_hiring_funnel_monthly AS
SELECT o.organisation_id, d.month_start,
       count(*)                     AS applied_count,
       count(f.shortlisted_date_id) AS shortlisted_count,
       count(f.interviewed_date_id) AS interviewed_count,
       count(f.offered_date_id)     AS offered_count,
       count(f.joined_date_id)      AS joined_count,
       count(f.rejected_date_id)    AS rejected_count,
       round(avg(f.days_to_hire), 2) AS avg_days_to_hire
FROM fact_application f
JOIN dim_organisation o ON o.id = f.dim_organisation_id
JOIN dim_date d ON d.id = f.applied_date_id
GROUP BY o.organisation_id, d.month_start;
CREATE UNIQUE INDEX uq_agg_hiring_funnel_monthly_organisation_id_month_start ON agg_hiring_funnel_monthly (organisation_id, month_start);

CREATE MATERIALIZED VIEW agg_job_posting_monthly AS
SELECT o.organisation_id, d.month_start,
       count(*)                     AS requirements_posted,
       sum(f.positions_opened)      AS positions_opened,
       sum(f.positions_filled)      AS positions_filled,
       sum(f.application_count)     AS applications,
       round(avg(f.days_to_fill), 2) AS avg_days_to_fill
FROM fact_job_posting f
JOIN dim_organisation o ON o.id = f.dim_organisation_id
JOIN dim_date d ON d.id = f.posted_date_id
GROUP BY o.organisation_id, d.month_start;
CREATE UNIQUE INDEX uq_agg_job_posting_monthly_organisation_id_month_start ON agg_job_posting_monthly (organisation_id, month_start);

CREATE MATERIALIZED VIEW agg_sourcing_monthly AS
SELECT coalesce(e.organisation_id, r.organisation_id) AS organisation_id, coalesce(e.month_start, r.month_start) AS month_start,
       coalesce(e.profile_views, 0) AS profile_views, coalesce(e.profile_downloads, 0) AS profile_downloads,
       coalesce(e.credits_charged, 0) AS credits_charged,
       coalesce(r.outreach_sent, 0) AS outreach_sent, coalesce(r.outreach_delivered, 0) AS outreach_delivered,
       coalesce(r.outreach_responded, 0) AS outreach_responded
FROM (SELECT o.organisation_id, d.month_start,
             count(*) FILTER (WHERE f.engagement_kind = 'view')     AS profile_views,
             count(*) FILTER (WHERE f.engagement_kind = 'download') AS profile_downloads,
             sum(f.credits_charged)                                 AS credits_charged
      FROM fact_profile_engagement f JOIN dim_organisation o ON o.id = f.dim_organisation_id JOIN dim_date d ON d.id = f.event_date_id
      GROUP BY o.organisation_id, d.month_start) e
FULL JOIN (SELECT o.organisation_id, d.month_start, count(*) AS outreach_sent,
                  count(*) FILTER (WHERE f.is_delivered) AS outreach_delivered, count(*) FILTER (WHERE f.is_responded) AS outreach_responded
           FROM fact_outreach f JOIN dim_organisation o ON o.id = f.dim_organisation_id JOIN dim_date d ON d.id = f.sent_date_id
           GROUP BY o.organisation_id, d.month_start) r
  ON r.organisation_id = e.organisation_id AND r.month_start = e.month_start;
CREATE UNIQUE INDEX uq_agg_sourcing_monthly_organisation_id_month_start ON agg_sourcing_monthly (organisation_id, month_start);

CREATE MATERIALIZED VIEW agg_revenue_monthly AS
SELECT o.organisation_id, d.month_start, f.amount_currency_id, f.purpose_code,
       sum(f.paid_amount)       AS paid_amount,
       sum(f.refunded_amount)   AS refunded_amount,
       sum(f.credits_purchased) AS credits_purchased
FROM fact_payment f
JOIN dim_organisation o ON o.id = f.dim_organisation_id
JOIN dim_date d ON d.id = f.paid_date_id
GROUP BY o.organisation_id, d.month_start, f.amount_currency_id, f.purpose_code;
CREATE UNIQUE INDEX uq_agg_revenue_monthly_org_month_currency_purpose ON agg_revenue_monthly (organisation_id, month_start, amount_currency_id, purpose_code);

-- -----------------------------------------------------------------------------
-- Classification and nullability justification (rule groups 5, 6)
-- -----------------------------------------------------------------------------
COMMENT ON COLUMN dim_date.calendar_date            IS 'class=Public';
COMMENT ON COLUMN dim_date.year_number              IS 'class=Public';
COMMENT ON COLUMN dim_date.quarter_number           IS 'class=Public';
COMMENT ON COLUMN dim_date.month_number             IS 'class=Public';
COMMENT ON COLUMN dim_date.month_start              IS 'class=Public';
COMMENT ON COLUMN dim_date.iso_week                 IS 'class=Public';
COMMENT ON COLUMN dim_date.day_of_week              IS 'class=Public; ISO 1=Monday..7=Sunday';
COMMENT ON COLUMN dim_location.city_name            IS 'class=Public; copied from city at load';
COMMENT ON COLUMN dim_location.state_name           IS 'class=Public';
COMMENT ON COLUMN dim_location.country_code         IS 'class=Public; ISO 3166-1 alpha-2';
COMMENT ON COLUMN dim_organisation.display_name     IS 'class=Internal; trade name, else legal name, at load';
COMMENT ON COLUMN dim_organisation.organisation_type_code IS 'class=Internal; lookup code copied at load';
COMMENT ON COLUMN dim_organisation.industry_code    IS 'class=Internal; null=industry not stated';
COMMENT ON COLUMN dim_organisation.company_size_band_code IS 'class=Internal; null=size not stated';
COMMENT ON COLUMN dim_organisation.verification_status_code IS 'class=Internal';
COMMENT ON COLUMN dim_organisation.hq_dim_location_id IS 'class=Internal; null=no headquarters recorded';
COMMENT ON COLUMN dim_organisation.valid_from       IS 'class=Internal; SCD type 2 version start';
COMMENT ON COLUMN dim_organisation.valid_to         IS 'class=Internal; null=current version';
COMMENT ON COLUMN dim_candidate.dim_location_id     IS 'class=Internal; null=candidate city unknown';
COMMENT ON COLUMN dim_candidate.experience_band_code IS 'class=Internal; banded years of experience (0_1, 1_3, 3_5, 5_10, 10_plus)';
COMMENT ON COLUMN dim_candidate.highest_qualification_code IS 'class=Internal; null=no education recorded';
COMMENT ON COLUMN dim_candidate.profile_completion_pct IS 'class=Internal; 0..100';
COMMENT ON COLUMN dim_candidate.valid_from          IS 'class=Internal; SCD type 2 version start';
COMMENT ON COLUMN dim_candidate.valid_to            IS 'class=Internal; null=current version';
COMMENT ON COLUMN dim_job_requirement.dim_location_id IS 'class=Internal; null=remote or no primary location';
COMMENT ON COLUMN dim_job_requirement.job_role_code IS 'class=Internal; null=role not mapped';
COMMENT ON COLUMN dim_job_requirement.industry_code IS 'class=Internal; null=industry not stated';
COMMENT ON COLUMN dim_job_requirement.employment_type_code IS 'class=Internal';
COMMENT ON COLUMN dim_job_requirement.work_mode_code IS 'class=Internal';
COMMENT ON COLUMN dim_job_requirement.salary_band_code IS 'class=Internal; null=salary not disclosed';
COMMENT ON COLUMN fact_application.application_id   IS 'class=Internal; degenerate key: source application id (no FK, see header)';
COMMENT ON COLUMN fact_application.shortlisted_date_id IS 'class=Internal; null=not shortlisted (yet)';
COMMENT ON COLUMN fact_application.interviewed_date_id IS 'class=Internal; null=not interviewed (yet)';
COMMENT ON COLUMN fact_application.offered_date_id  IS 'class=Internal; null=no offer (yet)';
COMMENT ON COLUMN fact_application.joined_date_id   IS 'class=Internal; null=not joined (yet)';
COMMENT ON COLUMN fact_application.rejected_date_id IS 'class=Internal; null=not rejected';
COMMENT ON COLUMN fact_application.current_stage_code IS 'class=Internal';
COMMENT ON COLUMN fact_application.application_source_code IS 'class=Internal';
COMMENT ON COLUMN fact_application.days_to_shortlist IS 'class=Internal; null=not shortlisted';
COMMENT ON COLUMN fact_application.days_to_hire     IS 'class=Internal; applied to joined; null=not joined';
COMMENT ON COLUMN fact_job_posting.job_requirement_id IS 'class=Internal; degenerate key: source requirement id';
COMMENT ON COLUMN fact_job_posting.published_date_id IS 'class=Internal; null=never published';
COMMENT ON COLUMN fact_job_posting.filled_date_id   IS 'class=Internal; null=not filled';
COMMENT ON COLUMN fact_job_posting.closed_date_id   IS 'class=Internal; null=still open';
COMMENT ON COLUMN fact_job_posting.positions_opened IS 'class=Internal';
COMMENT ON COLUMN fact_job_posting.positions_filled IS 'class=Internal';
COMMENT ON COLUMN fact_job_posting.application_count IS 'class=Internal';
COMMENT ON COLUMN fact_job_posting.days_to_fill     IS 'class=Internal; published to filled; null=not filled';
COMMENT ON COLUMN fact_profile_engagement.engagement_kind IS 'class=Internal; view or download';
COMMENT ON COLUMN fact_profile_engagement.dim_organisation_id IS 'class=Internal; null=viewer without organisation (freelance consultant)';
COMMENT ON COLUMN fact_profile_engagement.credits_charged IS 'class=Internal; 0=covered by plan entitlement';
COMMENT ON COLUMN fact_outreach.outreach_recipient_id IS 'class=Internal; degenerate key: source recipient id';
COMMENT ON COLUMN fact_outreach.dim_organisation_id IS 'class=Internal; null=sender without organisation (freelance consultant)';
COMMENT ON COLUMN fact_outreach.sent_date_id        IS 'class=Internal; null=not sent yet';
COMMENT ON COLUMN fact_outreach.channel_code        IS 'class=Internal';
COMMENT ON COLUMN fact_sourcing_request.sourcing_request_id IS 'class=Internal; degenerate key: source request id';
COMMENT ON COLUMN fact_sourcing_request.decided_date_id IS 'class=Internal; null=undecided';
COMMENT ON COLUMN fact_sourcing_request.outcome_code IS 'class=Internal; sourcing_request_status code';
COMMENT ON COLUMN fact_sourcing_request.hours_to_decision IS 'class=Internal; null=undecided';
COMMENT ON COLUMN fact_payment.payment_order_id     IS 'class=Internal; degenerate key: source order id';
COMMENT ON COLUMN fact_payment.purpose_code         IS 'class=Internal';
COMMENT ON COLUMN fact_payment.paid_amount          IS 'class=Internal';
COMMENT ON COLUMN fact_payment.refunded_amount      IS 'class=Internal';
COMMENT ON COLUMN fact_payment.credits_purchased    IS 'class=Internal; 0 for subscription orders';
COMMENT ON COLUMN fact_wallet_transaction.wallet_ledger_entry_id IS 'class=Internal; degenerate key: source ledger entry id';
COMMENT ON COLUMN fact_wallet_transaction.entry_type_code IS 'class=Internal';
COMMENT ON COLUMN fact_wallet_transaction.credit_delta IS 'class=Internal';
COMMENT ON COLUMN fact_gig_assignment.gig_assignment_id IS 'class=Internal; degenerate key: source assignment id';
COMMENT ON COLUMN fact_gig_assignment.dim_organisation_id IS 'class=Internal; null=individual requester';
COMMENT ON COLUMN fact_gig_assignment.dim_location_id IS 'class=Internal; null=remote gig';
COMMENT ON COLUMN fact_gig_assignment.completed_date_id IS 'class=Internal; null=not completed';
COMMENT ON COLUMN fact_gig_assignment.assignment_status_code IS 'class=Internal';
COMMENT ON COLUMN fact_gig_assignment.price_amount  IS 'class=Internal';
COMMENT ON COLUMN fact_gig_assignment.earning_amount IS 'class=Internal; reconciled earnings reported so far';
COMMENT ON COLUMN fact_gig_assignment.rating_score  IS 'class=Internal; null=not rated';
COMMENT ON COLUMN fact_login_daily.dim_organisation_id IS 'class=Internal; null=users without organisation';
COMMENT ON COLUMN fact_login_daily.login_outcome_code IS 'class=Internal';
COMMENT ON COLUMN fact_login_daily.attempt_count    IS 'class=Internal';
COMMENT ON COLUMN fact_login_daily.distinct_user_count IS 'class=Internal';
COMMENT ON COLUMN fact_notification_daily.notification_type_code IS 'class=Internal';
COMMENT ON COLUMN fact_notification_daily.channel_code IS 'class=Internal';
COMMENT ON COLUMN fact_notification_daily.delivery_status_code IS 'class=Internal';
COMMENT ON COLUMN fact_notification_daily.delivery_count IS 'class=Internal';
COMMENT ON COLUMN fact_support_ticket.support_ticket_id IS 'class=Internal; degenerate key: source ticket id';
COMMENT ON COLUMN fact_support_ticket.dim_organisation_id IS 'class=Internal; null=raised by an individual';
COMMENT ON COLUMN fact_support_ticket.resolved_date_id IS 'class=Internal; null=unresolved';
COMMENT ON COLUMN fact_support_ticket.category_code IS 'class=Internal';
COMMENT ON COLUMN fact_support_ticket.priority_code IS 'class=Internal';
COMMENT ON COLUMN fact_support_ticket.hours_to_resolve IS 'class=Internal; null=unresolved';

CALL attach_audit_triggers();
RESET app.current_user_id;
