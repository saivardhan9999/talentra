-- =============================================================================
-- Talentra :: 12_notifications.sql
-- Module: Notifications, preferences and community — team, Phase 4
-- Notification and job-alert preferences, language and privacy preferences,
-- notifications and their per-channel deliveries, community posts and reactions,
-- support tickets, FAQs and referral events.
-- Messaging provider boundary (docket §6): the platform stores the template
-- reference, a short summary and the delivery status reported by the provider;
-- message bodies stay with the provider.
-- =============================================================================
SET app.current_user_id = '1';

CALL create_lookup_table('notification_type',            'application_update, job_alert, interview_reminder, outreach_message, sourcing_request, payment, security, system');
CALL create_lookup_table('notification_delivery_status', 'SYSTEM: 1=queued, 2=sent, 3=delivered, 4=read, 5=failed, 6=suppressed');
CALL create_lookup_table('alert_frequency',              'instant, daily, weekly');
CALL create_lookup_table('community_post_status',        'SYSTEM: 1=published; hidden, removed');
CALL create_lookup_table('reaction_type',                'like, celebrate, insightful, support');
CALL create_lookup_table('support_ticket_category',      'account, billing, job_posting, application, technical, abuse_report, other');
CALL create_lookup_table('support_ticket_status',        'SYSTEM: 1=open; in_progress, waiting_on_user, resolved, closed');
CALL create_lookup_table('support_ticket_priority',      'low, normal, high, urgent');
CALL create_lookup_table('faq_category',                 'candidates, employers, consultants, billing, gig');
CALL create_lookup_table('referral_event_type',          'invited, registered, applied, hired, rewarded');

CALL seed_lookups('notification_type', ARRAY['application_update|Application update', 'job_alert|Job alert', 'interview_reminder|Interview reminder',
    'outreach_message|Message from a recruiter', 'sourcing_request|Sourcing request', 'payment|Payment', 'security|Security', 'system|System']);
CALL seed_lookups('notification_delivery_status', ARRAY['queued|Queued', 'sent|Sent', 'delivered|Delivered', 'read|Read', 'failed|Failed', 'suppressed|Suppressed by preference']);
CALL seed_lookups('alert_frequency', ARRAY['instant|Instant', 'daily|Daily digest', 'weekly|Weekly digest']);
CALL seed_lookups('community_post_status', ARRAY['published|Published', 'hidden|Hidden', 'removed|Removed']);
CALL seed_lookups('reaction_type', ARRAY['like|Like', 'celebrate|Celebrate', 'insightful|Insightful', 'support|Support']);
CALL seed_lookups('support_ticket_category', ARRAY['account|Account', 'billing|Billing', 'job_posting|Job posting', 'application|Application',
    'technical|Technical', 'abuse_report|Abuse report', 'other|Other']);
CALL seed_lookups('support_ticket_status', ARRAY['open|Open', 'in_progress|In progress', 'waiting_on_user|Waiting on user', 'resolved|Resolved', 'closed|Closed']);
CALL seed_lookups('support_ticket_priority', ARRAY['low|Low', 'normal|Normal', 'high|High', 'urgent|Urgent']);
CALL seed_lookups('faq_category', ARRAY['candidates|Candidates', 'employers|Employers', 'consultants|Consultants', 'billing|Billing', 'gig|Gig work']);
CALL seed_lookups('referral_event_type', ARRAY['invited|Invited', 'registered|Registered', 'applied|Applied', 'hired|Hired', 'rewarded|Rewarded']);

-- -----------------------------------------------------------------------------
-- Preferences. Channels reuse outreach_channel (email, sms, whatsapp, in_app).
-- -----------------------------------------------------------------------------
-- Language and privacy preferences: one row per user (1 : 0..1); defaults apply without a row.
CREATE TABLE user_preference (
    id                          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_account_id             bigint      NOT NULL REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    preferred_language_id       bigint      NOT NULL REFERENCES language (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    timezone_name               varchar(64) NOT NULL DEFAULT 'Asia/Kolkata',
    is_searchable_by_employers  boolean     NOT NULL DEFAULT true,
    show_contact_to_employers   boolean     NOT NULL DEFAULT false,
    allow_recruiter_outreach    boolean     NOT NULL DEFAULT true,
    allow_profile_download      boolean     NOT NULL DEFAULT true,
    created_at                  timestamptz NOT NULL DEFAULT now(),
    created_by                  bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at                  timestamptz NOT NULL DEFAULT now(),
    updated_by                  bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_user_preference_timezone_name CHECK (timezone_name ~ '^[A-Za-z_]+(/[A-Za-z0-9_+-]+)*$')
);
CREATE UNIQUE INDEX uq_user_preference_user_account_id ON user_preference (user_account_id);

-- Per user, notification type and channel: on or off. No row = the type's default.
CREATE TABLE notification_preference (
    id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_account_id      bigint      NOT NULL REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    notification_type_id bigint      NOT NULL REFERENCES notification_type (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    outreach_channel_id  bigint      NOT NULL REFERENCES outreach_channel (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    is_enabled           boolean     NOT NULL,
    created_at           timestamptz NOT NULL DEFAULT now(),
    created_by           bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at           timestamptz NOT NULL DEFAULT now(),
    updated_by           bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_notification_preference_user_type_channel UNIQUE (user_account_id, notification_type_id, outreach_channel_id)
);

-- A candidate's saved search that produces job alerts.
CREATE TABLE job_alert (
    id                        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id      bigint        NOT NULL REFERENCES candidate_profile (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    name                      varchar(100)  NOT NULL,
    keywords                  varchar(200),
    city_id                   bigint REFERENCES city (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    job_role_id               bigint REFERENCES job_role (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    industry_id               bigint REFERENCES industry (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    employment_type_id        bigint REFERENCES employment_type (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    work_mode_id              bigint REFERENCES work_mode (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    min_salary_amount         numeric(14,2),
    min_salary_currency_id    bigint REFERENCES currency (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    alert_frequency_id        bigint        NOT NULL REFERENCES alert_frequency (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    is_active                 boolean       NOT NULL DEFAULT true,
    last_sent_at              timestamptz,
    created_at                timestamptz   NOT NULL DEFAULT now(),
    created_by                bigint        NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at                timestamptz   NOT NULL DEFAULT now(),
    updated_by                bigint        NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_job_alert_min_salary CHECK ((min_salary_amount IS NULL) = (min_salary_currency_id IS NULL) AND min_salary_amount > 0),
    CONSTRAINT ck_job_alert_has_criterion CHECK (num_nonnulls(keywords, city_id, job_role_id, industry_id, employment_type_id, work_mode_id, min_salary_amount) >= 1)
);
CREATE INDEX idx_job_alert_candidate_profile_id ON job_alert (candidate_profile_id);
CREATE INDEX idx_job_alert_alert_frequency_id ON job_alert (alert_frequency_id, last_sent_at) WHERE is_active;

-- -----------------------------------------------------------------------------
-- Notifications: one per event per recipient; one delivery per channel tried.
-- Deliveries are the high-volume write path (partitioned monthly by queued_at).
-- -----------------------------------------------------------------------------
CREATE TABLE notification (
    id                         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    recipient_user_account_id  bigint       NOT NULL REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    notification_type_id       bigint       NOT NULL REFERENCES notification_type (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    job_alert_id               bigint REFERENCES job_alert (id) ON UPDATE RESTRICT ON DELETE SET NULL,
    template_ref               varchar(100) NOT NULL,
    summary                    varchar(300) NOT NULL,
    target_table               varchar(63),
    target_record_id           bigint,
    read_at                    timestamptz,
    created_at                 timestamptz  NOT NULL DEFAULT now(),
    created_by                 bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at                 timestamptz  NOT NULL DEFAULT now(),
    updated_by                 bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_notification_target CHECK ((target_table IS NULL) = (target_record_id IS NULL) AND target_table ~ '^[a-z][a-z0-9_]*$'),
    CONSTRAINT ck_notification_date_range CHECK (read_at >= created_at)
);
CREATE INDEX idx_notification_recipient_user_account_id ON notification (recipient_user_account_id, created_at DESC);

CREATE TABLE notification_delivery (
    id                              bigint GENERATED ALWAYS AS IDENTITY,
    notification_id                 bigint       NOT NULL REFERENCES notification (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    outreach_channel_id             bigint       NOT NULL REFERENCES outreach_channel (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    notification_delivery_status_id bigint       NOT NULL DEFAULT 1 REFERENCES notification_delivery_status (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    provider_message_ref            varchar(100),
    queued_at                       timestamptz  NOT NULL DEFAULT now(),
    sent_at                         timestamptz,
    delivered_at                    timestamptz,
    failed_at                       timestamptz,
    failure_code                    varchar(50),
    created_at                      timestamptz  NOT NULL DEFAULT now(),
    created_by                      bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at                      timestamptz  NOT NULL DEFAULT now(),
    updated_by                      bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT pk_notification_delivery PRIMARY KEY (id, queued_at),
    CONSTRAINT ck_notification_delivery_date_range CHECK (sent_at >= queued_at AND delivered_at >= sent_at AND failed_at >= queued_at)
) PARTITION BY RANGE (queued_at);
CREATE INDEX idx_notification_delivery_notification_id ON notification_delivery (notification_id);
CALL create_monthly_partitions('notification_delivery', DATE '2025-01-01', DATE '2027-01-01');

-- -----------------------------------------------------------------------------
-- Community
-- -----------------------------------------------------------------------------
CREATE TABLE community_post (
    id                        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    author_user_account_id    bigint        NOT NULL REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    parent_community_post_id  bigint REFERENCES community_post (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    title                     varchar(200),
    body                      varchar(4000) NOT NULL,
    body_language_id          bigint REFERENCES language (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    community_post_status_id  bigint        NOT NULL DEFAULT 1 REFERENCES community_post_status (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    published_at              timestamptz   NOT NULL DEFAULT now(),
    deleted_at                timestamptz,
    created_at                timestamptz   NOT NULL DEFAULT now(),
    created_by                bigint        NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at                timestamptz   NOT NULL DEFAULT now(),
    updated_by                bigint        NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    -- a top-level post has a title; a reply does not
    CONSTRAINT ck_community_post_title CHECK ((parent_community_post_id IS NULL) = (title IS NOT NULL)),
    CONSTRAINT ck_community_post_not_own_parent CHECK (parent_community_post_id <> id)
);
CREATE INDEX idx_community_post_parent_community_post_id ON community_post (parent_community_post_id) WHERE parent_community_post_id IS NOT NULL;
CREATE INDEX idx_community_post_author_user_account_id ON community_post (author_user_account_id, published_at DESC);
CREATE VIEW v_community_post AS SELECT * FROM community_post WHERE deleted_at IS NULL;

CREATE TABLE community_reaction (
    id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    community_post_id bigint      NOT NULL REFERENCES community_post (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    user_account_id   bigint      NOT NULL REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    reaction_type_id  bigint      NOT NULL REFERENCES reaction_type (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    created_at        timestamptz NOT NULL DEFAULT now(),
    created_by        bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at        timestamptz NOT NULL DEFAULT now(),
    updated_by        bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_community_reaction_community_post_id_user_account_id UNIQUE (community_post_id, user_account_id)
);
CREATE INDEX idx_community_reaction_user_account_id ON community_reaction (user_account_id);

-- -----------------------------------------------------------------------------
-- Support tickets and FAQs
-- -----------------------------------------------------------------------------
CREATE TABLE support_ticket (
    id                          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ticket_number               varchar(20)  NOT NULL,
    raised_by_user_account_id   bigint       NOT NULL REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    organisation_id             bigint REFERENCES organisation (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    support_ticket_category_id  bigint       NOT NULL REFERENCES support_ticket_category (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    support_ticket_priority_id  bigint       NOT NULL REFERENCES support_ticket_priority (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    support_ticket_status_id    bigint       NOT NULL DEFAULT 1 REFERENCES support_ticket_status (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    subject                     varchar(200) NOT NULL,
    assigned_to_user_account_id bigint REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    opened_at                   timestamptz  NOT NULL DEFAULT now(),
    resolved_at                 timestamptz,
    closed_at                   timestamptz,
    created_at                  timestamptz  NOT NULL DEFAULT now(),
    created_by                  bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at                  timestamptz  NOT NULL DEFAULT now(),
    updated_by                  bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_support_ticket_ticket_number UNIQUE (ticket_number),
    CONSTRAINT ck_support_ticket_date_range CHECK (resolved_at >= opened_at AND closed_at >= opened_at)
);
CREATE INDEX idx_support_ticket_raised_by_user_account_id ON support_ticket (raised_by_user_account_id, opened_at DESC);
CREATE INDEX idx_support_ticket_assigned_to_user_account_id ON support_ticket (assigned_to_user_account_id, support_ticket_status_id)
    WHERE assigned_to_user_account_id IS NOT NULL;

-- Conversation on a ticket; append-only (a correction is a new message).
CREATE TABLE support_ticket_message (
    id                     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    support_ticket_id      bigint        NOT NULL REFERENCES support_ticket (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    author_user_account_id bigint        NOT NULL REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    body                   varchar(4000) NOT NULL,
    is_internal_note       boolean       NOT NULL DEFAULT false,
    created_at             timestamptz   NOT NULL DEFAULT now(),
    created_by             bigint        NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
CREATE INDEX idx_support_ticket_message_support_ticket_id ON support_ticket_message (support_ticket_id, created_at);
CALL make_append_only('support_ticket_message');

-- FAQ text is platform content, so question and answer are UI label keys (rule group 7).
CREATE TABLE faq (
    id                    bigint GENERATED BY DEFAULT AS IDENTITY (START WITH 1000) PRIMARY KEY,
    faq_category_id       bigint      NOT NULL REFERENCES faq_category (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    question_label_key_id bigint      NOT NULL REFERENCES ui_label_key (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    answer_label_key_id   bigint      NOT NULL REFERENCES ui_label_key (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    sort_order            integer     NOT NULL DEFAULT 0,
    is_active             boolean     NOT NULL DEFAULT true,
    created_at            timestamptz NOT NULL DEFAULT now(),
    created_by            bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at            timestamptz NOT NULL DEFAULT now(),
    updated_by            bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_faq_question_label_key_id UNIQUE (question_label_key_id),
    CONSTRAINT ck_faq_distinct_keys CHECK (question_label_key_id <> answer_label_key_id)
);
CREATE INDEX idx_faq_faq_category_id ON faq (faq_category_id, sort_order) WHERE is_active;

-- -----------------------------------------------------------------------------
-- Referral events: the history of a Phase 1 referral (invited -> ... -> rewarded).
-- Append-only.
-- -----------------------------------------------------------------------------
CREATE TABLE referral_event (
    id                     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    referral_id            bigint      NOT NULL REFERENCES referral (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    referral_event_type_id bigint      NOT NULL REFERENCES referral_event_type (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    application_id         bigint REFERENCES application (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    occurred_at            timestamptz NOT NULL DEFAULT now(),
    created_at             timestamptz NOT NULL DEFAULT now(),
    created_by             bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
CREATE INDEX idx_referral_event_referral_id ON referral_event (referral_id, occurred_at);
CALL make_append_only('referral_event');

-- -----------------------------------------------------------------------------
-- Classification and nullability justification (rule groups 5, 6)
-- -----------------------------------------------------------------------------
COMMENT ON COLUMN user_preference.timezone_name              IS 'class=Personal; IANA zone name, used for alert and digest times';
COMMENT ON COLUMN job_alert.name                             IS 'class=Personal; candidate''s label for the alert';
COMMENT ON COLUMN job_alert.keywords                         IS 'class=Personal; null=no keyword filter';
COMMENT ON COLUMN job_alert.city_id                          IS 'class=Personal; null=any city';
COMMENT ON COLUMN job_alert.job_role_id                      IS 'class=Internal; null=any role';
COMMENT ON COLUMN job_alert.industry_id                      IS 'class=Internal; null=any industry';
COMMENT ON COLUMN job_alert.employment_type_id               IS 'class=Internal; null=any employment type';
COMMENT ON COLUMN job_alert.work_mode_id                     IS 'class=Internal; null=any work mode';
COMMENT ON COLUMN job_alert.min_salary_amount                IS 'class=Personal; null=no salary floor (never 0 as a sentinel)';
COMMENT ON COLUMN job_alert.min_salary_currency_id           IS 'class=Personal; null exactly when no salary floor';
COMMENT ON COLUMN job_alert.last_sent_at                     IS 'class=Internal; null=never sent';
COMMENT ON COLUMN notification.job_alert_id                  IS 'class=Internal; null=not produced by a job alert';
COMMENT ON COLUMN notification.template_ref                  IS 'class=Internal; provider / in-app template id (body not stored)';
COMMENT ON COLUMN notification.summary                       IS 'class=Personal; short rendered line shown in the in-app list, kept for audit';
COMMENT ON COLUMN notification.target_table                  IS 'class=Internal; what the notification is about; null=general notice';
COMMENT ON COLUMN notification.target_record_id              IS 'class=Internal; id in target_table; null exactly when target_table is null';
COMMENT ON COLUMN notification.read_at                       IS 'class=Internal; null=unread';
COMMENT ON COLUMN notification_delivery.provider_message_ref IS 'class=Internal; provider message id, keys delivery callbacks; null=not handed to the provider yet';
COMMENT ON COLUMN notification_delivery.queued_at            IS 'class=Internal; partition key';
COMMENT ON COLUMN notification_delivery.sent_at              IS 'class=Internal; null=not sent yet';
COMMENT ON COLUMN notification_delivery.delivered_at         IS 'class=Internal; null=not delivered (yet)';
COMMENT ON COLUMN notification_delivery.failed_at            IS 'class=Internal; null=not failed';
COMMENT ON COLUMN notification_delivery.failure_code         IS 'class=Internal; provider error code; null=not failed';
COMMENT ON COLUMN community_post.parent_community_post_id    IS 'class=Public; null=top-level post';
COMMENT ON COLUMN community_post.title                       IS 'class=Public; null=reply (replies have no title)';
COMMENT ON COLUMN community_post.body                        IS 'class=Public; stored once in the language written';
COMMENT ON COLUMN community_post.body_language_id            IS 'class=Public; null=language not detected';
COMMENT ON COLUMN community_post.published_at                IS 'class=Public';
COMMENT ON COLUMN community_post.deleted_at                  IS 'class=Internal; null=not deleted';
COMMENT ON COLUMN support_ticket.ticket_number               IS 'class=Internal; human-readable reference quoted to the user';
COMMENT ON COLUMN support_ticket.organisation_id             IS 'class=Internal; null=raised by an individual, not for an organisation';
COMMENT ON COLUMN support_ticket.subject                     IS 'class=Personal; may name people or accounts';
COMMENT ON COLUMN support_ticket.assigned_to_user_account_id IS 'class=Internal; null=not assigned yet';
COMMENT ON COLUMN support_ticket.opened_at                   IS 'class=Internal';
COMMENT ON COLUMN support_ticket.resolved_at                 IS 'class=Internal; null=not resolved';
COMMENT ON COLUMN support_ticket.closed_at                   IS 'class=Internal; null=not closed';
COMMENT ON COLUMN support_ticket_message.body                IS 'class=Personal; conversation text';
COMMENT ON COLUMN referral_event.application_id              IS 'class=Internal; null=event not tied to an application (invited, registered, rewarded)';
COMMENT ON COLUMN referral_event.occurred_at                 IS 'class=Internal';

CALL attach_audit_triggers();
RESET app.current_user_id;
