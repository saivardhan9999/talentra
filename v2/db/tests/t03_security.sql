-- t03 Security: the access rules hold for every actor when queried through the runtime role, exactly as the API would
-- (docket section 3, B79). One transaction, rolled back.
-- Covers FR-IAM-02, FR-ORG-02, FR-PRO-07..08, FR-BIL-05..06, NFR-SEC-01..05, NFR-PRIV-02..03.
BEGIN;

SELECT m.app_user_id AS rec1, m.organisation_id AS org1 FROM organisation_member m JOIN wallet w ON w.organisation_id = m.organisation_id
WHERE m.valid_to IS NULL AND m.access_role_id = 5 AND w.balance_credits >= 2 AND EXISTS (SELECT 1 FROM application a WHERE a.organisation_id = m.organisation_id)
ORDER BY m.id LIMIT 1 \gset
SELECT app_user_id AS rec2, organisation_id AS org2 FROM organisation_member WHERE valid_to IS NULL AND access_role_id = 5 AND organisation_id <> :org1 ORDER BY id LIMIT 1 \gset
SELECT app_user_id AS admin1 FROM organisation_member WHERE organisation_id = :org1 AND access_role_id = 3 AND valid_to IS NULL \gset
SELECT a.candidate_profile_id AS cand, p.app_user_id AS cand_user, a.id AS cand_app FROM application a JOIN candidate_profile p ON p.id = a.candidate_profile_id
WHERE a.organisation_id = :org1 AND p.profile_visibility_id = 1 AND p.deleted_at IS NULL AND a.application_status_id IN (1, 2, 3)
  AND NOT EXISTS (SELECT 1 FROM candidate_block b WHERE b.candidate_profile_id = p.id)
  AND NOT EXISTS (SELECT 1 FROM profile_download d WHERE d.candidate_profile_id = p.id AND d.organisation_id = :org1)
ORDER BY a.id LIMIT 1 \gset
SELECT id AS other_cand FROM candidate_profile WHERE id <> :cand AND deleted_at IS NULL ORDER BY id LIMIT 1 \gset
SELECT id AS hidden_cand FROM candidate_profile WHERE profile_visibility_id = 3 AND deleted_at IS NULL ORDER BY id LIMIT 1 \gset
SELECT id AS draft_other FROM job_requirement WHERE job_status_id = 1 AND organisation_id <> :org1 ORDER BY id LIMIT 1 \gset
SELECT id AS job_other FROM job_requirement WHERE job_status_id = 2 AND organisation_id <> :org1 ORDER BY id LIMIT 1 \gset
SELECT id AS job_open FROM job_requirement WHERE job_status_id = 2 AND closes_on IS NULL AND deleted_at IS NULL ORDER BY id DESC LIMIT 1 \gset
SELECT id AS staff FROM app_user WHERE email = 'admin@talentra.test' \gset
SELECT id AS consultant FROM app_user WHERE email LIKE 'consultant%' ORDER BY id LIMIT 1 \gset
SELECT id AS rec1_session FROM user_session WHERE app_user_id = :rec1 ORDER BY id LIMIT 1 \gset
SELECT count(*) AS all_profiles FROM candidate_profile \gset
SELECT balance_credits AS org1_balance FROM wallet WHERE organisation_id = :org1 \gset

SET LOCAL ROLE v2_app;

-- candidate
SELECT pg_temp.act_as(:cand_user);
SELECT pg_temp.check((SELECT count(*) > 0 FROM application) AND (SELECT count(*) = 0 FROM application WHERE candidate_profile_id <> :cand),
                     't03 a candidate sees only their own applications');
SELECT pg_temp.check((SELECT count(*) = 1 FROM candidate_profile) AND (SELECT count(*) = 1 FROM app_user), 't03 a candidate sees no other candidate or user');
SELECT pg_temp.check((SELECT count(*) > 0 FROM job_requirement) AND (SELECT count(*) = 0 FROM job_requirement WHERE job_status_id <> 2),
                     't03 a candidate sees published open jobs only');
SELECT pg_temp.expect_error('SELECT * FROM user_credential', 'permission denied', 't03 credentials are unreadable by the API role');
SELECT pg_temp.expect_error(format($$INSERT INTO application (job_requirement_id, candidate_profile_id) VALUES (%s, %s)$$, :job_open, :other_cand),
                            'row-level security', 't03 a candidate cannot apply on someone else''s behalf');
SELECT pg_temp.expect_error(format($$UPDATE application SET application_status_id = application_status_id + 1 WHERE id = %s$$, :cand_app), 'can only withdraw',
                            't03 a candidate cannot move their own application forward');
SELECT pg_temp.expect_error($$SELECT auth_register_candidate('someone@mail.test', '$argon2id$v=19$m=65536,t=3,p=4$c2FsdA$aGFzaA', 'Some One')$$,
                            'register themselves', 't03 a signed-in user cannot register a candidate');

-- recruiter of org1
SELECT pg_temp.act_as(:rec1);
SELECT pg_temp.check((SELECT count(*) = 0 FROM job_requirement WHERE id = :draft_other) AND (SELECT count(*) = 0 FROM job_requirement WHERE job_status_id <> 2 AND organisation_id <> :org1),
                     't03 a recruiter cannot see another company''s draft or closed jobs');
WITH u AS (UPDATE job_requirement SET title = 'hijacked' WHERE id = :job_other RETURNING 1)
SELECT pg_temp.check(count(*) = 0, 't03 a recruiter cannot change another company''s job') FROM u;
SELECT pg_temp.check((SELECT count(*) > 0 FROM application) AND (SELECT count(*) = 0 FROM application WHERE organisation_id <> :org1),
                     't03 a recruiter sees only their company''s applications');
SELECT pg_temp.check((SELECT count(*) = 1 FROM candidate_profile WHERE id = :cand) AND (SELECT count(*) = 0 FROM candidate_profile WHERE id = :hidden_cand),
                     't03 a recruiter finds visible candidates, never hidden ones');
SELECT pg_temp.check((SELECT count(*) = 1 FROM app_user), 't03 a recruiter cannot read candidates'' contact details from the user table');
SELECT count(*) AS rls_visible FROM candidate_profile \gset
RESET ROLE;
SELECT pg_temp.check((SELECT count(*) FILTER (WHERE app_can_view_candidate(id)) = :rls_visible FROM candidate_profile),
                     't03 the row-level policy and app_can_view_candidate() agree on what a recruiter sees');
SET LOCAL ROLE v2_app;
SELECT pg_temp.expect_error(format('SELECT * FROM candidate_contact(%s)', :cand), 'download the profile first', 't03 contact details stay hidden until the profile is downloaded');
SELECT billing_download_profile(:cand) AS dl1 \gset
SELECT billing_download_profile(:cand) AS dl2 \gset
SELECT pg_temp.check(:dl1 = :dl2 AND (SELECT balance_credits = :org1_balance - 1 FROM wallet), 't03 a download costs one credit; repeating it within 30 days is free');
SELECT pg_temp.check((SELECT email LIKE 'cand%@mail.test' FROM candidate_contact(:cand)), 't03 after downloading, the recruiter gets the contact details');
SELECT pg_temp.check((SELECT count(*) = 0 FROM audit_event), 't03 a recruiter (no audit permission) cannot read the audit trail');
SELECT pg_temp.expect_error(format($$UPDATE wallet_ledger_entry SET credits = 100 WHERE wallet_id = (SELECT id FROM wallet WHERE organisation_id = %s)$$, :org1),
                            'permission denied', 't03 the API role cannot touch the ledger directly');
SELECT pg_temp.expect_error($$INSERT INTO audit_event (action, entity_table) VALUES ('fake.event', 'x')$$, 'permission denied', 't03 the API role cannot forge audit events');
SELECT pg_temp.expect_error(format('DELETE FROM application WHERE id = %s', :cand_app), 'permission denied', 't03 applications cannot be deleted by the API');
SELECT pg_temp.expect_error(format($$SELECT auth_end_session(%s, 'revoked_by_admin')$$, :rec1_session), 'invalid end reason', 't03 only staff can revoke as admin');

-- blocking: the candidate blocks org1
SELECT pg_temp.act_as(:cand_user);
INSERT INTO candidate_block (candidate_profile_id, blocked_organisation_id) VALUES (:cand, :org1) RETURNING id AS block_id \gset
SELECT pg_temp.act_as(:rec1);
SELECT pg_temp.check((SELECT count(*) = 0 FROM candidate_profile WHERE id = :cand) AND (SELECT count(*) = 0 FROM application WHERE id = :cand_app),
                     't03 after a block, the blocked company sees neither the candidate nor their application');
SELECT pg_temp.expect_error(format('SELECT * FROM candidate_contact(%s)', :cand), 'not available', 't03 a blocked company loses access to downloaded contact details');
SELECT pg_temp.check((SELECT count(*) = 0 FROM candidate_block), 't03 the blocked company cannot see the block itself');
SELECT pg_temp.act_as(:rec2);
SELECT pg_temp.check((SELECT count(*) = 1 FROM candidate_profile WHERE id = :cand), 't03 other companies still see the candidate');
SELECT pg_temp.act_as(:cand_user);
UPDATE candidate_block SET unblocked_at = now() WHERE id = :block_id;
SELECT pg_temp.act_as(:rec1);
SELECT pg_temp.check((SELECT count(*) = 1 FROM candidate_profile WHERE id = :cand), 't03 after unblocking, the company sees the candidate again');

-- account admin of org1: own organisation's audit trail and funnel only
SELECT pg_temp.act_as(:admin1);
SELECT pg_temp.check((SELECT count(*) > 0 FROM audit_event) AND (SELECT count(*) = 0 FROM audit_event WHERE organisation_id IS DISTINCT FROM :org1),
                     't03 an account admin reads only their organisation''s audit trail');
SELECT pg_temp.check((SELECT count(*) > 0 FROM employer_hiring_funnel) AND (SELECT count(*) = 0 FROM employer_hiring_funnel WHERE organisation_id <> :org1),
                     't03 the employer dashboard shows only the own organisation''s funnel');
SELECT pg_temp.check(EXISTS (SELECT 1 FROM audit_event WHERE action = 'candidate_contact.read' AND entity_id = :cand)
                     AND EXISTS (SELECT 1 FROM audit_event WHERE action = 'profile_download.insert'),
                     't03 downloads and contact reads are in the audit trail');

-- staff, consultant, guest
SELECT pg_temp.act_as(:staff);
SELECT pg_temp.check((SELECT count(*) = :all_profiles FROM candidate_profile) AND (SELECT count(*) = 1 FROM job_requirement WHERE id = :draft_other),
                     't03 staff see all profiles and jobs');
SELECT pg_temp.act_as(:consultant);
SELECT pg_temp.check((SELECT count(*) = 0 FROM job_requirement WHERE job_status_id <> 2) AND (SELECT count(*) > 0 FROM candidate_profile),
                     't03 a consultant searches candidates but sees only published jobs');
SELECT pg_temp.expect_error(format('SELECT billing_download_profile(%s)', :cand), 'only organisation members', 't03 a consultant without an organisation cannot download');
SELECT pg_temp.act_as(NULL);
SELECT pg_temp.check((SELECT count(*) > 0 FROM job_requirement) AND (SELECT count(*) = 0 FROM candidate_profile), 't03 a guest browses jobs but no candidates');
SELECT pg_temp.check(auth_register_candidate('new.person@mail.test', '$argon2id$v=19$m=65536,t=3,p=4$c2FsdA$aGFzaA', 'New Person') IS NOT NULL,
                     't03 a guest can register as a candidate');

-- reporting role: aggregates yes, personal data no
RESET ROLE;
SET LOCAL ROLE v2_reporting;
SELECT pg_temp.check((SELECT count(*) > 0 FROM agg_hiring_funnel_monthly), 't03 reporting reads the aggregates');
SELECT pg_temp.expect_error('SELECT * FROM candidate_profile', 'permission denied', 't03 reporting cannot read personal data');
ROLLBACK;
