-- =============================================================================
-- Talentra seed :: 09_analytics.sql  (B64: analytics layer)
-- A full initial load of the marts from the transactional tables (what the scheduled
-- load job does on its first run), then the aggregate refresh rule (M18).
-- Facts attach the dimension version valid when the event happened (SCD type 2):
-- 5% of organisations get an earlier "pending verification" version to exercise it.
-- =============================================================================
\set ON_ERROR_STOP on
SET app.current_user_id = '1';
SET synchronous_commit = off;
ANALYZE;

CREATE FUNCTION seed.dk(p_at timestamptz) RETURNS bigint LANGUAGE sql IMMUTABLE AS $$ SELECT to_char(p_at AT TIME ZONE 'Asia/Kolkata', 'YYYYMMDD')::bigint $$;
CREATE FUNCTION seed.dk(p_at date) RETURNS bigint LANGUAGE sql IMMUTABLE AS $$ SELECT to_char(p_at, 'YYYYMMDD')::bigint $$;

-- ---------------------------------------------------------------- dimensions
INSERT INTO dim_location (city_id, city_name, state_name, country_code)
SELECT c.id, c.name, coalesce(s.name, 'Unknown'), co.iso_alpha2 FROM city c LEFT JOIN state s ON s.id = c.state_id JOIN country co ON co.id = c.country_id;

WITH o AS (
    SELECT x.*, coalesce(x.trade_name, x.legal_name) AS dname, coalesce(ot.code, 'direct_employer') AS tcode, i.code AS icode, sb.code AS scode,
           vs.code AS vcode, dl.id AS loc
    FROM organisation x
    LEFT JOIN organisation_type ot ON ot.id = x.organisation_type_id LEFT JOIN industry i ON i.id = x.industry_id
    LEFT JOIN company_size_band sb ON sb.id = x.company_size_band_id JOIN verification_status vs ON vs.id = x.verification_status_id
    LEFT JOIN organisation_location hq ON hq.organisation_id = x.id AND hq.is_headquarters LEFT JOIN dim_location dl ON dl.city_id = hq.city_id)
INSERT INTO dim_organisation (organisation_id, display_name, organisation_type_code, industry_code, company_size_band_code, verification_status_code,
                              hq_dim_location_id, valid_from, valid_to, is_current)
SELECT id, dname, tcode, icode, scode, 'pending', loc, created_at, created_at + interval '30 days', false FROM o WHERE id % 20 = 0
UNION ALL
SELECT id, dname, tcode, icode, scode, vcode, loc, CASE WHEN id % 20 = 0 THEN created_at + interval '30 days' ELSE created_at END, NULL, true FROM o;

INSERT INTO dim_candidate (candidate_profile_id, dim_location_id, experience_band_code, highest_qualification_code, is_fresher, profile_completion_pct,
                           registered_date_id, valid_from, is_current)
SELECT p.id, dl.id,
       CASE WHEN coalesce(p.total_experience_months, 0) < 12 THEN '0_1' WHEN p.total_experience_months < 36 THEN '1_3'
            WHEN p.total_experience_months < 60 THEN '3_5' WHEN p.total_experience_months < 120 THEN '5_10' ELSE '10_plus' END,
       q.code, p.is_fresher, p.profile_completion_pct, seed.dk(p.created_at), p.created_at, true
FROM candidate_profile p LEFT JOIN dim_location dl ON dl.city_id = p.current_city_id
LEFT JOIN candidate_education e ON e.candidate_profile_id = p.id AND e.is_highest LEFT JOIN qualification q ON q.id = e.qualification_id;

INSERT INTO dim_job_requirement (job_requirement_id, dim_organisation_id, dim_location_id, job_role_code, industry_code, employment_type_code, work_mode_code,
                                 salary_band_code, is_open_to_consultants)
SELECT r.id, d.id, dl.id, jr.code, i.code, et.code, wm.code,
       CASE WHEN r.salary_min_amount IS NULL THEN NULL WHEN r.salary_min_amount < 300000 THEN 'lt_3l' WHEN r.salary_min_amount < 600000 THEN '3_6l'
            WHEN r.salary_min_amount < 1200000 THEN '6_12l' WHEN r.salary_min_amount < 2500000 THEN '12_25l' ELSE '25l_plus' END,
       r.is_open_to_consultants
FROM job_requirement r
JOIN dim_organisation d ON d.organisation_id = r.organisation_id AND d.is_current
LEFT JOIN LATERAL (SELECT city_id FROM job_requirement_location l WHERE l.job_requirement_id = r.id ORDER BY l.id LIMIT 1) loc ON true
LEFT JOIN dim_location dl ON dl.city_id = loc.city_id
LEFT JOIN job_role jr ON jr.id = r.job_role_id LEFT JOIN industry i ON i.id = r.industry_id
JOIN employment_type et ON et.id = r.employment_type_id JOIN work_mode wm ON wm.id = r.work_mode_id;

-- ---------------------------------------------------------------- facts
-- fresh statistics first: without them the planner nests loops over the new dimensions
ANALYZE dim_location, dim_organisation, dim_candidate, dim_job_requirement, application, application_status_history, job_requirement;
WITH h AS (
    SELECT application_id,
           min(changed_at) FILTER (WHERE to_application_status_id = 3) AS sl, min(changed_at) FILTER (WHERE to_application_status_id = 5) AS iv,
           min(changed_at) FILTER (WHERE to_application_status_id = 6) AS ofr, min(changed_at) FILTER (WHERE to_application_status_id = 8) AS jn,
           min(changed_at) FILTER (WHERE to_application_status_id = 9) AS rj
    FROM application_status_history GROUP BY application_id)
INSERT INTO fact_application (application_id, dim_job_requirement_id, dim_candidate_id, dim_organisation_id, applied_date_id, shortlisted_date_id,
                              interviewed_date_id, offered_date_id, joined_date_id, rejected_date_id, current_stage_code, application_source_code,
                              days_to_shortlist, days_to_hire)
SELECT a.id, dj.id, dc.id, dorg.id, seed.dk(a.applied_at), seed.dk(h.sl), seed.dk(h.iv), seed.dk(h.ofr), seed.dk(h.jn), seed.dk(h.rj),
       st.code, src.code, floor(extract(epoch FROM h.sl - a.applied_at) / 86400)::int, floor(extract(epoch FROM h.jn - a.applied_at) / 86400)::int
FROM application a
JOIN h ON h.application_id = a.id
JOIN job_requirement r ON r.id = a.job_requirement_id
JOIN dim_job_requirement dj ON dj.job_requirement_id = a.job_requirement_id
JOIN dim_candidate dc ON dc.candidate_profile_id = a.candidate_profile_id AND tstzrange(dc.valid_from, dc.valid_to) @> a.applied_at
JOIN dim_organisation dorg ON dorg.organisation_id = r.organisation_id AND tstzrange(dorg.valid_from, dorg.valid_to) @> a.applied_at
JOIN application_status st ON st.id = a.application_status_id JOIN application_source src ON src.id = a.application_source_id;

WITH pl AS (SELECT job_requirement_id, count(*) AS filled, max(joined_on) AS last_join FROM placement GROUP BY 1),
     ac AS (SELECT job_requirement_id, count(*) AS n FROM application GROUP BY 1)
INSERT INTO fact_job_posting (job_requirement_id, dim_job_requirement_id, dim_organisation_id, posted_date_id, published_date_id, filled_date_id, closed_date_id,
                              positions_opened, positions_filled, application_count, days_to_fill)
SELECT r.id, dj.id, dorg.id, seed.dk(r.created_at), seed.dk(r.published_at),
       CASE WHEN r.job_requirement_status_id = 6 THEN seed.dk(coalesce(pl.last_join, least(r.expires_at, now())::date)) END,
       CASE WHEN r.job_requirement_status_id IN (5, 6, 7) THEN seed.dk(least(r.expires_at, now())) END,
       r.number_of_positions, least(coalesce(pl.filled, 0), r.number_of_positions), coalesce(ac.n, 0),
       CASE WHEN r.job_requirement_status_id = 6 AND r.published_at IS NOT NULL
            THEN greatest(0, coalesce(pl.last_join, least(r.expires_at, now())::date) - r.published_at::date) END
FROM job_requirement r
JOIN dim_job_requirement dj ON dj.job_requirement_id = r.id
JOIN dim_organisation dorg ON dorg.organisation_id = r.organisation_id AND tstzrange(dorg.valid_from, dorg.valid_to) @> r.created_at
LEFT JOIN pl ON pl.job_requirement_id = r.id LEFT JOIN ac ON ac.job_requirement_id = r.id;

INSERT INTO fact_profile_engagement (engagement_kind, dim_candidate_id, dim_organisation_id, event_date_id, credits_charged)
SELECT 'view', dc.id, dorg.id, seed.dk(v.viewed_at), CASE WHEN v.wallet_ledger_entry_id IS NOT NULL THEN 1 ELSE 0 END
FROM profile_view_event v
JOIN dim_candidate dc ON dc.candidate_profile_id = v.candidate_profile_id AND dc.is_current
LEFT JOIN dim_organisation dorg ON dorg.organisation_id = v.viewer_organisation_id AND tstzrange(dorg.valid_from, dorg.valid_to) @> v.viewed_at
UNION ALL
SELECT 'download', dc.id, dorg.id, seed.dk(d.downloaded_at), CASE WHEN d.wallet_ledger_entry_id IS NOT NULL THEN 1 ELSE 0 END
FROM profile_download_event d
JOIN dim_candidate dc ON dc.candidate_profile_id = d.candidate_profile_id AND dc.is_current
LEFT JOIN dim_organisation dorg ON dorg.organisation_id = d.downloader_organisation_id AND tstzrange(dorg.valid_from, dorg.valid_to) @> d.downloaded_at;

INSERT INTO fact_outreach (outreach_recipient_id, dim_candidate_id, dim_organisation_id, sent_date_id, channel_code, is_delivered, is_responded, is_via_consultant)
SELECT r.id, dc.id, dorg.id, seed.dk(r.sent_at), ch.code, r.delivered_at IS NOT NULL, r.responded_at IS NOT NULL, b.sourcing_request_id IS NOT NULL
FROM outreach_recipient r JOIN outreach_batch b ON b.id = r.outreach_batch_id JOIN outreach_channel ch ON ch.id = b.outreach_channel_id
JOIN dim_candidate dc ON dc.candidate_profile_id = r.candidate_profile_id AND dc.is_current
LEFT JOIN job_requirement j ON j.id = b.job_requirement_id
LEFT JOIN dim_organisation dorg ON dorg.organisation_id = coalesce(b.organisation_id, j.organisation_id) AND dorg.is_current;

INSERT INTO fact_sourcing_request (sourcing_request_id, dim_job_requirement_id, requested_date_id, decided_date_id, outcome_code, hours_to_decision)
SELECT s.id, dj.id, seed.dk(s.requested_at), seed.dk(s.decided_at), st.code, round(extract(epoch FROM s.decided_at - s.requested_at) / 3600, 2)
FROM sourcing_request s JOIN dim_job_requirement dj ON dj.job_requirement_id = s.job_requirement_id
JOIN sourcing_request_status st ON st.id = s.sourcing_request_status_id;

INSERT INTO fact_payment (payment_order_id, dim_organisation_id, paid_date_id, purpose_code, paid_amount, refunded_amount, amount_currency_id, credits_purchased)
SELECT o.id, dorg.id, seed.dk(o.paid_at), pp.code, o.order_amount,
       coalesce((SELECT sum(f.refund_amount) FROM refund f WHERE f.payment_order_id = o.id AND f.refund_status_id = 3), 0),
       o.order_currency_id, coalesce(o.credit_quantity, 0)
FROM payment_order o JOIN payment_purpose pp ON pp.id = o.payment_purpose_id
JOIN dim_organisation dorg ON dorg.organisation_id = o.organisation_id AND tstzrange(dorg.valid_from, dorg.valid_to) @> o.paid_at
WHERE o.payment_order_status_id IN (3, 6, 7);

INSERT INTO fact_wallet_transaction (wallet_ledger_entry_id, dim_organisation_id, entry_date_id, entry_type_code, credit_delta)
SELECT e.id, dorg.id, seed.dk(e.occurred_at), t.code, e.credit_delta
FROM wallet_ledger_entry e JOIN wallet w ON w.id = e.wallet_id JOIN wallet_entry_type t ON t.id = e.wallet_entry_type_id
JOIN dim_organisation dorg ON dorg.organisation_id = w.organisation_id AND tstzrange(dorg.valid_from, dorg.valid_to) @> e.occurred_at;

INSERT INTO fact_gig_assignment (gig_assignment_id, dim_organisation_id, dim_location_id, window_start_date_id, completed_date_id, assignment_status_code,
                                 price_amount, earning_amount, amount_currency_id, rating_score)
SELECT s.id, dorg.id, dl.id, seed.dk(s.window_start_at), seed.dk(s.completed_at), st.code, q.price_amount,
       coalesce((SELECT max(e.earning_amount) FROM gig_earning_snapshot e WHERE e.gig_assignment_id = s.id AND e.gig_earning_type_id = 2), 0),
       q.price_currency_id, gr.rating_score
FROM gig_assignment s JOIN gig_application a ON a.id = s.gig_application_id JOIN gig_request q ON q.id = a.gig_request_id
JOIN gig_assignment_status st ON st.id = s.gig_assignment_status_id
LEFT JOIN dim_organisation dorg ON dorg.organisation_id = q.requester_organisation_id AND dorg.is_current
LEFT JOIN dim_location dl ON dl.city_id = q.city_id LEFT JOIN gig_rating gr ON gr.gig_assignment_id = s.id;

INSERT INTO fact_login_daily (event_date_id, dim_organisation_id, login_outcome_code, attempt_count, distinct_user_count)
SELECT seed.dk(la.attempted_at), dorg.id, lo.code, count(*), count(DISTINCT la.user_account_id)
FROM login_attempt la JOIN login_outcome lo ON lo.id = la.login_outcome_id
LEFT JOIN LATERAL (SELECT l.organisation_id FROM licence_seat s JOIN licence l ON l.id = s.licence_id
                   WHERE s.user_account_id = la.user_account_id ORDER BY s.id LIMIT 1) org ON true
LEFT JOIN dim_organisation dorg ON dorg.organisation_id = org.organisation_id AND dorg.is_current
GROUP BY 1, 2, 3;

INSERT INTO fact_notification_daily (event_date_id, notification_type_code, channel_code, delivery_status_code, delivery_count)
SELECT seed.dk(d.queued_at), nt.code, ch.code, ds.code, count(*)
FROM notification_delivery d JOIN notification n ON n.id = d.notification_id JOIN notification_type nt ON nt.id = n.notification_type_id
JOIN outreach_channel ch ON ch.id = d.outreach_channel_id JOIN notification_delivery_status ds ON ds.id = d.notification_delivery_status_id
GROUP BY 1, 2, 3, 4;

INSERT INTO fact_support_ticket (support_ticket_id, dim_organisation_id, opened_date_id, resolved_date_id, category_code, priority_code, hours_to_resolve)
SELECT t.id, dorg.id, seed.dk(t.opened_at), seed.dk(t.resolved_at), c.code, p.code, round(extract(epoch FROM t.resolved_at - t.opened_at) / 3600, 2)
FROM support_ticket t JOIN support_ticket_category c ON c.id = t.support_ticket_category_id JOIN support_ticket_priority p ON p.id = t.support_ticket_priority_id
LEFT JOIN dim_organisation dorg ON dorg.organisation_id = t.organisation_id AND dorg.is_current;

CALL refresh_aggregates();

DO $$
BEGIN
    PERFORM seed.done('analytics: dimensions', (SELECT count(*) FROM dim_location) + (SELECT count(*) FROM dim_organisation)
        + (SELECT count(*) FROM dim_candidate) + (SELECT count(*) FROM dim_job_requirement));
    PERFORM seed.done('analytics: organisation versions (SCD 2)', (SELECT count(*) FROM dim_organisation WHERE NOT is_current));
    PERFORM seed.done('analytics: fact_application', (SELECT count(*) FROM fact_application));
    PERFORM seed.done('analytics: other facts', (SELECT count(*) FROM fact_job_posting) + (SELECT count(*) FROM fact_profile_engagement)
        + (SELECT count(*) FROM fact_outreach) + (SELECT count(*) FROM fact_sourcing_request) + (SELECT count(*) FROM fact_payment)
        + (SELECT count(*) FROM fact_wallet_transaction) + (SELECT count(*) FROM fact_gig_assignment) + (SELECT count(*) FROM fact_login_daily)
        + (SELECT count(*) FROM fact_notification_daily) + (SELECT count(*) FROM fact_support_ticket));
    PERFORM seed.done('analytics: aggregates refreshed', (SELECT count(*) FROM agg_refresh_log));
END $$;
