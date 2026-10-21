-- AP-10 Notification inbox: latest 20
-- as: candidate
SELECT n.id, n.template_key, n.payload, n.queued_at FROM notification n
WHERE n.app_user_id = :cand_user ORDER BY n.queued_at DESC LIMIT 20;
