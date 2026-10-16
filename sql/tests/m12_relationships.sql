-- Milestone 12 (B39-B41): Licences, Sourcing and Subscriptions relationships exist with the stated
-- cardinality and delete rule (same checker as m3 and m8).
\set ON_ERROR_STOP on
CREATE TEMP TABLE expected_fk (child text, cols text, parent text, on_delete char, one_to_one boolean);
-- on_delete: r = RESTRICT, c = CASCADE, n = SET NULL
INSERT INTO expected_fk VALUES
 -- B41 Subscriptions: plan -> subscription -> period, payments, wallet -> ledger, downloads
 ('plan_entitlement','plan_id','plan','c', false),
 ('subscription','organisation_id','organisation','r', false),
 ('subscription','plan_id','plan','r', false),
 ('subscription_period','subscription_id','subscription','r', false),
 ('subscription_period','payment_order_id','payment_order','r', true),
 ('payment_order','organisation_id','organisation','r', false),
 ('payment_order','placed_by_user_account_id','user_account','r', false),
 ('payment_event','payment_order_id','payment_order','r', false),
 ('invoice','payment_order_id','payment_order','r', true),
 ('refund','payment_order_id','payment_order','r', false),
 ('wallet','organisation_id','organisation','r', true),
 ('wallet_ledger_entry','wallet_id','wallet','r', false),
 ('wallet_ledger_entry','payment_order_id','payment_order','r', true),
 ('wallet_ledger_entry','refund_id','refund','r', true),
 ('wallet_ledger_entry','reverses_wallet_ledger_entry_id','wallet_ledger_entry','r', true),
 ('profile_download_event','candidate_profile_id','candidate_profile','r', false),
 ('profile_download_event','downloader_user_account_id','user_account','r', false),
 ('profile_download_event','wallet_ledger_entry_id','wallet_ledger_entry','r', false),
 ('profile_view_event','wallet_ledger_entry_id','wallet_ledger_entry','r', false),
 -- B39 Licences: subscription -> licence -> seat -> user; user -> device -> session
 ('licence','subscription_id,organisation_id','subscription','r', true),
 ('licence_seat','licence_id','licence','r', false),
 ('licence_seat','user_account_id','user_account','r', false),
 ('user_device','user_account_id','user_account','r', false),
 ('user_session','user_account_id','user_account','r', false),
 ('user_session','user_device_id,user_account_id','user_device','r', false),
 ('user_session','licence_seat_id,user_account_id','licence_seat','r', false),
 ('login_attempt','user_account_id','user_account','r', false),
 ('login_attempt','user_device_id,user_account_id','user_device','r', false),
 ('session_revocation_event','user_session_id','user_session','r', false),
 ('session_revocation_event','user_session_id,user_device_id','user_session','r', false),
 ('session_revocation_event','user_device_id','user_device','r', false),
 -- B40 Sourcing: requirement / consultant -> request -> shortlist, outreach -> recipient -> candidate
 ('sourcing_request','job_requirement_id','job_requirement','r', false),
 ('sourcing_request','consultant_user_account_id','user_account','r', false),
 ('sourcing_request','decided_by_user_account_id','user_account','r', false),
 ('talent_list','sourcing_request_id','sourcing_request','r', false),
 ('outreach_batch','sender_user_account_id','user_account','r', false),
 ('outreach_batch','sourcing_request_id,job_requirement_id','sourcing_request','r', false),
 ('outreach_batch','wallet_ledger_entry_id','wallet_ledger_entry','r', true),
 ('outreach_recipient','outreach_batch_id','outreach_batch','r', false),
 ('outreach_recipient','candidate_profile_id','candidate_profile','r', false);

\ir check_expected_fk.sql

-- Composite FKs only bite when every column is set (MATCH SIMPLE): prove that pinned pairs cannot
-- be mixed across owners. Runs in a rolled-back transaction.
BEGIN;
SET LOCAL app.current_user_id = '1';
DO $$
DECLARE u1 bigint; u2 bigint; d2 bigint; o1 bigint; o2 bigint; p1 bigint; s1 bigint; r1 bigint; j1 bigint; j2 bigint;
BEGIN
    INSERT INTO user_account (email) VALUES ('m12a@example.com') RETURNING id INTO u1;
    INSERT INTO user_account (email) VALUES ('m12b@example.com') RETURNING id INTO u2;
    INSERT INTO user_device (user_account_id, device_platform_id, device_fingerprint_hmac)
    VALUES (u2, 1, '\x01') RETURNING id INTO d2;
    BEGIN
        INSERT INTO user_session (user_account_id, user_device_id, session_token_hash, expires_at)
        VALUES (u1, d2, '\x02', now() + interval '1 hour');
        RAISE EXCEPTION 'FAIL session accepted on another user''s device';
    EXCEPTION WHEN foreign_key_violation THEN
        RAISE NOTICE 'PASS rejected: session on another user''s device (fk_user_session_user_device)';
    END;

    INSERT INTO organisation (legal_name) VALUES ('M12 Subscriber Ltd') RETURNING id INTO o1;
    INSERT INTO organisation (legal_name) VALUES ('M12 Other Ltd') RETURNING id INTO o2;
    INSERT INTO plan (code, ui_label_key_id, billing_period_id, price_amount, price_currency_id, max_users, max_devices_per_user)
    VALUES ('m12_plan', (SELECT min(id) FROM ui_label_key), 1, 100, (SELECT min(id) FROM currency), 5, 2) RETURNING id INTO p1;
    INSERT INTO subscription (organisation_id, plan_id, subscription_status_id) VALUES (o1, p1, 2) RETURNING id INTO s1;
    BEGIN
        INSERT INTO licence (organisation_id, subscription_id, licence_status_id, max_users, max_devices_per_user)
        VALUES (o2, s1, 1, 1, 1);
        RAISE EXCEPTION 'FAIL licence accepted for an organisation that did not subscribe';
    EXCEPTION WHEN foreign_key_violation THEN
        RAISE NOTICE 'PASS rejected: licence for another organisation''s subscription (fk_licence_subscription)';
    END;

    INSERT INTO job_requirement (organisation_id, posted_by_user_account_id, title, description, job_category_id,
        employment_type_id, work_mode_id, job_requirement_status_id, publish_state_id, number_of_positions)
    VALUES (o1, u2, 'M12 job one', 'x', 4, 1, 1, 1, 1, 1) RETURNING id INTO j1;
    INSERT INTO job_requirement (organisation_id, posted_by_user_account_id, title, description, job_category_id,
        employment_type_id, work_mode_id, job_requirement_status_id, publish_state_id, number_of_positions)
    VALUES (o1, u2, 'M12 job two', 'x', 4, 1, 1, 1, 1, 1) RETURNING id INTO j2;
    -- the M14 rules run first, so the request is valid and accepted: u1 consultant, u2 employer, job open to consultants
    UPDATE job_requirement SET is_open_to_consultants = true, job_requirement_status_id = 3 WHERE id = j1;
    INSERT INTO user_account_role (user_account_id, role_id) VALUES (u1, 8);
    INSERT INTO organisation_member (organisation_id, user_account_id, role_id) VALUES (o1, u2, 6);
    PERFORM set_config('app.current_user_id', u1::text, true);
    INSERT INTO sourcing_request (job_requirement_id, consultant_user_account_id) VALUES (j1, u1) RETURNING id INTO r1;
    PERFORM set_config('app.current_user_id', u2::text, true);
    UPDATE sourcing_request SET sourcing_request_status_id = 2 WHERE id = r1;
    PERFORM set_config('app.current_user_id', u1::text, true);
    BEGIN
        INSERT INTO outreach_batch (sender_user_account_id, job_requirement_id, sourcing_request_id, outreach_channel_id, message_template_ref)
        VALUES (u1, j2, r1, 1, 'tpl');
        RAISE EXCEPTION 'FAIL outreach accepted for a requirement other than the sourcing request''s';
    EXCEPTION WHEN foreign_key_violation THEN
        RAISE NOTICE 'PASS rejected: outreach under a sourcing request for a different requirement (fk_outreach_batch_sourcing_request)';
    END;
END $$;
ROLLBACK;
