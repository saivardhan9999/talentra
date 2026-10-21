-- V001 Foundation: extensions, roles, standard domains (docket rule group 3), shared trigger functions.
-- Requirements: NFR-SEC-01 (least privilege), NFR-INT-01 (domains), NFR-AUD-01 (audit columns).

CREATE EXTENSION IF NOT EXISTS pg_trgm;      -- trigram search on names (AP-05)
CREATE EXTENSION IF NOT EXISTS btree_gist;   -- exclusion constraints mixing = and && (ADR-007)
CREATE EXTENSION IF NOT EXISTS pgcrypto;     -- hmac() for tokenised identifiers (ADR-009)

-- Roles are cluster-wide, so they carry a v2_ prefix to stay clear of the v1 build.
-- v2_app: the runtime role behind the API (row-level security applies). v2_reporting: analytics reads only.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'v2_app') THEN CREATE ROLE v2_app NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'v2_reporting') THEN CREATE ROLE v2_reporting NOLOGIN; END IF;
END $$;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO v2_app, v2_reporting;
ALTER ROLE v2_app SET statement_timeout = '5s';          -- NFR-PERF-04: no runaway query from the API
ALTER ROLE v2_reporting SET statement_timeout = '60s';

-- Standard domains: one definition per kind of data, so every column of that kind gets the same rule.
CREATE DOMAIN person_name   AS text CHECK (char_length(VALUE) BETWEEN 1 AND 150 AND VALUE = btrim(VALUE));
CREATE DOMAIN short_text    AS text CHECK (char_length(VALUE) BETWEEN 1 AND 200);
CREATE DOMAIN medium_text   AS text CHECK (char_length(VALUE) BETWEEN 1 AND 2000);
CREATE DOMAIN long_text     AS text CHECK (char_length(VALUE) BETWEEN 1 AND 20000);   -- job descriptions only (ADR-008)
CREATE DOMAIN email_address AS text CHECK (char_length(VALUE) <= 254 AND VALUE = lower(VALUE) AND VALUE ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$');
CREATE DOMAIN phone_e164    AS text CHECK (VALUE ~ '^\+[1-9][0-9]{6,14}$');
CREATE DOMAIN money_amount  AS numeric(14,2) CHECK (VALUE >= 0);
CREATE DOMAIN credit_count  AS integer;
CREATE DOMAIN percentage    AS numeric(5,2) CHECK (VALUE BETWEEN 0 AND 100);
CREATE DOMAIN latitude      AS numeric(8,6) CHECK (VALUE BETWEEN -90 AND 90);
CREATE DOMAIN longitude     AS numeric(9,6) CHECK (VALUE BETWEEN -180 AND 180);
CREATE DOMAIN lookup_code   AS text CHECK (VALUE ~ '^[a-z][a-z0-9_]{0,49}$');
CREATE DOMAIN sha256_digest AS bytea CHECK (octet_length(VALUE) = 32);

-- Actor of the current transaction. The API sets it per transaction: SELECT set_config('app.user_id', '42', true).
-- NULL means a system process (seed, scheduler, migration).
CREATE FUNCTION app_current_user_id() RETURNS bigint LANGUAGE sql STABLE AS
$$ SELECT nullif(current_setting('app.user_id', true), '')::bigint $$;

-- Audit columns (docket rule group 4). Added by add_audit_columns() so every business table gets the same four
-- columns and the same trigger. created_at may be supplied (seed, migration from legacy); updated_* always are set here.
CREATE FUNCTION set_audit_columns() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.created_at := coalesce(NEW.created_at, now());
    NEW.created_by := coalesce(NEW.created_by, app_current_user_id());
    NEW.updated_at := NEW.created_at;
    NEW.updated_by := NEW.created_by;
  ELSE
    NEW.created_at := OLD.created_at;
    NEW.created_by := OLD.created_by;
    NEW.updated_at := now();
    NEW.updated_by := app_current_user_id();
  END IF;
  RETURN NEW;
END $$;

-- Append-only tables (rule groups 4 and 10): no UPDATE or DELETE for anyone, owner included.
-- Retention removes whole partitions or runs the erasure procedure, which is the only documented exception.
CREATE FUNCTION forbid_change() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF current_setting('app.retention_job', true) = 'on' AND TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RAISE EXCEPTION '% is append-only: % is not allowed', TG_TABLE_NAME, TG_OP USING ERRCODE = 'insufficient_privilege';
END $$;

-- Called after app_user exists (V003): adds the four audit columns, their foreign keys and the trigger.
CREATE PROCEDURE add_audit_columns(t regclass, append_only boolean DEFAULT false) LANGUAGE plpgsql AS $$
DECLARE n text := (SELECT relname FROM pg_class WHERE oid = t);
BEGIN
  EXECUTE format('ALTER TABLE %s
      ADD COLUMN created_at timestamptz NOT NULL DEFAULT now(),
      ADD COLUMN created_by bigint CONSTRAINT fk_%s_created_by REFERENCES app_user (id) ON DELETE RESTRICT,
      ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now(),
      ADD COLUMN updated_by bigint CONSTRAINT fk_%s_updated_by REFERENCES app_user (id) ON DELETE RESTRICT', t, n, n);
  EXECUTE format('CREATE TRIGGER trg_%s_audit_columns BEFORE INSERT OR UPDATE ON %s FOR EACH ROW EXECUTE FUNCTION set_audit_columns()', n, t);
  IF append_only THEN
    EXECUTE format('CREATE TRIGGER trg_%s_append_only BEFORE UPDATE OR DELETE ON %s FOR EACH ROW EXECUTE FUNCTION forbid_change()', n, t);
  END IF;
END $$;
