-- V005 Audit trail and system errors.
-- Requirements: FR-AUD-01..03, NFR-AUD-01..03, docket section 3 (every sensitive action audited), rule group 4 (append-only).
-- These two tables are logs: occurred_at and the actor are their audit columns, so they do not get created_by /
-- updated_by (deviation D-02 in docs/06-physical-model.md).

CREATE TABLE audit_event (
    id                 bigint GENERATED ALWAYS AS IDENTITY,
    occurred_at        timestamptz NOT NULL DEFAULT now(),
    actor_app_user_id  bigint REFERENCES app_user (id) ON DELETE RESTRICT,
    organisation_id    bigint REFERENCES organisation (id) ON DELETE RESTRICT,
    action             text NOT NULL CHECK (action ~ '^[a-z_]+(\.[a-z_]+)+$'),
    entity_table       text NOT NULL CHECK (entity_table ~ '^[a-z_]+$'),
    entity_id          bigint,
    details            jsonb NOT NULL DEFAULT '{}' CHECK (pg_column_size(details) <= 4096),
    PRIMARY KEY (id, occurred_at)
) PARTITION BY RANGE (occurred_at);
COMMENT ON TABLE audit_event IS 'Internal. Append-only, monthly partitions audit_event_pYYYYMM; retention 7 years by dropping partitions (NFR-AUD-03).';
COMMENT ON COLUMN audit_event.actor_app_user_id IS 'Internal. Who did it. NULL: a system process (scheduler, payment webhook, migration).';
COMMENT ON COLUMN audit_event.organisation_id IS 'Internal. Organisation the action belongs to, so account admins see their own trail. NULL: not organisation-scoped.';
COMMENT ON COLUMN audit_event.entity_id IS 'Internal. Row acted on. NULL: the action has no single row (e.g. a refused login attempt).';
COMMENT ON COLUMN audit_event.details IS 'Internal. Changed column names and non-personal context; never personal values (NFR-PRIV-03).';
CREATE INDEX idx_audit_event_actor_app_user_id ON audit_event (actor_app_user_id, occurred_at);
CREATE INDEX idx_audit_event_organisation_id ON audit_event (organisation_id, occurred_at) WHERE organisation_id IS NOT NULL;
CREATE INDEX idx_audit_event_entity ON audit_event (entity_table, entity_id);
CREATE TRIGGER trg_audit_event_append_only BEFORE UPDATE OR DELETE ON audit_event FOR EACH ROW EXECUTE FUNCTION forbid_change();

-- Monthly partitions named <table>_pYYYYMM plus <table>_pdefault (rule group 8). A scheduler calls this monthly.
CREATE PROCEDURE create_month_partitions(p_parent regclass, p_from date, p_months int) LANGUAGE plpgsql AS $$
DECLARE m date; n text := (SELECT relname FROM pg_class WHERE oid = p_parent);
BEGIN
  FOR i IN 0 .. p_months - 1 LOOP
    m := date_trunc('month', p_from)::date + make_interval(months => i);
    EXECUTE format('CREATE TABLE IF NOT EXISTS %I PARTITION OF %s FOR VALUES FROM (%L) TO (%L)',
                   n || '_p' || to_char(m, 'YYYYMM'), p_parent, m, (m + interval '1 month')::date);
  END LOOP;
  EXECUTE format('CREATE TABLE IF NOT EXISTS %I PARTITION OF %s DEFAULT', n || '_pdefault', p_parent);
END $$;
CALL create_month_partitions('audit_event', date '2025-10-01', 24);

-- The one way application code writes audit events (SECURITY DEFINER: the runtime role has no INSERT on the table,
-- so it cannot forge an actor). The actor is always the transaction's user.
CREATE FUNCTION audit_log(p_action text, p_entity_table text, p_entity_id bigint, p_organisation_id bigint DEFAULT NULL,
                          p_details jsonb DEFAULT '{}', p_occurred_at timestamptz DEFAULT now())
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
    INSERT INTO audit_event (occurred_at, actor_app_user_id, organisation_id, action, entity_table, entity_id, details)
    VALUES (p_occurred_at, app_current_user_id(), p_organisation_id, p_action, p_entity_table, p_entity_id, p_details)
$$;

-- Row-level audit for sensitive tables: records the action and the names of the changed columns, not the values.
CREATE FUNCTION audit_row_change() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r jsonb := to_jsonb(coalesce(NEW, OLD));
  changed text[];
BEGIN
  IF TG_OP = 'UPDATE' THEN
    SELECT array_agg(k ORDER BY k) INTO changed
    FROM jsonb_each(to_jsonb(NEW)) n(k, v) WHERE v IS DISTINCT FROM to_jsonb(OLD) -> k AND k NOT IN ('updated_at', 'updated_by', 'last_login_at');
    IF changed IS NULL THEN RETURN NULL; END IF;
  END IF;
  PERFORM audit_log(TG_TABLE_NAME || '.' || lower(TG_OP), TG_TABLE_NAME, (r ->> 'id')::bigint,
                    CASE WHEN TG_TABLE_NAME = 'organisation' THEN (r ->> 'id')::bigint ELSE (r ->> 'organisation_id')::bigint END,
                    CASE WHEN changed IS NULL THEN '{}' ELSE jsonb_build_object('changed', changed) END,
                    CASE WHEN TG_OP = 'DELETE' THEN now() ELSE coalesce((r ->> 'updated_at')::timestamptz, now()) END);
  RETURN NULL;
END $$;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['app_user', 'user_credential', 'user_access_role', 'organisation', 'organisation_member',
                           'organisation_tax_identifier'] LOOP
    EXECUTE format('CREATE TRIGGER trg_%s_audit AFTER INSERT OR UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION audit_row_change()', t, t);
  END LOOP;
END $$;

CREATE TABLE system_error (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    occurred_at   timestamptz NOT NULL DEFAULT now(),
    service_name  short_text NOT NULL,
    error_code    short_text NOT NULL,
    message       medium_text NOT NULL,
    app_user_id   bigint REFERENCES app_user (id) ON DELETE SET NULL,
    context       jsonb NOT NULL DEFAULT '{}' CHECK (pg_column_size(context) <= 8192)
);
CREATE INDEX idx_system_error_occurred_at ON system_error USING brin (occurred_at);
CREATE INDEX idx_system_error_app_user_id ON system_error (app_user_id) WHERE app_user_id IS NOT NULL;
COMMENT ON TABLE system_error IS 'Internal. Application errors; retention 90 days (scheduled delete), messages truncated to 2000 characters.';
COMMENT ON COLUMN system_error.app_user_id IS 'Internal. User whose request failed. NULL: background job or anonymous request.';
