-- V008 Plans, subscriptions (the licence), wallet and ledger, payments, invoices, profile downloads.
-- Requirements: FR-BIL-01..09, docket rule groups 2 (limits by the database), 9 (licence columns), 10 (append-only ledgers,
-- non-overlapping periods, download history). The licence is the subscription (ADR-005).

CREATE TABLE plan (
    id                     smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code                   lookup_code NOT NULL CONSTRAINT uq_plan_code UNIQUE,
    name                   short_text NOT NULL,
    price_amount           money_amount NOT NULL,
    price_currency_id      smallint NOT NULL REFERENCES currency (id) ON DELETE RESTRICT,
    billing_period_months  smallint NOT NULL CHECK (billing_period_months IN (1, 3, 12)),
    max_seats              integer NOT NULL CHECK (max_seats > 0),
    max_devices_per_user   integer NOT NULL CHECK (max_devices_per_user > 0),
    included_credits       credit_count NOT NULL CHECK (included_credits >= 0),
    is_active              boolean NOT NULL DEFAULT true
);
CALL add_audit_columns('plan');
-- The catalogue ships with the schema; price changes are new migrations (sold subscriptions keep their own limits).
INSERT INTO plan (code, name, price_amount, price_currency_id, billing_period_months, max_seats, max_devices_per_user, included_credits) VALUES
  ('starter', 'Starter', 4999.00, 1, 1, 2, 1, 50),
  ('growth', 'Growth', 24999.00, 1, 3, 5, 2, 300),
  ('enterprise', 'Enterprise', 199999.00, 1, 12, 15, 3, 2000);

-- One row per paid (or granted) period. Limits are copied from the plan at purchase, so a later price or plan change
-- never alters a licence already sold. Periods of one organisation cannot overlap (exclusion constraint).
CREATE TABLE subscription (
    id                            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organisation_id               bigint NOT NULL REFERENCES organisation (id) ON DELETE RESTRICT,
    plan_id                       smallint NOT NULL REFERENCES plan (id) ON DELETE RESTRICT,
    max_seats                     integer NOT NULL CHECK (max_seats > 0),
    max_devices_per_user          integer NOT NULL CHECK (max_devices_per_user > 0),
    starts_on                     date NOT NULL,
    ends_on                       date NOT NULL,
    auto_renew                    boolean NOT NULL DEFAULT true,
    cancelled_at                  timestamptz,
    renewed_from_subscription_id  bigint CONSTRAINT uq_subscription_renewed_from_subscription_id UNIQUE
                                  REFERENCES subscription (id) ON DELETE RESTRICT,
    payment_order_id              bigint,
    CONSTRAINT ck_subscription_period CHECK (ends_on > starts_on),
    CONSTRAINT ex_subscription_no_overlap EXCLUDE USING gist (organisation_id WITH =, daterange(starts_on, ends_on) WITH &&)
);
CALL add_audit_columns('subscription');
CREATE INDEX idx_subscription_plan_id ON subscription (plan_id);
COMMENT ON TABLE subscription IS 'Internal. The licence: max_seats users per organisation, max_devices_per_user each (rule group 9). Active when today is in [starts_on, ends_on).';
COMMENT ON COLUMN subscription.cancelled_at IS 'Internal. NULL: not cancelled. Cancelling stops renewal and may bring ends_on forward; it never deletes the row.';
COMMENT ON COLUMN subscription.renewed_from_subscription_id IS 'Internal. Previous period this one renews. NULL: first subscription of the organisation.';
COMMENT ON COLUMN subscription.payment_order_id IS 'Internal. Payment that bought the period. NULL: complimentary or migrated period.';

-- Only cancellation fields may change; plan, limits and start are facts of the sale.
CREATE FUNCTION subscription_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF (NEW.organisation_id, NEW.plan_id, NEW.max_seats, NEW.max_devices_per_user, NEW.starts_on, NEW.payment_order_id)
     IS DISTINCT FROM (OLD.organisation_id, OLD.plan_id, OLD.max_seats, OLD.max_devices_per_user, OLD.starts_on, OLD.payment_order_id)
     OR NEW.ends_on > OLD.ends_on THEN
    RAISE EXCEPTION 'subscription % : only cancellation and auto-renew may change', OLD.id USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_subscription_guard BEFORE UPDATE ON subscription FOR EACH ROW EXECUTE FUNCTION subscription_guard();
CREATE TRIGGER trg_subscription_audit AFTER INSERT OR UPDATE ON subscription FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TABLE wallet (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organisation_id  bigint NOT NULL CONSTRAINT uq_wallet_organisation_id UNIQUE REFERENCES organisation (id) ON DELETE RESTRICT,
    balance_credits  credit_count NOT NULL DEFAULT 0 CONSTRAINT ck_wallet_balance_not_negative CHECK (balance_credits >= 0)
);
CALL add_audit_columns('wallet');
COMMENT ON COLUMN wallet.balance_credits IS 'Internal. Cached sum of the ledger, changed only by wallet_post() in the same transaction as the entry (test t05 checks they agree).';

CREATE TABLE payment_order (
    id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organisation_id    bigint NOT NULL REFERENCES organisation (id) ON DELETE RESTRICT,
    payment_purpose_id smallint NOT NULL REFERENCES payment_purpose (id) ON DELETE RESTRICT,
    amount             money_amount NOT NULL CHECK (amount > 0),
    currency_id        smallint NOT NULL REFERENCES currency (id) ON DELETE RESTRICT,
    credits_to_grant   credit_count,
    plan_id            smallint REFERENCES plan (id) ON DELETE RESTRICT,
    payment_status_id  smallint NOT NULL DEFAULT 1 REFERENCES payment_status (id) ON DELETE RESTRICT,
    gateway_order_ref  text CONSTRAINT uq_payment_order_gateway_order_ref UNIQUE CHECK (gateway_order_ref ~ '^[A-Za-z0-9_-]{6,64}$'),
    idempotency_key    text NOT NULL CONSTRAINT uq_payment_order_idempotency_key UNIQUE CHECK (char_length(idempotency_key) BETWEEN 8 AND 100),
    -- a recharge says how many credits; a subscription says which plan; never both, never neither
    CONSTRAINT ck_payment_order_purpose CHECK (
        (payment_purpose_id = 1) = (credits_to_grant IS NOT NULL AND credits_to_grant > 0)
        AND (payment_purpose_id = 2) = (plan_id IS NOT NULL))
);
CALL add_audit_columns('payment_order');
CREATE INDEX idx_payment_order_organisation_id ON payment_order (organisation_id, created_at DESC);
CREATE INDEX idx_payment_order_plan_id ON payment_order (plan_id) WHERE plan_id IS NOT NULL;
COMMENT ON COLUMN payment_order.credits_to_grant IS 'Internal. NULL: exactly when the order is for a subscription.';
COMMENT ON COLUMN payment_order.plan_id IS 'Internal. NULL: exactly when the order is a wallet recharge.';
COMMENT ON COLUMN payment_order.gateway_order_ref IS 'Sensitive. Gateway order id (no card or bank data is ever stored). NULL: the gateway has not created the order yet.';
ALTER TABLE subscription ADD CONSTRAINT fk_subscription_payment_order FOREIGN KEY (payment_order_id) REFERENCES payment_order (id) ON DELETE RESTRICT;
CREATE UNIQUE INDEX uq_subscription_payment_order_id ON subscription (payment_order_id) WHERE payment_order_id IS NOT NULL;

-- Gateway webhooks, exactly as received. gateway_event_ref is unique, so a redelivered webhook is a no-op (idempotency).
CREATE TABLE payment_event (
    id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    payment_order_id   bigint NOT NULL REFERENCES payment_order (id) ON DELETE RESTRICT,
    payment_status_id  smallint NOT NULL REFERENCES payment_status (id) ON DELETE RESTRICT,
    gateway_event_ref  text NOT NULL CONSTRAINT uq_payment_event_gateway_event_ref UNIQUE CHECK (gateway_event_ref ~ '^[A-Za-z0-9_-]{6,64}$'),
    amount             money_amount NOT NULL,
    currency_id        smallint NOT NULL REFERENCES currency (id) ON DELETE RESTRICT,
    occurred_at        timestamptz NOT NULL,
    payload_sha256     sha256_digest NOT NULL
);
CALL add_audit_columns('payment_event', append_only => true);
CREATE INDEX idx_payment_event_payment_order_id ON payment_event (payment_order_id, occurred_at);
COMMENT ON COLUMN payment_event.gateway_event_ref IS 'Sensitive. Gateway event id; the idempotency key for webhooks.';
COMMENT ON COLUMN payment_event.occurred_at IS 'Internal. Gateway time of the event; created_at is when Talentra received it.';
COMMENT ON COLUMN payment_event.payload_sha256 IS 'Internal. Hash of the raw webhook body, proving what was received without storing it.';

-- Signed credit movements. Never updated: a correction is a reversal entry pointing at the original (rule group 10).
CREATE TABLE wallet_ledger_entry (
    id                        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    wallet_id                 bigint NOT NULL REFERENCES wallet (id) ON DELETE RESTRICT,
    ledger_entry_type_id      smallint NOT NULL REFERENCES ledger_entry_type (id) ON DELETE RESTRICT,
    credits                   credit_count NOT NULL,
    balance_after             credit_count NOT NULL CHECK (balance_after >= 0),
    reverses_ledger_entry_id  bigint CONSTRAINT uq_wallet_ledger_entry_reverses_ledger_entry_id UNIQUE
                              REFERENCES wallet_ledger_entry (id) ON DELETE RESTRICT,
    payment_order_id          bigint REFERENCES payment_order (id) ON DELETE RESTRICT,
    idempotency_key           text NOT NULL CONSTRAINT uq_wallet_ledger_entry_idempotency_key UNIQUE CHECK (char_length(idempotency_key) BETWEEN 8 AND 100),
    occurred_at               timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_wallet_ledger_entry_sign CHECK (CASE
        WHEN ledger_entry_type_id IN (1, 2) THEN credits > 0
        WHEN ledger_entry_type_id IN (3, 4, 5) THEN credits < 0
        ELSE credits <> 0 END),
    CONSTRAINT ck_wallet_ledger_entry_reversal CHECK ((ledger_entry_type_id = 6) = (reverses_ledger_entry_id IS NOT NULL))
);
CALL add_audit_columns('wallet_ledger_entry', append_only => true);
CREATE INDEX idx_wallet_ledger_entry_wallet_id ON wallet_ledger_entry (wallet_id, occurred_at DESC);   -- AP-08 statement
CREATE INDEX idx_wallet_ledger_entry_payment_order_id ON wallet_ledger_entry (payment_order_id) WHERE payment_order_id IS NOT NULL;
COMMENT ON COLUMN wallet_ledger_entry.reverses_ledger_entry_id IS 'Internal. Entry this one corrects; each entry can be reversed once. NULL: not a reversal.';
COMMENT ON COLUMN wallet_ledger_entry.payment_order_id IS 'Internal. Payment behind a recharge, grant or refund. NULL: a debit for platform usage.';

CREATE SEQUENCE invoice_number_seq;
CREATE TABLE invoice (
    id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    payment_order_id  bigint NOT NULL CONSTRAINT uq_invoice_payment_order_id UNIQUE REFERENCES payment_order (id) ON DELETE RESTRICT,
    invoice_number    text NOT NULL CONSTRAINT uq_invoice_invoice_number UNIQUE CHECK (invoice_number ~ '^TAL-[0-9]{4}-[0-9]{6,}$'),
    issued_on         date NOT NULL,
    subtotal_amount   money_amount NOT NULL,
    tax_amount        money_amount NOT NULL,
    total_amount      money_amount NOT NULL,
    currency_id       smallint NOT NULL REFERENCES currency (id) ON DELETE RESTRICT,
    CONSTRAINT ck_invoice_total CHECK (total_amount = subtotal_amount + tax_amount)
);
CALL add_audit_columns('invoice', append_only => true);

CREATE TABLE profile_download (
    id                      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organisation_id         bigint NOT NULL REFERENCES organisation (id) ON DELETE RESTRICT,
    app_user_id             bigint NOT NULL REFERENCES app_user (id) ON DELETE RESTRICT,
    candidate_profile_id    bigint NOT NULL REFERENCES candidate_profile (id) ON DELETE RESTRICT,
    wallet_ledger_entry_id  bigint NOT NULL CONSTRAINT uq_profile_download_wallet_ledger_entry_id UNIQUE
                            REFERENCES wallet_ledger_entry (id) ON DELETE RESTRICT,
    downloaded_at           timestamptz NOT NULL DEFAULT now()
);
CALL add_audit_columns('profile_download', append_only => true);
CREATE INDEX idx_profile_download_candidate_profile_id ON profile_download (candidate_profile_id, organisation_id, downloaded_at DESC);  -- AP-07
CREATE INDEX idx_profile_download_organisation_id ON profile_download (organisation_id, downloaded_at DESC);
CREATE INDEX idx_profile_download_app_user_id ON profile_download (app_user_id);
COMMENT ON TABLE profile_download IS 'Internal. Append-only history: who (app_user_id, organisation_id) downloaded whom, when, for which credit debit.';

-- The only writer of the ledger. Locks the wallet row, so concurrent debits queue and the balance can never go negative.
-- Replaying the same idempotency key returns the original entry instead of charging twice.
CREATE FUNCTION wallet_post(p_wallet_id bigint, p_type_code text, p_credits integer, p_idempotency_key text,
                            p_payment_order_id bigint DEFAULT NULL, p_reverses bigint DEFAULT NULL, p_occurred_at timestamptz DEFAULT now())
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE w wallet; e bigint;
BEGIN
  SELECT * INTO w FROM wallet WHERE id = p_wallet_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'wallet % not found', p_wallet_id USING ERRCODE = 'no_data_found'; END IF;
  SELECT id INTO e FROM wallet_ledger_entry WHERE idempotency_key = p_idempotency_key;
  IF FOUND THEN RETURN e; END IF;
  IF w.balance_credits + p_credits < 0 THEN
    RAISE EXCEPTION 'insufficient credits: balance %, needed %', w.balance_credits, -p_credits USING ERRCODE = 'P0002', HINT = 'recharge the wallet';
  END IF;
  INSERT INTO wallet_ledger_entry (wallet_id, ledger_entry_type_id, credits, balance_after, reverses_ledger_entry_id,
                                   payment_order_id, idempotency_key, occurred_at, created_at)
  VALUES (w.id, (SELECT id FROM ledger_entry_type WHERE code = p_type_code), p_credits, w.balance_credits + p_credits,
          p_reverses, p_payment_order_id, p_idempotency_key, p_occurred_at, p_occurred_at)
  RETURNING id INTO e;
  UPDATE wallet SET balance_credits = balance_credits + p_credits WHERE id = w.id;
  RETURN e;
END $$;

-- Publishing a job costs credits, charged exactly once when it first leaves draft.
-- ponytail: price is a constant; move to a price table when pricing varies by plan.
CREATE FUNCTION job_requirement_charge_posting() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.published_at IS NOT NULL AND (TG_OP = 'INSERT' OR OLD.published_at IS NULL) THEN
    PERFORM wallet_post((SELECT id FROM wallet WHERE organisation_id = NEW.organisation_id), 'job_post_debit', -5,
                        'job_post:' || NEW.id, p_occurred_at => NEW.published_at);
  END IF;
  RETURN NULL;
END $$;
CREATE TRIGGER trg_job_requirement_charge_posting AFTER INSERT OR UPDATE OF published_at ON job_requirement
    FOR EACH ROW EXECUTE FUNCTION job_requirement_charge_posting();

-- Applies one gateway webhook. Duplicate deliveries return false and change nothing. Moves the order along
-- created -> authorised -> captured -> refunded (or -> failed); an out-of-date event is recorded but changes nothing.
-- On capture: credits for a recharge, or a subscription period plus the plan's credits, and an invoice (GST 18% included).
CREATE FUNCTION billing_apply_payment_event(p_payment_order_id bigint, p_status_code text, p_gateway_event_ref text,
                                            p_amount numeric, p_occurred_at timestamptz, p_payload_sha256 bytea)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  o payment_order; p plan; s_new smallint := (SELECT id FROM payment_status WHERE code = p_status_code);
  w bigint; prev subscription; start_on date; recharge bigint;
BEGIN
  SELECT * INTO o FROM payment_order WHERE id = p_payment_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'payment order % not found', p_payment_order_id USING ERRCODE = 'no_data_found'; END IF;
  INSERT INTO payment_event (payment_order_id, payment_status_id, gateway_event_ref, amount, currency_id, occurred_at, payload_sha256)
  VALUES (o.id, s_new, p_gateway_event_ref, p_amount, o.currency_id, p_occurred_at, p_payload_sha256)
  ON CONFLICT (gateway_event_ref) DO NOTHING;
  IF NOT FOUND THEN RETURN false; END IF;
  IF p_amount <> o.amount THEN
    RAISE EXCEPTION 'payment order %: event amount % does not match order amount %', o.id, p_amount, o.amount USING ERRCODE = 'check_violation';
  END IF;
  IF (o.payment_status_id, s_new) NOT IN ((1, 2), (1, 3), (1, 4), (2, 3), (2, 4), (3, 5)) THEN
    RETURN true;                                                   -- late or repeated state: kept as evidence only
  END IF;
  UPDATE payment_order SET payment_status_id = s_new WHERE id = o.id;
  w := (SELECT id FROM wallet WHERE organisation_id = o.organisation_id);

  IF p_status_code = 'captured' THEN
    IF o.payment_purpose_id = 1 THEN
      PERFORM wallet_post(w, 'recharge', o.credits_to_grant, 'payment:' || o.id, o.id, p_occurred_at => p_occurred_at);
    ELSE
      SELECT * INTO p FROM plan WHERE id = o.plan_id;
      SELECT * INTO prev FROM subscription WHERE organisation_id = o.organisation_id ORDER BY ends_on DESC LIMIT 1;
      start_on := greatest(p_occurred_at::date, coalesce(prev.ends_on, p_occurred_at::date));
      INSERT INTO subscription (organisation_id, plan_id, max_seats, max_devices_per_user, starts_on, ends_on,
                                renewed_from_subscription_id, payment_order_id, created_at)
      VALUES (o.organisation_id, p.id, p.max_seats, p.max_devices_per_user, start_on,
              start_on + make_interval(months => p.billing_period_months), prev.id, o.id, p_occurred_at);
      IF p.included_credits > 0 THEN
        PERFORM wallet_post(w, 'plan_grant', p.included_credits, 'payment:' || o.id, o.id, p_occurred_at => p_occurred_at);
      END IF;
    END IF;
    INSERT INTO invoice (payment_order_id, invoice_number, issued_on, subtotal_amount, tax_amount, total_amount, currency_id, created_at)
    VALUES (o.id, 'TAL-' || to_char(p_occurred_at, 'YYYY') || '-' || lpad(nextval('invoice_number_seq')::text, 6, '0'),
            p_occurred_at::date, round(o.amount / 1.18, 2), o.amount - round(o.amount / 1.18, 2), o.amount, o.currency_id, p_occurred_at);
  ELSIF p_status_code = 'refunded' THEN
    -- take back what the payment granted; fails (and so rejects the refund) if the credits were already spent
    SELECT id INTO recharge FROM wallet_ledger_entry WHERE idempotency_key = 'payment:' || o.id;
    IF recharge IS NOT NULL THEN
      PERFORM wallet_post(w, 'reversal', -(SELECT credits FROM wallet_ledger_entry WHERE id = recharge), 'refund:' || o.id,
                          o.id, recharge, p_occurred_at);
    END IF;
    UPDATE subscription SET cancelled_at = p_occurred_at, auto_renew = false,
           ends_on = greatest(starts_on + 1, least(ends_on, p_occurred_at::date))
    WHERE payment_order_id = o.id;
  END IF;
  PERFORM audit_log('payment_order.' || p_status_code, 'payment_order', o.id, o.organisation_id, '{}', p_occurred_at);
  RETURN true;
END $$;
