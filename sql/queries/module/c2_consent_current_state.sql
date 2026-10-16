-- C2 Shared items (B69): the current consent state per purpose, from the append-only history (latest record per
-- user and purpose wins), with the number of withdrawals.
SELECT p.code AS purpose, count(*) AS users_with_a_decision, count(*) FILTER (WHERE x.is_granted) AS currently_granted,
       count(*) FILTER (WHERE NOT x.is_granted) AS currently_withdrawn
FROM (SELECT DISTINCT ON (user_account_id, consent_purpose_id) user_account_id, consent_purpose_id, is_granted
      FROM consent_record ORDER BY user_account_id, consent_purpose_id, recorded_at DESC, id DESC) x
JOIN consent_purpose p ON p.id = x.consent_purpose_id
GROUP BY p.code, p.id
ORDER BY p.id;
