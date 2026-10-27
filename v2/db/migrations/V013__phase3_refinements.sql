-- V013 Phase 3 (Prove · Step 17 Design-Based Refinement): closes findings FND-01..FND-14 from Phase 2.
-- Requirements: FR-JOB-02 (FND-01, FND-02), FR-ORG-06 (FND-03), FR-IAM-06 (FND-04), FR-IAM-01..08 (FND-05, FND-14),
-- FR-BIL-02..03 (FND-06, FND-13), FR-ORG-04 / FR-PRO-08 (FND-07), FR-NOT-01..02 (FND-08, FND-09),
-- NFR-PRIV-01..04 (FND-09, FND-10, FND-11, FND-12).

------------------------------------------------------------------------------------------------------------------------
-- 1. Job status transitions & guard trigger (closes FND-01, FND-02)
-- draft(1) -> open(2) | closed(4); open(2) -> paused(3) | closed(4) | filled(5); paused(3) -> open(2) | closed(4).
-- closed(4) and filled(5) are final; published_at is write-once; filled(5) requires positions_filled = positions_total.
CREATE TABLE job_status_transition (
    id              smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    from_status_id  smallint NOT NULL REFERENCES job_status (id) ON DELETE CASCADE,
    to_status_id    smallint NOT NULL REFERENCES job_status (id) ON DELETE CASCADE,
    CONSTRAINT uq_job_status_transition_from_to UNIQUE (from_status_id, to_status_id),
    CONSTRAINT ck_job_status_transition_moves CHECK (from_status_id <> to_status_id)
);
INSERT INTO job_status_transition (from_status_id, to_status_id)
SELECT f.id, t.id FROM job_status f JOIN job_status t ON (f.code, t.code) IN (
  ('draft', 'open'), ('draft', 'closed'),
  ('open', 'paused'), ('open', 'closed'), ('open', 'filled'),
  ('paused', 'open'), ('paused', 'closed'));
GRANT SELECT ON job_status_transition TO v2_app, v2_reporting, v2_payments, v2_worker;

CREATE FUNCTION job_requirement_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.job_status_id IN (3, 4, 5) THEN
      RAISE EXCEPTION 'a new job requirement must start as draft or open' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.job_status_id = 2 AND NEW.published_at IS NULL THEN
      NEW.published_at := now();
    END IF;
  ELSE
    IF OLD.published_at IS NOT NULL AND NEW.published_at IS DISTINCT FROM OLD.published_at THEN
      RAISE EXCEPTION 'job requirement %: published_at is write-once and cannot be changed or cleared', OLD.id
        USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.job_status_id IS DISTINCT FROM OLD.job_status_id THEN
      IF NOT EXISTS (SELECT 1 FROM job_status_transition
                     WHERE from_status_id = OLD.job_status_id AND to_status_id = NEW.job_status_id) THEN
        RAISE EXCEPTION 'job requirement % cannot move from status % to %', OLD.id, OLD.job_status_id, NEW.job_status_id
          USING ERRCODE = 'check_violation';
      END IF;
      IF NEW.job_status_id = 2 AND NEW.published_at IS NULL THEN
        NEW.published_at := now();
      END IF;
      IF NEW.job_status_id = 5 AND NEW.positions_filled < NEW.positions_total THEN
        RAISE EXCEPTION 'job requirement % cannot be marked filled before all positions are joined (% of %)',
          OLD.id, NEW.positions_filled, NEW.positions_total USING ERRCODE = 'check_violation';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_job_requirement_guard BEFORE INSERT OR UPDATE ON job_requirement
    FOR EACH ROW EXECUTE FUNCTION job_requirement_guard();

------------------------------------------------------------------------------------------------------------------------
-- 2. Staff organisation verification entry point (closes FND-03)
-- Transitions: pending(1) -> verified(2) | rejected(3); rejected(3) -> pending(1). verified(2) is final.
CREATE FUNCTION organisation_set_verification(p_organisation_id bigint, p_status_code text, p_note text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  o organisation;
  s_new smallint := (SELECT id FROM verification_status WHERE code = p_status_code);
BEGIN
  IF NOT (app_is_staff() OR app_has_permission('organisation_verify')) THEN
    RAISE EXCEPTION 'only staff with organisation_verify permission may verify organisations'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF s_new IS NULL THEN
    RAISE EXCEPTION 'invalid verification status %', p_status_code USING ERRCODE = 'invalid_parameter_value';
  END IF;
  SELECT * INTO o FROM organisation WHERE id = p_organisation_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'organisation % not found', p_organisation_id USING ERRCODE = 'no_data_found';
  END IF;
  IF (o.verification_status_id, s_new) NOT IN ((1, 2), (1, 3), (3, 1)) THEN
    RAISE EXCEPTION 'organisation % cannot move verification status from % to %',
      o.id, o.verification_status_id, s_new USING ERRCODE = 'check_violation';
  END IF;
  UPDATE organisation
     SET verification_status_id = s_new,
         verified_at = CASE WHEN s_new = 2 THEN now() ELSE NULL END
   WHERE id = o.id;
  UPDATE organisation_tax_identifier
     SET verification_status_id = s_new,
         verified_at = CASE WHEN s_new = 2 THEN coalesce(verified_at, now()) ELSE NULL END
   WHERE organisation_id = o.id AND verification_status_id <> s_new;
  PERFORM audit_log('organisation.verification_' || p_status_code, 'organisation', o.id, o.id,
                    CASE WHEN p_note IS NULL THEN '{}' ELSE jsonb_build_object('note', p_note) END);
END $$;

------------------------------------------------------------------------------------------------------------------------
-- 3. Device revocation entry point & write-once guard (closes FND-04)
CREATE FUNCTION user_device_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.revoked_at IS NOT NULL AND NEW.revoked_at IS DISTINCT FROM OLD.revoked_at THEN
    RAISE EXCEPTION 'user_device %: revoked_at is write-once and cannot be cleared', OLD.id
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_user_device_guard BEFORE UPDATE ON user_device
    FOR EACH ROW EXECUTE FUNCTION user_device_guard();

CREATE FUNCTION auth_revoke_device(p_device_id bigint) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  d user_device;
  r smallint := CASE WHEN app_is_staff() AND (SELECT app_user_id FROM user_device WHERE id = p_device_id) IS DISTINCT FROM app_current_user_id()
                     THEN 4 ELSE 3 END;
BEGIN
  SELECT * INTO d FROM user_device WHERE id = p_device_id FOR UPDATE;
  IF NOT FOUND OR NOT (d.app_user_id = app_current_user_id() OR app_is_staff()) THEN
    RAISE EXCEPTION 'device % not found', p_device_id USING ERRCODE = 'no_data_found';
  END IF;
  IF d.revoked_at IS NULL THEN
    UPDATE user_device SET revoked_at = now() WHERE id = d.id;
    UPDATE user_session SET ended_at = now(), session_end_reason_id = r
     WHERE user_device_id = d.id AND ended_at IS NULL;
    PERFORM audit_log('user_device.revoked', 'user_device', d.id, NULL,
                      jsonb_build_object('reason_id', r));
  END IF;
END $$;

------------------------------------------------------------------------------------------------------------------------
-- 4. Account status transition guard & entry point (closes FND-05)
-- Allowed moves: active(1) <-> suspended(2) (staff), active(1) <-> deactivated(3) (owner/staff),
-- active/suspended/deactivated(1,2,3) -> erased(4) (erasure only). erased(4) is final.
CREATE FUNCTION app_user_status_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.account_status_id IS DISTINCT FROM NEW.account_status_id THEN
    IF OLD.account_status_id = 4 THEN
      RAISE EXCEPTION 'app_user %: erased account status is final', OLD.id USING ERRCODE = 'check_violation';
    END IF;
    IF (OLD.account_status_id, NEW.account_status_id) NOT IN (
         (1, 2), (2, 1), (1, 3), (3, 1), (1, 4), (2, 4), (3, 4)) THEN
      RAISE EXCEPTION 'app_user % cannot move from account status % to %',
        OLD.id, OLD.account_status_id, NEW.account_status_id USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_app_user_status_guard BEFORE UPDATE OF account_status_id ON app_user
    FOR EACH ROW EXECUTE FUNCTION app_user_status_guard();

CREATE FUNCTION user_set_account_status(p_app_user_id bigint, p_status_code text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  u app_user;
  s_new smallint := (SELECT id FROM account_status WHERE code = p_status_code);
BEGIN
  IF s_new IS NULL OR s_new = 4 THEN
    RAISE EXCEPTION 'invalid target account status % (use candidate_erase for erasure)', p_status_code
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  SELECT * INTO u FROM app_user WHERE id = p_app_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'user % not found', p_app_user_id USING ERRCODE = 'no_data_found';
  END IF;
  IF p_status_code = 'suspended' OR (u.account_status_id = 2 AND p_status_code = 'active') THEN
    IF NOT (app_is_staff() OR app_has_permission('user_manage')) THEN
      RAISE EXCEPTION 'only staff may suspend or unsuspend an account' USING ERRCODE = 'insufficient_privilege';
    END IF;
  ELSIF NOT (u.id = app_current_user_id() OR app_is_staff()) THEN
    RAISE EXCEPTION 'only the account owner or staff may change account status' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE app_user SET account_status_id = s_new WHERE id = u.id;
  IF s_new IN (2, 3) THEN
    UPDATE user_session SET ended_at = now(),
           session_end_reason_id = CASE WHEN app_is_staff() AND u.id IS DISTINCT FROM app_current_user_id() THEN 4 ELSE 3 END
     WHERE app_user_id = u.id AND ended_at IS NULL;
  END IF;
  PERFORM audit_log('app_user.status_' || p_status_code, 'app_user', u.id);
END $$;

------------------------------------------------------------------------------------------------------------------------
-- 5. Write-once closing timestamps on subscription, organisation_member, candidate_block (closes FND-06, FND-07)
CREATE OR REPLACE FUNCTION subscription_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF (NEW.organisation_id, NEW.plan_id, NEW.max_seats, NEW.max_devices_per_user, NEW.starts_on, NEW.payment_order_id)
     IS DISTINCT FROM (OLD.organisation_id, OLD.plan_id, OLD.max_seats, OLD.max_devices_per_user, OLD.starts_on, OLD.payment_order_id)
     OR NEW.ends_on > OLD.ends_on
     OR (OLD.cancelled_at IS NOT NULL AND NEW.cancelled_at IS DISTINCT FROM OLD.cancelled_at) THEN
    RAISE EXCEPTION 'subscription % : only cancellation and auto-renew may change, and cancelled_at is write-once', OLD.id
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

CREATE FUNCTION period_close_once_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_TABLE_NAME = 'organisation_member' AND OLD.valid_to IS NOT NULL AND NEW.valid_to IS DISTINCT FROM OLD.valid_to THEN
    RAISE EXCEPTION 'organisation_member %: valid_to is write-once; insert a new membership row to rejoin', OLD.id
      USING ERRCODE = 'check_violation';
  ELSIF TG_TABLE_NAME = 'candidate_block' AND OLD.unblocked_at IS NOT NULL AND NEW.unblocked_at IS DISTINCT FROM OLD.unblocked_at THEN
    RAISE EXCEPTION 'candidate_block %: unblocked_at is write-once; insert a new block row to block again', OLD.id
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_organisation_member_close_once BEFORE UPDATE ON organisation_member
    FOR EACH ROW EXECUTE FUNCTION period_close_once_guard();
CREATE TRIGGER trg_candidate_block_close_once BEFORE UPDATE ON candidate_block
    FOR EACH ROW EXECUTE FUNCTION period_close_once_guard();

------------------------------------------------------------------------------------------------------------------------
-- 6. Notification delivery state transitions (closes FND-08)
-- Allowed moves: queued(1) -> sent(2) | delivered(3) | failed(4); sent(2) -> delivered(3) | failed(4).
-- delivered(3), failed(4) and suppressed(5) are final.
CREATE OR REPLACE FUNCTION notification_record_result(p_notification_id bigint, p_status_code text,
                                                      p_provider_message_ref text DEFAULT NULL,
                                                      p_failure_reason text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  n notification;
  s_new smallint := (SELECT id FROM notification_status WHERE code = p_status_code);
BEGIN
  IF s_new IS NULL OR s_new NOT IN (2, 3, 4) THEN
    RAISE EXCEPTION 'invalid delivery result status %', p_status_code USING ERRCODE = 'invalid_parameter_value';
  END IF;
  SELECT * INTO n FROM notification WHERE id = p_notification_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'notification % not found', p_notification_id USING ERRCODE = 'no_data_found';
  END IF;
  IF (n.notification_status_id, s_new) NOT IN ((1, 2), (1, 3), (1, 4), (2, 3), (2, 4)) THEN
    RAISE EXCEPTION 'notification % cannot move from status % to %', n.id, n.notification_status_id, s_new
      USING ERRCODE = 'check_violation';
  END IF;
  IF p_status_code = 'failed' AND n.attempt_count < 5 THEN
    UPDATE notification SET next_attempt_at = now() + make_interval(mins => 2 ^ n.attempt_count) WHERE id = n.id;
  ELSE
    UPDATE notification SET notification_status_id = s_new,
           provider_message_ref = coalesce(p_provider_message_ref, provider_message_ref),
           sent_at = CASE WHEN p_status_code IN ('sent', 'delivered') THEN coalesce(sent_at, now()) ELSE sent_at END,
           delivered_at = CASE WHEN p_status_code = 'delivered' THEN now() ELSE delivered_at END,
           failure_reason = CASE WHEN p_status_code = 'failed' THEN coalesce(p_failure_reason, 'unknown') END
    WHERE id = n.id;
  END IF;
END $$;

------------------------------------------------------------------------------------------------------------------------
-- 7. Consent enforcement on notifications & candidate visibility (closes FND-09)
-- Purpose 3 = profile_visible_to_recruiters; Purpose 4 = marketing_email; Purpose 5 = whatsapp_alerts.
CREATE OR REPLACE FUNCTION notification_apply_preference() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.notification_category_id <> 3 THEN
    IF EXISTS (
         SELECT 1 FROM notification_preference p
         WHERE p.app_user_id = NEW.app_user_id AND p.notification_category_id = NEW.notification_category_id
           AND p.notification_channel_id = NEW.notification_channel_id AND NOT p.is_enabled)
       OR (NEW.notification_category_id = 5 AND NOT EXISTS (
         SELECT 1 FROM consent_current c
         WHERE c.app_user_id = NEW.app_user_id AND c.consent_purpose_id = 4 AND c.is_granted))
       OR (NEW.notification_channel_id = 3 AND NOT EXISTS (
         SELECT 1 FROM consent_current c
         WHERE c.app_user_id = NEW.app_user_id AND c.consent_purpose_id = 5 AND c.is_granted)) THEN
      NEW.notification_status_id := 5;
    END IF;
  END IF;
  RETURN NEW;
END $$;

-- Helper returning user IDs who have withdrawn profile_visible_to_recruiters (purpose 3) consent, evaluated once per query.
CREATE FUNCTION app_users_without_recruiter_consent() RETURNS bigint[] LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT coalesce(array_agg(app_user_id), '{}') FROM consent_current
    WHERE consent_purpose_id = 3 AND NOT is_granted
$$;

CREATE OR REPLACE FUNCTION app_candidate_visible(p_profile_id bigint, p_owner_id bigint, p_visibility_id smallint, p_deleted_at timestamptz)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT p_owner_id = (SELECT app_current_user_id())
        OR (SELECT app_is_staff())
        OR ((SELECT app_has_permission('candidate_search')) AND p_deleted_at IS NULL AND p_visibility_id <> 3
            AND NOT p_profile_id = ANY ((SELECT app_candidates_blocking_viewer())::bigint[])
            AND NOT p_owner_id = ANY ((SELECT app_users_without_recruiter_consent())::bigint[]))
$$;

DROP POLICY candidate_profile_read ON candidate_profile;
CREATE POLICY candidate_profile_read ON candidate_profile FOR SELECT USING (
       app_user_id = (SELECT app_current_user_id())
    OR (SELECT app_is_staff())
    OR ((SELECT app_has_permission('candidate_search')) AND deleted_at IS NULL AND profile_visibility_id <> 3
        AND NOT id = ANY ((SELECT app_candidates_blocking_viewer())::bigint[])
        AND NOT app_user_id = ANY ((SELECT app_users_without_recruiter_consent())::bigint[])));

------------------------------------------------------------------------------------------------------------------------
-- 8. Complete right-to-erasure scrubbing (closes FND-10, FND-11)
-- Blanks application_answer.answer_text to '[erased]' and user_device.device_label to NULL + revokes devices.
CREATE OR REPLACE FUNCTION candidate_erase(p_candidate_profile_id bigint) RETURNS void
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
  UPDATE application_answer SET answer_text = '[erased]'
   WHERE application_id IN (SELECT id FROM application WHERE candidate_profile_id = p.id);
  UPDATE application SET resume_id = NULL WHERE candidate_profile_id = p.id AND resume_id IS NOT NULL;
  DELETE FROM resume WHERE candidate_profile_id = p.id;
  UPDATE candidate_profile SET full_name = 'Erased candidate ' || p.id, headline = NULL, summary = NULL, current_city_id = NULL,
         expected_salary_amount = NULL, expected_salary_currency_id = NULL, salary_disclosure_id = 3, notice_period_days = NULL,
         is_open_to_work = false, profile_visibility_id = 3, deleted_at = now()
  WHERE id = p.id;
  UPDATE user_session SET ended_at = now(), session_end_reason_id = 4 WHERE app_user_id = p.app_user_id AND ended_at IS NULL;
  UPDATE user_device SET device_label = NULL, revoked_at = coalesce(revoked_at, now()) WHERE app_user_id = p.app_user_id;
  DELETE FROM user_credential WHERE app_user_id = p.app_user_id;
  UPDATE app_user SET email = NULL, phone_e164 = NULL, phone_country_id = NULL, account_status_id = 4, deleted_at = now()
  WHERE id = p.app_user_id;
  PERFORM audit_log('candidate_profile.erased', 'candidate_profile', p.id);
END $$;

------------------------------------------------------------------------------------------------------------------------
-- 9. Every organisation has a wallet automatically (closes FND-13)
CREATE FUNCTION organisation_ensure_wallet() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO wallet (organisation_id, created_at, created_by)
  VALUES (NEW.id, NEW.created_at, NEW.created_by)
  ON CONFLICT (organisation_id) DO NOTHING;
  RETURN NULL;
END $$;
CREATE TRIGGER trg_organisation_ensure_wallet AFTER INSERT ON organisation
    FOR EACH ROW EXECUTE FUNCTION organisation_ensure_wallet();

-- Make auth_register_employer idempotent with the trigger
CREATE OR REPLACE FUNCTION auth_register_employer(p_email text, p_password_hash text, p_legal_name text, p_display_name text,
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
  INSERT INTO organisation (legal_name, display_name, industry_id, country_id, created_by)
  VALUES (p_legal_name, p_display_name, p_industry_id, p_country_id, u) RETURNING id INTO o;
  INSERT INTO wallet (organisation_id, created_by) VALUES (o, u) ON CONFLICT (organisation_id) DO NOTHING;
  INSERT INTO organisation_member (organisation_id, app_user_id, access_role_id, created_by) VALUES (o, u, 3, u);
  INSERT INTO consent_record (app_user_id, consent_purpose_id, is_granted, policy_version, created_by)
  VALUES (u, 1, true, p_policy_version, u), (u, 2, true, p_policy_version, u);
  RETURN o;
END $$;

------------------------------------------------------------------------------------------------------------------------
-- 10. Database-enforced credential lockout after failed logins (closes FND-14)
-- 5 consecutive failed attempts lock the account for 15 minutes and write an audit event; auth_open_session checks the lock
-- and resets failed_attempt_count on success.
CREATE FUNCTION auth_record_login_failure(p_app_user_id bigint, p_max_attempts smallint DEFAULT 5,
                                          p_lockout_duration interval DEFAULT interval '15 minutes')
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE c user_credential;
BEGIN
  UPDATE user_credential
     SET failed_attempt_count = failed_attempt_count + 1,
         locked_until = CASE WHEN failed_attempt_count + 1 >= p_max_attempts THEN now() + p_lockout_duration ELSE locked_until END
   WHERE app_user_id = p_app_user_id
   RETURNING * INTO c;
  IF NOT FOUND THEN RETURN false; END IF;
  IF c.failed_attempt_count >= p_max_attempts THEN
    INSERT INTO audit_event (actor_app_user_id, action, entity_table, entity_id, details)
    VALUES (p_app_user_id, 'user_credential.locked', 'user_credential', c.id,
            jsonb_build_object('failed_attempt_count', c.failed_attempt_count, 'locked_until', c.locked_until));
    RETURN true;
  END IF;
  RETURN false;
END $$;

CREATE OR REPLACE FUNCTION auth_open_session(p_app_user_id bigint, p_device_fingerprint_hash bytea, p_device_label text,
                                             p_token_hash bytea, p_ttl interval DEFAULT interval '30 days')
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE d user_device; lim int; active_devices int; s bigint;
BEGIN
  PERFORM 1 FROM app_user WHERE id = p_app_user_id AND account_status_id = 1 AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'user % cannot log in', p_app_user_id USING ERRCODE = 'insufficient_privilege'; END IF;

  IF EXISTS (SELECT 1 FROM user_credential WHERE app_user_id = p_app_user_id AND locked_until > now()) THEN
    INSERT INTO audit_event (actor_app_user_id, action, entity_table, entity_id, details)
    VALUES (p_app_user_id, 'user_session.refused.account_locked', 'app_user', p_app_user_id, '{}');
    RETURN NULL;
  END IF;
  UPDATE user_credential SET failed_attempt_count = 0, locked_until = NULL
   WHERE app_user_id = p_app_user_id AND (failed_attempt_count > 0 OR locked_until IS NOT NULL);

  UPDATE user_session SET ended_at = expires_at, session_end_reason_id = 2
  WHERE app_user_id = p_app_user_id AND ended_at IS NULL AND expires_at <= now();

  INSERT INTO user_device (app_user_id, device_fingerprint_hash, device_label, created_by)
  VALUES (p_app_user_id, p_device_fingerprint_hash, p_device_label, p_app_user_id)
  ON CONFLICT (app_user_id, device_fingerprint_hash) DO UPDATE SET last_seen_at = now()
  RETURNING * INTO d;

  IF d.revoked_at IS NOT NULL THEN
    INSERT INTO audit_event (actor_app_user_id, action, entity_table, entity_id, details)
    VALUES (p_app_user_id, 'user_session.refused.device_revoked', 'user_device', d.id, '{}');
    RETURN NULL;
  END IF;

  lim := app_device_limit(p_app_user_id);
  SELECT count(DISTINCT user_device_id) INTO active_devices FROM user_session
  WHERE app_user_id = p_app_user_id AND ended_at IS NULL AND user_device_id <> d.id;
  IF active_devices >= lim THEN
    INSERT INTO audit_event (actor_app_user_id, action, entity_table, entity_id, details)
    VALUES (p_app_user_id, 'user_session.refused.device_limit', 'user_device', d.id,
            jsonb_build_object('device_limit', lim, 'active_devices', active_devices));
    RETURN NULL;
  END IF;

  INSERT INTO user_session (app_user_id, user_device_id, token_hash, expires_at, created_by)
  VALUES (p_app_user_id, d.id, p_token_hash, now() + p_ttl, p_app_user_id) RETURNING id INTO s;
  UPDATE app_user SET last_login_at = now() WHERE id = p_app_user_id;
  RETURN s;
END $$;

------------------------------------------------------------------------------------------------------------------------
-- 11. Privileges for new functions and triggers
REVOKE ALL ON FUNCTION job_requirement_guard(), organisation_set_verification(bigint, text, text),
    user_device_guard(), auth_revoke_device(bigint), app_user_status_guard(), user_set_account_status(bigint, text),
    period_close_once_guard(), app_users_without_recruiter_consent(), organisation_ensure_wallet(),
    auth_record_login_failure(bigint, smallint, interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION job_requirement_guard(), user_device_guard(), app_user_status_guard(),
    period_close_once_guard(), app_users_without_recruiter_consent(), organisation_ensure_wallet()
    TO v2_app, v2_payments, v2_worker, v2_reporting;

GRANT EXECUTE ON FUNCTION organisation_set_verification(bigint, text, text), auth_revoke_device(bigint),
    user_set_account_status(bigint, text), auth_record_login_failure(bigint, smallint, interval)
    TO v2_app;

------------------------------------------------------------------------------------------------------------------------
-- 12. Column classification comments for all 52 reclassified columns (closes FND-12)
COMMENT ON COLUMN app_user.phone_country_id IS 'Personal. Country of the phone number. NULL: exactly when phone_e164 is NULL.';
COMMENT ON COLUMN app_user.account_status_id IS 'Personal. Current lifecycle status of the user account.';
COMMENT ON COLUMN app_user.preferred_language_id IS 'Personal. Preferred UI language of the user.';
COMMENT ON COLUMN app_user.time_zone IS 'Personal. IANA zone of the user, used to display UTC timestamps.';
COMMENT ON COLUMN app_user.last_login_at IS 'Personal. NULL: the user has never logged in (invited or migrated account).';
COMMENT ON COLUMN consent_record.consent_purpose_id IS 'Personal. Purpose to which the user granted or withdrew consent.';
COMMENT ON COLUMN consent_record.is_granted IS 'Personal. Yes or no to the purpose; withdrawal is a new record with false.';
COMMENT ON COLUMN consent_record.policy_version IS 'Personal. Version of the terms or privacy policy shown to the user.';
COMMENT ON COLUMN consent_record.recorded_at IS 'Personal. When the consent choice was recorded.';
COMMENT ON COLUMN user_device.device_fingerprint_hash IS 'Sensitive. SHA-256 of the client device identifier; the raw identifier is not stored.';
COMMENT ON COLUMN user_device.device_label IS 'Personal. Name shown in "your devices", e.g. "Chrome on Windows". NULL: client did not send one or erased.';
COMMENT ON COLUMN user_device.first_seen_at IS 'Personal. First login timestamp from this device.';
COMMENT ON COLUMN user_device.last_seen_at IS 'Personal. Latest login timestamp from this device.';
COMMENT ON COLUMN user_device.revoked_at IS 'Personal. NULL: the device is trusted. Revoking ends its sessions (auditable, rule group 9).';
COMMENT ON COLUMN user_session.started_at IS 'Personal. When the session opened.';
COMMENT ON COLUMN user_session.last_activity_at IS 'Personal. Latest request timestamp in this session.';
COMMENT ON COLUMN user_session.expires_at IS 'Personal. When the session stops being valid without activity.';
COMMENT ON COLUMN user_session.ended_at IS 'Personal. NULL: session not ended (still active until expires_at).';
COMMENT ON COLUMN user_session.session_end_reason_id IS 'Personal. Why the session ended. NULL: exactly when ended_at is NULL.';
COMMENT ON COLUMN candidate_profile.profile_language_id IS 'Personal. Language the candidate wrote the profile in (rule group 7). NULL: unknown.';
COMMENT ON COLUMN candidate_profile.total_experience_months IS 'Personal. Total work experience in months stated by the candidate.';
COMMENT ON COLUMN candidate_profile.expected_salary_currency_id IS 'Personal. NULL: exactly when the expected salary amount is NULL.';
COMMENT ON COLUMN candidate_profile.salary_disclosure_id IS 'Personal. Whether expected salary is disclosed, not disclosed, or not provided.';
COMMENT ON COLUMN candidate_profile.is_open_to_work IS 'Personal. Whether the candidate wants to be found by recruiters.';
COMMENT ON COLUMN candidate_profile.profile_visibility_id IS 'Personal. Whether the profile is public, recruiters_only, or hidden.';
COMMENT ON COLUMN candidate_profile.last_active_at IS 'Personal. Latest candidate activity; drives inactivity erasure and search ranking.';
COMMENT ON COLUMN candidate_profile.search_vector IS 'Personal. Generated from name and headline for full-text search.';
COMMENT ON COLUMN candidate_education.qualification_id IS 'Personal. Qualification level studied for.';
COMMENT ON COLUMN candidate_education.institution_name IS 'Personal. School, college or university name.';
COMMENT ON COLUMN candidate_education.start_date IS 'Personal. When the course started.';
COMMENT ON COLUMN candidate_experience.organisation_id IS 'Personal. Matched employer on the platform. NULL: employer is not on Talentra (company_name is always kept).';
COMMENT ON COLUMN candidate_experience.company_name IS 'Personal. Employer name as written by the candidate.';
COMMENT ON COLUMN candidate_experience.job_title IS 'Personal. Role held by the candidate.';
COMMENT ON COLUMN candidate_experience.employment_type_id IS 'Personal. Employment type of the role held.';
COMMENT ON COLUMN candidate_experience.start_date IS 'Personal. First day in the job.';
COMMENT ON COLUMN candidate_skill.skill_id IS 'Personal. Skill from the shared taxonomy held by the candidate.';
COMMENT ON COLUMN candidate_skill.proficiency_level_id IS 'Personal. Self-stated proficiency level in the skill.';
COMMENT ON COLUMN candidate_language.language_id IS 'Personal. Language spoken by the candidate.';
COMMENT ON COLUMN candidate_language.proficiency_level_id IS 'Personal. Proficiency level in the spoken language.';
COMMENT ON COLUMN resume.version_number IS 'Personal. Version number of the resume per candidate.';
COMMENT ON COLUMN resume.file_sha256 IS 'Personal. SHA-256 checksum of the resume file.';
COMMENT ON COLUMN resume.content_language_id IS 'Personal. NULL: language not detected.';
COMMENT ON COLUMN resume.is_primary IS 'Personal. Whether this version is sent by default on applications.';
COMMENT ON COLUMN candidate_block.blocked_organisation_id IS 'Personal. Role-named key (deviation D-03). NULL: the block targets one person instead.';
COMMENT ON COLUMN candidate_block.blocked_app_user_id IS 'Personal. Role-named key (deviation D-03). NULL: the block targets a company instead.';
COMMENT ON COLUMN candidate_block.blocked_at IS 'Personal. When the block started.';
COMMENT ON COLUMN candidate_block.unblocked_at IS 'Personal. NULL: block is active.';
COMMENT ON COLUMN job_alert.city_id IS 'Personal. NULL: any city.';
COMMENT ON COLUMN job_alert.salary_currency_id IS 'Personal. NULL: exactly when there is no salary filter.';
COMMENT ON COLUMN job_alert.alert_frequency_id IS 'Personal. How often matching job digests are sent.';
COMMENT ON COLUMN job_alert.is_active IS 'Personal. Whether the saved job alert is active.';
COMMENT ON COLUMN job_alert.last_sent_at IS 'Personal. NULL: never sent yet.';
