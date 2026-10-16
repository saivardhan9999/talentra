-- B1 Licences (B68): seat utilisation per plan: licences, seats in use against max_users, and how many
-- licences are full.
SELECT p.code AS plan, count(DISTINCT l.id) AS licences, sum(x.seats) AS seats_in_use, sum(l.max_users) AS seats_sold,
       round(100.0 * sum(x.seats) / sum(l.max_users), 1) AS utilisation_pct, count(*) FILTER (WHERE x.seats = l.max_users) AS full_licences
FROM licence l
JOIN subscription s ON s.id = l.subscription_id
JOIN plan p ON p.id = s.plan_id
CROSS JOIN LATERAL (SELECT count(*) AS seats FROM licence_seat ls WHERE ls.licence_id = l.id AND ls.released_at IS NULL) x
WHERE l.licence_status_id = 1
GROUP BY p.code, p.price_amount
ORDER BY p.price_amount;
