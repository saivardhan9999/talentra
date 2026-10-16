-- Milestone 14 (B45-B47): keys and constraints for Licences, Sourcing and Subscriptions.
-- Part 1: behavioural tests in one rolled-back transaction (helpers included).
-- Part 2: the device limit under two truly concurrent logins (two dblink connections).
\set ON_ERROR_STOP on
BEGIN;
CREATE FUNCTION public.t_expect_fail(p_sql text, p_label text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS rejected: % (%)', p_label, SQLERRM;
        RETURN;
    END;
    RAISE EXCEPTION 'FAIL accepted but should be rejected: %', p_label;
END $$;
CREATE FUNCTION public.t_check(p_ok boolean, p_label text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    IF p_ok IS NOT TRUE THEN RAISE EXCEPTION 'FAIL %', p_label; END IF;
    RAISE NOTICE 'PASS %', p_label;
END $$;
CREATE FUNCTION public.t_as(p_user bigint) RETURNS void LANGUAGE sql AS $$ SELECT set_config('app.current_user_id', p_user::text, true) $$;
SET LOCAL app.current_user_id = '1';

DO $$
DECLARE
    u_emp bigint; u_rec bigint; u_rec2 bigint; u_con bigint; u_x bigint; u_out bigint;
    o_a bigint; o_b bigint; cur bigint; p bigint; sub bigint; sub2 bigint; lic bigint; lic2 bigint;
    seat_emp bigint; seat_rec bigint; dev1 bigint; dev2 bigint; dev3 bigint;
    s1 bigint; s2 bigint; s3 bigint; s4 bigint; s5 bigint; v bigint; v_n bigint;
    j_open bigint; j_closed bigint; r1 bigint; tl bigint; cand bigint; cand2 bigint;
    ord_sub bigint; ord_sub_unpaid bigint; ord_rech bigint; ord_rech_unpaid bigint; ord_rech_b bigint;
    w bigint; e_cons bigint; e_dl bigint; e_dl2 bigint; e_rech bigint; f1 bigint;
BEGIN
    -- ---------------------------------------------------------------- setup
    INSERT INTO user_account (email) VALUES ('m14.emp@acme.test') RETURNING id INTO u_emp;
    INSERT INTO user_account (email) VALUES ('m14.rec@acme.test') RETURNING id INTO u_rec;
    INSERT INTO user_account (email) VALUES ('m14.rec2@acme.test') RETURNING id INTO u_rec2;
    INSERT INTO user_account (email) VALUES ('m14.con@freelance.test') RETURNING id INTO u_con;
    INSERT INTO user_account (email) VALUES ('m14.x@mail.test') RETURNING id INTO u_x;
    INSERT INTO user_account (email) VALUES ('m14.out@globex.test') RETURNING id INTO u_out;
    INSERT INTO organisation (legal_name) VALUES ('M14 Acme') RETURNING id INTO o_a;
    INSERT INTO organisation (legal_name) VALUES ('M14 Globex') RETURNING id INTO o_b;
    INSERT INTO organisation_member (organisation_id, user_account_id, role_id) VALUES (o_a, u_emp, 6), (o_a, u_rec, 7), (o_a, u_rec2, 7);
    INSERT INTO user_account_role (user_account_id, role_id) VALUES (u_con, 8);
    SELECT min(id) INTO cur FROM currency;
    INSERT INTO plan (code, ui_label_key_id, billing_period_id, price_amount, price_currency_id, max_users, max_devices_per_user)
    VALUES ('m14_team', (SELECT min(id) FROM ui_label_key), 1, 1000, cur, 2, 2) RETURNING id INTO p;
    INSERT INTO subscription (organisation_id, plan_id, subscription_status_id) VALUES (o_a, p, 2) RETURNING id INTO sub;
    INSERT INTO subscription (organisation_id, plan_id, subscription_status_id) VALUES (o_a, p, 2) RETURNING id INTO sub2;
    INSERT INTO licence (organisation_id, subscription_id, licence_status_id, max_users, max_devices_per_user)
    VALUES (o_a, sub, 1, 2, 2) RETURNING id INTO lic;
    INSERT INTO licence (organisation_id, subscription_id, licence_status_id, max_users, max_devices_per_user)
    VALUES (o_a, sub2, 2, 2, 2) RETURNING id INTO lic2;

    -- ---------------------------------------------------------------- B45 seats
    PERFORM t_expect_fail(format('INSERT INTO licence (organisation_id, subscription_id, licence_status_id, max_users, max_devices_per_user) VALUES (%s, %s, 1, 0, 1)', o_a, sub2), 'licence with zero users');
    PERFORM t_expect_fail(format('INSERT INTO licence_seat (licence_id, user_account_id) VALUES (%s, %s)', lic, u_out), 'seat for a user outside the licensed organisation');
    INSERT INTO licence_seat (licence_id, user_account_id) VALUES (lic, u_emp) RETURNING id INTO seat_emp;
    INSERT INTO licence_seat (licence_id, user_account_id) VALUES (lic, u_rec) RETURNING id INTO seat_rec;
    PERFORM t_expect_fail(format('INSERT INTO licence_seat (licence_id, user_account_id) VALUES (%s, %s)', lic, u_rec2), 'third seat on a 2-user licence (max_users)');
    UPDATE licence_seat SET released_at = now() WHERE id = seat_rec;
    INSERT INTO licence_seat (licence_id, user_account_id) VALUES (lic, u_rec2);
    RAISE NOTICE 'PASS released seat frees capacity for another user';
    PERFORM t_expect_fail(format('UPDATE licence_seat SET released_at = NULL WHERE id = %s', seat_rec), 're-opening a released seat');
    PERFORM t_expect_fail(format('INSERT INTO licence_seat (licence_id, user_account_id) VALUES (%s, %s)', lic2, u_emp), 'seat on a suspended licence');

    -- ---------------------------------------------------------------- B45 device limit at login
    INSERT INTO user_device (user_account_id, device_platform_id, device_fingerprint_hmac) VALUES (u_emp, 1, '\x01') RETURNING id INTO dev1;
    INSERT INTO user_device (user_account_id, device_platform_id, device_fingerprint_hmac) VALUES (u_emp, 2, '\x02') RETURNING id INTO dev2;
    INSERT INTO user_device (user_account_id, device_platform_id, device_fingerprint_hmac) VALUES (u_emp, 3, '\x03') RETURNING id INTO dev3;
    -- sessions started two hours ago, so one can later be expired without breaking the date-range CHECK
    INSERT INTO user_session (user_account_id, user_device_id, session_token_hash, started_at, last_activity_at, expires_at)
    VALUES (u_emp, dev1, '\xa1', now() - interval '2 hours', now() - interval '2 hours', now() + interval '1 hour') RETURNING id, licence_seat_id INTO s1, v;
    PERFORM t_check(v = seat_emp, 'session of a licensed user is placed on the user''s seat even when the seat is left out');
    INSERT INTO user_session (user_account_id, user_device_id, session_token_hash, started_at, last_activity_at, expires_at)
    VALUES (u_emp, dev2, '\xa2', now() - interval '2 hours', now() - interval '2 hours', now() + interval '1 hour') RETURNING id INTO s2;
    PERFORM t_expect_fail(format('INSERT INTO user_session (user_account_id, user_device_id, session_token_hash, expires_at) VALUES (%s, %s, ''\xa9'', now() + interval ''1 hour'')', u_emp, dev3),
        'third active session with max_devices_per_user = 2 (trg_user_session_rules)');

    v := app_open_session(u_emp, dev3, '\xee', '\xa3', now() + interval '1 hour', '10.0.0.7');
    PERFORM t_check(v IS NULL, 'login entry point refuses the third device and returns no session');
    SELECT count(*) INTO v_n FROM login_attempt WHERE user_account_id = u_emp AND login_outcome_id = 4;
    PERFORM t_check(v_n = 1, 'refused login recorded in login history as device_limit_reached');
    SELECT count(*) INTO v_n FROM audit_event a JOIN audit_action x ON x.id = a.audit_action_id
    WHERE x.code = 'login_failed' AND a.created_by = u_emp AND a.organisation_id = o_a
      AND a.detail ->> 'reason' = 'device_limit_reached' AND (a.detail ->> 'active_sessions')::int = 2;
    PERFORM t_check(v_n = 1, 'attempt to exceed the device limit written to the audit trail (rule group 9)');

    UPDATE user_session SET ended_at = now(), session_end_reason_id = 1 WHERE id = s2;
    s3 := app_open_session(u_emp, dev3, '\xee', '\xa4', now() + interval '1 hour');
    PERFORM t_check(s3 IS NOT NULL, 'logout releases the session: login on the third device now succeeds');
    PERFORM t_check((SELECT count(*) FROM login_attempt WHERE user_account_id = u_emp AND login_outcome_id = 1) = 1, 'successful login recorded in login history');
    PERFORM t_expect_fail(format('UPDATE user_session SET ended_at = NULL, session_end_reason_id = NULL WHERE id = %s', s2), 're-opening an ended session');
    PERFORM t_expect_fail(format('UPDATE user_session SET user_device_id = %s WHERE id = %s', dev2, s3), 'moving a session to another device');

    UPDATE user_session SET expires_at = now() - interval '1 hour' WHERE id = s1;
    INSERT INTO user_session (user_account_id, user_device_id, session_token_hash, expires_at) VALUES (u_emp, dev2, '\xa5', now() + interval '1 hour') RETURNING id INTO s4;
    RAISE NOTICE 'PASS expired session no longer counts against the limit';

    PERFORM app_revoke_session(s4, 2);
    PERFORM t_check((SELECT ended_at IS NOT NULL AND session_end_reason_id = 4 FROM user_session WHERE id = s4)
        AND (SELECT count(*) FROM session_revocation_event WHERE user_session_id = s4 AND created_by = 1) = 1,
        'revoking a session ends it and records who revoked it');
    PERFORM app_revoke_device(dev3, 3);
    PERFORM t_check((SELECT ended_at IS NOT NULL FROM user_session WHERE id = s3)
        AND (SELECT count(*) FROM session_revocation_event WHERE user_device_id = dev3 AND user_session_id IS NULL) = 1,
        'revoking a device ends its live sessions and records the revocation');
    PERFORM t_expect_fail(format('INSERT INTO user_session (user_account_id, user_device_id, session_token_hash, expires_at) VALUES (%s, %s, ''\xa6'', now() + interval ''1 hour'')', u_emp, dev3), 'session on a revoked device');
    PERFORM t_expect_fail(format('UPDATE user_device SET revoked_at = NULL WHERE id = %s', dev3), 'un-revoking a device');
    PERFORM t_check((SELECT count(*) FROM audit_event a WHERE a.target_table = 'user_device' AND a.target_record_id = dev3 AND a.detail -> 'changed' ? 'revoked_at') = 1,
        'device revocation also lands in the audit trail');
    INSERT INTO user_device (user_account_id, device_platform_id, device_fingerprint_hmac) VALUES (u_emp, 3, '\x03');
    RAISE NOTICE 'PASS revoked device can be registered again';
    PERFORM t_expect_fail('UPDATE session_revocation_event SET revocation_reason_id = 1', 'editing a revocation event');

    INSERT INTO user_session (user_account_id, user_device_id, session_token_hash, expires_at) VALUES (u_emp, dev2, '\xa7', now() + interval '1 hour') RETURNING id INTO s5;
    UPDATE licence_seat SET released_at = now() WHERE id = seat_emp;
    PERFORM t_check((SELECT ended_at IS NOT NULL FROM user_session WHERE id = s5)
        AND (SELECT count(*) FROM session_revocation_event WHERE user_session_id = s5 AND revocation_reason_id = 5) = 1,
        'releasing a seat ends its sessions as seat_released revocations');

    -- ---------------------------------------------------------------- B46 consultants
    INSERT INTO job_requirement (organisation_id, posted_by_user_account_id, title, description, job_category_id, employment_type_id,
        work_mode_id, job_requirement_status_id, publish_state_id, number_of_positions, published_at, expires_at,
        is_open_to_consultants, consultant_fee_pct)
    VALUES (o_a, u_emp, 'M14 open to consultants', 'x', 4, 1, 1, 3, 3, 1, now(), now() + interval '30 days', true, 8.5)
    RETURNING id INTO j_open;
    INSERT INTO job_requirement (organisation_id, posted_by_user_account_id, title, description, job_category_id, employment_type_id,
        work_mode_id, job_requirement_status_id, publish_state_id, number_of_positions, published_at, expires_at)
    VALUES (o_a, u_emp, 'M14 closed to consultants', 'x', 4, 1, 1, 3, 3, 1, now(), now() + interval '30 days')
    RETURNING id INTO j_closed;

    PERFORM t_as(u_x);
    PERFORM t_expect_fail(format('INSERT INTO sourcing_request (job_requirement_id, consultant_user_account_id) VALUES (%s, %s)', j_open, u_x), 'sourcing request by a user without the consultant role');
    PERFORM t_as(u_con);
    PERFORM t_expect_fail(format('INSERT INTO sourcing_request (job_requirement_id, consultant_user_account_id) VALUES (%s, %s)', j_closed, u_con), 'consultant requesting a requirement closed to consultants (B46)');
    PERFORM t_as(1);
    PERFORM t_expect_fail(format('INSERT INTO sourcing_request (job_requirement_id, consultant_user_account_id) VALUES (%s, %s)', j_open, u_con), 'sourcing request filed on a consultant''s behalf');
    PERFORM t_as(u_con);
    INSERT INTO sourcing_request (job_requirement_id, consultant_user_account_id, proposed_fee_pct) VALUES (j_open, u_con, 8.5) RETURNING id INTO r1;
    RAISE NOTICE 'PASS consultant requests a requirement open to consultants';
    PERFORM t_expect_fail(format('INSERT INTO sourcing_request (job_requirement_id, consultant_user_account_id) VALUES (%s, %s)', j_open, u_con), 'second live request for the same requirement');
    PERFORM t_expect_fail(format('UPDATE sourcing_request SET sourcing_request_status_id = 2 WHERE id = %s', r1), 'consultant accepting own request');
    PERFORM t_expect_fail(format('INSERT INTO outreach_batch (sender_user_account_id, job_requirement_id, sourcing_request_id, outreach_channel_id, message_template_ref) VALUES (%s, %s, %s, 1, ''tpl'')', u_con, j_open, r1),
        'outreach under a request that is not accepted yet');
    PERFORM t_as(u_rec);
    PERFORM t_expect_fail(format('UPDATE sourcing_request SET sourcing_request_status_id = 2 WHERE id = %s', r1), 'recruiter (no job_requirement.manage) accepting');
    PERFORM t_as(u_emp);
    UPDATE sourcing_request SET sourcing_request_status_id = 2 WHERE id = r1;
    PERFORM t_check((SELECT decided_by_user_account_id = u_emp AND decided_at IS NOT NULL FROM sourcing_request WHERE id = r1), 'employer accepts; decision time and decider recorded');
    PERFORM t_expect_fail(format('UPDATE sourcing_request SET sourcing_request_status_id = 3 WHERE id = %s', r1), 'turning an accepted request into a decline');

    -- candidates register themselves (Phase 1 rule)
    INSERT INTO user_account (email) VALUES ('m14.cand@mail.test') RETURNING id INTO v;
    PERFORM t_as(v);
    INSERT INTO candidate_profile (user_account_id, full_name, profile_visibility_id) VALUES (v, 'M14 Candidate', 1) RETURNING id INTO cand;
    INSERT INTO user_account (email) VALUES ('m14.cand2@mail.test') RETURNING id INTO v;
    PERFORM t_as(v);
    INSERT INTO candidate_profile (user_account_id, full_name, profile_visibility_id) VALUES (v, 'M14 Candidate Two', 1) RETURNING id INTO cand2;
    PERFORM t_as(u_con);
    INSERT INTO talent_list (owner_user_account_id, talent_list_type_id, name, sourcing_request_id)
    VALUES (u_con, (SELECT min(id) FROM talent_list_type), 'M14 shortlist', r1) RETURNING id INTO tl;
    INSERT INTO talent_list_entry (talent_list_id, candidate_profile_id, added_by_user_account_id) VALUES (tl, cand, u_con);
    INSERT INTO outreach_batch (sender_user_account_id, job_requirement_id, sourcing_request_id, outreach_channel_id, message_template_ref)
    VALUES (u_con, j_open, r1, 1, 'tpl');
    RAISE NOTICE 'PASS accepted consultant shortlists and sends outreach under the request';
    PERFORM t_expect_fail(format('INSERT INTO talent_list (owner_user_account_id, talent_list_type_id, name, sourcing_request_id) VALUES (%s, %s, ''x'', %s)', u_rec, (SELECT min(id) FROM talent_list_type), r1),
        'shortlist under another consultant''s request');
    PERFORM t_as(u_x);
    PERFORM t_expect_fail(format('INSERT INTO outreach_batch (sender_user_account_id, job_requirement_id, outreach_channel_id, message_template_ref) VALUES (%s, %s, 1, ''tpl'')', u_x, j_open),
        'outreach for a requirement without membership or accepted request');
    PERFORM t_as(u_rec);
    INSERT INTO outreach_batch (sender_user_account_id, job_requirement_id, outreach_channel_id, message_template_ref) VALUES (u_rec, j_open, 1, 'tpl');
    RAISE NOTICE 'PASS organisation recruiter sends outreach for own requirement';

    PERFORM t_as(u_emp);
    UPDATE job_requirement SET is_open_to_consultants = false, consultant_fee_pct = NULL WHERE id = j_open;
    PERFORM t_as(u_con);
    PERFORM t_expect_fail(format('INSERT INTO outreach_batch (sender_user_account_id, job_requirement_id, sourcing_request_id, outreach_channel_id, message_template_ref) VALUES (%s, %s, %s, 1, ''tpl'')', u_con, j_open, r1),
        'consultant outreach after the requirement closed to consultants (B46)');
    PERFORM t_expect_fail(format('INSERT INTO talent_list_entry (talent_list_id, candidate_profile_id, added_by_user_account_id) VALUES (%s, %s, %s)', tl, cand2, u_con),
        'consultant shortlisting after the requirement closed to consultants (B46)');
    UPDATE sourcing_request SET sourcing_request_status_id = 4 WHERE id = r1;
    RAISE NOTICE 'PASS consultant withdraws an accepted request';
    PERFORM t_as(1);

    -- ---------------------------------------------------------------- B47 subscriptions and payments
    PERFORM t_expect_fail(format('INSERT INTO payment_order (organisation_id, placed_by_user_account_id, payment_purpose_id, order_amount, order_currency_id) VALUES (%s, %s, 2, 500, %s)', o_a, u_emp, cur),
        'wallet recharge order without a credit quantity');
    INSERT INTO payment_order (organisation_id, placed_by_user_account_id, payment_purpose_id, order_amount, order_currency_id, payment_order_status_id)
    VALUES (o_a, u_emp, 1, 1000, cur, 3) RETURNING id INTO ord_sub;
    INSERT INTO payment_order (organisation_id, placed_by_user_account_id, payment_purpose_id, order_amount, order_currency_id, payment_order_status_id)
    VALUES (o_a, u_emp, 1, 1000, cur, 2) RETURNING id INTO ord_sub_unpaid;
    INSERT INTO payment_order (organisation_id, placed_by_user_account_id, payment_purpose_id, order_amount, order_currency_id, credit_quantity, payment_order_status_id)
    VALUES (o_a, u_emp, 2, 500, cur, 100, 3) RETURNING id INTO ord_rech;
    INSERT INTO payment_order (organisation_id, placed_by_user_account_id, payment_purpose_id, order_amount, order_currency_id, credit_quantity, payment_order_status_id)
    VALUES (o_a, u_emp, 2, 250, cur, 50, 2) RETURNING id INTO ord_rech_unpaid;
    INSERT INTO payment_order (organisation_id, placed_by_user_account_id, payment_purpose_id, order_amount, order_currency_id, credit_quantity, payment_order_status_id)
    VALUES (o_b, u_out, 2, 50, cur, 10, 3) RETURNING id INTO ord_rech_b;

    INSERT INTO subscription_period (subscription_id, renewal_number, period_start_at, period_end_at, payment_order_id)
    VALUES (sub, 0, now(), now() + interval '30 days', ord_sub);
    PERFORM t_expect_fail(format('INSERT INTO subscription_period (subscription_id, renewal_number, period_start_at, period_end_at) VALUES (%s, 1, now() + interval ''20 days'', now() + interval ''50 days'')', sub),
        'overlapping subscription periods for the same licence (B47)');
    INSERT INTO subscription_period (subscription_id, renewal_number, period_start_at, period_end_at)
    VALUES (sub, 1, now() + interval '30 days', now() + interval '60 days');
    RAISE NOTICE 'PASS back-to-back renewal period accepted';
    PERFORM t_expect_fail(format('INSERT INTO subscription_period (subscription_id, renewal_number, period_start_at, period_end_at, payment_order_id) VALUES (%s, 2, now() + interval ''60 days'', now() + interval ''90 days'', %s)', sub, ord_sub_unpaid),
        'period paid by an unpaid order');
    PERFORM t_expect_fail(format('INSERT INTO subscription_period (subscription_id, renewal_number, period_start_at, period_end_at, payment_order_id) VALUES (%s, 2, now() + interval ''60 days'', now() + interval ''90 days'', %s)', sub, ord_rech),
        'period paid by a wallet-recharge order');

    -- ---------------------------------------------------------------- B47 wallet ledger
    PERFORM t_expect_fail(format('INSERT INTO wallet (organisation_id, credit_balance) VALUES (%s, 50)', o_a), 'wallet opened with credits not from the ledger');
    INSERT INTO wallet (organisation_id) VALUES (o_a) RETURNING id INTO w;
    INSERT INTO wallet (organisation_id) VALUES (o_b);
    PERFORM t_expect_fail(format('UPDATE wallet SET credit_balance = 1000 WHERE id = %s', w), 'editing a wallet balance directly');
    PERFORM t_expect_fail(format('INSERT INTO wallet_ledger_entry (wallet_id, wallet_entry_type_id, credit_delta, payment_order_id) VALUES (%s, 1, 50, %s)', w, ord_rech_unpaid), 'recharge from an unpaid order');
    PERFORM t_expect_fail(format('INSERT INTO wallet_ledger_entry (wallet_id, wallet_entry_type_id, credit_delta, payment_order_id) VALUES (%s, 1, 99, %s)', w, ord_rech), 'recharge crediting more than the order bought');
    PERFORM t_expect_fail(format('INSERT INTO wallet_ledger_entry (wallet_id, wallet_entry_type_id, credit_delta, payment_order_id) VALUES (%s, 1, 10, %s)', w, ord_rech_b), 'recharge from another organisation''s order');
    PERFORM t_expect_fail(format('INSERT INTO wallet_ledger_entry (wallet_id, wallet_entry_type_id, credit_delta) VALUES (%s, 1, 10)', w), 'recharge without a payment order');
    INSERT INTO wallet_ledger_entry (wallet_id, wallet_entry_type_id, credit_delta, payment_order_id) VALUES (w, 1, 100, ord_rech) RETURNING id INTO e_rech;
    PERFORM t_check((SELECT balance_after FROM wallet_ledger_entry WHERE id = e_rech) = 100 AND (SELECT credit_balance FROM wallet WHERE id = w) = 100,
        'recharge credits the order''s 100 credits; balance computed by the ledger');
    PERFORM t_expect_fail(format('INSERT INTO wallet_ledger_entry (wallet_id, wallet_entry_type_id, credit_delta, payment_order_id) VALUES (%s, 1, 100, %s)', w, ord_rech), 'crediting the same order twice');
    PERFORM t_expect_fail(format('INSERT INTO wallet_ledger_entry (wallet_id, wallet_entry_type_id, credit_delta) VALUES (%s, 2, 5)', w), 'consumption with a positive amount');
    PERFORM t_expect_fail(format('INSERT INTO wallet_ledger_entry (wallet_id, wallet_entry_type_id, credit_delta) VALUES (%s, 2, -150)', w), 'consuming more credits than the wallet holds');
    INSERT INTO wallet_ledger_entry (wallet_id, wallet_entry_type_id, credit_delta) VALUES (w, 2, -30) RETURNING id INTO e_cons;
    PERFORM t_expect_fail(format('INSERT INTO wallet_ledger_entry (wallet_id, wallet_entry_type_id, credit_delta, reverses_wallet_ledger_entry_id) VALUES (%s, 4, 20, %s)', w, e_cons), 'reversal that does not negate the original');
    INSERT INTO wallet_ledger_entry (wallet_id, wallet_entry_type_id, credit_delta, reverses_wallet_ledger_entry_id) VALUES (w, 4, 30, e_cons);
    PERFORM t_check((SELECT credit_balance FROM wallet WHERE id = w) = 100, 'correction is a new reversal entry referencing the original; balance restored (rule group 10)');
    PERFORM t_expect_fail(format('INSERT INTO wallet_ledger_entry (wallet_id, wallet_entry_type_id, credit_delta, reverses_wallet_ledger_entry_id) VALUES (%s, 4, 30, %s)', w, e_cons), 'reversing the same entry twice');
    PERFORM t_expect_fail(format('UPDATE wallet_ledger_entry SET credit_delta = -1 WHERE id = %s', e_cons), 'correcting a ledger entry by update');
    PERFORM t_expect_fail(format('DELETE FROM wallet_ledger_entry WHERE id = %s', e_cons), 'deleting a ledger entry');

    -- ---------------------------------------------------------------- B47 refunds and invoices
    PERFORM t_expect_fail(format('INSERT INTO refund (payment_order_id, refund_amount, refund_currency_id, reason) VALUES (%s, 10, %s, ''x'')', ord_rech_unpaid, cur), 'refund of an unpaid order');
    PERFORM t_expect_fail(format('INSERT INTO refund (payment_order_id, refund_amount, refund_currency_id, reason) VALUES (%s, 600, %s, ''x'')', ord_rech, cur), 'refund larger than the order');
    INSERT INTO refund (payment_order_id, refund_amount, refund_currency_id, reason, refund_status_id) VALUES (ord_rech, 200, cur, 'partial', 3) RETURNING id INTO f1;
    PERFORM t_expect_fail(format('INSERT INTO refund (payment_order_id, refund_amount, refund_currency_id, reason) VALUES (%s, 400, %s, ''x'')', ord_rech, cur), 'refunds totalling more than was paid');
    INSERT INTO wallet_ledger_entry (wallet_id, wallet_entry_type_id, credit_delta, refund_id) VALUES (w, 3, -40, f1);
    PERFORM t_check((SELECT credit_balance FROM wallet WHERE id = w) = 60, 'completed refund debits the wallet through the ledger');
    PERFORM t_expect_fail(format('INSERT INTO invoice (payment_order_id, invoice_number, billing_name, subtotal_amount, tax_amount, total_amount, invoice_currency_id) VALUES (%s, ''M14-1'', ''Acme'', 200, 50, 250, %s)', ord_rech_unpaid, cur), 'invoice for an unpaid order');
    PERFORM t_expect_fail(format('INSERT INTO invoice (payment_order_id, invoice_number, billing_name, subtotal_amount, tax_amount, total_amount, invoice_currency_id) VALUES (%s, ''M14-2'', ''Acme'', 300, 50, 350, %s)', ord_rech, cur), 'invoice total different from the order amount');
    INSERT INTO invoice (payment_order_id, invoice_number, billing_name, subtotal_amount, tax_amount, total_amount, invoice_currency_id)
    VALUES (ord_rech, 'M14-3', 'M14 Acme', 400, 100, 500, cur);
    RAISE NOTICE 'PASS invoice for the paid order';

    -- ---------------------------------------------------------------- B47 download history and credit charges
    INSERT INTO wallet_ledger_entry (wallet_id, wallet_entry_type_id, credit_delta) VALUES (w, 2, -1) RETURNING id INTO e_dl;
    INSERT INTO wallet_ledger_entry (wallet_id, wallet_entry_type_id, credit_delta) VALUES (w, 2, -1) RETURNING id INTO e_dl2;
    INSERT INTO profile_download_event (candidate_profile_id, downloader_user_account_id, downloader_organisation_id, wallet_ledger_entry_id)
    VALUES (cand, u_emp, o_a, e_dl);
    RAISE NOTICE 'PASS download records actor, subject, time and the credit deduction';
    PERFORM t_expect_fail(format('INSERT INTO profile_view_event (candidate_profile_id, viewer_user_account_id, viewer_organisation_id, view_context_id, wallet_ledger_entry_id) VALUES (%s, %s, %s, %s, %s)', cand, u_emp, o_a, (SELECT min(id) FROM view_context), e_dl),
        'one credit deduction paying for a download and a view');
    PERFORM t_expect_fail(format('INSERT INTO profile_download_event (candidate_profile_id, downloader_user_account_id, downloader_organisation_id, wallet_ledger_entry_id) VALUES (%s, %s, %s, %s)', cand, u_out, o_b, e_dl2),
        'download charged to another organisation''s wallet');
    PERFORM t_expect_fail(format('INSERT INTO profile_download_event (candidate_profile_id, downloader_user_account_id, downloader_organisation_id, wallet_ledger_entry_id) VALUES (%s, %s, %s, %s)', cand, u_emp, o_a, e_rech),
        'download charged to a recharge entry');
    PERFORM t_expect_fail('DELETE FROM profile_download_event', 'deleting download history');
END $$;
ROLLBACK;

-- -----------------------------------------------------------------------------
-- Part 2: device limit under concurrent logins. Committed fixtures (unique names, so
-- --no-build re-runs work); two separate connections log the same user in at once.
-- -----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS dblink;
SET app.current_user_id = '1';
CREATE TEMP TABLE t_conc (uid bigint, dev1 bigint, dev2 bigint);
DO $$
DECLARE k text := md5(clock_timestamp()::text); u bigint; o bigint; p bigint; s bigint; l bigint; d1 bigint; d2 bigint;
BEGIN
    INSERT INTO user_account (email) VALUES ('m14.conc.' || k || '@acme.test') RETURNING id INTO u;
    INSERT INTO organisation (legal_name) VALUES ('M14 Concurrency ' || k) RETURNING id INTO o;
    INSERT INTO organisation_member (organisation_id, user_account_id, role_id) VALUES (o, u, 7);
    INSERT INTO plan (code, ui_label_key_id, billing_period_id, price_amount, price_currency_id, max_users, max_devices_per_user)
    VALUES ('m14_conc_' || k, (SELECT min(id) FROM ui_label_key), 1, 100, (SELECT min(id) FROM currency), 1, 1) RETURNING id INTO p;
    INSERT INTO subscription (organisation_id, plan_id, subscription_status_id) VALUES (o, p, 2) RETURNING id INTO s;
    INSERT INTO licence (organisation_id, subscription_id, licence_status_id, max_users, max_devices_per_user) VALUES (o, s, 1, 1, 1) RETURNING id INTO l;
    INSERT INTO licence_seat (licence_id, user_account_id) VALUES (l, u);
    INSERT INTO user_device (user_account_id, device_platform_id, device_fingerprint_hmac) VALUES (u, 1, '\x01') RETURNING id INTO d1;
    INSERT INTO user_device (user_account_id, device_platform_id, device_fingerprint_hmac) VALUES (u, 2, '\x02') RETURNING id INTO d2;
    INSERT INTO t_conc VALUES (u, d1, d2);
END $$;
SELECT uid, dev1, dev2 FROM t_conc \gset
\set login 'SELECT app_open_session(%s, %s, ''\\x11''::bytea, decode(md5(random()::text), ''hex''), now() + interval ''1 hour'')'

-- c1 logs in inside an open transaction (holding the seat lock); c2 logs in at the same time
SELECT dblink_connect('c1', 'dbname=talentra user=postgres') \g /dev/null
SELECT dblink_connect('c2', 'dbname=talentra user=postgres') \g /dev/null
SELECT dblink_exec('c1', 'BEGIN') \g /dev/null
CREATE TEMP TABLE t_c1 AS SELECT * FROM dblink('c1', format(:'login', :uid, :dev1)) AS t(session_id bigint);
SELECT dblink_send_query('c2', format(:'login', :uid, :dev2)) \g /dev/null
SELECT pg_sleep(1) \g /dev/null
CREATE TEMP TABLE t_busy AS SELECT dblink_is_busy('c2') AS busy;
SELECT dblink_exec('c1', 'COMMIT') \g /dev/null
CREATE TEMP TABLE t_c2 AS SELECT * FROM dblink_get_result('c2') AS t(session_id bigint);
SELECT dblink_disconnect('c1') \g /dev/null
SELECT dblink_disconnect('c2') \g /dev/null

DO $$
DECLARE u bigint := (SELECT uid FROM t_conc); n int;
BEGIN
    IF (SELECT session_id FROM t_c1) IS NULL THEN RAISE EXCEPTION 'FAIL first concurrent login was refused'; END IF;
    IF (SELECT busy FROM t_busy) <> 1 THEN
        RAISE EXCEPTION 'FAIL second concurrent login did not wait for the first (no lock on the seat)';
    END IF;
    RAISE NOTICE 'PASS second concurrent login waited on the seat lock while the first was open';
    IF (SELECT session_id FROM t_c2) IS NOT NULL THEN RAISE EXCEPTION 'FAIL both concurrent logins got a session'; END IF;
    SELECT count(*) INTO n FROM user_session WHERE user_account_id = u AND ended_at IS NULL;
    IF n <> 1 THEN RAISE EXCEPTION 'FAIL % live sessions with max_devices_per_user = 1', n; END IF;
    SELECT count(*) INTO n FROM login_attempt WHERE user_account_id = u AND login_outcome_id = 4;
    IF n <> 1 THEN RAISE EXCEPTION 'FAIL refused concurrent login not recorded'; END IF;
    RAISE NOTICE 'PASS device limit holds under concurrent logins: 1 live session, the other login refused and recorded (B45)';
END $$;
RESET app.current_user_id;
\echo MILESTONE 14 CHECKS PASSED
