-- AP-13 Notification worker claims a batch of 100 (write)
-- as: worker
SELECT count(*) FROM notification_claim(100);
