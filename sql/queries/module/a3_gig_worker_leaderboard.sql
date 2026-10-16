-- A3 Gig marketplace (B67): top gig workers by completed gigs, with average rating and reconciled earnings.
SELECT w.display_name, count(*) AS completed_gigs, round(avg(g.rating_score), 2) AS avg_rating,
       sum(e.earning_amount) AS earnings_inr
FROM gig_assignment s
JOIN gig_worker_profile w ON w.id = s.gig_worker_profile_id
LEFT JOIN gig_rating g ON g.gig_assignment_id = s.id
LEFT JOIN gig_earning_snapshot e ON e.gig_assignment_id = s.id AND e.gig_earning_type_id = 2
WHERE s.gig_assignment_status_id = 3
GROUP BY w.id, w.display_name
ORDER BY completed_gigs DESC, avg_rating DESC NULLS LAST
LIMIT 10;
