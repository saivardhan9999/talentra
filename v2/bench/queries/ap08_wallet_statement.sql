-- AP-08 Wallet statement: last 50 entries
-- as: admin
SELECT e.occurred_at, t.code AS entry_type, e.credits, e.balance_after
FROM wallet_ledger_entry e JOIN ledger_entry_type t ON t.id = e.ledger_entry_type_id
WHERE e.wallet_id = (SELECT id FROM wallet WHERE organisation_id = :busy_org) ORDER BY e.occurred_at DESC LIMIT 50;
