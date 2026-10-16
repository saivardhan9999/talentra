-- =============================================================================
-- Talentra :: 06_organisation.sql   (Module: Organisation and account — individual, Phase 2, Member B)
-- Employer and client organisations (extends the 00 shell), hierarchy, locations,
-- tax and registration identifiers, verification, and the effective-dated mapping
-- of account administrators, employers and recruiters to an organisation.
-- An "account" is the root organisation of a hierarchy: licences, subscriptions and
-- the wallet (Phase 3) attach to it, so there is no separate account table.
-- =============================================================================
SET app.current_user_id = '1';

CALL create_lookup_table('organisation_type',            'direct_employer, staffing_agency, client');
CALL create_lookup_table('organisation_account_status',  'SYSTEM: 1=active; suspended, closed');
CALL create_lookup_table('verification_status',          'SYSTEM: 1=pending; verified, rejected, expired');
CALL create_lookup_table('registration_identifier_type', 'gstin, pan, cin, tan, udyam, ein, vat, other');
CALL create_lookup_table('organisation_member_type',     'account_administrator, employer, recruiter');

CALL seed_lookups('organisation_type', ARRAY['direct_employer|Direct employer', 'staffing_agency|Staffing agency', 'client|Client']);
CALL seed_lookups('organisation_account_status', ARRAY['active|Active', 'suspended|Suspended', 'closed|Closed']);
CALL seed_lookups('verification_status', ARRAY['pending|Pending', 'verified|Verified', 'rejected|Rejected', 'expired|Expired']);
CALL seed_lookups('registration_identifier_type', ARRAY['gstin|GSTIN', 'pan|PAN', 'cin|CIN', 'tan|TAN', 'udyam|Udyam registration',
                                                        'ein|EIN', 'vat|VAT number', 'other|Other']);
CALL seed_lookups('organisation_member_type', ARRAY['account_administrator|Account administrator', 'employer|Employer', 'recruiter|Recruiter']);

-- -----------------------------------------------------------------------------
-- organisation (extends the 00 shell). Hierarchy is an adjacency list.
-- -----------------------------------------------------------------------------
ALTER TABLE organisation
    ADD COLUMN organisation_type_id           bigint NOT NULL DEFAULT 1 REFERENCES organisation_type (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    ADD COLUMN parent_organisation_id         bigint REFERENCES organisation (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    ADD COLUMN trade_name                     varchar(250),
    ADD COLUMN industry_id                    bigint REFERENCES industry (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    ADD COLUMN website_url                    varchar(500),
    ADD COLUMN organisation_account_status_id bigint NOT NULL DEFAULT 1 REFERENCES organisation_account_status (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    ADD COLUMN verification_status_id         bigint NOT NULL DEFAULT 1 REFERENCES verification_status (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    ADD CONSTRAINT ck_organisation_website_url CHECK (website_url ~* '^https?://');
CREATE INDEX idx_organisation_parent_organisation_id ON organisation (parent_organisation_id) WHERE parent_organisation_id IS NOT NULL;

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
    CONSTRAINT ck_organisation_location_latitude CHECK (latitude BETWEEN -90 AND 90),
    CONSTRAINT ck_organisation_location_longitude CHECK (longitude BETWEEN -180 AND 180),
    CONSTRAINT ck_organisation_location_coordinates CHECK (
        (latitude IS NULL) = (longitude IS NULL) AND (latitude IS NULL) = (coordinate_source_id IS NULL))
);
CREATE INDEX idx_organisation_location_organisation_id ON organisation_location (organisation_id);
CREATE INDEX idx_organisation_location_city_id ON organisation_location (city_id);

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
        UNIQUE (registration_identifier_type_id, issuing_country_id, identifier_hmac)
);
CREATE INDEX idx_organisation_registration_identifier_organisation_id ON organisation_registration_identifier (organisation_id);

-- Effective-dated mapping of users to an organisation (recruiter mapping, account
-- administrators, employer users). Never deleted: a mapping ends by setting valid_to,
-- so "which recruiter could act for this company on date X" stays answerable.
CREATE TABLE organisation_member (
    id                          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organisation_id             bigint      NOT NULL REFERENCES organisation (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    user_account_id             bigint      NOT NULL REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    organisation_member_type_id bigint      NOT NULL REFERENCES organisation_member_type (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    valid_from                  timestamptz NOT NULL DEFAULT now(),
    valid_to                    timestamptz,
    created_at                  timestamptz NOT NULL DEFAULT now(),
    created_by                  bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at                  timestamptz NOT NULL DEFAULT now(),
    updated_by                  bigint      NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_organisation_member_date_range CHECK (valid_to >= valid_from)
);
CREATE INDEX idx_organisation_member_organisation_id ON organisation_member (organisation_id, organisation_member_type_id);
CREATE INDEX idx_organisation_member_user_account_id ON organisation_member (user_account_id);

-- -----------------------------------------------------------------------------
-- Classification and nullability justification (rule groups 5, 6)
-- -----------------------------------------------------------------------------
COMMENT ON COLUMN organisation.parent_organisation_id IS 'class=Internal; null=root organisation (the account)';
COMMENT ON COLUMN organisation.trade_name             IS 'class=Public; null=trades under its legal name';
COMMENT ON COLUMN organisation.industry_id            IS 'class=Public; null=not stated';
COMMENT ON COLUMN organisation.website_url            IS 'class=Public; null=no website';
COMMENT ON COLUMN organisation_location.address_line_1 IS 'class=Public';
COMMENT ON COLUMN organisation_location.address_line_2 IS 'class=Public; null=address fits on one line';
COMMENT ON COLUMN organisation_location.postal_code   IS 'class=Public; null=country without postal codes or not provided';
COMMENT ON COLUMN organisation_location.latitude      IS 'class=Public; WGS84 6 dp; null=not geocoded (optional service)';
COMMENT ON COLUMN organisation_location.longitude     IS 'class=Public; WGS84 6 dp; null=not geocoded';
COMMENT ON COLUMN organisation_location.coordinate_source_id IS 'class=Internal; null only when coordinates are null';
COMMENT ON COLUMN organisation_registration_identifier.identifier_token  IS 'class=Sensitive; vault token, never the clear value';
COMMENT ON COLUMN organisation_registration_identifier.identifier_hmac   IS 'class=Sensitive; keyed hash of the normalised value, for lookup and uniqueness';
COMMENT ON COLUMN organisation_registration_identifier.identifier_masked IS 'class=Internal; display form, e.g. ******1234';
COMMENT ON COLUMN organisation_registration_identifier.verified_at       IS 'class=Internal; null=not verified yet';
COMMENT ON COLUMN organisation_registration_identifier.verification_ref  IS 'class=Internal; reference returned by the verification service; null=not submitted yet';
COMMENT ON COLUMN organisation_member.valid_to        IS 'class=Internal; null=mapping is current';

CALL attach_audit_triggers();
RESET app.current_user_id;
