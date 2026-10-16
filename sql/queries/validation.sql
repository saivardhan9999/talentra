-- Seed validation (M20, B66): the seeded data checked against the data standards in docket Section 5 and the
-- design rules. kind = rule: must be 0 violations. kind = finding: a data-quality issue the dataset carries on
-- purpose (as real migrated data would); it must be detected and is recorded in the validation report.
WITH
hist AS (
    SELECT h.application_id, h.from_application_status_id AS f, h.to_application_status_id AS t, h.changed_at,
           lag(h.to_application_status_id) OVER w AS prev_to, lag(h.changed_at) OVER w AS prev_at,
           row_number() OVER w AS step, count(*) OVER (PARTITION BY h.application_id) AS steps
    FROM application_status_history h
    WINDOW w AS (PARTITION BY h.application_id ORDER BY h.changed_at, h.id)),
ledger AS (
    SELECT e.wallet_id, e.balance_after, sum(e.credit_delta) OVER (PARTITION BY e.wallet_id ORDER BY e.id) AS running
    FROM wallet_ledger_entry e)
SELECT * FROM (VALUES
-- rule group 2: keys, limits and concurrency
('2', 'rule', 'licences with more live seats than max_users',
 (SELECT count(*) FROM licence l WHERE (SELECT count(*) FROM licence_seat s WHERE s.licence_id = l.id AND s.released_at IS NULL) > l.max_users)),
('2', 'rule', 'seats with more live sessions than max_devices_per_user',
 (SELECT count(*) FROM licence_seat s JOIN licence l ON l.id = s.licence_id
  WHERE (SELECT count(*) FROM user_session u WHERE u.licence_seat_id = s.id AND u.ended_at IS NULL AND u.expires_at > now()) > l.max_devices_per_user)),
('2', 'rule', 'consumption ledger entries paying for more than one download / view / outreach',
 (SELECT count(*) FROM (SELECT wallet_ledger_entry_id FROM (
                            SELECT wallet_ledger_entry_id FROM profile_download_event WHERE wallet_ledger_entry_id IS NOT NULL
                            UNION ALL SELECT wallet_ledger_entry_id FROM profile_view_event WHERE wallet_ledger_entry_id IS NOT NULL
                            UNION ALL SELECT wallet_ledger_entry_id FROM outreach_batch WHERE wallet_ledger_entry_id IS NOT NULL) x
                        GROUP BY wallet_ledger_entry_id HAVING count(*) > 1) d)),
-- rule group 3: standard domains, checked on the data
('3', 'rule', 'account emails not lowercase or not an address', (SELECT count(*) FROM user_account WHERE email <> lower(email) OR email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$')),
('3', 'rule', 'phone numbers not in E.164', (SELECT count(*) FROM candidate_phone WHERE phone_e164 !~ '^\+[1-9][0-9]{7,14}$')),
('3', 'rule', 'person names blank or longer than 150 characters', (SELECT count(*) FROM candidate_profile WHERE btrim(full_name) = '' OR length(full_name) > 150)),
('3', 'rule', 'salary amounts without a currency', (SELECT count(*) FROM candidate_profile WHERE current_salary_amount IS NOT NULL AND current_salary_currency_id IS NULL)
                                                + (SELECT count(*) FROM job_requirement WHERE salary_min_amount IS NOT NULL AND salary_currency_id IS NULL)),
('3', 'rule', 'cities with incomplete or out-of-range coordinates',
 (SELECT count(*) FROM city WHERE (latitude IS NULL) <> (longitude IS NULL) OR latitude NOT BETWEEN -90 AND 90 OR longitude NOT BETWEEN -180 AND 180)),
('3', 'rule', 'tax identifiers stored in clear (only token, HMAC and masked form allowed)',
 (SELECT count(*) FROM organisation_registration_identifier WHERE identifier_masked !~ 'X' OR octet_length(identifier_hmac) <> 32)),
('3', 'rule', 'credentials not in argon2id / HMAC form',
 (SELECT count(*) FROM user_credential WHERE password_hash !~ '^\$argon2id\$' OR octet_length(provider_subject_hmac) <> 32)),
-- rule group 4: lifecycle
('4', 'rule', 'soft-deleted profiles visible through v_candidate_profile', (SELECT count(*) FROM v_candidate_profile WHERE deleted_at IS NOT NULL)),
('4', 'rule', 'business tables rows without created_by', (SELECT count(*) FROM application WHERE created_by IS NULL) + (SELECT count(*) FROM candidate_profile WHERE created_by IS NULL)),
-- rule group 5: unknown values and sentinels
('5', 'rule', 'empty-string or "NA" sentinels in optional text',
 (SELECT count(*) FROM candidate_profile WHERE btrim(coalesce(headline, 'x')) IN ('', 'NA', 'N/A') OR btrim(coalesce(given_name, 'x')) IN ('', 'NA', 'N/A'))
 + (SELECT count(*) FROM organisation WHERE btrim(coalesce(trade_name, 'x')) IN ('', 'NA', 'N/A'))),
('5', 'rule', 'zero salary used to mean "not disclosed"', (SELECT count(*) FROM candidate_profile WHERE current_salary_amount = 0 OR expected_salary_amount = 0)),
-- application pipeline: every seeded history is a legal path ending at the current status
('pipeline', 'rule', 'history steps that are not an allowed transition',
 (SELECT count(*) FROM hist WHERE step > 1 AND NOT EXISTS (SELECT 1 FROM application_status_transition x WHERE x.from_application_status_id = hist.prev_to AND x.to_application_status_id = hist.t))),
('pipeline', 'rule', 'histories not starting from nothing into an initial status',
 (SELECT count(*) FROM hist JOIN application_status s ON s.id = hist.t WHERE step = 1 AND (hist.f IS NOT NULL OR NOT s.is_initial))),
('pipeline', 'rule', 'history steps whose from-status is not the previous step',
 (SELECT count(*) FROM hist WHERE step > 1 AND hist.f IS DISTINCT FROM hist.prev_to)),
('pipeline', 'rule', 'applications whose last history step is not their current status',
 (SELECT count(*) FROM hist JOIN application a ON a.id = hist.application_id WHERE step = steps AND hist.t <> a.application_status_id)),
-- temporal consistency
('time', 'rule', 'applications before the candidate registered or the requirement was published',
 (SELECT count(*) FROM application a JOIN candidate_profile p ON p.id = a.candidate_profile_id JOIN job_requirement r ON r.id = a.job_requirement_id
  WHERE a.applied_at < p.created_at OR a.applied_at < r.published_at)),
('time', 'rule', 'offers before their application, placements before their offer',
 (SELECT count(*) FROM offer o JOIN application a ON a.id = o.application_id WHERE o.offered_at < a.applied_at)
 + (SELECT count(*) FROM placement pl JOIN offer o ON o.id = pl.offer_id WHERE pl.joined_on < o.offered_at::date)),
('time', 'rule', 'events in the future', (SELECT count(*) FROM application WHERE applied_at > now()) + (SELECT count(*) FROM application_status_history WHERE changed_at > now())),
-- money and history (rule group 10)
('10', 'rule', 'wallets whose balance is not the sum of their ledger', (SELECT count(*) FROM wallet w WHERE w.credit_balance <> (SELECT coalesce(sum(credit_delta), 0) FROM wallet_ledger_entry e WHERE e.wallet_id = w.id))),
('10', 'rule', 'ledger entries whose balance_after breaks the running sum', (SELECT count(*) FROM ledger WHERE balance_after <> running)),
('10', 'rule', 'invoices not equal to their paid order', (SELECT count(*) FROM invoice i JOIN payment_order o ON o.id = i.payment_order_id WHERE i.total_amount <> o.order_amount)),
-- analytics
('analytics', 'rule', 'fact_application rows differing from application', (SELECT abs((SELECT count(*) FROM application) - (SELECT count(*) FROM fact_application)))),
('analytics', 'rule', 'facts attached to a dimension version not valid at the event',
 (SELECT count(*) FROM fact_application f JOIN dim_organisation d ON d.id = f.dim_organisation_id JOIN application a ON a.id = f.application_id
  WHERE NOT tstzrange(d.valid_from, d.valid_to) @> a.applied_at)),
-- findings: issues the data carries on purpose; each must be detected
('quality', 'finding', 'duplicate registrations not yet flagged (same phone and name)',
 (SELECT count(*) FROM (SELECT 1 FROM candidate_phone ph JOIN candidate_profile p ON p.id = ph.candidate_profile_id WHERE ph.is_primary
                        GROUP BY ph.phone_e164, lower(btrim(p.full_name)) HAVING count(*) > 1 AND bool_and(p.duplicate_of_candidate_profile_id IS NULL)) d)),
('quality', 'finding', 'names with stray whitespace (import defect)', (SELECT count(*) FROM candidate_profile WHERE full_name <> btrim(full_name) OR full_name ~ '\s{2,}')),
('quality', 'finding', 'single-word names (no family name; valid, but breaks naive first/last parsing)', (SELECT count(*) FROM candidate_profile WHERE family_name IS NULL)),
('quality', 'finding', 'joined applications without a placement (requirement had no open position left)',
 (SELECT count(*) FROM application a WHERE a.application_status_id = 8 AND NOT EXISTS (SELECT 1 FROM placement p WHERE p.application_id = a.id))),
('quality', 'finding', 'applications received after the requirement stopped accepting (late applications)',
 (SELECT count(*) FROM application a JOIN job_requirement r ON r.id = a.job_requirement_id WHERE r.expires_at IS NOT NULL AND a.applied_at > r.expires_at)),
('quality', 'finding', 'profiles imported from legacy systems (legacy reference kept)', (SELECT count(*) FROM candidate_profile WHERE legacy_record_ref IS NOT NULL)),
('quality', 'finding', 'unverified primary phone numbers', (SELECT count(*) FROM candidate_phone WHERE is_primary AND verified_at IS NULL))
) v(rule_group, kind, check_name, violations)
ORDER BY CASE kind WHEN 'rule' THEN 0 ELSE 1 END, rule_group, check_name;
