-- V010 Business rules that need more than one table: viewer context, candidate visibility, device limit at login,
-- seat limit, paid profile download and contact reveal.
-- Requirements: FR-IAM-05..07, FR-ORG-05, FR-BIL-05..06, FR-PRO-08, docket rule groups 2 and 9.

-- Viewer context, computed once per query when wrapped as (SELECT fn()) in policies (NFR-PERF-03).
-- SECURITY DEFINER: they read membership and role tables that the runtime role cannot see directly.
CREATE FUNCTION app_viewer_organisation_id() RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT organisation_id FROM organisation_member WHERE app_user_id = app_current_user_id() AND valid_to IS NULL
$$;

CREATE FUNCTION app_viewer_candidate_profile_id() RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT id FROM candidate_profile WHERE app_user_id = app_current_user_id()
$$;

CREATE FUNCTION app_has_permission(p_code text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT EXISTS (SELECT 1 FROM user_access_role ur
                   JOIN access_role_permission rp ON rp.access_role_id = ur.access_role_id
                   JOIN access_permission p ON p.id = rp.access_permission_id
                   JOIN app_user u ON u.id = ur.app_user_id AND u.account_status_id = 1
                   WHERE ur.app_user_id = app_current_user_id() AND p.code = p_code)
$$;

CREATE FUNCTION app_is_staff() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT EXISTS (SELECT 1 FROM user_access_role WHERE app_user_id = app_current_user_id() AND access_role_id IN (1, 2))
$$;

-- Candidates who blocked the viewer or the viewer's company (active blocks only).
CREATE FUNCTION app_candidates_blocking_viewer() RETURNS bigint[] LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT coalesce(array_agg(candidate_profile_id), '{}') FROM candidate_block
    WHERE unblocked_at IS NULL
      AND (blocked_app_user_id = app_current_user_id() OR blocked_organisation_id = app_viewer_organisation_id())
$$;

-- The visibility rule for a candidate profile, for point checks in the functions below: owner and staff always; a viewer
-- allowed to search candidates sees live, non-hidden profiles of candidates who have not blocked them or their company.
-- The RLS policy on candidate_profile (V011) states the same rule inline for speed; t03 checks they agree.
CREATE FUNCTION app_candidate_visible(p_profile_id bigint, p_owner_id bigint, p_visibility_id smallint, p_deleted_at timestamptz)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT p_owner_id = (SELECT app_current_user_id())
        OR (SELECT app_is_staff())
        OR ((SELECT app_has_permission('candidate_search')) AND p_deleted_at IS NULL AND p_visibility_id <> 3
            AND NOT p_profile_id = ANY ((SELECT app_candidates_blocking_viewer())::bigint[]))
$$;

CREATE FUNCTION app_can_view_candidate(p_candidate_profile_id bigint) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT coalesce((SELECT app_candidate_visible(id, app_user_id, profile_visibility_id, deleted_at)
                     FROM candidate_profile WHERE id = p_candidate_profile_id), false)
$$;

-- Device limit: org staff get the limit of their organisation's active subscription (1 without one); candidates get 3.
-- ponytail: candidate limit is a constant; make it a setting if product wants it configurable.
CREATE FUNCTION app_device_limit(p_app_user_id bigint) RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT CASE WHEN m.organisation_id IS NULL THEN 3 ELSE coalesce(s.max_devices_per_user, 1) END
    FROM (SELECT p_app_user_id AS app_user_id) u
    LEFT JOIN organisation_member m ON m.app_user_id = u.app_user_id AND m.valid_to IS NULL
    LEFT JOIN subscription s ON s.organisation_id = m.organisation_id AND current_date >= s.starts_on AND current_date < s.ends_on
$$;

-- Login (FR-IAM-05, rule group 9). Called by the auth service after the password check. Locks the user row so two
-- concurrent logins of the same user are decided one after the other; expired sessions are closed first and do not count.
-- Returns the new session id, or NULL when refused; a refusal is written to the audit trail (and committed, since
-- nothing is raised).
CREATE FUNCTION auth_open_session(p_app_user_id bigint, p_device_fingerprint_hash bytea, p_device_label text,
                                  p_token_hash bytea, p_ttl interval DEFAULT interval '30 days')
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE d user_device; lim int; active_devices int; s bigint;
BEGIN
  PERFORM 1 FROM app_user WHERE id = p_app_user_id AND account_status_id = 1 AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'user % cannot log in', p_app_user_id USING ERRCODE = 'insufficient_privilege'; END IF;

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

-- Logout or revocation of one session. Users end their own sessions; staff may end anyone's. Revocations are audited.
CREATE FUNCTION auth_end_session(p_session_id bigint, p_reason_code text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE s user_session; r smallint := (SELECT id FROM session_end_reason WHERE code = p_reason_code);
BEGIN
  SELECT * INTO s FROM user_session WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND OR NOT (s.app_user_id = app_current_user_id() OR app_is_staff()) THEN
    RAISE EXCEPTION 'session % not found', p_session_id USING ERRCODE = 'no_data_found';
  END IF;
  IF r IS NULL OR (p_reason_code = 'revoked_by_admin' AND NOT app_is_staff()) THEN
    RAISE EXCEPTION 'invalid end reason %', p_reason_code USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF s.ended_at IS NULL THEN
    UPDATE user_session SET ended_at = now(), session_end_reason_id = r WHERE id = s.id;
    IF p_reason_code LIKE 'revoked%' THEN
      PERFORM audit_log('user_session.' || p_reason_code, 'user_session', s.id);
    END IF;
  END IF;
END $$;

-- Seat limit (FR-ORG-05, rule group 2): an organisation has at most max_seats current members under its active
-- subscription (1 without one, the account admin). The organisation row lock serialises concurrent additions.
CREATE FUNCTION organisation_member_seat_limit() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE seats int; used int;
BEGIN
  IF NEW.valid_to IS NOT NULL OR (TG_OP = 'UPDATE' AND OLD.valid_to IS NULL) THEN RETURN NEW; END IF;
  PERFORM 1 FROM organisation WHERE id = NEW.organisation_id FOR UPDATE;
  SELECT coalesce(max(max_seats), 1) INTO seats FROM subscription
  WHERE organisation_id = NEW.organisation_id AND NEW.valid_from::date >= starts_on AND NEW.valid_from::date < ends_on;
  SELECT count(*) INTO used FROM organisation_member
  WHERE organisation_id = NEW.organisation_id AND valid_to IS NULL AND id IS DISTINCT FROM NEW.id;
  IF used >= seats THEN
    RAISE EXCEPTION 'organisation % has used all % seats of its licence', NEW.organisation_id, seats USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_organisation_member_seat_limit BEFORE INSERT OR UPDATE OF valid_to ON organisation_member
    FOR EACH ROW EXECUTE FUNCTION organisation_member_seat_limit();

-- Paid profile download (FR-BIL-05). One credit per candidate per organisation per 30 days: a repeat within the window
-- returns the earlier download and charges nothing. Fails if the viewer may not see the candidate or has no credits.
-- ponytail: price and window are constants; move to the plan when they vary.
CREATE FUNCTION billing_download_profile(p_candidate_profile_id bigint) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE org bigint := app_viewer_organisation_id(); d bigint; e bigint;
BEGIN
  IF org IS NULL OR NOT app_has_permission('candidate_download') THEN
    RAISE EXCEPTION 'only organisation members with download permission can download profiles' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT app_can_view_candidate(p_candidate_profile_id) THEN
    RAISE EXCEPTION 'candidate profile % not found', p_candidate_profile_id USING ERRCODE = 'no_data_found';
  END IF;
  PERFORM 1 FROM wallet WHERE organisation_id = org FOR UPDATE;   -- serialise this organisation's downloads
  SELECT id INTO d FROM profile_download
  WHERE candidate_profile_id = p_candidate_profile_id AND organisation_id = org AND downloaded_at > now() - interval '30 days'
  ORDER BY downloaded_at DESC LIMIT 1;
  IF FOUND THEN RETURN d; END IF;
  e := wallet_post((SELECT id FROM wallet WHERE organisation_id = org), 'profile_download_debit', -1,
                   'download:' || org || ':' || p_candidate_profile_id || ':' || to_char(now(), 'YYYYMMDDHH24MISSUS'));
  INSERT INTO profile_download (organisation_id, app_user_id, candidate_profile_id, wallet_ledger_entry_id)
  VALUES (org, app_current_user_id(), p_candidate_profile_id, e) RETURNING id INTO d;
  PERFORM audit_log('profile_download.insert', 'profile_download', d, org, jsonb_build_object('candidate_profile_id', p_candidate_profile_id));
  RETURN d;
END $$;

-- Contact details (Personal) for a candidate: the candidate, staff, or an organisation that downloaded the profile in
-- the last 30 days and is still allowed to see it. Every read is audited (NFR-PRIV-03).
CREATE FUNCTION candidate_contact(p_candidate_profile_id bigint) RETURNS TABLE (email text, phone_e164 text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE org bigint := app_viewer_organisation_id();
BEGIN
  IF NOT app_can_view_candidate(p_candidate_profile_id)
     OR NOT (app_viewer_candidate_profile_id() IS NOT DISTINCT FROM p_candidate_profile_id OR app_is_staff()
             OR EXISTS (SELECT 1 FROM profile_download WHERE candidate_profile_id = p_candidate_profile_id
                        AND organisation_id = org AND downloaded_at > now() - interval '30 days')) THEN
    RAISE EXCEPTION 'contact details of candidate % are not available: download the profile first', p_candidate_profile_id
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  PERFORM audit_log('candidate_contact.read', 'candidate_profile', p_candidate_profile_id, org);
  RETURN QUERY SELECT u.email::text, u.phone_e164::text FROM candidate_profile p JOIN app_user u ON u.id = p.app_user_id
               WHERE p.id = p_candidate_profile_id;
END $$;
