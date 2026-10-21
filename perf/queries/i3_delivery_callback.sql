-- I3 Provider delivery callback (Notifications, B73): a webhook names only the provider message id; find the delivery to update
SELECT id, queued_at, notification_delivery_status_id
FROM notification_delivery
WHERE provider_message_ref = :'delivery_ref';
