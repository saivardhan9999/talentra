-- =============================================================================
-- Talentra seed :: 06_subscriptions_licences_sourcing.sql
-- (B63: licences, sessions, sourcing requests, subscriptions, payments, refunds and downloads)
-- Distributions:
--   plans          starter / team (monthly), business / enterprise (annual); limits copied to licences
--   subscriptions  30% of organisations; 80% active, 8% past due, 7% cancelled, 5% expired; every
--                  billing period paid by its own paid order (gateway events + invoice); periods contiguous
--   payments       5% of orders fail (events, no invoice); wallet recharges of 100 / 500 / 1000 credits
--   wallet         subscribers and 20% of other organisations; credits consumed by profile downloads,
--                  charged profile views and outreach; 2% of recharges partly refunded (ledger debit)
--   licences       one per subscription; seats for current members up to max_users
--   sessions       10 past sessions per seat holder plus logins through app_open_session() on 1-3 devices
--                  (refusals at the device limit are recorded); 5% of candidates log in without a seat;
--                  some failed logins; 2% of live sessions and 1% of devices revoked
--   sourcing       10k consultant requests on requirements open to consultants: 50% accepted, 20%
--                  declined, 10% withdrawn, 20% pending; shortlists and outreach for accepted requests;
--                  recruiter outreach for own requirements; 50 recipients per batch on average
-- Decisions and sessions run through the real rules: the employer's identity is set per decision.
-- =============================================================================
\set ON_ERROR_STOP on
SET app.current_user_id = '1';
SET synchronous_commit = off;

-- ---------------------------------------------------------------- plans
DO $$
DECLARE k bigint; r record;
BEGIN
    FOR r IN SELECT * FROM (VALUES ('starter','Starter',1,999,2,1),('team','Team',1,4999,5,2),('business','Business',4,49999,25,3),
                                   ('enterprise','Enterprise',4,199999,100,3)) v(code, label, period, price, users, devices) LOOP
        k := NULL;
        CALL seed_label('plan.' || r.code, 'subscriptions', k);
        CALL seed_translation('plan.' || r.code, 'en', r.label);
        INSERT INTO plan (code, ui_label_key_id, billing_period_id, price_amount, price_currency_id, max_users, max_devices_per_user)
        VALUES (r.code, k, r.period, r.price, 1, r.users, r.devices);
    END LOOP;
END $$;
INSERT INTO plan_entitlement (plan_id, entitlement_type_id, quantity_per_period)
SELECT p.id, e.t, CASE WHEN p.code = 'enterprise' THEN NULL ELSE q * CASE p.code WHEN 'starter' THEN 1 WHEN 'team' THEN 4 ELSE 20 END END
FROM plan p CROSS JOIN (VALUES (1, 5), (2, 50), (3, 500), (4, 1)) e(t, q);

-- ---------------------------------------------------------------- subscriptions, orders, events, invoices
CREATE TABLE seed.sub AS
SELECT o.g, o.org_id, p.id AS plan_id, p.billing_period_id AS period, p.price_amount AS price, p.max_users, p.max_devices_per_user,
       CASE WHEN seed.r(o.g, 101) < 0.80 THEN 2 WHEN seed.r(o.g, 101) < 0.88 THEN 3 WHEN seed.r(o.g, 101) < 0.95 THEN 4 ELSE 5 END AS status,
       now() - interval '30 days' * (1 + floor(seed.r(o.g, 102) * 17)) AS started_at
FROM seed.org o
JOIN plan p ON p.code = CASE WHEN seed.r(o.g, 103) < 0.45 THEN 'starter' WHEN seed.r(o.g, 103) < 0.80 THEN 'team'
                             WHEN seed.r(o.g, 103) < 0.95 THEN 'business' ELSE 'enterprise' END
WHERE seed.r(o.g, 100) < 0.30;
INSERT INTO subscription (organisation_id, plan_id, subscription_status_id, is_auto_renew, started_at, cancelled_at, cancellation_reason, created_at, updated_at)
SELECT org_id, plan_id, status, status = 2, started_at,
       CASE WHEN status = 4 THEN now() - interval '10 days' END, CASE WHEN status = 4 THEN 'Hiring paused for the quarter' END,
       started_at, started_at
FROM seed.sub ORDER BY g;
ALTER TABLE seed.sub ADD COLUMN sub_id bigint;
UPDATE seed.sub s SET sub_id = x.id FROM subscription x WHERE x.organisation_id = s.org_id;

-- one period per elapsed term (monthly or annual), each paid by its own order
CREATE TABLE seed.period AS
SELECT s.sub_id, s.org_id, s.price, n - 1 AS renewal,
       s.started_at + CASE WHEN s.period = 1 THEN interval '1 month' ELSE interval '1 year' END * (n - 1) AS p_start,
       s.started_at + CASE WHEN s.period = 1 THEN interval '1 month' ELSE interval '1 year' END * n AS p_end
FROM seed.sub s
CROSS JOIN LATERAL generate_series(1, CASE WHEN s.period = 1 THEN 1 + floor(extract(epoch FROM now() - s.started_at) / (30 * 86400))::int ELSE 2 END) n
WHERE s.started_at + CASE WHEN s.period = 1 THEN interval '1 month' ELSE interval '1 year' END * (n - 1) < now();
ALTER TABLE seed.period ADD COLUMN pk bigserial PRIMARY KEY;

INSERT INTO payment_order (organisation_id, placed_by_user_account_id, payment_purpose_id, order_amount, order_currency_id, payment_order_status_id,
                           gateway_order_ref, paid_at, created_at, updated_at)
SELECT p.org_id, op.user_id, 1, p.price, 1, 3, 'order_S' || p.pk, p.p_start, p.p_start - interval '1 hour', p.p_start
FROM seed.period p JOIN seed.org_person op ON op.org_id = p.org_id AND op.k = 1;
INSERT INTO subscription_period (subscription_id, renewal_number, period_start_at, period_end_at, payment_order_id)
SELECT p.sub_id, p.renewal, p.p_start, p.p_end, o.id FROM seed.period p JOIN payment_order o ON o.gateway_order_ref = 'order_S' || p.pk;

-- wallet recharges (and 5% failed orders of either purpose)
INSERT INTO wallet (organisation_id)
SELECT o.org_id FROM seed.org o WHERE o.org_id IN (SELECT org_id FROM seed.sub) OR seed.r(o.g, 104) < 0.20;
CREATE TABLE seed.recharge AS
SELECT w.organisation_id AS org_id, w.id AS wallet_id, n, (ARRAY[100, 500, 1000])[1 + floor(seed.r(w.id * 4 + n, 105) * 3)::int] AS credits,
       now() - interval '500 days' + interval '120 days' * n + interval '20 days' * seed.r(w.id * 4 + n, 106) AS at
FROM wallet w CROSS JOIN generate_series(1, 4) n WHERE n <= 1 + floor(seed.r(w.id, 107) * 4);
INSERT INTO payment_order (organisation_id, placed_by_user_account_id, payment_purpose_id, order_amount, order_currency_id, credit_quantity,
                           payment_order_status_id, gateway_order_ref, paid_at, created_at, updated_at)
SELECT r.org_id, op.user_id, 2, r.credits * 5, 1, r.credits, 3, 'order_W' || r.wallet_id || '_' || r.n, r.at, r.at - interval '5 minutes', r.at
FROM seed.recharge r JOIN seed.org_person op ON op.org_id = r.org_id AND op.k = 1;
INSERT INTO payment_order (organisation_id, placed_by_user_account_id, payment_purpose_id, order_amount, order_currency_id, credit_quantity,
                           payment_order_status_id, gateway_order_ref, created_at, updated_at)
SELECT r.org_id, op.user_id, 2, r.credits * 5, 1, r.credits, 4, 'order_F' || r.wallet_id || '_' || r.n, r.at - interval '1 hour', r.at - interval '1 hour'
FROM seed.recharge r JOIN seed.org_person op ON op.org_id = r.org_id AND op.k = 1 WHERE seed.r(r.wallet_id * 4 + r.n, 108) < 0.05;

INSERT INTO payment_event (payment_order_id, payment_order_status_id, gateway_event_ref, gateway_payment_ref, occurred_at)
SELECT o.id, st, 'evt_' || o.id || '_' || st, CASE WHEN st IN (3, 4) THEN 'pay_' || o.id END, o.created_at + interval '1 minute' * st
FROM payment_order o CROSS JOIN (VALUES (2), (3), (4)) v(st)
WHERE st = 2 OR st = o.payment_order_status_id;
INSERT INTO invoice (payment_order_id, invoice_number, issued_at, billing_name, billing_tax_identifier_masked, subtotal_amount, tax_amount, total_amount, invoice_currency_id)
SELECT o.id, 'INV-' || to_char(o.paid_at, 'YYYY') || '-' || lpad(o.id::text, 8, '0'), o.paid_at, x.legal_name, ri.identifier_masked,
       round(o.order_amount / 1.18, 2), o.order_amount - round(o.order_amount / 1.18, 2), o.order_amount, 1
FROM payment_order o JOIN organisation x ON x.id = o.organisation_id
LEFT JOIN organisation_registration_identifier ri ON ri.organisation_id = x.id
WHERE o.payment_order_status_id = 3;

-- ledger: recharges first (the trigger computes every balance), then refunds and consumption
INSERT INTO wallet_ledger_entry (wallet_id, wallet_entry_type_id, credit_delta, payment_order_id, occurred_at)
SELECT r.wallet_id, 1, r.credits, o.id, r.at FROM seed.recharge r JOIN payment_order o ON o.gateway_order_ref = 'order_W' || r.wallet_id || '_' || r.n
ORDER BY r.at;
INSERT INTO refund (payment_order_id, refund_amount, refund_currency_id, refund_status_id, reason, gateway_refund_ref, requested_at, processed_at)
SELECT o.id, round(o.order_amount * 0.2, 2), 1, 3, 'Unused credits refunded on request', 'rfnd_' || o.id, o.paid_at + interval '10 days', o.paid_at + interval '12 days'
FROM payment_order o WHERE o.payment_purpose_id = 2 AND o.payment_order_status_id = 3 AND seed.r(o.id, 109) < 0.02;
INSERT INTO wallet_ledger_entry (wallet_id, wallet_entry_type_id, credit_delta, refund_id, occurred_at, note)
SELECT w.id, 3, -least((o.credit_quantity * 0.2)::int, w.credit_balance), f.id, f.processed_at, 'Refund of unused credits'
FROM refund f JOIN payment_order o ON o.id = f.payment_order_id JOIN wallet w ON w.organisation_id = o.organisation_id
WHERE w.credit_balance > 0;

-- profile downloads and charged views: 70% of downloads use a credit, the rest are covered by the plan
CREATE TABLE seed.charge AS
SELECT v AS g, CASE WHEN v % 10 < 8 THEN 'download' ELSE 'view' END AS kind, w.id AS wallet_id, w.organisation_id AS org_id, p.user_id AS viewer_id,
       c.profile_id, seed.ts(v, 110) AS at, seed.r(v, 111) < 0.70 AS charged
FROM generate_series(1, seed.n(250000)) v
JOIN (SELECT id, organisation_id, row_number() OVER (ORDER BY id) AS rn FROM wallet) w ON w.rn = seed.skew((SELECT count(*) FROM wallet), v, 112, 1.5)
JOIN seed.org_person p ON p.org_id = w.organisation_id AND p.k = 2
JOIN seed.cand_p c ON c.g = 1 + (v * 3989) % (SELECT count(*) FROM seed.cand_p);
-- keep each wallet within its credits
DELETE FROM seed.charge c USING (SELECT g, row_number() OVER (PARTITION BY wallet_id ORDER BY g) AS n FROM seed.charge WHERE charged) x
WHERE c.g = x.g AND x.n > (SELECT credit_balance FROM wallet WHERE id = c.wallet_id);
INSERT INTO wallet_ledger_entry (wallet_id, wallet_entry_type_id, credit_delta, note, occurred_at)
SELECT wallet_id, 2, -1, kind || ':' || g, at FROM seed.charge WHERE charged ORDER BY g;
INSERT INTO profile_download_event (candidate_profile_id, downloader_user_account_id, downloader_organisation_id, resume_version_id, wallet_ledger_entry_id, downloaded_at)
SELECT c.profile_id, c.viewer_id, c.org_id, cr.version_id, e.id, c.at
FROM seed.charge c LEFT JOIN wallet_ledger_entry e ON e.note = 'download:' || c.g LEFT JOIN seed.cand_resume cr ON cr.profile_id = c.profile_id
WHERE c.kind = 'download';
INSERT INTO profile_view_event (candidate_profile_id, viewer_user_account_id, viewer_organisation_id, view_context_id, viewed_at, wallet_ledger_entry_id)
SELECT c.profile_id, c.viewer_id, c.org_id, 3, c.at, e.id
FROM seed.charge c JOIN wallet_ledger_entry e ON e.note = 'view:' || c.g WHERE c.kind = 'view';

-- ---------------------------------------------------------------- licences, seats, devices, sessions
INSERT INTO licence (organisation_id, subscription_id, licence_status_id, max_users, max_devices_per_user, created_at, updated_at)
SELECT org_id, sub_id, CASE WHEN status IN (2, 3) THEN 1 WHEN status = 4 THEN 4 ELSE 3 END, max_users, max_devices_per_user, started_at, started_at
FROM seed.sub;
INSERT INTO licence_seat (licence_id, user_account_id, assigned_at)
SELECT l.id, m.user_account_id, l.created_at + interval '1 day'
FROM licence l
JOIN LATERAL (SELECT m.user_account_id, row_number() OVER (ORDER BY m.role_id DESC, m.user_account_id) AS n
              FROM organisation_member m WHERE m.organisation_id = l.organisation_id AND m.valid_to IS NULL AND m.valid_from <= now()) m ON m.n <= l.max_users
WHERE l.licence_status_id = 1;

CREATE TABLE seed.login_user AS
SELECT s.user_account_id AS user_id, true AS licensed FROM licence_seat s WHERE s.released_at IS NULL
UNION ALL SELECT c.user_id, false FROM seed.cand_p c WHERE seed.r(c.g, 113) < 0.05 AND c.live;
INSERT INTO user_device (user_account_id, device_platform_id, device_fingerprint_hmac, device_label, first_seen_at, last_seen_at)
SELECT u.user_id, 1 + floor(seed.r(u.user_id * 3 + k, 114) * 6)::int, seed.hmac('device:' || u.user_id || ':' || k),
       CASE WHEN seed.r(u.user_id * 3 + k, 115) < 0.3 THEN 'My ' || (ARRAY['laptop','phone','tablet'])[k] END,
       now() - interval '400 days', now() - interval '1 day' * k
FROM seed.login_user u CROSS JOIN generate_series(1, 3) k WHERE k <= 1 + floor(seed.r(u.user_id, 116) * 3);

-- past sessions (already ended: they never count against the limit)
INSERT INTO user_session (user_account_id, user_device_id, session_token_hash, started_at, last_activity_at, expires_at, ended_at, session_end_reason_id,
                          created_by, updated_by)
SELECT d.user_account_id, d.id, seed.hmac('sess:' || d.id || ':' || n),
       now() - interval '1 day' * (n * 9 + 2), now() - interval '1 day' * (n * 9 + 2) + interval '2 hours',
       now() - interval '1 day' * (n * 9 + 2) + interval '12 hours', now() - interval '1 day' * (n * 9 + 2) + interval '3 hours',
       CASE WHEN n % 3 = 0 THEN 2 ELSE 1 END, d.user_account_id, d.user_account_id
FROM user_device d CROSS JOIN generate_series(1, 10) n
WHERE n <= CASE WHEN d.user_account_id IN (SELECT user_id FROM seed.login_user WHERE licensed) THEN 10 ELSE 3 END;
INSERT INTO login_attempt (user_account_id, attempted_identifier_hmac, user_device_id, login_outcome_id, source_ip, attempted_at, created_by)
SELECT s.user_account_id, seed.hmac('login:' || s.user_account_id), s.user_device_id, 1, '49.36.0.1', s.started_at, s.user_account_id
FROM user_session s;
INSERT INTO login_attempt (user_account_id, attempted_identifier_hmac, user_device_id, login_outcome_id, source_ip, attempted_at, created_by)
SELECT d.user_account_id, seed.hmac('login:' || d.user_account_id), d.id, 2, '49.36.0.1', now() - interval '3 days' * seed.r(d.id, 117), d.user_account_id
FROM user_device d WHERE seed.r(d.id, 118) < 0.03;

-- current logins through the login entry point, one per device: users with more devices than their
-- licence allows are refused at the limit (login history + audit trail)
SELECT count(*) FILTER (WHERE x IS NULL) AS refused_at_device_limit, count(x) AS live_sessions
FROM (SELECT app_open_session(d.user_account_id, d.id, seed.hmac('login:' || d.user_account_id), seed.hmac('live:' || d.id),
                              now() + interval '8 hours', '49.36.0.1') AS x
      FROM user_device d ORDER BY d.user_account_id, d.id) s \gset
\echo '         logins at the device limit refused:' :refused_at_device_limit ', live sessions:' :live_sessions
SELECT count(*) FROM (SELECT app_revoke_session(s.id, 4) FROM user_session s WHERE s.ended_at IS NULL AND seed.r(s.id, 119) < 0.02) x \g /dev/null
SELECT count(*) FROM (SELECT app_revoke_device(d.id, 3) FROM user_device d WHERE seed.r(d.id, 120) < 0.01) x \g /dev/null

-- ---------------------------------------------------------------- sourcing (consultants) and outreach
CREATE TABLE seed.src AS
SELECT v AS g, pp.user_id AS consultant_id, j.job_id, j.org_id, op.user_id AS employer_id,
       CASE WHEN seed.r(v, 121) < 0.50 THEN 2 WHEN seed.r(v, 121) < 0.70 THEN 3 WHEN seed.r(v, 121) < 0.80 THEN 4 ELSE 1 END AS outcome
FROM generate_series(1, seed.n(10000)) v
JOIN (SELECT user_id, row_number() OVER (ORDER BY g) AS rn FROM seed.platform_person WHERE kind = 'consultant') pp
  ON pp.rn = 1 + (v * 17) % (SELECT count(*) FROM seed.platform_person WHERE kind = 'consultant')
JOIN (SELECT j.job_id, j.org_id, row_number() OVER (ORDER BY j.g) AS rn FROM seed.job j
      JOIN job_requirement r ON r.id = j.job_id WHERE r.is_open_to_consultants AND r.job_requirement_status_id = 3) j
  ON j.rn = 1 + (v * 7) % (SELECT count(*) FROM seed.job j JOIN job_requirement r ON r.id = j.job_id WHERE r.is_open_to_consultants AND r.job_requirement_status_id = 3)
JOIN seed.org_person op ON op.org_id = j.org_id AND op.k = 1;
DELETE FROM seed.src a USING seed.src b WHERE a.job_id = b.job_id AND a.consultant_id = b.consultant_id AND a.g > b.g;
INSERT INTO sourcing_request (job_requirement_id, consultant_user_account_id, request_note, proposed_fee_pct, requested_at, created_by, updated_by)
SELECT job_id, consultant_id, 'I have a ready pipeline for this role in your city.', round(6 + seed.r(g, 122) * 6, 2), now() - interval '20 days' * seed.r(g, 123),
       consultant_id, consultant_id
FROM seed.src;
ALTER TABLE seed.src ADD COLUMN request_id bigint;
UPDATE seed.src s SET request_id = r.id FROM sourcing_request r WHERE r.job_requirement_id = s.job_id AND r.consultant_user_account_id = s.consultant_id;
-- each decision is taken as the requirement's employer (and each withdrawal as the consultant): the rules check who acts
DO $$
DECLARE r record;
BEGIN
    FOR r IN SELECT * FROM seed.src WHERE outcome <> 1 ORDER BY g LOOP
        PERFORM set_config('app.current_user_id', CASE WHEN r.outcome = 4 THEN r.consultant_id ELSE r.employer_id END::text, true);
        UPDATE sourcing_request SET sourcing_request_status_id = r.outcome,
               decision_note = CASE r.outcome WHEN 3 THEN 'We are sourcing this role internally.' END
        WHERE id = r.request_id;
    END LOOP;
    PERFORM set_config('app.current_user_id', '1', true);
END $$;
UPDATE sourcing_request SET decided_at = requested_at + interval '1 day' WHERE decided_at IS NOT NULL;   -- the trigger stamped "now"

INSERT INTO talent_list (owner_user_account_id, talent_list_type_id, name, sourcing_request_id, created_by, updated_by)
SELECT s.consultant_id, 1, 'Shortlist for request ' || s.request_id, s.request_id, s.consultant_id, s.consultant_id FROM seed.src s WHERE s.outcome = 2;
INSERT INTO talent_list_entry (talent_list_id, candidate_profile_id, added_by_user_account_id, created_by)
SELECT DISTINCT ON (t.id, c.profile_id) t.id, c.profile_id, t.owner_user_account_id, t.owner_user_account_id
FROM talent_list t CROSS JOIN generate_series(1, 8) n
JOIN seed.cand_p c ON c.g = 1 + (t.id * 7877 + n * 131) % (SELECT count(*) FROM seed.cand_p)
WHERE t.sourcing_request_id IS NOT NULL
ORDER BY t.id, c.profile_id;

-- outreach: consultants under accepted requests, recruiters for their own requirements
CREATE TABLE seed.batch AS
SELECT row_number() OVER () AS b, * FROM (
    SELECT s.consultant_id AS sender_id, NULL::bigint AS org_id, s.job_id, s.request_id FROM seed.src s WHERE s.outcome = 2
    UNION ALL
    SELECT p.user_id, p.org_id, j.job_id, NULL FROM seed.job j JOIN seed.org_person p ON p.org_id = j.org_id AND p.k = 2
    WHERE j.status = 3 AND seed.r(j.g, 124) < 0.05
      -- only a current member may send outreach for the requirement (M14 rule); some recruiters moved company
      AND EXISTS (SELECT 1 FROM organisation_member m WHERE m.organisation_id = p.org_id AND m.user_account_id = p.user_id
                  AND m.valid_to IS NULL AND m.valid_from <= now())) x;
INSERT INTO outreach_batch (sender_user_account_id, organisation_id, job_requirement_id, sourcing_request_id, outreach_channel_id, message_template_ref,
                            outreach_batch_status_id, scheduled_at, created_by, updated_by)
SELECT sender_id, org_id, job_id, request_id, 1 + floor(seed.r(b, 125) * 3)::int, 'tpl_outreach_v' || (1 + b % 3), 4, now() - interval '10 days' * seed.r(b, 126),
       sender_id, sender_id
FROM seed.batch ORDER BY b;
INSERT INTO outreach_recipient (outreach_batch_id, candidate_profile_id, outreach_recipient_status_id, provider_message_ref, sent_at, delivered_at, responded_at)
SELECT DISTINCT ON (o.id, c.profile_id) o.id, c.profile_id, x.st, 'msg_' || o.id || '_' || c.profile_id,
       o.scheduled_at, CASE WHEN x.st IN (3, 5) THEN o.scheduled_at + interval '1 minute' END, CASE WHEN x.st = 5 THEN o.scheduled_at + interval '1 day' END
FROM outreach_batch o CROSS JOIN generate_series(1, 100) n
JOIN seed.cand_p c ON c.g = 1 + (o.id * 6113 + n * 97) % (SELECT count(*) FROM seed.cand_p)
CROSS JOIN LATERAL (SELECT CASE WHEN seed.r(o.id * 100 + n, 127) < 0.10 THEN 4 WHEN seed.r(o.id * 100 + n, 127) < 0.25 THEN 5 ELSE 3 END AS st) x
WHERE n <= 20 + floor(seed.r(o.id, 128) * 61)
ORDER BY o.id, c.profile_id;

DO $$
BEGIN
    PERFORM seed.done('subscriptions: plans + entitlements', (SELECT count(*) FROM plan) + (SELECT count(*) FROM plan_entitlement));
    PERFORM seed.done('subscriptions: subscriptions', (SELECT count(*) FROM subscription));
    PERFORM seed.done('subscriptions: periods (renewals)', (SELECT count(*) FROM subscription_period));
    PERFORM seed.done('payments: orders / events / invoices', (SELECT count(*) FROM payment_order) + (SELECT count(*) FROM payment_event) + (SELECT count(*) FROM invoice));
    PERFORM seed.done('payments: refunds', (SELECT count(*) FROM refund));
    PERFORM seed.done('wallet: wallets', (SELECT count(*) FROM wallet));
    PERFORM seed.done('wallet: ledger entries', (SELECT count(*) FROM wallet_ledger_entry));
    PERFORM seed.done('downloads: profile downloads', (SELECT count(*) FROM profile_download_event));
    PERFORM seed.done('licences: licences + seats', (SELECT count(*) FROM licence) + (SELECT count(*) FROM licence_seat));
    PERFORM seed.done('licences: devices', (SELECT count(*) FROM user_device));
    PERFORM seed.done('licences: sessions', (SELECT count(*) FROM user_session));
    PERFORM seed.done('licences: login attempts', (SELECT count(*) FROM login_attempt));
    PERFORM seed.done('licences: revocations', (SELECT count(*) FROM session_revocation_event));
    PERFORM seed.done('sourcing: requests', (SELECT count(*) FROM sourcing_request));
    PERFORM seed.done('sourcing: outreach batches + recipients', (SELECT count(*) FROM outreach_batch) + (SELECT count(*) FROM outreach_recipient));
END $$;
