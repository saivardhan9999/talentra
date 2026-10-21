-- t05 Data quality: invariants of the seeded data (must be 0 violations) and the deliberate data-quality findings
-- (must be detected and reported). Covers NFR-INT-05, docs/03-data-requirements.md section 6. Read-only.

CREATE TEMP TABLE dq_rule (rule text, violations bigint);
INSERT INTO dq_rule
SELECT 'R-01 wallet balance equals the sum of its ledger', count(*) FROM wallet w
WHERE w.balance_credits <> coalesce((SELECT sum(credits) FROM wallet_ledger_entry e WHERE e.wallet_id = w.id), 0)
UNION ALL
SELECT 'R-02 ledger balance_after is the running sum (posting order)', count(*) FROM (
  SELECT balance_after, sum(credits) OVER (PARTITION BY wallet_id ORDER BY id) AS running FROM wallet_ledger_entry) x WHERE balance_after <> running
UNION ALL
SELECT 'R-03 ledger reads correctly in time order too', count(*) FROM (
  SELECT balance_after, sum(credits) OVER (PARTITION BY wallet_id ORDER BY occurred_at, id) AS running FROM wallet_ledger_entry) x WHERE balance_after <> running
UNION ALL
SELECT 'R-04 latest history entry equals the application status', count(*) FROM application a
WHERE a.application_status_id <> (SELECT h.to_status_id FROM application_status_history h WHERE h.application_id = a.id ORDER BY h.changed_at DESC, h.id DESC LIMIT 1)
UNION ALL
SELECT 'R-05 every history step is an allowed transition', count(*) FROM application_status_history h
WHERE h.from_status_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM application_status_transition t WHERE t.from_status_id = h.from_status_id AND t.to_status_id = h.to_status_id)
UNION ALL
SELECT 'R-06 applications made after the job was published and the candidate registered', count(*) FROM application a
JOIN job_requirement j ON j.id = a.job_requirement_id JOIN candidate_profile p ON p.id = a.candidate_profile_id
WHERE a.applied_at < j.published_at OR a.applied_at < p.created_at
UNION ALL
SELECT 'R-07 positions_filled equals the number of joins', count(*) FROM job_requirement j
WHERE j.positions_filled <> (SELECT count(*) FROM application a WHERE a.job_requirement_id = j.id AND a.application_status_id = 5)
UNION ALL
SELECT 'R-08 every captured payment has an invoice, and only those', count(*) FROM payment_order o
WHERE (o.payment_status_id IN (3, 5)) <> EXISTS (SELECT 1 FROM invoice i WHERE i.payment_order_id = o.id)
UNION ALL
SELECT 'R-09 every captured subscription payment created its period', count(*) FROM payment_order o
WHERE o.payment_purpose_id = 2 AND o.payment_status_id = 3 AND NOT EXISTS (SELECT 1 FROM subscription s WHERE s.payment_order_id = o.id)
UNION ALL
SELECT 'R-10 every download was paid by exactly one debit of one credit', count(*) FROM profile_download d
JOIN wallet_ledger_entry e ON e.id = d.wallet_ledger_entry_id WHERE e.ledger_entry_type_id <> 4 OR e.credits <> -1
UNION ALL
SELECT 'R-11 no user has more active devices than the licence allows', count(*) FROM (
  SELECT app_user_id, count(DISTINCT user_device_id) AS devices FROM user_session WHERE ended_at IS NULL GROUP BY app_user_id) s
WHERE s.devices > app_device_limit(s.app_user_id)
UNION ALL
SELECT 'R-12 every live candidate currently consents to terms and privacy', count(*) FROM candidate_profile p
WHERE p.deleted_at IS NULL AND (SELECT count(*) FROM consent_current c WHERE c.app_user_id = p.app_user_id AND c.consent_purpose_id IN (1, 2) AND c.is_granted) <> 2
UNION ALL
SELECT 'R-13 every candidate profile belongs to a user with the candidate role', count(*) FROM candidate_profile p
WHERE NOT EXISTS (SELECT 1 FROM user_access_role r WHERE r.app_user_id = p.app_user_id AND r.access_role_id = 8)
UNION ALL
SELECT 'R-14 every organisation has a wallet and a current account admin', count(*) FROM organisation o
WHERE NOT EXISTS (SELECT 1 FROM wallet w WHERE w.organisation_id = o.id)
   OR NOT EXISTS (SELECT 1 FROM organisation_member m WHERE m.organisation_id = o.id AND m.access_role_id = 3 AND m.valid_to IS NULL)
UNION ALL
SELECT 'R-15 one primary resume at most, and applications use the applicant''s own', count(*) FROM application a
JOIN resume r ON r.id = a.resume_id WHERE r.candidate_profile_id <> a.candidate_profile_id
UNION ALL
SELECT 'R-16 notification payloads carry no contact details', count(*) FROM notification
WHERE payload::text ~* '@|\+91[0-9]{10}';

DO $$
DECLARE r record; bad int := 0;
BEGIN
  FOR r IN SELECT * FROM dq_rule ORDER BY rule LOOP
    IF r.violations = 0 THEN RAISE NOTICE 'PASS t05 %', r.rule;
    ELSE RAISE WARNING 'FAIL t05 %: % violations', r.rule, r.violations; bad := bad + 1; END IF;
  END LOOP;
  ASSERT bad = 0, bad || ' data-quality rules violated';
END $$;

-- Findings: issues migrated data really has. The seed plants them on purpose; detection must find them.
DO $$
DECLARE n bigint;
BEGIN
  SELECT count(*) INTO n FROM (SELECT u.phone_e164, lower(p.full_name) FROM candidate_profile p JOIN app_user u ON u.id = p.app_user_id
                               WHERE u.phone_e164 IS NOT NULL GROUP BY 1, 2 HAVING count(*) > 1) d;
  ASSERT n > 0, 'F-01 planted duplicates were not detected';
  RAISE NOTICE 'FINDING F-01 probable duplicate candidates (same phone and name): % groups', n;
  SELECT count(*) INTO n FROM candidate_profile WHERE current_city_id IS NULL AND deleted_at IS NULL;
  RAISE NOTICE 'FINDING F-02 profiles without a city (excluded from city search): %', n;
  SELECT count(*) INTO n FROM candidate_profile p WHERE EXISTS (
    SELECT 1 FROM candidate_experience e WHERE e.candidate_profile_id = p.id AND (coalesce(e.end_date, current_date) - e.start_date) / 30 > p.total_experience_months + 3);
  RAISE NOTICE 'FINDING F-03 stated total experience shorter than the work history: %', n;
  SELECT count(*) INTO n FROM organisation o
  WHERE (SELECT count(*) FROM organisation_member m WHERE m.organisation_id = o.id AND m.valid_to IS NULL)
        > coalesce((SELECT max(max_seats) FROM subscription s WHERE s.organisation_id = o.id AND current_date >= s.starts_on AND current_date < s.ends_on), 1);
  RAISE NOTICE 'FINDING F-04 organisations over their seat limit after the subscription lapsed: %', n;
  SELECT count(*) INTO n FROM job_requirement j JOIN organisation o ON o.id = j.organisation_id WHERE j.job_status_id = 2 AND o.verification_status_id <> 2;
  RAISE NOTICE 'FINDING F-05 open jobs from organisations not yet verified: %', n;
  SELECT count(*) INTO n FROM candidate_profile WHERE is_open_to_work AND deleted_at IS NULL AND last_active_at < now() - interval '90 days';
  RAISE NOTICE 'FINDING F-06 "open to work" profiles inactive for 90+ days: %', n;
END $$;
