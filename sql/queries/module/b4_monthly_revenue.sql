-- B4 Subscriptions and payments (B68): revenue per month over the last 12 months: subscriptions and wallet
-- recharges paid, refunds, net.
SELECT date_trunc('month', o.paid_at)::date AS month,
       sum(o.order_amount) FILTER (WHERE o.payment_purpose_id = 1) AS subscriptions_inr,
       sum(o.order_amount) FILTER (WHERE o.payment_purpose_id = 2) AS recharges_inr,
       coalesce(sum(f.refunded), 0) AS refunds_inr,
       sum(o.order_amount) - coalesce(sum(f.refunded), 0) AS net_inr
FROM payment_order o
LEFT JOIN LATERAL (SELECT sum(refund_amount) AS refunded FROM refund r WHERE r.payment_order_id = o.id AND r.refund_status_id = 3) f ON true
WHERE o.payment_order_status_id IN (3, 6, 7) AND o.paid_at >= date_trunc('month', now()) - interval '12 months'
GROUP BY 1
ORDER BY 1;
