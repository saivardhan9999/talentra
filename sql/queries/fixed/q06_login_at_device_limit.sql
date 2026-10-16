-- Q6 Login at the device limit (transactional; rolled back): a seat holder whose live sessions already fill the
-- licence's device limit logs in again; the login is refused and recorded in the login history and the audit trail.
-- explain: no
BEGIN;
SELECT app_open_session(:user_at_limit, :device_at_limit, '\x01'::bytea, '\x02'::bytea, now() + interval '8 hours') AS session_id;
SELECT o.code AS outcome, count(*) AS attempts
FROM login_attempt la JOIN login_outcome o ON o.id = la.login_outcome_id
WHERE la.user_account_id = :user_at_limit AND la.attempted_at = now()
GROUP BY o.code;
SELECT a.detail AS audit_detail FROM audit_event a WHERE a.created_by = :user_at_limit AND a.occurred_at = now();
ROLLBACK;
