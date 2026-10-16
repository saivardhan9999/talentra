-- Q13 Profile download history for one candidate (rule group 10): who downloaded the profile, when, for which
-- organisation, and the credit deduction that paid for it.
SELECT d.downloaded_at, u.email AS downloaded_by, o.legal_name AS organisation, e.id AS ledger_entry, e.credit_delta, e.balance_after
FROM profile_download_event d
JOIN user_account u ON u.id = d.downloader_user_account_id
LEFT JOIN organisation o ON o.id = d.downloader_organisation_id
LEFT JOIN wallet_ledger_entry e ON e.id = d.wallet_ledger_entry_id
WHERE d.candidate_profile_id = :cand_downloaded
ORDER BY d.downloaded_at DESC;
