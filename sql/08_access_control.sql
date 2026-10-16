-- =============================================================================
-- Talentra :: 08_access_control.sql   (Module: Administration — Phase 2, Member A, B33)
-- Role-based access enforced in the database, not only the interface (docket §3):
--   * talentra_app: the only role the application connects as. It owns nothing,
--     so RLS applies to it and append-only tables are closed to UPDATE/DELETE.
--   * Permission matrix role -> permission; a user's permissions come from live
--     platform role grants (user_account_role) and live organisation mappings
--     (organisation_member, effective-dated).
--   * RLS on job_requirement and application: recruiters see only their own
--     company's requirements; candidates see only their own applications.
--   * Sensitive changes write audit_event automatically, with the actor.
-- Runs after every module that defines tables RLS or auditing refers to.
-- =============================================================================
SET app.current_user_id = '1';

-- -----------------------------------------------------------------------------
-- Permission matrix
-- -----------------------------------------------------------------------------
DO $$
DECLARE r record; k bigint; n int := 0;
BEGIN
    FOR r IN SELECT * FROM (VALUES
        ('platform.admin',          'Administer the platform'),
        ('organisation.manage',     'Manage organisation profile, locations and members'),
        ('job_requirement.view',    'View the organisation''s job requirements'),
        ('job_requirement.manage',  'Create and edit the organisation''s job requirements'),
        ('application.view',        'View applications to the organisation''s jobs'),
        ('application.manage',      'Move applications through the pipeline')
    ) AS v(code, label)
    LOOP
        n := n + 1;
        CALL seed_label('permission.' || r.code, 'administration', k);
        CALL seed_translation('permission.' || r.code, 'en', r.label);
        INSERT INTO permission (id, code, ui_label_key_id) VALUES (n, r.code, k);
    END LOOP;
END $$;

INSERT INTO role_permission (role_id, permission_id)
SELECT r.id, p.id FROM (VALUES
    ('super_admin', 'platform.admin'), ('admin', 'platform.admin'),
    ('account_admin', 'organisation.manage'), ('account_admin', 'job_requirement.view'), ('account_admin', 'application.view'),
    ('employer', 'job_requirement.view'), ('employer', 'job_requirement.manage'),
    ('employer', 'application.view'), ('employer', 'application.manage'),
    ('recruiter', 'job_requirement.view'), ('recruiter', 'application.view'), ('recruiter', 'application.manage')
) AS v(role_code, permission_code)
JOIN role r ON r.code = v.role_code
JOIN permission p ON p.code = v.permission_code;

-- Platform-wide permission (live role grants).
CREATE OR REPLACE FUNCTION app_has_permission(p_permission text) RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (
        SELECT 1 FROM user_account_role g
        JOIN role_permission rp ON rp.role_id = g.role_id
        JOIN permission p ON p.id = rp.permission_id AND p.is_active
        WHERE g.user_account_id = app_current_user_id() AND g.revoked_at IS NULL AND p.code = p_permission)
$$;

-- Organisations in which the current user holds a permission right now (live mappings).
-- Used as `organisation_id IN (SELECT ...)`, so it is evaluated once per query, not per row.
CREATE OR REPLACE FUNCTION app_organisation_ids_with(p_permission text) RETURNS SETOF bigint
LANGUAGE sql STABLE AS $$
    SELECT m.organisation_id FROM organisation_member m
    JOIN role_permission rp ON rp.role_id = m.role_id
    JOIN permission p ON p.id = rp.permission_id AND p.is_active
    WHERE m.user_account_id = app_current_user_id() AND p.code = p_permission
      AND m.valid_from <= now() AND (m.valid_to IS NULL OR m.valid_to > now())
$$;

CREATE OR REPLACE FUNCTION app_current_user_is_recruiter() RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (
        SELECT 1 FROM organisation_member m
        WHERE m.user_account_id = app_current_user_id() AND m.role_id = 7
          AND m.valid_from <= now() AND (m.valid_to IS NULL OR m.valid_to > now()))
$$;

-- -----------------------------------------------------------------------------
-- Application role and privileges
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'talentra_app') THEN
        CREATE ROLE talentra_app NOLOGIN;
    END IF;
END $$;
GRANT USAGE ON SCHEMA public TO talentra_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO talentra_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO talentra_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO talentra_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO talentra_app;

-- Append-only tables: the trigger blocks every role; the privilege is removed as well.
CREATE OR REPLACE PROCEDURE revoke_append_only(p_table text)
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE format('REVOKE UPDATE, DELETE, TRUNCATE ON %I FROM talentra_app', p_table);
END $$;

DO $$
DECLARE r record;
BEGIN
    FOR r IN SELECT DISTINCT c.relname FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
             WHERE t.tgname LIKE 'trg\_%\_append\_only' AND NOT c.relispartition
    LOOP
        CALL revoke_append_only(r.relname);
    END LOOP;
END $$;

-- Later modules call make_append_only(); it now also removes the privileges.
CREATE OR REPLACE PROCEDURE make_append_only(p_table text)
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION trg_forbid_modification()',
                   'trg_' || p_table || '_append_only', p_table);
    EXECUTE format('CREATE TRIGGER %I BEFORE TRUNCATE ON %I FOR EACH STATEMENT EXECUTE FUNCTION trg_forbid_modification()',
                   'trg_' || p_table || '_no_truncate', p_table);
    CALL revoke_append_only(p_table);
END $$;

-- -----------------------------------------------------------------------------
-- Row-level security. Superusers and the table owner bypass RLS (migration,
-- scheduled jobs); talentra_app never does. No DELETE policy for organisation or
-- candidate users: requirements are soft-deleted.
-- Helper calls are wrapped in (SELECT ...): PostgreSQL then evaluates them once per
-- query instead of once per row. Without it, a search on 100k requirements ran the
-- permission check 100k times (3.7 s at laptop scale, found by the demo UI after M20).
-- -----------------------------------------------------------------------------
ALTER TABLE job_requirement ENABLE ROW LEVEL SECURITY;
CREATE POLICY job_requirement_platform_admin ON job_requirement FOR ALL TO talentra_app
    USING ((SELECT app_has_permission('platform.admin'))) WITH CHECK ((SELECT app_has_permission('platform.admin')));
CREATE POLICY job_requirement_org_read ON job_requirement FOR SELECT TO talentra_app
    USING (organisation_id IN (SELECT app_organisation_ids_with('job_requirement.view')));
CREATE POLICY job_requirement_org_insert ON job_requirement FOR INSERT TO talentra_app
    WITH CHECK (organisation_id IN (SELECT app_organisation_ids_with('job_requirement.manage')));
CREATE POLICY job_requirement_org_update ON job_requirement FOR UPDATE TO talentra_app
    USING (organisation_id IN (SELECT app_organisation_ids_with('job_requirement.manage')))
    WITH CHECK (organisation_id IN (SELECT app_organisation_ids_with('job_requirement.manage')));
-- Public job board: published, open, not deleted. Recruiters are excluded: a recruiter
-- may only see requirements of their own company (docket §3).
CREATE POLICY job_requirement_public_read ON job_requirement FOR SELECT TO talentra_app
    USING (deleted_at IS NULL AND publish_state_id = 3 AND job_requirement_status_id = 3 AND NOT (SELECT app_current_user_is_recruiter()));

ALTER TABLE application ENABLE ROW LEVEL SECURITY;
CREATE POLICY application_platform_admin ON application FOR ALL TO talentra_app
    USING ((SELECT app_has_permission('platform.admin'))) WITH CHECK ((SELECT app_has_permission('platform.admin')));
CREATE POLICY application_candidate ON application FOR ALL TO talentra_app
    USING (candidate_profile_id IN (SELECT id FROM candidate_profile WHERE user_account_id = (SELECT app_current_user_id())))
    WITH CHECK (candidate_profile_id IN (SELECT id FROM candidate_profile WHERE user_account_id = (SELECT app_current_user_id())));
CREATE POLICY application_org_read ON application FOR SELECT TO talentra_app
    USING (job_requirement_id IN (SELECT j.id FROM job_requirement j
                                  WHERE j.organisation_id IN (SELECT app_organisation_ids_with('application.view'))));
CREATE POLICY application_org_update ON application FOR UPDATE TO talentra_app
    USING (job_requirement_id IN (SELECT j.id FROM job_requirement j
                                  WHERE j.organisation_id IN (SELECT app_organisation_ids_with('application.manage'))))
    WITH CHECK (job_requirement_id IN (SELECT j.id FROM job_requirement j
                                       WHERE j.organisation_id IN (SELECT app_organisation_ids_with('application.manage'))));

-- -----------------------------------------------------------------------------
-- Automatic audit of sensitive changes. The actor is created_by (from
-- app.current_user_id), so a sensitive change without an actor fails. Detail holds
-- only the names of changed columns, never their values (no secrets in the trail).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_write_audit_event() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    r       jsonb := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
    changed text[];
BEGIN
    IF TG_OP = 'UPDATE' THEN
        SELECT array_agg(k ORDER BY k) INTO changed FROM jsonb_object_keys(r) k
        WHERE r -> k IS DISTINCT FROM to_jsonb(OLD) -> k AND k NOT IN ('updated_at', 'updated_by');
        IF changed IS NULL THEN RETURN NULL; END IF;
    END IF;
    INSERT INTO audit_event (audit_action_id, target_table, target_record_id, organisation_id, detail)
    SELECT a.id, TG_TABLE_NAME, (r ->> 'id')::bigint,
           CASE WHEN TG_TABLE_NAME = 'organisation' THEN (r ->> 'id')::bigint ELSE (r ->> 'organisation_id')::bigint END,
           CASE WHEN changed IS NOT NULL THEN jsonb_build_object('changed', changed) END
    FROM audit_action a
    WHERE a.code = CASE TG_OP WHEN 'INSERT' THEN 'create' WHEN 'UPDATE' THEN 'update' ELSE 'delete' END;
    RETURN NULL;
END $$;

CREATE OR REPLACE PROCEDURE make_audited(p_table text)
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE format('CREATE TRIGGER %I AFTER INSERT OR UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION trg_write_audit_event()',
                   'trg_' || p_table || '_audit_event', p_table);
END $$;

CALL make_audited('user_account');
CALL make_audited('user_account_role');
CALL make_audited('role_permission');
CALL make_audited('organisation');
CALL make_audited('organisation_member');
CALL make_audited('organisation_registration_identifier');

RESET app.current_user_id;
