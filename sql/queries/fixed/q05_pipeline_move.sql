-- Q5 Move an application forward (transactional; rolled back): the employer shortlists an applied application;
-- the pipeline trigger checks the transition and writes the history row in the same transaction.
-- explain: no
BEGIN;
SELECT set_config('app.current_user_id', :'recruiter', true) \g /dev/null
UPDATE application SET application_status_id = 3 WHERE id = :app_applied;
SELECT h.from_application_status_id AS from_status, h.to_application_status_id AS to_status, h.changed_at = now() AS written_now
FROM application_status_history h WHERE h.application_id = :app_applied ORDER BY h.changed_at;
ROLLBACK;
