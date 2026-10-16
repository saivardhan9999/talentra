-- C1 Notifications (B69): delivery rate per channel, including deliveries suppressed by the recipient's
-- preferences on the write path.
SELECT c.code AS channel, count(*) AS deliveries,
       round(100.0 * count(*) FILTER (WHERE d.notification_delivery_status_id IN (3, 4)) / count(*), 1) AS delivered_pct,
       count(*) FILTER (WHERE d.notification_delivery_status_id = 5) AS failed,
       count(*) FILTER (WHERE d.notification_delivery_status_id = 6) AS suppressed_by_preference
FROM notification_delivery d
JOIN outreach_channel c ON c.id = d.outreach_channel_id
GROUP BY c.code
ORDER BY deliveries DESC;
