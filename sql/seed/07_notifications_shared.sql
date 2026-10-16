-- =============================================================================
-- Talentra seed :: 07_notifications_shared.sql
-- (B64: notification deliveries, community posts, credentials, consent records, audit events, blocks)
-- Distributions:
--   preferences    30% of candidates set language / privacy; 10% switch SMS off for job alerts;
--                  15% keep 1-2 job alerts
--   notifications  500k over 180 days (application updates, job alerts, interview reminders, outreach);
--                  in-app always plus email or SMS for 60%; 90% delivered, 3% failed, rest sent/queued;
--                  60% read in-app; switched-off channels are stored as suppressed by the write-path rule
--   community      20k posts (30% replies) in English, Hindi and Tamil, 0-6 reactions each
--   support        10k tickets, 2-4 messages each, 70% resolved
--   credentials    a password (argon2id format) for every user; 15% also link Google sign-in
--   consent        terms + privacy at registration; marketing email 60% (a tenth later withdrawn)
--   blocks         20k: candidates blocking recruiters (60%) or companies (40%); 10% later unblocked
--   errors         5k system errors across services (plus the gig overlap rejections from 05)
-- Audit events come from the audit triggers on every audited table as the rows are written.
-- =============================================================================
\set ON_ERROR_STOP on
SET app.current_user_id = '1';
SET synchronous_commit = off;

-- ---------------------------------------------------------------- preferences and job alerts
INSERT INTO user_preference (user_account_id, preferred_language_id, is_searchable_by_employers, show_contact_to_employers, allow_recruiter_outreach, allow_profile_download)
SELECT c.user_id, l.id, seed.r(c.g, 201) < 0.95, seed.r(c.g, 202) < 0.30, seed.r(c.g, 203) < 0.85, seed.r(c.g, 204) < 0.90
FROM seed.cand_p c JOIN language l ON l.code = CASE WHEN seed.r(c.g, 205) < 0.5 THEN c.lang ELSE 'en' END
WHERE seed.r(c.g, 200) < 0.30;
INSERT INTO notification_preference (user_account_id, notification_type_id, outreach_channel_id, is_enabled)
SELECT c.user_id, 2, 2, false FROM seed.cand_p c WHERE seed.r(c.g, 206) < 0.10;
INSERT INTO job_alert (candidate_profile_id, name, keywords, city_id, job_role_id, alert_frequency_id, last_sent_at)
SELECT c.profile_id, jr.name || ' jobs', lower(jr.name), c.city_id, jr.id, 1 + floor(seed.r(c.g * 2 + k, 207) * 3)::int,
       now() - interval '3 days' * seed.r(c.g * 2 + k, 208)
FROM seed.cand_p c CROSS JOIN generate_series(1, 2) k
JOIN seed.role_rank jr ON jr.rank = 1 + floor(seed.r(c.g * 2 + k, 209) * (SELECT count(*) FROM seed.role_rank))
WHERE seed.r(c.g, 210) < 0.15 AND (k = 1 OR seed.r(c.g, 211) < 0.4);

-- ---------------------------------------------------------------- notifications and deliveries
CREATE TABLE seed.notif AS
SELECT v AS g, c.user_id, c.profile_id, x.t AS type_id, now() - interval '180 days' * seed.r(v, 213) AS at
FROM generate_series(1, seed.n(500000)) v
JOIN seed.cand_p c ON c.g = 1 + (v * 2711) % (SELECT count(*) FROM seed.cand_p)
CROSS JOIN LATERAL (SELECT CASE WHEN seed.r(v, 212) < 0.55 THEN 1 WHEN seed.r(v, 212) < 0.85 THEN 2 WHEN seed.r(v, 212) < 0.93 THEN 3 ELSE 4 END AS t) x;
INSERT INTO notification (recipient_user_account_id, notification_type_id, template_ref, summary, target_table, target_record_id, read_at, created_at, updated_at)
SELECT n.user_id, n.type_id, (ARRAY['application_status_changed','job_alert_digest','interview_reminder','recruiter_message'])[n.type_id],
       (ARRAY['Your application has moved to the next stage','New jobs matching your alert','Reminder: your interview is tomorrow',
              'A recruiter sent you a message'])[n.type_id],
       CASE WHEN n.type_id IN (1, 3) THEN 'application' END,
       CASE WHEN n.type_id IN (1, 3) THEN (SELECT a.id FROM application a WHERE a.candidate_profile_id = n.profile_id LIMIT 1) END,
       CASE WHEN seed.r(n.g, 214) < 0.60 THEN n.at + interval '2 hours' END, n.at, n.at
FROM seed.notif n;
-- notifications about an application the candidate does not have are general notices instead
UPDATE notification SET target_table = NULL WHERE target_table IS NOT NULL AND target_record_id IS NULL;

INSERT INTO notification_delivery (notification_id, outreach_channel_id, queued_at, created_at, updated_at)
SELECT n.id, ch, n.created_at, n.created_at, n.created_at
FROM notification n CROSS JOIN (VALUES (4), (1), (2)) v(ch)
WHERE ch = 4 OR (ch = 1 AND seed.r(n.id, 215) < 0.40) OR (ch = 2 AND seed.r(n.id, 215) >= 0.40 AND seed.r(n.id, 215) < 0.60);
-- provider callbacks: the status trigger only moves forward and keeps the first reported times
UPDATE notification_delivery SET notification_delivery_status_id = x.st,
       sent_at = queued_at + interval '5 seconds', delivered_at = CASE WHEN x.st IN (3, 4) THEN queued_at + interval '20 seconds' END,
       failed_at = CASE WHEN x.st = 5 THEN queued_at + interval '30 seconds' END,
       failure_code = CASE WHEN x.st = 5 THEN 'DND_REGISTERED' END,
       provider_message_ref = CASE WHEN outreach_channel_id <> 4 THEN 'prov_' || id END
FROM (SELECT id AS did, CASE WHEN seed.r(id, 216) < 0.03 THEN 5 WHEN seed.r(id, 216) < 0.93 THEN 3 WHEN seed.r(id, 216) < 0.98 THEN 2 ELSE 1 END AS st
      FROM notification_delivery) x
WHERE id = x.did AND notification_delivery_status_id = 1 AND x.st > 1;

-- ---------------------------------------------------------------- community
INSERT INTO community_post (author_user_account_id, title, body, body_language_id, published_at, created_by, updated_by, created_at, updated_at)
SELECT c.user_id, t.title, t.body, l.id, at, c.user_id, c.user_id, at, at
FROM generate_series(1, seed.n(14000)) v
JOIN seed.cand_p c ON c.g = 1 + (v * 4447) % (SELECT count(*) FROM seed.cand_p)
CROSS JOIN LATERAL (SELECT now() - interval '400 days' * seed.r(v, 217) AS at) d
CROSS JOIN LATERAL (SELECT * FROM (VALUES
    ('en', 'How do I prepare for a technical interview?', 'I have my first technical round next week for a Java role. Any tips on what to revise?'),
    ('en', 'Is a notice period buyout common?', 'My new employer wants me to join in 30 days but my notice period is 90. How do people handle this?'),
    ('hi', 'डिलीवरी जॉब में कितनी कमाई होती है?', 'मैं दोपहिया डिलीवरी का काम शुरू करना चाहता हूँ। बेंगलुरु में महीने की कमाई कितनी होती है?'),
    ('ta', 'சென்னையில் எலக்ட்ரீஷியன் வேலை', 'ITI முடித்தவர்களுக்கு சென்னையில் நல்ல நிறுவனங்கள் எவை?')) p(lang, title, body)
    OFFSET floor(seed.r(v, 218) * 4)::int LIMIT 1) t
JOIN language l ON l.code = t.lang;
INSERT INTO community_post (author_user_account_id, parent_community_post_id, body, body_language_id, published_at, created_by, updated_by, created_at, updated_at)
SELECT c.user_id, p.id, 'Thanks for asking. In my experience it helps to revise the basics and practise with a friend.', p.body_language_id,
       p.published_at + interval '6 hours', c.user_id, c.user_id, p.published_at + interval '6 hours', p.published_at + interval '6 hours'
FROM community_post p JOIN seed.cand_p c ON c.g = 1 + (p.id * 7333) % (SELECT count(*) FROM seed.cand_p)
WHERE seed.r(p.id, 219) < 0.43;
INSERT INTO community_reaction (community_post_id, user_account_id, reaction_type_id)
SELECT DISTINCT ON (p.id, c.user_id) p.id, c.user_id, 1 + floor(seed.r(p.id * 7 + k, 220) * 4)::int
FROM community_post p CROSS JOIN generate_series(1, 6) k
JOIN seed.cand_p c ON c.g = 1 + (p.id * 911 + k * 37) % (SELECT count(*) FROM seed.cand_p)
WHERE k <= floor(seed.r(p.id, 221) * 7) AND c.user_id <> p.author_user_account_id
ORDER BY p.id, c.user_id;
UPDATE community_post SET community_post_status_id = 2 WHERE seed.r(id, 222) < 0.01;   -- hidden by moderation

-- ---------------------------------------------------------------- support tickets and FAQs
INSERT INTO support_ticket (ticket_number, raised_by_user_account_id, support_ticket_category_id, support_ticket_priority_id, support_ticket_status_id,
                            subject, assigned_to_user_account_id, opened_at, resolved_at, closed_at, created_at, updated_at)
SELECT 'TKT-' || lpad(v::text, 7, '0'), c.user_id, 1 + floor(seed.r(v, 223) * 7)::int, 1 + floor(seed.r(v, 224) * 4)::int,
       CASE WHEN seed.r(v, 225) < 0.40 THEN 5 WHEN seed.r(v, 225) < 0.70 THEN 4 WHEN seed.r(v, 225) < 0.85 THEN 2 WHEN seed.r(v, 225) < 0.92 THEN 3 ELSE 1 END,
       (ARRAY['Cannot upload my resume','Refund for unused credits','Job post stuck in pending approval','Application status not updating',
              'OTP not received','Recruiter is sending spam','Need invoice with GSTIN'])[1 + floor(seed.r(v, 223) * 7)::int],
       CASE WHEN seed.r(v, 225) >= 0.92 THEN NULL ELSE (SELECT user_id FROM seed.platform_person WHERE kind = 'admin' ORDER BY g OFFSET (v % 3) + 1 LIMIT 1) END,
       o.at, CASE WHEN seed.r(v, 225) < 0.70 THEN o.at + interval '30 hours' * seed.r(v, 226) END,
       CASE WHEN seed.r(v, 225) < 0.40 THEN o.at + interval '3 days' END, o.at, o.at
FROM generate_series(1, seed.n(10000)) v
JOIN seed.cand_p c ON c.g = 1 + (v * 6271) % (SELECT count(*) FROM seed.cand_p)
CROSS JOIN LATERAL (SELECT now() - interval '300 days' * seed.r(v, 227) - interval '4 days' AS at) o;
INSERT INTO support_ticket_message (support_ticket_id, author_user_account_id, body, is_internal_note, created_at, created_by)
SELECT t.id, CASE WHEN k % 2 = 1 OR t.assigned_to_user_account_id IS NULL THEN t.raised_by_user_account_id ELSE t.assigned_to_user_account_id END,
       CASE WHEN k = 1 THEN 'Please help: ' || lower(t.subject) || '.' WHEN k % 2 = 0 THEN 'We are looking into this and will update you shortly.'
            ELSE 'Thank you, that worked.' END,
       k = 4 AND t.assigned_to_user_account_id IS NOT NULL, t.opened_at + interval '3 hours' * k,
       CASE WHEN k % 2 = 1 OR t.assigned_to_user_account_id IS NULL THEN t.raised_by_user_account_id ELSE t.assigned_to_user_account_id END
FROM support_ticket t CROSS JOIN generate_series(1, 4) k WHERE k <= 2 + floor(seed.r(t.id, 228) * 3);

DO $$
DECLARE r record; q bigint; a bigint; n int := 0;
BEGIN
    FOR r IN SELECT * FROM (VALUES
        ('candidates','How do I make my profile visible only to verified employers?','Open Privacy settings and choose "Employers only".'),
        ('candidates','Can I block a company from seeing my profile?','Yes. Open the company page and choose Block. Its recruiters will no longer see your profile.'),
        ('candidates','Why was my application rejected?','Employers may share a reason; it appears on the application card when they do.'),
        ('employers','How many recruiters can use my licence?','Each licence states the number of users and devices per user; see Licences and seats.'),
        ('employers','How are profile download credits charged?','One credit per download unless your plan includes downloads for the period.'),
        ('consultants','Which requirements can I source for?','Only requirements the employer has opened to consultants.'),
        ('billing','Can I get a GST invoice?','Every paid order has an invoice with your GSTIN; download it from Billing.'),
        ('gig','How do I get paid for a gig?','Earnings are reconciled by the fulfilment partner and shown under Earnings.')) v(cat, qtext, atext) LOOP
        n := n + 1; q := NULL; a := NULL;
        CALL seed_label('faq.' || n || '.question', 'notifications', q); CALL seed_translation('faq.' || n || '.question', 'en', r.qtext);
        CALL seed_label('faq.' || n || '.answer', 'notifications', a);   CALL seed_translation('faq.' || n || '.answer', 'en', r.atext);
        INSERT INTO faq (faq_category_id, question_label_key_id, answer_label_key_id, sort_order) VALUES (seed.id('faq_category', r.cat), q, a, n);
    END LOOP;
    CALL seed_translation('faq.2.question', 'hi', 'क्या मैं किसी कंपनी को अपनी प्रोफ़ाइल देखने से रोक सकता हूँ?');
    CALL seed_translation('faq.2.question', 'ta', 'ஒரு நிறுவனம் என் சுயவிவரத்தைப் பார்ப்பதைத் தடுக்க முடியுமா?');
END $$;

INSERT INTO referral_event (referral_id, referral_event_type_id, application_id, occurred_at)
SELECT r.id, e, CASE WHEN e IN (3, 4) THEN (SELECT a.id FROM application a WHERE a.candidate_profile_id = r.referred_candidate_profile_id
                                                                        AND a.job_requirement_id = r.job_requirement_id) END,
       r.referred_at + interval '2 days' * (e - 1)
FROM referral r CROSS JOIN generate_series(1, 4) e
WHERE e <= CASE r.referral_status_id WHEN 1 THEN 1 WHEN 2 THEN 2 WHEN 3 THEN 3 WHEN 4 THEN 4 ELSE 1 END;

-- ---------------------------------------------------------------- credentials, consent, blocks, errors
INSERT INTO user_credential (user_account_id, credential_type_id, password_hash, last_used_at, created_at, updated_at)
SELECT u.id, 1, '$argon2id$v=19$m=65536,t=3,p=4$' || rtrim(encode(substr(seed.hmac('salt' || u.id), 1, 16), 'base64'), '=')
                || '$' || rtrim(encode(seed.hmac('pw' || u.id), 'base64'), '='),
       now() - interval '30 days' * seed.r(u.id, 229), u.created_at, u.created_at
FROM user_account u WHERE u.id <> 1;
INSERT INTO user_credential (user_account_id, credential_type_id, provider_subject_hmac, last_used_at, created_at, updated_at)
SELECT c.user_id, 2, seed.hmac('google:' || c.user_id), now() - interval '10 days' * seed.r(c.g, 230), c.registered_at, c.registered_at
FROM seed.cand_p c WHERE seed.r(c.g, 231) < 0.15;

INSERT INTO consent_record (user_account_id, consent_purpose_id, policy_version, is_granted, recorded_at, source_ip, created_at)
SELECT c.user_id, p, '2024.2', true, c.registered_at, '49.36.0.1', c.registered_at FROM seed.cand_p c CROSS JOIN (VALUES (1), (2)) v(p);
INSERT INTO consent_record (user_account_id, consent_purpose_id, policy_version, is_granted, recorded_at, source_ip, created_at)
SELECT c.user_id, 3, '2024.2', true, c.registered_at, '49.36.0.1', c.registered_at FROM seed.cand_p c WHERE seed.r(c.g, 232) < 0.60;
INSERT INTO consent_record (user_account_id, consent_purpose_id, policy_version, is_granted, recorded_at, source_ip, created_at)
SELECT c.user_id, 3, '2024.2', false, c.registered_at + interval '90 days', '49.36.0.1', c.registered_at + interval '90 days'
FROM seed.cand_p c WHERE seed.r(c.g, 232) < 0.06;

INSERT INTO block_entry (blocker_user_account_id, blocked_user_account_id, blocked_organisation_id, block_reason_id, blocked_at, unblocked_at, created_by, updated_by)
SELECT DISTINCT ON (c.user_id, coalesce(p.user_id, -p.org_id))
       c.user_id, CASE WHEN x.by_user THEN p.user_id END, CASE WHEN NOT x.by_user THEN p.org_id END, 1 + floor(seed.r(v, 233) * 5)::int,
       x.blocked_at, CASE WHEN seed.r(v, 235) < 0.10 THEN x.blocked_at + (now() - x.blocked_at) / 2 END,   -- unblocked after it was blocked
       c.user_id, c.user_id
FROM generate_series(1, seed.n(20000)) v
JOIN seed.cand_p c ON c.g = 1 + (v * 3571) % (SELECT count(*) FROM seed.cand_p)
JOIN seed.org_person p ON p.org_id = (SELECT org_id FROM seed.org WHERE seed.org.g = seed.skew((SELECT count(*) FROM seed.org), v, 236, 1.5)) AND p.k = 2
CROSS JOIN LATERAL (SELECT seed.r(v, 237) < 0.60 AS by_user, now() - interval '200 days' * seed.r(v, 234) AS blocked_at) x
ORDER BY c.user_id, coalesce(p.user_id, -p.org_id), v;

INSERT INTO system_error_event (error_severity_id, source_component, error_code, message, correlation_ref, occurred_at)
SELECT 1 + floor(seed.r(v, 238) * 3)::int,
       (ARRAY['payment-gateway-webhook','sms-provider','resume-parser','search-indexer','gst-verification'])[1 + floor(seed.r(v, 239) * 5)::int],
       (ARRAY['timeout','http_502','parse_failed','index_lag','lookup_unavailable'])[1 + floor(seed.r(v, 239) * 5)::int],
       'Upstream call failed after 3 retries; message queued for retry', 'req-' || md5(v::text), now() - interval '180 days' * seed.r(v, 240)
FROM generate_series(1, seed.n(5000)) v;

DO $$
BEGIN
    PERFORM seed.done('notifications: preferences + job alerts',
        (SELECT count(*) FROM user_preference) + (SELECT count(*) FROM notification_preference) + (SELECT count(*) FROM job_alert));
    PERFORM seed.done('notifications: notifications', (SELECT count(*) FROM notification));
    PERFORM seed.done('notifications: deliveries', (SELECT count(*) FROM notification_delivery));
    PERFORM seed.done('notifications: suppressed by preference', (SELECT count(*) FROM notification_delivery WHERE notification_delivery_status_id = 6));
    PERFORM seed.done('community: posts + reactions', (SELECT count(*) FROM community_post) + (SELECT count(*) FROM community_reaction));
    PERFORM seed.done('support: tickets + messages', (SELECT count(*) FROM support_ticket) + (SELECT count(*) FROM support_ticket_message));
    PERFORM seed.done('support: FAQs', (SELECT count(*) FROM faq));
    PERFORM seed.done('referrals: events', (SELECT count(*) FROM referral_event));
    PERFORM seed.done('shared: credentials', (SELECT count(*) FROM user_credential));
    PERFORM seed.done('shared: consent records', (SELECT count(*) FROM consent_record));
    PERFORM seed.done('shared: block entries', (SELECT count(*) FROM block_entry));
    PERFORM seed.done('shared: system errors', (SELECT count(*) FROM system_error_event));
    PERFORM seed.done('shared: audit events (from triggers)', (SELECT count(*) FROM audit_event));
END $$;
