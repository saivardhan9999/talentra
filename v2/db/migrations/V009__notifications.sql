-- V009 Notification preferences, job alerts, and the notification outbox.
-- Requirements: FR-NOT-01..05, NFR-REL-03 (no lost notifications: transactional outbox, ADR-010).

CREATE TABLE notification_preference (
    id                        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    app_user_id               bigint NOT NULL REFERENCES app_user (id) ON DELETE CASCADE,
    notification_category_id  smallint NOT NULL REFERENCES notification_category (id) ON DELETE RESTRICT,
    notification_channel_id   smallint NOT NULL REFERENCES notification_channel (id) ON DELETE RESTRICT,
    is_enabled                boolean NOT NULL,
    CONSTRAINT uq_notification_preference_user_category_channel UNIQUE (app_user_id, notification_category_id, notification_channel_id)
);
CALL add_audit_columns('notification_preference');
COMMENT ON TABLE notification_preference IS 'Internal. Only explicit choices are stored; no row means the default (enabled, except marketing which needs consent).';

CREATE TABLE job_alert (
    id                    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id  bigint NOT NULL REFERENCES candidate_profile (id) ON DELETE CASCADE,
    keywords              short_text NOT NULL,
    city_id               integer REFERENCES city (id) ON DELETE RESTRICT,
    min_salary_amount     money_amount,
    salary_currency_id    smallint REFERENCES currency (id) ON DELETE RESTRICT,
    alert_frequency_id    smallint NOT NULL DEFAULT 2 REFERENCES alert_frequency (id) ON DELETE RESTRICT,
    is_active             boolean NOT NULL DEFAULT true,
    last_sent_at          timestamptz,
    CONSTRAINT ck_job_alert_salary_currency CHECK ((min_salary_amount IS NULL) = (salary_currency_id IS NULL))
);
CALL add_audit_columns('job_alert');
CREATE INDEX idx_job_alert_candidate_profile_id ON job_alert (candidate_profile_id);
CREATE INDEX idx_job_alert_due ON job_alert (alert_frequency_id, last_sent_at) WHERE is_active;
COMMENT ON COLUMN job_alert.keywords IS 'Personal. Search words, matched with the job full-text index.';
COMMENT ON COLUMN job_alert.city_id IS 'Internal. NULL: any city.';
COMMENT ON COLUMN job_alert.min_salary_amount IS 'Personal. NULL: no salary filter.';
COMMENT ON COLUMN job_alert.salary_currency_id IS 'Internal. NULL: exactly when there is no salary filter.';
COMMENT ON COLUMN job_alert.last_sent_at IS 'Internal. NULL: never sent yet.';

-- Transactional outbox: business code inserts the notification in the same transaction as the change it reports;
-- delivery workers claim rows with FOR UPDATE SKIP LOCKED. The payload holds template variables, not the message body.
CREATE TABLE notification (
    id                        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    app_user_id               bigint NOT NULL REFERENCES app_user (id) ON DELETE CASCADE,
    notification_category_id  smallint NOT NULL REFERENCES notification_category (id) ON DELETE RESTRICT,
    notification_channel_id   smallint NOT NULL REFERENCES notification_channel (id) ON DELETE RESTRICT,
    template_key              text NOT NULL CHECK (template_key ~ '^[a-z_]+(\.[a-z_]+)+$'),
    payload                   jsonb NOT NULL DEFAULT '{}' CHECK (pg_column_size(payload) <= 2048),
    notification_status_id    smallint NOT NULL DEFAULT 1 REFERENCES notification_status (id) ON DELETE RESTRICT,
    dedupe_key                text CONSTRAINT uq_notification_dedupe_key UNIQUE CHECK (char_length(dedupe_key) <= 200),
    attempt_count             smallint NOT NULL DEFAULT 0 CHECK (attempt_count BETWEEN 0 AND 10),
    queued_at                 timestamptz NOT NULL DEFAULT now(),
    next_attempt_at           timestamptz NOT NULL DEFAULT now(),
    sent_at                   timestamptz,
    delivered_at              timestamptz,
    provider_message_ref      text CONSTRAINT uq_notification_provider_message_ref UNIQUE CHECK (char_length(provider_message_ref) <= 128),
    failure_reason            short_text,
    CONSTRAINT ck_notification_times CHECK (sent_at IS NULL OR sent_at >= queued_at),
    CONSTRAINT ck_notification_delivered CHECK (delivered_at IS NULL OR (sent_at IS NOT NULL AND delivered_at >= sent_at)),
    CONSTRAINT ck_notification_failed CHECK ((notification_status_id = 4) = (failure_reason IS NOT NULL))
);
CALL add_audit_columns('notification');
CREATE INDEX idx_notification_app_user_id ON notification (app_user_id, queued_at DESC);                               -- AP-10 inbox
CREATE INDEX idx_notification_due ON notification (next_attempt_at) WHERE notification_status_id = 1;                  -- AP-13 worker claim
COMMENT ON COLUMN notification.payload IS 'Internal. Template variables (ids, job title); no contact details or message bodies (docket section 6).';
COMMENT ON COLUMN notification.dedupe_key IS 'Internal. Prevents the same event notifying twice, e.g. "application_status:<id>:<status>". NULL: no dedupe needed.';
COMMENT ON COLUMN notification.sent_at IS 'Internal. NULL: not handed to the provider yet.';
COMMENT ON COLUMN notification.delivered_at IS 'Internal. NULL: no delivery receipt (yet, or channel gives none).';
COMMENT ON COLUMN notification.provider_message_ref IS 'Internal. Provider message id, used by delivery callbacks. NULL: not sent yet.';
COMMENT ON COLUMN notification.failure_reason IS 'Internal. NULL: exactly when not failed.';

-- A user's opt-out wins at insert time: the row is kept (evidence) but marked suppressed. Security notices always go.
CREATE FUNCTION notification_apply_preference() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.notification_category_id <> 3 AND EXISTS (
       SELECT 1 FROM notification_preference p
       WHERE p.app_user_id = NEW.app_user_id AND p.notification_category_id = NEW.notification_category_id
         AND p.notification_channel_id = NEW.notification_channel_id AND NOT p.is_enabled) THEN
    NEW.notification_status_id := 5;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_notification_apply_preference BEFORE INSERT ON notification FOR EACH ROW EXECUTE FUNCTION notification_apply_preference();

-- Every status change of an application notifies the candidate (in-app), through the outbox.
CREATE FUNCTION application_notify() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO notification (app_user_id, notification_category_id, notification_channel_id, template_key, payload, dedupe_key,
                            queued_at, next_attempt_at, created_at)
  SELECT p.app_user_id, 2, 4, 'application.status_changed',
         jsonb_build_object('application_id', NEW.id, 'status', NEW.application_status_id),
         'application_status:' || NEW.id || ':' || NEW.application_status_id,
         NEW.status_changed_at, NEW.status_changed_at, NEW.status_changed_at
  FROM candidate_profile p WHERE p.id = NEW.candidate_profile_id
  ON CONFLICT (dedupe_key) DO NOTHING;
  RETURN NULL;
END $$;
CREATE TRIGGER trg_application_notify AFTER UPDATE OF application_status_id ON application
    FOR EACH ROW WHEN (NEW.application_status_id IS DISTINCT FROM OLD.application_status_id) EXECUTE FUNCTION application_notify();
