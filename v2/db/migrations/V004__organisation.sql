-- V004 Organisations: companies, hierarchy, locations, tokenised tax identifiers, effective-dated membership.
-- Requirements: FR-ORG-01..06, NFR-SEC-03 (tokenisation), docket section 3 (recruiter sees only own company).

-- Keyed hash for identifiers that must be matched but never stored in clear (tax ids). The key is supplied per session
-- by the API from its secret store (SET app.hmac_key); it is never stored in the database (ADR-009).
CREATE FUNCTION pii_hmac(p_value text) RETURNS bytea LANGUAGE plpgsql STABLE AS $$
DECLARE k text := current_setting('app.hmac_key', true);
BEGIN
  IF coalesce(k, '') = '' THEN RAISE EXCEPTION 'app.hmac_key is not set'; END IF;
  RETURN hmac(upper(regexp_replace(p_value, '\s', '', 'g')), k, 'sha256');
END $$;

CREATE TABLE organisation (
    id                      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    legal_name              short_text NOT NULL,
    display_name            short_text NOT NULL,
    industry_id             smallint NOT NULL REFERENCES industry (id) ON DELETE RESTRICT,
    country_id              smallint NOT NULL REFERENCES country (id) ON DELETE RESTRICT,
    parent_organisation_id  bigint REFERENCES organisation (id) ON DELETE RESTRICT,
    website_url             text CHECK (website_url ~ '^https?://[^\s]{3,250}$'),
    verification_status_id  smallint NOT NULL DEFAULT 1 REFERENCES verification_status (id) ON DELETE RESTRICT,
    verified_at             timestamptz,
    account_status_id       smallint NOT NULL DEFAULT 1 REFERENCES account_status (id) ON DELETE RESTRICT,
    deleted_at              timestamptz,
    CONSTRAINT ck_organisation_not_own_parent CHECK (parent_organisation_id <> id),
    CONSTRAINT ck_organisation_verified_at    CHECK ((verification_status_id = 2) = (verified_at IS NOT NULL))
);
CALL add_audit_columns('organisation');
CREATE INDEX idx_organisation_parent_organisation_id ON organisation (parent_organisation_id) WHERE parent_organisation_id IS NOT NULL;
CREATE INDEX idx_organisation_display_name_trgm ON organisation USING gin (lower(display_name) gin_trgm_ops);
COMMENT ON COLUMN organisation.legal_name IS 'Public. Registered name.';
COMMENT ON COLUMN organisation.display_name IS 'Public. Brand name shown on job posts.';
COMMENT ON COLUMN organisation.parent_organisation_id IS 'Internal. Group company. NULL: top of its hierarchy.';
COMMENT ON COLUMN organisation.website_url IS 'Public. NULL: the company has no website (common for small employers).';
COMMENT ON COLUMN organisation.verified_at IS 'Internal. NULL: exactly when not verified (ck_organisation_verified_at).';

-- The hierarchy must stay a tree: a new parent may not be one of the organisation's descendants.
CREATE FUNCTION organisation_prevent_cycle() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.parent_organisation_id IS NOT NULL AND EXISTS (
      WITH RECURSIVE up AS (
          SELECT o.id, o.parent_organisation_id FROM organisation o WHERE o.id = NEW.parent_organisation_id
          UNION ALL
          SELECT o.id, o.parent_organisation_id FROM organisation o JOIN up ON o.id = up.parent_organisation_id)
      SELECT 1 FROM up WHERE up.id = NEW.id) THEN
    RAISE EXCEPTION 'organisation % cannot be placed under its own descendant %', NEW.id, NEW.parent_organisation_id
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_organisation_prevent_cycle BEFORE UPDATE OF parent_organisation_id ON organisation
    FOR EACH ROW EXECUTE FUNCTION organisation_prevent_cycle();

CREATE TABLE organisation_location (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organisation_id  bigint NOT NULL REFERENCES organisation (id) ON DELETE CASCADE,
    city_id          integer NOT NULL REFERENCES city (id) ON DELETE RESTRICT,
    address_line     medium_text NOT NULL,
    postal_code      text CHECK (postal_code ~ '^[A-Z0-9 -]{3,10}$'),
    latitude         latitude,
    longitude        longitude,
    is_headquarters  boolean NOT NULL DEFAULT false,
    CONSTRAINT ck_organisation_location_coordinates CHECK ((latitude IS NULL) = (longitude IS NULL))
);
CALL add_audit_columns('organisation_location');
CREATE INDEX idx_organisation_location_organisation_id ON organisation_location (organisation_id);
CREATE UNIQUE INDEX uq_organisation_location_organisation_id_headquarters ON organisation_location (organisation_id) WHERE is_headquarters;
COMMENT ON COLUMN organisation_location.address_line IS 'Public. Office address as entered.';
COMMENT ON COLUMN organisation_location.postal_code IS 'Public. NULL: not provided (optional for small towns).';
COMMENT ON COLUMN organisation_location.latitude IS 'Public. WGS 84, from the mapping service (optional boundary). NULL: not geocoded yet.';
COMMENT ON COLUMN organisation_location.longitude IS 'Public. NULL: not geocoded yet, always together with latitude.';

-- Tax and registration identifiers: format validated by the API per type (GSTIN 15 chars with checksum, PAN 10 chars,
-- CIN 21 chars), sent to the verification service, then stored only as a keyed hash plus the last four characters.
CREATE TABLE organisation_tax_identifier (
    id                       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organisation_id          bigint NOT NULL REFERENCES organisation (id) ON DELETE CASCADE,
    country_id               smallint NOT NULL REFERENCES country (id) ON DELETE RESTRICT,
    tax_identifier_type_id   smallint NOT NULL REFERENCES tax_identifier_type (id) ON DELETE RESTRICT,
    identifier_hmac          sha256_digest NOT NULL,
    identifier_last4         text NOT NULL CHECK (identifier_last4 ~ '^[A-Z0-9]{4}$'),
    verification_status_id   smallint NOT NULL DEFAULT 1 REFERENCES verification_status (id) ON DELETE RESTRICT,
    verified_at              timestamptz,
    CONSTRAINT uq_organisation_tax_identifier_country_id_type_hmac UNIQUE (country_id, tax_identifier_type_id, identifier_hmac),
    CONSTRAINT ck_organisation_tax_identifier_verified_at CHECK ((verification_status_id = 2) = (verified_at IS NOT NULL))
);
CALL add_audit_columns('organisation_tax_identifier');
CREATE INDEX idx_organisation_tax_identifier_organisation_id ON organisation_tax_identifier (organisation_id);
COMMENT ON COLUMN organisation_tax_identifier.identifier_hmac IS 'Sensitive. HMAC-SHA256 of the normalised identifier (pii_hmac); finds duplicates without storing the value.';
COMMENT ON COLUMN organisation_tax_identifier.identifier_last4 IS 'Internal. Last four characters, for display ("GSTIN ending 1Z5A").';
COMMENT ON COLUMN organisation_tax_identifier.verified_at IS 'Internal. NULL: exactly when not verified.';

-- Who works for which company, and when. A user belongs to at most one organisation at a time (exclusion constraint);
-- history is kept by closing valid_to, never by deleting. Role here is one of account_admin, employer, recruiter.
CREATE TABLE organisation_member (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organisation_id  bigint NOT NULL REFERENCES organisation (id) ON DELETE RESTRICT,
    app_user_id      bigint NOT NULL REFERENCES app_user (id) ON DELETE RESTRICT,
    access_role_id   smallint NOT NULL REFERENCES access_role (id) ON DELETE RESTRICT
                     CONSTRAINT ck_organisation_member_role CHECK (access_role_id IN (3, 4, 5)),
    valid_from       timestamptz NOT NULL DEFAULT now(),
    valid_to         timestamptz,
    CONSTRAINT ck_organisation_member_period CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ex_organisation_member_one_organisation EXCLUDE USING gist
        (app_user_id WITH =, tstzrange(valid_from, valid_to) WITH &&)
);
CALL add_audit_columns('organisation_member');
CREATE INDEX idx_organisation_member_organisation_id ON organisation_member (organisation_id) WHERE valid_to IS NULL;
CREATE INDEX idx_organisation_member_app_user_id ON organisation_member (app_user_id) WHERE valid_to IS NULL;
COMMENT ON COLUMN organisation_member.valid_to IS 'Internal. NULL: the membership is current.';
