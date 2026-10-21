-- I2 Brute-force check at login (Licences, B72): failed attempts for the identifier just typed, in the last 15 minutes; runs on every login
SELECT count(*) AS recent_failures
FROM login_attempt
WHERE attempted_identifier_hmac = decode(:'hmac_failed', 'hex')
  AND login_outcome_id <> 1
  AND attempted_at >= now() - interval '15 minutes';
