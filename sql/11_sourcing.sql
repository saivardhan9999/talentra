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

CALL create_lookup_table('sourcing_request_status',   'requested, accepted, declined, withdrawn, expired');
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
    CONSTRAINT ck_sourcing_request_decision CHECK ((decided_at IS NULL) = (decided_by_user_account_id IS NULL))
);
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
