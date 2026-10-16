-- Milestone 18 (B57-B59): keys and constraints for Notifications, Analytics and the shared team items.
-- Behavioural tests in one rolled-back transaction; visibility rules run as talentra_app.
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
    cu bigint; ra bigint; rb bigint; cn bigint; ux bigint; ad bigint; oa bigint; ob bigint; cp bigint; j_b bigint;
    n1 bigint; d_mail bigint; d_sms bigint; v_ts timestamptz; d record;
    loc bigint; v1 bigint; v2 bigint; djr bigint; dc bigint; c1 bigint;
    v_hash text := '$argon2id$v=19$m=65536,t=3,p=4$c29tZXNhbHQ$RdescudvJCsgt3ub+b+dWRWJTmaaJObG';
    v_part text := 'audit_event_p' || to_char(now(), 'YYYYMM');
BEGIN
    -- ---------------------------------------------------------------- setup
    INSERT INTO user_account (email) VALUES ('m18.cand@mail.test') RETURNING id INTO cu;
    INSERT INTO user_account (email) VALUES ('m18.rec.a@acme.test') RETURNING id INTO ra;
    INSERT INTO user_account (email) VALUES ('m18.rec.b@globex.test') RETURNING id INTO rb;
    INSERT INTO user_account (email) VALUES ('m18.con@freelance.test') RETURNING id INTO cn;
    INSERT INTO user_account (email) VALUES ('m18.x@mail.test') RETURNING id INTO ux;
    INSERT INTO user_account (email) VALUES ('m18.admin@talentra.test') RETURNING id INTO ad;
    INSERT INTO organisation (legal_name) VALUES ('M18 Acme') RETURNING id INTO oa;
    INSERT INTO organisation (legal_name) VALUES ('M18 Globex') RETURNING id INTO ob;
    INSERT INTO organisation_member (organisation_id, user_account_id, role_id) VALUES (oa, ra, 7), (ob, rb, 7);
    INSERT INTO user_account_role (user_account_id, role_id) VALUES (cn, 8), (ad, 2);
    PERFORM t_as(cu);
    INSERT INTO candidate_profile (user_account_id, full_name, profile_visibility_id) VALUES (cu, 'M18 Candidate', 1) RETURNING id INTO cp;
    INSERT INTO candidate_email (candidate_profile_id, email, is_primary) VALUES (cp, 'm18.cand@mail.test', true);
    INSERT INTO resume (candidate_profile_id, title) VALUES (cp, 'M18 CV');
    PERFORM t_as(1);
    INSERT INTO job_requirement (organisation_id, posted_by_user_account_id, title, description, job_category_id, employment_type_id,
        work_mode_id, job_requirement_status_id, publish_state_id, number_of_positions)
    VALUES (ob, rb, 'M18 Globex draft', 'x', 4, 1, 1, 1, 1, 1) RETURNING id INTO j_b;

    -- ---------------------------------------------------------------- B57 delivery write path
    INSERT INTO notification (recipient_user_account_id, notification_type_id, template_ref, summary)
    VALUES (cu, 1, 'application_moved', 'Your application moved to shortlisted') RETURNING id INTO n1;
    INSERT INTO notification_preference (user_account_id, notification_type_id, outreach_channel_id, is_enabled) VALUES (cu, 1, 2, false);
    INSERT INTO notification_delivery (notification_id, outreach_channel_id) VALUES (n1, 2) RETURNING id INTO d_sms;
    INSERT INTO notification_delivery (notification_id, outreach_channel_id) VALUES (n1, 1) RETURNING id INTO d_mail;
    PERFORM t_check((SELECT notification_delivery_status_id FROM notification_delivery WHERE id = d_sms) = 6
                AND (SELECT notification_delivery_status_id FROM notification_delivery WHERE id = d_mail) = 1,
        'channel switched off by the user is stored as suppressed at enqueue; the other channel is queued');
    PERFORM t_expect_fail(format('INSERT INTO notification_delivery (notification_id, outreach_channel_id, notification_delivery_status_id) VALUES (%s, 3, 3)', n1),
        'delivery inserted as already delivered');
    UPDATE notification_delivery SET notification_delivery_status_id = 2 WHERE id = d_mail;
    SELECT sent_at INTO v_ts FROM notification_delivery WHERE id = d_mail;
    UPDATE notification_delivery SET notification_delivery_status_id = 2, sent_at = now() + interval '1 hour' WHERE id = d_mail;
    PERFORM t_check(v_ts IS NOT NULL AND (SELECT sent_at FROM notification_delivery WHERE id = d_mail) = v_ts,
        'sent callback sets sent_at; a replayed callback changes nothing (idempotent)');
    UPDATE notification_delivery SET notification_delivery_status_id = 3 WHERE id = d_mail;
    UPDATE notification_delivery SET notification_delivery_status_id = 2 WHERE id = d_mail;
    UPDATE notification_delivery SET notification_delivery_status_id = 5 WHERE id = d_mail;
    SELECT * INTO d FROM notification_delivery WHERE id = d_mail;
    PERFORM t_check(d.notification_delivery_status_id = 3 AND d.delivered_at IS NOT NULL AND d.failed_at IS NULL,
        'late sent and failed callbacks after delivery are ignored: status never moves backwards');
    UPDATE notification_delivery SET notification_delivery_status_id = 4 WHERE id = d_mail;
    UPDATE notification_delivery SET notification_delivery_status_id = 1 WHERE id = d_mail;
    UPDATE notification_delivery SET notification_delivery_status_id = 2 WHERE id = d_sms;
    PERFORM t_check((SELECT notification_delivery_status_id FROM notification_delivery WHERE id = d_mail) = 4
                AND (SELECT notification_delivery_status_id FROM notification_delivery WHERE id = d_sms) = 6,
        'read and suppressed are final');
    PERFORM t_expect_fail(format('UPDATE notification_delivery SET outreach_channel_id = 3 WHERE id = %s', d_mail), 'moving a delivery to another channel');
    PERFORM t_check(NOT EXISTS (SELECT 1 FROM pg_inherits i JOIN pg_class c ON c.oid = i.inhrelid
                                WHERE i.inhparent = 'notification_delivery'::regclass AND NOT coalesce(c.reloptions, '{}') @> '{fillfactor=70}'),
        'every delivery partition keeps 30% free space for HOT status updates');
    PERFORM t_check(NOT EXISTS (SELECT 1 FROM pg_index x JOIN pg_attribute a ON a.attrelid = x.indrelid AND a.attnum = ANY (x.indkey)
                                WHERE x.indrelid = 'notification_delivery'::regclass
                                  AND a.attname IN ('notification_delivery_status_id', 'sent_at', 'delivered_at', 'failed_at')),
        'callback-updated columns carry no index (updates stay HOT)');
    CALL create_monthly_partitions('notification_delivery', DATE '2027-01-01', DATE '2027-02-01');
    PERFORM t_check((SELECT reloptions FROM pg_class WHERE relname = 'notification_delivery_p202701') @> '{fillfactor=70}',
        'a partition added later inherits the storage options');

    -- ---------------------------------------------------------------- B58 slowly changing dimensions and aggregates
    INSERT INTO dim_location (city_id, city_name, state_name, country_code) VALUES (900001, 'Chennai', 'Tamil Nadu', 'IN') RETURNING id INTO loc;
    CALL dim_organisation_apply(900001, 'Acme', 'employer', 'it_services', 'small', 'verified', loc, '2026-01-01');
    CALL dim_organisation_apply(900001, 'Acme Pvt Ltd', 'employer', 'it_services', 'small', 'verified', loc, '2026-03-01');
    PERFORM t_check((SELECT count(*) FROM dim_organisation WHERE organisation_id = 900001) = 1
                AND (SELECT display_name FROM dim_organisation WHERE organisation_id = 900001) = 'Acme Pvt Ltd',
        'type 1 attribute (name) corrected in place, no new version');
    CALL dim_organisation_apply(900001, 'Acme Pvt Ltd', 'employer', 'finance', 'small', 'verified', loc, '2026-06-01');
    v1 := dim_organisation_version(900001, '2026-02-01');
    v2 := dim_organisation_version(900001, '2026-07-01');
    PERFORM t_check(v1 <> v2 AND (SELECT valid_to = '2026-06-01' AND NOT is_current FROM dim_organisation WHERE id = v1)
                AND (SELECT is_current AND industry_code = 'finance' FROM dim_organisation WHERE id = v2),
        'type 2 change closes the old version and opens a new one; facts look up the version valid at the event');
    PERFORM t_expect_fail(format('INSERT INTO dim_organisation (organisation_id, display_name, organisation_type_code, verification_status_code, valid_from, is_current) VALUES (900001, ''x'', ''employer'', ''verified'', ''2026-09-01'', true)'),
        'second open version of the same organisation');
    PERFORM t_expect_fail('INSERT INTO dim_organisation (organisation_id, display_name, organisation_type_code, verification_status_code, valid_from, valid_to, is_current) VALUES (900002, ''x'', ''employer'', ''verified'', ''2026-01-01'', ''2026-02-01'', true)',
        'closed version flagged as current');
    PERFORM t_expect_fail('INSERT INTO dim_organisation (organisation_id, display_name, organisation_type_code, verification_status_code, valid_from, valid_to, is_current) VALUES (900001, ''x'', ''employer'', ''verified'', ''2026-05-01'', ''2026-07-01'', false)',
        'overlapping versions of one organisation');

    INSERT INTO dim_candidate (candidate_profile_id, experience_band_code, is_fresher, profile_completion_pct, registered_date_id, valid_from, is_current)
    VALUES (900001, '1_3', false, 70, 20260101, '2026-01-01', true) RETURNING id INTO dc;
    INSERT INTO dim_job_requirement (job_requirement_id, dim_organisation_id, employment_type_code, work_mode_code, is_open_to_consultants)
    VALUES (900001, v2, 'full_time', 'onsite', false) RETURNING id INTO djr;
    INSERT INTO fact_application (application_id, dim_job_requirement_id, dim_candidate_id, dim_organisation_id, applied_date_id, current_stage_code, application_source_code)
    VALUES (900001, djr, dc, v2, 20260715, 'applied', 'portal');
    PERFORM t_check(NOT EXISTS (SELECT 1 FROM agg_hiring_funnel_monthly WHERE organisation_id = 900001), 'aggregate is stale until refreshed');
    CALL refresh_aggregates();
    PERFORM t_check((SELECT applied_count FROM agg_hiring_funnel_monthly WHERE organisation_id = 900001 AND month_start = '2026-07-01') = 1
                AND (SELECT count(*) FROM agg_refresh_log WHERE created_at = now()) = 4,
        'refresh_aggregates() refreshes all 4 aggregates concurrently and logs each refresh');
    PERFORM t_expect_fail('UPDATE agg_refresh_log SET row_count = 0', 'editing the refresh log');

    -- ---------------------------------------------------------------- B59 append-only audit trail
    PERFORM t_expect_fail('TRUNCATE audit_event', 'truncating the audit trail');
    PERFORM t_expect_fail(format('TRUNCATE %I', v_part), 'truncating one month of the audit trail directly');
    CALL create_monthly_partitions('audit_event', DATE '2027-01-01', DATE '2027-02-01');
    PERFORM t_expect_fail('TRUNCATE audit_event_p202701', 'truncating an audit partition created later');
    PERFORM t_expect_fail('TRUNCATE profile_view_event_pdefault', 'truncating a Phase 1 history partition directly');
    PERFORM t_expect_fail('TRUNCATE system_error_event_pdefault', 'truncating the error log');
    INSERT INTO consent_record (user_account_id, consent_purpose_id, policy_version, is_granted) VALUES (cu, 3, '2026.1', true);
    PERFORM t_expect_fail('UPDATE consent_record SET is_granted = false', 'rewriting a consent instead of recording a withdrawal');

    -- ---------------------------------------------------------------- B59 credentials
    PERFORM t_expect_fail(format('INSERT INTO user_credential (user_account_id, credential_type_id, password_hash) VALUES (%s, 1, ''hunter2'')', cu), 'password stored in clear');
    INSERT INTO user_credential (user_account_id, credential_type_id, password_hash) VALUES (cu, 1, v_hash) RETURNING id INTO c1;
    PERFORM t_expect_fail(format('INSERT INTO user_credential (user_account_id, credential_type_id, password_hash) VALUES (%s, 1, %L)', cu, v_hash), 'second live password for one user');
    PERFORM t_expect_fail(format('UPDATE user_credential SET password_hash = %L WHERE id = %s', replace(v_hash, 't=3', 't=4'), c1), 'changing a password hash in place');
    UPDATE user_credential SET revoked_at = now() WHERE id = c1;
    INSERT INTO user_credential (user_account_id, credential_type_id, password_hash) VALUES (cu, 1, replace(v_hash, 't=3', 't=4'));
    RAISE NOTICE 'PASS password rotation = revoke + new credential (history kept)';
    PERFORM t_expect_fail(format('UPDATE user_credential SET revoked_at = NULL WHERE id = %s', c1), 'reviving a revoked credential');
    INSERT INTO user_credential (user_account_id, credential_type_id, provider_subject_hmac) VALUES (cu, 2, decode(repeat('ab', 32), 'hex'));
    PERFORM t_expect_fail(format('INSERT INTO user_credential (user_account_id, credential_type_id, provider_subject_hmac) VALUES (%s, 2, decode(repeat(''ab'', 32), ''hex''))', ra),
        'one Google identity linked to two users');
    PERFORM t_expect_fail(format('INSERT INTO user_credential (user_account_id, credential_type_id, provider_subject_hmac) VALUES (%s, 3, ''\x01'')', ra), 'subject hash that is not HMAC-SHA256');

    -- ---------------------------------------------------------------- B59 blocking and visibility (as the application role)
    PERFORM t_expect_fail(format('INSERT INTO block_entry (blocker_user_account_id, blocked_user_account_id) VALUES (%s, %s)', cu, ra), 'block filed on the candidate''s behalf');
    EXECUTE 'SET LOCAL ROLE talentra_app';
    PERFORM t_as(ra);
    PERFORM t_check((SELECT count(*) FROM candidate_profile WHERE id = cp) = 1 AND (SELECT count(*) FROM candidate_email WHERE candidate_profile_id = cp) = 1,
        'recruiter sees a public candidate profile and its contact details');
    PERFORM t_check((SELECT count(*) FROM v_job_requirement WHERE id = j_b) = 0,
        'recruiter cannot read another company''s draft through v_job_requirement (view runs with the caller''s rights)');
    PERFORM t_as(cu);
    INSERT INTO block_entry (blocker_user_account_id, blocked_user_account_id, block_reason_id) VALUES (cu, ra, 1);
    PERFORM t_expect_fail(format('INSERT INTO block_entry (blocker_user_account_id, blocked_user_account_id) VALUES (%s, %s)', cu, ra), 'blocking the same recruiter twice');
    PERFORM t_as(ra);
    PERFORM t_check((SELECT count(*) FROM candidate_profile WHERE id = cp) = 0 AND (SELECT count(*) FROM v_candidate_profile WHERE id = cp) = 0
                AND (SELECT count(*) FROM candidate_email WHERE candidate_profile_id = cp) = 0 AND (SELECT count(*) FROM resume WHERE candidate_profile_id = cp) = 0,
        'blocked recruiter no longer sees the candidate: profile, view, contact details and resume (docket §3)');
    PERFORM t_check((SELECT count(*) FROM block_entry) = 0, 'blocked recruiter cannot see the block itself');
    PERFORM t_as(rb);
    PERFORM t_check((SELECT count(*) FROM candidate_profile WHERE id = cp) = 1, 'a recruiter of another company still sees the candidate');
    PERFORM t_as(cu);
    INSERT INTO block_entry (blocker_user_account_id, blocked_organisation_id) VALUES (cu, ob);
    PERFORM t_as(rb);
    PERFORM t_check((SELECT count(*) FROM candidate_profile WHERE id = cp) = 0, 'blocking a company hides the candidate from all its recruiters');
    PERFORM t_as(cu);
    PERFORM t_check((SELECT count(*) FROM candidate_profile WHERE id = cp) = 1 AND (SELECT count(*) FROM block_entry) = 2,
        'candidate sees own profile and own block list');
    UPDATE block_entry SET unblocked_at = now() WHERE blocked_user_account_id = ra;
    PERFORM t_expect_fail(format('UPDATE block_entry SET unblocked_at = NULL WHERE blocked_user_account_id = %s', ra), 'undoing an unblock (block again instead)');
    PERFORM t_as(ra);
    PERFORM t_check((SELECT count(*) FROM candidate_profile WHERE id = cp) = 1, 'unblocked recruiter sees the candidate again');

    PERFORM t_as(cu);
    UPDATE candidate_profile SET profile_visibility_id = 3 WHERE id = cp;
    PERFORM t_as(cn);
    PERFORM t_check((SELECT count(*) FROM candidate_profile WHERE id = cp) = 0, 'hidden profile is invisible to others');
    PERFORM t_as(ad);
    PERFORM t_check((SELECT count(*) FROM candidate_profile WHERE id = cp) = 1, 'platform admin still sees a hidden profile');
    PERFORM t_as(cu);
    UPDATE candidate_profile SET profile_visibility_id = 2 WHERE id = cp;
    PERFORM t_as(cn);
    PERFORM t_check((SELECT count(*) FROM candidate_profile WHERE id = cp) = 1, 'employers-only profile visible to a consultant');
    PERFORM t_as(ux);
    PERFORM t_check((SELECT count(*) FROM candidate_profile WHERE id = cp) = 0, 'employers-only profile invisible to a user with no organisation or consultant role');
    PERFORM t_as(ra);   -- unblocked organisation member: can see the employers-only profile, but is not its owner
    PERFORM t_check((SELECT count(*) FROM candidate_profile WHERE id = cp) = 1, 'organisation recruiter sees the employers-only profile');
    UPDATE candidate_profile SET full_name = 'Hacked' WHERE id = cp;
    EXECUTE 'RESET ROLE';
    PERFORM t_check((SELECT full_name FROM candidate_profile WHERE id = cp) = 'M18 Candidate',
        'a recruiter who can see the profile cannot edit it (update touches no rows)');

    PERFORM t_check(NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace s ON s.oid = c.relnamespace
                                WHERE s.nspname = 'public' AND c.relkind = 'v' AND NOT coalesce(c.reloptions, '{}') @> '{security_invoker=true}'),
        'every view runs with the caller''s rights, so row-level security applies through views');
END $$;
ROLLBACK;
\echo MILESTONE 18 CHECKS PASSED
