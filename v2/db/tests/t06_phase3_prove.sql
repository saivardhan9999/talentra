-- t06 Phase 3 — Test Suite v1 (Data) and Test Suite v2 (Business Rules, State Transitions, Boundaries, and NFRs).
-- Covers Step 15 (Data Test Suite v1) and Step 20 (Test Suite v2), including all 14 Phase 2 findings closed in V013
-- (FND-01..FND-14), boundary values at exact limits, state machine transitions (TC-08-001..048), and NFR checks.
-- Runs inside a rolled-back transaction so the golden dataset stays clean.

BEGIN;
SET LOCAL app.hmac_key = 'prove-phase-sample-hmac-key';

SELECT id AS staff_user FROM app_user WHERE email = 'admin@talentra.test' \gset
SELECT id AS rec1_user FROM app_user WHERE email = 'rec1@org1.test' \gset
SELECT id AS admin1_user FROM app_user WHERE email = 'admin@org1.test' \gset
SELECT id AS org1 FROM organisation WHERE display_name = 'Apex Technologies' \gset
SELECT id AS org4_pending FROM organisation WHERE verification_status_id = 1 ORDER BY id LIMIT 1 \gset
SELECT id AS org5_rejected FROM organisation WHERE verification_status_id = 3 ORDER BY id LIMIT 1 \gset
SELECT id AS job_draft FROM job_requirement WHERE job_status_id = 1 AND organisation_id = :org1 ORDER BY id LIMIT 1 \gset
SELECT id AS job_open FROM job_requirement WHERE job_status_id = 2 AND organisation_id = :org1 AND positions_filled < positions_total ORDER BY id LIMIT 1 \gset
SELECT id AS job_paused FROM job_requirement WHERE job_status_id = 3 ORDER BY id LIMIT 1 \gset
SELECT id AS job_closed FROM job_requirement WHERE job_status_id = 4 AND deleted_at IS NULL ORDER BY id LIMIT 1 \gset
SELECT id AS job_filled FROM job_requirement WHERE job_status_id = 5 ORDER BY id LIMIT 1 \gset
SELECT p.id AS cand1_profile, p.app_user_id AS cand1_user FROM candidate_profile p JOIN app_user u ON u.id = p.app_user_id WHERE u.email = 'cand1@mail.test' \gset
SELECT p.id AS cand27_profile, p.app_user_id AS cand27_user FROM candidate_profile p JOIN app_user u ON u.id = p.app_user_id WHERE u.email = 'cand27@mail.test' \gset
SELECT p.id AS cand30_erased, p.app_user_id AS cand30_user FROM candidate_profile p WHERE p.deleted_at IS NOT NULL ORDER BY p.id LIMIT 1 \gset

------------------------------------------------------------------------------------------------------------------------
-- PART 1: Step 15 — Data Test Suite v1 (Keys, Orphans, Formats, Ranges, Boundaries, Positive & Negative)
------------------------------------------------------------------------------------------------------------------------

-- TC-15-001..006: Domain boundary tests (exact limits accepted, 1 beyond limit rejected)
SELECT pg_temp.expect_error($$SELECT ''::person_name$$, 'person_name', 'TC-15-001 empty person_name rejected (min 1)');
SELECT pg_temp.expect_error($$SELECT ' leading space'::person_name$$, 'person_name', 'TC-15-002 untrimmed person_name rejected');
SELECT pg_temp.check(char_length((repeat('A', 150)::person_name)) = 150, 'TC-15-003 person_name of exact length 150 accepted');
SELECT pg_temp.expect_error($$SELECT repeat('A', 151)::person_name$$, 'person_name', 'TC-15-004 person_name of length 151 rejected');

SELECT pg_temp.check((0.00::money_amount) = 0.00 AND (100.00::percentage) = 100.00 AND (-90.000000::latitude) = -90 AND (180.000000::longitude) = 180,
                     'TC-15-005 exact boundary values on money_amount (0), percentage (100), latitude (-90), longitude (180) accepted');
SELECT pg_temp.expect_error($$SELECT (-0.01)::money_amount$$, 'money_amount', 'TC-15-006 negative money_amount (-0.01) rejected');
SELECT pg_temp.expect_error($$SELECT 100.01::percentage$$, 'percentage', 'TC-15-007 percentage > 100.00 rejected');
SELECT pg_temp.expect_error($$SELECT 90.000001::latitude$$, 'latitude', 'TC-15-008 latitude > 90 rejected');
SELECT pg_temp.expect_error($$SELECT (-180.000001)::longitude$$, 'longitude', 'TC-15-009 longitude < -180 rejected');
SELECT pg_temp.expect_error($$SELECT '\x1234'::sha256_digest$$, 'sha256_digest', 'TC-15-010 sha256_digest != 32 bytes rejected');

-- TC-15-011..016: Table-level range and cross-field boundary checks
SELECT pg_temp.expect_error(format($$UPDATE candidate_profile SET total_experience_months = 721 WHERE id = %s$$, :cand1_profile),
                            'total_experience_months', 'TC-15-011 experience > 720 months rejected');
SELECT pg_temp.expect_error(format($$UPDATE candidate_profile SET notice_period_days = 366 WHERE id = %s$$, :cand1_profile),
                            'notice_period_days', 'TC-15-012 notice_period_days > 365 rejected');
SELECT pg_temp.expect_error(format($$UPDATE job_requirement SET positions_total = 0 WHERE id = %s$$, :job_open),
                            'positions', 'TC-15-013 positions_total = 0 rejected (min 1)');
SELECT pg_temp.expect_error(format($$UPDATE job_requirement SET positions_total = 10001 WHERE id = %s$$, :job_open),
                            'positions', 'TC-15-014 positions_total = 10001 rejected (max 10000)');

------------------------------------------------------------------------------------------------------------------------
-- PART 2: Step 17 & Step 20 — Verification of all 14 Phase 2 Findings (FND-01..FND-14) and State Transitions
------------------------------------------------------------------------------------------------------------------------

-- FND-01 & FND-02: Job status transitions and write-once published_at (TC-08-001..009)
SELECT pg_temp.expect_error(format($$UPDATE job_requirement SET job_status_id = 1, published_at = NULL WHERE id = %s$$, :job_open),
                            'published_at is write-once|cannot move from status',
                            'TC-20-001 (FND-01) published job cannot return to draft even if published_at is cleared');
SELECT pg_temp.expect_error(format($$UPDATE job_requirement SET published_at = now() WHERE id = %s$$, :job_open),
                            'published_at is write-once',
                            'TC-20-002 (FND-01) published_at cannot be overwritten once set');
SELECT pg_temp.expect_error(format($$UPDATE job_requirement SET job_status_id = 2 WHERE id = %s$$, :job_closed),
                            'cannot move from status',
                            'TC-20-003 (FND-02) closed job cannot be reopened');
SELECT pg_temp.expect_error(format($$UPDATE job_requirement SET job_status_id = 2 WHERE id = %s$$, :job_filled),
                            'cannot move from status',
                            'TC-20-004 (FND-02) filled job cannot be reopened');
SELECT pg_temp.expect_error(format($$UPDATE job_requirement SET job_status_id = 5 WHERE id = %s$$, :job_open),
                            'cannot be marked filled before all positions are joined',
                            'TC-20-005 (FND-02) open job cannot be manually marked filled while positions remain');
UPDATE job_requirement SET job_status_id = 2 WHERE id = :job_paused;
UPDATE job_requirement SET job_status_id = 3 WHERE id = :job_paused;
SELECT pg_temp.check((SELECT job_status_id = 3 FROM job_requirement WHERE id = :job_paused),
                     'TC-20-006 (FND-02) paused <-> open transitions succeed');

-- FND-03: Staff organisation verification entry point (TC-08-035..039)
SET LOCAL ROLE v2_app;
SELECT pg_temp.act_as(:rec1_user);
SELECT pg_temp.expect_error(format($$SELECT organisation_set_verification(%s, 'verified')$$, :org4_pending),
                            'only staff', 'TC-20-007 (FND-03) non-staff cannot verify an organisation');
SELECT pg_temp.act_as(:staff_user);
SELECT organisation_set_verification(:org4_pending, 'verified', 'GSTIN confirmed with registry');
SELECT pg_temp.check((SELECT verification_status_id = 2 AND verified_at IS NOT NULL FROM organisation WHERE id = :org4_pending)
                     AND EXISTS (SELECT 1 FROM audit_event WHERE action = 'organisation.verification_verified' AND entity_id = :org4_pending),
                     'TC-20-008 (FND-03) staff verifies pending organisation, sets verified_at and writes audit trail');
SELECT pg_temp.expect_error(format($$SELECT organisation_set_verification(%s, 'pending')$$, :org4_pending),
                            'cannot move verification status', 'TC-20-009 (FND-03) verified organisation cannot revert to pending');
SELECT organisation_set_verification(:org5_rejected, 'pending', 'Re-submitted documents');
SELECT pg_temp.check((SELECT verification_status_id = 1 FROM organisation WHERE id = :org5_rejected),
                     'TC-20-010 (FND-03) rejected organisation can return to pending for re-verification');
RESET ROLE;

-- FND-04: Device revocation entry point and write-once revoked_at (TC-08-043..045)
SELECT id AS dev_to_revoke FROM user_device WHERE app_user_id = :rec1_user AND revoked_at IS NULL LIMIT 1 \gset
SET LOCAL ROLE v2_app;
SELECT pg_temp.act_as(:cand1_user);
SELECT pg_temp.expect_error(format($$SELECT auth_revoke_device(%s)$$, :dev_to_revoke),
                            'not found', 'TC-20-011 (FND-04) user cannot revoke another user''s device');
SELECT pg_temp.act_as(:rec1_user);
SELECT auth_revoke_device(:dev_to_revoke);
RESET ROLE;
SELECT pg_temp.check((SELECT revoked_at IS NOT NULL FROM user_device WHERE id = :dev_to_revoke)
                     AND NOT EXISTS (SELECT 1 FROM user_session WHERE user_device_id = :dev_to_revoke AND ended_at IS NULL)
                     AND EXISTS (SELECT 1 FROM audit_event WHERE action = 'user_device.revoked' AND entity_id = :dev_to_revoke),
                     'TC-20-012 (FND-04) auth_revoke_device sets revoked_at, closes active sessions, and audits');
SELECT pg_temp.expect_error(format($$UPDATE user_device SET revoked_at = NULL WHERE id = %s$$, :dev_to_revoke),
                            'revoked_at is write-once', 'TC-20-013 (FND-04) revoked_at cannot be cleared once set');

-- FND-05: Account status transitions & entry point (TC-08-040..042)
SELECT pg_temp.expect_error(format($$UPDATE app_user SET account_status_id = 1, email = 'restored@mail.test' WHERE id = %s$$, :cand30_user),
                            'erased account status is final', 'TC-20-014 (FND-05) erased account status is final and cannot be reactivated');
SET LOCAL ROLE v2_app;
SELECT pg_temp.act_as(:cand1_user);
SELECT pg_temp.expect_error(format($$SELECT user_set_account_status(%s, 'suspended')$$, :cand1_user),
                            'only staff may suspend', 'TC-20-015 (FND-05) non-staff cannot suspend an account');
SELECT user_set_account_status(:cand1_user, 'deactivated');
SELECT pg_temp.check((SELECT account_status_id = 3 FROM app_user WHERE id = :cand1_user),
                     'TC-20-016 (FND-05) user can deactivate their own account');
SELECT user_set_account_status(:cand1_user, 'active');
RESET ROLE;

-- FND-06 & FND-07: Write-once closing timestamps on subscription, organisation_member, candidate_block (TC-08-034, 046..048)
SELECT id AS sub_to_cancel FROM subscription WHERE cancelled_at IS NULL LIMIT 1 \gset
UPDATE subscription SET cancelled_at = now(), auto_renew = false WHERE id = :sub_to_cancel;
SELECT pg_temp.expect_error(format($$UPDATE subscription SET cancelled_at = NULL WHERE id = %s$$, :sub_to_cancel),
                            'cancelled_at is write-once', 'TC-20-017 (FND-06) subscription.cancelled_at cannot be cleared');
SELECT id AS closed_member FROM organisation_member WHERE valid_to IS NOT NULL LIMIT 1 \gset
SELECT pg_temp.expect_error(format($$UPDATE organisation_member SET valid_to = NULL WHERE id = %s$$, :closed_member),
                            'valid_to is write-once', 'TC-20-018 (FND-07) organisation_member.valid_to cannot be cleared');
SELECT id AS lifted_block FROM candidate_block WHERE unblocked_at IS NOT NULL LIMIT 1 \gset
SELECT pg_temp.expect_error(format($$UPDATE candidate_block SET unblocked_at = NULL WHERE id = %s$$, :lifted_block),
                            'unblocked_at is write-once', 'TC-20-019 (FND-07) candidate_block.unblocked_at cannot be cleared');

-- FND-08: Notification delivery state machine guard (TC-08-029..033)
SELECT id AS notif_delivered FROM notification WHERE notification_status_id = 3 LIMIT 1 \gset
SELECT pg_temp.expect_error(format($$SELECT notification_record_result(%s, 'sent')$$, :notif_delivered),
                            'cannot move from status', 'TC-20-020 (FND-08) delivered notification cannot move back to sent');
SELECT pg_temp.expect_error(format($$SELECT notification_record_result(%s, 'queued')$$, :notif_delivered),
                            'invalid delivery result status', 'TC-20-021 (FND-08) notification_record_result rejects invalid target status queued');

-- FND-09: Consent enforcement on marketing email, WhatsApp alerts, and recruiter visibility
INSERT INTO notification (app_user_id, notification_category_id, notification_channel_id, template_key, payload)
VALUES (:cand27_user, 2, 3, 'application.whatsapp_ping', '{}'::jsonb) RETURNING id AS n_wa_no_consent \gset
SELECT pg_temp.check((SELECT notification_status_id = 5 FROM notification WHERE id = :n_wa_no_consent),
                     'TC-20-022 (FND-09) WhatsApp notification without whatsapp_alerts consent (purpose 5) is automatically suppressed');
SET LOCAL ROLE v2_app;
SELECT pg_temp.act_as(:rec1_user);
SELECT pg_temp.check((SELECT count(*) = 0 FROM candidate_profile WHERE id = :cand27_profile),
                     'TC-20-023 (FND-09) candidate who withdrew profile_visible_to_recruiters consent (purpose 3) is hidden from recruiters');
RESET ROLE;

-- FND-10 & FND-11: Erasure blanks application_answer.answer_text and user_device.device_label
SELECT pg_temp.check(NOT EXISTS (SELECT 1 FROM application_answer aa JOIN application a ON a.id = aa.application_id
                                 WHERE a.candidate_profile_id = :cand30_erased AND aa.answer_text <> '[erased]')
                     AND NOT EXISTS (SELECT 1 FROM user_device WHERE app_user_id = :cand30_user AND (device_label IS NOT NULL OR revoked_at IS NULL)),
                     'TC-20-024 (FND-10, FND-11) candidate_erase blanks answer_text to [erased] and clears device_label + revokes devices');

-- FND-12: All 78 Personal and Sensitive columns carry explicit Personal. or Sensitive. comments in pg_description
SELECT pg_temp.check((SELECT count(*) >= 78 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                      JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
                      WHERE n.nspname = 'public' AND c.relkind = 'r' AND NOT c.relispartition
                        AND col_description(c.oid, a.attnum) ~ '^(Personal|Sensitive)\.'),
                     'TC-20-025 (FND-12) all 78 personal and sensitive columns are explicitly tagged in column comments');

-- FND-13: Inserting an organisation directly automatically creates its wallet via trigger
INSERT INTO organisation (legal_name, display_name, industry_id, country_id)
VALUES ('Trigger Test Corp Private Limited', 'Trigger Test Corp', 1, 1) RETURNING id AS new_org \gset
SELECT pg_temp.check(EXISTS (SELECT 1 FROM wallet WHERE organisation_id = :new_org AND balance_credits = 0),
                     'TC-20-026 (FND-13) inserting an organisation automatically creates its wallet');

-- FND-14: Database-enforced login failure counting and lockout
SELECT auth_record_login_failure(:cand1_user, 3, interval '15 minutes') AS lock1 \gset
SELECT auth_record_login_failure(:cand1_user, 3, interval '15 minutes') AS lock2 \gset
SELECT auth_record_login_failure(:cand1_user, 3, interval '15 minutes') AS lock3 \gset
SELECT pg_temp.check(NOT :'lock1'::boolean AND NOT :'lock2'::boolean AND :'lock3'::boolean
                     AND (SELECT failed_attempt_count = 3 AND locked_until > now() FROM user_credential WHERE app_user_id = :cand1_user),
                     'TC-20-027 (FND-14) auth_record_login_failure locks account on reaching threshold');
SELECT (auth_open_session(:cand1_user, sha256('dev-lock-test'::bytea), 'Lock test device', sha256('tok-lock-test'::bytea)) IS NULL) AS sess_null \gset
SELECT pg_temp.check(:'sess_null'::boolean
                     AND EXISTS (SELECT 1 FROM audit_event WHERE actor_app_user_id = :cand1_user AND action = 'user_session.refused.account_locked'),
                     'TC-20-028 (FND-14) locked account is refused by auth_open_session and audited');

ROLLBACK;
