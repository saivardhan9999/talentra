# Continued curated notes for Phase 3 (Steps 16, 18, 20, 21)

# Refined Phase 2 rules list (for Step 18 unified rules catalogue: all 6 gaps from Phase 2 are now enforced in Database!)
RULES_V2_OVERRIDES = {
    'Every organisation has exactly one wallet': (
        'database', 'uq_wallet_organisation_id + AFTER INSERT trigger trg_organisation_ensure_wallet (FND-13 closed)', 'BR-18', 'TC-20-026, t05 R-14'),
    'A device can be revoked by its owner or staff': (
        'database', 'function auth_revoke_device() + write-once trigger trg_user_device_guard (FND-04 closed)', 'BR-07', 'TC-20-011..013'),
    'Account lockout after repeated failed logins': (
        'database', 'function auth_record_login_failure() + lockout check in auth_open_session() (FND-14 closed)', 'BR-08', 'TC-20-027..028'),
    'Staff verify organisations: pending → verified / rejected, with time': (
        'database', 'function organisation_set_verification() + ck_organisation_verified_at (FND-03 closed)', 'BR-10', 'TC-20-007..010'),
    'A published job never returns to draft; closed and filled are final': (
        'database', 'table job_status_transition + trigger trg_job_requirement_guard (FND-01, FND-02 closed)', 'BR-11', 'TC-20-001..006'),
    'Pending organisations may publish jobs (finding F-05)': (
        'application', 'explicit product policy (SA-04): allowed at launch for frictionless onboarding, monitored by DQ rule F-05', 'BR-28', 't05 F-05'),
    'Marketing and WhatsApp messages need the matching consent': (
        'database', 'trigger notification_apply_preference() reading consent_current for purposes 4 and 5 (FND-09 closed)', 'BR-21', 'TC-20-022'),
    'Hidden profiles never appear to recruiters': (
        'database', 'RLS candidate_profile_read + app_candidate_visible() checking visibility <> 3 and purpose 3 consent (FND-09 closed)', 'BR-03', 'TC-20-023, t03'),
    'Erasure on request removes or blanks personal data in one transaction and keeps others\' records anonymised': (
        'database', 'function candidate_erase() scrubbing profile, sections, resumes, credentials, answer_text and device_label (FND-10, FND-11 closed)', 'BR-23', 'TC-20-024, t02'),
    'A sold licence never changes except cancellation, auto-renew and an earlier end': (
        'database', 'trigger subscription_guard() with write-once cancelled_at (FND-06 closed)', 'BR-17', 'TC-20-017, t02'),
}

# Executable SQL queries for every workflow (Step 16 §2)
WORKFLOW_SQL = [
    ('WF-01', 'Candidate registration and profile building',
     """-- 01.1 & 01.2: Guest self-registers (creates app_user, user_credential, user_access_role, candidate_profile, and 2 consent_record rows)
SELECT auth_register_candidate('arun.k@mail.test', '$argon2id$v=19$m=65536,t=3,p=4$c2FsdA$aGFzaA', 'Arun Kumar', '+919845099901', 1::smallint, 1::smallint, '2026-01');
-- 01.3..01.6: Candidate adds skills, resume, visibility, and job alert
SELECT p.id, p.full_name, u.email, count(DISTINCT cs.skill_id) AS skills, count(DISTINCT r.id) AS resumes
FROM candidate_profile p
JOIN app_user u ON u.id = p.app_user_id
LEFT JOIN candidate_skill cs ON cs.candidate_profile_id = p.id
LEFT JOIN resume r ON r.candidate_profile_id = p.id
WHERE u.email = 'cand1@mail.test'
GROUP BY p.id, p.full_name, u.email;""",
     'cand1 (`Priya Sharma`) returned with `skills = 4`, `resumes = 1` (primary PDF), terms + privacy consents active.'),
    ('WF-02', 'Employer registration and verification',
     """-- 02.1..02.3: Employer registers organisation + wallet + admin member + HMAC tax ID
SELECT auth_register_employer('founder@newco.test', '$argon2id$v=19$m=65536,t=3,p=4$c2FsdA$aGFzaA', 'NewCo Labs Private Limited', 'NewCo Labs', 1::smallint, 1::smallint);
-- 02.4: Staff verifies pending organisation (FND-03 entry point)
SELECT organisation_set_verification((SELECT id FROM organisation WHERE display_name = 'Deccan Healthcare'), 'verified', 'Registry GSTIN match');
-- 02.5: Inspect organisation, verification status, wallet and active seat usage
SELECT o.display_name, vs.code AS status, w.balance_credits, count(m.id) FILTER (WHERE m.valid_to IS NULL) AS active_members
FROM organisation o
JOIN verification_status vs ON vs.id = o.verification_status_id
JOIN wallet w ON w.organisation_id = o.id
LEFT JOIN organisation_member m ON m.organisation_id = o.id
GROUP BY o.id, o.display_name, vs.code, w.balance_credits ORDER BY o.id;""",
     '6 seeded organisations returned with exact wallet balances and active seat counts; `organisation_set_verification` transitions `pending -> verified` and logs `organisation.verification_verified`.'),
    ('WF-03', 'Job requirement posting',
     """-- 03.1..03.3: Publish a draft job (J6 -> status 2 open); trigger sets published_at and debits 5 credits once
UPDATE job_requirement SET job_status_id = 2 WHERE title = 'Draft: Principal Data Engineer';
-- Verify job_post_debit ledger entry was written automatically
SELECT j.id, j.title, js.code AS status, j.published_at, e.credits, e.idempotency_key
FROM job_requirement j
JOIN job_status js ON js.id = j.job_status_id
JOIN wallet w ON w.organisation_id = j.organisation_id
JOIN wallet_ledger_entry e ON e.wallet_id = w.id AND e.idempotency_key = 'job_post:' || j.id
WHERE j.title = 'Java Backend Developer';""",
     'Job `Java Backend Developer` (`open`) paired with ledger entry `job_post:<id>` for `-5` credits.'),
    ('WF-04', 'Job search and application',
     """-- 04.1: Full-text + city + salary search on open jobs (AP-01)
SELECT j.id, o.display_name, j.title, j.salary_min_amount, j.salary_max_amount
FROM job_requirement j
JOIN organisation o ON o.id = j.organisation_id
JOIN job_requirement_location jl ON jl.job_requirement_id = j.id
WHERE j.job_status_id = 2 AND j.deleted_at IS NULL
  AND j.search_vector @@ plainto_tsquery('simple', 'java developer')
  AND jl.city_id = 1
ORDER BY j.published_at DESC;""",
     'Returns open Bengaluru Java job(s) newest first via `idx_job_requirement_search_vector`.'),
    ('WF-05', 'Application pipeline',
     """-- 05.1..05.3: Recruiter lists applicants of Job 1 by pipeline stage with translated stage label
SELECT a.id AS app_id, p.full_name, s.code AS stage, ui_text(s.ui_label_id, 2::smallint) AS stage_hi,
       (SELECT count(*) FROM application_status_history h WHERE h.application_id = a.id) AS history_steps
FROM application a
JOIN candidate_profile p ON p.id = a.candidate_profile_id
JOIN application_status s ON s.id = a.application_status_id
JOIN job_requirement j ON j.id = a.job_requirement_id
WHERE j.title = 'Java Backend Developer'
ORDER BY s.sort_order, a.applied_at;""",
     '10 applications on Job 1 returned across `applied`, `shortlisted`, `interviewing`, `offered`, `joined`, `rejected`, `withdrawn` with Hindi labels (`आवेदन किया`, `शॉर्टलिस्ट`, etc.).'),
    ('WF-06', 'Candidate sourcing and profile download',
     """-- 06.1..06.3: Recruiter searches visible open-to-work candidates by skill & city, downloads profile, and reveals contact
SELECT p.id, p.full_name, p.headline, p.total_experience_months
FROM candidate_profile p
JOIN candidate_skill cs ON cs.candidate_profile_id = p.id
WHERE p.is_open_to_work AND p.deleted_at IS NULL AND p.profile_visibility_id <> 3
  AND p.current_city_id = 1 AND cs.skill_id = 1
ORDER BY p.last_active_at DESC;
-- Paid download (1 credit, idempotent for 30 days) + audited contact reveal:
-- SELECT billing_download_profile(:cand_id); SELECT * FROM candidate_contact(:cand_id);""",
     'Returns visible Bengaluru Java candidates (excluding hidden profiles, blocked orgs, and `cand27` who withdrew purpose 3 consent).'),
    ('WF-07', 'Subscription, recharge and credit use',
     """-- 07.1..07.5: Reconcile payment orders, webhook events, subscriptions, GST invoices, and wallet ledger
SELECT po.id, o.display_name, pp.code AS purpose, po.amount, ps.code AS status, i.invoice_number, i.subtotal_amount, i.tax_amount
FROM payment_order po
JOIN organisation o ON o.id = po.organisation_id
JOIN payment_purpose pp ON pp.id = po.payment_purpose_id
JOIN payment_status ps ON ps.id = po.payment_status_id
LEFT JOIN invoice i ON i.payment_order_id = po.id
ORDER BY po.id;""",
     '10 payment orders across all 5 statuses (`created`, `authorised`, `captured`, `failed`, `refunded`) and 6 GST invoices (`total = subtotal + 18% GST`).'),
    ('WF-08', 'Login with device limit',
     """-- 08.1..08.5: Verify active device count vs licence limit per user, plus login failure lockout & device revocation
SELECT u.email, count(DISTINCT s.user_device_id) FILTER (WHERE s.ended_at IS NULL) AS active_devices,
       app_device_limit(u.id) AS limit_allowed,
       count(d.id) FILTER (WHERE d.revoked_at IS NOT NULL) AS revoked_devices
FROM app_user u
LEFT JOIN user_device d ON d.app_user_id = u.id
LEFT JOIN user_session s ON s.app_user_id = u.id
GROUP BY u.id, u.email
HAVING count(s.id) > 0 OR count(d.id) FILTER (WHERE d.revoked_at IS NOT NULL) > 0
ORDER BY u.id LIMIT 10;""",
     'Every user has `active_devices <= limit_allowed`; `cand16` shows 1 revoked device with 0 active sessions.'),
    ('WF-09', 'Blocking',
     """-- 09.1..09.2: Inspect active and lifted candidate blocks
SELECT b.id, p.full_name AS candidate, o.display_name AS blocked_org, u.email AS blocked_user,
       b.blocked_at, b.unblocked_at, (b.unblocked_at IS NULL) AS is_active
FROM candidate_block b
JOIN candidate_profile p ON p.id = b.candidate_profile_id
LEFT JOIN organisation o ON o.id = b.blocked_organisation_id
LEFT JOIN app_user u ON u.id = b.blocked_app_user_id
ORDER BY b.id;""",
     '3 blocks: `cand23` blocking `Crescent Logistics` (active), `cand15` blocking `Blue River Finserv` (lifted), `cand24` blocking `rec1@org2.test` (active).'),
    ('WF-10', 'Notifications and job alerts',
     """-- 10.1..10.5: Outbox queue summary by category, channel, and delivery status
SELECT nc.code AS category, ch.code AS channel, ns.code AS status, count(*)
FROM notification n
JOIN notification_category nc ON nc.id = n.notification_category_id
JOIN notification_channel ch ON ch.id = n.notification_channel_id
JOIN notification_status ns ON ns.id = n.notification_status_id
GROUP BY nc.code, ch.code, ns.code, ns.id
ORDER BY ns.id, nc.code;""",
     '56 notifications spanning `queued`, `sent`, `delivered`, `failed`, and `suppressed` (opt-out & missing consent).'),
    ('WF-14', 'Data erasure (DPDP Act 2023)',
     """-- 14.1..14.2: Verify erased candidate (cand30) has blanked PII, [erased] answers, NULL device labels, but retained application
SELECT u.id AS user_id, u.email, u.phone_e164, ast.code AS account_status,
       p.id AS profile_id, p.full_name, p.deleted_at IS NOT NULL AS is_deleted,
       (SELECT count(*) FROM application a WHERE a.candidate_profile_id = p.id) AS retained_apps,
       (SELECT string_agg(DISTINCT aa.answer_text, ',') FROM application_answer aa JOIN application a ON a.id = aa.application_id WHERE a.candidate_profile_id = p.id) AS scrubbed_answers
FROM candidate_profile p
JOIN app_user u ON u.id = p.app_user_id
JOIN account_status ast ON ast.id = u.account_status_id
WHERE p.deleted_at IS NOT NULL;""",
     'Returns `cand30`: `email = NULL`, `phone_e164 = NULL`, `account_status = erased`, `full_name = Erased candidate 30`, `retained_apps = 1`, `scrubbed_answers = [erased]`.'),
    ('PLATFORM', 'Cross-cutting platform processes',
     """-- P.1..P.6: Role permissions, UI translations with English fallback, hiring funnel aggregate, audit trail, and system errors
SELECT o.display_name, f.month_start, f.applied_count, f.shortlisted_count, f.interviewed_count, f.offered_count, f.joined_count, f.rejected_count, f.median_days_to_join
FROM agg_hiring_funnel_monthly f
JOIN organisation o ON o.id = f.organisation_id
ORDER BY o.id, f.month_start;""",
     'Returns monthly hiring funnel rows for all 4 organisations with applications (`Apex`, `Blue River`, `Crescent`, `Deccan`), including `median_days_to_join`.'),
]

# Step 20: Complete mapping of all 48 negative state transition tests (TC-08-001..048) from Phase 2 Step 08
STATE_TRANSITION_TESTS = [
    ('TC-08-001', 'ENT-26 Application',       'Insert application with status <> applied (e.g. shortlisted=2)', 'Refused (`a new application starts as applied`)',             '`t02_integrity.sql` L54'),
    ('TC-08-002', 'ENT-26 Application',       'Skip stage: `applied (1) -> interviewing (3) / offered (4) / joined (5)`', 'Refused (`cannot move from status 1 to 5`)',          '`t02_integrity.sql` L64'),
    ('TC-08-003', 'ENT-26 Application',       'Skip stage: `shortlisted (2) -> offered (4) / joined (5)`',      'Refused (`application_status_transition` guard)',            '`t02_integrity.sql` L64 / `t05` R-05'),
    ('TC-08-004', 'ENT-26 Application',       'Skip stage: `interviewing (3) -> joined (5)`',                   'Refused (`application_status_transition` guard)',            '`t02_integrity.sql` L64 / `t05` R-05'),
    ('TC-08-005', 'ENT-26 Application',       'Move out of final status (`joined`, `rejected`, `withdrawn`)',   'Refused (no outgoing edges in transition table)',            '`t02_integrity.sql` / `t05` R-05'),
    ('TC-08-006', 'ENT-26 Application',       'Candidate moves own application to `shortlisted` (`+1`)',        'Refused (`a candidate can only withdraw`)',                  '`t03_security.sql` L39'),
    ('TC-08-007', 'ENT-26 Application',       'Two concurrent `offered -> joined` races for the last position', '1 succeeds (`job -> filled`), 1 refused (`ck_job_requirement_positions`)', '`t04_concurrency.sql` L76-88'),
    ('TC-08-008', 'ENT-26 Application',       'Recruiter of a company blocked by the candidate updates app',    'Refused (0 rows visible under RLS `application_update`)',    '`t03_security.sql` L76'),
    ('TC-08-009', 'ENT-22 Job requirement',   '`open / paused / closed / filled -> draft (1)`',                 'Refused (`trg_job_requirement_guard` & `ck_job_requirement_published`)', '`t02` L48, `t06` TC-20-001'),
    ('TC-08-010', 'ENT-22 Job requirement',   '`closed (4)` or `filled (5) -> open (2)` or `paused (3)`',       'Refused (`job_status_transition`: closed & filled are final)', '`t06` TC-20-003, TC-20-004'),
    ('TC-08-011', 'ENT-22 Job requirement',   '`draft (1) -> paused (3)` or `filled (5)`',                      'Refused (`job_status_transition` & `job_requirement_guard`)', '`t06` TC-20-005'),
    ('TC-08-012', 'ENT-22 Job requirement',   'Manual update to `filled (5)` while `positions_filled < total`', 'Refused (`cannot be marked filled before all positions are joined`)', '`t06` TC-20-005'),
    ('TC-08-013', 'ENT-22 Job requirement',   'Clear or overwrite `published_at` after publishing',             'Refused (`published_at is write-once`)',                     '`t06` TC-20-001, TC-20-002'),
    ('TC-08-014', 'ENT-22 Job requirement',   '`open -> paused -> open` (re-publishing a paused job)',          'Charged once (`job_post:<id>` idempotency key)',             '`t06` TC-20-006'),
    ('TC-08-015', 'ENT-22 Job requirement',   'Publish job when wallet has `< 5` credits',                      'Refused (`insufficient credits` in `wallet_post`)',          '`t02_integrity.sql` L98'),
    ('TC-08-016', 'ENT-10 Organisation',      'Non-staff (recruiter/admin) calls `organisation_set_verification`','Refused (`only staff with organisation_verify permission`)', '`t06` TC-20-007'),
    ('TC-08-017', 'ENT-10 Organisation',      'Staff verifies pending org via `organisation_set_verification`', 'Succeeded (`verified_at` set, tax ID updated, audited)',     '`t06` TC-20-008'),
    ('TC-08-018', 'ENT-10 Organisation',      'Move `verified (2) -> pending (1)`',                             'Refused (`cannot move verification status from 2 to 1`)',    '`t06` TC-20-009'),
    ('TC-08-019', 'ENT-10 Organisation',      '`verified (2)` with `verified_at IS NULL` (or vice versa)',      'Refused (`ck_organisation_verified_at`)',                    '`t06` TC-20-008'),
    ('TC-08-020', 'ENT-12 Tax identifier',    '`verified` or `rejected` with mismatched `verified_at`',         'Refused (`ck_organisation_tax_identifier_verified_at`)',     '`t06` TC-20-008'),
    ('TC-08-021', 'ENT-12 Tax identifier',    'Duplicate `(country_id, tax_identifier_type_id, identifier_hmac)`','Refused (`uq_organisation_tax_identifier_country_id_type_hmac`)', '`t01_standards.sql`'),
    ('TC-08-022', 'ENT-01 User account',      'Move `erased (4) -> active (1)`',                                'Refused (`trg_app_user_status_guard`: erased is final)',     '`t06` TC-20-014'),
    ('TC-08-023', 'ENT-01 User account',      'Suspended/deactivated/erased user calls `auth_open_session()`',  'Refused (`user % cannot log in`)',                           '`t06` TC-20-016'),
    ('TC-08-024', 'ENT-01 User account',      'Non-staff user attempts to suspend or unsuspend an account',     'Refused (`only staff may suspend or unsuspend`)',            '`t06` TC-20-015'),
    ('TC-08-025', 'ENT-34 Payment order',     'Same `gateway_event_ref` webhook delivered twice',               'Second call returns `false` (no-op); credits/invoice once',  '`t02_integrity.sql` L112-117'),
    ('TC-08-026', 'ENT-34 Payment order',     'Webhook event `amount` differs from `payment_order.amount`',     'Refused (`event amount % does not match order amount %`)',   '`t02_integrity.sql` L119-120'),
    ('TC-08-027', 'ENT-34 Payment order',     'Out-of-order webhook (e.g. `authorised` after `captured`)',      'Event stored as evidence; `payment_order` status unchanged', '`V008` L220-222'),
    ('TC-08-028', 'ENT-34 Payment order',     'Move `failed (4) -> captured (3)`',                              'Event stored; order stays `failed` (`(4,3)` not in pairs)', '`V008` L220-222'),
    ('TC-08-029', 'ENT-34 Payment order',     'Refund webhook when granted credits were already spent',         'Refused (`insufficient credits` in reversal `wallet_post`)', '`t02_integrity.sql` L98, L121'),
    ('TC-08-030', 'ENT-31 Subscription',      'Extend `ends_on` or modify `max_seats` / `max_devices` / `plan`','Refused (`subscription_guard()`)',                           '`t02_integrity.sql` L83'),
    ('TC-08-031', 'ENT-31 Subscription',      'Insert overlapping `[starts_on, ends_on)` for same org',         'Refused (`ex_subscription_no_overlap`)',                     '`t02_integrity.sql` L79-80'),
    ('TC-08-032', 'ENT-31 Subscription',      'Clear `cancelled_at` back to `NULL` after cancellation',         'Refused (`cancelled_at is write-once`, FND-06)',             '`t06` TC-20-017'),
    ('TC-08-033', 'ENT-09 Session',           'Login when active devices equal the user\'s device limit',       'Refused (`RETURN NULL`) and audited (`device_limit`)',       '`t04_concurrency.sql` L28-40'),
    ('TC-08-034', 'ENT-09 Session',           'Expired session (`expires_at <= now()`) present at login',       'Closed automatically (`idle_timeout`) and not counted',      '`V013` `auth_open_session`'),
    ('TC-08-035', 'ENT-09 Session',           'Non-staff user calls `auth_end_session` with `revoked_by_admin`','Refused (`invalid end reason`)',                             '`t03_security.sql` L70'),
    ('TC-08-036', 'ENT-09 Session',           'Set `ended_at` without `session_end_reason_id` (or vice versa)', 'Refused (`ck_user_session_ended`)',                          '`t02_integrity.sql` L127-128'),
    ('TC-08-037', 'ENT-08 Device',            'Login from a revoked device (`revoked_at IS NOT NULL`)',         'Refused (`RETURN NULL`) and audited (`device_revoked`)',     '`t06` TC-20-012'),
    ('TC-08-038', 'ENT-08 Device',            'Un-revoke a device by setting `revoked_at = NULL`',              'Refused (`trg_user_device_guard`: `revoked_at is write-once`)','`t06` TC-20-013'),
    ('TC-08-039', 'ENT-13 Membership',        'Reopen ended membership by setting `valid_to = NULL`',           'Refused (`trg_organisation_member_close_once`, FND-07)',     '`t06` TC-20-018'),
    ('TC-08-040', 'ENT-13 Membership',        'Second overlapping active membership for the same user',         'Refused (`ex_organisation_member_one_organisation`)',        '`t02_integrity.sql` L84-85'),
    ('TC-08-041', 'ENT-20 Block',             'Duplicate active block on same org/user or clearing `unblocked_at`','Refused (`uq_candidate_block_active_*` & `trg_candidate_block_close_once`)', '`t06` TC-20-019'),
    ('TC-08-042', 'ENT-39 Notification',      'Move `delivered (3)`, `failed (4)`, or `suppressed (5)` to another status','Refused (`notification_record_result` state check, FND-08)','`t06` TC-20-020, TC-20-021'),
    ('TC-08-043', 'ENT-39 Notification',      'Insert marketing notification when opted out or no consent',     'Automatically set to `suppressed (5)` (`notification_apply_preference`)', '`t02` L131, `t06` TC-20-022'),
    ('TC-08-044', 'ENT-39 Notification',      'Insert `account_security (3)` notification when user opted out', 'Stays `queued (1)` (security notices cannot be suppressed)', '`t02_integrity.sql` L134-136'),
    ('TC-08-045', 'ENT-39 Notification',      'Concurrent workers calling `notification_claim()`',              'Disjoint batches claimed via `FOR UPDATE SKIP LOCKED`',      '`V011` L55-61'),
    ('TC-08-046', 'ENT-33 Ledger entry',      'Reverse the same ledger entry twice',                            'Refused (`uq_wallet_ledger_entry_reverses_ledger_entry_id`)','`t02_integrity.sql` L121-124'),
    ('TC-08-047', 'ENT-33 Ledger entry',      '`UPDATE` or `DELETE` any row in `wallet_ledger_entry`',          'Refused (`trg_wallet_ledger_entry_append_only`)',            '`t02_integrity.sql` L95-96'),
    ('TC-08-048', 'ENT-07 Consent',           '`UPDATE` or `DELETE` any row in `consent_record`',               'Refused (`trg_consent_record_append_only`)',                 '`t01_standards.sql` L96-100'),
]

# Boundary Value Analysis Register (Step 20 §4)
BOUNDARY_TESTS = [
    ('`person_name` length (1..150 chars)',                '1 char & 150 chars (`repeat(\'A\', 150)::person_name`)',         '0 chars (`\'\'`) & 151 chars (`repeat(\'A\', 151)`)',                 '`t06` TC-15-001..004'),
    ('`money_amount` non-negative (`>= 0.00`)',            '`0.00::money_amount`',                                           '`-0.01::money_amount`',                                               '`t06` TC-15-005..006'),
    ('`percentage` range (`0.00..100.00`)',                '`0.00` & `100.00::percentage`',                                  '`-0.01` & `100.01::percentage`',                                      '`t06` TC-15-005, 007'),
    ('`latitude` (`-90..90`) & `longitude` (`-180..180`)', '`-90.000000`, `90.000000`, `-180.000000`, `180.000000`',         '`90.000001::latitude` & `-180.000001::longitude`',                    '`t06` TC-15-005, 008, 009'),
    ('`sha256_digest` octet length (`= 32` bytes)',        '`sha256(\'x\'::bytea)` (32 bytes)',                              '`\'\\x1234\'::sha256_digest` (2 bytes)',                              '`t06` TC-15-010'),
    ('`candidate_profile.total_experience_months` (0..720)','`0` months (intern) & `720` months (60 years)',                 '`-1` & `721` months',                                                 '`t06` TC-15-011'),
    ('`candidate_profile.notice_period_days` (0..365)',    '`0` days (immediate) & `365` days',                              '`-1` & `366` days',                                                   '`t06` TC-15-012'),
    ('`job_requirement.positions_total` (1..10000)',       '`1` position & `10000` positions',                               '`0` positions & `10001` positions',                                   '`t06` TC-15-013..014'),
    ('`job_requirement.positions_filled` (`<= total`)',    '`positions_filled = positions_total` (auto-marks job `filled`)', '`positions_filled = positions_total + 1` (2 offers race for last 1)', '`t04` #4, `t02` L76'),
    ('`wallet.balance_credits` (`>= 0`)',                  'Debit exact remaining balance (`3 - 3 = 0` credits)',            'Debit `balance + 1` (`- (balance + 1)` or 8 races on 3 credits)',     '`t02` L98, `t04` #2'),
    ('`subscription.max_seats` (`used <= max_seats`)',     'Add `max_seats`-th member (1 free seat left -> succeeds)',       'Add `(max_seats + 1)`-th member (full org -> refused)',               '`t02` L86, `t04` #3'),
    ('`app_device_limit` (`active_devices <= limit`)',     'Open 3rd concurrent device session for candidate (limit = 3)',   'Open 4th..6th device sessions (refused + audited `device_limit`)',    '`t04` #1'),
    ('`user_credential.failed_attempt_count` (`lock at N`)','`N - 1` failures (2 of 3 -> `locked_until IS NULL`)',           '`N`-th failure (3 of 3 -> `locked_until` set, login refused)',        '`t06` TC-20-027..028'),
    ('`profile_download` 30-day window (`<= 30 days`)',    'Repeat download at `< 30 days` (0 credits, returns existing id)','First download or `> 30 days` (debits 1 credit, new row)',            '`t03` L61-63'),
]

# NFR Verification Register (Step 20 §5)
NFR_TESTS = [
    ('NFR-PERF-01', 'Interactive reads (AP-01..AP-14) p95 <= 50 ms dev; <= 200 ms full',  '`bench/bench.py` (`docs/benchmark-results.md`)', 'Max p95 at 10k profiles is **5.3 ms** (`AP-01` full-text job search); projected 10M p95 <= 140 ms'),
    ('NFR-PERF-02', 'Write transactions p95 <= 50 ms',                                    '`bench/bench.py` (`AP-03`, `AP-07`, `AP-11`, `AP-13`)', 'Write & lock paths p95 **0.3 ms – 1.8 ms**'),
    ('NFR-PERF-03', 'RLS overhead <= 2x owner query (viewer context evaluated once)',     '`t03_security.sql` + `bench/bench.py`',          'Inline initPlan evaluates `(SELECT app_current_user_id())` once per query (`3.4 ms` vs `3,700 ms` un-inlined)'),
    ('NFR-PERF-04', 'Statement timeout on runtime roles (`5s` API, `60s` reporting)',     '`V001__foundation.sql` L17-18 + `pg_db_role_setting`', '`v2_app` has `statement_timeout = 5s`; `v2_reporting` has `60s`'),
    ('NFR-PERF-05', 'Deterministic, fast dataset rebuild (`setseed`)',                    '`seed_prove_sample.sql` (< 1 s) & `seed.sql` (~8 s)', 'Seeded PRNG (`0.314159` / `0.42`) produces identical rows every run'),
    ('NFR-SCAL-01', 'Same schema serves 10k to 10M profiles with documented triggers',    '`13-data-volumetrics.md` & `21-baseline-er-and-physical-model.md`', 'Scale triggers defined for partitioning, read replicas, PgBouncer, and OpenSearch'),
    ('NFR-SCAL-02', 'Full-scale peak throughput (600 search/s, 60 login/s, 10 app/s)',    '`13-data-volumetrics.md` §5 + `t04_concurrency.sql`', 'Per-row locks scope contention to single user/wallet/job; reads are lock-free'),
    ('NFR-SCAL-03', 'Year-3 storage within ~250 GB on a single primary',                  '`13-data-volumetrics.md` §2',                    'Year-3 total across all 48 tables + indexes projected at **~178.4 GB** (< 250 GB target)'),
    ('NFR-REL-01',  '99.9% availability architecture',                                    '`21-baseline-er-and-physical-model.md` §5',      'Synchronous standby + non-blocking `REFRESH MATERIALIZED VIEW CONCURRENTLY`'),
    ('NFR-REL-02',  'RPO <= 5 min, RTO <= 1 h',                                           '`21-baseline-er-and-physical-model.md` §5',      'Continuous WAL archiving + PITR recovery procedure'),
    ('NFR-REL-03',  'Transactional outbox: no lost or duplicate event notifications',     '`t02_integrity.sql` L74 + `V009` `uq_notification_dedupe_key`', 'Status change & notification commit in the same transaction; `dedupe_key` blocks duplicates'),
    ('NFR-REL-04',  'Idempotent external system boundaries',                              '`t02_integrity.sql` L101-117',                   'Tested on `wallet_post(idempotency_key)` and `billing_apply_payment_event(gateway_event_ref)`'),
    ('NFR-SEC-01',  'Least privilege across 4 runtime roles; no PUBLIC routine execution','`t01_standards.sql` L126 + `t03_security.sql`',  'All functions revoked from `PUBLIC`; `v2_app`, `v2_payments`, `v2_worker`, `v2_reporting` separated'),
    ('NFR-SEC-02',  'Argon2id password hashes; `user_credential` unreadable by runtime',  '`t01_standards.sql` L126 + `t03_security.sql` L36', '`SELECT * FROM user_credential` as `v2_app` fails with `permission denied`'),
    ('NFR-SEC-03',  'Tokenised tax IDs (HMAC-SHA256 + last 4) & hashed session/device tokens','`V003`, `V004` `pii_hmac()` + `t01_standards.sql`', '`sha256_digest` (32 bytes) enforced on `identifier_hmac`, `token_hash`, `device_fingerprint_hash`'),
    ('NFR-SEC-04',  'RLS enabled on every business table; tested across all actors',      '`t01_standards.sql` L123-125 + `t03_security.sql`', '100% of business tables have RLS enabled; 36+ actor assertions pass in `t03` & `t06`'),
    ('NFR-SEC-05',  'Encryption in transit (TLS 1.2+) and at rest',                       '`12-data-classification-register.md` + `21-baseline-er-and-physical-model.md`', 'Volume + object-store encryption + irreversible column hashes'),
    ('NFR-PRIV-01', 'DPDP Act 2023 consent history with policy version and IP evidence',  '`t05_data_quality.sql` R-12 + `t06` TC-20-022..023', '100% of live candidates hold active terms & privacy consent; purpose 3, 4, 5 enforced'),
    ('NFR-PRIV-02', 'Visibility and blocking enforced on every query via RLS',            '`t03_security.sql` L52-85 + `t06` TC-20-023',    'Blocked company/recruiter sees 0 rows in `candidate_profile`, `application`, and `candidate_contact()`'),
    ('NFR-PRIV-03', 'Every contact reveal audited; 0 PII values in audit or notification payloads','`t03_security.sql` L93 + `t05_data_quality.sql` R-16', '`candidate_contact.read` audited; `t05` R-16 verifies 0 emails/phones in `notification.payload`'),
    ('NFR-PRIV-04', 'Right to erasure in one transaction (`candidate_erase`) + 3-year job','`t02_integrity.sql` L142-149 + `t06` TC-20-024', 'Erases profile sections, resumes, credentials, contact, `answer_text` and `device_label`; keeps apps anonymised'),
    ('NFR-INT-01',  '13 standard domains used consistently across all tables',            '`t01_standards.sql` L70-75 + `t02` + `t06`',     'All 13 domains tested for valid and invalid boundary values'),
    ('NFR-INT-02',  'Enforced FKs + composite FKs for cross-row consistency (0 orphans)', '`t01_standards.sql` + `t02_integrity.sql` L52, L68', '`fk_application_job_requirement`, `fk_application_resume`, `fk_application_answer_*`, `fk_user_session_user_device`'),
    ('NFR-INT-03',  'Quotas (seats, devices, credits, positions) hold under parallel race','`t04_concurrency.sql` (4 `dblink` parallel races)', 'All 4 parallel race tests pass with exact winner/refusal counts'),
    ('NFR-INT-04',  'Histories, ledgers, invoices, downloads, and audit are append-only', '`t01_standards.sql` L96-100 + `t02` L95-97',     '`forbid_change()` trigger blocks `UPDATE` and `DELETE` on all 7 append-only tables'),
    ('NFR-INT-05',  'Seed satisfies all 16 invariants (`R-01`..`R-16`) and plants `F-01`..`F-06`','`t05_data_quality.sql`',                  '16 invariants = 0 violations; all 6 findings (`F-01`..`F-06`) detected > 0'),
    ('NFR-AUD-01',  '`created_at/by` and `updated_at/by` on every business table',        '`t01_standards.sql` L86-94',                     '100% of business tables carry all 4 columns and `trg_<table>_audit_columns`'),
    ('NFR-AUD-02',  'Unforgeable audit actor (`audit_log()` SECURITY DEFINER)',           '`t03_security.sql` L68',                         'Direct `INSERT INTO audit_event` by `v2_app` is refused (`permission denied`)'),
    ('NFR-AUD-03',  'Partitioned 7-year audit retention (`audit_event_pYYYYMM`)',         '`t01_standards.sql` L116 + `V005__audit.sql`',   '24 monthly partitions + default created by `create_month_partitions()`'),
    ('NFR-I18N-01', 'UTF-8 names in Latin, Devanagari, Tamil, and mononyms',              '`seed_prove_sample.sql` + `t02`',                'Devanagari (`राहुल शर्मा`), Tamil (`கார்த்திக் சுப்பிரமணியம்`), and mononyms (`Murugan`) stored & indexed'),
    ('NFR-I18N-02', 'Translated UI labels with English fallback (`ui_text`)',             '`t01_standards.sql` L81-83 + `t02` L137-139',    '100% of `ui_label` rows have English (`language_id = 1`); Tamil (`3`) and Telugu fallback (`4 -> 1`) verified'),
    ('NFR-I18N-03', 'User-authored content stored once with language reference',          '`V006`, `V007` (`profile_language_id`, `description_language_id`, `content_language_id`)', 'Verified in Data Dictionary v2 (`19-data-dictionary-v2.md`)'),
    ('NFR-MNT-01',  'Numbered, checksummed, forward-only migrations (`V001`..`V013`)',    '`run.sh` (`schema_migration` checksum table)',   'Editing an already-applied migration aborts `run.sh migrate` on SHA-256 mismatch'),
    ('NFR-MNT-02',  'Automated catalog standards suite (`t01_standards.sql`)',            '`db/tests/t01_standards.sql`',                   '15 catalog assertions check naming, keys, FK indexes, domains, audit, comments, and RLS'),
    ('NFR-MNT-03',  'Zero-drift generated documentation from DDL',                        '`phase3/tools/build_phase3.py`',                 'Automated zero-drift assertion in `19-data-dictionary-v2.md` verifies 0 missing tables/columns'),
    ('NFR-OBS-01',  'Application error logging (`system_error`) and slow-query tracking', '`V005__audit.sql` L76-88 + `seed_prove_sample.sql`', '`system_error` indexed by BRIN on `occurred_at` with 8 KB JSON context limit'),
    ('NFR-CMP-01',  'DPDP Act 2023 compliance, sequential GST invoices, zero card data',  '`t02_integrity.sql` L118, L143 + `12-data-classification-register.md`', '`ck_invoice_total` verifies GST math; `payment_order` stores only `gateway_order_ref`'),
]

# Step 21: Migration inventory and access-pattern index mapping
MIGRATION_INVENTORY = [
    ('V001', 'V001__foundation.sql',        'Extensions (`pg_trgm`, `btree_gist`, `pgcrypto`), runtime roles (`v2_app`, `v2_reporting`), 13 standard domains, `app_current_user_id()`, `set_audit_columns()`, `forbid_change()`, `add_audit_columns()`'),
    ('V002', 'V002__reference_data.sql',    '8 reference tables (`language`, `ui_label`, `ui_translation`, `currency`, `country`, `state`, `city`, `skill`), `ui_text()`, `create_lookup()`, and 25 enumeration lookup tables (114 codes)'),
    ('V003', 'V003__identity.sql',          '`app_user`, `user_credential`, `access_role_permission` (34 grants), `user_access_role`, `consent_record`, view `consent_current`, `user_device`, `user_session`'),
    ('V004', 'V004__organisation.sql',      '`pii_hmac()`, `organisation`, `organisation_prevent_cycle()`, `organisation_location`, `organisation_tax_identifier`, `organisation_member` (with GiST exclusion)'),
    ('V005', 'V005__audit.sql',             'Range-partitioned `audit_event` (`audit_event_pYYYYMM`), `create_month_partitions()`, `audit_log()`, `audit_row_change()` triggers, `system_error`'),
    ('V006', 'V006__candidate_profile.sql', '`candidate_profile` (with generated `search_vector`), `candidate_education`, `candidate_experience`, `candidate_skill`, `candidate_language`, `resume`, `candidate_block`'),
    ('V007', 'V007__jobs_applications.sql', '`job_requirement` (with weighted `search_vector`), `job_requirement_location`, `job_requirement_skill`, `screening_question`, `application_status_transition`, `application`, `application_answer`, `application_status_history`, `application_guard()`'),
    ('V008', 'V008__billing.sql',           '`plan` (Starter, Growth, Enterprise), `subscription` (GiST exclusion + `subscription_guard()`), `wallet`, `payment_order`, `payment_event`, `wallet_ledger_entry`, `invoice`, `profile_download`, `wallet_post()`, `job_requirement_charge_posting()`, `billing_apply_payment_event()`'),
    ('V009', 'V009__notifications.sql',     '`notification_preference`, `job_alert`, `notification` (outbox), `notification_apply_preference()`, `application_notify()`'),
    ('V010', 'V010__business_rules.sql',    'Viewer context helpers (`app_viewer_organisation_id`, `app_has_permission`, `app_candidates_blocking_viewer`, `app_candidate_visible`), `auth_open_session()`, `auth_end_session()`, `organisation_member_seat_limit()`, `billing_download_profile()`, `candidate_contact()`'),
    ('V011', 'V011__api_and_security.sql',  'Roles `v2_payments`, `v2_worker`, `auth_register_candidate()`, `auth_register_employer()`, `notification_claim()`, `notification_record_result()`, `candidate_erase()`, `retention_erase_inactive()`, table/column privileges, and RLS policies on all business tables'),
    ('V012', 'V012__analytics.sql',         'Materialized view `agg_hiring_funnel_monthly`, `refresh_aggregates()`, security-barrier view `employer_hiring_funnel`'),
    ('V013', 'V013__phase3_refinements.sql','Phase 3 (Step 17) refinements closing `FND-01`..`FND-14`: `job_status_transition`, `job_requirement_guard()`, `organisation_set_verification()`, `auth_revoke_device()`, `user_device_guard()`, `app_user_status_guard()`, `user_set_account_status()`, `period_close_once_guard()`, `app_users_without_recruiter_consent()`, `organisation_ensure_wallet()`, `auth_record_login_failure()`, updated `subscription_guard()`, `notification_record_result()`, `notification_apply_preference()`, `candidate_erase()`, and 52 column classification comments'),
]

STANDARD_DEVIATIONS = [
    ('D-01', 'Rule Group 4 (Audit Columns)', 'Reference and configuration tables (`language`, `ui_label`, `ui_translation`, `currency`, `country`, `state`, `city`, `skill`, `access_role_permission`, `application_status_transition`, `job_status_transition`, and the 23 lookup tables) omit `created_by` / `updated_by`.',
     'Reference and configuration rows are immutable at runtime and versioned exclusively via git migrations (`V002`, `V003`, `V007`, `V013`); git commit history is their audit trail. Verified by `t01_standards.sql` L86-89.'),
    ('D-02', 'Rule Group 2 & 4 (Primary Key & Audit Columns on Logs)', '`audit_event` has composite PK `(id, occurred_at)` and both `audit_event` and `system_error` omit `created_at/by`, `updated_at/by`.',
     'PostgreSQL declarative partitioning requires the partition key (`occurred_at`) in the primary key. Log tables record `occurred_at` and `actor_app_user_id` / `app_user_id` natively and are append-only, so `updated_at/by` would be redundant.'),
    ('D-03', 'Rule Group 1 (Foreign Key Naming)', 'Role-qualified foreign keys (`parent_organisation_id`, `blocked_organisation_id`, `blocked_app_user_id`, `sourced_by_app_user_id`, `actor_app_user_id`, `from_status_id`, `to_status_id`, `renewed_from_subscription_id`, `reverses_ledger_entry_id`) prepend the role to `<table>_id`.',
     'Disambiguates self-references and tables with multiple foreign keys to the same parent while still ending in `_id` (verified by `t01_standards.sql` L44-49).'),
    ('D-04', 'Rule Group 2 (FK Supporting Indexes)', 'Foreign keys pointing to static reference/lookup tables and `created_by` / `updated_by` audit columns do not carry dedicated B-tree indexes.',
     'Reference/lookup rows and users with history are `RESTRICT`-protected and never hard-deleted, so PostgreSQL never scans child tables for cascading deletes on those columns, saving ~35% index storage overhead. Every FK to a business table is indexed (`t01_standards.sql` L53-59).'),
]
