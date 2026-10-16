-- Q7 Profile download paid with a credit (transactional; rolled back): one ledger debit and one download event
-- in one transaction; the ledger trigger locks the wallet and computes the new balance.
-- explain: no
BEGIN;
SELECT set_config('app.current_user_id', :'wallet_recruiter', true) \g /dev/null
SELECT credit_balance AS balance_before FROM wallet WHERE id = :wallet;
WITH debit AS (
    INSERT INTO wallet_ledger_entry (wallet_id, wallet_entry_type_id, credit_delta, note) VALUES (:wallet, 2, -1, 'Q7 download') RETURNING id)
INSERT INTO profile_download_event (candidate_profile_id, downloader_user_account_id, downloader_organisation_id, wallet_ledger_entry_id)
SELECT :cand, :wallet_recruiter, :wallet_org, id FROM debit;
SELECT credit_balance AS balance_after FROM wallet WHERE id = :wallet;
ROLLBACK;
