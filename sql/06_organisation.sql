-- =============================================================================
-- Talentra :: 06_organisation.sql   (Module: Organisation and account — individual, Phase 2, Member B)
-- Employer and client organisations (extends the 00 shell), hierarchy, locations,
-- tax and registration identifiers, verification, and the effective-dated mapping
-- of account administrators, employers and recruiters to an organisation.
-- An "account" is the root organisation of a hierarchy: licences, subscriptions and
-- the wallet (Phase 3) attach to it, so there is no separate account table (D12).
-- =============================================================================
SET app.current_user_id = '1';

CALL create_lookup_table('organisation_type',            'direct_employer, staffing_agency, client');
CALL create_lookup_table('organisation_account_status',  'SYSTEM: 1=active; suspended, closed');
CALL create_lookup_table('verification_status',          'SYSTEM: 1=pending, 2=verified; rejected, expired');
CALL create_lookup_table('registration_identifier_type', 'gstin, pan, cin, tan, udyam, ein, vat, other');
CALL create_lookup_table('company_size_band',            'employee-count bands');

CALL seed_lookups('organisation_type', ARRAY['direct_employer|Direct employer', 'staffing_agency|Staffing agency', 'client|Client']);
CALL seed_lookups('organisation_account_status', ARRAY['active|Active', 'suspended|Suspended', 'closed|Closed']);
CALL seed_lookups('verification_status', ARRAY['pending|Pending', 'verified|Verified', 'rejected|Rejected', 'expired|Expired']);
CALL seed_lookups('registration_identifier_type', ARRAY['gstin|GSTIN', 'pan|PAN', 'cin|CIN', 'tan|TAN', 'udyam|Udyam registration',
                                                        'ein|EIN', 'vat|VAT number', 'other|Other']);
CALL seed_lookups('company_size_band', ARRAY['1_10|1-10', '11_50|11-50', '51_200|51-200', '201_1000|201-1,000',
                                             '1001_5000|1,001-5,000', '5001_plus|5,001+']);

-- -----------------------------------------------------------------------------
-- organisation (extends the 00 shell). Hierarchy is an adjacency list.
-- -----------------------------------------------------------------------------
ALTER TABLE organisation
    ADD COLUMN organisation_type_id           bigint NOT NULL DEFAULT 1 REFERENCES organisation_type (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    ADD COLUMN parent_organisation_id         bigint REFERENCES organisation (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    ADD COLUMN trade_name                     varchar(250),
    ADD COLUMN description                    varchar(4000),
    ADD COLUMN description_language_id        bigint REFERENCES language (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    ADD COLUMN industry_id                    bigint REFERENCES industry (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    ADD COLUMN company_size_band_id           bigint REFERENCES company_size_band (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    ADD COLUMN founded_year                   smallint,
    ADD COLUMN website_url                    varchar(500),
    ADD COLUMN logo_uri                       varchar(500),
    ADD COLUMN contact_email                  varchar(254),
    ADD COLUMN contact_phone_e164             varchar(16),
    ADD COLUMN contact_phone_country_id       bigint REFERENCES country (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    ADD COLUMN organisation_account_status_id bigint NOT NULL DEFAULT 1 REFERENCES organisation_account_status (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    ADD COLUMN verification_status_id         bigint NOT NULL DEFAULT 1 REFERENCES verification_status (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    ADD CONSTRAINT ck_organisation_legal_name_not_blank CHECK (btrim(legal_name) <> ''),
    ADD CONSTRAINT ck_organisation_not_own_parent CHECK (parent_organisation_id <> id),
    ADD CONSTRAINT ck_organisation_founded_year CHECK (founded_year BETWEEN 1800 AND 2100),
    ADD CONSTRAINT ck_organisation_website_url CHECK (website_url ~* '^https?://'),
    ADD CONSTRAINT ck_organisation_contact_email_lowercase CHECK (contact_email = lower(contact_email)),
    ADD CONSTRAINT ck_organisation_contact_email_format CHECK (contact_email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
    ADD CONSTRAINT ck_organisation_contact_phone_e164 CHECK (contact_phone_e164 ~ '^\+[1-9][0-9]{6,14}$'),
    ADD CONSTRAINT ck_organisation_contact_phone_pair CHECK ((contact_phone_e164 IS NULL) = (contact_phone_country_id IS NULL));
CREATE INDEX idx_organisation_parent_organisation_id ON organisation (parent_organisation_id) WHERE parent_organisation_id IS NOT NULL;

-- No cycles in the hierarchy (an organisation cannot be its own ancestor).
-- ponytail: two concurrent re-parentings could still form a cycle; re-parenting is a rare admin action, add a lock if it becomes self-service.
CREATE OR REPLACE FUNCTION trg_organisation_no_cycle() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.parent_organisation_id IS NOT NULL AND EXISTS (
        WITH RECURSIVE ancestor AS (
            SELECT NEW.parent_organisation_id AS id
            UNION
            SELECT o.parent_organisation_id FROM organisation o JOIN ancestor a ON o.id = a.id
            WHERE o.parent_organisation_id IS NOT NULL)
        SELECT 1 FROM ancestor WHERE id = NEW.id)
    THEN
        RAISE EXCEPTION 'organisation % cannot be placed under its own descendant %', NEW.id, NEW.parent_organisation_id
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_organisation_no_cycle BEFORE INSERT OR UPDATE OF parent_organisation_id ON organisation
    FOR EACH ROW EXECUTE FUNCTION trg_organisation_no_cycle();

CREATE VIEW v_organisation AS
    SELECT * FROM organisation WHERE deleted_at IS NULL;

CREATE TABLE organisation_location (
    id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organisation_id      bigint       NOT NULL REFERENCES organisation (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    city_id              bigint       NOT NULL REFERENCES city (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    address_line_1       varchar(250) NOT NULL,
    address_line_2       varchar(250),
    postal_code          varchar(20),
    latitude             numeric(9,6),
    longitude            numeric(9,6),
    coordinate_source_id bigint REFERENCES coordinate_source (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    is_headquarters      boolean      NOT NULL DEFAULT false,
    created_at           timestamptz  NOT NULL DEFAULT now(),
    created_by           bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at           timestamptz  NOT NULL DEFAULT now(),
    updated_by           bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_organisation_location_address_line_1_not_blank CHECK (btrim(address_line_1) <> ''),
    CONSTRAINT ck_organisation_location_latitude CHECK (latitude BETWEEN -90 AND 90),
    CONSTRAINT ck_organisation_location_longitude CHECK (longitude BETWEEN -180 AND 180),
    CONSTRAINT ck_organisation_location_coordinates CHECK (
        (latitude IS NULL) = (longitude IS NULL) AND (latitude IS NULL) = (coordinate_source_id IS NULL))
);
CREATE INDEX idx_organisation_location_organisation_id ON organisation_location (organisation_id);
CREATE INDEX idx_organisation_location_city_id ON organisation_location (city_id);
-- At most one headquarters per organisation.
CREATE UNIQUE INDEX uq_organisation_location_organisation_id_hq ON organisation_location (organisation_id) WHERE is_headquarters;

-- Tax / registration identifiers are Sensitive (rule group 6): the clear value lives
-- in the token vault; the row keeps the vault token, a keyed hash for lookup and
-- uniqueness, and a masked form for display. Rows are verification evidence, so
-- they are not deleted with the organisation.
CREATE TABLE organisation_registration_identifier (
    id                              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organisation_id                 bigint       NOT NULL REFERENCES organisation (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    registration_identifier_type_id bigint       NOT NULL REFERENCES registration_identifier_type (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    issuing_country_id              bigint       NOT NULL REFERENCES country (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    identifier_token                varchar(100) NOT NULL,
    identifier_hmac                 bytea        NOT NULL,
    identifier_masked               varchar(30)  NOT NULL,
    verification_status_id          bigint       NOT NULL DEFAULT 1 REFERENCES verification_status (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    verified_at                     timestamptz,
    verification_ref                varchar(100),
    created_at                      timestamptz  NOT NULL DEFAULT now(),
    created_by                      bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at                      timestamptz  NOT NULL DEFAULT now(),
    updated_by                      bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_organisation_registration_identifier_type_country_hmac
        UNIQUE (registration_identifier_type_id, issuing_country_id, identifier_hmac),
    CONSTRAINT ck_organisation_registration_identifier_hmac_length CHECK (octet_length(identifier_hmac) = 32),
    -- verified (2) needs the time and the service's reference
    CONSTRAINT ck_organisation_registration_identifier_verified CHECK (
        verification_status_id <> 2 OR (verified_at IS NOT NULL AND verification_ref IS NOT NULL))
);
CREATE INDEX idx_organisation_registration_identifier_organisation_id ON organisation_registration_identifier (organisation_id);

-- Effective-dated mapping of users to an organisation in an organisation-scoped
-- role (account_admin 3, employer 6, recruiter 7). Never deleted: a mapping ends
-- by setting valid_to, so "who could act for this company on date X" stays
-- answerable. Row-level security (08) reads live rows of this table.
CREATE TABLE organisation_member (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organisation_id bigint      NOT NULL REFERENCES organisation (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    user_account_id bigint      NOT NULL REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    role_id         bigint      NOT NULL REFERENCES role (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    valid_from      timestamptz NOT NULL DEFAULT now(),
    valid_to        timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now(),
    created_by      bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at      timestamptz NOT NULL DEFAULT now(),
    updated_by      bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_organisation_member_date_range CHECK (valid_to > valid_from),
    CONSTRAINT ck_organisation_member_scoped_role CHECK (role_id IN (3, 6, 7)),
    -- one mapping per organisation, user and role at any instant
    CONSTRAINT uq_organisation_member_no_overlap EXCLUDE USING gist (
        organisation_id WITH =, user_account_id WITH =, role_id WITH =, tstzrange(valid_from, valid_to) WITH &&)
);
CREATE INDEX idx_organisation_member_organisation_id ON organisation_member (organisation_id, role_id);
CREATE INDEX idx_organisation_member_user_account_id ON organisation_member (user_account_id, valid_from);
CREATE TRIGGER trg_organisation_member_no_delete BEFORE DELETE ON organisation_member
    FOR EACH ROW EXECUTE FUNCTION trg_forbid_modification();

-- -----------------------------------------------------------------------------
-- Classification and nullability justification (rule groups 5, 6)
-- -----------------------------------------------------------------------------
COMMENT ON COLUMN organisation.parent_organisation_id IS 'class=Internal; null=root organisation (the account)';
COMMENT ON COLUMN organisation.trade_name             IS 'class=Public; null=trades under its legal name';
COMMENT ON COLUMN organisation.description            IS 'class=Public; company profile text; null=not written yet';
COMMENT ON COLUMN organisation.description_language_id IS 'class=Internal; null=description absent or language not detected';
COMMENT ON COLUMN organisation.industry_id            IS 'class=Public; null=not stated';
COMMENT ON COLUMN organisation.company_size_band_id   IS 'class=Public; null=not stated';
COMMENT ON COLUMN organisation.founded_year           IS 'class=Public; null=not stated';
COMMENT ON COLUMN organisation.website_url            IS 'class=Public; null=no website';
COMMENT ON COLUMN organisation.logo_uri               IS 'class=Public; object-store key; null=no logo uploaded';
COMMENT ON COLUMN organisation.contact_email          IS 'class=Internal; company contact, not a login; null=not provided';
COMMENT ON COLUMN organisation.contact_phone_e164     IS 'class=Internal; E.164; null=not provided';
COMMENT ON COLUMN organisation.contact_phone_country_id IS 'class=Internal; null exactly when contact_phone_e164 is null';
COMMENT ON COLUMN organisation_location.address_line_1 IS 'class=Public';
COMMENT ON COLUMN organisation_location.address_line_2 IS 'class=Public; null=address fits on one line';
COMMENT ON COLUMN organisation_location.postal_code   IS 'class=Public; null=country without postal codes or not provided';
COMMENT ON COLUMN organisation_location.latitude      IS 'class=Public; WGS84 6 dp; null=not geocoded (optional service)';
COMMENT ON COLUMN organisation_location.longitude     IS 'class=Public; WGS84 6 dp; null=not geocoded';
COMMENT ON COLUMN organisation_location.coordinate_source_id IS 'class=Internal; null only when coordinates are null';
COMMENT ON COLUMN organisation_registration_identifier.identifier_token  IS 'class=Sensitive; vault token, never the clear value';
COMMENT ON COLUMN organisation_registration_identifier.identifier_hmac   IS 'class=Sensitive; HMAC-SHA256 of the normalised value, for lookup and uniqueness';
COMMENT ON COLUMN organisation_registration_identifier.identifier_masked IS 'class=Internal; display form, e.g. ******1234';
COMMENT ON COLUMN organisation_registration_identifier.verified_at       IS 'class=Internal; null=not verified (CHECK: required when status is verified)';
COMMENT ON COLUMN organisation_registration_identifier.verification_ref  IS 'class=Internal; reference returned by the verification service; null=not submitted yet';
COMMENT ON COLUMN organisation_member.valid_from      IS 'class=Internal; mapping takes effect';
COMMENT ON COLUMN organisation_member.valid_to        IS 'class=Internal; null=mapping is current';

CALL attach_audit_triggers();
RESET app.current_user_id;
