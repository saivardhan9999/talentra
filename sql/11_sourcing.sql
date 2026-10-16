-- =============================================================================
-- Talentra :: 11_sourcing.sql
-- Module: Sourcing and consultant requests — individual, Phase 3, Member B
-- Consultant openness is job_requirement.is_open_to_consultants (+ fee), built in
-- Phase 1. A consultant asks to source for a requirement; the employer accepts or
-- declines (the decision is recorded on the request: one decision per request).
-- Accepted consultants build a shortlist in the existing talent_list. Employers,
-- recruiters and consultants send bulk outreach in batches; each recipient's
-- delivery status comes back from the messaging provider (message bodies stay
-- with the provider, docket §6).
-- =============================================================================
SET app.current_user_id = '1';

CALL create_lookup_table('sourcing_request_status',   'SYSTEM: 1=requested, 2=accepted, 3=declined, 4=withdrawn, 5=expired');
CALL create_lookup_table('outreach_channel',          'email, sms, whatsapp, in_app');
CALL create_lookup_table('outreach_batch_status',     'draft, queued, sending, completed, cancelled');
CALL create_lookup_table('outreach_recipient_status', 'queued, sent, delivered, failed, responded, opted_out');

CALL seed_lookups('sourcing_request_status', ARRAY['requested|Requested', 'accepted|Accepted', 'declined|Declined', 'withdrawn|Withdrawn', 'expired|Expired']);
CALL seed_lookups('outreach_channel', ARRAY['email|Email', 'sms|SMS', 'whatsapp|WhatsApp', 'in_app|In-app']);
CALL seed_lookups('outreach_batch_status', ARRAY['draft|Draft', 'queued|Queued', 'sending|Sending', 'completed|Completed', 'cancelled|Cancelled']);
CALL seed_lookups('outreach_recipient_status', ARRAY['queued|Queued', 'sent|Sent', 'delivered|Delivered', 'failed|Failed',
                                                     'responded|Responded', 'opted_out|Opted out']);

CREATE TABLE sourcing_request (
    id                         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_requirement_id         bigint        NOT NULL REFERENCES job_requirement (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    consultant_user_account_id bigint        NOT NULL REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    request_note               varchar(2000),
    proposed_fee_pct           numeric(5,2),
    sourcing_request_status_id bigint        NOT NULL DEFAULT 1 REFERENCES sourcing_request_status (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    requested_at               timestamptz   NOT NULL DEFAULT now(),
    decided_at                 timestamptz,
    decided_by_user_account_id bigint REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    decision_note              varchar(1000),
    created_at                 timestamptz   NOT NULL DEFAULT now(),
    created_by                 bigint        NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at                 timestamptz   NOT NULL DEFAULT now(),
    updated_by                 bigint        NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    -- target of outreach_batch's composite FK: outreach under a request is for the request's requirement
    CONSTRAINT uq_sourcing_request_id_job_requirement_id UNIQUE (id, job_requirement_id),
    CONSTRAINT ck_sourcing_request_proposed_fee_pct CHECK (proposed_fee_pct > 0 AND proposed_fee_pct <= 100),
    CONSTRAINT ck_sourcing_request_date_range CHECK (decided_at >= requested_at),
    CONSTRAINT ck_sourcing_request_decision CHECK ((decided_at IS NULL) = (decided_by_user_account_id IS NULL)),
    -- a consultant asks for themselves; an accepted or declined request carries its decision
    CONSTRAINT ck_sourcing_request_self_requested CHECK (consultant_user_account_id = created_by),
    CONSTRAINT ck_sourcing_request_decided CHECK (sourcing_request_status_id NOT IN (1, 2, 3)
        OR (sourcing_request_status_id = 1) = (decided_at IS NULL))
);
-- One live (requested or accepted) request per consultant and requirement.
CREATE UNIQUE INDEX uq_sourcing_request_job_requirement_id_consultant_live ON sourcing_request (job_requirement_id, consultant_user_account_id)
    WHERE sourcing_request_status_id IN (1, 2);
CREATE INDEX idx_sourcing_request_job_requirement_id ON sourcing_request (job_requirement_id, sourcing_request_status_id);
CREATE INDEX idx_sourcing_request_consultant_user_account_id ON sourcing_request (consultant_user_account_id, requested_at DESC);

-- A consultant's candidate shortlist for an accepted request is a talent_list
-- (Jobs and Applications) scoped to that request.
ALTER TABLE talent_list
    ADD COLUMN sourcing_request_id bigint REFERENCES sourcing_request (id) ON UPDATE RESTRICT ON DELETE RESTRICT;
CREATE INDEX idx_talent_list_sourcing_request_id ON talent_list (sourcing_request_id) WHERE sourcing_request_id IS NOT NULL;

CREATE TABLE outreach_batch (
    id                       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sender_user_account_id   bigint       NOT NULL REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    organisation_id          bigint REFERENCES organisation (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    job_requirement_id       bigint REFERENCES job_requirement (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    sourcing_request_id      bigint,
    outreach_channel_id      bigint       NOT NULL REFERENCES outreach_channel (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    message_template_ref     varchar(100) NOT NULL,
    outreach_batch_status_id bigint       NOT NULL DEFAULT 1 REFERENCES outreach_batch_status (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    scheduled_at             timestamptz,
    wallet_ledger_entry_id   bigint REFERENCES wallet_ledger_entry (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    created_at               timestamptz  NOT NULL DEFAULT now(),
    created_by               bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at               timestamptz  NOT NULL DEFAULT now(),
    updated_by               bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_outreach_batch_sourcing_request FOREIGN KEY (sourcing_request_id, job_requirement_id)
        REFERENCES sourcing_request (id, job_requirement_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_outreach_batch_sourcing_request CHECK (sourcing_request_id IS NULL OR job_requirement_id IS NOT NULL)
);
-- A batch is charged once (1 : 0..1 to the ledger entry).
CREATE UNIQUE INDEX uq_outreach_batch_wallet_ledger_entry_id ON outreach_batch (wallet_ledger_entry_id) WHERE wallet_ledger_entry_id IS NOT NULL;
CREATE INDEX idx_outreach_batch_sender_user_account_id ON outreach_batch (sender_user_account_id, created_at DESC);
CREATE INDEX idx_outreach_batch_job_requirement_id ON outreach_batch (job_requirement_id) WHERE job_requirement_id IS NOT NULL;
CREATE INDEX idx_outreach_batch_sourcing_request_id ON outreach_batch (sourcing_request_id) WHERE sourcing_request_id IS NOT NULL;

CREATE TABLE outreach_recipient (
    id                           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    outreach_batch_id            bigint       NOT NULL REFERENCES outreach_batch (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    candidate_profile_id         bigint       NOT NULL REFERENCES candidate_profile (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    outreach_recipient_status_id bigint       NOT NULL DEFAULT 1 REFERENCES outreach_recipient_status (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    provider_message_ref         varchar(100),
    sent_at                      timestamptz,
    delivered_at                 timestamptz,
    responded_at                 timestamptz,
    created_at                   timestamptz  NOT NULL DEFAULT now(),
    created_by                   bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    updated_at                   timestamptz  NOT NULL DEFAULT now(),
    updated_by                   bigint       NOT NULL DEFAULT app_current_user_id() REFERENCES user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_outreach_recipient_outreach_batch_id_candidate_profile_id UNIQUE (outreach_batch_id, candidate_profile_id),
    CONSTRAINT uq_outreach_recipient_provider_message_ref UNIQUE (provider_message_ref),
    CONSTRAINT ck_outreach_recipient_date_range CHECK (delivered_at >= sent_at AND responded_at >= sent_at)
);
CREATE INDEX idx_outreach_recipient_candidate_profile_id ON outreach_recipient (candidate_profile_id);

-- -----------------------------------------------------------------------------
-- M14 (B46) rules: a consultant acts only on a requirement open to consultants.
-- "Open" = is_open_to_consultants, status open, not deleted; read with definer rights
-- so the rule does not depend on what row-level security lets the actor see.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app_job_open_to_consultants(p_job_requirement_id bigint) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT EXISTS (SELECT 1 FROM job_requirement WHERE id = p_job_requirement_id AND is_open_to_consultants
                   AND job_requirement_status_id = 3 AND deleted_at IS NULL)
$$;

CREATE OR REPLACE FUNCTION trg_sourcing_request_rules() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE v_actor bigint := app_current_user_id();
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.sourcing_request_status_id <> 1 OR NEW.decided_at IS NOT NULL THEN
            RAISE EXCEPTION 'a sourcing request starts as requested, undecided';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM user_account_role WHERE user_account_id = NEW.consultant_user_account_id
                       AND role_id = 8 AND revoked_at IS NULL) THEN
            RAISE EXCEPTION 'user % is not a consultant', NEW.consultant_user_account_id;
        END IF;
        IF NOT app_job_open_to_consultants(NEW.job_requirement_id) THEN
            RAISE EXCEPTION 'job requirement % is not open to consultants', NEW.job_requirement_id;
        END IF;
        RETURN NEW;
    END IF;
    IF NEW.job_requirement_id <> OLD.job_requirement_id OR NEW.consultant_user_account_id <> OLD.consultant_user_account_id THEN
        RAISE EXCEPTION 'sourcing request % cannot move to another requirement or consultant', OLD.id;
    END IF;
    IF NEW.sourcing_request_status_id = OLD.sourcing_request_status_id THEN RETURN NEW; END IF;
    -- requested -> accepted | declined | withdrawn | expired; accepted -> withdrawn; the rest is final
    IF OLD.sourcing_request_status_id NOT IN (1, 2) OR (OLD.sourcing_request_status_id = 2 AND NEW.sourcing_request_status_id <> 4) THEN
        RAISE EXCEPTION 'sourcing request % cannot go from status % to %', OLD.id, OLD.sourcing_request_status_id, NEW.sourcing_request_status_id;
    END IF;
    IF NEW.sourcing_request_status_id IN (2, 3) THEN
        IF NOT EXISTS (SELECT 1 FROM job_requirement j WHERE j.id = NEW.job_requirement_id
                       AND j.organisation_id IN (SELECT app_organisation_ids_with('job_requirement.manage'))) THEN
            RAISE EXCEPTION 'only the requirement''s employer can accept or decline sourcing request %', OLD.id;
        END IF;
        IF NEW.sourcing_request_status_id = 2 AND NOT app_job_open_to_consultants(NEW.job_requirement_id) THEN
            RAISE EXCEPTION 'job requirement % is no longer open to consultants', NEW.job_requirement_id;
        END IF;
        NEW.decided_at := now();
        NEW.decided_by_user_account_id := v_actor;
    ELSIF NEW.sourcing_request_status_id = 4 AND v_actor IS DISTINCT FROM NEW.consultant_user_account_id THEN
        RAISE EXCEPTION 'only the consultant can withdraw sourcing request %', OLD.id;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_sourcing_request_rules BEFORE INSERT OR UPDATE ON sourcing_request
    FOR EACH ROW EXECUTE FUNCTION trg_sourcing_request_rules();

-- Acting under a request (shortlisting, outreach) needs an accepted request, by its
-- own consultant, on a requirement that is still open to consultants.
CREATE OR REPLACE FUNCTION app_assert_sourcing_request_actor(p_sourcing_request_id bigint, p_actor bigint) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE r sourcing_request;
BEGIN
    SELECT * INTO r FROM sourcing_request WHERE id = p_sourcing_request_id;
    IF r.sourcing_request_status_id <> 2 OR r.consultant_user_account_id <> p_actor THEN
        RAISE EXCEPTION 'sourcing request % is not an accepted request of user %', p_sourcing_request_id, p_actor;
    END IF;
    IF NOT app_job_open_to_consultants(r.job_requirement_id) THEN
        RAISE EXCEPTION 'job requirement % is no longer open to consultants', r.job_requirement_id;
    END IF;
END $$;

CREATE OR REPLACE FUNCTION trg_talent_list_sourcing_rules() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.sourcing_request_id IS NOT NULL AND (TG_OP = 'INSERT' OR NEW.sourcing_request_id IS DISTINCT FROM OLD.sourcing_request_id) THEN
        PERFORM app_assert_sourcing_request_actor(NEW.sourcing_request_id, NEW.owner_user_account_id);
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_talent_list_sourcing_rules BEFORE INSERT OR UPDATE OF sourcing_request_id, owner_user_account_id ON talent_list
    FOR EACH ROW EXECUTE FUNCTION trg_talent_list_sourcing_rules();

CREATE OR REPLACE FUNCTION trg_talent_list_entry_sourcing_rules() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE v_request bigint;
BEGIN
    SELECT sourcing_request_id INTO v_request FROM talent_list WHERE id = NEW.talent_list_id;
    IF v_request IS NOT NULL THEN
        PERFORM app_assert_sourcing_request_actor(v_request, NEW.added_by_user_account_id);
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_talent_list_entry_sourcing_rules BEFORE INSERT ON talent_list_entry
    FOR EACH ROW EXECUTE FUNCTION trg_talent_list_entry_sourcing_rules();

-- Outreach for a requirement: either by a current member of its organisation, or by
-- the consultant of an accepted request.
CREATE OR REPLACE FUNCTION trg_outreach_batch_rules() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.sourcing_request_id IS NOT NULL THEN
        PERFORM app_assert_sourcing_request_actor(NEW.sourcing_request_id, NEW.sender_user_account_id);
    ELSIF NEW.job_requirement_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM job_requirement j JOIN organisation_member m ON m.organisation_id = j.organisation_id
        WHERE j.id = NEW.job_requirement_id AND m.user_account_id = NEW.sender_user_account_id
          AND m.valid_from <= now() AND (m.valid_to IS NULL OR m.valid_to > now())) THEN
        RAISE EXCEPTION 'outreach for job requirement % needs membership of its organisation or an accepted sourcing request',
            NEW.job_requirement_id;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_outreach_batch_rules BEFORE INSERT OR UPDATE OF sourcing_request_id, job_requirement_id, sender_user_account_id ON outreach_batch
    FOR EACH ROW EXECUTE FUNCTION trg_outreach_batch_rules();

-- -----------------------------------------------------------------------------
-- M14 (B47, M12 deviation): a consumption entry pays for exactly one thing (download,
-- view or outreach batch) of the paying organisation. The partitioned history tables
-- cannot carry a unique index on the entry, so a row lock on the ledger entry
-- serialises two charges of the same entry and the second one sees the first.
-- A row lock is kept on the row itself; an advisory lock per row (the first design)
-- took a shared lock-table slot per charged row until commit and ran out of shared
-- memory when 175k downloads were loaded in one statement (M19, full scale).
-- Definer rights: the application role may not update ledger rows (append-only), so it
-- cannot take the row lock itself, and the check must see every charge regardless of RLS.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_credit_charge_rules() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    r       jsonb  := to_jsonb(NEW);
    v_entry bigint := (r ->> 'wallet_ledger_entry_id')::bigint;
    v_org   bigint := coalesce(r ->> 'downloader_organisation_id', r ->> 'viewer_organisation_id', r ->> 'organisation_id')::bigint;
BEGIN
    IF v_entry IS NULL OR (TG_OP = 'UPDATE' AND v_entry IS NOT DISTINCT FROM (to_jsonb(OLD) ->> 'wallet_ledger_entry_id')::bigint) THEN
        RETURN NEW;
    END IF;
    PERFORM 1 FROM wallet_ledger_entry WHERE id = v_entry FOR UPDATE;
    IF NOT EXISTS (SELECT 1 FROM wallet_ledger_entry e JOIN wallet w ON w.id = e.wallet_id
                   WHERE e.id = v_entry AND e.wallet_entry_type_id = 2 AND w.organisation_id = v_org) THEN
        RAISE EXCEPTION 'ledger entry % is not a consumption from the acting organisation''s wallet', v_entry;
    END IF;
    IF EXISTS (SELECT 1 FROM profile_download_event WHERE wallet_ledger_entry_id = v_entry)
       OR EXISTS (SELECT 1 FROM profile_view_event WHERE wallet_ledger_entry_id = v_entry)
       OR EXISTS (SELECT 1 FROM outreach_batch WHERE wallet_ledger_entry_id = v_entry AND id <> (r ->> 'id')::bigint) THEN
        RAISE EXCEPTION 'ledger entry % already paid for another download, view or outreach', v_entry;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_profile_download_event_credit BEFORE INSERT ON profile_download_event
    FOR EACH ROW EXECUTE FUNCTION trg_credit_charge_rules();
CREATE TRIGGER trg_profile_view_event_credit BEFORE INSERT ON profile_view_event
    FOR EACH ROW EXECUTE FUNCTION trg_credit_charge_rules();
CREATE TRIGGER trg_outreach_batch_credit BEFORE INSERT OR UPDATE OF wallet_ledger_entry_id ON outreach_batch
    FOR EACH ROW EXECUTE FUNCTION trg_credit_charge_rules();
CREATE INDEX idx_profile_download_event_wallet_ledger_entry_id ON profile_download_event (wallet_ledger_entry_id) WHERE wallet_ledger_entry_id IS NOT NULL;
CREATE INDEX idx_profile_view_event_wallet_ledger_entry_id ON profile_view_event (wallet_ledger_entry_id) WHERE wallet_ledger_entry_id IS NOT NULL;

-- -----------------------------------------------------------------------------
-- Classification and nullability justification (rule groups 5, 6)
-- -----------------------------------------------------------------------------
COMMENT ON COLUMN sourcing_request.request_note       IS 'class=Internal; null=no note';
COMMENT ON COLUMN sourcing_request.proposed_fee_pct   IS 'class=Internal; 0..100; null=accepts the fee on the requirement';
COMMENT ON COLUMN sourcing_request.requested_at       IS 'class=Internal';
COMMENT ON COLUMN sourcing_request.decided_at         IS 'class=Internal; null=employer has not decided';
COMMENT ON COLUMN sourcing_request.decided_by_user_account_id IS 'class=Internal; null exactly when not decided';
COMMENT ON COLUMN sourcing_request.decision_note      IS 'class=Internal; null=no reason given';
COMMENT ON COLUMN talent_list.sourcing_request_id     IS 'class=Internal; null=employer/recruiter list, not a consultant shortlist';
COMMENT ON COLUMN outreach_batch.organisation_id      IS 'class=Internal; null=freelance consultant without organisation';
COMMENT ON COLUMN outreach_batch.job_requirement_id   IS 'class=Internal; null=general outreach, not for one requirement';
COMMENT ON COLUMN outreach_batch.sourcing_request_id  IS 'class=Internal; null=not sent under a consultant sourcing request';
COMMENT ON COLUMN outreach_batch.message_template_ref IS 'class=Internal; template id at the messaging provider (body not stored)';
COMMENT ON COLUMN outreach_batch.scheduled_at         IS 'class=Internal; null=send immediately';
COMMENT ON COLUMN outreach_batch.wallet_ledger_entry_id IS 'class=Internal; null=covered by plan entitlement or not yet charged';
COMMENT ON COLUMN outreach_recipient.provider_message_ref IS 'class=Internal; provider message id, idempotency for delivery callbacks; null=not sent yet';
COMMENT ON COLUMN outreach_recipient.sent_at          IS 'class=Internal; null=not sent yet';
COMMENT ON COLUMN outreach_recipient.delivered_at     IS 'class=Internal; null=not delivered (yet)';
COMMENT ON COLUMN outreach_recipient.responded_at     IS 'class=Internal; null=no response';

CALL attach_audit_triggers();
RESET app.current_user_id;
