-- B5 Wallet (B68): reconciliation. Every cached wallet balance equals the sum of its ledger, and the latest
-- entry's balance_after equals the balance. Lists the totals and any wallet that disagrees (expected: none).
WITH s AS (
    SELECT w.id, w.credit_balance, coalesce(sum(e.credit_delta), 0) AS ledger_sum,
           (SELECT e2.balance_after FROM wallet_ledger_entry e2 WHERE e2.wallet_id = w.id ORDER BY e2.id DESC LIMIT 1) AS last_balance_after
    FROM wallet w LEFT JOIN wallet_ledger_entry e ON e.wallet_id = w.id
    GROUP BY w.id, w.credit_balance)
SELECT count(*) AS wallets, sum(credit_balance) AS credits_held, sum(ledger_sum) AS ledger_total,
       count(*) FILTER (WHERE credit_balance <> ledger_sum OR credit_balance <> coalesce(last_balance_after, 0)) AS wallets_out_of_balance
FROM s;
