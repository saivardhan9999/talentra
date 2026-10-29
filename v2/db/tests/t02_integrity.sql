-- t02 Integrity: every constraint and trigger rule refuses bad data and accepts good data. Runs as the owner (rules hold
-- for everyone, not only the API role) inside one transaction that is rolled back.
-- Covers FR-APP-03..06, FR-BIL-01..07, FR-ORG-03..05, NFR-INT-01..04.
BEGIN;
SET LOCAL app.hmac_key = 'test';

SELECT j.id AS job_open FROM job_requirement j
WHERE j.job_status_id = 2 AND j.closes_on IS NULL AND NOT j.is_open_to_consultants AND j.deleted_at IS NULL ORDER BY j.id LIMIT 1 \gset
SELECT id AS job_closed FROM job_requirement WHERE job_status_id = 4 ORDER BY id LIMIT 1 \gset
SELECT p.id AS cand, p.app_user_id AS cand_user FROM candidate_profile p
WHERE p.deleted_at IS NULL AND NOT EXISTS (SELECT 1 FROM application a WHERE a.candidate_profile_id = p.id AND a.job_requirement_id = :job_open)
ORDER BY p.id LIMIT 1 \gset
SELECT id AS other_resume FROM resume WHERE candidate_profile_id <> :cand ORDER BY id LIMIT 1 \gset
SELECT id AS other_question FROM screening_question WHERE job_requirement_id <> :job_open ORDER BY id LIMIT 1 \gset
SELECT id AS app_applied FROM application WHERE application_status_id = 1 ORDER BY id LIMIT 1 \gset
SELECT a.id AS app_offered, a.job_requirement_id AS app_offered_job FROM application a JOIN job_requirement j ON j.id = a.job_requirement_id
WHERE a.application_status_id = 4 AND j.positions_filled < j.positions_total ORDER BY a.id LIMIT 1 \gset
SELECT w.id AS wallet, w.organisation_id AS wallet_org, w.balance_credits AS balance FROM wallet w WHERE w.balance_credits > 0 ORDER BY w.id LIMIT 1 \gset
SELECT id AS ledger_entry FROM wallet_ledger_entry ORDER BY id LIMIT 1 \gset
SELECT id AS sub, organisation_id AS sub_org, starts_on AS sub_start, ends_on AS sub_end FROM subscription ORDER BY id LIMIT 1 \gset
SELECT app_user_id AS member_user, organisation_id AS member_org FROM organisation_member WHERE valid_to IS NULL AND access_role_id = 5 ORDER BY id LIMIT 1 \gset
SELECT o.id AS free_org FROM organisation o
JOIN subscription s ON s.organisation_id = o.id AND current_date >= s.starts_on AND current_date < s.ends_on
WHERE o.id <> :member_org AND (SELECT count(*) FROM organisation_member m WHERE m.organisation_id = o.id AND m.valid_to IS NULL) < s.max_seats
ORDER BY o.id LIMIT 1 \gset
SELECT o.id AS full_org FROM organisation o
WHERE (SELECT count(*) FROM organisation_member m WHERE m.organisation_id = o.id AND m.valid_to IS NULL)
      >= coalesce((SELECT max(max_seats) FROM subscription s WHERE s.organisation_id = o.id AND current_date >= s.starts_on AND current_date < s.ends_on), 1)
ORDER BY o.id LIMIT 1 \gset
SELECT id AS org_a FROM organisation WHERE parent_organisation_id IS NULL ORDER BY id LIMIT 1 \gset
SELECT id AS org_b FROM organisation WHERE parent_organisation_id IS NULL AND id <> :org_a ORDER BY id LIMIT 1 \gset
SELECT id AS consultant FROM app_user WHERE email LIKE 'consultant%' ORDER BY id LIMIT 1 \gset

-- domains (rule group 3)
SELECT pg_temp.expect_error($$INSERT INTO app_user (email) VALUES ('Mixed.Case@Mail.test')$$, 'email_address', 't02 email must be lowercase');
SELECT pg_temp.expect_error($$INSERT INTO app_user (email, phone_e164, phone_country_id) VALUES ('ok@mail.test', '98450 12345', 1)$$, 'phone_e164', 't02 phone must be E.164');
SELECT pg_temp.expect_error($$INSERT INTO app_user (email, phone_e164) VALUES ('ok2@mail.test', '+919845012345')$$, 'ck_app_user_phone_country', 't02 phone needs its country');

-- unknown vs not disclosed (rule group 5)
SELECT pg_temp.expect_error(format($$UPDATE job_requirement SET salary_min_amount = 900000, salary_max_amount = 500000, salary_currency_id = 1,
    salary_disclosure_id = 1 WHERE id = %s$$, :job_open), 'ck_job_requirement_salary', 't02 job minimum salary cannot exceed maximum');
SELECT pg_temp.expect_error(format($$UPDATE job_requirement SET salary_disclosure_id = 1, salary_min_amount = NULL, salary_max_amount = NULL,
    salary_currency_id = NULL WHERE id = %s$$, :job_open), 'ck_job_requirement_salary_disclosed', 't02 a disclosed job salary needs an amount');
SELECT pg_temp.expect_error(format($$UPDATE candidate_profile SET salary_disclosure_id = 1, expected_salary_amount = NULL,
    expected_salary_currency_id = NULL WHERE id = %s$$, :cand), 'ck_candidate_profile_salary', 't02 a disclosed expected salary needs an amount');
SELECT pg_temp.check((SELECT count(DISTINCT salary_disclosure_id) = 2 FROM candidate_profile WHERE expected_salary_amount IS NULL),
                     't02 "not disclosed" and "not provided" are stored as different facts');
SELECT pg_temp.expect_error(format($$UPDATE job_requirement SET job_status_id = 1 WHERE id = %s$$, :job_open), 'ck_job_requirement_published',
                            't02 a published job cannot go back to draft');

-- applications and the pipeline
SELECT pg_temp.expect_error(format($$INSERT INTO application (job_requirement_id, candidate_profile_id, resume_id) VALUES (%s, %s, %s)$$,
    :job_open, :cand, :other_resume), 'fk_application_resume', 't02 an applicant can only attach their own resume');
SELECT pg_temp.expect_error(format($$INSERT INTO application (job_requirement_id, candidate_profile_id, application_status_id) VALUES (%s, %s, 2)$$,
    :job_open, :cand), 'starts as applied', 't02 a new application starts as applied');
SELECT pg_temp.expect_error(format($$INSERT INTO application (job_requirement_id, candidate_profile_id) VALUES (%s, %s)$$, :job_closed, :cand),
    'not open for applications', 't02 no applications to a closed job');
SELECT pg_temp.expect_error(format($$INSERT INTO application (job_requirement_id, candidate_profile_id, application_source_id, sourced_by_app_user_id)
    VALUES (%s, %s, 3, %s)$$, :job_open, :cand, :consultant), 'not open to consultants', 't02 consultants only on jobs open to consultants');
INSERT INTO application (job_requirement_id, candidate_profile_id) VALUES (:job_open, :cand) RETURNING id AS new_app \gset
SELECT pg_temp.check((SELECT count(*) = 1 AND bool_and(from_status_id IS NULL AND to_status_id = 1) FROM application_status_history WHERE application_id = :new_app)
                     AND (SELECT organisation_id FROM application WHERE id = :new_app) = (SELECT organisation_id FROM job_requirement WHERE id = :job_open),
                     't02 a valid application is accepted, copies the job''s organisation and starts its history');
SELECT pg_temp.expect_error(format($$UPDATE application SET application_status_id = 5 WHERE id = %s$$, :app_applied), 'cannot move from status',
                            't02 the pipeline refuses applied -> joined');
SELECT pg_temp.expect_error(format($$INSERT INTO application (job_requirement_id, candidate_profile_id) VALUES (%s, %s)$$, :job_open, :cand),
                            'uq_application_job_requirement_id_candidate_profile_id', 't02 one application per candidate per job');
SELECT pg_temp.expect_error(format($$INSERT INTO application_answer (application_id, job_requirement_id, screening_question_id, answer_text)
    VALUES (%s, %s, %s, 'yes')$$, :new_app, :job_open, :other_question), 'fk_application_answer_screening_question',
    't02 answers only to questions of the job applied for');
SELECT positions_filled AS filled_before FROM job_requirement WHERE id = :app_offered_job \gset
UPDATE application SET application_status_id = 5 WHERE id = :app_offered;
SELECT pg_temp.check((SELECT positions_filled = :filled_before + 1 FROM job_requirement WHERE id = :app_offered_job)
                     AND EXISTS (SELECT 1 FROM notification WHERE dedupe_key = 'application_status:' || :app_offered || ':5'),
                     't02 a join fills one position and queues the candidate''s notification in the same transaction');
SELECT pg_temp.check((SELECT count(*) = 0 FROM job_requirement WHERE positions_filled > positions_total), 't02 no job has more joins than positions');

-- subscriptions, seats, memberships (rule groups 2, 9, 10)
SELECT pg_temp.expect_error(format($$INSERT INTO subscription (organisation_id, plan_id, max_seats, max_devices_per_user, starts_on, ends_on)
    VALUES (%s, 1, 2, 1, %L, %L)$$, :sub_org, :'sub_start', :'sub_end'), 'ex_subscription_no_overlap', 't02 subscription periods of one licence cannot overlap');
SELECT pg_temp.expect_error(format($$INSERT INTO subscription (organisation_id, plan_id, max_seats, max_devices_per_user, starts_on, ends_on)
    VALUES (%s, 1, 0, 1, '2030-01-01', '2030-02-01')$$, :sub_org), 'max_seats_check', 't02 licence seats must be positive');
SELECT pg_temp.expect_error(format($$UPDATE subscription SET max_seats = 99 WHERE id = %s$$, :sub), 'only cancellation', 't02 a sold licence''s limits cannot change');
SELECT pg_temp.expect_error(format($$INSERT INTO organisation_member (organisation_id, app_user_id, access_role_id) VALUES (%s, %s, 5)$$, :free_org, :member_user),
                            'ex_organisation_member_one_organisation', 't02 a recruiter belongs to one organisation at a time');
SELECT pg_temp.expect_error(format($$INSERT INTO organisation_member (organisation_id, app_user_id, access_role_id) VALUES (%s, %s, 5)$$, :full_org, :cand_user),
                            'used all', 't02 the seat limit of the licence is enforced');
SELECT pg_temp.expect_error(format($$INSERT INTO organisation_member (organisation_id, app_user_id, access_role_id) VALUES (%s, %s, 8)$$, :free_org, :cand_user),
                            'ck_organisation_member_role', 't02 only account admins, employers and recruiters can be members');
UPDATE organisation SET parent_organisation_id = :org_b WHERE id = :org_a;
SELECT pg_temp.expect_error(format($$UPDATE organisation SET parent_organisation_id = %s WHERE id = %s$$, :org_a, :org_b), 'own descendant',
                            't02 the organisation hierarchy cannot form a cycle');

-- wallet and ledger
SELECT pg_temp.expect_error(format($$UPDATE wallet_ledger_entry SET credits = credits WHERE id = %s$$, :ledger_entry), 'append-only', 't02 ledger entries cannot be updated');
SELECT pg_temp.expect_error(format($$DELETE FROM wallet_ledger_entry WHERE id = %s$$, :ledger_entry), 'append-only', 't02 ledger entries cannot be deleted');
SELECT pg_temp.expect_error($$UPDATE audit_event SET action = 'x.y' WHERE id = (SELECT min(id) FROM audit_event)$$, 'append-only', 't02 audit events cannot be changed');
SELECT pg_temp.expect_error(format($$SELECT wallet_post(%s, 'profile_download_debit', -(%s + 1), 'test-overdraw-1')$$, :wallet, :balance),
                            'insufficient credits', 't02 a wallet cannot go below zero');
SELECT pg_temp.expect_error(format($$SELECT wallet_post(%s, 'recharge', -5, 'test-wrong-sign')$$, :wallet), 'ck_wallet_ledger_entry_sign', 't02 entry signs follow their type');
SELECT wallet_post(:wallet, 'recharge', 10, 'test-idempotent-1') AS e1 \gset
SELECT wallet_post(:wallet, 'recharge', 10, 'test-idempotent-1') AS e2 \gset
SELECT pg_temp.check(:e1 = :e2 AND (SELECT balance_credits = :balance + 10 FROM wallet WHERE id = :wallet), 't02 replaying an idempotency key charges once');

-- payments: purpose, webhook idempotency, amount check, refund reverses credits
SELECT pg_temp.expect_error(format($$INSERT INTO payment_order (organisation_id, payment_purpose_id, amount, currency_id, plan_id, idempotency_key)
    VALUES (%s, 1, 5000, 1, 1, 'test-purpose-1')$$, :wallet_org), 'ck_payment_order_purpose', 't02 a recharge order must say credits, not a plan');
INSERT INTO payment_order (organisation_id, payment_purpose_id, amount, currency_id, credits_to_grant, idempotency_key)
VALUES (:wallet_org, 1, 5000, 1, 100, 'test-order-1') RETURNING id AS ord \gset
SELECT balance_credits AS before_capture FROM wallet WHERE id = :wallet \gset
-- separate statements: a statement does not see the writes of the functions it calls
SELECT billing_apply_payment_event(:ord, 'captured', 'evt_test_1', 5000, now(), sha256('x'::bytea)) AS first_delivery \gset
SELECT billing_apply_payment_event(:ord, 'captured', 'evt_test_1', 5000, now(), sha256('x'::bytea)) AS second_delivery \gset
SELECT pg_temp.check(:'first_delivery'::boolean AND NOT :'second_delivery'::boolean
                     AND (SELECT balance_credits = :before_capture + 100 FROM wallet WHERE id = :wallet)
                     AND (SELECT count(*) = 1 FROM invoice WHERE payment_order_id = :ord),
                     't02 a redelivered payment webhook is a no-op: credits and invoice once');
SELECT pg_temp.check((SELECT total_amount = subtotal_amount + tax_amount AND tax_amount > 0 FROM invoice WHERE payment_order_id = :ord), 't02 invoice total = subtotal + GST');
SELECT pg_temp.expect_error(format($$SELECT billing_apply_payment_event(%s, 'refunded', 'evt_test_2', 4000, now(), sha256('y'::bytea))$$, :ord),
                            'does not match', 't02 a webhook amount must match the order');
SELECT billing_apply_payment_event(:ord, 'refunded', 'evt_test_3', 5000, now(), sha256('z'::bytea)) \g
SELECT pg_temp.check((SELECT balance_credits = :before_capture FROM wallet WHERE id = :wallet)
                     AND EXISTS (SELECT 1 FROM wallet_ledger_entry WHERE idempotency_key = 'refund:' || :ord AND reverses_ledger_entry_id IS NOT NULL),
                     't02 a refund is a reversal entry pointing at the original, never an update');

-- sessions, notifications, translations
SELECT pg_temp.expect_error(format($$UPDATE user_session SET ended_at = now() WHERE app_user_id = %s AND ended_at IS NULL$$,
    (SELECT app_user_id FROM user_session WHERE ended_at IS NULL LIMIT 1)), 'ck_user_session_ended', 't02 an ended session records why');
INSERT INTO notification_preference (app_user_id, notification_category_id, notification_channel_id, is_enabled) VALUES (:cand_user, 5, 2, false)
ON CONFLICT (app_user_id, notification_category_id, notification_channel_id) DO UPDATE SET is_enabled = false;
INSERT INTO notification (app_user_id, notification_category_id, notification_channel_id, template_key) VALUES (:cand_user, 5, 2, 'marketing.offer') RETURNING id AS n_marketing \gset
INSERT INTO notification_preference (app_user_id, notification_category_id, notification_channel_id, is_enabled) VALUES (:cand_user, 3, 2, false)
ON CONFLICT (app_user_id, notification_category_id, notification_channel_id) DO UPDATE SET is_enabled = false;
INSERT INTO notification (app_user_id, notification_category_id, notification_channel_id, template_key) VALUES (:cand_user, 3, 2, 'security.new_login') RETURNING id AS n_security \gset
SELECT pg_temp.check((SELECT notification_status_id = 5 FROM notification WHERE id = :n_marketing) AND (SELECT notification_status_id = 1 FROM notification WHERE id = :n_security),
                     't02 an opt-out suppresses marketing but never security notices');
SELECT pg_temp.check(ui_text((SELECT id FROM ui_label WHERE label_key = 'application_status.applied'), 3::smallint) = 'விண்ணப்பிக்கப்பட்டது'
                     AND ui_text((SELECT id FROM ui_label WHERE label_key = 'application_status.applied'), 4::smallint) = 'Applied',
                     't02 UI text in Tamil, with fallback to English for Telugu');

-- erasure keeps others' records but removes the person
SELECT count(*) AS apps_before FROM application WHERE candidate_profile_id = :cand \gset
SELECT candidate_erase(:cand) \g
SELECT pg_temp.check((SELECT email IS NULL AND phone_e164 IS NULL AND account_status_id = 4 FROM app_user WHERE id = :cand_user)
                     AND NOT EXISTS (SELECT 1 FROM candidate_skill WHERE candidate_profile_id = :cand)
                     AND NOT EXISTS (SELECT 1 FROM user_credential WHERE app_user_id = :cand_user)
                     AND (SELECT count(*) FROM application WHERE candidate_profile_id = :cand) = :apps_before
                     AND EXISTS (SELECT 1 FROM audit_event WHERE action = 'candidate_profile.erased' AND entity_id = :cand),
                     't02 erasure removes personal data, keeps applications, and is audited');
ROLLBACK;
