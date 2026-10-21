-- V011 API functions (registration, outbox worker, erasure), runtime roles, privileges and row-level security.
-- Requirements: NFR-SEC-01..05, NFR-PRIV-01..04, docket section 3 (privileges enforced in the database).
-- Owner (migration role) bypasses RLS; every runtime path goes through v2_app, v2_payments, v2_worker or v2_reporting.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'v2_payments') THEN CREATE ROLE v2_payments NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'v2_worker') THEN CREATE ROLE v2_worker NOLOGIN; END IF;
END $$;
GRANT USAGE ON SCHEMA public TO v2_payments, v2_worker;

-- Self-registration of a candidate. Recruiters and employers cannot register candidates (docket section 3): the
-- function refuses any signed-in caller except staff (assisted registration at a placement drive is staff-run).
CREATE FUNCTION auth_register_candidate(p_email text, p_password_hash text, p_full_name text, p_phone_e164 text DEFAULT NULL,
                                        p_phone_country_id smallint DEFAULT NULL, p_language_id smallint DEFAULT 1,
                                        p_policy_version text DEFAULT '2026-01')
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u bigint; p bigint;
BEGIN
  IF app_current_user_id() IS NOT NULL AND NOT app_is_staff() THEN
    RAISE EXCEPTION 'candidates register themselves; a signed-in user cannot register a candidate' USING ERRCODE = 'insufficient_privilege';
  END IF;
  INSERT INTO app_user (email, phone_e164, phone_country_id, preferred_language_id)
  VALUES (lower(p_email), p_phone_e164, p_phone_country_id, p_language_id) RETURNING id INTO u;
  INSERT INTO user_credential (app_user_id, password_hash) VALUES (u, p_password_hash);
  INSERT INTO user_access_role (app_user_id, access_role_id) VALUES (u, 8);
  INSERT INTO candidate_profile (app_user_id, full_name, profile_language_id, created_by) VALUES (u, p_full_name, p_language_id, u) RETURNING id INTO p;
  INSERT INTO consent_record (app_user_id, consent_purpose_id, is_granted, policy_version, created_by)
  VALUES (u, 1, true, p_policy_version, u), (u, 2, true, p_policy_version, u);
  RETURN p;
END $$;

-- Employer sign-up: the user, the organisation (verification pending), its wallet, and the user as account admin.
CREATE FUNCTION auth_register_employer(p_email text, p_password_hash text, p_legal_name text, p_display_name text,
                                       p_industry_id smallint, p_country_id smallint, p_policy_version text DEFAULT '2026-01')
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u bigint; o bigint;
BEGIN
  IF app_current_user_id() IS NOT NULL AND NOT app_is_staff() THEN
    RAISE EXCEPTION 'employers register themselves' USING ERRCODE = 'insufficient_privilege';
  END IF;
  INSERT INTO app_user (email) VALUES (lower(p_email)) RETURNING id INTO u;
  INSERT INTO user_credential (app_user_id, password_hash) VALUES (u, p_password_hash);
  INSERT INTO user_access_role (app_user_id, access_role_id) VALUES (u, 3);
  INSERT INTO organisation (legal_name, display_name, industry_id, country_id, created_by) VALUES (p_legal_name, p_display_name, p_industry_id, p_country_id, u) RETURNING id INTO o;
  INSERT INTO wallet (organisation_id, created_by) VALUES (o, u);
  INSERT INTO organisation_member (organisation_id, app_user_id, access_role_id, created_by) VALUES (o, u, 3, u);
  INSERT INTO consent_record (app_user_id, consent_purpose_id, is_granted, policy_version, created_by)
  VALUES (u, 1, true, p_policy_version, u), (u, 2, true, p_policy_version, u);
  RETURN o;
END $$;

-- Outbox worker (v2_worker). Claims due rows with SKIP LOCKED so many workers never take the same row, and leases them
-- for 5 minutes: if a worker dies, the rows become due again.
CREATE FUNCTION notification_claim(p_limit integer DEFAULT 100) RETURNS SETOF notification
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
    UPDATE notification n SET attempt_count = n.attempt_count + 1, next_attempt_at = now() + interval '5 minutes'
    WHERE n.id IN (SELECT id FROM notification WHERE notification_status_id = 1 AND next_attempt_at <= now() AND attempt_count < 10
                   ORDER BY next_attempt_at LIMIT p_limit FOR UPDATE SKIP LOCKED)
    RETURNING n.*
$$;

-- Result of one delivery attempt. A failure is retried with exponential backoff up to 5 attempts, then marked failed.
CREATE FUNCTION notification_record_result(p_notification_id bigint, p_status_code text, p_provider_message_ref text DEFAULT NULL,
                                           p_failure_reason text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n notification;
BEGIN
  SELECT * INTO n FROM notification WHERE id = p_notification_id FOR UPDATE;
  IF p_status_code = 'failed' AND n.attempt_count < 5 THEN
    UPDATE notification SET next_attempt_at = now() + make_interval(mins => 2 ^ n.attempt_count) WHERE id = n.id;
  ELSE
    UPDATE notification SET notification_status_id = (SELECT id FROM notification_status WHERE code = p_status_code),
           provider_message_ref = coalesce(p_provider_message_ref, provider_message_ref),
           sent_at = CASE WHEN p_status_code IN ('sent', 'delivered') THEN coalesce(sent_at, now()) ELSE sent_at END,
           delivered_at = CASE WHEN p_status_code = 'delivered' THEN now() ELSE delivered_at END,
           failure_reason = CASE WHEN p_status_code = 'failed' THEN coalesce(p_failure_reason, 'unknown') END
    WHERE id = n.id;
  END IF;
END $$;

-- Right to erasure (NFR-PRIV-04): on request by the candidate or staff, and by the retention job after 3 years of
-- inactivity. Personal data is deleted or blanked; rows other parties legitimately keep (applications, downloads,
-- consent evidence, ledgers) stay, pointing at an anonymous profile. Resume files are deleted through the outbox.
CREATE FUNCTION candidate_erase(p_candidate_profile_id bigint) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE p candidate_profile;
BEGIN
  SELECT * INTO p FROM candidate_profile WHERE id = p_candidate_profile_id FOR UPDATE;
  IF NOT FOUND OR NOT (p.app_user_id = app_current_user_id() OR app_is_staff() OR app_current_user_id() IS NULL) THEN
    RAISE EXCEPTION 'candidate profile % not found', p_candidate_profile_id USING ERRCODE = 'no_data_found';
  END IF;
  INSERT INTO notification (app_user_id, notification_category_id, notification_channel_id, template_key, payload)
  SELECT p.app_user_id, 3, 4, 'storage.delete_resume', jsonb_build_object('storage_key', storage_key) FROM resume WHERE candidate_profile_id = p.id;
  DELETE FROM candidate_education WHERE candidate_profile_id = p.id;
  DELETE FROM candidate_experience WHERE candidate_profile_id = p.id;
  DELETE FROM candidate_skill WHERE candidate_profile_id = p.id;
  DELETE FROM candidate_language WHERE candidate_profile_id = p.id;
  DELETE FROM job_alert WHERE candidate_profile_id = p.id;
  UPDATE application SET resume_id = NULL WHERE candidate_profile_id = p.id AND resume_id IS NOT NULL;
  DELETE FROM resume WHERE candidate_profile_id = p.id;
  UPDATE candidate_profile SET full_name = 'Erased candidate ' || p.id, headline = NULL, summary = NULL, current_city_id = NULL,
         expected_salary_amount = NULL, expected_salary_currency_id = NULL, salary_disclosure_id = 3, notice_period_days = NULL,
         is_open_to_work = false, profile_visibility_id = 3, deleted_at = now()
  WHERE id = p.id;
  UPDATE user_session SET ended_at = now(), session_end_reason_id = 4 WHERE app_user_id = p.app_user_id AND ended_at IS NULL;
  DELETE FROM user_credential WHERE app_user_id = p.app_user_id;
  UPDATE app_user SET email = NULL, phone_e164 = NULL, phone_country_id = NULL, account_status_id = 4, deleted_at = now()
  WHERE id = p.app_user_id;
  PERFORM audit_log('candidate_profile.erased', 'candidate_profile', p.id);
END $$;

CREATE FUNCTION retention_erase_inactive(p_inactive interval DEFAULT interval '3 years') RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r record; n int := 0;
BEGIN
  FOR r IN SELECT id FROM candidate_profile WHERE deleted_at IS NULL AND last_active_at < now() - p_inactive LOOP
    PERFORM candidate_erase(r.id); n := n + 1;
  END LOOP;
  RETURN n;
END $$;

------------------------------------------------------------------------------------------------------------------------
-- Privileges. Functions: nothing for PUBLIC; each role gets exactly its entry points.
DO $$
DECLARE f regprocedure;
BEGIN
  FOR f IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'public' AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e') LOOP
    EXECUTE format('REVOKE ALL ON ROUTINE %s FROM PUBLIC', f);
  END LOOP;
END $$;

-- helpers that policies and invoker-rights triggers call while running as the caller
GRANT EXECUTE ON FUNCTION app_current_user_id(), app_viewer_organisation_id(), app_viewer_candidate_profile_id(), app_has_permission(text),
    app_is_staff(), app_candidates_blocking_viewer(), app_candidate_visible(bigint, bigint, smallint, timestamptz), ui_text(integer, smallint),
    pii_hmac(text), set_audit_columns(), forbid_change(), subscription_guard(), notification_apply_preference(), organisation_prevent_cycle()
    TO v2_app, v2_payments, v2_worker, v2_reporting;
-- API entry points
GRANT EXECUTE ON FUNCTION auth_register_candidate(text, text, text, text, smallint, smallint, text),
    auth_register_employer(text, text, text, text, smallint, smallint, text), auth_open_session(bigint, bytea, text, bytea, interval),
    auth_end_session(bigint, text), billing_download_profile(bigint), candidate_contact(bigint), app_can_view_candidate(bigint),
    candidate_erase(bigint), audit_log(text, text, bigint, bigint, jsonb, timestamptz) TO v2_app;
GRANT EXECUTE ON FUNCTION billing_apply_payment_event(bigint, text, text, numeric, timestamptz, bytea) TO v2_payments;
GRANT EXECUTE ON FUNCTION notification_claim(integer), notification_record_result(bigint, text, text, text) TO v2_worker;

GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO v2_app;

-- Reference data: readable by every runtime role.
DO $$
DECLARE t text;
BEGIN
  FOR t IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
           WHERE n.nspname = 'public' AND c.relkind = 'r' AND NOT EXISTS (
             SELECT 1 FROM pg_attribute a WHERE a.attrelid = c.oid AND a.attname = 'created_by')
             AND c.relname NOT IN ('audit_event', 'system_error') AND c.relispartition = false LOOP
    EXECUTE format('GRANT SELECT ON %I TO v2_app, v2_reporting, v2_payments, v2_worker', t);
  END LOOP;
END $$;
GRANT SELECT ON plan TO v2_app, v2_reporting;

-- Table privileges of the API role (row-level security below narrows them to rows).
GRANT SELECT ON app_user, user_access_role, consent_record, consent_current, user_device, user_session, organisation, organisation_location,
    organisation_tax_identifier, organisation_member, candidate_profile, candidate_education, candidate_experience, candidate_skill,
    candidate_language, resume, candidate_block, job_requirement, job_requirement_location, job_requirement_skill, screening_question,
    application, application_answer, application_status_history, subscription, wallet, wallet_ledger_entry, payment_order, payment_event,
    invoice, profile_download, notification_preference, job_alert, notification, audit_event TO v2_app;
GRANT UPDATE (phone_e164, phone_country_id, preferred_language_id, time_zone) ON app_user TO v2_app;
GRANT INSERT ON consent_record, candidate_education, candidate_experience, candidate_skill, candidate_language, resume, candidate_block,
    organisation_location, organisation_tax_identifier, organisation_member, job_requirement, job_requirement_location,
    job_requirement_skill, screening_question, application, application_answer, payment_order, notification_preference, job_alert,
    system_error TO v2_app;
GRANT UPDATE, DELETE ON candidate_education, candidate_experience, candidate_skill, candidate_language, organisation_location,
    job_requirement_location, job_requirement_skill, screening_question, notification_preference, job_alert TO v2_app;
GRANT UPDATE (headline, summary, profile_language_id, current_city_id, total_experience_months, expected_salary_amount,
    expected_salary_currency_id, salary_disclosure_id, notice_period_days, is_open_to_work, profile_visibility_id, last_active_at, full_name)
    ON candidate_profile TO v2_app;
GRANT UPDATE (is_primary, content_language_id) ON resume TO v2_app;
GRANT UPDATE (unblocked_at) ON candidate_block TO v2_app;
GRANT UPDATE (display_name, website_url, industry_id, parent_organisation_id) ON organisation TO v2_app;
GRANT UPDATE (valid_to) ON organisation_member TO v2_app;
GRANT UPDATE (title, description, description_language_id, employment_type_id, work_mode_id, industry_id, min_experience_months,
    max_experience_months, salary_min_amount, salary_max_amount, salary_currency_id, salary_disclosure_id, positions_total,
    job_status_id, is_open_to_consultants, published_at, closes_on, deleted_at) ON job_requirement TO v2_app;
GRANT UPDATE (application_status_id, status_changed_at) ON application TO v2_app;
GRANT UPDATE (auto_renew, cancelled_at, ends_on) ON subscription TO v2_app;
GRANT UPDATE (gateway_order_ref) ON payment_order TO v2_payments;
GRANT SELECT ON payment_order TO v2_payments;

------------------------------------------------------------------------------------------------------------------------
-- Row-level security. Helpers are wrapped in (SELECT ...) so they run once per statement, not once per row.
ALTER TABLE app_user ENABLE ROW LEVEL SECURITY;
CREATE POLICY app_user_self ON app_user USING (id = (SELECT app_current_user_id()) OR (SELECT app_is_staff()));

-- Rows that belong to one user: the user, and staff for support.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['user_access_role', 'consent_record', 'user_device', 'user_session', 'notification_preference', 'notification'] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY %I ON %I USING (app_user_id = (SELECT app_current_user_id()) OR (SELECT app_is_staff()))
                    WITH CHECK (app_user_id = (SELECT app_current_user_id()))', t || '_owner', t);
  END LOOP;
END $$;

ALTER TABLE candidate_profile ENABLE ROW LEVEL SECURITY;
-- Same rule as app_candidate_visible(), written inline: PostgreSQL does not inline a function containing sub-selects,
-- so calling it here would run the viewer lookups once per row (measured: 3.7 s for a name search at 10k profiles).
-- Inline, each (SELECT ...) is an init plan evaluated once per query. Test t03 checks the two stay equivalent.
CREATE POLICY candidate_profile_read ON candidate_profile FOR SELECT USING (
       app_user_id = (SELECT app_current_user_id())
    OR (SELECT app_is_staff())
    OR ((SELECT app_has_permission('candidate_search')) AND deleted_at IS NULL AND profile_visibility_id <> 3
        AND NOT id = ANY ((SELECT app_candidates_blocking_viewer())::bigint[])));
CREATE POLICY candidate_profile_owner_update ON candidate_profile FOR UPDATE
    USING (app_user_id = (SELECT app_current_user_id())) WITH CHECK (app_user_id = (SELECT app_current_user_id()));

-- Profile sections: readable when the profile is (the subquery runs under candidate_profile's policy), writable by the owner.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['candidate_education', 'candidate_experience', 'candidate_skill', 'candidate_language', 'resume', 'job_alert'] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY %I ON %I FOR SELECT USING (EXISTS (SELECT 1 FROM candidate_profile p WHERE p.id = candidate_profile_id))',
                   t || '_read', t);
    EXECUTE format('CREATE POLICY %I ON %I FOR ALL USING (candidate_profile_id = (SELECT app_viewer_candidate_profile_id()))
                    WITH CHECK (candidate_profile_id = (SELECT app_viewer_candidate_profile_id()))', t || '_owner_write', t);
  END LOOP;
END $$;
-- job alerts are private, unlike profile sections
DROP POLICY job_alert_read ON job_alert;

-- Blocks: only the candidate (and staff) see them; the blocked party never learns of the block.
ALTER TABLE candidate_block ENABLE ROW LEVEL SECURITY;
CREATE POLICY candidate_block_owner ON candidate_block
    USING (candidate_profile_id = (SELECT app_viewer_candidate_profile_id()) OR (SELECT app_is_staff()))
    WITH CHECK (candidate_profile_id = (SELECT app_viewer_candidate_profile_id()));

ALTER TABLE organisation ENABLE ROW LEVEL SECURITY;
CREATE POLICY organisation_read ON organisation FOR SELECT USING (deleted_at IS NULL OR (SELECT app_is_staff()));
CREATE POLICY organisation_admin_update ON organisation FOR UPDATE
    USING (id = (SELECT app_viewer_organisation_id()) AND (SELECT app_has_permission('member_manage')));

ALTER TABLE organisation_location ENABLE ROW LEVEL SECURITY;
CREATE POLICY organisation_location_read ON organisation_location FOR SELECT USING (true);
CREATE POLICY organisation_location_write ON organisation_location FOR ALL
    USING (organisation_id = (SELECT app_viewer_organisation_id()) AND (SELECT app_has_permission('member_manage')))
    WITH CHECK (organisation_id = (SELECT app_viewer_organisation_id()) AND (SELECT app_has_permission('member_manage')));

-- Organisation-private rows: members of the organisation, and staff. Writes need the matching permission.
DO $$
DECLARE t text; perm text;
BEGIN
  FOR t, perm IN VALUES ('organisation_tax_identifier', 'member_manage'), ('organisation_member', 'member_manage'),
                        ('subscription', 'billing_manage'), ('wallet', 'billing_manage'), ('payment_order', 'billing_manage'),
                        ('profile_download', 'candidate_download') LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY %I ON %I FOR SELECT USING (organisation_id = (SELECT app_viewer_organisation_id()) OR (SELECT app_is_staff()))',
                   t || '_member_read', t);
    EXECUTE format('CREATE POLICY %I ON %I FOR INSERT WITH CHECK (organisation_id = (SELECT app_viewer_organisation_id()) AND (SELECT app_has_permission(%L)))',
                   t || '_member_insert', t, perm);
    EXECUTE format('CREATE POLICY %I ON %I FOR UPDATE USING (organisation_id = (SELECT app_viewer_organisation_id()) AND (SELECT app_has_permission(%L)))',
                   t || '_member_update', t, perm);
  END LOOP;
END $$;
-- payment service sees orders to attach gateway references
CREATE POLICY payment_order_payments ON payment_order TO v2_payments USING (true);

-- Child rows of the wallet and payments follow their parent's visibility.
ALTER TABLE wallet_ledger_entry ENABLE ROW LEVEL SECURITY;
CREATE POLICY wallet_ledger_entry_read ON wallet_ledger_entry FOR SELECT USING (EXISTS (SELECT 1 FROM wallet w WHERE w.id = wallet_id));
ALTER TABLE payment_event ENABLE ROW LEVEL SECURITY;
CREATE POLICY payment_event_read ON payment_event FOR SELECT USING (EXISTS (SELECT 1 FROM payment_order o WHERE o.id = payment_order_id));
ALTER TABLE invoice ENABLE ROW LEVEL SECURITY;
CREATE POLICY invoice_read ON invoice FOR SELECT USING (EXISTS (SELECT 1 FROM payment_order o WHERE o.id = payment_order_id));

-- Jobs: published open jobs are public; drafts, paused and closed jobs only for the owning company (docket section 3).
ALTER TABLE job_requirement ENABLE ROW LEVEL SECURITY;
CREATE POLICY job_requirement_read ON job_requirement FOR SELECT
    USING ((job_status_id = 2 AND deleted_at IS NULL) OR organisation_id = (SELECT app_viewer_organisation_id()) OR (SELECT app_is_staff()));
CREATE POLICY job_requirement_insert ON job_requirement FOR INSERT
    WITH CHECK (organisation_id = (SELECT app_viewer_organisation_id()) AND (SELECT app_has_permission('job_post')));
CREATE POLICY job_requirement_update ON job_requirement FOR UPDATE
    USING (organisation_id = (SELECT app_viewer_organisation_id()) AND (SELECT app_has_permission('job_manage')));

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['job_requirement_location', 'job_requirement_skill', 'screening_question'] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY %I ON %I FOR SELECT USING (EXISTS (SELECT 1 FROM job_requirement j WHERE j.id = job_requirement_id))', t || '_read', t);
    EXECUTE format('CREATE POLICY %I ON %I FOR ALL USING (EXISTS (SELECT 1 FROM job_requirement j WHERE j.id = job_requirement_id
                      AND j.organisation_id = (SELECT app_viewer_organisation_id()) AND (SELECT app_has_permission(''job_manage''))))
                    WITH CHECK (EXISTS (SELECT 1 FROM job_requirement j WHERE j.id = job_requirement_id
                      AND j.organisation_id = (SELECT app_viewer_organisation_id()) AND (SELECT app_has_permission(''job_manage''))))',
                   t || '_write', t);
  END LOOP;
END $$;

-- Applications: the candidate; the hiring company unless the candidate has blocked it or the viewer; whoever sourced it; staff.
ALTER TABLE application ENABLE ROW LEVEL SECURITY;
CREATE POLICY application_read ON application FOR SELECT USING (
       candidate_profile_id = (SELECT app_viewer_candidate_profile_id())
    OR (organisation_id = (SELECT app_viewer_organisation_id()) AND NOT candidate_profile_id = ANY ((SELECT app_candidates_blocking_viewer())::bigint[]))
    OR sourced_by_app_user_id = (SELECT app_current_user_id())
    OR (SELECT app_is_staff()));
CREATE POLICY application_candidate_insert ON application FOR INSERT
    WITH CHECK (candidate_profile_id = (SELECT app_viewer_candidate_profile_id()) AND application_source_id = 1);
CREATE POLICY application_update ON application FOR UPDATE USING (
       candidate_profile_id = (SELECT app_viewer_candidate_profile_id())
    OR (organisation_id = (SELECT app_viewer_organisation_id()) AND (SELECT app_has_permission('application_manage'))
        AND NOT candidate_profile_id = ANY ((SELECT app_candidates_blocking_viewer())::bigint[])));

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['application_answer', 'application_status_history'] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY %I ON %I FOR SELECT USING (EXISTS (SELECT 1 FROM application a WHERE a.id = application_id))', t || '_read', t);
  END LOOP;
END $$;
CREATE POLICY application_answer_candidate_insert ON application_answer FOR INSERT WITH CHECK (EXISTS (
    SELECT 1 FROM application a WHERE a.id = application_id AND a.candidate_profile_id = (SELECT app_viewer_candidate_profile_id())));

-- Audit trail: staff, and an organisation's admins for their own organisation's events.
ALTER TABLE audit_event ENABLE ROW LEVEL SECURITY;
CREATE POLICY audit_event_read ON audit_event FOR SELECT USING (
    (SELECT app_is_staff()) OR (organisation_id = (SELECT app_viewer_organisation_id()) AND (SELECT app_has_permission('audit_read'))));

ALTER TABLE system_error ENABLE ROW LEVEL SECURITY;
CREATE POLICY system_error_insert ON system_error FOR INSERT WITH CHECK (true);
